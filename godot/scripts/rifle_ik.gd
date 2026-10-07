extends SkeletonModifier3D
# Верх тела бойца: поза с автоматом берётся из настоящей анимации (Kevin Iglesias «AssaultRifle_Aim01»:
# обе руки на оружии, живое дыхание), накладывается на ноги/таз из ходьбы или бега. Автомат ставится
# по рукам (правая — рукоять, левая — цевьё). Скрутка корпуса к цели — поверх. Работает после анимации.

var player

var _b := {}
var _aim_names: Array = []      # кости верха тела: [индекс кости, трек, вес]
var _aim_anim: Animation
var _shot_anim: Animation
var _t := 0.0
var _shot_t := 99.0
const UPPER_W := {"Spine1": 0.7, "Spine2": 0.85, "Neck": 0.5, "Head": 0.5}
const LEG_WORDS := ["UpLeg", "Leg", "Foot", "ToeBase", "Hips"]

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _setup(skel: Skeleton3D) -> void:
	_aim_names = [true]
	var anim: AnimationPlayer = player.anim
	if anim == null or not anim.has_animation("AimAR"):
		return
	_aim_anim = anim.get_animation("AimAR")
	_shot_anim = anim.get_animation("ShootAR") if anim.has_animation("ShootAR") else null
	for ti in _aim_anim.get_track_count():
		if _aim_anim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var nm := str(_aim_anim.track_get_path(ti)).get_slice(":", 1)
		var bi := skel.find_bone(nm)
		if bi < 0:
			continue
		var short := nm.trim_prefix("mixamorig_")
		var skip := false
		for w in LEG_WORDS:
			if short == w or short.ends_with("Left" + w) or short.ends_with("Right" + w) or short == "Left" + w or short == "Right" + w:
				skip = true
		if short == "Spine" or nm.begins_with("Bip01_") and (nm.contains("Thigh") or nm.contains("Calf") or nm.contains("Foot") or nm.contains("Toe")) or nm == "mixamorig_Hips":
			skip = true
		if skip:
			continue
		_aim_names.append([bi, ti, UPPER_W.get(short, 1.0)])

# Обновление времени позы (вызывается из player каждый кадр) и выстрела
func fire() -> void:
	_shot_t = 0.0

func _process_modification() -> void:
	var skel := get_skeleton()
	if player == null or skel == null or player.rifle_rig == null:
		return
	if _aim_names.is_empty():
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
	var dt := get_process_delta_time()
	_t += dt
	_shot_t += dt
	# 1) верх тела — поза с автоматом (дыхание из клипа), выстрел — клип отдачи
	if _aim_anim != null and _aim_names.size() > 1:
		var ta := fposmod(_t, _aim_anim.length)
		var use_shot: bool = _shot_anim != null and _shot_t < _shot_anim.length
		for i in range(1, _aim_names.size()):
			var e: Array = _aim_names[i]
			var q: Quaternion = _aim_anim.rotation_track_interpolate(e[1], ta)
			if use_shot:
				var ts := _shot_anim.find_track(_aim_anim.track_get_path(e[1]), Animation.TYPE_ROTATION_3D)
				if ts >= 0:
					var q2: Quaternion = _shot_anim.rotation_track_interpolate(ts, _shot_t)
					q = q.slerp(q2, minf(1.0, _shot_t * 40.0) if _shot_t < 0.05 else 1.0)
			var w: float = e[2]
			skel.set_bone_pose_rotation(e[0], skel.get_bone_pose_rotation(e[0]).slerp(q, w))
	# 2) скрутка корпуса к цели (часть поворота — тазом, остальное — по позвоночнику)
	var tw: float = clampf(player.aim_local, -player.TWIST, player.TWIST)
	for pair in [["Hips", 0.22, "Spine"], ["Spine", 0.26, "Spine1"], ["Spine1", 0.26, "Spine2"], ["Spine2", 0.26, "Neck"]]:
		var bi := _bone(pair[0])
		if bi >= 0:
			# ось скрутки — вдоль позвоночника (к следующей кости)
			var ci := _bone(pair[2])
			var ax := skel.get_bone_rest(ci).origin.normalized() if ci >= 0 else Vector3.UP
			skel.set_bone_pose_rotation(bi, skel.get_bone_pose_rotation(bi) * Quaternion(ax, tw * pair[1]))
	# 3) автомат по рукам: рукоять — правая кисть, цевьё — левая
	var to_model := model.global_transform.affine_inverse() * skel.global_transform
	var rh := skel.find_bone("Bip01_R_Finger2")
	var lh := skel.find_bone("Bip01_L_Finger2")
	if rh < 0 or lh < 0:
		rh = _bone("RightHand"); lh = _bone("LeftHand")
	var rp: Vector3 = to_model * skel.get_bone_global_pose(rh).origin
	var lp: Vector3 = to_model * skel.get_bone_global_pose(lh).origin
	var f := (lp - rp)
	if f.length() < 0.05:
		return
	f = f.normalized()
	var up_v := Vector3.UP
	var y2 := (up_v - f * up_v.dot(f)).normalized()
	var x2 := y2.cross(f).normalized()
	var basis := Basis(x2, y2, f)
	var rc: float = player.recoil
	var origin: Vector3 = rp - basis * player.RIFLE_GRIP - f * (0.03 * rc)
	player.rifle_rig.transform = Transform3D(basis, origin)
