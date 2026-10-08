extends Node
# Краска машин и вертолёта лежит в цвете вершин, база материала paint белая.
# Godot показывает базу, пока не включить vertex_color_use_as_albedo.
# Только эти имена: фото-материалы домов не трогаем.

const NEED := ["paint", "paint_matte", "wagon_red", "spray", "fabric"]

func _ready() -> void:
	var root := get_tree().root
	if get_parent() != root:
		reparent(root)
	if not get_tree().node_added.is_connected(_on_node):
		get_tree().node_added.connect(_on_node)
	_walk(root)

func _on_node(n: Node) -> void:
	_walk(n)

func _walk(n: Node) -> void:
	if n is MeshInstance3D and n.mesh:
		_fix(n.mesh)
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
		_fix(n.multimesh.mesh)
	for c in n.get_children():
		_walk(c)

func _fix(m: Mesh) -> void:
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		if mat is BaseMaterial3D and str(mat.resource_name) in NEED:
			mat.vertex_color_use_as_albedo = true
