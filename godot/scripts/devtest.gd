extends RefCounted
# Проверки без экрана (запуск с --test=start|run|side|sideaim|sidewalk|runaim|runback|fireback|zombie|behind|aim): сценарии
# управления и вывод замеров в лог. В обычной игре не используется.

static func _yaw(d: Vector2) -> float:
	return atan2(d.x, d.y)

static func _hide_mm(n: Node) -> void:
	for c in n.get_children():
		if c is MultiMeshInstance3D:
			c.visible = false
		_hide_mm(c)

static var _ik = null
static func _bp(sk: Skeleton3D, n: String) -> Vector3:
	if _ik != null and _ik.dbg.has(n):
		return _ik.dbg[n]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + n)).origin

# замер позы (--pose): высоты локтей относительно плеч, наклон корпуса, сгиб колен, голова над прикладом
static func pose_report(m) -> void:
	var sk: Skeleton3D = m.player.skel
	var y0: float = m.player.global_position.y
	var hips := _bp(sk, "Hips")
	var neck := _bp(sk, "Neck")
	var fwd: Vector3 = m.player.model.global_transform.basis.z.normalized()
	var tv := (neck - hips)
	var lean := rad_to_deg(atan2(tv.dot(fwd), tv.y))
	var knee := func(side: String) -> float:
		var a := _bp(sk, side + "UpLeg"); var b := _bp(sk, side + "Leg"); var c := _bp(sk, side + "Foot")
		return rad_to_deg((a - b).angle_to(c - b))
	if _ik == null:
		for c in sk.get_children():
			if c is SkeletonModifier3D and "dbg" in c:
				_ik = c
	var hd := _bp(sk, "RightEye")
	var bt := _bp(sk, "butt") if _ik != null and _ik.dbg.has("butt") else hd
	print("POSE t=", snappedf(m._tt, 0.1), " anim=", m.player.anim.current_animation, " aim=", snappedf(m.player.aim_blend, 0.01),
		" elbowR-shR=", snappedf(_bp(sk, "RightForeArm").y - _bp(sk, "RightArm").y, 0.01),
		" elbowL-shL=", snappedf(_bp(sk, "LeftForeArm").y - _bp(sk, "LeftArm").y, 0.01),
		" handR=", snappedf(_bp(sk, "RightHand").y - y0, 0.01), " shR=", snappedf(_bp(sk, "RightArm").y - y0, 0.01),
		" head=", snappedf(_bp(sk, "Head").y - y0, 0.01), " lean=", snappedf(lean, 0.1),
		" kneeL=", snappedf(knee.call("Left"), 1), " kneeR=", snappedf(knee.call("Right"), 1),
		" hipsY=", snappedf(hips.y - y0, 0.01),
		" eye-butt=", (hd - bt).snappedf(0.01), " butt-shR=", (bt - _bp(sk, "RightArm")).snappedf(0.01),
		" elbowR_out=", snappedf((_bp(sk, "RightForeArm") - _bp(sk, "Spine2")).dot(-m.player.model.global_transform.basis.x.normalized()), 0.01),
		" elbowL_out=", snappedf((_bp(sk, "LeftForeArm") - _bp(sk, "Spine2")).dot(m.player.model.global_transform.basis.x.normalized()), 0.01))

static var _pf := {}
static func strafe_log(m) -> void:
	if _ik == null:
		for c in m.player.skel.get_children():
			if c is SkeletonModifier3D and "dbg" in c:
				_ik = c
	if _ik == null or not _ik.dbg.has("hips_fwd"):
		return
	var pl = m.player
	var mf: Vector3 = pl.model.global_transform.basis.z
	var hf: Vector3 = _ik.dbg["hips_fwd"]
	var hy := rad_to_deg(wrapf(atan2(hf.x, hf.z) - atan2(mf.x, mf.z), -PI, PI))
	var out := ""
	for sd in ["LeftFoot", "RightFoot"]:
		var p: Vector3 = _ik.dbg[sd]
		var low: bool = p.y - pl.global_position.y < 0.12
		var sp := 0.0
		if _pf.has(sd):
			sp = Vector2(p.x - _pf[sd].x, p.z - _pf[sd].z).length() / 0.033
		_pf[sd] = p
		out += " %s=%.2f/%.3f" % [sd.substr(0, 1), sp, p.y - pl.global_position.y]
	# колено: куда смотрит (от линии бедро–стопа) относительно носка стопы, градусы; ноль — колено над носком
	for sd in ["Left", "Right"]:
		var hp: Vector3 = _ik.dbg[sd + "UpLeg"]; var kn: Vector3 = _ik.dbg[sd + "Leg"]; var ft: Vector3 = _ik.dbg[sd + "Foot"]; var toe: Vector3 = _ik.dbg[sd + "ToeBase"]
		var ax := (ft - hp).normalized()
		var kd := kn - hp; kd -= ax * kd.dot(ax)
		var td := toe - ft; td -= ax * td.dot(ax)
		var bend := rad_to_deg((hp - kn).angle_to(ft - kn))
		if bend < 155.0:     # колено согнуто — направление определено
			out += " k%s=%d" % [sd.substr(0, 1), int(rad_to_deg(kd.signed_angle_to(td, ax)))]
	print("ST t=", snappedf(m._tt, 0.033), " anim=", pl.anim.current_animation, " k=", snappedf(pl.anim.speed_scale, 0.01), " v=", snappedf(pl.vel.length() * WorldGen.T, 0.01), " hipyaw=", snappedf(hy, 1), " yaw=", snappedf(rad_to_deg(pl.yaw), 1), out)

static func run(m, dt: float) -> void:
	if OS.get_cmdline_user_args().has("--pose") and Engine.get_process_frames() % 5 == 0 and m._tt > 0.3:
		pose_report(m)
	if OS.get_cmdline_user_args().has("--clean") and Engine.get_process_frames() % 10 == 0:
		_hide_mm(m.world)   # снимки позы: без деревьев и кустов (земля остаётся)
	if OS.get_cmdline_user_args().has("--weapon=pistol") and not m.player.has_pistol:
		m.player.has_pistol = true
		m.player.ammo["pistol"] = 12
		m.player.reserve["pistol"] = 24
		m.player.set_weapon("pistol")
	if m._test_script == "run" and Engine.get_process_frames() % 10 == 0:
		var an = m.player.anim
		print("ANIM name=", an.current_animation, " playing=", an.is_playing(), " pos=", snappedf(an.current_animation_position, 0.01), " foot=", snappedf(m.player.foot_offset(), 0.001))
	if m._test_script == "idle" or m._test_script == "idleaim":
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--pyaw=") and m._test_script == "idle":
				m.player.yaw = float(a.substr(7))
		# стоит на месте (без стика); idleaim — прицел зажат вправо
		if m._test_script == "idleaim":
			m.stick_r.active = true
			m.stick_r.vec = Vector2(1, 0)
			m.stick_r.len_px = 60.0
		if Engine.get_process_frames() % 4 == 0:
			print("IDLEAIM aiming=", m.player.aiming, " blend=", snappedf(m.player.aim_blend, 0.01), " aim_local=", snappedf(m.player.aim_local, 0.01), " muzzle_h=", snappedf(m.player.muzzle_world().y - m.player.global_position.y, 0.01), " shoulder_h=", snappedf((m.player.skel.global_transform * m.player.skel.get_bone_global_pose(m.player.skel.find_bone("mixamorig_RightArm")).origin).y - m.player.global_position.y, 0.01), " rHand_h=", snappedf((m.player.skel.global_transform * m.player.skel.get_bone_global_pose(m.player.skel.find_bone("mixamorig_RightHand")).origin).y - m.player.global_position.y, 0.01))
	if m._test_script == "start":
		# с места: стик отпущен до 1.5 с, потом полный вперёд; замер расстановки ног (не путаются ли)
		var pl2 = m.player
		m.stick_l.active = m._tt > 1.5
		m.stick_l.vec = Vector2(0, -1) if m._tt > 1.5 else Vector2.ZERO
		var sk2: Skeleton3D = pl2.skel
		var l2: Vector3 = sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("mixamorig_LeftFoot")).origin
		var r2: Vector3 = sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("mixamorig_RightFoot")).origin
		var fwd := Vector3(sin(pl2.yaw), 0, cos(pl2.yaw))
		var rgt := Vector3(fwd.z, 0, -fwd.x)
		print("S ", snappedf(m._tt, 0.001), " ", pl2.anim.current_animation, " ", snappedf(pl2.anim.current_animation_position, 0.01), " lat=", snappedf((l2 - r2).dot(rgt), 0.001), " lon=", snappedf((l2 - r2).dot(fwd), 0.001), " v=", snappedf(pl2.vel.length(), 0.01))
	if m._test_script == "feet":
		var pl = m.player
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--gait="):
				pl.forced_clip = a.substr(7)
		var mag := 0.4 if m._tt < 4.0 else (0.7 if m._tt < 8.0 else 1.0)
		m.stick_l.active = true
		m.stick_l.vec = Vector2(0, -mag)
		pl.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # кадры в тесте медленные: двигаем клип по фикс. dt
		pl.anim.advance(dt)
		var sk: Skeleton3D = pl.skel
		var lf: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftFoot")).origin
		var rf: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_RightFoot")).origin
		var hp: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin
		print("F ", snappedf(m._tt, 0.001), " ", pl.anim.current_animation, " ", snappedf(pl.anim.speed_scale, 0.001), " ", pl.global_position.x, " ", pl.global_position.z, " ", lf.x, " ", lf.y, " ", lf.z, " ", rf.x, " ", rf.y, " ", rf.z, " ", hp.y - pl.global_position.y, " ", lf.y - pl.global_position.y, " ", rf.y - pl.global_position.y)
	match m._test_script:
		"run":
			m.stick_l.active = true
			m.stick_l.vec = Vector2(0, -1)
		"side", "sideaim", "sidewalk":
			# бег/шаг вбок по экрану — снимок в профиль
			m.stick_l.active = true
			m.stick_l.vec = Vector2(0.35 if m._test_script == "sidewalk" else 1.0, 0)
			if m._test_script == "sideaim":
				m.stick_r.active = true
				m.stick_r.vec = Vector2(1, 0)
				m.stick_r.len_px = 60.0
		"fireback":
			m.stick_l.vec = Vector2(0, -1)
			if m._tt > 0.5:
				m.stick_r.active = true
				m.stick_r.vec = Vector2(0.6, 0.8)
				m.stick_r.len_px = 60.0
			if m._tt > 0.3 and m.zombies.list.is_empty():
				m.zombies.spawn()
		"zombie":
			if m.zombies.list.is_empty():
				m.zombies.spawn(); m.zombies.spawn()
				m.zombies.list[0].tile = m.player.tile + Vector2(3, 1)
				m.zombies.list[1].tile = m.player.tile + Vector2(-1, 3)
			m.weapon.auto = m._tt > 1.0 and not OS.get_cmdline_user_args().has("--noauto")
			if Engine.get_process_frames() % 30 == 0:
				print("ZT t=", snappedf(m._tt, 0.1), " hp=", snappedf(m.player.hp, 0.1), " ammo=", m.player.ammo, " res=", m.player.reserve, " reload=", snappedf(m.player.reload_t, 0.01))
		"behind":
			if not m.has_meta("done"):
				m.set_meta("done", true)
				# встать за ближайшее дерево (дальше от камеры)
				var best = null
				var bd := 1e9
				for o in m.world.obstacles_near(m.player.tile):
					if o.tree:
						var d: float = Vector2(o.x, o.y).distance_to(m.player.tile)
						if d < bd:
							bd = d
							best = o
				if best != null:
					var back: Vector3 = m.cam.global_transform.basis.z
					var bt := Vector2(back.x, back.z).normalized()
					m.player.set_tile(Vector2(best.x, best.y) - bt * 1.6)
		"runaim", "runback":
			m.stick_l.active = true
			m.stick_l.vec = Vector2(0, -1)
			m.stick_r.active = true
			m.stick_r.vec = Vector2(1, 0) if m._test_script == "runaim" else Vector2(0.2, 1)
			m.stick_r.len_px = 60.0
			if Engine.get_process_frames() % 20 == 0 and m._tt > 1.0:
				var bd: Vector3 = m.player.barrel_dir()
				print("RUNAIM t=", snappedf(m._tt, 0.1), " legs=", snappedf(rad_to_deg(m.player.yaw), 1), " move=", snappedf(rad_to_deg(_yaw(m.player.move_dir)), 1), " aim=", snappedf(rad_to_deg(m.player.aim_yaw), 1), " twist=", snappedf(rad_to_deg(m.player.aim_local), 1), " barrel=", snappedf(rad_to_deg(atan2(bd.x, bd.z)), 1), " back=", m.player.backpedal, " anim=", m.player.anim.current_animation, " spd=", snappedf(m.player.anim.speed_scale, 0.01), " bullets=", m.weapon.bullets.size())
		"lr", "lrwalk":
			# без прицела: вправо, с 2.5 с — влево, с 5 с — вверх, с 7 с — вниз
			m.stick_l.active = true
			var mag2 := 0.45 if m._test_script == "lrwalk" else 1.0
			var v2 := Vector2(1, 0)
			if m._tt > 2.5: v2 = Vector2(-1, 0)
			if m._tt > 5.0: v2 = Vector2(0, -1)
			if m._tt > 7.0: v2 = Vector2(0, 1)
			m.stick_l.vec = v2 * mag2
			strafe_log(m)
		"strafe", "strafewalk":
			# целится вверх по экрану, идёт вправо, с 2.5 с — влево, с 5 с — вперёд (вверх), с 7 с — назад
			m.stick_r.active = true
			m.stick_r.vec = Vector2(0, -1)
			m.stick_r.len_px = 60.0
			m.stick_l.active = true
			var mag := 0.5 if m._test_script == "strafewalk" else 1.0
			var v := Vector2(1, 0)
			if m._tt > 2.5: v = Vector2(-1, 0)
			if m._tt > 5.0: v = Vector2(0, -1)
			if m._tt > 7.0: v = Vector2(0, 1)
			m.stick_l.vec = v * mag
			strafe_log(m)
		"aim":
			m.stick_r.active = true
			m.stick_r.vec = Vector2(1, 0.3)
			m.stick_r.len_px = 10.0

