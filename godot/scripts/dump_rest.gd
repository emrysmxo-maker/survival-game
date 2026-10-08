extends SceneTree
# Выгрузка позы покоя скелета бойца (для переноса мокапа): godot --headless --path godot -s res://scripts/dump_rest.gd -- <out.json>
func _init() -> void:
	var root: Node = (load("res://assets/character/Survivor.glb") as PackedScene).instantiate()
	get_root().add_child(root)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for i in sk.get_bone_count():
		var g := Transform3D.IDENTITY
		var b := i
		while b >= 0:
			g = sk.get_bone_rest(b) * g
			b = sk.get_bone_parent(b)
		var q := g.basis.orthonormalized().get_rotation_quaternion()
		var r := sk.get_bone_rest(i)
		var lq := r.basis.orthonormalized().get_rotation_quaternion()
		out.append({"name": sk.get_bone_name(i), "parent": sk.get_bone_parent(i), "pos": [g.origin.x, g.origin.y, g.origin.z],
			"rot": [q.x, q.y, q.z, q.w], "lpos": [r.origin.x, r.origin.y, r.origin.z], "lrot": [lq.x, lq.y, lq.z, lq.w]})
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_string(JSON.stringify({"bones": out, "skel_path": str(root.get_path_to(sk))}))
	quit()
