# Предметы лута из набора Kevin Iglesias (GunsAndProps.blend): пистолет, автомат, каска — отдельные .glb,
# лежат на земле (центр снизу, ось Y вверх glTF). Запуск: python -I loot_items.py GunsAndProps.blend Textures/палитра.png outdir
import bpy, sys, os
from mathutils import Vector, Matrix
BL, PAL, OUT = sys.argv[-3:]
ITEMS = {'Human_GunR': 'loot_pistol', 'Human_AssaultRifle': 'loot_rifle', 'Human_SoldierHelmet': 'loot_helmet'}
bpy.ops.wm.open_mainfile(filepath=BL)
img = bpy.data.images.load(PAL)
for name, out in ITEMS.items():
    src = bpy.data.objects.get(name) or bpy.data.objects.get(name.rstrip('R'))
    if src is None:
        print('MISSING', name); continue
    me = src.data.copy()
    me.transform(Matrix.Diagonal(src.matrix_world.to_scale()).to_4x4())
    vs = [v.co for v in me.vertices]
    ext = [max(v[i] for v in vs) - min(v[i] for v in vs) for i in range(3)]
    ctr = Vector([(max(v[i] for v in vs) + min(v[i] for v in vs)) / 2 for i in range(3)])
    me.transform(Matrix.Translation(-ctr))
    # лёжа на боку: самая тонкая ось — вверх (Blender Z)
    thin = ext.index(min(ext))
    if thin == 0: me.transform(Matrix.Rotation(1.5708, 4, 'Y'))
    elif thin == 1: me.transform(Matrix.Rotation(1.5708, 4, 'X'))
    if 'Helmet' in name:
        me = src.data.copy(); me.transform(Matrix.Diagonal(src.matrix_world.to_scale()).to_4x4())
        vs = [v.co for v in me.vertices]
        ctr = Vector([(max(v[i] for v in vs) + min(v[i] for v in vs)) / 2 for i in range(3)])
        me.transform(Matrix.Translation(-ctr))
    zmin = min(v.co.z for v in me.vertices)
    me.transform(Matrix.Translation((0, 0, -zmin)))
    mat = bpy.data.materials.new(out); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
    tx = nt.nodes.new('ShaderNodeTexImage'); tx.image = img; tx.interpolation = 'Closest'
    nt.links.new(tx.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.6
    me.materials.clear(); me.materials.append(mat)
    for o in list(bpy.context.scene.objects): o.select_set(False)
    ob = bpy.data.objects.new(out, me); bpy.context.scene.collection.objects.link(ob)
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, out + '.glb'), export_format='GLB', use_selection=True,
                              export_image_format='JPEG', export_jpeg_quality=85, export_animations=False)
    print('LOOT', out, [round(e, 3) for e in ext])
