# What everything is made of. For each object this bakes two maps in Blender
# (how hidden from the sky each bit of surface is, and where it is in space),
# paints a colour texture from them (skin with its lips, flush, stubble and
# grime; cloth with its weave, fading, creases and dirt), and gives the object
# a material using it that the game can load.
import os

import bpy
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

import mh

TEX = int(os.environ.get("TEX", "1024"))     # texture size for clothes (skin is twice this)
SAMPLES = int(os.environ.get("AO_SAMPLES", "24"))


def to_linear(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


# --- Noise (in space, so it runs unbroken across the seams of a texture) --------
def _hash(ix, iy, iz, seed):
    n = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 974711) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1103515245) & 0xFFFFFFFF
    n ^= n >> 16
    return (n & 0xFFFF) / 65535.0


def vnoise(p, seed=0):
    """Smooth noise, 0 to 1, at points p (..., 3)."""
    i = np.floor(p).astype(np.int64)
    f = p - i
    f = f * f * (3.0 - 2.0 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1.0 - f[..., 0]) * (f[..., 1] if dy else 1.0 - f[..., 1]) * (f[..., 2] if dz else 1.0 - f[..., 2])
                out = out + w * _hash(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def fbm(p, octaves=4, seed=0):
    out, amp, total = 0.0, 1.0, 0.0
    for k in range(octaves):
        out = out + amp * vnoise(p * (2.0 ** k), seed + k * 17)
        total += amp
        amp *= 0.5
    return out / total


def step(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    """Colour a (..., 3) towards colour b by t (...)."""
    return a + (np.asarray(b) - a) * t[..., None]


# --- Baking ----------------------------------------------------------------------
def _setup_baking():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 6
    scene.render.bake.use_clear = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.light_settings.distance = 0.3


def bake(ob, res, tinted=False):
    """(where in space each texel is (res, res, 3), how open to the sky it is (res, res)),
    rows from the bottom of the texture up, as Blender keeps them."""
    scene = bpy.context.scene
    mat = bpy.data.materials.new("bake")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    add = nt.nodes.new("ShaderNodeVectorMath")
    add.operation = "MULTIPLY_ADD"
    add.inputs[1].default_value = (0.25, 0.25, 0.25)
    add.inputs[2].default_value = (0.5, 0.5, 0.5)
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Position"], add.inputs[0])
    nt.links.new(add.outputs[0], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    nt.nodes.active = tex
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for o in bpy.context.view_layer.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    maps = []
    passes = [("EMIT", 1), ("AO", SAMPLES)]
    if tinted:        # a third map: each part's own colour
        passes.append(("TINT", 1))
    for kind, samples in passes:
        if kind == "TINT":
            attr = nt.nodes.new("ShaderNodeAttribute")
            attr.attribute_name = "tint"
            nt.links.new(attr.outputs["Color"], emit.inputs["Color"])
            kind = "EMIT"
        img = bpy.data.images.new("bake_" + kind, res, res, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        tex.image = img
        scene.cycles.samples = samples
        bpy.ops.object.bake(type=kind)
        px = np.empty(res * res * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        maps.append(px.reshape(res, res, 4)[..., :3].astype(np.float64))
        bpy.data.images.remove(img)
    ob.data.materials.clear()
    bpy.data.materials.remove(mat)
    return ((maps[0] - 0.5) * 4.0, maps[1][..., 0]) + ((maps[2],) if tinted else ())


def uv_mask(shapes, res, blur=0.0):
    """A mask (res, res), 0 to 1, of some shapes (lists of (u, v) corners) in a texture."""
    img = Image.new("L", (res, res), 0)
    draw = ImageDraw.Draw(img)
    for shape in shapes:
        draw.polygon([(u * res, (1.0 - v) * res) for u, v in shape], fill=255)
    if blur > 0.0:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(img, dtype=np.float64)[::-1] / 255.0


def _file_mask(name, res):
    img = Image.open(mh._path("textures", name)).convert("L").resize((res, res), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64)[::-1] / 255.0


def save(ctx, name, rgb):
    """Writes a painted texture (rows from the bottom up, sRGB 0 to 1) and loads it into Blender."""
    folder = os.path.join(ctx.out, "textures")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "%s_%s.jpg" % (ctx.name, name.lower()))
    Image.fromarray((np.clip(rgb[::-1], 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)).save(path, quality=90)
    img = bpy.data.images.load(path)
    img.pack()
    return img


def material(name, color=(0.8, 0.8, 0.8), image=None, roughness=0.7, two_sided=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*to_linear(color), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if image is not None:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    m.use_backface_culling = not two_sided
    return m


# --- Painting --------------------------------------------------------------------
DIRT = np.array([0.30, 0.24, 0.17])


def paint_skin(ctx, ob, look):
    res = TEX * 2
    pos, ao = bake(ob, res)
    tone = np.array(look["skin"])
    rgb = np.ones((res, res, 3)) * tone
    # Never one flat colour: it varies in patches, is ruddier where the blood
    # is near the skin, and darker in every fold.
    rgb *= (0.93 + 0.14 * fbm(pos * 14.0, 4, 3))[..., None]
    lips, face, ears, lids, nails, mouth = (_file_mask("mpfb_%s.jpg" % n, res) for n in ("lips", "face", "ears", "eyelids", "fingernails", "inside-mouth"))
    ruddy = tone * np.array([1.0, 0.72, 0.68])
    flush = np.clip(0.35 * face * fbm(pos * 30.0, 3, 9) + 0.45 * ears + 0.3 * lids, 0.0, 1.0)
    rgb = mix(rgb, ruddy, flush)
    body_look = look.get("grime", 0.4)
    rgb = mix(rgb, tone * np.array([0.86, 0.62, 0.6]), lips * 0.8)
    rgb = mix(rgb, tone * 1.12 + np.array([0.04, 0.02, 0.02]), nails * 0.6)
    rgb = mix(rgb, np.array([0.25, 0.07, 0.07]), mouth)
    if "stubble" in look:       # the shapes, in the texture, of where a beard grows
        m = uv_mask(look["stubble"], res, blur=res / 180.0)
        specks = fbm(pos * 900.0, 2, 5)
        rgb = mix(rgb, np.array(look["hair"]) * 0.6, m * (0.38 + 0.3 * specks) * look.get("stubble_amount", 1.0))
    if "brows" in look:         # eyebrows: fine hairs, drawn on
        m = uv_mask(look["brows"], res, blur=res / 500.0)
        hairs = 0.55 + 0.45 * vnoise(pos * np.array([1100.0, 500.0, 500.0]), 7)
        rgb = mix(rgb, np.array(look["hair"]) * 0.6, np.clip(m * 1.25, 0.0, 1.0) * hairs * look.get("brow_amount", 0.8))
    if "scalp" in look:         # under the hair, the scalp is shadowed with it
        m = uv_mask(look["scalp"], res, blur=res / 120.0)
        rgb = mix(rgb, np.array(look["hair"]) * 0.5, m * 0.75)
    rgb *= (0.55 + 0.45 * np.clip(ao, 0.0, 1.0) ** 0.9)[..., None]
    rgb *= (0.975 + 0.05 * vnoise(pos * 1500.0, 11))[..., None]             # pores
    grime = step(fbm(pos * 7.0, 4, 21), 0.5, 0.78) * body_look
    rgb = mix(rgb, DIRT * 0.9, grime * 0.55)
    return save(ctx, ob.name, rgb)


def paint_cloth(ctx, ob, look):
    res = TEX * (2 if look.get("big") else 1)
    if look.get("tinted"):
        pos, ao, rgb = bake(ob, res, True)
    else:
        pos, ao = bake(ob, res)
        rgb = np.ones((res, res, 3)) * np.array(look["color"])
    fabric = look.get("fabric", "cotton")
    seed = look.get("seed", 1)
    rgb *= (0.9 + 0.2 * fbm(pos * 5.0, 4, seed))[..., None]
    thread = vnoise(pos * 1400.0, seed + 3)
    if fabric == "denim":      # a twill: fine diagonal lines, white threads showing where it's worn
        twill = 0.5 + 0.5 * np.sin((pos[..., 0] + pos[..., 1] + pos[..., 2] * 1.4) * 2600.0)
        rgb *= (0.9 + 0.12 * twill * thread)[..., None]
        worn = step(fbm(pos * 22.0, 4, seed + 5) * (0.4 + 0.6 * ao), 0.45, 0.75)
        rgb = mix(rgb, rgb * 1.4 + 0.06, worn * 0.3)
    elif fabric == "leather":  # dark in the creases, scuffed pale on the high spots
        rgb *= (0.92 + 0.1 * vnoise(pos * 500.0, seed + 3))[..., None]
        scuff = step(fbm(pos * 16.0, 4, seed + 5) * ao, 0.48, 0.7)
        rgb = mix(rgb, rgb * 1.7 + 0.06, scuff * 0.45)
    elif fabric == "knit":     # ribs running up it
        rib = 0.5 + 0.5 * np.sin(np.arctan2(pos[..., 0], pos[..., 1]) * 110.0)
        rgb *= (0.84 + 0.2 * rib + 0.06 * thread)[..., None]
    elif fabric == "fleece":   # a deep pile, tufted
        rgb *= (0.8 + 0.3 * fbm(pos * 160.0, 3, seed + 3))[..., None]
    else:                      # plain woven cloth
        rgb *= (0.93 + 0.12 * thread)[..., None]
    rgb *= (0.6 + 0.4 * np.clip(ao, 0.0, 1.0) ** 0.8)[..., None]
    # Lived in: grime worked into it in patches, heavier towards the ground.
    grime = step(fbm(pos * 6.0, 4, seed + 9), 0.45, 0.8) * look.get("grime", 0.5)
    rgb = mix(rgb, DIRT, grime * 0.5)
    dust = step(-pos[..., 2], -0.6, -0.02) * look.get("dusty", 0.0) * (0.35 + 0.5 * fbm(pos * 5.0, 2, seed + 13))     # pale, from the road
    rgb = mix(rgb, np.array([0.5, 0.45, 0.37]), dust * 0.55)
    stain = step(fbm(pos * 4.0 + 31.0, 3, seed + 21), 0.66, 0.76) * look.get("stains", 0.0)
    rgb = mix(rgb, np.array([0.2, 0.06, 0.04]), stain * 0.7)
    return save(ctx, ob.name, rgb)


ROUGH = {"cotton": 0.92, "denim": 0.9, "leather": 0.55, "knit": 0.95, "fleece": 1.0, "canvas": 0.9}


def textures(ctx):
    _setup_baking()
    for name, ob in list(ctx.objects.items()):
        look = dict(ctx.materials.get(name, {}))
        kind = look.get("kind", "plain")
        if kind == "hair":
            continue                      # hair.py gave it its material
        if not ob.data.uv_layers:
            kind = "plain"
        if kind == "skin":
            look.update(ctx.spec.get("skin_look", {}), skin=ctx.spec["skin"], hair=ctx.spec.get("hair", (0.1, 0.08, 0.06)))
            look.update(ctx.skin_masks)
            m = material(name, image=paint_skin(ctx, ob, look), roughness=0.6)
        elif kind == "eyes":
            # The eye texture, its iris recoloured to this person's and its white toned down.
            eye = np.asarray(Image.open(mh._path("eyes", "materials", "brown_eye.png")).convert("RGBA"), dtype=np.float64) / 255.0
            hi, lo = eye[..., :3].max(axis=2), eye[..., :3].min(axis=2)
            iris = step((hi - lo) / np.maximum(hi, 1e-6), 0.2, 0.45)
            eye[..., :3] = mix(eye[..., :3] * 0.88, np.clip(hi[..., None] * 1.6 * np.array(ctx.spec.get("eyes", (0.36, 0.25, 0.15))), 0.0, 1.0), iris)
            path = os.path.join(ctx.out, "textures", "%s_eyes.png" % ctx.name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            Image.fromarray((eye * 255.0 + 0.5).astype(np.uint8), "RGBA").save(path)
            img = bpy.data.images.load(path)
            img.pack()
            m = material(name, image=img, roughness=0.12)
            cut = m.node_tree.nodes.new("ShaderNodeMath")       # the clear front of the eye is cut away, to see the iris
            cut.operation = "ROUND"
            m.node_tree.links.new(m.node_tree.nodes["Image Texture"].outputs["Alpha"], cut.inputs[0])
            m.node_tree.links.new(cut.outputs[0], m.node_tree.nodes["Principled BSDF"].inputs["Alpha"])
            m.blend_method = "CLIP"
        elif kind == "cloth":
            m = material(name, image=paint_cloth(ctx, ob, look), roughness=ROUGH.get(look.get("fabric", "cotton"), 0.9), two_sided=True)
        else:
            m = material(name, look.get("color", (0.5, 0.5, 0.5)), roughness=look.get("roughness", 0.8), two_sided=look.get("two_sided", False))
        ob.data.materials.clear()
        ob.data.materials.append(m)
