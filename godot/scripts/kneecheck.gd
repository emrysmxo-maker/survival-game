extends SceneTree
# Запуск: godot --headless --path godot -s res://scripts/kneecheck.gd [-- --fix]  (колено относительно таза по всем записям)
# Проверка записей: колено относительно носка стопы (градусы) по всем клипам модели.
func _bp(sk: Skeleton3D, n: String) -> Vector3:
	var bi := sk.find_bone("mixamorig_" + n)
	var g := Transform3D.IDENTITY
	while bi >= 0:
		g = sk.get_bone_pose(bi) * g
		bi = sk.get_bone_parent(bi)
	return g.origin

func _init() -> void:
	var scn: PackedScene = load("res://assets/character/Survivor.glb")
	var root := scn.instantiate()
	get_root().add_child(root)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	if "--fix" in OS.get_cmdline_user_args():
		load("res://scripts/player.gd").fix_strafe_pelvis(ap, sk)
	for an in ap.get_animation_list():
		var a := ap.get_animation(an)
		var res := {}
		for side in ["Left", "Right"]:
			res[side] = []
		var N := 24
		for i in N:
			var t := a.length * i / N
			sk.reset_bone_poses()
			for ti in a.get_track_count():
				var bn := str(a.track_get_path(ti)).get_slice(":", 1)
				var bi := sk.find_bone(bn)
				if bi < 0: continue
				if a.track_get_type(ti) == Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bi, a.rotation_track_interpolate(ti, t))
				elif a.track_get_type(ti) == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bi, a.position_track_interpolate(ti, t))
			for side in ["Left", "Right"]:
				var hp := _bp(sk, side + "UpLeg"); var kn := _bp(sk, side + "Leg"); var ft := _bp(sk, side + "Foot"); var toe := _bp(sk, side + "ToeBase")
				var bend := rad_to_deg((hp - kn).angle_to(ft - kn))
				if bend > 160.0:
					continue
				var ax := (ft - hp).normalized()
				var kd := kn - hp; kd -= ax * kd.dot(ax)
				var rgt := _bp(sk, "RightUpLeg") - _bp(sk, "LeftUpLeg")
				var upv := _bp(sk, "Spine") - _bp(sk, "Hips")
				var td := upv.cross(rgt); td -= ax * td.dot(ax)     # вперёд таза
				res[side].append(absf(rad_to_deg(kd.signed_angle_to(td, ax))))
		var line := an
		for side in ["Left", "Right"]:
			var arr: Array = res[side]
			if arr.is_empty():
				line += "  %s: прямая" % side
			else:
				var s := 0.0
				for v in arr: s += v
				line += "  %s: ср %d макс %d (n=%d)" % [side, int(s / arr.size()), int(arr.max()), arr.size()]
		print(line)
	quit()
