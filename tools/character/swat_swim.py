# Плавание Swim_Fwd/Swim_Idle: Quaternius Universal Animation Library (CC0) → скелет Swat (по мировым поворотам костей).
# Выполняется из build_swat.py (exec): использует его solve_pose/new_action/finish/WR/PAIRS и т.д.
UAL = os.environ.get('SWIM_GLB', '/tmp/claude-0/gp/ual/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb')
UMAP = {'Hips': 'DEF-hips', 'Spine': 'DEF-spine.001', 'Spine1': 'DEF-spine.002', 'Spine2': 'DEF-spine.003', 'Neck': 'DEF-neck', 'Head': 'DEF-head'}
for _s, _S in (('Left', 'L'), ('Right', 'R')):
    UMAP.update({f'{_s}Shoulder': f'DEF-shoulder.{_S}', f'{_s}Arm': f'DEF-upper_arm.{_S}', f'{_s}ForeArm': f'DEF-forearm.{_S}', f'{_s}Hand': f'DEF-hand.{_S}',
                 f'{_s}UpLeg': f'DEF-thigh.{_S}', f'{_s}Leg': f'DEF-shin.{_S}', f'{_s}Foot': f'DEF-foot.{_S}', f'{_s}ToeBase': f'DEF-toe.{_S}'})
    for _mx, _u in (('Thumb', 'thumb.0%d'), ('Index', 'f_index.0%d'), ('Middle', 'f_middle.0%d'), ('Ring', 'f_ring.0%d'), ('Pinky', 'f_pinky.0%d')):
        for _i in (1, 2, 3):
            UMAP[f'{_s}Hand{_mx}{_i}'] = 'DEF-' + (_u % _i) + '.' + _S
_before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=UAL)
_new = set(bpy.data.objects) - _before
_src = [o for o in _new if o.type == 'ARMATURE'][0]
_sc = bpy.context.scene
_sfps = _sc.render.fps / _sc.render.fps_base
_srest = {mx: rest_world_q(_src, u, True) for mx, u in UMAP.items()}
_u_hips0 = (RZ @ (_src.matrix_world @ _src.data.bones['DEF-hips'].head_local)).z
_k = HIPS_T / _u_hips0
for _clip, _an in (('Swim_Fwd', 'Swim_Fwd_Loop_Rig'), ('Swim_Idle', 'Swim_Idle_Loop_Rig')):
    _src.animation_data_create()
    for _t in list(_src.animation_data.nla_tracks): _src.animation_data.nla_tracks.remove(_t)
    _cands = [a for a in bpy.data.actions if a.name.startswith(_an)]
    print('SWIMACT', _an, [a.name for a in bpy.data.actions if 'wim' in a.name])
    _act = _cands[0]
    _src.animation_data.action = _act
    _f0, _f1 = _act.frame_range
    _dur = (_f1 - _f0) / _sfps
    _n = int(round(_dur * FPS)) + 1
    _na = new_action(_clip)
    _pos = []; _Ws = []
    for _i in range(_n):
        _sf = _f0 + _i / FPS * _sfps
        _sc.frame_set(int(math.floor(_sf)), subframe=_sf - math.floor(_sf))
        _W = {}
        for mx, u in UMAP.items():
            qs = RZ @ qof(_src.matrix_world @ _src.pose.bones[u].matrix)
            _W[MX + mx] = (qs @ _srest[mx].inverted()) @ WR[MX + mx]
        _Ws.append(_W)
        _pos.append(RZ @ (_src.matrix_world @ _src.pose.bones['DEF-hips'].head))
    for _i in range(_n):
        solve_pose(_i + 1, _Ws[_i])
        _p = _pos[_i]
        _d = Vector(((_p.x - _pos[0].x) * _k, (_p.y - _pos[0].y) * _k, (_p.z - _u_hips0) * _k))
        _pbh = tgt.pose.bones[MX + 'Hips']
        _pbh.location = WR[MX + 'Hips'].inverted() @ _d
        _pbh.keyframe_insert('location', frame=_i + 1)
    print('SWIMCLIP', _clip, _n, 'dur', round(_dur, 2))
    finish(_clip, _na)
for _o in _new: bpy.data.objects.remove(_o)
