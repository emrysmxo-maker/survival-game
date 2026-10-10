# Быстрый показ героя в позе покоя (без игры): рендеры во весь рост и лица → <out>/rest_*.png
#   /tmp/claude-0/blender/v/bin/python -I tools/character/hero_show.py [hero.glb] [out_dir]
import sys
GLB = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/character/hero.glb"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/claude-0/hero"
import bpy, math, os
GLB = os.path.abspath(GLB); os.makedirs(OUT, exist_ok=True)
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
if arm.animation_data:
    for tr in list(arm.animation_data.nla_tracks): arm.animation_data.nla_tracks.remove(tr)
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.rotation_mode="QUATERNION"; pb.rotation_quaternion=(1,0,0,0); pb.location=(0,0,0)
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 24; sc.cycles.use_denoising = True
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.7, 0.75, 0.8, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.data.energy = 3.0; sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
for nm, pos, tgt, lens, rx, ry in (("front", (0.3, -4.2, 1.1), (0, 0, 0.92), 50, 500, 700), ("face", (0.25, -0.75, 1.68), (0, -0.04, 1.64), 70, 600, 600), ("face2", (0.6, -0.6, 1.66), (0, -0.03, 1.64), 70, 600, 600)):
    sc.render.resolution_x, sc.render.resolution_y = rx, ry
    cam.location = Vector(pos); cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat("-Z", "Y").to_euler(); cam.data.lens = lens
    sc.render.filepath = os.path.join(OUT, "rest_%s.png") % nm
    bpy.ops.render.render(write_still=True)
