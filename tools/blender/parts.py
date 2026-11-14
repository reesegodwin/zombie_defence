# The pieces of a survivor, as Blender objects: skeleton, body, eyes, and
# (wear_*) each thing they wear or carry.
import math

import bpy
import numpy as np
from mathutils import kdtree

import mh


class Context:
    def __init__(self, human, spec, name):
        self.human = human
        self.spec = spec
        self.name = name
        self.objects = {}      # everything made, by name
        self.materials = {}    # what each object is made of, for paint.py: name -> {"kind": ..., ...}
        self.joins = {}        # parts to be joined into an object, by its name
        self.rig = None
        self.bone_names = []
        self.W = None          # skin weights of every base-mesh vertex: (verts, bones)
        self._kd = None

    def weights_at(self, points, k=4):
        """Skin weights for new points: those of the nearest bits of body."""
        if self._kd is None:
            a, b = self.human.group_range("body")
            self._kd_idx = np.arange(a, b)
            self._kd = kdtree.KDTree(b - a)
            for i in range(a, b):
                self._kd.insert(self.human.verts[i], i)
            self._kd.balance()
        out = np.zeros((len(points), len(self.bone_names)), dtype=np.float32)
        for n, p in enumerate(points):
            for _, i, d in self._kd.find_n(p, k):
                out[n] += self.W[i] / (d * d + 1e-6)
        out /= np.maximum(out.sum(axis=1, keepdims=True), 1e-9)
        return out


def new_object(ctx, name, verts, faces, uvs=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(float(c) for c in v) for v in verts], [], faces)
    me.update()
    if uvs is not None:
        layer = me.uv_layers.new(name="UVMap")
        layer.data.foreach_set("uv", [c for f in uvs for uv in f for c in uv])
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ctx.objects[name] = ob
    return ob


def skin(ctx, ob, weights):
    """Binds an object to the skeleton. weights: (verts, bones), or a bone's name for something rigid."""
    if isinstance(weights, str):
        ob.vertex_groups.new(name=weights).add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    else:
        for b, bone in enumerate(ctx.bone_names):
            col = weights[:, b]
            idx = np.nonzero(col > 0.005)[0]
            if len(idx):
                g = ob.vertex_groups.new(name=bone)
                for i in idx:
                    g.add([int(i)], float(col[i]), "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = ctx.rig
    ob.parent = ctx.rig


def make_rig(ctx):
    bones = ctx.human.rig()
    arm = bpy.data.armatures.new("Skeleton")
    rig = bpy.data.objects.new("Skeleton", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    made = {}
    for name, b in bones.items():
        e = arm.edit_bones.new(name)
        e.head = b["head"]
        e.tail = b["tail"] if np.linalg.norm(b["tail"] - b["head"]) > 1e-4 else b["head"] + np.array([0, 0, 0.05])
        e.roll = b["roll"]
        made[name] = e
    for name, b in bones.items():
        if b["parent"]:
            made[name].parent = made[b["parent"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    ctx.rig = rig
    ctx.bones = bones
    ctx.bone_names = list(bones)
    ctx.W = np.zeros((len(ctx.human.verts), len(ctx.bone_names)), dtype=np.float32)
    for bone, pairs in ctx.human.weights().items():
        if bone in bones and pairs:
            p = np.array(pairs)
            ctx.W[p[:, 0].astype(int), ctx.bone_names.index(bone)] = p[:, 1]


def make_body(ctx):
    verts, faces, uvs, old = ctx.human.part("body")
    ob = new_object(ctx, "Body", verts, faces, uvs)
    ctx.body_old = old
    skin(ctx, ob, ctx.W[old])
    ctx.materials["Body"] = {"kind": "skin"}
    # Where hair and beard grow, as shapes in the skin's texture (to shade the skin under them).
    import gzip, json
    def region(name):
        return {int(k) for k in json.load(gzip.open(mh._path("uv_layers", name + ".json.gz"), "rt"))}
    centre = np.array([p.center for p in ob.data.polygons])
    lips = region("lips_solid")
    mouth = centre[sorted(lips)].mean(axis=0)
    ctx.mouth = mouth
    ctx.scalp_faces = sorted(region("scalp_solid"))
    jaw = []
    for f in region("face_solid") | region("neck_front_split"):
        c = centre[f]
        top = mouth[2] + (0.02 if abs(c[0]) < 0.045 else 0.02 + min(0.06, (abs(c[0]) - 0.045) * 1.6))
        if f not in lips and mouth[2] - 0.085 < c[2] < top and c[1] < mouth[1] + 0.105:
            jaw.append(f)
    ctx.jaw_faces = jaw
    eye = ctx.human.joint("joint-l-eye")
    # Hair grows from a hairline, not from halfway down the forehead.
    middle = centre[ctx.scalp_faces].mean(axis=0)
    ctx.scalp_faces = [f for f in ctx.scalp_faces if not (centre[f][1] < middle[1] - 0.045 and centre[f][2] < eye[2] + 0.07 - abs(centre[f][0]) * 0.28)]
    ctx.brow_faces = [f for f in region("face_solid") if 0.01 < abs(centre[f][0]) < 0.058 and centre[f][1] < eye[1] + 0.03
                      and abs(centre[f][2] - (eye[2] + 0.023 + 0.004 * math.sin(math.pi * (abs(centre[f][0]) - 0.01) / 0.048))) < 0.0065]
    uv = ob.data.uv_layers.active.data
    def shapes(faces):
        return [[(uv[l].uv[0], uv[l].uv[1]) for l in ob.data.polygons[f].loop_indices] for f in faces]
    ctx.skin_masks = {"brows": shapes(ctx.brow_faces)}
    if ctx.spec.get("hair_style", "none") != "none":
        ctx.skin_masks["scalp"] = shapes(ctx.scalp_faces)
    if ctx.spec.get("stubble", 0.0) > 0.0:
        ctx.skin_masks["stubble"] = shapes(jaw)
        ctx.skin_masks["stubble_amount"] = ctx.spec["stubble"]
    return ob


def make_eyes(ctx):
    verts, faces, uvs = mh.fit_proxy(ctx.human, "eyes/high-poly", "high-poly")
    ob = new_object(ctx, "Eyes", verts, faces, uvs)
    skin(ctx, ob, "head")
    ctx.materials["Eyes"] = {"kind": "eyes"}
    return ob


def finish(ctx):
    """Joins each thing's parts into it (sharing one texture), and cuts away
    the skin that's under clothes (it would only poke through)."""
    for parent, kids in ctx.joins.items():
        ob = ctx.objects[parent]
        if not ob.data.color_attributes.get("tint"):
            tint(ob, ctx.materials[parent].get("color", (0.5, 0.5, 0.5)))
        with bpy.context.temp_override(active_object=ob, object=ob, selected_objects=[ob] + kids, selected_editable_objects=[ob] + kids):
            bpy.ops.object.join()
        bpy.context.view_layer.objects.active = ob
        for o in bpy.context.view_layer.objects:
            o.select_set(o == ob)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(margin=0.006)
        bpy.ops.object.mode_set(mode="OBJECT")
        ctx.materials[parent]["tinted"] = True
    if not hasattr(ctx, "hidden"):
        return
    body = ctx.objects["Body"]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    hidden = ctx.hidden[ctx.body_old]
    gone = [f for f in bm.faces if all(hidden[v.index] for v in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    bm.to_mesh(body.data)
    bm.free()


# --- Helpers for making things on the body -------------------------------------
import bmesh                                    # noqa: E402
from mathutils import Vector                    # noqa: E402
from mathutils.bvhtree import BVHTree           # noqa: E402

FAST = bool(__import__("os").environ.get("FAST"))   # skip the slow steps (draping) while trying things out

ARM = ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")
LEG = ("thigh", "calf", "foot", "ball")


def _along(p, a, b, c):
    """How far along the limb a -> b -> c each point p is: 0 at a, 1 at b, 2 at c."""
    def seg(a, b):
        ab = b - a
        t = ((p - a) @ ab) / (ab @ ab)
        near = a + np.clip(t, 0.0, 1.0)[:, None] * ab
        return t, np.linalg.norm(p - near, axis=1)
    t1, d1 = seg(a, b)
    t2, d2 = seg(b, c)
    return np.where(d2 < d1, 1.0 + np.maximum(t2, 0.0), np.minimum(t1, 1.0))


def body_fields(ctx):
    """Where every vertex of the base mesh is on the body: "arm" and "leg"
    (how much it moves with them, 0 to 1), "arm_t" and "leg_t" (how far down
    them: 0 shoulder/hip, 1 elbow/knee, 2 wrist/ankle)."""
    if hasattr(ctx, "fields"):
        return ctx.fields
    h = ctx.human
    v = h.verts
    names = ctx.bone_names
    arm = ctx.W[:, [i for i, n in enumerate(names) if n.startswith(ARM)]].sum(axis=1)
    leg = ctx.W[:, [i for i, n in enumerate(names) if n.startswith(LEG)]].sum(axis=1)
    arm_t = np.zeros(len(v))
    leg_t = np.zeros(len(v))
    for s, sign in (("l", 1.0), ("r", -1.0)):
        m = v[:, 0] * sign >= 0.0
        arm_t[m] = _along(v[m], h.joint("joint-%s-shoulder" % s), h.joint("joint-%s-elbow" % s), h.joint("joint-%s-hand" % s))
        leg_t[m] = _along(v[m], h.joint("joint-%s-upper-leg" % s), h.joint("joint-%s-knee" % s), h.joint("joint-%s-ankle" % s))
    ctx.fields = {"arm": arm, "leg": leg, "arm_t": arm_t, "leg_t": leg_t}
    ctx.z = {k: h.joint("joint-" + k)[2] for k in ("pelvis", "neck", "head", "spine-1", "spine-2", "spine-3")}
    return ctx.fields


def nearest_base(ctx, points, group="helper-tights"):
    """For each point, the index of the nearest base-mesh vertex in a group."""
    key = "_kd_" + group
    if not hasattr(ctx, key):
        a, b = ctx.human.group_range(group)
        kd = kdtree.KDTree(b - a)
        for i in range(a, b):
            kd.insert(ctx.human.verts[i], i)
        kd.balance()
        setattr(ctx, key, kd)
    kd = getattr(ctx, key)
    return np.array([kd.find(p)[1] for p in points])


def coords(ob):
    out = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", out)
    return out.reshape(-1, 3)


def set_coords(ob, co):
    ob.data.vertices.foreach_set("co", np.asarray(co, dtype=np.float64).ravel())
    ob.data.update()


def normals(ob):
    out = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("normal", out)
    return out.reshape(-1, 3)


def apply_modifier(ob, mod):
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def subdivide(ob, levels=1):
    mod = ob.modifiers.new("Subdivision", "SUBSURF")
    mod.levels = levels
    mod.subdivision_type = "CATMULL_CLARK"
    apply_modifier(ob, mod)


def unwrap(ob, angle=66.0, margin=0.01):
    """Lays the object's surface out flat for its texture (do it before the
    mesh is made fine: the layout carries over)."""
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.view_layer.objects:
        o.select_set(o == ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def thicken(ob, thickness=0.003, rim_only=True):
    mod = ob.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_rim_only = rim_only
    apply_modifier(ob, mod)


def smooth(ob, factor=0.5, repeat=1):
    mod = ob.modifiers.new("Smooth", "SMOOTH")
    mod.factor = factor
    mod.iterations = repeat
    apply_modifier(ob, mod)


def surface_of(obs):
    """A tree for finding the nearest point on (or casting rays at) some objects' surfaces."""
    verts, polys = [], []
    for ob in obs:
        base = len(verts)
        verts.extend(Vector(v) for v in coords(ob))
        polys.extend([base + i for i in p.vertices] for p in ob.data.polygons)
    return BVHTree.FromPolygons(verts, polys)


def drape(ctx, ob, pin, colliders, frames=22, grow=0.04, more=None, grow_more=0.0, gravity=0.35, stiff=12.0, bend=0.4, gap=0.004):
    """Lets cloth hang on the body: it is a little too big for it (grow, and
    grow_more where more (0 to 1 per vertex) says), so it settles into folds.
    pin: how firmly each vertex is held where it is (0 to 1)."""
    if FAST:
        return
    g = ob.vertex_groups.new(name="pin")
    for i in np.nonzero(pin > 0.01)[0]:
        g.add([int(i)], float(min(pin[i], 1.0)), "REPLACE")
    g2 = ob.vertex_groups.new(name="grow")
    if more is not None:
        for i in np.nonzero(more > 0.01)[0]:
            g2.add([int(i)], float(min(more[i], 1.0)), "REPLACE")
    for c in colliders:
        if not any(m.type == "COLLISION" for m in c.modifiers):
            c.modifiers.new("Collision", "COLLISION")
            c.collision.thickness_outer = gap
            c.collision.thickness_inner = 0.02
            c.collision.cloth_friction = 12.0
    mod = ob.modifiers.new("Cloth", "CLOTH")
    s = mod.settings
    s.quality = 7
    s.mass = 0.25
    s.tension_stiffness = stiff
    s.compression_stiffness = stiff
    s.shear_stiffness = stiff * 0.4
    s.bending_stiffness = bend
    s.tension_damping = 8.0
    s.compression_damping = 8.0
    s.bending_damping = 0.6
    s.vertex_group_mass = "pin"
    s.pin_stiffness = 1.0
    s.shrink_min = -grow
    if more is not None:
        s.vertex_group_shrink = "grow"
        s.shrink_max = -grow_more
    s.effector_weights.gravity = gravity
    c = mod.collision_settings
    c.use_collision = True
    c.distance_min = gap
    c.collision_quality = 3
    c.use_self_collision = False
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frames + 1
    for f in range(1, frames + 1):
        scene.frame_set(f)
    ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
    co = np.empty(len(ev.data.vertices) * 3)
    ev.data.vertices.foreach_get("co", co)
    ob.modifiers.remove(mod)
    ob.vertex_groups.remove(g)
    ob.vertex_groups.remove(g2)
    scene.frame_set(1)
    set_coords(ob, co.reshape(-1, 3))


def garment(ctx, name, keep, ease, cut=None, trim=(), levels=2, kind="cloth", **look):
    """A piece of clothing cut from the body's fitted surface (the base
    mesh's "tights"): the faces whose corners all pass keep (an array over
    the base mesh), moved out from the skin by ease (metres, per base
    vertex), with the faces cut(centre, normal) says to cut away removed."""
    h = ctx.human
    a, b = h.group_range("helper-tights")
    bm = bmesh.new()
    made = {}
    src = []
    for f, g in zip(h.faces, h.face_groups):
        if g == "helper-tights" and all(keep[i] for i in f):
            for i in f:
                if i not in made:
                    made[i] = bm.verts.new(h.verts[i])
                    src.append(i)
            bm.faces.new([made[i] for i in f])
    bm.normal_update()
    if cut is not None:
        gone = [f for f in bm.faces if cut(np.array(f.calc_center_median()), np.array(f.normal))]
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bm.normal_update()
    bm.verts.ensure_lookup_table()
    index_of = {v: i for i, v in made.items()}
    for v in bm.verts:
        v.co += v.normal * float(ease[index_of[v]])
    for point, normal in trim:      # a clean edge: everything beyond this plane goes
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=point, plane_no=normal, clear_outer=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ctx.objects[name] = ob
    ctx.materials[name] = dict(kind=kind, **look)
    if "color" in look:
        tint(ob, look["color"])
    unwrap(ob)
    if levels:
        subdivide(ob, levels)
    return ob


def bind(ctx, ob):
    """Skins something that lies on the body, by the body under it."""
    skin(ctx, ob, ctx.weights_at(coords(ob)))


def cover(ctx, hidden):
    """Marks body vertices (an array over the base mesh) as under clothes: they're cut away at the end."""
    ctx.hidden = hidden if not hasattr(ctx, "hidden") else (ctx.hidden | hidden)


def _step(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _on_body(ctx, ob):
    """The body fields (see body_fields) at each of an object's vertices."""
    F = body_fields(ctx)
    i = nearest_base(ctx, coords(ob))
    return {k: a[i] for k, a in F.items()}


def _colliders(ctx, *names):
    return [ctx.objects["Body"]] + [ctx.objects[n] for n in names if n in ctx.objects]


# --- Clothes ---------------------------------------------------------------------
def wear_tee(ctx, color, name="Tee", hem=-0.06, sleeve=0.45, ease=0.006, scoop=0.035, **look):
    """A T-shirt, close on the body: hem (metres from the hip joints), sleeve (how far down the upper arm)."""
    F = body_fields(ctx)
    v = ctx.human.verts
    z = v[:, 2]
    low = ctx.z["pelvis"] + hem
    keep = (z > low - 0.06) & (z < ctx.z["neck"] - 0.012) & (F["leg"] < 0.8) & ((F["arm"] < 0.5) | (F["arm_t"] < sleeve))
    top = ctx.z["pelvis"] + 0.1          # below here it hangs outside the trousers
    ob = garment(ctx, name, keep, ease + 0.016 * _step(-z, -(top + 0.05), -top), trim=[((0, 0, low), (0, 0, -1))], color=color, **look)
    co = coords(ob)
    front = _step(-co[:, 1], 0.0, 0.08) * _step(co[:, 2], ctx.z["neck"] - 0.09, ctx.z["neck"] - 0.02) * _step(-np.abs(co[:, 0]), -0.09, -0.02)
    co[:, 2] -= scoop * front            # a crew neck, lower at the front
    set_coords(ob, co)
    f = _on_body(ctx, ob)
    pin = _step(co[:, 2], ctx.z["neck"] - 0.14, ctx.z["neck"] - 0.03)
    drape(ctx, ob, pin, _colliders(ctx, "Trousers"), frames=16, grow=0.02, gravity=0.3, bend=0.2, gap=0.005)
    smooth(ob, 0.35, 1)
    thicken(ob, 0.002)
    bind(ctx, ob)
    cover(ctx, (z > ctx.z["pelvis"] + hem + 0.03) & (z < ctx.z["neck"] - 0.05) & (F["leg"] < 0.4) & ((F["arm"] < 0.5) | (F["arm_t"] < sleeve - 0.08)))
    return ob


def wear_jacket(ctx, color, name="Jacket", hem=0.03, sleeve=1.93, ease=0.011, open=0.03, spread=0.012, grow=0.008, stack=0.045,
                neck="fold", pockets=2, flaps=True, buttons=0, zip_=False, cuffs=False, **look):
    """A jacket: hem (metres from the hip joints), sleeve (2 is the wrist),
    open (half the gap down the front, 0 for done up), spread (how far the
    fronts fall apart at the bottom)."""
    F = body_fields(ctx)
    v = ctx.human.verts
    z = v[:, 2]
    low = ctx.z["pelvis"] + hem
    keep = (z > low - 0.05) & (z < ctx.z["neck"] + 0.012) & ((F["arm"] < 0.5) | (F["arm_t"] < sleeve))
    ease_at = ease * (1.0 + 0.25 * F["arm"]) + 0.012 * _step(-z, -(low + 0.18), -low) * (1.0 - F["arm"])
    cut = (lambda c, n: abs(c[0]) < open and n[1] < -0.3) if open > 0.0 else None
    ob = garment(ctx, name, keep, ease_at, cut=cut, trim=[((0, 0, low), (0, 0, -1))], color=color, **look)
    co = coords(ob)
    f = _on_body(ctx, ob)
    torso = 1.0 - f["arm"]
    if open > 0.0:   # the fronts hang apart, more so lower down
        front = _step(-co[:, 1], 0.02, 0.07) * _step(-np.abs(co[:, 0]), -0.13, -0.03) * torso
        co[:, 0] += np.sign(co[:, 0]) * front * (0.012 + spread * _step(-co[:, 2], -(ctx.z["neck"] - 0.1), -low))
        co[:, 1] -= front * 0.006
        set_coords(ob, co)
    pin = np.maximum(0.7 * _step(co[:, 2], ctx.z["neck"] - 0.07, ctx.z["neck"] - 0.01), 0.12) * torso      # held at the collar; elsewhere it only keeps its shape
    pin = np.maximum(pin, 0.8 * _step(f["arm_t"], sleeve - 0.1, sleeve - 0.02) * f["arm"])
    pin = np.maximum(pin, 0.3 * _step(-co[:, 2], -(low + 0.05), -low) * torso)
    drape(ctx, ob, pin, _colliders(ctx, "Tee", "Shirt", "Scarf"), grow=grow, more=_step(f["arm_t"], 0.25, 0.6) * f["arm"], grow_more=stack,
          gravity=0.45, stiff=18.0, bend=0.8, gap=0.006)
    smooth(ob, 0.3, 1)
    dark = tuple(c * 0.86 for c in color)
    if neck:
        collar(ctx, ob, neck, color=tuple(c * 0.93 for c in color) if neck != "sherpa" else None)
    thicken(ob, 0.004)
    bind(ctx, ob)
    tree = surface_of([ob])
    chest = ctx.z["neck"] - 0.2
    for k in range(pockets):       # patch pockets on the chest, each under a flap
        side = 1.0 if k == 0 else -1.0
        at = (side * 0.128, -0.1, chest - 0.035)
        attach(ctx, name, patch(ctx, "%sPocket%d" % (name, k), tree, at, (1, 0, 0), (0, 0, 1), 0.095, 0.105, 6, 6, offset=0.003), tuple(c * 0.94 for c in color))
        if flaps:
            attach(ctx, name, patch(ctx, "%sFlap%d" % (name, k), tree, (at[0], at[1], at[2] + 0.052), (1, 0, 0), (0, 0, 1), 0.1, 0.036, 6, 2, offset=0.007), dark)
            attach(ctx, name, patch(ctx, "%sStud%d" % (name, k), tree, (at[0], at[1], at[2] + 0.043), (1, 0, 0), (0, 0, 1), 0.011, 0.011, 2, 2, offset=0.011, round_=1.0), (0.5, 0.48, 0.42))
    for k in range(buttons):       # down the front, on a placket
        zb = ctx.z["neck"] - 0.07 - k * (ctx.z["neck"] - 0.09 - low) / max(1, buttons - 0.5)
        attach(ctx, name, patch(ctx, "%sButton%d" % (name, k), tree, (0.0, -0.1, zb), (1, 0, 0), (0, 0, 1), 0.012, 0.012, 3, 3, offset=0.005, round_=1.0), (0.2, 0.19, 0.18))
    if buttons:
        attach(ctx, name, patch(ctx, name + "Placket", tree, (0.0, -0.1, (ctx.z["neck"] - 0.05 + low) * 0.5), (1, 0, 0), (0, 0, 1), 0.03, ctx.z["neck"] - 0.07 - low, 2, 24, offset=0.002, thick=0.002), dark)
    if zip_:                       # a zip, done up
        attach(ctx, name, patch(ctx, name + "Zip", tree, (0.0, -0.1, (ctx.z["neck"] - 0.03 + low) * 0.5), (1, 0, 0), (0, 0, 1), 0.012, ctx.z["neck"] - 0.05 - low, 2, 30, offset=0.002, thick=0.002), (0.62, 0.6, 0.56))
    if cuffs:                      # the sleeves turned back in a thick roll
        for s, sign in (("l", 1.0), ("r", -1.0)):
            a, b, c = (ctx.human.joint("joint-%s-%s" % (s, j)) for j in ("shoulder", "elbow", "hand"))
            t = sleeve - 0.04
            at = a + (b - a) * t if t <= 1.0 else b + (c - b) * (t - 1.0)
            along = _unit(b - a if t <= 1.0 else c - b)
            side_dir = _unit(np.cross(along, [0.0, 1.0, 0.0]))
            attach(ctx, name, patch(ctx, "%sCuff%s" % (name, s), tree, at + side_dir * 0.05, np.cross(along, side_dir), along, 0.0, 0.05, 20, 2, axis=at, offset=0.004, thick=0.007, closed=True, reach=0.085), dark)
    cover(ctx, (z > low + 0.05) & (z < ctx.z["neck"] - 0.05) & (F["leg"] < 0.4) & ((F["arm"] < 0.5) | (F["arm_t"] < sleeve - 0.1)) & (np.abs(v[:, 0]) > 0.11))
    return ob


def wear_trousers(ctx, color, name="Trousers", waist=0.075, cuff=1.82, ease=0.009, grow=0.012, stack=0.05, cargo=0, pads=0, turnup=False, **look):
    """Trousers: waist (metres above the hip joints), cuff (how far down the leg: 2 is the ankle)."""
    F = body_fields(ctx)
    v = ctx.human.verts
    z = v[:, 2]
    top = ctx.z["pelvis"] + waist
    keep = (z < top) & (F["arm"] < 0.3) & ((F["leg"] < 0.5) | (F["leg_t"] < cuff))
    ease_at = ease * (1.0 + 0.3 * _step(F["leg_t"], 0.9, 1.3) * F["leg"])
    ob = garment(ctx, name, keep, ease_at, color=color, **look)
    co = coords(ob)
    f = _on_body(ctx, ob)
    pin = np.maximum(_step(co[:, 2], top - 0.1, top - 0.01), 0.7 * _step(f["leg_t"], cuff - 0.12, cuff - 0.02) * f["leg"])
    drape(ctx, ob, pin, _colliders(ctx), grow=grow, more=_step(f["leg_t"], 0.8, 1.3) * f["leg"], grow_more=stack, gravity=0.25)
    smooth(ob, 0.3, 1)
    thicken(ob, 0.003)
    bind(ctx, ob)
    tree = surface_of([ob])
    front = np.array([0.0, -1.0, 0.0])
    for k, (s, sign) in enumerate((("l", 1.0), ("r", -1.0))):
        hip, knee, ankle = (ctx.human.joint("joint-%s-%s" % (s, j)) for j in ("upper-leg", "knee", "ankle"))
        if k < cargo:      # a bellows pocket on the outside of the thigh, under a flap
            at = knee + (hip - knee) * 0.42
            right = np.array([0.0, sign, 0.0])
            attach(ctx, name, patch(ctx, "%sCargo%s" % (name, s), tree, at, right, (0, 0, 1), 0.13, 0.15, 6, 6, offset=0.007, thick=0.006), tuple(c * 0.9 for c in color))
            attach(ctx, name, patch(ctx, "%sCargoFlap%s" % (name, s), tree, at + np.array([0, 0, 0.065]), right, (0, 0, 1), 0.135, 0.045, 6, 2, offset=0.014), tuple(c * 0.8 for c in color))
        if k < pads or pads < 0 and k == 1:   # padded knees, sewn in
            up = _unit(hip - ankle)
            right = _unit(np.cross(up, front))
            attach(ctx, name, patch(ctx, "%sPad%s" % (name, s), tree, knee + front * 0.07 - up * 0.01, right, up, 0.17, 0.17, 8, 8, axis=knee, offset=0.004, thick=0.008, round_=0.8, reach=0.14),
                   tuple(c * 0.82 for c in color))
        if turnup:         # the cuffs rolled up
            up = _unit(knee - ankle)
            at = knee + (ankle - knee) * (cuff - 1.0 - 0.035)
            attach(ctx, name, patch(ctx, "%sTurnup%s" % (name, s), tree, at + front * 0.06, _unit(np.cross(up, front)), up, 0.0, 0.045, 20, 2, axis=at, offset=0.003, thick=0.006, closed=True, reach=0.1),
                   tuple(min(1.0, c * 1.25 + 0.03) for c in color))
    cover(ctx, (z < top - 0.03) & (F["arm"] < 0.3) & ((F["leg"] < 0.5) | (F["leg_t"] < cuff - 0.08)))
    return ob


def wear_boots(ctx, color, name="Boots", top=1.5, ease=0.007, sole=0.022, **look):
    """Boots up the shin to top (1 is the knee, 2 the ankle), on a sole."""
    F = body_fields(ctx)
    v = ctx.human.verts
    keep = (F["leg"] > 0.5) & (F["leg_t"] > top)
    ease_at = ease * (1.0 + 0.6 * _step(-v[:, 2], -0.12, -0.03))
    ob = garment(ctx, name, keep, ease_at, color=color, **look)
    co = coords(ob)
    co[:, 2] = np.maximum(co[:, 2], sole * 0.9)        # stands on its sole, not on the foot's
    set_coords(ob, co)
    smooth(ob, 0.3, 1)
    thicken(ob, 0.004)
    bind(ctx, ob)
    # The soles: each foot's outline, a little proud of the boot, down to the floor.
    for sign in (1.0, -1.0):
        foot = co[(co[:, 0] * sign > 0.0) & (co[:, 2] < 0.05)]
        hull = _hull(foot[:, :2])
        centre = hull.mean(axis=0)
        hull = centre + (hull - centre) * 1.03 + np.sign(hull - centre) * 0.003
        n = len(hull)
        verts = [(x, y, sole) for x, y in hull] + [(x, y, 0.0) for x, y in hull]
        faces = [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)] + [list(range(n))[::-1], list(range(n, 2 * n))]
        s = new_object(ctx, "%sSole%s" % (name, "L" if sign > 0 else "R"), verts, faces, smooth=False)
        unwrap(s)
        bind(ctx, s)
        ctx.materials[s.name] = {"kind": "rubber", "color": (0.05, 0.045, 0.04)}
    tree = surface_of([ob])
    for s, sign in (("l", 1.0), ("r", -1.0)):
        knee, ankle = ctx.human.joint("joint-%s-knee" % s), ctx.human.joint("joint-%s-ankle" % s)
        toe = ctx.human.joint("joint-%s-toe-1-1" % s)
        up = _unit(knee - ankle)
        front = _unit((toe - ankle) * np.array([1.0, 1.0, 0.0]))
        height = np.linalg.norm(knee - ankle) * (2.0 - top)
        rows = max(3, int(height / 0.022))
        for k in range(rows):      # laces, crossing up the front
            at = ankle + up * (0.012 + (height - 0.03) * k / (rows - 1))
            right = _unit(np.cross(up, front))
            tilt = 0.45 if k % 2 == 0 else -0.45
            r2 = right * math.cos(tilt) + up * math.sin(tilt)
            u2 = _unit(np.cross(front * -1.0, r2)) * -1.0
            attach(ctx, name, patch(ctx, "%sLace%s%d" % (name, s, k), tree, at + front * 0.06, r2, _unit(np.cross(np.cross(r2, u2), r2)), 0.05, 0.006, 4, 1, offset=0.0035, thick=0.003),
                   look.get("laces", (0.55, 0.47, 0.34)))
    cover(ctx, (F["leg"] > 0.5) & (F["leg_t"] > top + 0.08))
    return ob


def _hull(p):
    """The convex outline of some 2D points, anticlockwise."""
    p = sorted(set(map(tuple, np.round(p, 4))))
    def half(pts):
        out = []
        for q in pts:
            while len(out) >= 2 and (out[-1][0] - out[-2][0]) * (q[1] - out[-2][1]) - (out[-1][1] - out[-2][1]) * (q[0] - out[-2][0]) <= 0:
                out.pop()
            out.append(q)
        return out[:-1]
    return np.array(half(p) + half(p[::-1]))


# --- Hair ------------------------------------------------------------------------
def wear_hair(ctx, style, over=("Jacket", "Tee", "Shirt"), **change):
    import hair
    return hair.grow(ctx, "Hair", ctx.scalp_faces, style, ctx.spec["hair"], over=over, **change)


def wear_beard(ctx, style="beard", **change):
    import hair
    return hair.grow(ctx, "Beard", ctx.jaw_faces, style, ctx.spec["hair"], **change)


def wear_brows(ctx, **change):
    import hair
    return hair.grow(ctx, "Brows", ctx.brow_faces, "brow", tuple(c * 0.8 for c in ctx.spec["hair"]), **change)


# --- Details: things made on a surface -------------------------------------------
def _unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(np.linalg.norm(v), 1e-9)


def tint(ob, color):
    """Marks a part with its colour (painted into the texture of whatever it ends up joined to)."""
    a = ob.data.color_attributes.get("tint") or ob.data.color_attributes.new("tint", "FLOAT_COLOR", "POINT")
    a.data.foreach_set("color", [c for _ in range(len(ob.data.vertices)) for c in (*color, 1.0)])


def attach(ctx, parent, ob, color=None):
    """Makes ob part of the object named parent (joined, sharing its texture) when everything's built."""
    if color is not None:
        tint(ob, color)
    ctx.joins.setdefault(parent, []).append(ob)
    ctx.objects.pop(ob.name, None)
    ctx.materials.pop(ob.name, None)


def patch(ctx, name, tree, centre, right, up, w, h, nu=8, nv=8, axis=None, offset=0.003, thick=0.003, round_=0.0, closed=False, swell=None, reach=0.45):
    """A piece laid onto a surface (tree: see surface_of), following its every
    fold: w by h metres about centre, right and up being its directions.
    axis: a point on the limb's middle to wrap it round (up is then the limb's
    direction); closed: all the way round. round_: 0 square, 1 an oval.
    reach: how far out from the axis to look for the surface (short, for a
    limb, so as not to find the other one)."""
    centre, right, up = np.asarray(centre, dtype=np.float64), _unit(right), _unit(up)
    out = _unit(np.cross(right, up))
    verts, uvs, last = [], [], centre
    cols = nu if closed else nu + 1
    for j in range(nv + 1):
        t = j / nv * 2.0 - 1.0
        for i in range(cols):
            s = (i / nu) * 2.0 - 1.0
            u, v = s * w * 0.5, t * h * 0.5
            if round_ > 0.0:
                u *= math.sqrt(max(0.0, 1.0 - round_ * t * t * 0.5))
                v *= math.sqrt(max(0.0, 1.0 - round_ * s * s * 0.5))
            if axis is None:
                d = -out
                o = centre + right * u + up * v + out * 0.3
            else:
                a0 = np.asarray(axis, dtype=np.float64)
                radius = np.linalg.norm((centre - a0) - up * ((centre - a0) @ up))
                th = math.pi * s if closed else u / radius
                r = out * math.cos(th) + right * math.sin(th)
                d = -r
                o = a0 + up * ((centre - a0) @ up + v) + r * reach
            hit = tree.ray_cast(Vector(o), Vector(d), reach + 0.02 if axis is not None else 0.6)
            p = (np.array(hit[0]) - d * (offset + (swell(s, t) if swell else 0.0))) if hit[0] is not None else last
            last = p
            verts.append(p)
            uvs.append((i / nu, j / nv))
    faces, face_uvs = [], []
    for j in range(nv):
        for i in range(nu):
            a, b = j * cols + i, j * cols + (i + 1) % cols
            c, e = (j + 1) * cols + (i + 1) % cols, (j + 1) * cols + i
            faces.append([a, b, c, e])
            face_uvs.append([(i / nu, j / nv), ((i + 1) / nu, j / nv), ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv)])
    ob = new_object(ctx, name, verts, faces, face_uvs)
    if thick > 0.0:
        thicken(ob, thick, rim_only=False)
    bind(ctx, ob)
    return ob


def box(ctx, name, centre, x, y, z, size, bone, bevel=0.006, color=None):
    """A box with softened edges: x, y, z its directions, size its (width, depth, height); it moves with one bone."""
    centre = np.asarray(centre, dtype=np.float64)
    x, y, z = _unit(x), _unit(y), _unit(z)
    hx, hy, hz = (s * 0.5 for s in size)
    corners = [centre + x * sx * hx + y * sy * hy + z * sz * hz for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    faces = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
    ob = new_object(ctx, name, corners, faces, smooth=True)
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 3
    apply_modifier(ob, mod)
    unwrap(ob)
    skin(ctx, ob, bone)
    if color is not None:
        tint(ob, color)
    return ob


def lathe(ctx, name, base, axis, profile, bone, sides=14):
    """Something turned: profile is [(distance along axis, radius), ...] from base."""
    base, axis = np.asarray(base, dtype=np.float64), _unit(axis)
    u = _unit(np.cross(axis, [0.3, 0.9, 0.2]))
    v = np.cross(axis, u)
    verts, faces = [], []
    for d, r in profile:
        for k in range(sides):
            a = 2.0 * math.pi * k / sides
            verts.append(base + axis * d + (u * math.cos(a) + v * math.sin(a)) * r)
    for j in range(len(profile) - 1):
        for k in range(sides):
            a, b = j * sides + k, j * sides + (k + 1) % sides
            faces.append([a, b, b + sides, a + sides])
    faces.append(list(range(sides))[::-1])
    faces.append(list(range((len(profile) - 1) * sides, len(profile) * sides)))
    ob = new_object(ctx, name, verts, faces)
    unwrap(ob)
    skin(ctx, ob, bone)
    return ob


def edge_chain(ob, want):
    """The open edge of a piece of cloth where want(point) holds, as points in order."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if len(e.link_faces) == 1 and want(np.array(e.verts[0].co)) and want(np.array(e.verts[1].co))]
    link = {}
    for e in edges:
        a, b = e.verts
        link.setdefault(a.index, []).append(b.index)
        link.setdefault(b.index, []).append(a.index)
    co = {v.index: np.array(v.co) for e in edges for v in e.verts}
    bm.free()
    if not link:
        return np.zeros((0, 3))
    best = []
    seen = set()
    for start in [i for i, n in link.items() if len(n) == 1] + list(link):   # from an end if there is one
        if start in seen:
            continue
        chain = [start]
        seen.add(start)
        while True:
            nxt = [n for n in link[chain[-1]] if n not in seen]
            if not nxt:
                break
            chain.append(nxt[0])
            seen.add(nxt[0])
        if len(chain) > len(best):
            best = chain
    return np.array([co[i] for i in best])


def collar(ctx, ob, kind="fold", stand=0.024, fall=0.03, thick=0.003, color=None, parent=None, fabric=None):
    """A collar round a garment's neck: "band" (standing), "fold" (turned
    down, with points at the front), "sherpa" (the same, thick with fleece)."""
    neck = ctx.z["neck"]
    chain = edge_chain(ob, lambda p: p[2] > neck - 0.045 and abs(p[0]) < 0.14)
    if len(chain) < 6:
        return None
    if chain[0][0] > chain[-1][0]:
        chain = chain[::-1]
    for _ in range(3):      # the cloth's edge is ragged from draping: a collar's is cut straight
        chain[1:-1] = (chain[:-2] + chain[1:-1] * 2.0 + chain[2:]) * 0.25
    mid = np.array([0.0, ctx.human.joint("joint-neck")[1], 0.0])
    n = len(chain)
    rows = []
    for j, (up, outw, drop) in enumerate([(0.0, 0.0, 0.0), (stand * 0.6, 0.003, 0.0), (stand, 0.006, 0.0)] + ([] if kind == "band" else [(stand + 0.003, 0.012, 0.0), (stand * 0.5, 0.021, 0.4), (0.0, 0.026 if kind == "fold" else 0.036, 1.0)])):
        row = []
        for i, p in enumerate(chain):
            r = _unit((p - mid) * np.array([1.0, 1.0, 0.0]))
            end = abs(i / (n - 1) * 2.0 - 1.0) ** 3            # the points, at the two front ends
            q = p + np.array([0.0, 0.0, up]) + r * outw * (1.0 + 0.5 * end) - np.array([0.0, 0.0, fall]) * drop * (1.0 + 0.9 * end)
            row.append(q)
        rows.append(row)
    verts = [p for row in rows for p in row]
    faces, uvs = [], []
    for j in range(len(rows) - 1):
        for i in range(n - 1):
            a = j * n + i
            faces.append([a, a + 1, a + n + 1, a + n])
            uvs.append([(i / n, j / len(rows)), ((i + 1) / n, j / len(rows)), ((i + 1) / n, (j + 1) / len(rows)), (i / n, (j + 1) / len(rows))])
    c = new_object(ctx, ob.name + "Collar", verts, faces, uvs)
    subdivide(c, 1)
    thicken(c, 0.014 if kind == "sherpa" else thick, rim_only=False)
    if kind == "sherpa":
        smooth(c, 0.5, 2)
    bind(ctx, c)
    if kind == "sherpa":
        ctx.materials[c.name] = {"kind": "cloth", "fabric": "fleece", "color": color or (0.78, 0.72, 0.6), "grime": 0.5}
    else:
        attach(ctx, parent or ob.name, c, color)
    return c


# --- Gear ------------------------------------------------------------------------
def gear(ctx, ob, color):
    """Adds a piece of kit: it all ends up one object, "Gear", each piece its own colour."""
    if "Gear" not in ctx.objects:
        ctx.objects.pop(ob.name, None)
        ob.name = "Gear"
        ctx.objects["Gear"] = ob
        ctx.materials["Gear"] = {"kind": "cloth", "fabric": "leather", "color": color, "grime": 0.5}
        tint(ob, color)
    else:
        attach(ctx, "Gear", ob, color)


def _clothes(ctx):
    return surface_of([o for n, o in ctx.objects.items() if n not in ("Eyes", "Hair", "Beard", "Brows", "Gear")])


def wear_strap(ctx, high=(-0.11, 0.0, -0.03), low=(0.15, 0.0, 0.05), width=0.035, color=(0.2, 0.15, 0.1)):
    """A strap slung across the body: over the point high (from the neck's
    height) and round under the point low (from the hip joints' height)."""
    hi = np.array(high) + np.array([0.0, ctx.human.joint("joint-neck")[1] + 0.03, ctx.z["neck"]])
    lo = np.array(low) + np.array([0.0, ctx.human.joint("joint-neck")[1] + 0.03, ctx.z["pelvis"]])
    along = _unit(hi - lo)
    across = _unit(np.cross(along, [0.0, -1.0, 0.0]))        # the strap's width runs this way
    mid = (hi + lo) * 0.5
    ob = patch(ctx, "Strap", _clothes(ctx), mid, along, across, 0.0, width, 72, 1, axis=mid, offset=0.006, thick=0.004, closed=True)
    ctx.strap = (hi, lo, along, across)
    gear(ctx, ob, color)


def wear_bat(ctx, color=(0.5, 0.36, 0.22)):
    """A baseball bat slung on the back, handle up over one shoulder."""
    back = _clothes(ctx).ray_cast(Vector((0.0, 0.6, ctx.z["neck"] - 0.2)), Vector((0.0, -1.0, 0.0)), 1.0)[0]
    y = (back[1] if back is not None else 0.12) + 0.04
    base = np.array([-0.2, y - 0.02, ctx.z["neck"] + 0.13])
    axis = _unit(np.array([0.36, 0.035, -0.78]))
    prof = [(0.0, 0.006), (0.004, 0.018), (0.02, 0.019), (0.03, 0.012), (0.3, 0.0135), (0.52, 0.024), (0.72, 0.031), (0.82, 0.032), (0.845, 0.025), (0.85, 0.008)]
    ob = lathe(ctx, "Bat", base, axis, prof, "spine_03")
    gear(ctx, ob, color)
    grip = lathe(ctx, "BatGrip", base + axis * 0.035, axis, [(0.0, 0.0145), (0.24, 0.0155)], "spine_03", sides=14)
    gear(ctx, grip, (0.12, 0.11, 0.1))


def wear_bag(ctx, side=1.0, size=(0.2, 0.08, 0.16), color=(0.27, 0.23, 0.17), drop=-0.06):
    """A satchel at the hip, on the low end of the strap."""
    at = np.array([side * 0.19, ctx.human.joint("joint-pelvis")[1] + 0.06, ctx.z["pelvis"] + drop])
    hit = _clothes(ctx).ray_cast(Vector((side * 0.6, at[1], at[2])), Vector((-side, 0.0, 0.0)), 1.0)[0]
    if hit is not None:
        at[0] = hit[0] + side * size[1] * 0.5
    x, y, z = np.array([0.0, -1.0, 0.0]), np.array([side, 0.0, 0.0]), np.array([0.0, 0.0, 1.0])
    gear(ctx, box(ctx, "Bag", at, x, y, z, size, "pelvis", bevel=0.012), color)
    gear(ctx, box(ctx, "BagFlap", at + y * (size[1] * 0.5 + 0.004) + z * size[2] * 0.12, x, y, z, (size[0] * 1.03, 0.008, size[2] * 0.72), "pelvis", bevel=0.003), tuple(c * 0.85 for c in color))
    gear(ctx, box(ctx, "BagBuckle", at + y * (size[1] * 0.5 + 0.01) - z * size[2] * 0.12, x, y, z, (0.03, 0.006, 0.035), "pelvis", bevel=0.002), (0.45, 0.42, 0.36))


def wear_holster(ctx, where="thigh", side=-1.0, color=(0.1, 0.1, 0.1)):
    """A holstered pistol: on the thigh (with its straps), under the arm, or a sheath on the belt."""
    s = "l" if side > 0 else "r"
    tree = _clothes(ctx)
    hip, knee = ctx.human.joint("joint-%s-upper-leg" % s), ctx.human.joint("joint-%s-knee" % s)
    down = _unit(knee - hip)
    out = np.array([side, 0.0, 0.0])
    fwd = np.array([0.0, -1.0, 0.0])
    if where == "thigh":
        at = hip + (knee - hip) * 0.42
        hit = tree.ray_cast(Vector(at + out * 0.4), Vector(-out), 0.6)[0]
        at = np.array(hit) + out * 0.022 if hit is not None else at + out * 0.1
        gear(ctx, box(ctx, "Holster", at, fwd, out, -down, (0.075, 0.04, 0.17), "thigh_" + s, bevel=0.01), color)
        gear(ctx, box(ctx, "HolsterGrip", at - down * 0.115 + fwd * -0.012, fwd, out, -down, (0.035, 0.028, 0.075), "thigh_" + s, bevel=0.006), (0.06, 0.06, 0.065))
        for k in (0.3, 0.52):      # strapped round the leg
            c = hip + (knee - hip) * k
            gear(ctx, patch(ctx, "HolsterStrap%d" % int(k * 100), tree, c + fwd * 0.07, _unit(np.cross(-down, fwd)), -down, 0.0, 0.028, 28, 1, axis=c, offset=0.004, thick=0.003, closed=True, reach=0.13), color)
    elif where == "arm":            # a shoulder holster: under the arm, on the strap
        at = np.array([side * 0.17, ctx.human.joint("joint-neck")[1] + 0.0, ctx.z["neck"] - 0.27])
        hit = tree.ray_cast(Vector(at + out * 0.4), Vector(-out), 0.6)[0]
        at = np.array(hit) + out * 0.02 if hit is not None else at
        gear(ctx, box(ctx, "Holster", at, fwd, out, (0, 0, 1), (0.12, 0.035, 0.15), "spine_03", bevel=0.01), color)
        gear(ctx, box(ctx, "HolsterGrip", at + np.array([0, 0, 0.085]) + fwd * 0.03, fwd, out, (0, 0, 1), (0.035, 0.028, 0.07), "spine_03", bevel=0.006), (0.07, 0.07, 0.075))
    else:                           # a knife in its sheath, at the hip
        at = np.array([side * 0.15, ctx.human.joint("joint-pelvis")[1] - 0.03, ctx.z["pelvis"] - 0.15])
        hit = tree.ray_cast(Vector(at + out * 0.4), Vector(-out), 0.6)[0]
        at = np.array(hit) + out * 0.014 if hit is not None else at
        gear(ctx, box(ctx, "Sheath", at, fwd, out, (0, 0, 1), (0.04, 0.02, 0.2), "thigh_" + s, bevel=0.007), color)
        gear(ctx, box(ctx, "Hilt", at + np.array([0, 0, 0.14]), fwd, out, (0, 0, 1), (0.028, 0.02, 0.09), "thigh_" + s, bevel=0.007), (0.3, 0.22, 0.12))


def wear_pouches(ctx, sides=(1.0, -1.0), color=(0.2, 0.21, 0.17)):
    """Pouches on the belt, at the hips."""
    tree = _clothes(ctx)
    for k, side in enumerate(sides):
        out = _unit([side, -0.35, 0.0])
        at = np.array([side * 0.12, ctx.human.joint("joint-pelvis")[1] - 0.05, ctx.z["pelvis"] + 0.035])
        hit = tree.ray_cast(Vector(at + out * 0.4), Vector(-out), 0.6)[0]
        at = np.array(hit) + out * 0.024 if hit is not None else at
        x = _unit(np.cross([0, 0, 1], out))
        gear(ctx, box(ctx, "Pouch%d" % k, at, x, out, (0, 0, 1), (0.085, 0.045, 0.095), "pelvis", bevel=0.012), color)
        gear(ctx, box(ctx, "PouchFlap%d" % k, at + out * 0.025 + np.array([0, 0, 0.022]), x, out, (0, 0, 1), (0.088, 0.008, 0.05), "pelvis", bevel=0.003), tuple(c * 0.8 for c in color))


def wear_kneepad(ctx, side=1.0, color=(0.08, 0.08, 0.085)):
    """A hard knee pad strapped on over the trousers."""
    s = "l" if side > 0 else "r"
    tree = _clothes(ctx)
    hip, knee, ankle = (ctx.human.joint("joint-%s-%s" % (s, j)) for j in ("upper-leg", "knee", "ankle"))
    up = _unit(hip - ankle)
    front = np.array([0.0, -1.0, 0.0])
    right = _unit(np.cross(up, front))
    gear(ctx, patch(ctx, "KneePad" + s, tree, knee + front * 0.07 - up * 0.005, right, up, 0.15, 0.15, 8, 8, axis=knee, offset=0.008, thick=0.014, round_=0.9, reach=0.14), color)
    for d in (0.05, -0.06):
        c = knee + up * d
        gear(ctx, patch(ctx, "KneeStrap%s%d" % (s, int(d * 100)), tree, c + front * 0.07, right, up, 0.0, 0.03, 28, 1, axis=c, offset=0.004, thick=0.003, closed=True, reach=0.12), (0.3, 0.29, 0.26))


def fluff(ob, strength=0.01, size=0.03):
    """Roughens a surface: the deep pile of a fleece, the folds of a scarf."""
    tex = bpy.data.textures.new("fluff", "CLOUDS")
    tex.noise_scale = size
    mod = ob.modifiers.new("Displace", "DISPLACE")
    mod.texture = tex
    mod.strength = strength
    mod.mid_level = 0.4
    apply_modifier(ob, mod)


def wear_scarf(ctx, color, name="Scarf", **look):
    """A cowl round the neck, in soft folds."""
    at = ctx.human.joint("joint-neck") + np.array([0.0, 0.01, 0.0])
    tree = surface_of([ctx.objects[n] for n in ("Body", "Tee") if n in ctx.objects])
    ob = patch(ctx, name, tree, at + np.array([0.0, -0.08, -0.01]), (1, 0, 0), (0, 0, 1), 0.0, 0.12, 36, 6, axis=at, offset=0.006, thick=0.0, closed=True,
               swell=lambda s, t: 0.018 * math.sin(math.pi * (t * 0.5 + 0.5)) + 0.006 * (1.0 - t))
    subdivide(ob, 1)
    fluff(ob, 0.012, 0.035)
    thicken(ob, 0.004)
    ctx.materials[name] = dict(kind="cloth", fabric="knit", color=color, **look)
    tint(ob, color)
    return ob


def wear_beanie(ctx, color, name="Beanie", slouch=0.035, **look):
    """A knitted hat pulled down to the brow, loose at the back."""
    body = ctx.objects["Body"]
    tree = surface_of([body])
    scalp = coords(body)[sorted({v for f in ctx.scalp_faces for v in body.data.polygons[f].vertices})]
    c = scalp.mean(axis=0) + np.array([0.0, 0.0, -0.01])
    nu, nv = 32, 10
    verts, faces, uvs = [], [], []
    for j in range(nv + 1):
        t = j / nv
        for i in range(nu):
            a = 2.0 * math.pi * i / nu
            frontness = 0.5 - 0.5 * math.cos(a)            # 0 at the back, 1 at the front (a = pi faces -y)
            e0 = -0.3 + 0.5 * frontness                    # the rim: over the brow in front, down on the nape behind
            e = e0 + (1.5 - e0) * t
            d = np.array([math.cos(e) * math.sin(a), math.cos(e) * math.cos(a), math.sin(e)])
            hit = tree.ray_cast(Vector(c + d * 0.4), Vector(-d), 0.6)[0]
            p = (np.array(hit) if hit is not None else c + d * 0.1) + d * (0.014 + 0.004 * (1.0 - t))
            loose = _step(np.array([t]), 0.35, 0.9)[0] * (1.0 - frontness)
            p = p + np.array([0.0, slouch * 1.3, -slouch * 0.35]) * loose + d * slouch * 0.5 * loose
            verts.append(p)
    top = len(verts)
    verts.append(np.mean(verts[-nu:], axis=0) + np.array([0.0, 0.004, 0.004]))
    for j in range(nv):
        for i in range(nu):
            a, b = j * nu + i, j * nu + (i + 1) % nu
            faces.append([a, b, b + nu, a + nu])
            uvs.append([(i / nu, j / nv), ((i + 1) / nu, j / nv), ((i + 1) / nu, (j + 1) / nv), (i / nu, (j + 1) / nv)])
    for i in range(nu):
        faces.append([nv * nu + i, nv * nu + (i + 1) % nu, top])
        uvs.append([(i / nu, 1.0), ((i + 1) / nu, 1.0), (0.5, 1.0)])
    ob = new_object(ctx, name, verts, faces, uvs)
    subdivide(ob, 2)
    fluff(ob, 0.004, 0.05)
    thicken(ob, 0.005)
    bind(ctx, ob)
    ctx.materials[name] = dict(kind="cloth", fabric="knit", color=color, **look)
    tint(ob, color)
    # Its turned-up band, round the rim.
    eye = ctx.human.joint("joint-l-eye")
    band = patch(ctx, name + "Band", surface_of([ob]), c + np.array([0.0, -0.1, eye[2] + 0.045 - c[2]]), (1, 0, 0), (0, 0, 1), 0.0, 0.045, 36, 2,
                 axis=np.array([c[0], c[1], eye[2] + 0.045]), offset=0.004, thick=0.005, closed=True)
    attach(ctx, name, band, tuple(x * 0.85 for x in color))
    return ob


def wear_pack(ctx, color=(0.22, 0.24, 0.2), size=(0.27, 0.12, 0.36), strap_color=(0.12, 0.12, 0.12), chest=True):
    """A rucksack: the bag on the back, its straps over the shoulders and one across the chest."""
    tree = _clothes(ctx)
    neck_y = ctx.human.joint("joint-neck")[1]
    for side in (1.0, -1.0):
        mid = np.array([side * 0.105, neck_y + 0.03, ctx.z["neck"] - 0.13])
        ob = patch(ctx, "PackStrap%d" % side, tree, mid + np.array([0.0, 0.0, 0.12]), (0, -1, 0), (1, 0, 0), 0.12 * 4.6, 0.04, 30, 1, axis=mid, offset=0.006, thick=0.005, reach=0.3)
        gear(ctx, ob, strap_color)
    if chest:
        z = ctx.z["neck"] - 0.15
        mid = np.array([0.0, neck_y + 0.03, z])
        ob = patch(ctx, "ChestStrap", tree, mid + np.array([0.0, -0.1, 0.0]), (1, 0, 0), (0, 0, 1), 0.3, 0.025, 20, 1, axis=mid, offset=0.012, thick=0.004, reach=0.22)
        gear(ctx, ob, strap_color)
        gear(ctx, box(ctx, "ChestClip", np.array(tree.ray_cast(Vector((0.0, -0.6, z)), Vector((0, 1, 0)), 1.0)[0]) + np.array([0.0, -0.016, 0.0]), (1, 0, 0), (0, -1, 0), (0, 0, 1), (0.035, 0.01, 0.03), "spine_03", bevel=0.003), (0.05, 0.05, 0.05))
    back = tree.ray_cast(Vector((0.0, 0.6, ctx.z["neck"] - 0.22)), Vector((0.0, -1.0, 0.0)), 1.0)[0]
    at = np.array([0.0, (back[1] if back is not None else 0.12) + size[1] * 0.5 + 0.005, ctx.z["neck"] - 0.24])
    x, y, z = np.array([1.0, 0.0, 0.0]), np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.0, 1.0])
    gear(ctx, box(ctx, "Pack", at, x, y, z, size, "spine_03", bevel=0.04), color)
    gear(ctx, box(ctx, "PackPocket", at + y * (size[1] * 0.5 + 0.02) - z * size[2] * 0.14, x, y, z, (size[0] * 0.72, 0.05, size[2] * 0.46), "spine_03", bevel=0.02), tuple(c * 0.88 for c in color))
    gear(ctx, lathe(ctx, "Bedroll", at + z * (size[2] * 0.5 + 0.045) - x * 0.17, x, [(0.0, 0.03), (0.01, 0.05), (0.33, 0.05), (0.34, 0.03)], "spine_03"), (0.36, 0.33, 0.26))
