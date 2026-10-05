extends Node3D
# Зомби (кнопка «ЗОМБИ +»): идут к бойцу, пуля попадает в случайную часть тела.
# Голова — много урона; рука может оторваться; нога — ломается, зомби ползёт.
# Перенос src/zombie.js (модель Zombie.glb на скелете Mixamo, клипы Walk/Idle/Run).

const HP := 250.0
const WALK_TPS := 0.55
const CRAWL_TPS := 0.22
const HIT_R := 0.38
const REACH := 0.75
const MAX := 6
const PARTS := [
	["head", 0.12, 55.0, 0.0], ["torso", 0.43, 16.0, 0.0],
	["armL", 0.11, 10.0, 28.0], ["armR", 0.11, 10.0, 28.0],
	["legL", 0.115, 12.0, 30.0], ["legR", 0.115, 12.0, 30.0]]
const PART_BONE := {"armL": "LeftArm", "armR": "RightArm", "legL": "LeftUpLeg", "legR": "RightUpLeg"}

var player
var world
var weapon
var effects
var list: Array = []
var _scene: PackedScene
var _decals: Array = []
var _blood_mat: StandardMaterial3D

class Zombie:
	var node: Node3D
	var model: Node3D
	var anim: AnimationPlayer
	var skel: Skeleton3D
	var tile := Vector2.ZERO
	var hp := HP
	var parts := {}
	var lost := {}
	var crawl := false
	var dead := false
	var dead_t := 0.0
	var yaw := 0.0
	var fall := 0.0

func _ready() -> void:
	_scene = load("res://assets/character/Zombie.glb")
	_blood_mat = StandardMaterial3D.new()
	_blood_mat.albedo_color = Color(0.32, 0.03, 0.03, 0.85)
	_blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blood_mat.roughness = 0.3

func spawn() -> void:
	var alive := 0
	for z in list:
		if not z.dead:
			alive += 1
	if alive >= MAX:
		return
	var z := Zombie.new()
	var a := randf() * TAU
	var d := randf_range(7.0, 9.0)
	z.tile = player.tile + Vector2(cos(a), sin(a)) * d
	z.node = Node3D.new()
	add_child(z.node)
	# модель в файле смотрит в -Z — разворачиваем внутри опоры
	z.model = Node3D.new()
	z.model.scale = Vector3.ONE * 0.8
	z.node.add_child(z.model)
	var glb: Node3D = _scene.instantiate()
	glb.rotation.y = PI
	z.model.add_child(glb)
	player.add_xray(glb)
	z.node.add_child(player.make_blob(0.8))
	z.anim = _find(glb, "AnimationPlayer")
	z.skel = _find(glb, "Skeleton3D")
	for p in PARTS:
		if p[3] > 0.0:
			z.parts[p[0]] = p[3]
	if z.skel:
		var m = load("res://scripts/zombie_mod.gd").new()
		m.z = z
		z.skel.add_child(m)
	if z.anim:
		z.anim.play("Walk")
		z.anim.speed_scale = 0.8
		z.anim.seek(randf() * 1.0, true)
	list.append(z)
	_place(z)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

func _place(z: Zombie) -> void:
	z.node.global_position = WorldGen.to_world(z.tile.x, z.tile.y, WorldGen.height(z.tile.x, z.tile.y))
	z.node.rotation.y = z.yaw

func update_zombies(dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var z: Zombie = list[i]
		if z.dead:
			z.dead_t += dt
			z.fall = minf(1.0, z.fall + dt * 2.2)
			z.model.rotation.x = -PI / 2.0 * _ease(z.fall)
			if z.dead_t > 25.0:
				z.node.queue_free()
				list.remove_at(i)
			continue
		var to: Vector2 = player.tile - z.tile
		var dist := to.length()
		var want_yaw := atan2(to.x, to.y)
		z.yaw = lerp_angle(z.yaw, want_yaw, minf(1.0, 3.0 * dt))
		if dist > REACH:
			var sp := CRAWL_TPS if z.crawl else WALK_TPS
			var prev := z.tile
			z.tile += to / dist * sp * dt
			if effects:
				effects.step(z, z.tile, dt, true)
			_collide(z, prev)
			if z.anim and z.anim.current_animation != "Walk":
				z.anim.play("Walk", 0.2)
		else:
			if z.anim and z.anim.current_animation != "Idle":
				z.anim.play("Idle", 0.2)
		if z.anim:
			z.anim.speed_scale = 0.35 if z.crawl else 0.75
		z.model.rotation.x = 1.25 if z.crawl else 0.0
		_place(z)
	for i in range(_decals.size() - 1, -1, -1):
		var d: Dictionary = _decals[i]
		d.age += dt
		if d.age > 40.0:
			d.node.queue_free()
			_decals.remove_at(i)

func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

func _collide(z: Zombie, prev: Vector2) -> void:
	for o in world.obstacles_near(z.tile):
		var d: Vector2 = z.tile - Vector2(o.x, o.y)
		var l := d.length()
		if l < o.r and l > 1e-4:
			z.tile = Vector2(o.x, o.y) + d / l * o.r

func bullet_hit(b: Dictionary) -> bool:
	for z in list:
		if z.dead:
			continue
		var d: Vector2 = Vector2(b.x, b.y) - z.tile
		if d.length() > HIT_R:
			continue
		var gz := WorldGen.height_m(z.tile.x, z.tile.y)
		var top := gz + (0.6 if z.crawl else 1.9)
		if b.z < gz or b.z > top:
			continue
		_damage(z, b)
		return true
	return false

func _damage(z: Zombie, b: Dictionary) -> void:
	var r := randf()
	var part := "torso"
	var dmg := 16.0
	for p in PARTS:
		if r < p[1]:
			part = p[0]
			dmg = p[2]
			break
		r -= p[1]
	z.hp -= dmg
	var hit_p := Vector3(b.x * WorldGen.T, b.z, b.y * WorldGen.T)
	for i in 4:
		weapon._puff(hit_p, Vector3(b.dx * randf_range(0.5, 1.5), randf_range(0.2, 1.0), b.dy * randf_range(0.5, 1.5)) + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), Color(0.45, 0.02, 0.02, 0.8), 0.07, 0.5)
	if randf() < 0.6:
		_blood_decal(z.tile + Vector2(b.dx, b.dy) * randf_range(0.2, 0.6), randf_range(0.25, 0.5))
	if z.parts.has(part) and not z.lost.has(part):
		z.parts[part] -= dmg
		if z.parts[part] <= 0.0:
			if part.begins_with("arm"):
				z.lost[part] = true
				_blood_decal(z.tile, 0.6)
			elif part.begins_with("leg"):
				z.crawl = true
				if randf() < 0.5:
					z.lost[part] = true
	if z.hp <= 0.0:
		z.dead = true
		if z.anim:
			z.anim.play("Idle", 0.1)
			z.anim.speed_scale = 0.0
		_blood_decal(z.tile, 0.9)

func _blood_decal(t: Vector2, s: float) -> void:
	var m := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(s, s * randf_range(0.6, 1.0))
	m.mesh = q
	var mat: StandardMaterial3D = _blood_mat.duplicate()
	mat.albedo_texture = weapon._soft_tex()
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.global_position = WorldGen.to_world(t.x, t.y, WorldGen.height(t.x, t.y)) + Vector3(0, 0.03, 0)
	m.rotation.y = randf() * TAU
	_decals.append({"node": m, "age": 0.0})
	if _decals.size() > 60:
		_decals[0].node.queue_free()
		_decals.remove_at(0)
