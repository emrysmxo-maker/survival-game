# Сборка ВСЕХ построек и машин в один props.glb (текстуры общие, объекты — по именам). python -I build_all.py <props.glb>
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[-1]
sys.argv = [sys.argv[0], os.path.dirname(OUT) or '.']      # модули читают sys.argv[1] как папку вывода
import bpy
from common import reset
import houses, vehicles, rural, buildings, locs, locs2
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'houses'))
import house as house2                      # реалистичные дома (tools/houses): оболочка + крыша «<имя>_roof»
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'cars'))
import car as cars2                         # реалистичные машины (tools/cars)
import places as places2                    # новые места (tools/houses/places.py)
import story as story2                      # сюжет: дом героя, сарай с люком, лаборатория, авиация (tools/houses/story.py)
reset()
count = 0
names = []
only = os.environ.get('ONLY')
for nm, fn in house2.JOBS.items():
    if only and nm not in only.split(','): continue
    shell, roof = fn()
    shell.name = nm
    names.append(nm); count += 1
    if roof is not None:
        roof.name = nm + '_roof'
        names.append(nm + '_roof')
for nm, fn in places2.JOBS.items():
    if only and nm not in only.split(','): continue
    shell, roof = fn()
    shell.name = nm
    names.append(nm); count += 1
    if roof is not None:
        roof.name = nm + '_roof'
        names.append(nm + '_roof')
for nm, fn in story2.JOBS.items():
    if only and nm not in only.split(','): continue
    shell, roof = fn()
    shell.name = nm
    names.append(nm); count += 1
    if roof is not None:
        roof.name = nm + '_roof'
        names.append(nm + '_roof')
for nm, fn in cars2.JOBS.items():
    if only and nm not in only.split(','): continue
    o = fn()
    o.name = nm
    names.append(nm); count += 1
for mod in (houses, vehicles, rural, buildings, locs, locs2):
    for nm, fn in mod.JOBS.items():
        if only and nm not in only.split(','): continue
        if nm in house2.JOBS or nm in cars2.JOBS: continue         # заменены новыми домами и машинами
        o = fn()
        o.name = nm
        names.append(nm); count += 1
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.objects: o.select_set(o.type == 'MESH')
tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_image_format='AUTO', export_jpeg_quality=82, export_apply=True, export_vertex_color='NAME', export_vertex_color_name='Color', export_all_vertex_colors=False, export_tangents=True)   # 'ACTIVE' в Blender 5.2 пишет пустой белый COLOR_0, краска уходила в COLOR_1 — Godot её не видел
print('моделей', count, 'полигонов', tris, 'файл', os.path.getsize(OUT) // 1024, 'КБ')
open(OUT.replace('.glb', '_names.txt'), 'w').write('\n'.join(names))
