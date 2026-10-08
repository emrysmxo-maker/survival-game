extends Node3D
# Заброшенные постройки и машины (assets/props/*.glb, строятся в Blender: tools/props). Ставятся один раз при запуске:
# на локациях по списку SETS (смещения от центра локации в тайлах, поворот в градусах) и ржавые остовы вдоль дорог.
# Дом: «лицо» (крыльцо) смотрит в +Z модели; машина: нос смотрит в +X модели. Модели собраны в метрах, масштаб S — как у мира.

const S := 0.8
const CARS := ["car_sedan_red", "car_sedan_blue", "car_sedan_white", "car_sedan_burnt", "car_van_olive", "car_van_white", "car_truck_blue", "car_truck_green"]
# [модель, dx, dy, yaw°]; yaw 0 — лицом в +y (на юг карты), 180 — на север; у машин yaw 0 — носом на +x (восток)
const SETS := {
	"village": [
		["house_izba_a", -17, -10, 0], ["house_brick", -5, -11, 0], ["house_izba_b", 8, -10, -6], ["shed_blue", 17, -8, 20],
		["house_izba_b", -15, 10, 180], ["house_izba_a", -2, 11, 172], ["house_brick", 11, 10, 188], ["shed_green", -21, 3, 90],
		["car_sedan_blue", -9, 1.5, 84], ["car_van_olive", 5, -1.5, 96], ["car_sedan_burnt", 15, 2, 20],
	],
	"farm": [
		["barn", -7, -8, 0], ["barn", 10, 6, 90], ["house_brick", -14, 8, 180], ["shed_green", 5, -14, 0], ["shed_blue", -3, 12, 180],
		["car_truck_green", -1, 3, 24], ["car_truck_blue", 15, -8, -50], ["car_van_white", -8, 4, 200],
	],
	"sawmill": [
		["shed_blue", -8, -4, 0], ["shed_green", 7, -5, 10], ["house_izba_b", -7, 7, 180], ["car_truck_green", 3, 4, -10], ["car_sedan_white", 9, 8, 140],
	],
	"lakebase": [
		["shed_blue", -6, -5, 0], ["shed_green", 4, -7, -15], ["house_izba_a", -3, 6, 180], ["car_sedan_white", 6, 3, 200],
	],
	"bunker": [
		["shed_green", -6, -6, 0], ["car_van_olive", 5, 4, 35], ["car_truck_green", -4, 6, 160],
	],
	"tower": [
		["shed_green", -5, -4, 0], ["car_van_white", 4, 4, 210],
	],
	"camp": [
		["shed_blue", 8, -6, 15], ["car_van_olive", -7, 6, 160],
	],
}
var _scenes := {}
var _n := 0

func _ready() -> void:
	for key in SETS:
		var f: Dictionary = WorldGen.FEATURES[key]
		for p in SETS[key]:
			_place(p[0], f.x + p[1], f.y + p[2], p[3])
	_road_wrecks()
	print("props: ", _n)

func _h(x: float, y: float) -> float:
	return WorldGen.height_m(x, y)

func _place(model: String, tx: float, ty: float, yaw_deg: float) -> void:
	if not _scenes.has(model):
		var path := "res://assets/props/%s.glb" % model
		_scenes[model] = load(path) if ResourceLoader.exists(path) else null
	var sc: PackedScene = _scenes[model]
	if sc == null:
		return
	var t := WorldGen.terrain(tx, ty)
	if t[1] > 0.02:                       # в воде не ставим
		return
	var node: Node3D = sc.instantiate()
	var th := deg_to_rad(yaw_deg)
	var is_car := model.begins_with("car_")
	var yb := Basis(Vector3.UP, th)
	var y: float
	if is_car:
		# машина стоит по склону: наклон по носу и по борту, одно колесо спущено — чуть заваливается
		var f := Vector2(cos(th), -sin(th))
		var r := Vector2(sin(th), cos(th))
		var d := 2.0
		var hf := _h(tx + f.x * d, ty + f.y * d) - _h(tx - f.x * d, ty - f.y * d)
		var hr := _h(tx + r.x * d, ty + r.y * d) - _h(tx - r.x * d, ty - r.y * d)
		var pitch := atan2(hf, 2.0 * d * WorldGen.T)
		var roll := -atan2(hr, 2.0 * d * WorldGen.T)
		yb = yb * Basis(Vector3(0, 0, 1), pitch) * Basis(Vector3(1, 0, 0), roll + 0.02 * sin(tx * 3.1))
		y = _h(tx, ty) - 0.02
	else:
		y = minf(minf(_h(tx - 3, ty - 3), _h(tx + 3, ty + 3)), minf(_h(tx - 3, ty + 3), minf(_h(tx + 3, ty - 3), _h(tx, ty)))) - 0.12
	node.transform = Transform3D(yb * S, Vector3(tx * WorldGen.T, y, ty * WorldGen.T))
	add_child(node)
	_n += 1

# ржавые остовы на дорогах между локациями
func _road_wrecks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ri := 0
	for rd in WorldGen._roads:
		var pts: PackedVector2Array = rd.pts
		var n := 2 + (ri % 2)
		ri += 1
		for k in n:
			var i := 1 + rng.randi() % (pts.size() - 3)
			var a := pts[i]
			var dir := (pts[i + 1] - pts[i]).normalized()
			var off := Vector2(-dir.y, dir.x) * rng.randf_range(-1.4, 1.4)
			var p := a + dir * rng.randf() * 3.0 + off
			var near_loc := false
			for key in WorldGen.FEATURES:       # у локаций машины расставлены вручную
				var f: Dictionary = WorldGen.FEATURES[key]
				if Vector2(p.x - f.x, p.y - f.y).length() < f.r + 3.0:
					near_loc = true
			if near_loc:
				continue
			var yaw := rad_to_deg(atan2(-dir.y, dir.x)) + (0.0 if rng.randf() < 0.5 else 180.0) + rng.randf_range(-18.0, 18.0)
			if rng.randf() < 0.25:
				yaw += rng.randf_range(40.0, 70.0)       # съехала в кювет
			_place(CARS[rng.randi() % CARS.size()], p.x, p.y, yaw)
