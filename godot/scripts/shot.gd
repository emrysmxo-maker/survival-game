extends Node
# Снимки экрана без телефона (сервер GitHub / программный Vulkan). Включается аргументом --shot=<папка>.
#   --views=x:y[:cam[:yaw[:elev[:time]]]]/x:y...   — точки съёмки (тайлы), по снимку на каждую
#   --shots=N --every=сек                          — серия кадров с каждой точки («видео» картинками)
#   --wait=сек                                     — пауза после загрузки чанков перед снимком (по умолчанию 1.5)
# Файлы: <папка>/shot_<точка>_<кадр>.jpg; в лог — строка SHOT с местом, загрузкой и деревьями.
var main
var out := ""
var views: Array = []
var shots := 1
var every := 0.5
var wait := 1.5

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.substr(7)
		if a.begins_with("--views="):
			for v in a.substr(8).split("/", false): views.append(v.split(":"))
		if a.begins_with("--shots="): shots = maxi(1, int(a.substr(8)))
		if a.begins_with("--every="): every = float(a.substr(8))
		if a.begins_with("--wait="): wait = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(out)
	if views.is_empty():
		views.append([str(main.focus.x), str(main.focus.y)])
	_run()

func _sleep(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _run() -> void:
	await _sleep(0.5)
	for i in views.size():
		var v: PackedStringArray = views[i]
		if v.size() > 2 and v[2] != "": main.cam_size = float(v[2])
		if v.size() > 3 and v[3] != "": main.cam_yaw = float(v[3])
		if v.size() > 4 and v[4] != "": main.cam_elev = float(v[4])
		if v.size() > 5 and v[5] != "":
			main.daynight.t = float(v[5]); main.daynight.auto = false
		main.teleport(Vector2(float(v[0]), float(v[1])))
		var t0 := Time.get_ticks_msec()
		while (main.world.pending.size() > 0 or Time.get_ticks_msec() - t0 < 500) and Time.get_ticks_msec() - t0 < 60000:
			await _sleep(0.1)
		await _sleep(wait)
		for k in shots:
			await RenderingServer.frame_post_draw
			var path := "%s/shot_%02d_%02d.jpg" % [out, i, k]                # JPG ~0,3–0,5 МБ: коннекторы ИИ не берут файлы > 1 МБ
			get_viewport().get_texture().get_image().save_jpg(path, 0.82)
			print("SHOT %s  точка %s,%s  cam %.0f yaw %.0f elev %.0f  чанков ждали %.1f с  деревьев рядом %d  fps %d" % [path, v[0], v[1],
				main.cam_size, main.cam_yaw, main.cam_elev, (Time.get_ticks_msec() - t0) / 1000.0, main.world.count_trees(), Engine.get_frames_per_second()])
			if k < shots - 1: await _sleep(every)
	print("SHOT done")
	get_tree().quit()
