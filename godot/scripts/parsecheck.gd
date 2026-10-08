extends SceneTree
# Загружает все скрипты и шейдеры проекта — ошибки разбора видны без запуска игры.
# godot --headless --path godot -s res://scripts/parsecheck.gd
func _init() -> void:
	var bad := 0
	for dir in ["res://scripts", "res://shaders"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd") or f.ends_with(".gdshader"):
				var r = load(dir + "/" + f)
				if r == null or (r is GDScript and not r.can_instantiate()):
					print("PARSE FAIL ", f)
					bad += 1
	print("PARSECHECK ok" if bad == 0 else "PARSECHECK ошибок: %d" % bad)
	quit()
