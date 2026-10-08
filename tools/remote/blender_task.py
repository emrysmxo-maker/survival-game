import json
from pathlib import Path
import bpy
from mathutils import Vector

out = Path.cwd() / 'remote-output'
out.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2, location=(0, 0, 0))
cube = bpy.context.object
cube.name = 'RemoteSmokeCube'
material = bpy.data.materials.new('SmokeMaterial')
material.diffuse_color = (0.15, 0.5, 0.8, 1)
cube.data.materials.append(material)
bpy.ops.object.camera_add(location=(5, -5, 4))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene = bpy.context.scene
scene.camera = camera
bpy.ops.object.light_add(type='AREA', location=(3, -4, 6))
bpy.context.object.data.energy = 800
bpy.context.object.data.shape = 'DISK'
bpy.context.object.data.size = 5
bpy.context.object.rotation_euler = (Vector((0, 0, 0)) - bpy.context.object.location).to_track_quat('-Z', 'Y').to_euler()
scene.world = bpy.data.worlds.new('SmokeWorld')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.1, 0.1, 0.1, 1)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = str(out / 'preview.png')
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'smoke.blend'))
bpy.ops.export_scene.gltf(filepath=str(out / 'smoke.glb'), export_format='GLB')
bpy.ops.render.render(write_still=True)
outputs = ['smoke.blend', 'smoke.glb', 'preview.png']
for filename in outputs:
    path = out / filename
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f'Missing output: {filename}')
report = {'status': 'ok', 'blender_version': bpy.app.version_string, 'outputs': {name: (out / name).stat().st_size for name in outputs}}
(out / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
