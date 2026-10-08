extends Node3D
# Лут на земле: пистолет, автомат (патроны к нему), патроны, каска, бронежилет, аптечка.
# Предметы раскладываются вокруг бойца (не в воде, не в деревьях), подбираются, когда боец подходит вплотную.
# Рядом с предметом — светлое кольцо, чтобы его было видно сверху. Модели оружия и каски — Kevin Iglesias.

const KEEP := 14                 # сколько предметов держать вокруг бойца
const R_MIN := 6.0               # тайлов от бойца при появлении
const R_MAX := 34.0
const R_FORGET := 60.0           # дальше — убираем (появятся новые ближе)
const PICK_R := 0.75             # тайлов — подбор
const KINDS := [                 # вид, вес, модель (или "" — простая коробка)
	["pistol", 1.0, "res://assets/loot/loot_pistol.glb"],
	["rifle_ammo", 3.0, ""],
	["pistol_ammo", 2.0, ""],
	["rifle", 1.0, "res://assets/loot/loot_rifle.glb"],
	["helmet", 1.0, "res://assets/loot/loot_helmet.glb"],
	["vest", 1.0, ""],
	["medkit", 1.5, ""]]
const NAMES := {"pistol": "Пистолет", "rifle_ammo": "Патроны 5.56", "pistol_ammo": "Патроны 9 мм", "rifle": "Автомат (патроны)",
	"helmet": "Каска", "vest": "Бронежилет", "medkit": "Аптечка"}

var player
var world
var hud
var items: Array = []
var _scenes := {}
var _ring_mat: StandardMaterial3D
var _ring_mesh: TorusMesh
var _rng := RandomNumberGenerator.new()
var _first := true

func _ready() -> void:
	_rng.seed = 7351
	for k in KINDS:
		if k[2] != "" and ResourceLoader.exists(k[2]):
			_scenes[k[0]] = load(k[2])
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.30
	_ring_mesh.outer_radius = 0.34
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(1.0, 0.86, 0.45, 0.75)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _pick_kind() -> String:
	var tot := 0.0
	for k in KINDS:
		tot += k[1]
	var r := _rng.randf() * tot
	for k in KINDS:
		if r < k[1]:
			return k[0]
		r -= k[1]
	return "rifle_ammo"

func _free_spot(t: Vector2) -> bool:
	if WorldGen.water_at(t.x, t.y).x > 0.2:
		return false
	for o in world.obstacles_near(t):
		if Vector2(o.x, o.y).distance_to(t) < o.r + 0.5:
			return false
	return true

func _spawn(kind: String, t: Vector2) -> void:
	var n := Node3D.new()
	add_child(n)
	var vis: Node3D
	if _scenes.has(kind):
		vis = _scenes[kind].instantiate()
		if kind == "helmet":
			vis.scale = Vector3.ONE * 1.0
	else:
		vis = _box(kind)
	n.add_child(vis)
	vis.rotation.y = _rng.randf() * TAU
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = 0.02
	n.add_child(ring)
	n.global_position = WorldGen.to_world(t.x, t.y, WorldGen.height_m(t.x, t.y))
	items.append({"kind": kind, "tile": t, "node": n, "ring": ring, "ph": _rng.randf() * TAU})

func _box(kind: String) -> Node3D:
	# патроны — зелёный ящик, аптечка — белая с красным, бронежилет — тёмная «плита»
	var root := Node3D.new()
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	match kind:
		"rifle_ammo":
			b.size = Vector3(0.30, 0.16, 0.16); mat.albedo_color = Color(0.25, 0.32, 0.18)
		"pistol_ammo":
			b.size = Vector3(0.20, 0.10, 0.12); mat.albedo_color = Color(0.32, 0.30, 0.18)
		"medkit":
			b.size = Vector3(0.26, 0.12, 0.18); mat.albedo_color = Color(0.92, 0.92, 0.9)
		"vest":
			b.size = Vector3(0.42, 0.08, 0.48); mat.albedo_color = Color(0.12, 0.13, 0.12)
	m.mesh = b
	m.material_override = mat
	m.position.y = b.size.y * 0.5
	root.add_child(m)
	if kind == "medkit":
		for i in 2:
			var c := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(0.14, 0.01, 0.04) if i == 0 else Vector3(0.04, 0.01, 0.14)
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color(0.8, 0.08, 0.08)
			c.mesh = cb
			c.material_override = cm
			c.position.y = b.size.y + 0.005
			root.add_child(c)
	if kind.ends_with("_ammo"):
		var lid := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(b.size.x * 0.9, 0.012, b.size.z * 0.5)
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.75, 0.6, 0.2)
		lid.mesh = lb
		lid.material_override = lm
		lid.position.y = b.size.y + 0.006
		root.add_child(lid)
	return root

func update_loot(dt: float) -> void:
	if player == null:
		return
	var pt: Vector2 = player.tile
	# убрать далёкие
	for i in range(items.size() - 1, -1, -1):
		if items[i].tile.distance_to(pt) > R_FORGET:
			items[i].node.queue_free()
			items.remove_at(i)
	# досыпать (в начале — сразу всё; первым — пистолет недалеко, чтобы его было легко найти)
	var tries := 40 if _first else 3
	while items.size() < KEEP and tries > 0:
		tries -= 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(R_MIN, R_MAX if not _first else R_MAX * 0.6)
		var t := pt + Vector2(cos(a), sin(a)) * r
		if not _free_spot(t):
			continue
		var kind := "pistol" if (_first and items.is_empty()) else _pick_kind()
		if _first and items.is_empty():
			t = pt + Vector2(cos(a), sin(a)) * 4.5
			if not _free_spot(t):
				continue
		_spawn(kind, t)
	_first = false
	# подбор и «пульс» колец
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it.ph += dt * 3.0
		it.ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(it.ph))
		if it.tile.distance_to(pt) < PICK_R and not player.swimming:
			var msg := _take(it.kind)
			if msg != "":
				it.node.queue_free()
				items.remove_at(i)
				if hud:
					hud.toast(msg)

# применить предмет к бойцу; "" — не нужен (не подбираем)
func _take(kind: String) -> String:
	match kind:
		"pistol":
			if not player.has_pistol:
				player.has_pistol = true
				player.ammo["pistol"] = 12
				player.reserve["pistol"] += 24
				return "Пистолет! Кнопка «ОРУЖИЕ» — сменить"
			player.reserve["pistol"] += 12
			return "+12 патронов 9 мм"
		"rifle":
			player.reserve["rifle"] += 30
			return "Автомат: +30 патронов 5.56"
		"rifle_ammo":
			player.reserve["rifle"] += 30
			return "+30 патронов 5.56"
		"pistol_ammo":
			player.reserve["pistol"] += 15
			return "+15 патронов 9 мм"
		"helmet":
			if player.helmet:
				return ""
			player.helmet = true
			player.armor = minf(100.0, player.armor + 30.0)
			return "Каска: броня +30"
		"vest":
			if player.vest:
				return ""
			player.vest = true
			player.armor = minf(100.0, player.armor + 50.0)
			return "Бронежилет: броня +50"
		"medkit":
			if player.hp >= 99.0:
				return ""
			player.hp = minf(100.0, player.hp + 50.0)
			return "Аптечка: здоровье +50"
	return ""
