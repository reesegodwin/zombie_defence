# Shared helpers for the Blender model scripts in this folder.
#
# Each model script builds one prop out of bevelled parts with a colour per
# part, bakes ambient occlusion into those colours (so the creases and the
# undersides come out darker), and exports res://assets/models/<name>.glb.
# The game reads the .glb's mesh in place of the one it builds in code
# (scripts/models.gd), so it keeps its own materials, snow and lighting.
#
# Coordinates are the game's (Godot's): y is up, guns point down +z. The
# export keeps them as they are (no y-up conversion), and rotations are
# Godot's Euler order (YXZ), so numbers can be copied from the GDScript.
#
# Colours are the same sRGB values as in the GDScript; they're stored raw and
# the game's materials read them as sRGB, just as they do the code meshes.
#
# Needs Blender's Python module (pip install bpy). From the project folder:
#   python3 tools/blender/<model>.py            builds and exports the model
#   python3 tools/blender/<model>.py --preview  also renders a preview into shots/
import math
import os
import sys

import bpy
import bmesh

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")

_parts = []


def reset():
    """An empty scene, ready for a new model."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _parts.clear()


def _colour(obj, col):
    me = obj.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    c = (col[0], col[1], col[2], 1.0)
    for d in attr.data:
        d.color = c


def _place(obj, pos, rot):
    obj.rotation_mode = "ZXY"   # Godot's default YXZ: z turns first, then x, then y
    obj.rotation_euler = rot
    obj.location = pos


def _bevel(obj, width, segments=2):
    if width <= 0.0:
        return
    m = obj.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segments
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    m.harden_normals = True
    m.use_clamp_overlap = True


def box(pos, size, col, rot=(0, 0, 0), bevel=0.0, segments=2):
    """A box centred on pos, size (x, y, z), turned by rot."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    _place(obj, pos, rot)
    _bevel(obj, bevel, segments)
    _colour(obj, col)
    _parts.append(obj)
    return obj


def cyl(pos, r, length, col, rot=(0, 0, 0), verts=16, r2=None, bevel=0.0, segments=2):
    """A tube along z (like Kit.cyl), radius r (r2 at the +z end), turned by rot."""
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r if r2 is None else r2, depth=length)
    obj = bpy.context.active_object
    _place(obj, pos, rot)
    _bevel(obj, bevel, segments)
    _colour(obj, col)
    _parts.append(obj)
    return obj


def tube(a, b, r, col, verts=8):
    """A round rod from point a to point b."""
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=(b - a).length)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    obj.location = (a + b) / 2
    bpy.ops.object.shade_smooth()
    _colour(obj, col)
    _parts.append(obj)
    return obj


def sphere(pos, r, col, scale=(1, 1, 1), segs=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=rings, radius=r)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    _place(obj, pos, (0, 0, 0))
    bpy.ops.object.shade_smooth()
    _colour(obj, col)
    _parts.append(obj)
    return obj


def mesh_part(verts, faces, col, smooth=False, bevel=0.0):
    """A part from raw vertices and faces (game coordinates)."""
    me = bpy.data.meshes.new("part")
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new("part", me)
    bpy.context.collection.objects.link(obj)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    _bevel(obj, bevel)
    _colour(obj, col)
    _parts.append(obj)
    return obj


def smooth(obj, angle=40):
    """Smooth shading across soft edges (curved tanks, tubes), hard past angle."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))


def _join():
    bpy.ops.object.select_all(action="DESELECT")
    for o in _parts:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.convert(target="MESH")   # applies the bevels
    for o in _parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = _parts[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = "model"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def _bake_ao(obj, strength, distance, samples):
    """Ambient occlusion into a second colour layer, then into Col."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.world = scene.world or bpy.data.worlds.new("w")
    scene.world.light_settings.distance = distance
    me = obj.data
    ao = me.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    me.color_attributes.active_color = ao
    mat = bpy.data.materials.new("bake")
    me.materials.clear()
    me.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    col = me.color_attributes["Col"]
    for c, a in zip(col.data, ao.data):
        k = 1.0 - strength * (1.0 - a.color[0])
        c.color = (c.color[0] * k, c.color[1] * k, c.color[2] * k, 1.0)
    me.color_attributes.remove(me.color_attributes["AO"])
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.materials.clear()


def export(name, ao=0.6, ao_distance=0.5, samples=64):
    """Joins the parts, bakes the AO in and writes assets/models/<name>.glb."""
    obj = _join()
    if ao > 0.0:
        _bake_ao(obj, ao, ao_distance, samples)
    # Vertex colours through a material, so the exporter writes them out.
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.append(mat)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=False, export_yup=False,
        export_vertex_color="ACTIVE", export_texcoords=False, export_materials="EXPORT",
        export_apply=True,
    )
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("wrote %s (%d triangles)" % (os.path.relpath(path, ROOT), tris))
    if "--preview" in sys.argv:
        _preview(obj, name)
    return obj


def _preview(obj, name):
    """A quick render to look at: three-quarter view, soft light."""
    from mathutils import Vector
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.62, 0.66, 1)
    scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    # Our y is up: tip the model over so Blender's z is up for the camera.
    obj.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.view_layer.update()
    pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    mid = (lo + hi) / 2
    size = (hi - lo).length
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    d = Vector((1.0, -1.3, 0.8)).normalized() * size * 1.5
    cam.location = mid + d
    cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    scene.collection.objects.link(sun)
    scene.render.filepath = os.path.join(os.environ.get("PREVIEW_DIR", os.path.join(ROOT, "shots")), name + "_preview.png")
    bpy.ops.render.render(write_still=True)
    print("preview", scene.render.filepath)
