extends Node
# Качество графики: «Среднее», «Высокое», «Максимум». Сохраняется в user://settings.cfg.
#  Среднее — экран 75%, без сглаживания, тени 2048, земля без карт рельефа, трава 50%, 60 fps.
#  Высокое — экран 100%, сглаживание 2x, тени 4096, рельеф земли, трава 80%, до 90 fps.
#  Максимум — экран 100%, сглаживание 4x, тени 4096 мягкие, рельеф земли, вся трава, без ограничения fps.

const NAMES := ["Среднее", "Высокое", "Максимум"]
const PATH := "user://settings.cfg"
var level := 1
var main

func load_saved() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		level = clampi(int(cf.get_value("gfx", "level", 1)), 0, 2)
	apply(level)

func apply(l: int) -> void:
	level = l
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.75, 1.0, 1.0][l]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][l]
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][l], true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][l])
	RenderingServer.global_shader_parameter_set("q_ground_normals", l >= 1)
	Engine.max_fps = [60, 90, 0][l]
	if main and main.world:
		main.world.load_radius = [2, 3, 3][l]
	if main and main.world:
		main.world.set_density([0.5, 0.8, 1.0][l])
	var cf := ConfigFile.new()
	cf.set_value("gfx", "level", l)
	cf.save(PATH)
