# Реалистичный солдат: Rocketbox Military_Male_03 (MIT) + родной мокап Rocketbox (тот же скелет Biped — без переноса).
# Клипы запекаются на скелет персонажа через Copy Rotation/Location в мировых координатах.
# Запуск: python -I build_soldier_rb.py <папка_аватара> <папка_клипов> <выход.glb>
import bpy, sys, os, math
SRC, ANIMS, OUT = sys.argv[-3:]
CLIPS = {'Idle': 'm_idle_neutral_01', 'WalkSlow': 'm_walk_slow_01', 'Walk': 'm_walk_neutral_01',
         'RunSlow': 'm_run_slow_01', 'Run': 'm_run_neutral_01'}
bpy.ops.wm.read_factory_settings(use_empty=True)
name = os.path.basename(SRC.rstrip('/'))
bpy.ops.import_scene.fbx(filepath=f'{SRC}/Export/{name}.fbx')
for o in list(bpy.data.objects):
    if o.type == 'EMPTY':
        bpy.data.objects.remove(o)
for img in bpy.data.images:
    p = f'{SRC}/Textures/{os.path.basename(img.filepath)}'
    if os.path.exists(p):
        img.filepath = p; img.reload()
        if img.size[0] > 1024:
            img.scale(1024, 1024)
for m in bpy.data.materials:
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE' and n.image and 'specular' in os.path.basename(n.image.filepath).lower():
            nt.nodes.remove(n)
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links): nt.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0
            n.inputs['Roughness'].default_value = 0.85
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
for o in bpy.data.objects:
    o.animation_data_clear()
arm.rotation_euler[2] += math.pi            # лицом в -Z glTF (как прежний боец)
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
sc = bpy.context.scene
arm.animation_data_create()
for clip, fn in CLIPS.items():
    before = set(bpy.data.objects); before_a = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=f'{ANIMS}/{fn}.fbx')
    new = list(set(bpy.data.objects) - before)
    src = [o for o in new if o.type == 'ARMATURE'][0]
    piv = bpy.data.objects.new('piv', None); sc.collection.objects.link(piv)
    piv.rotation_euler[2] = math.pi
    src.parent = piv
    act = [a for a in bpy.data.actions if a not in before_a and src.animation_data and a == src.animation_data.action]
    act = act[0] if act else src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    cons = []
    for pb in arm.pose.bones:
        if pb.name in src.pose.bones:
            c = pb.constraints.new('COPY_ROTATION'); c.target = src; c.subtarget = pb.name; cons.append((pb, c))
            if pb.name == 'Bip01 Pelvis':
                c2 = pb.constraints.new('COPY_LOCATION'); c2.target = src; c2.subtarget = pb.name; cons.append((pb, c2))
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True); bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False, visual_keying=True,
                     clear_constraints=True, use_current_action=False, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    baked = arm.animation_data.action
    baked.name = clip
    t = arm.animation_data.nla_tracks.new(); t.name = clip
    t.strips.new(clip, f0, baked)
    arm.animation_data.action = None
    print('CLIP', clip, fn, f0, f1, 'fps', sc.render.fps)
    for o in new: bpy.data.objects.remove(o)
    bpy.data.objects.remove(piv)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS',
                          export_image_format='JPEG', export_jpeg_quality=85)
