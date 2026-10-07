# Реалистичный солдат: Rocketbox Military_Male_03 (MIT) + анимации Kevin Iglesias «Human Soldier Animations FREE»
# (ходьба/бег в 8 направлениях, прицел/выстрел/перезарядка автомата и др.). Перенос между скелетами:
#  1) Rocketbox ставится в позу источника (направления костей) и эта поза становится «покоем» (с деформацией меша);
#  2) для каждого кадра мировой поворот цели = (мировая поворот источника × обратный поворот покоя источника) × покой цели.
# Запуск: python -I build_soldier_ki.py <папка_аватара_Rocketbox> <папка_Animations/Male> <выход.glb>
import bpy, sys, os, math
from mathutils import Matrix, Quaternion, Vector
SRC, ANIMS, OUT = sys.argv[-3:]
MODEL = ANIMS.replace('Animations/Male', 'Models/HumanM_Model.fbx')
# Ноги и корпус — живой мокап Rocketbox (тот же скелет: копируется мировой поворот каждой кости);
# у бега Iglesias таз стоит на одной высоте, ноги «пружинят» — для ходьбы/бега он не годится.
RB_ANIMS = os.environ.get('RB_ANIMS', '')
RB_CLIPS = {'Idle': 'm_idle_neutral_01', 'WalkSlow': 'm_walk_slow_01', 'Walk': 'm_walk_neutral_01', 'WalkFast': 'm_walk_fast_01',
            'RunSlow': 'm_run_slow_01', 'Run': 'm_run_neutral_01', 'RunFast': 'm_run_fast_01'}
SPEEDS = {}
CLIPS = {   # Iglesias: поза с автоматом (верх тела), выстрел, перезарядка, военная стойка
    'MilIdle': 'Idles/HumanM@MilitaryIdle01',
    'AimAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Aim01', 'ShootAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Aim01_Shoot01',
    'ReloadAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Reload01',
}
# Rocketbox-кость -> кость Iglesias (None = сам объект-арматура: таз). Пары идут родитель → потомок.
PAIRS = [('Pelvis', None), ('Spine', 'B-spine'), ('Spine1', 'B-spine+chest'), ('Spine2', 'B-chest'),
         ('Neck', 'B-neck'), ('Head', 'B-head')]
for s_, S_ in (('L', 'L'), ('R', 'R')):
    PAIRS += [(f'{s_} Clavicle', f'B-shoulder.{S_}'), (f'{s_} UpperArm', f'B-upperArm.{S_}'), (f'{s_} Forearm', f'B-forearm.{S_}'),
              (f'{s_} Hand', f'B-hand.{S_}')]
    for rb, ig in (('0', 'thumb'), ('1', 'indexFinger'), ('2', 'middleFinger'), ('3', 'ringFinger'), ('4', 'pinky')):
        PAIRS += [(f'{s_} Finger{rb}', f'B-{ig}01.{S_}'), (f'{s_} Finger{rb}1', f'B-{ig}02.{S_}'), (f'{s_} Finger{rb}2', f'B-{ig}03.{S_}')]
    PAIRS += [(f'{s_} Thigh', f'B-thigh.{S_}'), (f'{s_} Calf', f'B-shin.{S_}'), (f'{s_} Foot', f'B-foot.{S_}'), (f'{s_} Toe0', f'B-toe.{S_}')]
PFX = 'Bip01 '

bpy.ops.wm.read_factory_settings(use_empty=True)
# ---------- цель: Rocketbox ----------
name = os.path.basename(SRC.rstrip('/'))
bpy.ops.import_scene.fbx(filepath=f'{SRC}/Export/{name}.fbx')
for o in list(bpy.data.objects):
    if o.type == 'EMPTY': bpy.data.objects.remove(o)
for img in bpy.data.images:
    p = f'{SRC}/Textures/{os.path.basename(img.filepath)}'
    if os.path.exists(p):
        img.filepath = p; img.reload()
        if img.size[0] > 1024: img.scale(1024, 1024)
for m in bpy.data.materials:
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE' and n.image and 'specular' in os.path.basename(n.image.filepath).lower(): nt.nodes.remove(n)
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links): nt.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0; n.inputs['Roughness'].default_value = 0.85
tgt = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in bpy.data.objects: o.animation_data_clear()
tgt.rotation_euler[2] += math.pi        # лицом в -Z glTF (+Y Blender), как прежний боец
bpy.ops.object.select_all(action='SELECT'); bpy.context.view_layer.objects.active = tgt
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for a in list(bpy.data.actions): bpy.data.actions.remove(a)

# ---------- источник: покой (из модели Iglesias) ----------
before = set(bpy.data.objects)
bpy.ops.import_scene.fbx(filepath=MODEL)
newo = set(bpy.data.objects) - before
src0 = [o for o in newo if o.type == 'ARMATURE'][0]
RZ = Quaternion((0, 0, 1), math.pi)     # источник смотрит в -Y, наша цель — в +Y: поворачиваем все данные источника на 180° вокруг Z
def qof(M):
    return M.decompose()[1]       # поворот матрицы с масштабом (to_quaternion на масштабированной матрице неточен)
def wrot(arm, bname):      # мировой поворот кости (в покое), для None — объект
    if bname is None: return RZ @ qof(arm.matrix_world)
    return RZ @ qof(arm.matrix_world @ arm.data.bones[bname].matrix_local)
def ydir(arm, bname):
    if bname is None: return (arm.matrix_world.to_3x3().normalized() @ Vector((0, 0, 1))).normalized()
    return (arm.matrix_world.to_3x3() @ arm.data.bones[bname].matrix_local.to_3x3() @ Vector((0, 1, 0))).normalized()
def src_rest(arm, key):
    if key == 'B-spine+chest':
        return wrot(arm, 'B-spine').slerp(wrot(arm, 'B-chest'), 0.5)
    return wrot(arm, key)
# поворот мира: источник смотрит в -Y (лицом), Rocketbox после поворота тоже
# 1) поза покоя Rocketbox → геометрические направления костей источника
#    (у Biped ось Y кости НЕ вдоль кости, поэтому направление = от головы кости к голове следующей кости)
DIRS = [('Spine', 'Spine1', 'B-spine', ('head', 'B-chest')), ('Spine1', 'Spine2', 'B-chest', ('tail', 'B-chest')),
        ('Spine2', 'Neck', 'B-chest', ('tail', 'B-chest')), ('Neck', 'Head', 'B-neck', ('tail', 'B-neck'))]
for S_ in 'LR':
    DIRS += [(f'{S_} Clavicle', f'{S_} UpperArm', f'B-shoulder.{S_}', ('head', f'B-upperArm.{S_}')),
             (f'{S_} UpperArm', f'{S_} Forearm', f'B-upperArm.{S_}', ('head', f'B-forearm.{S_}')),
             (f'{S_} Forearm', f'{S_} Hand', f'B-forearm.{S_}', ('head', f'B-hand.{S_}')),
             (f'{S_} Hand', f'{S_} Finger2', f'B-hand.{S_}', ('head', f'B-middleFinger01.{S_}')),
             (f'{S_} Thigh', f'{S_} Calf', f'B-thigh.{S_}', ('head', f'B-shin.{S_}')),
             (f'{S_} Calf', f'{S_} Foot', f'B-shin.{S_}', ('head', f'B-foot.{S_}')),
             (f'{S_} Foot', f'{S_} Toe0', f'B-foot.{S_}', ('head', f'B-toe.{S_}'))]
def src_dir(frm, to):
    h = src0.matrix_world @ src0.data.bones[frm].head_local
    kind, nm = to
    p = src0.matrix_world @ (src0.data.bones[nm].head_local if kind == 'head' else src0.data.bones[nm].tail_local)
    return (RZ @ (p - h)).normalized()
def tgt_dir(b, c):
    return (tgt.pose.bones[PFX + c].head - tgt.pose.bones[PFX + b].head).normalized()
bpy.context.view_layer.objects.active = tgt
bpy.ops.object.mode_set(mode='POSE')
for b_, c_, frm, to in DIRS:
    pb = tgt.pose.bones[PFX + b_]
    q = tgt_dir(b_, c_).rotation_difference(src_dir(frm, to))
    head = pb.head.copy()
    pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode='OBJECT')
# 2) бейк деформации в меш и «применить позу как покой»
for me_ in meshes:
    bpy.context.view_layer.objects.active = me_
    for md in list(me_.modifiers):
        if md.type == 'ARMATURE':
            bpy.ops.object.modifier_apply(modifier=md.name)
bpy.context.view_layer.objects.active = tgt
bpy.ops.object.mode_set(mode='POSE'); bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
for me_ in meshes:
    md = me_.modifiers.new('Armature', 'ARMATURE'); md.object = tgt
    me_.parent = tgt
bpy.context.view_layer.update()
# проверка: разница направлений
bad = 0
for b_, c_, frm, to in DIRS:
    ang = math.degrees(tgt_dir(b_, c_).angle(src_dir(frm, to)))
    if ang > 6: bad += 1; print('ALIGN?', b_, round(ang, 1))
print('ALIGN done, bad', bad)
if os.environ.get('KI_DEBUG'):
    for n in ('Pelvis','Spine','Spine1','Spine2','Neck','Head','L UpperArm','L Hand','L Thigh','L Foot'):
        b = tgt.data.bones[PFX + n]; print('REST', n, [round(x, 3) for x in b.head_local])
    for n in ('B-spine','B-chest','B-neck','B-head','B-hand.L'):
        b = src0.data.bones[n]; print('SREST', n, [round(x, 3) for x in (src0.matrix_world @ b.head_local)], 'Y', [round(x, 2) for x in (src0.matrix_world.to_3x3().normalized() @ b.matrix_local.to_3x3() @ Vector((0, 1, 0)))])
    sys.exit()

# ---------- покой цели ----------
bones_t = tgt.data.bones
def trest(rb): return qof(tgt.matrix_world @ bones_t[PFX + rb].matrix_local)
TREST = {rb: trest(rb) for rb, ig in PAIRS}
SREST = {rb: src_rest(src0, ig) for rb, ig in PAIRS}
parent_of = {}
for rb, ig in PAIRS:
    p = bones_t[PFX + rb].parent
    parent_of[rb] = p.name[len(PFX):] if p and p.name[len(PFX):] in TREST else None
# локальный покой (в осях родителя): L_rest = W_rest(p)^-1 · W_rest(b)
# для кости без «своего» родителя в списке берём родителя из арматуры (Spine для бёдер — как в Rocketbox)
def full_parent(rb):
    p = bones_t[PFX + rb].parent
    return p.name[len(PFX):] if p else None
WR = {}   # мировые повороты покоя всех костей цели
for b in bones_t: WR[b.name[len(PFX):]] = qof(tgt.matrix_world @ b.matrix_local)
hipsH = bones_t[PFX + 'Pelvis'].head_local.z

def bake(clip, fn):
    before_o = set(bpy.data.objects); before_a = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=f'{ANIMS}/{fn}.fbx')
    new = set(bpy.data.objects) - before_o
    src = [o for o in new if o.type == 'ARMATURE'][0]
    act = src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    k = hipsH / (src0.matrix_world.translation.z if src0.matrix_world.translation.z > 0.3 else 0.98)
    # источник на кадре f0: поза «покоя» для сдвига таза
    sc = bpy.context.scene
    sc.frame_set(f0)
    hips0 = src.matrix_world.translation.copy()
    tgt.animation_data_create()
    nact = bpy.data.actions.new(clip); tgt.animation_data.action = nact
    maxang = 0.0
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        D = {}
        for rb, ig in PAIRS:
            if ig is None: qs = RZ @ qof(src.matrix_world)
            elif ig == 'B-spine+chest':
                qs = (RZ @ qof(src.matrix_world @ src.pose.bones['B-spine'].matrix)).slerp(RZ @ qof(src.matrix_world @ src.pose.bones['B-chest'].matrix), 0.5)
            else: qs = RZ @ qof(src.matrix_world @ src.pose.bones[ig].matrix)
            D[rb] = qs @ SREST[rb].inverted()
        if f == f0:
            maxang = max(D[rb].angle for rb in D)
        # желаемые мировые повороты цели; для костей вне списка — наследуют от родителя (поворот 1 в локальном)
        W = {}
        order = ['Pelvis'] + [rb for rb, ig in PAIRS if rb != 'Pelvis']
        for b in bones_t:
            n = b.name[len(PFX):]
            if n in D: W[n] = D[n] @ TREST[n]
        for rb in order:
            pn = full_parent(rb)
            # мировой поворот родителя в позе: если родитель в списке — W, иначе покой (не двигается) либо унаследованный
            if pn is None: Wp = None
            else:
                Wp = W.get(pn)
                if Wp is None:
                    # родитель вне списка: его мировой поворот в позе = покой (его родители могут двигаться, пренебрегаем)
                    Wp = WR[pn]
            Wb = W[rb]
            Lrest = (WR[pn].inverted() @ WR[rb]) if pn is not None else WR[rb]
            Pq = Lrest.inverted() @ ((Wp.inverted() @ Wb) if Wp is not None else Wb)
            pb = tgt.pose.bones[PFX + rb]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = Pq
            pb.keyframe_insert('rotation_quaternion', frame=f)
        # положение таза: сдвиг источника × масштаб, в осях покоя кости
        dpos = (RZ @ (src.matrix_world.translation - hips0)) * k
        dpos = Vector((dpos.x, dpos.y, dpos.z))
        pbh = tgt.pose.bones[PFX + 'Pelvis']
        pbh.location = WR['Pelvis'].inverted() @ dpos
        pbh.keyframe_insert('location', frame=f)
    print('CLIP', clip, fn.split('/')[-1], f0, f1, 'D0 max angle deg', round(math.degrees(maxang), 1))
    tgt.animation_data.action = None
    nact.name = clip
    t = tgt.animation_data.nla_tracks.new(); t.name = clip; t.strips.new(clip, f0, nact)
    for o in new: bpy.data.objects.remove(o)
def bake_rb(clip, fn):
    before_o = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=f'{RB_ANIMS}/{fn}.fbx')
    new = set(bpy.data.objects) - before_o
    src = [o for o in new if o.type == 'ARMATURE'][0]
    act = src.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    sc = bpy.context.scene
    fps = sc.render.fps
    names = [b.name[len(PFX):] for b in bones_t if b.name in src.pose.bones]
    order = [b.name[len(PFX):] for b in bones_t if b.name in src.pose.bones]   # data.bones уже от родителя к детям
    pos = []
    frames = list(range(f0, f1 + 1))
    tgt.animation_data_create()
    nact = bpy.data.actions.new(clip); tgt.animation_data.action = nact
    for f in frames:
        sc.frame_set(f)
        W = {n: RZ @ qof(src.matrix_world @ src.pose.bones[PFX + n].matrix) for n in names}
        for rb in order:
            pn = full_parent(rb)
            Wp = W.get(pn, WR.get(pn)) if pn is not None else None
            Lrest = (WR[pn].inverted() @ WR[rb]) if pn is not None else WR[rb]
            Pq = Lrest.inverted() @ ((Wp.inverted() @ W[rb]) if Wp is not None else W[rb])
            pb = tgt.pose.bones[PFX + rb]
            pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = Pq
            pb.keyframe_insert('rotation_quaternion', frame=f)
        pos.append(RZ @ (src.matrix_world @ src.pose.bones[PFX + 'Pelvis'].head))
    # на месте: убираем путь вперёд (линейный), скорость клипа = путь / время
    drift = pos[-1] - pos[0]; drift.z = 0.0
    T = (frames[-1] - frames[0]) / fps
    SPEEDS[clip] = round(drift.length / T, 4) if T > 0 else 0.0
    rest_h = tgt.data.bones[PFX + 'Pelvis'].head_local
    pbh = tgt.pose.bones[PFX + 'Pelvis']
    for i, f in enumerate(frames):
        p = pos[i] - drift * (i / max(1, len(frames) - 1))
        d = Vector((p.x - pos[0].x, p.y - pos[0].y, p.z)) - Vector((0, 0, rest_h.z))   # высота — как в записи
        pbh.location = WR['Pelvis'].inverted() @ d
        pbh.keyframe_insert('location', frame=f)
    print('RBCLIP', clip, fn, f0, f1, 'speed', SPEEDS[clip])
    tgt.animation_data.action = None
    t = tgt.animation_data.nla_tracks.new(); t.name = clip; t.strips.new(clip, f0, nact)
    for o in new: bpy.data.objects.remove(o)
if RB_ANIMS:
    for clip, fn in RB_CLIPS.items():
        bake_rb(clip, fn)
for clip, fn in CLIPS.items():
    bake(clip, fn)
import json
json.dump(SPEEDS, open(OUT.replace('.glb', '_speeds.json'), 'w'))
for o in list(newo): bpy.data.objects.remove(o)
# вернуть позу в покой: экспортёр берёт «узлы» кадра, и остаток позы последнего клипа превращался в «покой» скелета
for pb in tgt.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS',
                          export_image_format='JPEG', export_jpeg_quality=85)
