extends SkeletonModifier3D
# Оружие в руках (автомат или пистолет). Оружие — часть модели: меши со скином на правой кисти, хват взят из .blend
# набора Kevin Iglesias. Позы рук — родные записи (скелет бойца — Mixamo, позы покоя совпадают, переноса нет):
#  автомат: HoldAR «наготове» ↔ AimAR прицел ↔ ShootAR выстрел (с отдачей из записи), ReloadAR перезарядка;
#  пистолет: MilIdle (пистолет опущен) ↔ AimPistol (двумя руками у глаз) ↔ ShootPistol, ReloadPistol.
# Поверх: корпус к позе прицела, щека к прикладу, скрутка на цель, наклон корпуса на бегу, покачивание в шаге.
# Плывёт — оружие спрятано. Работает после анимации ног.

var player

var _b := {}
var _sets := {}                    # оружие -> {hold, aim, shoot, reload: Animation, arms: [...], torso: [...], mz, bt}
var _t := 0.0
var _shoot_t := 0.0
var _ready_done := false
var _ok := false
var _dbg := OS.get_cmdline_user_args().has("--pose")   # замер позы для devtest (после всех правок модификатора)
var dbg := {}

const TORSO_W := {"Spine": 0.85, "Spine1": 0.9, "Spine2": 0.95, "Neck": 1.0, "Head": 1.0}
const CLIPS := {
	"rifle": {"hold": "HoldAR", "aim": "AimAR", "shoot": "ShootAR", "reload": "ReloadAR"},
	"pistol": {"hold": "AimPistol", "aim": "AimPistol", "shoot": "ShootPistol", "reload": "ReloadPistol"}}
const PISTOL_LOW := 0.75          # пистолет наготове: руки опущены на столько (рад) от прицела
const PISTOL_BACK := 0.12         # и ближе к груди (м)
const IDLE_LEAN := 0.08           # стоя: корпус чуть вперёд (рад)
const RUN_LEAN := 0.26            # наклон корпуса вперёд на бегу (рад, на полной скорости)
const SWAY := 0.07                # скрутка плеч в шаге (рад)
const BOB := 0.035                # покачивание оружия в шаге (рад)
const AIM_CROUCH := 0.025         # прицел: таз ниже на столько (м) — колени согнуты
const AIM_LEAN := 0.17            # прицел: корпус вперёд (рад) — «нос над носками»
const BUTT_IN := 0.05             # торец приклада: от плечевого сустава к груди (м) — «карман» плеча
const BUTT_FWD := 0.06            # и вперёд
const BUTT_DOWN := 0.02           # и чуть ниже сустава
const GRIP_FWD := 0.04            # левая рука дальше по цевью, чем в записи (м)
const EYE_FWD := 0.13             # глаз впереди торца приклада по стволу (м) — щека на гребне приклада
const EYE_OVER_BORE := 0.065      # и выше оси ствола (линия прицела)

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _track_of(a: Animation, nm: String) -> int:
	if a == null:
		return -1
	for ti in a.get_track_count():
		if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D and str(a.track_get_path(ti)).get_slice(":", 1) == nm:
			return ti
	return -1

func _setup(skel: Skeleton3D) -> void:
	_ready_done = true
	var anim: AnimationPlayer = player.anim
	if anim == null:
		return
	var to_skel: Transform3D = skel.global_transform.affine_inverse() * player.glb.global_transform
	var rh := _bone("RightHand")
	if rh < 0:
		return
	var inv := skel.get_bone_global_rest(rh).affine_inverse()
	for w in CLIPS:
		var c: Dictionary = CLIPS[w]
		var pts: Dictionary = player.rifle_pts if w == "rifle" else player.pistol_pts
		if pts.is_empty() or not anim.has_animation(c.aim):
			continue
		var st := {}
		for key in c:
			st[key] = anim.get_animation(c[key]) if anim.has_animation(c[key]) else null
		var arms := []
		var torso := []
		for bi in skel.get_bone_count():
			var full := skel.get_bone_name(bi)
			var nm := full.trim_prefix("mixamorig_")
			var ta := _track_of(st.aim, full)
			if ta < 0:
				continue
			var e := [bi, ta, _track_of(st.hold, full), _track_of(st.shoot, full), _track_of(st.reload, full)]
			if TORSO_W.has(nm):
				e.append(TORSO_W[nm])
				torso.append(e)
			elif nm.contains("Shoulder") or nm.contains("Arm") or nm.contains("Hand"):
				arms.append(e)
		st["arms"] = arms
		st["torso"] = torso
		st["mz"] = inv * (to_skel * (pts["muzzle"] as Vector3))
		st["bt"] = inv * (to_skel * (pts["butt"] as Vector3))
		_sets[w] = st
	_ok = _sets.has("rifle")

func fire() -> void:
	pass

static func _q(a: Animation, ti: int, t: float, fallback: Quaternion) -> Quaternion:
	if a == null or ti < 0:
		return fallback
	return a.rotation_track_interpolate(ti, fposmod(t, a.length))

func _process_modification() -> void:
	var skel := get_skeleton()
	if player == null or skel == null:
		return
	if not _ready_done:
		_setup(skel)
	if not _ok:
		return
	var w: String = player.weapon_kind if _sets.has(player.weapon_kind) else "rifle"
	var st: Dictionary = _sets[w]
	var rh := _bone("RightHand")
	if player.rifle_mesh:
		player.rifle_mesh.visible = not player.swimming and w == "rifle"
	if player.pistol_mesh:
		player.pistol_mesh.visible = not player.swimming and w == "pistol"
	if player.swimming:
		return
	var dt := get_process_delta_time()
	_t += dt
	var k: float = player.aim_blend
	var fb: float = player.fire_blend * k
	if fb > 0.01:
		_shoot_t += dt
	else:
		_shoot_t = 0.0
	var rl := 0.0                      # перезарядка: вся запись целиком (руки + корпус)
	var rt := 0.0
	if player.reload_t > 0.0 and st.reload != null:
		rt = clampf(1.0 - player.reload_t / player.reload_len, 0.0, 1.0) * st.reload.length
		rl = clampf(minf(player.reload_t, player.reload_len - player.reload_t) * 6.0, 0.0, 1.0)
	# 1) руки: наготове ↔ прицел ↔ выстрел, поверх — перезарядка
	for e in st.arms:
		var qa := _q(st.aim, e[1], _t, Quaternion.IDENTITY)
		var q := _q(st.hold, e[2], 0.0 if w == "rifle" else _t, qa).slerp(qa, k)
		if fb > 0.01:
			q = q.slerp(_q(st.shoot, e[3], _shoot_t, qa), fb)
		if rl > 0.0:
			q = q.slerp(_q(st.reload, e[4], rt, q), rl)
		skel.set_bone_pose_rotation(e[0], q)
	# 2) корпус, шея, голова: от шага/бега к позе прицела (выстрела)
	for e in st.torso:
		var qa := _q(st.aim, e[1], _t, Quaternion.IDENTITY)
		if fb > 0.01:
			qa = qa.slerp(_q(st.shoot, e[3], _shoot_t, qa), fb)
		var q := skel.get_bone_pose_rotation(e[0]).slerp(qa, k * e[5])
		if rl > 0.0:
			q = q.slerp(_q(st.reload, e[4], rt, q), rl * e[5])
		skel.set_bone_pose_rotation(e[0], q)
	var model: Node3D = player.model
	var m2s: Basis = skel.global_transform.basis.orthonormalized().inverse() * model.global_transform.basis.orthonormalized()
	var s2m: Basis = m2s.inverse()
	var up_s: Vector3 = (m2s * Vector3.UP).normalized()
	var fwd_s: Vector3 = (m2s * Vector3(0, 0, 1)).normalized()
	var right_s: Vector3 = (m2s * Vector3(-1, 0, 0)).normalized()     # лицо бойца — +Z модели, правая рука — −X
	# 3) живость в движении: наклон вперёд на бегу, скрутка плеч и покачивание в шаге
	var spd: float = clampf(player.anim_speed * WorldGen.T / 3.2, 0.0, 1.0) if player.moving else 0.0
	var ph := 0.0
	if player.anim and player.anim.current_animation != "" and player.anim.current_animation_length > 0.0:
		ph = player.anim.current_animation_position / player.anim.current_animation_length * TAU
	var still := (1.0 - spd) * (1.0 - k) * (1.0 - rl)
	if still > 0.01:                   # стоя: корпус не заваливается назад (в записи стойки −5°)
		_rot_global(skel, _bone("Spine"), right_s, -IDLE_LEAN * 0.5 * still)
		_rot_global(skel, _bone("Spine1"), right_s, -IDLE_LEAN * 0.5 * still)
	if spd > 0.01:
		var lean := RUN_LEAN * spd * (1.0 - 0.6 * k)
		_rot_global(skel, _bone("Spine"), right_s, -lean * 0.5)      # «+» вокруг правой оси — назад, поэтому минус
		_rot_global(skel, _bone("Spine1"), right_s, -lean * 0.5)
		_rot_global(skel, _bone("Spine2"), up_s, SWAY * spd * (1.0 - 0.7 * k) * sin(ph))
		var bob := BOB * spd * (1.0 - 0.5 * k) * sin(ph * 2.0)
		_rot_global(skel, _bone("RightShoulder"), right_s, bob)
		_rot_global(skel, _bone("LeftShoulder"), right_s, bob)
	# 4) скрутка позвоночника: ствол смотрит на цель (aim_local — на сколько ствол повёрнут относительно ног)
	var d := _barrel_m(skel, rh, s2m, st)
	if k > 0.001:
		var err_yaw := wrapf(player.aim_local - atan2(d.x, d.z), -PI, PI) * k
		for pr in [["Spine", 0.3], ["Spine1", 0.35], ["Spine2", 0.35]]:
			_rot_global(skel, _bone(pr[0]), up_s, err_yaw * pr[1])
	# 4а) стойка стрелка: колени согнуты — таз ниже, стопы на месте (IK ног, колено вперёд)
	var crouch: float = AIM_CROUCH * k * (1.0 - rl) * (0.5 if player.moving else 1.0)
	if crouch > 0.001:
		var hips := _bone("Hips")
		var legs := []
		for sd in ["Left", "Right"]:
			legs.append([_bone(sd + "UpLeg"), _bone(sd + "Leg"), _bone(sd + "Foot")])
		var feet := []
		for l in legs:
			feet.append(skel.get_bone_global_pose(l[2]))
		var hg := skel.get_bone_global_pose(hips)
		hg.origin -= up_s * crouch
		skel.set_bone_global_pose(hips, hg)
		for i in legs.size():
			var l: Array = legs[i]
			var ft: Transform3D = feet[i]
			_ik(skel, l[0], l[1], l[2], ft.origin, skel.get_bone_global_pose(l[1]).origin + fwd_s)
			var pg := skel.get_bone_global_pose(skel.get_bone_parent(l[2]))
			skel.set_bone_pose_rotation(l[2], (pg.basis.orthonormalized().inverse() * ft.basis.orthonormalized()).get_rotation_quaternion())
	# 4б) прицел из автомата как у стрелка: корпус наклонён вперёд («нос над носками»), приклад в «кармане» плеча,
	#     ствол на цель, ГОЛОВА опускается к прикладу (щека на прикладе), локти вниз. Руки ставит двухзвенный IK:
	#     правая кисть — по хвату автомата, левая — на цевье (как в записи, чуть дальше вперёд).
	var aim_k := k * (1.0 - rl) if w == "rifle" else 0.0
	if aim_k > 0.001:
		for pr in [["Spine", 0.35], ["Spine1", 0.35], ["Spine2", 0.3]]:
			_rot_global(skel, _bone(pr[0]), right_s, -AIM_LEAN * pr[1] * aim_k)
		var rh0 := skel.get_bone_global_pose(rh)
		var lh := _bone("LeftHand")
		var lh0 := skel.get_bone_global_pose(lh)
		var bt0: Vector3 = rh0 * (st.bt as Vector3)
		var z0: Vector3 = (rh0 * (st.mz as Vector3) - bt0).normalized()
		var y0: Vector3 = (up_s - z0 * z0.dot(up_s)).normalized()
		var r0 := Basis(y0.cross(z0), y0, z0)
		# куда смотрит ствол: на цель по горизонтали (aim_local — угол цели относительно ног)
		var z1: Vector3 = (m2s * Vector3(sin(player.aim_local), 0.0, cos(player.aim_local))).normalized()
		var y1: Vector3 = up_s
		var r1 := Basis(y1.cross(z1), y1, z1)
		var sh: Vector3 = skel.get_bone_global_pose(_bone("RightArm")).origin
		var chest: Vector3 = skel.get_bone_global_pose(_bone("Spine2")).origin
		var inward: Vector3 = chest - sh
		inward = (inward - up_s * inward.dot(up_s)).normalized()
		var bp: Vector3 = sh + inward * BUTT_IN + z1 * BUTT_FWD - up_s * BUTT_DOWN    # торец приклада — в плечо
		var rot: Basis = (r1 * r0.inverse()).orthonormalized()
		var rot_k := Basis(Quaternion.IDENTITY.slerp(rot.get_rotation_quaternion(), aim_k))
		var off: Vector3 = (bp - bt0) * aim_k
		var rh1 := Transform3D(rot_k * rh0.basis, bt0 + off + rot_k * (rh0.origin - bt0))
		var lh1 := Transform3D(rot_k * lh0.basis, bt0 + off + rot_k * (lh0.origin - bt0) + z1 * GRIP_FWD * aim_k)
		var down: Vector3 = -up_s
		for ch in [[_bone("RightArm"), _bone("RightForeArm"), rh, rh1, -inward * 0.45], [_bone("LeftArm"), _bone("LeftForeArm"), lh, lh1, -inward * 0.25]]:
			var tgt: Vector3 = (ch[3] as Transform3D).origin
			var mid: Vector3 = (skel.get_bone_global_pose(ch[0]).origin + tgt) * 0.5
			_ik(skel, ch[0], ch[1], ch[2], tgt, mid + down + (ch[4] as Vector3))    # локоть вниз и чуть наружу
			var pg := skel.get_bone_global_pose(skel.get_bone_parent(ch[2]))
			skel.set_bone_pose_rotation(ch[2], (pg.basis.orthonormalized().inverse() * (ch[3] as Transform3D).basis.orthonormalized()).get_rotation_quaternion())
		# щека на прикладе: глаз — над осью ствола, немного впереди торца; голову (шея + голова) поворачиваем к этой точке
		var eye := skel.find_bone("mixamorig_RightEye")
		if eye >= 0:
			var eye_t: Vector3 = bt0 + off + z1 * EYE_FWD + up_s * EYE_OVER_BORE
			for pr in [[_bone("Neck"), 0.5], [_bone("Head"), 1.0]]:
				var piv: Vector3 = skel.get_bone_global_pose(pr[0]).origin
				var e_now: Vector3 = skel.get_bone_global_pose(eye).origin - piv
				var e_want: Vector3 = eye_t - piv
				if e_now.length() < 1e-4 or e_want.length() < 1e-4:
					continue
				var q := Quaternion(e_now.normalized(), e_want.normalized())
				var ang: float = minf(q.get_angle(), deg_to_rad(40.0)) * float(pr[1]) * aim_k
				if ang > 1e-4:
					_rot_global(skel, pr[0], q.get_axis().normalized(), ang)
	# 4в) пистолет наготове: хват двумя руками как в прицеле, но кисти опущены перед грудью стволом вниз-вперёд
	var low: float = (1.0 - k) * (1.0 - rl) if w == "pistol" else 0.0
	if low > 0.001:
		var lh := _bone("LeftHand")
		var piv: Vector3 = (skel.get_bone_global_pose(_bone("RightArm")).origin + skel.get_bone_global_pose(_bone("LeftArm")).origin) * 0.5
		var rb := Basis(right_s, -PISTOL_LOW * low)
		var back: Vector3 = -fwd_s * PISTOL_BACK * low - up_s * 0.03 * low
		var tg := []
		for hb in [rh, lh]:
			var g := skel.get_bone_global_pose(hb)
			tg.append(Transform3D(rb * g.basis, piv + rb * (g.origin - piv) + back))
		for ch in [[_bone("RightArm"), _bone("RightForeArm"), rh, tg[0], -right_s * 0.4], [_bone("LeftArm"), _bone("LeftForeArm"), lh, tg[1], right_s * 0.4]]:
			var tgt: Vector3 = (ch[3] as Transform3D).origin
			var mid: Vector3 = (skel.get_bone_global_pose(ch[0]).origin + tgt) * 0.5
			_ik(skel, ch[0], ch[1], ch[2], tgt, mid - up_s + (ch[4] as Vector3))
			var pg := skel.get_bone_global_pose(skel.get_bone_parent(ch[2]))
			skel.set_bone_pose_rotation(ch[2], (pg.basis.orthonormalized().inverse() * (ch[3] as Transform3D).basis.orthonormalized()).get_rotation_quaternion())
	# 5) пистолет: голова чуть вниз к мушке
	var cheek := k * (1.0 - rl)
	if cheek > 0.001 and w == "pistol":
		_rot_global(skel, _bone("Neck"), right_s, -0.08 * 0.4 * cheek)
		_rot_global(skel, _bone("Head"), right_s, -0.08 * 0.6 * cheek)
	# 6) отдача: короткий толчок корпуса (дуло вверх)
	var rc: float = player.recoil
	if rc > 0.001:
		_rot_global(skel, _bone("Spine2"), right_s, 0.04 * rc)
	# опора оружия для выстрела: начало — торец, +Z — по стволу (в осях модели)
	var hp := skel.get_bone_global_pose(rh)
	var to_m: Transform3D = model.global_transform.affine_inverse() * skel.global_transform
	var bt: Vector3 = to_m * (hp * (st.bt as Vector3))
	var mz: Vector3 = to_m * (hp * (st.mz as Vector3))
	var z := (mz - bt).normalized()
	var y := (Vector3.UP - z * z.y).normalized()
	player.rifle_rig.transform = Transform3D(Basis(y.cross(z), y, z), bt)
	player.rifle_len = bt.distance_to(mz)
	if player.muzzle_flash:
		player.muzzle_flash.position = Vector3(0, 0, player.rifle_len)
	if _dbg:
		for i in skel.get_bone_count():
			dbg[skel.get_bone_name(i).trim_prefix("mixamorig_")] = skel.global_transform * skel.get_bone_global_pose(i).origin
		var hb := skel.global_transform.basis * skel.get_bone_global_pose(_bone("Hips")).basis
		dbg["hips_fwd"] = hb.z
		dbg["butt"] = skel.global_transform * (hp * (st.bt as Vector3))
		dbg["muzzle"] = skel.global_transform * (hp * (st.mz as Vector3))

func _rot_global(skel: Skeleton3D, bi: int, axis: Vector3, ang: float) -> void:
	if bi < 0 or absf(ang) < 1e-5:
		return
	var g := skel.get_bone_global_pose(bi)
	g.basis = Basis(axis, ang) * g.basis
	skel.set_bone_global_pose(bi, g)

func _barrel_m(skel: Skeleton3D, rh: int, s2m: Basis, st: Dictionary) -> Vector3:
	var hp := skel.get_bone_global_pose(rh)
	return (s2m * ((hp * (st.mz as Vector3)) - (hp * (st.bt as Vector3)))).normalized()

func _ik(skel: Skeleton3D, up: int, lo: int, hand: int, tgt: Vector3, pole: Vector3) -> void:
	# двухзвенный IK в осях скелета: плечо–локоть–кисть, локоть в сторону pole
	if up < 0 or lo < 0 or hand < 0:
		return
	var gu := skel.get_bone_global_pose(up)
	var gl := skel.get_bone_global_pose(lo)
	var gh := skel.get_bone_global_pose(hand)
	var sp := gu.origin
	var e := gl.origin
	var a := sp.distance_to(e)
	var b := e.distance_to(gh.origin)
	if a < 1e-5 or b < 1e-5:
		return
	var to := tgt - sp
	var c := clampf(to.length(), 0.01 * (a + b), (a + b) * 0.999)
	var dir := to.normalized()
	var cos_a := clampf((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var pn := pole - sp
	pn = pn - dir * pn.dot(dir)
	if pn.length() < 1e-5:
		return
	pn = pn.normalized()
	var e2 := sp + dir * a * cos_a + pn * a * sin_a
	gu.basis = Basis(Quaternion((e - sp).normalized(), (e2 - sp).normalized())) * gu.basis
	skel.set_bone_global_pose(up, gu)
	gl = skel.get_bone_global_pose(lo)
	gh = skel.get_bone_global_pose(hand)
	var want := sp + dir * c
	gl.basis = Basis(Quaternion((gh.origin - gl.origin).normalized(), (want - gl.origin).normalized())) * gl.basis
	skel.set_bone_global_pose(lo, gl)
