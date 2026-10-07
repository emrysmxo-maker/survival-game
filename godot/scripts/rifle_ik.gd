extends SkeletonModifier3D
# Автомат в руках: автомат ставится относительно груди (поза «наготове» / «к плечу», отдача), обе руки тянутся
# к точкам хвата (рукоять, цевьё — двухзвенный IK), кисти и пальцы берутся из записи «AssaultRifle_Aim01»
# (Kevin Iglesias) — хват настоящий. Скрутка корпуса к цели — поверх ходьбы/бега. Работает после анимации.
# Точки хвата оружия — константы RIFLE_* в player.gd (для другого оружия — свои).

var player

var _b := {}
var _hand_tracks: Array = []        # [индекс кости, трек] кисти и пальцев из записи прицела
var _aim_anim: Animation
var _t := 0.0
var _ready_done := false

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _setup(skel: Skeleton3D) -> void:
	_ready_done = true
	var anim: AnimationPlayer = player.anim
	if anim == null or not anim.has_animation("AimAR"):
		return
	_aim_anim = anim.get_animation("AimAR")
	for ti in _aim_anim.get_track_count():
		if _aim_anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var nm := str(_aim_anim.track_get_path(ti)).get_slice(":", 1)
		if nm == "mixamorig_LeftHand" or nm == "mixamorig_RightHand" or (nm.begins_with("Bip01_") and nm.contains("Finger")):
			var bi := skel.find_bone(nm)
			if bi >= 0:
				_hand_tracks.append([bi, ti])

func fire() -> void:
	pass

func _process_modification() -> void:
	var skel := get_skeleton()
	if player == null or skel == null or player.rifle_rig == null:
		return
	if not _ready_done:
		_setup(skel)
	var spine2 := _bone("Spine2")
	var r_arm := _bone("RightArm")
	var l_arm := _bone("LeftArm")
	if spine2 < 0 or r_arm < 0 or l_arm < 0:
		return
	var model: Node3D = player.model
	if player.swimming:
		# плывёт: автомат на ремне за спиной (наискосок вдоль позвоночника), положение — по костям
		var tm := model.global_transform.affine_inverse() * skel.global_transform
		var ch: Vector3 = tm * skel.get_bone_global_pose(spine2).origin
		var head := _bone("Head")
		var up: Vector3 = ((tm * skel.get_bone_global_pose(head).origin) - ch).normalized() if head >= 0 else Vector3.UP
		var right: Vector3 = ((tm * skel.get_bone_global_pose(r_arm).origin) - (tm * skel.get_bone_global_pose(l_arm).origin)).normalized()
		var fwd := up.cross(right).normalized()
		var z := (up * 0.92 + right * 0.3).normalized()
		var y := (-fwd - z * (-fwd).dot(z)).normalized()
		var x := y.cross(z).normalized()
		player.rifle_rig.transform = Transform3D(Basis(x, y, z), ch - fwd * 0.17 - up * 0.1)
		return
	_t += get_process_delta_time()
	# 1) хват: кисти и пальцы — из записи прицела (дыхание заодно)
	if _aim_anim != null:
		var ta := fposmod(_t, _aim_anim.length)
		for e in _hand_tracks:
			skel.set_bone_pose_rotation(e[0], _aim_anim.rotation_track_interpolate(e[1], ta))
	# 2) скрутка корпуса к цели по позвоночнику (бёдра подвешены на таз — не едут)
	var tw: float = clampf(player.aim_local, -player.TWIST, player.TWIST)
	for pair in [["Spine", 0.3, "Spine1"], ["Spine1", 0.35, "Spine2"], ["Spine2", 0.35, "Neck"]]:   # таз и бёдра не скручиваются — ноги стоят ровно
		var bi := _bone(pair[0])
		if bi >= 0:
			var ci := _bone(pair[2])
			var ax := skel.get_bone_rest(ci).origin.normalized() if ci >= 0 else Vector3.UP
			skel.set_bone_pose_rotation(bi, skel.get_bone_pose_rotation(bi) * Quaternion(ax, tw * pair[1]))
	# 3) автомат: приклад в плече (прицел) или у рёбер (наготове), ствол по линии прицела; руки тянутся к рукояти и цевью.
	#    Приклад привязан к правому плечу — рука согнута в локте, а не вытянута (как у живого стрелка).
	var to_model := model.global_transform.affine_inverse() * skel.global_transform
	var rs: Vector3 = to_model * skel.get_bone_global_pose(r_arm).origin        # правое плечо (модельные координаты)
	var side := signf(rs.x)
	if side == 0.0:
		side = 1.0
	var k: float = player.aim_blend
	var rc: float = player.recoil
	var ay: float = player.aim_local
	var yaw := -side * 0.22 * (1.0 - k) + ay
	var pitch := 0.50 * (1.0 - k) - 0.03 * rc            # наготове ствол вниз ~28°, при прицеле — по горизонту
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var lat := Vector3(cos(yaw), 0.0, -sin(yaw)) * side    # вправо от бойца
	var butt_ready := rs + fwd * 0.10 - lat * 0.09 + Vector3(0, -0.20, 0)
	var butt_aim := rs + fwd * 0.01 - lat * 0.05 + Vector3(0, -0.04, 0)
	var butt := butt_ready.lerp(butt_aim, k) - fwd * (0.03 * rc)
	var rig: Node3D = player.rifle_rig
	var bas := Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)
	rig.transform = Transform3D(bas, butt - bas * player.RIFLE_BUTT)
	var rig_w := model.global_transform * rig.transform
	var grip: Vector3 = rig_w * player.RIFLE_GRIP
	var guard: Vector3 = rig_w * player.RIFLE_HANDGUARD
	var mb := model.global_transform.basis
	var pole_r: Vector3 = (skel.global_transform * skel.get_bone_global_pose(r_arm).origin) + mb * Vector3(side * 0.6, -0.8, -0.5)   # локоть вниз и чуть наружу
	var pole_l: Vector3 = (skel.global_transform * skel.get_bone_global_pose(l_arm).origin) + mb * Vector3(-side * 0.6, -0.8, -0.2)
	_ik(skel, r_arm, _bone("RightForeArm"), _bone("RightHand"), grip, pole_r)
	_ik(skel, l_arm, _bone("LeftForeArm"), _bone("LeftHand"), guard, pole_l)

func _ik(skel: Skeleton3D, up: int, lo: int, hand: int, target_w: Vector3, pole_w: Vector3) -> void:
	if lo < 0 or hand < 0:
		return
	var inv := skel.global_transform.affine_inverse()
	var tgt := inv * target_w
	var pole := inv * pole_w
	var gu := skel.get_bone_global_pose(up)
	var gl := skel.get_bone_global_pose(lo)
	var gh := skel.get_bone_global_pose(hand)
	var s := gu.origin
	var e := gl.origin
	var h := gh.origin
	var a := s.distance_to(e)
	var b := e.distance_to(h)
	if a < 1e-5 or b < 1e-5:
		return
	var to := tgt - s
	var c := clampf(to.length(), 0.01 * (a + b), (a + b) * 0.999)
	var dir := to.normalized()
	var cos_a := clampf((a * a + c * c - b * b) / (2.0 * a * c), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var pn := pole - s
	pn = pn - dir * pn.dot(dir)
	if pn.length() < 1e-5:
		return
	pn = pn.normalized()
	var e2 := s + dir * a * cos_a + pn * a * sin_a
	var q1 := Quaternion((e - s).normalized(), (e2 - s).normalized())
	gu.basis = Basis(q1) * gu.basis
	skel.set_bone_global_pose(up, gu)
	gl = skel.get_bone_global_pose(lo)
	gh = skel.get_bone_global_pose(hand)
	var want := s + dir * c
	var q2 := Quaternion((gh.origin - gl.origin).normalized(), (want - gl.origin).normalized())
	gl.basis = Basis(q2) * gl.basis
	skel.set_bone_global_pose(lo, gl)

