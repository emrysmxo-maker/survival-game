extends SkeletonModifier3D
# Автомат в руках: ставит автомат относительно груди бойца (поза «наготове» или
# «к плечу», отдача) и тянет к нему обе руки (IK из двух костей) — перенос
# applyRiflePose / solveArmIK из браузерной версии. Работает после анимации.

var player

var _b := {}

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _process_modification() -> void:
	var skel := get_skeleton()
	if player == null or skel == null or player.rifle_rig == null:
		return
	var spine2 := _bone("Spine2")
	var r_arm := _bone("RightArm")
	var l_arm := _bone("LeftArm")
	if spine2 < 0 or r_arm < 0 or l_arm < 0:
		return
	var model: Node3D = player.model
	if player.swimming:
		# плывёт: автомат на ремне за спиной (наискосок, стволом вверх), руки свободны
		var tm := model.global_transform.affine_inverse() * skel.global_transform
		var ch: Vector3 = tm * skel.get_bone_global_pose(spine2).origin
		player.rifle_rig.transform = Transform3D(Basis(Vector3(0, 0, 1), 0.6) * Basis.from_euler(Vector3(-1.9, 0, 0)), ch + Vector3(0.0, 0.02, -0.17))
		_swim(skel, model)
		return
	# скручивание позвоночника к цели (корпус добирает до TWIST, остальное — руки)
	var tw: float = clampf(player.aim_local, -player.TWIST, player.TWIST)
	for pair in [["Spine", 0.3], ["Spine1", 0.35], ["Spine2", 0.35]]:
		var bi := _bone(pair[0])
		if bi >= 0:
			skel.set_bone_pose_rotation(bi, skel.get_bone_pose_rotation(bi) * Quaternion(Vector3.UP, tw * pair[1]))
	var to_model := model.global_transform.affine_inverse() * skel.global_transform
	var chest: Vector3 = to_model * skel.get_bone_global_pose(spine2).origin
	var side := signf((to_model * skel.get_bone_global_pose(r_arm).origin).x)
	if side == 0.0:
		side = 1.0
	var k: float = player.aim_blend
	var rc: float = player.recoil
	var ay: float = player.aim_local
	var cx := side * (0.05 + 0.04 * k)
	var cy := -0.21 + 0.31 * k
	var cz := 0.26 + 0.07 * k - 0.035 * rc
	var px := cx * cos(ay) + cz * sin(ay)
	var pz := -cx * sin(ay) + cz * cos(ay)
	var pitch := 0.42 * (1.0 - k) - 0.03 * rc
	var yaw := -side * 0.22 * (1.0 - k) + ay
	var rig: Node3D = player.rifle_rig
	rig.transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ), chest + Vector3(px, cy, pz))
	var rig_w := model.global_transform * rig.transform
	var grip: Vector3 = rig_w * player.RIFLE_GRIP
	var guard: Vector3 = rig_w * player.RIFLE_HANDGUARD
	var mb := model.global_transform.basis
	var pole_r: Vector3 = (skel.global_transform * skel.get_bone_global_pose(r_arm).origin) + mb * Vector3(side * 0.5, -1.0, -0.5)
	var pole_l: Vector3 = (skel.global_transform * skel.get_bone_global_pose(l_arm).origin) + mb * Vector3(-side * 0.5, -1.0, -0.3)
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

# Плавание (клипа нет — процедурно): руки по очереди тянутся вперёд и гребут вниз-назад
# (кроль/«по-собачьи»), ноги часто и мелко бьют. Направления — в осях модели: +Z вперёд, +Y вверх.
func _swim(skel: Skeleton3D, model: Node3D) -> void:
	var t: float = player.swim_t
	var to_s := skel.global_transform.basis.inverse() * model.global_transform.basis
	var side := signf((model.global_transform.affine_inverse() * skel.global_transform * skel.get_bone_global_pose(_bone("RightArm")).origin).x)
	if side == 0.0:
		side = 1.0
	for arm in [["Right", 0.0, side], ["Left", PI, -side]]:
		var ph: float = t + arm[1]
		var sx: float = arm[2]
		var reach := Vector3(sx * (0.3 + 0.15 * cos(ph)), -0.25 + 0.55 * sin(ph), 0.75 + 0.35 * cos(ph))
		var fore := reach + Vector3(sx * 0.1, -0.35 - 0.2 * sin(ph), 0.1)
		_point(skel, _bone(arm[0] + "Arm"), _bone(arm[0] + "ForeArm"), to_s * reach)
		_point(skel, _bone(arm[0] + "ForeArm"), _bone(arm[0] + "Hand"), to_s * fore)
	for leg in [["Right", 0.0, side], ["Left", PI, -side]]:
		var k: float = sin(t * 2.2 + leg[1])
		var thigh := Vector3(leg[2] * 0.12, -1.0, -0.25 + 0.3 * k)
		var shin := Vector3(leg[2] * 0.08, -1.0, -0.45 + 0.2 * k)
		_point(skel, _bone(leg[0] + "UpLeg"), _bone(leg[0] + "Leg"), to_s * thigh)
		_point(skel, _bone(leg[0] + "Leg"), _bone(leg[0] + "Foot"), to_s * shin)

# повернуть кость b так, чтобы её дочерняя c оказалась в направлении dir (оси скелета)
func _point(skel: Skeleton3D, b: int, c: int, dir: Vector3) -> void:
	if b < 0 or c < 0:
		return
	var gb := skel.get_bone_global_pose(b)
	var cur := skel.get_bone_global_pose(c).origin - gb.origin
	if cur.length() < 1e-5 or dir.length() < 1e-5:
		return
	gb.basis = Basis(Quaternion(cur.normalized(), dir.normalized())) * gb.basis
	skel.set_bone_global_pose(b, gb)
