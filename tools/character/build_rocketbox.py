# Персонаж Microsoft Rocketbox (MIT) → glb для игры: python -I build_rocketbox.py <папка_аватара> <выход.glb>
# Модель разворачивается лицом в -Z (как прежний боец Mixamo), масштаб — метры, текстуры JPEG 1024.
import bpy, sys, os, math
SRC, OUT = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
name = os.path.basename(SRC.rstrip('/'))
bpy.ops.import_scene.fbx(filepath=f'{SRC}/Export/{name}.fbx')
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o)
# текстуры: пути в FBX битые — подставляем файлы из Textures/, уменьшаем до 1024
for img in bpy.data.images:
    fn = os.path.basename(img.filepath)
    p = f'{SRC}/Textures/{fn}'
    if os.path.exists(p):
        img.filepath = p
        img.reload()
        if img.size[0] > 1024:
            img.scale(1024, 1024)
# убрать specular-текстуры (Godot их не использует как есть)
# металличность из FBX = 1 (модель выходит чёрной) — ставим 0; specular-карты убираем
for m in bpy.data.materials:
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE' and n.image and 'specular' in os.path.basename(n.image.filepath).lower():
            nt.nodes.remove(n)
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links):
                nt.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0
            n.inputs['Roughness'].default_value = 0.85
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
# в FBX есть «дубль» (ключи масштаба 0.01 на объекте) — убираем анимацию, иначе экспорт вернёт масштаб
for o in bpy.data.objects:
    o.animation_data_clear()
# лицом в -Z glTF = +Y Blender: модель смотрит в -Y → поворот на 180° вокруг Z
arm.rotation_euler[2] += math.pi
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in bpy.data.objects:
    print('OBJ', o.type, o.name, tuple(round(x, 3) for x in o.scale))
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animations=False,
                          export_image_format='JPEG', export_jpeg_quality=85)
