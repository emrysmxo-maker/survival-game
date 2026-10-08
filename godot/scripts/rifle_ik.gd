extends SkeletonModifier3D
# Автомат в руках. Автомат — часть модели: меш со скином на правой кисти, положение в кисти взято из .blend набора
# Kevin Iglesias — приклад в плече, левая кисть на цевье. Позы рук родные (скелет бойца — тот же Mixamo, переноса нет):
#  • прицел — запись AimAR (руки, кисти, пальцы; корпус, шея и голова почти целиком), с дыханием;
#  • без прицела — запись HoldAR («автомат наготове»), корпус остаётся от шага/бега;
#  • между ними плавный переход по aim_blend; поверх — небольшая скрутка позвоночника на цель и отдача.
# Плывёт — автомат спрятан. Работает после анимации ног.

var player

var _b := {}
var _aim: Animation
var _hold: Animation
var _arm_tracks: Array = []       # [кость, трек в AimAR, трек в HoldAR]
var _torso_tracks: Array = []     # [кость, трек в AimAR, доля]
var _t := 0.0
var _ready_done := false
var _mz_l := Vector3.ZERO         # дуло / приклад в осях правой кисти (покой)
var _bt_l := Vector3.ZERO
var _ok := false

const TORSO_W := {"Spine": 0.85, "Spine1": 0.9, "Spine2": 0.95, "Neck": 1.0, "Head": 1.0}
const RECOIL_KICK := 0.05         # толчок корпуса при выстреле (рад)

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _track_of(a: Animation, nm: String) -> int:
	for ti in a.get_track_count():
		if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D and str(a.track_get_path(ti)).get_slice(":", 1) == nm:
			return ti
	return -1

func _setup(skel: Skeleton3D) -> void:
	_ready_done = true
	var anim: AnimationPlayer = player.anim
	if anim == null or not anim.has_animation("AimAR") or not anim.has_animation("HoldAR") or player.rifle_pts.is_empty():
		return
	_aim = anim.get_animation("AimAR")
	_hold = anim.get_animation("HoldAR")
	for bi in skel.get_bone_count():
		var full := skel.get_bone_name(bi)
		var nm := full.trim_prefix("mixamorig_")
		var ta := _track_of(_aim, full)
		if ta < 0:
			continue
		if TORSO_W.has(nm):
			_torso_tracks.append([bi, ta, TORSO_W[nm]])
		elif nm.contains("Shoulder") or nm.contains("Arm") or nm.contains("Hand"):
			_arm_tracks.append([bi, ta, _track_of(_hold, full)])
	var rh := _bone("RightHand")
	if rh < 0:
		return
	# точки автомата: покой в координатах файла модели → оси скелета → оси правой кисти
	var to_skel: Transform3D = skel.global_transform.affine_inverse() * player.glb.global_transform
	var inv := skel.get_bone_global_rest(rh).affine_inverse()
	_mz_l = inv * (to_skel * (player.rifle_pts["muzzle"] as Vector3))
	_bt_l = inv * (to_skel * (player.rifle_pts["butt"] as Vector3))
	_ok = true

func fire() -> void:
	pass

func _process_modification() -> void:
	var skel := get_skeleton()
	if player == null or skel == null:
		return
	if not _ready_done:
		_setup(skel)
	if not _ok:
		return
	var rh := _bone("RightHand")
	if player.rifle_mesh:
		player.rifle_mesh.visible = not player.swimming
	if player.swimming:
		return
	_t += get_process_delta_time()
	var k: float = player.aim_blend
	var ta := fposmod(_t, _aim.length)
	# 1) руки: наготове ↔ прицел
	for e in _arm_tracks:
		var qa: Quaternion = _aim.rotation_track_interpolate(e[1], ta)
		var qh: Quaternion = _hold.rotation_track_interpolate(e[2], 0.0) if e[2] >= 0 else qa
		skel.set_bone_pose_rotation(e[0], qh.slerp(qa, k))
	# 2) корпус, шея, голова: от шага/бега к позе прицела
	for e in _torso_tracks:
		var qa: Quaternion = _aim.rotation_track_interpolate(e[1], ta)
		skel.set_bone_pose_rotation(e[0], skel.get_bone_pose_rotation(e[0]).slerp(qa, k * e[2]))
	var model: Node3D = player.model
	var m2s: Basis = skel.global_transform.basis.orthonormalized().inverse() * model.global_transform.basis.orthonormalized()
	var s2m: Basis = m2s.inverse()
	var up_s: Vector3 = (m2s * Vector3.UP).normalized()
	# 3) скрутка позвоночника: ствол смотрит на цель (aim_local — на сколько ствол повёрнут относительно ног)
	var d := _barrel_m(skel, rh, s2m)
	if k > 0.001:
		var err_yaw := wrapf(player.aim_local - atan2(d.x, d.z), -PI, PI) * k
		for pr in [["Spine", 0.3], ["Spine1", 0.35], ["Spine2", 0.35]]:
			var bi := _bone(pr[0])
			if bi >= 0:
				var g := skel.get_bone_global_pose(bi)
				g.basis = Basis(up_s, err_yaw * pr[1]) * g.basis
				skel.set_bone_global_pose(bi, g)
	# 4) отдача: короткий толчок корпуса (дуло вверх)
	var rc: float = player.recoil
	if rc > 0.001:
		d = _barrel_m(skel, rh, s2m)
		var dh := Vector3(d.x, 0.0, d.z).normalized()
		var axis: Vector3 = (m2s * dh.cross(Vector3.UP)).normalized()
		for pr in [["Spine1", 0.5], ["Spine2", 0.5]]:
			var bi := _bone(pr[0])
			if bi >= 0:
				var g := skel.get_bone_global_pose(bi)
				g.basis = Basis(axis, RECOIL_KICK * rc * pr[1]) * g.basis
				skel.set_bone_global_pose(bi, g)
	# опора автомата для выстрела: начало — приклад, +Z — по стволу (в осях модели)
	var hp := skel.get_bone_global_pose(rh)
	var to_m: Transform3D = model.global_transform.affine_inverse() * skel.global_transform
	var bt: Vector3 = to_m * (hp * _bt_l)
	var mz: Vector3 = to_m * (hp * _mz_l)
	var z := (mz - bt).normalized()
	var y := (Vector3.UP - z * z.y).normalized()
	player.rifle_rig.transform = Transform3D(Basis(y.cross(z), y, z), bt)
	player.rifle_len = bt.distance_to(mz)
	if player.muzzle_flash:
		player.muzzle_flash.position = Vector3(0, 0, player.rifle_len)

func _barrel_m(skel: Skeleton3D, rh: int, s2m: Basis) -> Vector3:
	var hp := skel.get_bone_global_pose(rh)
	return (s2m * ((hp * _mz_l) - (hp * _bt_l))).normalized()
