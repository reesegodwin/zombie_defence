# Builds the survivors in Blender and exports them for the game.
#
#   blender -b -P tools/blender/build_survivors.py -- [name ...]
#   (or, with Blender as a Python module: python tools/blender/build_survivors.py [name ...])
#
# Each survivor starts from the MakeHuman base human (tools/blender/makehuman,
# CC0), shaped into one particular person, then gets a painted skin, eyes,
# hair grown strand by strand, clothes cut from the body's own surface and
# draped, and their gear. Out come assets/models/survivors/<name>.gltf (what
# the game loads) and art/survivors/<name>.blend (to open and change by hand).
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mh          # noqa: E402
import parts       # noqa: E402
import paint       # noqa: E402
from people import PEOPLE   # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
OUT_GLB = os.path.join(ROOT, "assets", "models", "survivors")
OUT_BLEND = os.path.join(ROOT, "art", "survivors")


def build(name):
    spec = PEOPLE[name]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    human = mh.Human()
    human.macro(**spec["body"])
    for target, weight in spec.get("shape", {}).items():
        human.target(target, weight)
    human.finish()
    ctx = parts.Context(human, spec, name)
    ctx.out = OUT_GLB
    parts.make_rig(ctx)
    parts.make_body(ctx)
    parts.make_eyes(ctx)
    for step in spec.get("wear", []):
        getattr(parts, "wear_" + step[0])(ctx, **(step[1] if len(step) > 1 else {}))
    parts.finish(ctx)
    paint.textures(ctx)
    os.makedirs(OUT_GLB, exist_ok=True)
    os.makedirs(OUT_BLEND, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_BLEND, name + ".blend"), compress=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_GLB, name + ".gltf"), export_format="GLTF_SEPARATE", export_apply=True, export_yup=True,
        export_skins=True, export_animations=False, export_keep_originals=True,
        export_tangents=False, export_cameras=False, export_lights=False, export_vertex_color="NONE")
    tris = sum(len(o.data.loop_triangles) or sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print("built %s: %d triangles" % (name, tris))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for who in (args or list(PEOPLE)):
        build(who)
    if os.environ.get("MAKEHUMAN_USED"):
        open(os.environ["MAKEHUMAN_USED"], "a").write("\n".join(sorted(mh.USED)) + "\n")
