extends SceneTree
# Сборка анимаций из мокапа (JSON от tools/mocap/make_clips.py) в библиотеку Godot:
# godot --headless --path godot -s res://scripts/build_mocap.gd -- <clips.json>  → res://assets/character/mocap.res
func _init() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var lib := AnimationLibrary.new()
	var sp := {}
	for name in d:
		var c: Dictionary = d[name]
		var a := Animation.new()
		a.length = float(c.length)
		a.loop_mode = Animation.LOOP_LINEAR if c.get("loop", true) else Animation.LOOP_NONE
		var fps := float(c.fps)
		var hips: Array = c.hips
		var ti := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(ti, "Armature/Skeleton3D:mixamorig_Hips")
		for i in hips.size():
			a.position_track_insert_key(ti, i / fps, Vector3(hips[i][0], hips[i][1], hips[i][2]))
		for bn in c.rot:
			var qs: Array = c.rot[bn]
			ti = a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(ti, "Armature/Skeleton3D:mixamorig_" + bn)
			for i in qs.size():
				a.rotation_track_insert_key(ti, i / fps, Quaternion(qs[i][0], qs[i][1], qs[i][2], qs[i][3]).normalized())
		lib.add_animation(name, a)
		sp[name] = c.speed
	print("clips ", lib.get_animation_list())
	print(ResourceSaver.save(lib, "res://assets/character/mocap.res"))
	var f := FileAccess.open("res://assets/character/mocap_speeds.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(sp))
	quit()
