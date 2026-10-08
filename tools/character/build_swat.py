# Боец Swat (Mixamo, скелет mixamorig) + анимации автомата Kevin Iglesias и живой мокап ходьбы/бега Rocketbox.
# Позы покоя Swat и Iglesias — обе T-поза (расхождения костей ≤ 5°), поэтому перенос — по мировым поворотам костей
# без деформации сетки: целевой поворот = (поворот источника × обратный покой источника) × покой цели.
# Запуск: python -I build_swat.py <Swat.fbx> <Animations/Male Iglesias> <выход.glb>
# Окружение: RB_ANIMS (папка записей Rocketbox), RB_MODEL (Military_Male_03/Export/Military_Male_03.fbx — T-покой Rocketbox),
#            RIFLE_HOLD (json от extract_rifle_hold.py), KI_BLEND (HumanM_SoldierAnimationsFREE_2.0.blend), SWIM (опц.: json+glb плавания)
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swat_common import *
SWAT, ANIMS, OUT = sys.argv[-3:]
MODEL = ANIMS.replace('Animations/Male', 'Models/HumanM_Model.fbx')
RB_ANIMS = os.environ.get('RB_ANIMS', '')
RB_MODEL = os.environ.get('RB_MODEL', '')
FPS = 30
RB_CLIPS = {'Idle': 'm_idle_neutral_01', 'WalkSlow': 'm_walk_slow_01', 'Walk': 'm_walk_neutral_01', 'WalkFast': 'm_walk_fast_01',
            'RunSlow': 'm_run_slow_01', 'Run': 'm_run_neutral_01', 'RunFast': 'm_run_fast_01',
            'WalkStart': 'm_walk_start', 'RunStart': 'm_run_start', 'WalkStop': 'm_walk_stop', 'RunStop': 'm_run_stop'}
CLIPS = {'MilIdle': 'Idles/HumanM@MilitaryIdle01', 'AimAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Aim01',
         'ShootAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Aim01_Shoot01', 'ReloadAR': 'Combat/AssaultRifle/HumanM@AssaultRifle_Reload01',
         'HoldAR': '../Masked Poses/HumanM@WeaponHold_AssaultRifle01'}      # поза «автомат наготове» (только руки и кисти)
for _d in ('Forward', 'Backward', 'Left', 'Right', 'ForwardLeft', 'ForwardRight', 'BackwardLeft', 'BackwardRight'):
    CLIPS['SWalk' + _d] = f'Movement/Walk/HumanM@Walk01_{_d}'
    CLIPS['SRun' + _d] = f'Movement/Run/HumanM@Run01_{_d}'
# у записей Rocketbox руки в другой позе покоя (A-поза) — берём только корпус, голову и ноги; руки в игре задаёт поза автомата
RB_KEEP = {p[0] for p in PAIRS if not any(k in p[0] for k in ('Arm', 'Hand', 'Shoulder'))}
SPEEDS = {}

tgt, meshes = load_target(SWAT)
# имена костей как в игре: mixamorig_X (Godot всё равно заменяет ':' на '_')
for b in tgt.data.bones:
    if b.name.startswith(MX): b.name = 'mixamorig_' + b.name[len(MX):]
MX = 'mixamorig_'
face_plus_y(tgt)
# материалы: без блеска/карты бликов, матовая ткань
for m in bpy.data.materials:
    if not m.node_tree: continue
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == 'TEX_IMAGE' and n.image and 'specular' in (n.image.name + n.image.filepath).lower(): nt.nodes.remove(n)
    for n in nt.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for l in list(n.inputs['Metallic'].links) + list(n.inputs['Specular IOR Level'].links) + list(n.inputs['Roughness'].links): nt.links.remove(l)
            n.inputs['Metallic'].default_value = 0.0; n.inputs['Roughness'].default_value = 0.85
bones_t = tgt.data.bones
BN = {mx: MX + mx for mx, rb, ig in PAIRS}
WR = {b.name: qof(tgt.matrix_world @ b.matrix_local) for b in bones_t}
HIPS_T = bones_t[MX + 'Hips'].head_local.z

def import_armature(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = set(bpy.data.objects) - before
    arm = [o for o in new if o.type == 'ARMATURE'][0]
    return arm, new, bpy.context.scene.render.fps / bpy.context.scene.render.fps_base

# ---------- покой источников ----------
src_ig, new_ig, _ = import_armature(MODEL)
ig_hips_rest = src_ig.matrix_world.translation.z
SREST_IG = {}
def ig_world_rest(key):
    if key == 'B-spine+chest':
        return rest_world_q(src_ig, 'B-spine', True).slerp(rest_world_q(src_ig, 'B-chest', True), 0.5)
    return rest_world_q(src_ig, key, True)
for mx, rb, ig in PAIRS:
    if ig: SREST_IG[mx] = ig_world_rest(ig)
rb_src0 = None
SREST_RB = {}
if RB_MODEL:
    rb_src0, new_rb, _ = import_armature(RB_MODEL)
    for mx, rb, ig in PAIRS:
        if mx in RB_KEEP: SREST_RB[mx] = rest_world_q(rb_src0, 'Bip01 ' + rb, True)
    RB_HIPS_REST = (RZ @ (rb_src0.matrix_world @ rb_src0.data.bones['Bip01 Pelvis'].head_local)).z
    for o in new_rb: bpy.data.objects.remove(o)

def solve_pose(frame, W):
    """W: желаемые мировые повороты mapped-костей цели → локальные повороты в позе, ключи на кадре"""
    Wp_all = {}
    for b in bones_t:
        n = b.name
        p = b.parent.name if b.parent else None
        Wp = Wp_all.get(p) if p else None
        Lrest = (WR[p].inverted() @ WR[n]) if p else WR[n]
        pb = tgt.pose.bones[n]
        pb.rotation_mode = 'QUATERNION'
        if n in W:
            Wb = W[n]
            Pq = Lrest.inverted() @ ((Wp.inverted() @ Wb) if Wp is not None else Wb)
            Wp_all[n] = Wb
        else:
            Pq = Quaternion((1, 0, 0, 0))
            Wp_all[n] = (Wp @ Lrest) if Wp is not None else Lrest
        pb.rotation_quaternion = Pq
        pb.keyframe_insert('rotation_quaternion', frame=frame)

def new_action(clip):
    tgt.animation_data_create()
    nact = bpy.data.actions.new(clip); tgt.animation_data.action = nact
    return nact
def finish(clip, nact):
    tgt.animation_data.action = None
    t = tgt.animation_data.nla_tracks.new(); t.name = clip; t.strips.new(clip, 1, nact)

def bake_ig(clip, fn):
    src, new, sfps = import_armature(f'{ANIMS}/{fn}.fbx')
    sc = bpy.context.scene
    act = src.animation_data.action
    f0, f1 = act.frame_range[0], act.frame_range[1]
    dur = (f1 - f0) / sfps
    n = int(round(dur * FPS)) + 1
    k = HIPS_T / ig_hips_rest
    sc.frame_set(int(f0)); hips0 = src.matrix_world.translation.copy()
    nact = new_action(clip)
    for i in range(n):
        sf = f0 + i / FPS * sfps
        sc.frame_set(int(math.floor(sf)), subframe=sf - math.floor(sf))
        W = {}
        for mx, rb, ig in PAIRS:
            if not ig: continue
            if ig == 'B-spine+chest':
                qs = (RZ @ qof(src.matrix_world @ src.pose.bones['B-spine'].matrix)).slerp(RZ @ qof(src.matrix_world @ src.pose.bones['B-chest'].matrix), 0.5)
            else: qs = RZ @ qof(src.matrix_world @ src.pose.bones[ig].matrix)
            W[BN[mx]] = (qs @ SREST_IG[mx].inverted()) @ WR[BN[mx]]
        solve_pose(i + 1, W)
        dpos = (RZ @ (src.matrix_world.translation - hips0)) * k
        pbh = tgt.pose.bones[MX + 'Hips']
        pbh.location = WR[MX + 'Hips'].inverted() @ Vector((dpos.x, dpos.y, dpos.z))
        pbh.keyframe_insert('location', frame=i + 1)
    print('CLIP', clip, 'frames', n, 'dur', round(dur, 2))
    finish(clip, nact)
    for o in new: bpy.data.objects.remove(o)

def bake_rb(clip, fn):
    src, new, sfps = import_armature(f'{RB_ANIMS}/{fn}.fbx')
    sc = bpy.context.scene
    act = src.animation_data.action
    f0, f1 = act.frame_range[0], act.frame_range[1]
    dur = (f1 - f0) / sfps
    n = int(round(dur * FPS)) + 1
    k = HIPS_T / RB_HIPS_REST
    nact = new_action(clip)
    Ws, pos = [], []
    for i in range(n):
        sf = f0 + i / FPS * sfps
        sc.frame_set(int(math.floor(sf)), subframe=sf - math.floor(sf))
        W = {}
        for mx, rb, ig in PAIRS:
            if mx not in RB_KEEP: continue
            qs = RZ @ qof(src.matrix_world @ src.pose.bones['Bip01 ' + rb].matrix)
            W[BN[mx]] = (qs @ SREST_RB[mx].inverted()) @ WR[BN[mx]]
        # руки: покой (в игре перекрываются позой автомата)
        for b in bones_t:
            if b.name not in W and any(kk in b.name for kk in ('Arm', 'Hand', 'Shoulder')): W[b.name] = WR[b.name]
        Ws.append(W)
        pos.append(RZ @ (src.matrix_world @ src.pose.bones['Bip01 Pelvis'].head))
    drift = pos[-1] - pos[0]; drift.z = 0.0
    SPEEDS[clip] = round(drift.length * k / dur, 4) if dur > 0 else 0.0
    for i in range(n):
        solve_pose(i + 1, Ws[i])
        p = pos[i] - drift * (i / max(1, n - 1))
        d = Vector(((p.x - pos[0].x) * k, (p.y - pos[0].y) * k, (p.z - RB_HIPS_REST) * k))
        pbh = tgt.pose.bones[MX + 'Hips']
        pbh.location = WR[MX + 'Hips'].inverted() @ d
        pbh.keyframe_insert('location', frame=i + 1)
    print('RBCLIP', clip, 'speed', SPEEDS[clip], 'dur', round(dur, 2))
    finish(clip, nact)
    for o in new: bpy.data.objects.remove(o)

if RB_MODEL and RB_ANIMS:
    for clip, fn in RB_CLIPS.items(): bake_rb(clip, fn)
for clip, fn in CLIPS.items(): bake_ig(clip, fn)
if os.environ.get('SWIM'):
    exec(open(os.environ['SWIM']).read())

# ---------- автомат на правой кисти (меш со скином, хват из .blend Iglesias) ----------
def attach_rifle():
    hold = json.load(open(os.environ['RIFLE_HOLD']))
    with bpy.data.libraries.load(os.environ['KI_BLEND']) as (sd, dd):
        dd.meshes = [hold['mesh']]
    me = dd.meshes[0]
    rifle = bpy.data.objects.new('Rifle', me); bpy.context.scene.collection.objects.link(rifle)
    mat = bpy.data.materials.new('RifleMat'); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(ANIMS.replace('Animations/Male', 'Textures/HumanAnimations_ColorPalette.png'))
    tex.interpolation = 'Closest'
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55; bsdf.inputs['Metallic'].default_value = 0.3
    me.materials.clear(); me.materials.append(mat)
    O = Matrix(hold['O'])
    C = (WR[MX + 'RightHand'].inverted() @ SREST_IG['RightHand']).to_matrix().to_4x4()
    hm = tgt.matrix_world @ bones_t[MX + 'RightHand'].matrix_local
    t, q, _ = hm.decompose()
    W = Matrix.LocRotScale(t, q, None) @ C @ O
    me.transform(W); rifle.matrix_world = tgt.matrix_world
    me.transform(tgt.matrix_world.inverted())
    rifle.parent = tgt; rifle.matrix_parent_inverse.identity()
    vg = rifle.vertex_groups.new(name=MX + 'RightHand'); vg.add(range(len(me.vertices)), 1.0, 'REPLACE')
    mod = rifle.modifiers.new('Armature', 'ARMATURE'); mod.object = tgt
    def g(v): w = W @ Vector(v); return [round(w.x, 4), round(w.z, 4), round(-w.y, 4)]
    SPEEDS['rifle'] = {'muzzle': g(hold['muzzle']), 'port': g(hold['port']), 'butt': g(hold['butt'])}
    print('RIFLE attached', SPEEDS['rifle'])
attach_rifle()
for o in list(new_ig): bpy.data.objects.remove(o)
json.dump(SPEEDS, open(OUT.replace('.glb', '_speeds.json'), 'w'))
for pb in tgt.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0); pb.scale = (1, 1, 1)
bpy.context.scene.render.fps = FPS; bpy.context.scene.render.fps_base = 1.0
bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_animation_mode='NLA_TRACKS',
                          export_image_format='JPEG', export_jpeg_quality=85)
