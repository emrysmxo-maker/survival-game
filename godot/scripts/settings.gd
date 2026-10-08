extends Node
# Качество графики: 4 уровня, сохраняется в user://settings.cfg.
#  Низкое/Среднее — земля без анти-повтора текстур (вдвое меньше выборок). Низкое — экран 65%, без сглаживания, тени 1024 жёсткие, без теней крон, рельеф земли выкл, трава 35%, мир 5×5 чанков.
#  Среднее  — экран 80%, без сглаживания, тени 2048, тени крон, рельеф выкл, трава 60%, 5×5.
#  Высокое  — экран 100%, сглаживание 2x, тени 4096, рельеф земли, трава 85%, 7×7.
#  Максимум — экран 100%, сглаживание 4x, тени 4096 мягкие, рельеф, вся трава, 7×7.
#  Кадры (отдельно): «максимум» — без ограничения fps и vsync, «60» — 60 fps с vsync (меньше греется).

const NAMES := ["Низкое", "Среднее", "Высокое", "Максимум"]
const PATH := "user://settings.cfg"
var level := 2
var fps_max := true        # «Кадры: максимум» — без ограничения и без вертикальной синхронизации (сколько выдаст телефон)
var main

func load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		level = clampi(int(cf.get_value("gfx", "level4", 2)), 0, 3)
		fps_max = bool(cf.get_value("gfx", "fpsmax", true))
	apply(level)

func apply(l: int) -> void:
	level = l
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.65, 0.8, 1.0, 1.0][l]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][l]
	RenderingServer.directional_shadow_atlas_set_size([1024, 2048, 4096, 4096][l], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][l])
	RenderingServer.global_shader_parameter_set("q_ground_normals", l >= 2)
	apply_fps()
	if main and main.world:
		main.world.load_radius = [2, 2, 3, 3][l]
		main.world.crown_shadows = l >= 1
		main.world.ground_detail = l >= 2
		main.world._dirty = true
		main.world.set_density([0.35, 0.6, 0.85, 1.0][l])
	_save()

func apply_fps() -> void:
	Engine.max_fps = 0 if fps_max else 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if fps_max else DisplayServer.VSYNC_ENABLED)

func set_fps_max(on: bool) -> void:
	fps_max = on
	apply_fps()
	_save()

func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "level4", level)
	cf.set_value("gfx", "fpsmax", fps_max)
	cf.save(PATH)
