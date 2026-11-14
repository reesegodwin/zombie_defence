# Hair, grown: locks are combed out from roots scattered over the scalp (or
# jaw, or brow), each following its style and gravity and lying over the
# head, shoulders and clothes; each lock is then a narrow card of mesh,
# textured with fine strands (cut out where there's no hair).
import os
import zlib

import bpy
import numpy as np
from mathutils import Vector, kdtree
from PIL import Image

import paint
import parts


def _unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def _roots(ob, faces, n, rng):
    """n points scattered evenly over some of an object's faces: (points, normals)."""
    me = ob.data
    co = parts.coords(ob)
    tris, norms = [], []
    for f in faces:
        p = me.polygons[f]
        v = list(p.vertices)
        for k in range(1, len(v) - 1):
            tris.append((v[0], v[k], v[k + 1]))
            norms.append(tuple(p.normal))
    tris = np.array(tris)
    a, b, c = co[tris[:, 0]], co[tris[:, 1]], co[tris[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1)
    pick = rng.choice(len(tris), size=n, p=area / area.sum())
    u, v = rng.random(n), rng.random(n)
    flip = u + v > 1.0
    u[flip], v[flip] = 1.0 - u[flip], 1.0 - v[flip]
    return a[pick] + (b[pick] - a[pick]) * u[:, None] + (c[pick] - a[pick]) * v[:, None], np.array(norms)[pick]


def _surface(tree, p):
    """For each point: the nearest point of a surface, its normal there, and how far outside it the point is."""
    loc = np.zeros_like(p)
    nor = np.zeros_like(p)
    for i in range(len(p)):
        l, n, _, _ = tree.find_nearest(Vector(p[i]))
        if l is not None:
            loc[i], nor[i] = l, n
    return loc, nor, ((p - loc) * nor).sum(axis=1)


def _keep_out(tree, p, margin, stick=None):
    """Moves points that are inside (or too near) a surface out to margin from
    it, and those in stick onto it at that height; returns the surface's normals there."""
    loc, nor, out = _surface(tree, p)
    move = out < margin
    if stick is not None:
        move |= stick
    p[move] = (loc + nor * np.broadcast_to(margin, out.shape)[:, None])[move]
    return nor


STYLES = {
    # length (metres), segments, card width, how many, lift (how far off the head the outer locks lie)
    "long": dict(length=0.27, segs=9, width=0.014, count=2600, lift=0.016, wave=0.012, mess=0.25),
    "medium": dict(length=0.085, segs=6, width=0.012, count=2400, lift=0.008, wave=0.004, mess=0.22),
    "slick": dict(length=0.1, segs=6, width=0.011, count=2400, lift=0.007, wave=0.002, mess=0.1),
    "bob": dict(length=0.21, segs=8, width=0.014, count=2000, lift=0.012, wave=0.003, mess=0.06),
    "beard": dict(length=0.028, segs=3, width=0.006, count=2600, lift=0.004, wave=0.004, mess=0.6),
    "short_beard": dict(length=0.014, segs=2, width=0.005, count=2600, lift=0.002, wave=0.002, mess=0.6),
    "brow": dict(length=0.009, segs=2, width=0.003, count=130, lift=0.0005, wave=0.0, mess=0.12),
}


def grow(ctx, name, faces, style, color, over=(), **change):
    """Grows hair of a style from some of the body's faces, lying over the body and the objects named in over."""
    S = dict(STYLES[style], **change)
    rng = np.random.default_rng(zlib.crc32((ctx.name + name).encode()))
    parts.body_fields(ctx)
    body = ctx.objects["Body"]
    tree = parts.surface_of([body] + [ctx.objects[n] for n in over if n in ctx.objects])
    n = S["count"]
    root, nor = _roots(body, faces, n, rng)
    scalp = parts.coords(body)[sorted({v for f in ctx.scalp_faces for v in body.data.polygons[f].vertices})]
    centre = scalp.mean(axis=0)
    crown = scalp[:, 2].max()
    segs = S["segs"]
    length = S["length"] * rng.uniform(0.75, 1.1, n)
    if style == "long":      # all of it ends about the shoulders, wherever on the head it starts
        length = np.clip((root[:, 2] - (ctx.z["neck"] + 0.005)) * 1.3, 0.1, 0.3) * rng.uniform(0.85, 1.08, n)
    elif style == "bob":
        length = np.clip((root[:, 2] - (ctx.z["neck"] + 0.0)) * 1.2, 0.06, 0.26) * rng.uniform(0.9, 1.05, n)
    if style in ("beard", "short_beard"):   # the moustache is kept short of the lips
        length = np.where((root[:, 2] > ctx.mouth[2] + 0.002) & (np.abs(root[:, 0]) < 0.032), length * 0.4, length)
    # A few hundred guides are combed; every lock follows the guide nearest its root.
    guides = max(40, n // 9)
    kd = kdtree.KDTree(guides)
    for i in range(guides):
        kd.insert(root[i], i)
    kd.balance()
    guide_of = np.array([kd.find(p)[1] for p in root])
    g_root, g_nor, g_len = root[:guides], nor[:guides], length[:guides]
    down = np.array([0.0, 0.0, -1.0])
    back = np.array([0.0, 1.0, 0.0])
    side = np.sign(g_root[:, 0] + 0.008)[:, None] * np.array([1.0, 0.0, 0.0])
    radial = _unit((g_root - centre) * np.array([1.0, 1.0, 0.0]))
    front = parts._step(-(g_root[:, 1] - centre[1]), 0.03, 0.085)[:, None]      # how far forward on the head the lock starts
    eye = ctx.human.joint("joint-l-eye")
    phase = rng.uniform(0.0, 6.28, guides)
    base = 0.002 + 0.6 * S["lift"] * rng.random(guides)                           # how high off the head each lock lies
    path = [g_root.copy()]
    d = g_nor.copy()
    p = g_root.copy()
    for s in range(1, segs + 1):
        t = s / segs
        _, n_s, _ = _surface(tree, p)
        stick = np.ones(guides, dtype=bool)
        margin = base * min(1.0, t * 3.0)
        if style in ("long", "bob"):       # over the head it lies on it; below the ears it hangs free
            # Combed from a parting down each side of the head, and straight down the back.
            comb = -np.sign(g_root[:, 0] + 0.008)[:, None] * np.cross(n_s, back)
            flat = 1.0 - np.linalg.norm(comb, axis=1, keepdims=True)
            want = comb + down * 0.6 + back * 0.15 + side * front * 0.8 * flat
            stick = p[:, 2] > centre[2] - (0.03 if style == "long" else 0.045)
            if style == "bob":
                want = want - radial * 0.25 * t
        elif style == "medium":
            want = down + radial * 0.35 + back * 0.3 + side * 1.1 * front
            margin = margin + S["lift"] * 0.8 * t * t
        elif style == "slick":             # combed straight back over the head
            top = np.array([0.0, centre[1] + 0.02, crown]) - p             # up over the brow to the crown, then on down the back
            before = parts._step(top[:, 1], 0.0, 0.03)[:, None]
            want = _unit(top) * before + (back + down * 0.7) * (1.0 - before)
            margin = margin + S["lift"] * (0.6 * t * t + 0.8 * front[:, 0] * np.sin(t * 3.14))
        elif style in ("beard", "short_beard"):
            want = down + n_s * 0.25
            margin = 0.0015 + S["lift"] * 2.5 * t * rng.uniform(0.5, 1.0, guides)
        else:                              # brows: out along the brow, lying flat
            want = side + np.array([0.0, 0.0, 0.22])
        want = _unit(want) + rng.normal(0.0, S["mess"] * 0.3, (guides, 3))
        lying = stick[:, None]
        want = np.where(lying, want - n_s * (want * n_s).sum(axis=1, keepdims=True), want)
        d = _unit(d * 0.3 + _unit(want) * 0.7)
        p = p + d * (g_len / segs)[:, None] + np.cross(n_s, d) * (np.sin(phase + t * 8.0) * S["wave"] * t)[:, None]
        if style in ("long", "bob", "medium"):     # never across the face: it parts round it
            face = (p[:, 1] < centre[1] - 0.03) & (p[:, 2] < eye[2] + 0.028) & (np.abs(p[:, 0]) < 0.07)
            sign = np.where(g_root[:, 0] >= -0.008, 1.0, -1.0)
            p[face, 0] = (p[:, 0] + sign * np.minimum(0.07 - p[:, 0] * sign, 0.02))[face]
            p[face, 1] += 0.008
        _keep_out(tree, p, margin, stick)
        path.append(p.copy())
    path = np.array(path)                                   # (segs + 1, guides, 3)
    # The locks: each its guide's path, starting at its own root and drawing in to the guide's tip.
    t = np.linspace(0.0, 1.0, segs + 1)[:, None, None]
    offset = (root - g_root[guide_of])[None]
    scale = (length / g_len[guide_of])[None, :, None]
    pts = g_root[guide_of][None] + (path[:, guide_of] - g_root[guide_of][None]) * scale + offset * (1.0 - 0.55 * t)
    pts += rng.normal(0.0, S["mess"] * 0.004, pts.shape) * t
    lift = 0.0015 + S["lift"] * rng.random(n)
    outward = np.zeros_like(pts)
    for s in range(segs + 1):
        if style in ("long", "bob", "medium") and s > 0:
            face = (pts[s][:, 1] < centre[1] - 0.03) & (pts[s][:, 2] < eye[2] + 0.028) & (np.abs(pts[s][:, 0]) < 0.07)
            pts[s][face, 0] = np.where(root[face, 0] >= -0.008, 0.07, -0.07)
        outward[s] = _keep_out(tree, pts[s], lift * (0.3 + 0.7 * min(1.0, s / 2.0)))
    # Cards: a strip along each lock, flat to the head, narrowing to the tip.
    tangent = _unit(np.gradient(pts, axis=0))
    across = _unit(np.cross(tangent, outward) + 1e-9)
    width = S["width"] * rng.uniform(0.7, 1.2, n)[None, :, None] * (1.0 - 0.55 * t ** 2)
    left, right = pts - across * width * 0.5, pts + across * width * 0.5
    verts = np.concatenate([left, right], axis=0).transpose(1, 0, 2).reshape(-1, 3)      # per lock: lefts then rights
    per = 2 * (segs + 1)
    faces_out, uvs = [], []
    column = rng.integers(0, 4, n)
    for i in range(n):
        b = i * per
        u0, u1 = column[i] * 0.25 + 0.01, column[i] * 0.25 + 0.24
        for s in range(segs):
            faces_out.append([b + s, b + segs + 1 + s, b + segs + 2 + s, b + s + 1])
            v0, v1 = 1.0 - s / segs, 1.0 - (s + 1) / segs
            uvs.append([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
    ob = parts.new_object(ctx, name, verts, faces_out, uvs)
    # Lit as the head under it is, not as a thousand little flat strips.
    normal = _unit(outward * 0.85 + np.cross(across, tangent) * 0.15)
    normal = np.concatenate([normal, normal], axis=0).transpose(1, 0, 2).reshape(-1, 3)
    ob.data.normals_split_custom_set_from_vertices([tuple(x) for x in normal])
    parts.bind(ctx, ob)
    ob.data.materials.append(_material(ctx, color))
    ctx.materials[name] = {"kind": "hair"}
    return ob


def _material(ctx, color):
    """The locks' material: their shared grey texture, tinted the hair's colour.
    (The tint doesn't travel in the exported model: the game tints the texture
    itself, to each survivor's own hair colour. See survivor_model.gd.)"""
    key = "Hair %.2f %.2f %.2f" % tuple(color)
    if key in bpy.data.materials:
        return bpy.data.materials[key]
    path = os.path.join(ctx.out, "textures", "%s_hair.png" % ctx.name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _card().save(path)
    img = bpy.data.images.load(path, check_existing=True)
    img.pack()
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.55
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tint = nt.nodes.new("ShaderNodeMixRGB")
    tint.blend_type = "MULTIPLY"
    tint.inputs["Fac"].default_value = 1.0
    tint.inputs["Color2"].default_value = (*paint.to_linear(tuple(min(1.0, c * 1.5) for c in color)), 1.0)
    cut = nt.nodes.new("ShaderNodeMath")
    cut.operation = "ROUND"
    nt.links.new(tex.outputs["Color"], tint.inputs["Color1"])
    nt.links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], cut.inputs[0])
    nt.links.new(cut.outputs[0], bsdf.inputs["Alpha"])
    m.use_backface_culling = False
    m.blend_method = "CLIP"
    return m


def _card(w=256, h=512, seed=4):
    """The texture every lock shares: four columns of fine strands, root at the
    top, thinning out to wisps at the tip; grey, to be tinted the hair's colour."""
    rng = np.random.default_rng(seed)
    shade = np.zeros((h, w))
    alpha = np.zeros((h, w))
    y = np.linspace(0.0, 1.0, h)
    for col in range(4):
        x0 = col * w // 4
        for _ in range(26):
            x = x0 + rng.uniform(3, w // 4 - 3)
            end = rng.uniform(0.55, 1.0)
            thick = rng.uniform(0.8, 2.2)
            bright = rng.uniform(0.55, 1.0)
            drift = rng.normal(0.0, 2.0)
            for row in range(int(end * h)):
                cx = x + drift * (row / h) ** 2 * 3.0 + np.sin(row * 0.02 + x) * 0.8
                t = thick * (1.0 - 0.75 * (row / (end * h)) ** 3)
                a, b = int(max(x0 + 1, cx - t)), int(min(x0 + w // 4 - 1, cx + t + 1))
                alpha[row, a:b] = 1.0
                shade[row, a:b] = np.maximum(shade[row, a:b], bright * (0.75 + 0.25 * y[row]))
    alpha[: h // 14] = np.maximum(alpha[: h // 14], 0.0)
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., :3] = (np.clip(np.where(alpha > 0, shade, 0.6), 0, 1) * 255)[..., None]
    rgba[..., 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")
