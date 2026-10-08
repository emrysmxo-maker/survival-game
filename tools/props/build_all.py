# Сборка ВСЕХ построек и машин в один props.glb (текстуры общие, объекты — по именам). python -I build_all.py <props.glb>
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[-1]
sys.argv = [sys.argv[0], os.path.dirname(OUT) or '.']      # модули читают sys.argv[1] как папку вывода
import bpy
from common import reset
import houses, vehicles, rural, buildings, locs, locs2
reset()
count = 0
names = []
only = os.environ.get('ONLY')
for mod in (houses, vehicles, rural, buildings, locs, locs2):
    for nm, fn in mod.JOBS.items():
        if only and nm not in only.split(','): continue
        o = fn()
        o.name = nm
        names.append(nm); count += 1
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects: o.select_set(o.type == 'MESH')
tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_image_format='AUTO', export_jpeg_quality=82, export_apply=True)
print('моделей', count, 'полигонов', tris, 'файл', os.path.getsize(OUT) // 1024, 'КБ')
open(OUT.replace('.glb', '_names.txt'), 'w').write('\n'.join(names))
