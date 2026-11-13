# The dead, modelled in Blender: one continuous body per model in
# scenes/actors/body.gd ZOMBIE_MODELS (tee, sweater, shirtless, vest,
# open_shirt, workshirt, flayed), with what's left of their clothes grown
# from the body's own surface, skinned to the game's skeleton.
#
#   python3 tools/blender/zombies.py [model ...] [--preview]
#
# writes assets/models/zombie_<model>.glb and zombie_<model>_lo.glb (fewer
# points, for the horde far off). The game colours them per zombie, so the
# vertex colour carries what each point is, not its colour:
#   R: the region (REGIONS below, as code / 32), G: ambient occlusion.
# body.gd reads the region to pick the skin, shirt, trouser or boot colour of
# that zombie, its paint (blood, grime, rips) and its surface for the shader.
#
# Coordinates are the game's: y up, the body faces +z, its "l" side at -x.
# The bones are the game's joints (body.gd zombie()), named as there.
import math
import os
import sys

import bpy  # first: it brings bmesh and mathutils with it
import bmesh
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")

# What each point is (body.gd ZONE_* must match).
REGIONS = {
    "skin": 0, "shirt": 1, "trim": 2, "pants": 3, "boot": 4, "sole": 5, "scalp": 6,
    "strand": 7, "teeth": 8, "eye": 9, "mouth": 10, "nail": 11, "button": 12, "pocket": 13,
}

MODELS = {
    "tee": {"top": "tee", "legs": "long", "feet": "boots"},
    "sweater": {"top": "sweater", "legs": "long", "feet": "boots"},
    "shirtless": {"top": "none", "legs": "long", "feet": "odd"},
    "vest": {"top": "vest", "legs": "short", "feet": "bare"},
    "open_shirt": {"top": "open", "legs": "short", "feet": "bare"},
    "workshirt": {"top": "work", "legs": "long", "feet": "boots"},
    "flayed": {"top": "none", "legs": "short", "feet": "bare"},
}

# The game's joints at rest (body.gd zombie(), width 1): name, parent, position.
HIP_H = 0.93
JOINTS = [
    ("Hips", None, (0, HIP_H, 0)),
    ("Spine", None, (0, HIP_H + 0.04, 0)),
    ("Hipl", "Hips", (-0.076, HIP_H - 0.04, 0)),
    ("Kneel", "Hipl", (-0.076, HIP_H - 0.47, 0)),
    ("Hipr", "Hips", (0.076, HIP_H - 0.04, 0)),
    ("Kneer", "Hipr", (0.076, HIP_H - 0.47, 0)),
    ("Neck", "Spine", (0, HIP_H + 0.52, 0)),
    ("Head", "Neck", (0, HIP_H + 0.58, 0.01)),
    ("Shoulderl", "Spine", (-0.172, HIP_H + 0.455, 0)),
    ("Elbowl", "Shoulderl", (-0.172, HIP_H + 0.165, 0)),
    ("Handl", "Elbowl", (-0.172, HIP_H - 0.105, 0)),
    ("Shoulderr", "Spine", (0.172, HIP_H + 0.455, 0)),
    ("Elbowr", "Shoulderr", (0.172, HIP_H + 0.165, 0)),
    ("Handr", "Elbowr", (0.172, HIP_H - 0.105, 0)),
]
JOINT_AT = {n: Vector(p) for n, _, p in JOINTS}
PARENT = {n: p for n, p, _ in JOINTS}

# Capsules for the skin weights: bone -> (from, to, radius). Each point goes
# with the bone it's most inside of, blended with that bone's parent or
# children where it's inside them too (at the joints).
CAPS = {
    "Hips": ((0, 0.80, 0), (0, 1.0, 0), 0.15),
    "Spine": ((0, 1.0, 0), (0, 1.40, 0), 0.14),
    "Neck": ((0, 1.41, -0.005), (0, 1.53, 0.005), 0.06),
    "Head": ((0, 1.54, 0.01), (0, 1.74, 0.0), 0.11),
}
for s, x in (("l", -1), ("r", 1)):
    CAPS["Hip" + s] = ((x * 0.085, 0.86, 0), (x * 0.08, 0.47, 0.01), 0.085)
    CAPS["Knee" + s] = ((x * 0.08, 0.46, 0.01), (x * 0.082, 0.04, 0.06), 0.06)
    CAPS["Shoulder" + s] = ((x * 0.168, 1.385, 0), (x * 0.172, 1.10, 0), 0.05)
    CAPS["Elbow" + s] = ((x * 0.172, 1.09, 0), (x * 0.172, 0.835, 0.003), 0.042)
    CAPS["Hand" + s] = ((x * 0.172, 0.825, 0), (x * 0.168, 0.68, 0.005), 0.05)


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def bump(d, r):
    """1 at d = 0, falling smoothly to 0 at d = r."""
    return smooth(r, 0.0, d)


# --- The body ---------------------------------------------------------------

def _skeleton():
    """The skin modifier's frame: points with radii, joined into a body."""
    pts, rad, edges = [], [], []

    def add(p, r, parent=None):
        pts.append(p)
        rad.append(r)
        if parent is not None:
            edges.append((parent, len(pts) - 1))
        return len(pts) - 1

    pelvis = add((0, 0.90, 0.0), 0.128)
    waist = add((0, 1.02, 0.0), 0.114, pelvis)
    belly = add((0, 1.12, 0.004), 0.118, waist)
    chest = add((0, 1.24, 0.01), 0.13, belly)
    upper = add((0, 1.34, 0.0), 0.12, chest)
    nb = add((0, 1.43, -0.008), 0.062, upper)
    neck = add((0, 1.49, 0.0), 0.052, nb)
    add((0, 1.55, 0.008), 0.048, neck)
    for s in (-1, 1):
        # Shoulder and arm, hanging straight down.
        cl = add((s * 0.095, 1.395, -0.004), 0.055, upper)
        sh = add((s * 0.158, 1.385, 0.0), 0.05, cl)
        ua = add((s * 0.17, 1.25, 0.0), 0.045, sh)
        el = add((s * 0.172, 1.10, -0.004), 0.034, ua)
        fa = add((s * 0.172, 1.0, 0.004), 0.038, el)
        wr = add((s * 0.172, 0.84, 0.0), 0.025, fa)
        palm = add((s * 0.172, 0.79, 0.002), 0.03, wr)
        # Four fingers, curled a little, spread front to back; a thumb.
        for k, (fz, ln) in enumerate(((0.022, 0.92), (0.008, 1.0), (-0.007, 0.96), (-0.021, 0.8))):
            kn = add((s * 0.172, 0.752, fz), 0.0095, palm)
            mid = add((s * (0.172 - 0.004), 0.752 - 0.034 * ln, fz * 1.05), 0.0085, kn)
            add((s * (0.172 - 0.012), 0.752 - 0.062 * ln, fz * 1.05), 0.0072, mid)
        tb = add((s * 0.166, 0.80, 0.026), 0.012, palm)
        tm = add((s * 0.161, 0.778, 0.042), 0.0095, tb)
        add((s * 0.156, 0.758, 0.05), 0.008, tm)
        # Leg and foot.
        hip = add((s * 0.085, 0.84, 0.0), 0.082, pelvis)
        th = add((s * 0.086, 0.69, 0.006), 0.072, hip)
        ak = add((s * 0.083, 0.55, 0.01), 0.055, th)
        kn2 = add((s * 0.08, 0.465, 0.014), 0.045, ak)
        calf = add((s * 0.08, 0.36, -0.008), 0.054, kn2)
        shin = add((s * 0.08, 0.22, 0.0), 0.037, calf)
        ank = add((s * 0.08, 0.085, 0.0), 0.029, shin)
        add((s * 0.08, 0.035, -0.035), 0.03, ank)          # heel
        fm = add((s * 0.082, 0.045, 0.055), 0.034, ank)
        ball = add((s * 0.086, 0.03, 0.125), 0.031, fm)
        add((s * 0.088, 0.024, 0.175), 0.022, ball)
    return pts, rad, edges


def _body_mesh(levels):
    pts, rad, edges = _skeleton()
    me = bpy.data.meshes.new("frame")
    me.from_pydata([Vector(p) for p in pts], edges, [])
    obj = bpy.data.objects.new("frame", me)
    bpy.context.collection.objects.link(obj)
    sk = obj.modifiers.new("skin", "SKIN")
    sk.branch_smoothing = 0.6
    for i, r in enumerate(rad):
        d = me.skin_vertices[0].data[i]
        d.radius = (r, r)
        d.use_root = i == 0
    ss = obj.modifiers.new("sub", "SUBSURF")
    ss.levels = levels
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    bm = bmesh.new()
    bm.from_mesh(ev.to_mesh())
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj)
    return bm


def _shape_body(bm, top):
    """Anatomy pressed into the skin frame: a flat chest and back, hollow
    belly, collarbones, ribs, buttocks, kneecaps, flat feet and hands."""
    for v in bm.verts:
        x, y, z = v.co
        ax = abs(x)
        torso = smooth(0.145, 0.115, ax) * smooth(0.80, 0.86, y) * smooth(1.47, 1.42, y)
        # A torso is wider than it is deep.
        z *= 1.0 - 0.3 * torso
        # Hollow, starved belly; a ribcage standing out above it.
        if z > 0:
            z -= 0.016 * torso * bump(abs(y - 1.08), 0.07) * smooth(0.11, 0.0, ax)
            rib = smooth(1.03, 1.08, y) * smooth(1.32, 1.27, y) * smooth(0.0, 0.03, ax)
            ridge = 0.5 + 0.5 * math.cos(math.tau * (y + ax * 0.3) / 0.043)
            z += 0.0035 * rib * ridge * ridge * torso
            # Collarbones.
            z += 0.006 * torso * bump(abs(y - (1.405 - ax * 0.12)), 0.012) * smooth(0.02, 0.05, ax) * smooth(0.14, 0.11, ax)
            # A flat chest with a little pectoral shelf.
            z += 0.006 * torso * bump(abs(y - 1.3), 0.05) * bump(abs(ax - 0.06), 0.06)
        else:
            # Shoulder blades, and the buttocks below the waist.
            z -= 0.008 * torso * bump(abs(y - 1.3), 0.06) * bump(abs(ax - 0.07), 0.05)
            z -= 0.02 * bump(abs(y - 0.86), 0.08) * bump(abs(ax - 0.07), 0.07)
        # The trapezius rising from the shoulders to the neck.
        if y > 1.36 and ax < 0.16:
            y += 0.022 * smooth(0.15, 0.06, ax) * smooth(1.36, 1.42, y) * smooth(0.03, 0.05, ax)
        # Kneecaps and the backs of the knees.
        leg = smooth(0.03, 0.05, ax) * smooth(0.13, 0.11, ax)
        if y < 0.6:
            if z > 0.01:
                z += 0.008 * leg * bump(abs(y - 0.47), 0.03)
            # Calf muscle, behind.
            if z < -0.01:
                z -= 0.006 * leg * bump(abs(y - 0.37), 0.08)
        # Flat feet with soles on the ground; a flat palm.
        if y < 0.07:
            y = max(0.0, 0.01 + (y - 0.01) * 0.75)
        hand = smooth(0.85, 0.82, y) * smooth(0.14, 0.16, ax) * smooth(0.6, 0.7, y)
        if hand > 0:
            cx = 0.172 if x > 0 else -0.172
            x = cx + (x - cx) * (1.0 - 0.45 * hand * smooth(0.758, 0.775, y))
        v.co = Vector((x, y, z))


def _head(bm, segs, rings):
    """The skull with dead skin pulled tight over it: sunken eye sockets, a
    brow, a thin nose, cheekbones over hollow cheeks and a slack open mouth."""
    C = Vector((0, 1.635, 0.008))
    res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
    verts = res["verts"]
    mouth = []
    for v in verts:
        u = v.co.copy()
        q = Vector((u.x * 0.077, u.y * 0.116, u.z * 0.1))
        if q.y < 0:   # the jaw narrows; the back of the skull gives way to the neck
            k = smooth(0.0, -0.11, q.y)
            q.x *= 1 - 0.24 * k
            if q.z < 0:
                q.z *= 1 - 0.4 * k
        if q.z > 0:
            q.z *= 0.92
        elif q.y > 0:
            q.z *= 1.07
        ax = abs(q.x)
        if q.z > 0.02:
            # Eye sockets, brow, temples.
            d = math.hypot(ax - 0.032, (q.y - 0.005) * 1.2)
            q.z -= 0.011 * bump(d, 0.024)
            q.z += 0.005 * bump(math.hypot((ax - 0.03) * 0.6, (q.y - 0.026) * 2.2), 0.02)
            # The nose: a thin ridge to a tip, nostrils either side.
            t = smooth(0.006, -0.04, q.y)
            nose = bump(ax, 0.014 - 0.004 * (1 - t)) * smooth(-0.052, -0.04, q.y)
            q.z += nose * (0.003 + 0.02 * t)
            q.z += 0.004 * bump(math.hypot(ax - 0.01, q.y + 0.042), 0.007)
            # Cheekbones, and the hollow under them.
            q.x += math.copysign(0.005, q.x) * bump(math.hypot(ax - 0.05, q.y + 0.012), 0.02)
            hollow = bump(math.hypot(ax - 0.044, (q.y + 0.05) * 0.8), 0.022)
            q.z -= 0.006 * hollow
            q.x -= math.copysign(0.004, q.x) * hollow
            # The mouth hanging open, and the lips round it.
            g = math.hypot(q.x / 0.0225, (q.y + 0.066) / 0.0105)
            q.z -= 0.024 * smooth(1.25, 0.55, g)
            q.z += 0.003 * bump(abs(g - 1.15), 0.3)
            if g < 0.85:
                mouth.append(v)
            # A bony chin.
            q.z += 0.006 * bump(math.hypot(ax, q.y + 0.1), 0.02)
        v.co = C + q
    for v in mouth:
        v[bm.verts.layers.int["region"]] = REGIONS["mouth"]
    # Scalp: everything above the hairline round the top and back.
    reg = bm.verts.layers.int["region"]
    for v in verts:
        q = v.co - C
        f = max(0.0, min(1.0, q.z / 0.1 * 0.5 + 0.5))
        line = -0.055 + (0.066 + 0.055) * f ** 2.4 - abs(q.x) * 0.22 * f
        if q.y > line and v[reg] == 0:
            v[reg] = REGIONS["scalp"]
    return verts


def _small(bm, kind, at, size, region, rot=(0, 0, 0), segs=10, rings=6):
    """A little part (eye, ear, tooth, button) added to the mesh."""
    m = Matrix.Translation(at) @ (Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Rotation(rot[2], 4, "Z")) @ Matrix.Diagonal((*size, 1))
    if kind == "ball":
        res = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0, matrix=m)
    else:
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    reg = bm.verts.layers.int["region"]
    for v in res["verts"]:
        v[reg] = REGIONS[region]
    return res["verts"]


# --- Skin weights -------------------------------------------------------------

def _seg_dist(p, a, b):
    a, b = Vector(a), Vector(b)
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def _inside(p):
    return {b: _seg_dist(p, c[0], c[1]) / c[2] for b, c in CAPS.items()}


def _owners(bm):
    """Which bone each point belongs to, found by walking over the surface
    from points plainly inside one bone: a hand hanging by a thigh is close
    to it in space but far from it over the skin, so it can't claim it."""
    import heapq
    bm.verts.ensure_lookup_table()
    own = [None] * len(bm.verts)
    dist = [1e9] * len(bm.verts)
    heap = []
    for v in bm.verts:
        ins = _inside(v.co)
        order = sorted(ins, key=ins.get)
        if ins[order[0]] < 1.1 and ins[order[1]] > ins[order[0]] + 0.45:
            own[v.index] = order[0]
            dist[v.index] = 0.0
            heap.append((0.0, v.index))
    heapq.heapify(heap)
    while heap:
        d, i = heapq.heappop(heap)
        if d > dist[i]:
            continue
        v = bm.verts[i]
        for e in v.link_edges:
            o = e.other_vert(v)
            nd = d + e.calc_length()
            if nd < dist[o.index]:
                dist[o.index] = nd
                own[o.index] = own[i]
                heapq.heappush(heap, (nd, o.index))
    for v in bm.verts:   # any island no seed reached: nearest bone
        if own[v.index] is None:
            ins = _inside(v.co)
            own[v.index] = min(ins, key=ins.get)
    return own


def _weights(p, owner):
    """{bone: weight} for a point of the body at rest that belongs to owner:
    shared with owner's parent or children where it's inside them too."""
    ins = _inside(p)
    near = {owner} | {b for b in CAPS if PARENT.get(b) == owner or PARENT.get(owner) == b}
    if owner in ("Shoulderl", "Shoulderr"):
        near.add("Spine")
    if owner in ("Hipl", "Hipr"):
        near.add("Hips")
    if owner == "Neck":
        near.add("Spine")
    w = {}
    for b in near:
        e = ins[b] - ins[owner]
        if e < 0.35:
            w[b] = math.exp(-max(e, 0.0) / 0.08)
    if owner in ("Hips", "Spine") and abs(p.x) < 0.15:   # the hips and the spine share the waist
        t = smooth(0.94, 1.04, p.y)
        w = {"Hips": 1 - t, "Spine": t}
    tot = sum(w.values())
    out = sorted(((b, x / tot) for b, x in w.items()), key=lambda i: -i[1])[:4]
    tot = sum(x for _, x in out)
    return {b: x / tot for b, x in out}


LEG_BONES = ("Hips", "Hipl", "Hipr", "Kneel", "Kneer")
ARM_BONES = ("Shoulderl", "Shoulderr", "Elbowl", "Elbowr", "Handl", "Handr")


# --- Clothes ------------------------------------------------------------------

def _hem(co, y0, amp=0.025, seed=0.0):
    """A ragged edge height near y0 at this point."""
    n = noise.noise(Vector((co.x * 22 + seed, co.z * 22, seed * 3.1)))
    n2 = noise.noise(Vector((co.x * 60 + seed, co.z * 60, 7.0)))
    return y0 + amp * n + amp * 0.4 * n2


_LO = {"on": False}   # building the light body for the horde far off


def _cloth(bm, pred, region, offset, loose=None, thick=0.0035, seed=0.0, cover=None, edge=None):
    """A layer of cloth over the faces where pred(centre) holds: copied off
    the body (so it bends with it), pushed out, wrinkled and thickened.
    cover(centre): body faces safely under it are taken away. edge(point,
    bone): the height its open edge should run at there (its hem, cuff or
    neckline), so the edge follows that line, not the steps of the faces."""
    bl = bm.verts.layers.int["bone"]
    names = [n for n, _, _ in JOINTS]
    faces = [f for f in bm.faces if f[bm.faces.layers.int["layer"]] == 0 and pred(f.calc_center_median(), names[f.verts[0][bl]])]
    if not faces:
        return
    if cover is not None:
        hidden = [f for f in faces if cover(f.calc_center_median(), names[f.verts[0][bl]])]
    dup = bmesh.ops.duplicate(bm, geom=faces)
    new_faces = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
    new_verts = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
    lay = bm.faces.layers.int["layer"]
    reg = bm.verts.layers.int["region"]
    if edge is not None:
        for v in new_verts:
            if v.is_boundary:
                y = edge(v.co, names[v[bl]])
                if y is not None:
                    v.co.y += max(-0.02, min(0.02, y - v.co.y))
    bm.normal_update()
    for v in new_verts:
        n = v.normal
        o = offset + (loose(v.co) if loose else 0.0)
        o += 0.003 * noise.noise(v.co * 40 + Vector((seed, 0, 0)))
        v.co = v.co + n * o
        v[reg] = region
    for f in new_faces:
        f[lay] = 1
    if thick > 0 and not _LO["on"]:   # far off, nobody sees how thick the cloth is
        res = bmesh.ops.solidify(bm, geom=new_faces, thickness=thick)
        for g in res["geom"]:
            if isinstance(g, bmesh.types.BMFace):
                g[lay] = 1
            elif isinstance(g, bmesh.types.BMVert):
                g[reg] = region
    if cover is not None and hidden:
        bmesh.ops.delete(bm, geom=hidden, context="FACES")


def _dress(bm, top, legs, feet, seed):
    R = REGIONS
    # Trousers: long ones to the ankle, short ones torn off above the knee.
    if legs != "none":
        low = 0.12 if legs == "long" else 0.58
        amp = 0.012 if legs == "long" else 0.035

        def trousers(c, b):
            return b in LEG_BONES and c.y < 1.0 and c.y > _hem(c, low, amp, seed + 1)

        def under(c, b):
            return b in LEG_BONES and c.y < 0.97 and c.y > low + 0.06

        def trouser_edge(c, b):
            return _hem(c, low, amp, seed + 1) if c.y < 0.8 else None

        _cloth(bm, trousers, R["pants"], 0.006, lambda c: 0.004 * smooth(0.5, 0.2, c.y) + 0.003 * smooth(0.9, 0.98, c.y), seed=seed + 1, cover=under, edge=trouser_edge)
    # Shirts.
    if top in ("tee", "sweater", "work", "open", "vest"):
        sleeve = {"tee": 1.22, "open": 1.2, "sweater": 0.86, "work": 0.86, "vest": 9.0}[top]
        hem = 0.9 if top != "vest" else 0.94

        def neckline(c):
            front = c.z > 0
            if top in ("vest", "open"):
                return 1.44 - (0.075 * smooth(0.075, 0.0, abs(c.x)) if front else 0.0)
            # A round neck: dipping a little at the front, rising to the shoulders.
            return 1.445 - (0.025 * smooth(0.09, 0.0, abs(c.x)) if front else 0.0) + 0.05 * smooth(0.07, 0.12, abs(c.x))

        def shirt(c, b):
            if b in ("Head", "Neck") or (c.y > neckline(c) and abs(c.x) < 0.12):
                return False
            if b in ARM_BONES:   # the arms: sleeves, or arm holes in a vest
                if top == "vest":
                    return abs(c.x) < 0.15 and c.y > 1.2
                return b != "Handl" and b != "Handr" and c.y > _hem(c, sleeve, 0.012 if sleeve < 1 else 0.02, seed + 2)
            return b in ("Spine", "Hips") and c.y > _hem(c, hem, 0.03, seed + 3)

        def under_shirt(c, b):
            if top == "open" and c.z > 0 and abs(c.x) < 0.06:
                return False
            if b in ARM_BONES:
                return top != "vest" and b.startswith("Shoulder") and c.y > sleeve + 0.05 and c.y < 1.34
            return b in ("Spine", "Hips") and abs(c.x) < 0.125 and c.y > hem + 0.06 and c.y < 1.36

        def loose(c):
            torso = smooth(0.13, 0.1, abs(c.x))
            return torso * (0.004 + 0.012 * smooth(1.2, 0.95, c.y)) * (1.0 if c.z > -0.02 else 0.6)

        def shirt_edge(c, b):
            if b in ("Spine", "Neck") and c.y > 1.3 and abs(c.x) < 0.12:
                return neckline(c)
            if b in ARM_BONES and top != "vest" and c.y < 1.3:
                return _hem(c, sleeve, 0.012 if sleeve < 1 else 0.02, seed + 2)
            if b in ("Spine", "Hips") and c.y < 1.05:
                return _hem(c, hem, 0.03, seed + 3)
            return None

        _cloth(bm, shirt, R["shirt"], 0.006, loose, seed=seed + 2, cover=under_shirt, edge=shirt_edge)
        reg = bm.verts.layers.int["region"]
        lay = bm.faces.layers.int["layer"]
        # The neckband or collar, a work shirt's placket and pockets.
        for v in bm.verts:
            if v[reg] != R["shirt"]:
                continue
            c = v.co
            if top in ("sweater", "work", "open") and c.y > neckline(c) - 0.018 and abs(c.x) < 0.11:
                v[reg] = R["trim"]
                if top in ("work", "open"):
                    v.co = c + Vector((0, 0.004, -0.003 if c.z < 0 else 0.004))
            if top == "sweater" and abs(c.x) > 0.13 and c.y < sleeve + 0.03:
                v[reg] = R["trim"]
            if top == "work" and c.z > 0.05 and abs(c.x) < 0.011 and c.y > hem + 0.02:
                v[reg] = R["trim"]
            if top == "work" and c.z > 0.05 and 1.24 < c.y < 1.31 and 0.045 < abs(c.x) < 0.105:
                v[reg] = R["pocket"]
                v.co = c + Vector((0, 0, 0.002))
        if top == "work":
            for k in range(5):
                y = 1.33 - k * 0.085
                _small(bm, "ball", Vector((0.0, y, 0.0)), (0.005, 0.005, 0.002), "button", segs=6, rings=4)
    # Boots.
    sides = {"boots": (-1, 1), "odd": (1,), "bare": ()}[feet]
    for s in sides:
        def boot(c, b, s=s):
            return b == ("Kneer" if s > 0 else "Kneel") and c.y < _hem(c, 0.25, 0.01, seed + 5 + s)

        def in_boot(c, b, s=s):
            return b == ("Kneer" if s > 0 else "Kneel") and c.y < 0.2

        _cloth(bm, boot, R["boot"], 0.008, lambda c: 0.006 * smooth(0.06, 0.0, c.y) + 0.006 * smooth(0.12, 0.2, c.z), thick=0.004, seed=seed + 5, cover=in_boot,
               edge=lambda c, b, s=s: _hem(c, 0.25, 0.01, seed + 5 + s) if c.y > 0.15 else None)
        reg = bm.verts.layers.int["region"]
        for v in bm.verts:
            if v[reg] == R["boot"] and v.co.y < 0.018 and v.co.x * s > 0.03:
                v[reg] = R["sole"]
                v.co.y = min(v.co.y, 0.0)


# --- One whole zombie -------------------------------------------------------------

def build(model, hi=True):
    M = MODELS[model]
    seed = float(sum(map(ord, model)) % 50)
    _LO["on"] = not hi
    bm = _body_mesh(2 if hi else 1)
    reg = bm.verts.layers.int.new("region")
    lay = bm.faces.layers.int.new("layer")
    _shape_body(bm, M["top"])
    _head(bm, 36 if hi else 14, 26 if hi else 9)
    # Fingernails and toenails.
    for v in bm.verts:
        c = v.co
        if c.y < 0.703 and abs(c.x) > 0.14:
            s = 1 if c.x > 0 else -1
            if (c.x - s * 0.16) * s > 0.002:   # just the backs of the fingertips
                v[reg] = REGIONS["nail"]
        if M["feet"] != "boots" and c.y > 0.012 and c.z > 0.16:
            v[reg] = REGIONS["nail"] if (M["feet"] == "bare" or c.x < 0) else v[reg]
    # Weights for the body and head, before the clothes are copied off it.
    bm.verts.ensure_lookup_table()
    dl = bm.verts.layers.deform.verify()
    bones = [n for n, _, _ in JOINTS]
    own = _owners(bm)
    bl = bm.verts.layers.int.new("bone")
    for v in bm.verts:
        v[bl] = bones.index(own[v.index])
        for b, w in _weights(v.co, own[v.index]).items():
            v[dl][bones.index(b)] = w
    _dress(bm, M["top"], M["legs"], M["feet"], seed)
    # The face's small parts: eyes in their sockets, teeth, ears; all go with the head.
    C = Vector((0, 1.635, 0.008))
    parts = []
    for s in (-1, 1):
        parts += _small(bm, "ball", C + Vector((s * 0.032, 0.004, 0.0625)), (0.0115, 0.0115, 0.0115), "eye", segs=12 if hi else 8, rings=8 if hi else 5)
        parts += _small(bm, "ball", C + Vector((s * 0.077, -0.004, -0.012)), (0.009, 0.03, 0.019), "skin", rot=(0.12, s * 0.35, 0), segs=10, rings=6)
    rnd = noise.random
    noise.seed_set(int(seed) + 11)
    for k in range(8):
        tx = (k - 3.5) * 0.0054
        if rnd() > 0.12:
            parts += _small(bm, "cube", C + Vector((tx, -0.0585, 0.07 - tx * tx * 12.0)), (0.0042, 0.006 * (0.85 + rnd() * 0.3), 0.003), "teeth")
        if 0 < k < 7 and rnd() > 0.12:
            parts += _small(bm, "cube", C + Vector((tx * 0.9, -0.0735, 0.067 - tx * tx * 12.0)), (0.0038, 0.005, 0.003), "teeth")
    # Lank hair: flat clumps from the scalp, hanging round the sides and back
    # and swaying a little, thinning to their ends.
    n_strands = 34 if hi else 10
    steps = 7 if hi else 4
    for k in range(n_strands):
        a = 0.6 + (math.tau - 1.2) * (k + rnd()) / n_strands
        ln = 0.1 + rnd() * 0.13
        y0 = 0.035 + rnd() * 0.045
        ring_r = math.sqrt(max(0.0, 1 - (y0 / 0.116) ** 2))
        start = C + Vector((math.sin(a) * 0.077 * ring_r, y0, math.cos(a) * (0.094 if math.cos(a) > 0 else 0.106) * ring_r))
        out = Vector((math.sin(a), 0, math.cos(a)))
        side = Vector((math.cos(a), 0, -math.sin(a)))
        sway = (rnd() - 0.5) * 0.03
        width = 0.004 + rnd() * 0.004
        row = []
        for i in range(steps + 1):
            t = i / steps
            # Over the skull first, then hanging free.
            bulge = 0.004 + 0.012 * min(1.0, t * 2.2) ** 1.2
            p = start + Vector((0, -ln * t, 0)) + out * bulge + side * sway * t * t
            half = width * (1 - 0.7 * t)
            vs = [bm.verts.new(p + side * half), bm.verts.new(p - side * half), bm.verts.new(p - out * 0.002)]
            for v in vs:
                v[reg] = REGIONS["strand"]
                parts.append(v)
            if row:
                for j in range(3):
                    bm.faces.new((row[j], row[(j + 1) % 3], vs[(j + 1) % 3], vs[j]))
            row = vs
    hi_bone = bones.index("Head")
    for v in parts:
        if v.is_valid:
            v[dl].clear()
            v[dl][hi_bone] = 1.0
    for v in bm.verts:   # buttons go with the chest
        if v[reg] == REGIONS["button"]:
            v[dl].clear()
            v[dl][bones.index("Spine")] = 1.0
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _object(bm, name):
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    for n, _, _ in JOINTS:
        obj.vertex_groups.new(name=n)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return obj


def _armature():
    arm = bpy.data.armatures.new("rig")
    ao = bpy.data.objects.new("rig", arm)
    bpy.context.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n, p, at in JOINTS:
        b = arm.edit_bones.new(n)
        b.head = Vector(at)
        b.tail = Vector(at) + Vector((0, 0.05, 0))
        if p:
            b.parent = eb[p]
        eb[n] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return ao


def _colours(obj, ao_strength=0.75):
    """Col: R the region, G ambient occlusion baked in Cycles."""
    me = obj.data
    regions = [d.value for d in me.attributes["region"].data]
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.world = scene.world or bpy.data.worlds.new("w")
    scene.world.light_settings.distance = 0.15
    ao = me.color_attributes.new("AO", "FLOAT_COLOR", "POINT")
    me.color_attributes.active_color = ao
    me.materials.append(bpy.data.materials.new("bake"))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, d in enumerate(col.data):
        a = ao.data[i].color[0]
        d.color = ((regions[i] + 0.5) / 32.0, 1.0 - ao_strength * (1.0 - a), 0.0, 1.0)
    me.color_attributes.remove(me.color_attributes["AO"])
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    me.materials.clear()
    mat = bpy.data.materials.new("zombie")
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Col"
    mat.node_tree.links.new(node.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
    me.materials.append(mat)


def export(model, hi):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = build(model, hi)
    name = "zombie_%s%s" % (model, "" if hi else "_lo")
    obj = _object(bm, name)
    rig = _armature()
    _colours(obj)
    obj.parent = rig
    mod = obj.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=False, export_skins=True,
        export_vertex_color="ACTIVE", export_texcoords=False, export_materials="EXPORT",
        export_animations=False, export_apply=False,
    )
    print("wrote %s (%d vertices, %d faces)" % (os.path.relpath(path, ROOT), len(obj.data.vertices), len(obj.data.polygons)))
    if hi and "--preview" in sys.argv:
        _preview(obj, rig, name)


def _preview(obj, rig, name):
    """Renders it in true-ish colours, at rest and reaching."""
    me = obj.data
    pal = {0: (0.62, 0.6, 0.5), 1: (0.45, 0.12, 0.1), 2: (0.3, 0.08, 0.06), 3: (0.25, 0.28, 0.38), 4: (0.3, 0.18, 0.12),
           5: (0.1, 0.08, 0.07), 6: (0.5, 0.45, 0.38), 7: (0.42, 0.37, 0.3), 8: (0.8, 0.76, 0.66), 9: (0.74, 0.75, 0.71),
           10: (0.07, 0.015, 0.012), 11: (0.52, 0.56, 0.62), 12: (0.62, 0.6, 0.52), 13: (0.4, 0.1, 0.08)}
    col = me.color_attributes["Col"]
    show = me.color_attributes.new("Show", "FLOAT_COLOR", "POINT")
    for i, d in enumerate(col.data):
        r = int(d.color[0] * 32)
        c = pal.get(r, (1, 0, 1))
        a = d.color[1]
        show.data[i].color = (c[0] ** 2.2 * a, c[1] ** 2.2 * a, c[2] ** 2.2 * a, 1)
    mat = me.materials[0]
    mat.node_tree.nodes["Color Attribute"].layer_name = "Show"
    scene = bpy.context.scene
    scene.cycles.samples = 24
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.52, 0.56, 1)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), math.radians(-25), math.radians(20))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    out = os.environ.get("PREVIEW_DIR", os.path.join(ROOT, "shots"))
    os.makedirs(out, exist_ok=True)
    rig.rotation_euler = (math.radians(90), 0, 0)   # our y up is Blender's z up

    def bl(p):
        return Vector((p[0], -p[2], p[1]))

    for view, at, look, pose in (
        ("front", (0.9, 1.1, 2.6), (0, 0.95, 0), False),
        ("face", (0.12, 1.66, 0.42), (0, 1.62, 0), False),
        ("reach", (1.6, 1.2, 1.9), (0, 0.95, 0), True),
    ):
        cam.location = bl(at)
        cam.rotation_mode = "QUATERNION"
        cam.rotation_quaternion = (bl(look) - cam.location).to_track_quat("-Z", "Y")
        if pose:
            bpy.context.view_layer.objects.active = rig
            bpy.ops.object.mode_set(mode="POSE")
            for s in ("l", "r"):
                pb = rig.pose.bones["Shoulder" + s]
                pb.rotation_mode = "XYZ"
                pb.rotation_euler = (-1.3, 0, 0)
                pe = rig.pose.bones["Elbow" + s]
                pe.rotation_mode = "XYZ"
                pe.rotation_euler = (-0.4, 0, 0)
            ph = rig.pose.bones["Hipl"]
            ph.rotation_mode = "XYZ"
            ph.rotation_euler = (-0.5, 0, 0)
            pk = rig.pose.bones["Kneel"]
            pk.rotation_mode = "XYZ"
            pk.rotation_euler = (0.7, 0, 0)
            bpy.ops.object.mode_set(mode="OBJECT")
        scene.render.filepath = os.path.join(out, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    print("previews in", out)


if __name__ == "__main__":
    names = [a for a in sys.argv[1:] if not a.startswith("--")] or list(MODELS)
    for m in names:
        export(m, True)
        export(m, False)
