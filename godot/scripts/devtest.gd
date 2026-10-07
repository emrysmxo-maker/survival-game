extends RefCounted
# Проверки без экрана (запуск с --test=start|run|side|sideaim|sidewalk|runaim|runback|fireback|zombie|behind|aim): сценарии
# управления и вывод замеров в лог. В обычной игре не используется.

static func _yaw(d: Vector2) -> float:
	return atan2(d.x, d.y)

static func run(m, dt: float) -> void:
	if m._test_script == "run" and Engine.get_process_frames() % 10 == 0:
		var an = m.player.anim
		print("ANIM name=", an.current_animation, " playing=", an.is_playing(), " pos=", snappedf(an.current_animation_position, 0.01), " foot=", snappedf(m.player.foot_offset(), 0.001))
	if m._test_script == "idle" or m._test_script == "idleaim":
		# стоит на месте (без стика); idleaim — прицел зажат вправо
		if m._test_script == "idleaim":
			m.stick_r.active = true
			m.stick_r.vec = Vector2(1, 0)
			m.stick_r.len_px = 60.0
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
			m.weapon.auto = m._tt > 1.0
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
		"aim":
			m.stick_r.active = true
			m.stick_r.vec = Vector2(1, 0.3)
			m.stick_r.len_px = 10.0

