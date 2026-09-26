extends "res://scripts/ui/Фигурки3Д.gd"
## Preserve the native frame pipeline, replacing only the tank constructor.

var pax_mod: Node
var tank_length: float = 32.0
var tank_builds: int = 0

func set_display_length(value: float) -> void:
	var next: float = clampf(value, 24.0, 36.0)
	if is_equal_approx(next, tank_length):
		return
	var ratio: float = next / tank_length
	var crew_delta: float = 18.0 * (next - tank_length) / 32.0
	for squad: Dictionary in _узлы.values():
		var has_tank: bool = false
		for item: Dictionary in squad.get("техника", []):
			var node: Node3D = item.get("узел") as Node3D
			if node != null and node.name == "PaxTankFigure" and node.get_child_count() > 0:
				var model_node: Node3D = node.get_child(0) as Node3D
				model_node.scale *= ratio
				model_node.position *= ratio
				has_tank = true
		if has_tank:
			for person: Dictionary in squad.get("люди", []):
				var node: Node3D = person.get("узел") as Node3D
				if node != null:
					node.position.x -= crew_delta
	tank_length = next

func _танк(цвет: Color) -> Dictionary:
	if not is_instance_valid(pax_mod):
		return super._танк(цвет)
	var model_node: Node3D = pax_mod.call("tank_instance") as Node3D
	if model_node == null:
		return super._танк(цвет)
	var root: Node3D = Node3D.new()
	root.name = "PaxTankFigure"
	root.add_child(model_node)
	var bounds: AABB = pax_mod.get("_tank_bounds")
	var length: float = maxf(bounds.size.z, 0.01)
	var factor: float = tank_length / length
	model_node.scale = Vector3.ONE * factor
	# Our GLB points toward -Z; the native figurine forward axis is +X.
	model_node.rotation.y = -PI / 2.0
	# Center its footprint and place the lowest tread on the native ground plane.
	var center: Vector3 = bounds.position + bounds.size * 0.5
	model_node.position = Vector3(center.z * factor, -bounds.position.y * factor, -center.x * factor)
	tank_builds += 1
	return {"узел": root, "модель": true}

func _собрать_отряд(о: Dictionary, подпись: String) -> Dictionary:
	var result: Dictionary = super._собрать_отряд(о, подпись)
	var has_tank: bool = false
	for item: Dictionary in result.get("техника", []):
		var node: Node3D = item.get("узел") as Node3D
		if node != null and node.name == "PaxTankFigure":
			has_tank = true
	if has_tank:
		# Keep the native crew visible beside the enlarged hull.
		for person: Dictionary in result.get("люди", []):
			var node: Node3D = person.get("узел") as Node3D
			if node != null:
				node.position.x -= 18.0 * tank_length / 32.0
	return result
