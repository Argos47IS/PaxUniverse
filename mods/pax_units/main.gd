extends PaxMod
## Visual-only tank prototype. Original map renderer remains available for restoration.

var _template: Node3D
var _tank_bounds: AABB
var _map: CanvasLayer
var _original: SubViewport
var _replacement: SubViewport
var _picture: TextureRect
var _original_mode: int = SubViewport.UPDATE_ALWAYS
var _clock: float = 0.0
var _unloaded: bool = false

func _mod_loaded() -> void:
	set_process(true)
	if OS.get_cmdline_user_args().has("--units-live-test"):
		call_deferred("_run_test")

func _process(delta: float) -> void:
	if _unloaded:
		return
	_clock += delta
	if _clock < 0.5:
		return
	_clock = 0.0
	if is_instance_valid(Pax.game):
		var main: Node = Pax.game.main
		if not is_instance_valid(main):
			_restore()
			return
		var map: CanvasLayer = main.get("полит_карта") as CanvasLayer
		if is_instance_valid(map) and map != _map:
			attach_map(map)
		elif map == null and is_instance_valid(_replacement):
			_restore()
		if is_instance_valid(_replacement) and is_instance_valid(_map):
			_update_scale()
	elif is_instance_valid(_replacement):
		_restore()

func _world_ready(_game: PaxGame) -> void:
	_clock = 0.5

func tank_instance() -> Node3D:
	if not is_instance_valid(_template):
		_template = model("models/atlas_mbt.glb")
		if _template == null:
			return null
		_tank_bounds = _bounds(_template, Transform3D.IDENTITY)
	return _template.duplicate() as Node3D

func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result: AABB = AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = transform * (node as MeshInstance3D).get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var box: AABB = _bounds(child as Node3D, transform)
			if box.size.length_squared() > 0.0:
				result = box if result.size.length_squared() == 0.0 else result.merge(box)
	return result

func attach_map(map: CanvasLayer) -> bool:
	if _unloaded or map == _map:
		return false
	var original: SubViewport = map.get("фигурки") as SubViewport
	var picture: TextureRect = map.get("показ_фигурок") as TextureRect
	if original == null or picture == null:
		return false
	for method: String in ["кадр", "_танк", "задать_размер", "очистить", "_собрать_отряд"]:
		if not original.has_method(method):
			return false
	var has_spacesuits: bool = false
	for info: Dictionary in original.get_property_list():
		if str(info.name) == "в_скафандрах":
			has_spacesuits = true
	if not has_spacesuits:
		return false
	var script: Script = load(path("figures.gd")) as Script
	if script == null or not script.can_instantiate():
		return false
	var check: Node3D = tank_instance()
	if check == null:
		return false
	check.free()
	_restore()
	_map = map
	_original = original
	_picture = picture
	_original_mode = original.render_target_update_mode
	_replacement = script.new() as SubViewport
	if _replacement == null:
		_restore()
		return false
	_replacement.name = "PaxUnitsFigures"
	_replacement.set("pax_mod", self)
	_replacement.set("в_скафандрах", original.get("в_скафандрах"))
	original.get_parent().add_child(_replacement)
	_replacement.call("задать_размер", Vector2(original.size))
	original.render_target_update_mode = SubViewport.UPDATE_DISABLED
	map.set("фигурки", _replacement)
	picture.texture = _replacement.get_texture()
	_update_scale()
	return true

func _update_scale() -> void:
	var zoom: float = float(_map.get("зум"))
	var length: float = lerpf(24.0, 32.0, clampf((zoom - 7.0) / 6.0, 0.0, 1.0))
	if zoom > 13.0:
		length = lerpf(32.0, 36.0, clampf((zoom - 13.0) / 13.0, 0.0, 1.0))
	_replacement.call("set_display_length", length)

func _restore() -> void:
	if is_instance_valid(_map) and is_instance_valid(_original):
		if _map.get("фигурки") == _replacement:
			_map.set("фигурки", _original)
			_original.render_target_update_mode = _original_mode as SubViewport.UpdateMode
			_original.call("задать_размер", Vector2(_replacement.size) if is_instance_valid(_replacement) else Vector2(_original.size))
			if is_instance_valid(_picture):
				_picture.texture = _original.get_texture()
	if is_instance_valid(_replacement):
		_replacement.call("очистить")
		_replacement.queue_free()
	_map = null
	_original = null
	_picture = null
	_replacement = null

func _mod_unloaded() -> void:
	_unloaded = true
	set_process(false)
	_restore()
	if is_instance_valid(_template):
		_template.free()
	_template = null

func _run_test() -> void:
	var runner: RefCounted = load(path("dev/live_test.gd")).new()
	await runner.start(self)
