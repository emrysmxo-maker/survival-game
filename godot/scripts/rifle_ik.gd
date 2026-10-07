extends SkeletonModifier3D
# Автомат в руках. Автомат — часть модели: меш со скином на правой кисти, положение в кисти взято из .blend
# набора Kevin Iglesias (запись AssaultRifle_Aim01) — приклад в плече, левая кисть на цевье, пальцы на рукояти.
# Работает после анимации ног:
#  1) верх тела (руки, кисти, пальцы, шея, голова и большая часть позвоночника) — поза прицела из записи (с дыханием);
#  2) позвоночник доворачивается так, чтобы ствол смотрел точно на цель (по горизонту и по высоте);
#  3) не целится — «низкая готовность»: обе руки вместе с автоматом поворачиваются вокруг правого плеча (ствол вниз
#     и поперёк тела), левая кисть остаётся на цевье (двухзвенный IK); при выстреле — короткая отдача;
#  4) голова к прикладу (щека к автомату), пока целится.
# Плывёт — автомат спрятан.

var player

var _b := {}
var _aim: Animation
var _tracks: Array = []        # [кость, трек, доля записи]
var _t := 0.0
var _ready_done := false
var _mz_l := Vector3.ZERO      # дуло / приклад в осях правой кисти (покой)
var _bt_l := Vector3.ZERO
var _ok := false

const SPINE_W := 0.75           # позвоночник: доля позы прицела (остальное — от ходьбы, живое покачивание)
const READY_PITCH := 0.55       # наготове ствол вниз ~31° (вокруг приклада)
const READY_YAW := 0.42         # и поперёк тела влево ~24°
const AIM_PITCH := -0.03        # при прицеле — чуть ниже горизонта (цели на земле)
# где торец приклада относительно правого плечевого сустава (метры модели): [внутрь к груди, вверх, вперёд]
const BUTT_AIM := Vector3(0.06, 0.0, 0.10)      # в прицеле — в «карман» плеча, на уровне ключицы
const BUTT_READY := Vector3(0.05, -0.12, 0.13)  # наготове — чуть ниже и впереди
const EYE_BACK := 0.10          # глаз над прикладом: от торца вперёд по стволу
const EYE_UP := 0.075           # и над осью ствола (линия прицела)
const HEAD_MAX := 0.75          # предел наклона шеи+головы (рад)

func _bone(n: String) -> int:
	if not _b.has(n):
		_b[n] = get_skeleton().find_bone("mixamorig_" + n)
	return _b[n]

func _setup(skel: Skeleton3D) -> void:
	_ready_done = true
	var anim: AnimationPlayer = player.anim
	if anim == null or not anim.has_animation("AimAR") or player.rifle_pts.is_empty():
		return
	_aim = anim.get_animation("AimAR")
	var spine := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
	for ti in _aim.get_track_count():
		if _aim.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var nm := str(_aim.track_get_path(ti)).get_slice(":", 1)
		var w := -1.0
		if nm in spine:
			w = SPINE_W
		elif nm in ["mixamorig_Neck", "mixamorig_Head"] or nm.contains("Shoulder") or nm.contains("Arm") or nm.contains("Hand") or nm.contains("Finger"):
			w = 1.0
		var bi := skel.find_bone(nm)
		if w > 0.0 and bi >= 0:
			_tracks.append([bi, ti, w])
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
	var r_arm := _bone("RightArm")
	var l_arm := _bone("LeftArm")
	var lh := _bone("LeftHand")
	if player.rifle_mesh:
		player.rifle_mesh.visible = not player.swimming
	if player.swimming:
		return
	_t += get_process_delta_time()
	# 1) поза прицела из записи
	var ta := fposmod(_t, _aim.length)
	for e in _tracks:
		var q: Quaternion = _aim.rotation_track_interpolate(e[1], ta)
		if e[2] < 1.0:
			q = skel.get_bone_pose_rotation(e[0]).slerp(q, e[2])
		skel.set_bone_pose_rotation(e[0], q)
	var model: Node3D = player.model
	var m2s: Basis = skel.global_transform.basis.orthonormalized().inverse() * model.global_transform.basis.orthonormalized()
	var s2m: Basis = m2s.inverse()
	var up_s: Vector3 = (m2s * Vector3.UP).normalized()
	# 2) позвоночник: ствол на цель. Направление ствола — в осях модели (+Z — лицо бойца)
	var d := _barrel_m(skel, rh, s2m)
	var want_yaw: float = player.aim_local
	var err_yaw := wrapf(want_yaw - atan2(d.x, d.z), -PI, PI)
	for pr in [["Spine", 0.3], ["Spine1", 0.35], ["Spine2", 0.35]]:
		var bi := _bone(pr[0])
		if bi >= 0:
			var g := skel.get_bone_global_pose(bi)
			g.basis = Basis(up_s, err_yaw * pr[1]) * g.basis
			skel.set_bone_global_pose(bi, g)
	d = _barrel_m(skel, rh, s2m)
	var dh := Vector3(d.x, 0.0, d.z).normalized()
	var lat_m := dh.cross(Vector3.UP).normalized()          # поворот вокруг этой оси на «+» поднимает дуло
	var err_p := clampf(AIM_PITCH - asin(clampf(d.y, -1.0, 1.0)), -0.45, 0.45)
	for pr in [["Spine1", 0.5], ["Spine2", 0.5]]:
		var bi := _bone(pr[0])
		if bi >= 0:
			var g := skel.get_bone_global_pose(bi)
			g.basis = Basis((m2s * lat_m).normalized(), err_p * pr[1]) * g.basis
			skel.set_bone_global_pose(bi, g)
	# 3) автомат как целое: приклад — к плечу (по высоте), наготове ствол вниз и поперёк тела (поворот вокруг приклада),
	#    отдача — толчок назад и вверх. Обе кисти едут вместе с автоматом (двухзвенный IK, локти — как в записи).
	var k: float = player.aim_blend
	var m := 1.0 - k
	var side := signf((s2m * (skel.get_bone_global_pose(r_arm).origin - skel.get_bone_global_pose(l_arm).origin)).x)
	if side == 0.0:
		side = 1.0
	var rc: float = player.recoil
	var rh0 := skel.get_bone_global_pose(rh)
	var lh0 := skel.get_bone_global_pose(lh)
	var butt_s := rh0 * _bt_l
	var sh_m: Vector3 = s2m * skel.get_bone_global_pose(r_arm).origin
	var lsh_m: Vector3 = s2m * skel.get_bone_global_pose(l_arm).origin
	var bt_m: Vector3 = s2m * butt_s
	var inw := lsh_m - sh_m
	inw = (inw - dh * inw.dot(dh)); inw.y = 0.0; inw = inw.normalized()
	var bw: Vector3 = BUTT_READY.lerp(BUTT_AIM, k)
	var want_bt: Vector3 = sh_m + inw * bw.x + Vector3.UP * bw.y + dh * bw.z
	var dmov := (want_bt - bt_m).limit_length(0.35)
	var rot_m := Basis(Vector3.UP, -side * READY_YAW * m) * Basis(lat_m, -READY_PITCH * m + 0.04 * rc)
	var rot_s: Basis = m2s * rot_m * s2m
	var off_s: Vector3 = m2s * (dmov - dh * (0.03 * rc))
	var re0 := skel.get_bone_global_pose(_bone("RightForeArm")).origin
	var le0 := skel.get_bone_global_pose(_bone("LeftForeArm")).origin
	var xf := func(p: Vector3) -> Vector3: return butt_s + rot_s * (p - butt_s) + off_s
	for ch in [[r_arm, _bone("RightForeArm"), rh, rh0.origin, re0], [l_arm, _bone("LeftForeArm"), lh, lh0.origin, le0]]:
		var tgt: Vector3 = xf.call(ch[3])
		var el: Vector3 = xf.call(ch[4])
		var mid: Vector3 = (skel.get_bone_global_pose(ch[0]).origin + tgt) * 0.5
		_ik(skel, ch[0], ch[1], ch[2], tgt, el + (el - mid))          # локоть — в той же стороне, что в записи
	for pr in [[rh, rh0], [lh, lh0]]:
		var pg := skel.get_bone_global_pose(skel.get_bone_parent(pr[0]))
		var hb: Basis = rot_s * (pr[1] as Transform3D).basis
		skel.set_bone_pose_rotation(pr[0], (pg.basis.orthonormalized().inverse() * hb.orthonormalized()).get_rotation_quaternion())
	if OS.get_cmdline_user_args().has("--rifledbg") and Engine.get_process_frames() % 20 == 0:
		var pr := func(v: Vector3) -> String: return str((s2m * v).snappedf(0.01))
		print("RDBG k=", snappedf(k, 0.01), " dmov=", dmov.snappedf(0.01), " rh0=", pr.call(rh0.origin), " rh=", pr.call(skel.get_bone_global_pose(rh).origin), " rhT=", pr.call(xf.call(rh0.origin)), " lh0=", pr.call(lh0.origin), " lh=", pr.call(skel.get_bone_global_pose(lh).origin), " lhT=", pr.call(xf.call(lh0.origin)), " butt=", pr.call(butt_s), " sh=", pr.call(skel.get_bone_global_pose(r_arm).origin), " lsh=", pr.call(skel.get_bone_global_pose(l_arm).origin))
	# 4) голова к прикладу: шея и голова наклоняются так, чтобы правый глаз лёг на линию прицела над прикладом
	var head := _bone("Head")
	var neck := _bone("Neck")
	var eye := skel.find_bone("Bip01 REye")
	if head >= 0 and neck >= 0 and eye >= 0 and k > 0.001:
		var hp0 := skel.get_bone_global_pose(rh)
		var bt1: Vector3 = hp0 * _bt_l
		var z1: Vector3 = ((hp0 * _mz_l) - bt1).normalized()
		var e_want: Vector3 = bt1 + z1 * EYE_BACK + up_s * EYE_UP
		for pr in [[neck, 0.5], [head, 1.0]]:
			var g := skel.get_bone_global_pose(pr[0])
			var a := skel.get_bone_global_pose(eye).origin - g.origin
			var b := e_want - g.origin
			var q := Quaternion(a.normalized(), b.normalized())
			var ang := minf(q.get_angle(), HEAD_MAX * 0.5) * k * float(pr[1])
			if ang > 1e-4:
				g.basis = Basis(q.get_axis().normalized(), ang) * g.basis
				skel.set_bone_global_pose(pr[0], g)
		if OS.get_cmdline_user_args().has("--rifledbg") and Engine.get_process_frames() % 20 == 0:
			print("EYE want=", (s2m * e_want).snappedf(0.01), " got=", (s2m * skel.get_bone_global_pose(eye).origin).snappedf(0.01))
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

func _ik(skel: Skeleton3D, up: int, lo: int, hand: int, tgt: Vector3, pole: Vector3) -> void:
	# двухзвенный IK в осях скелета
	if lo < 0 or hand < 0:
		return
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
