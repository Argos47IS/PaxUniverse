extends RefCounted
## Run only in the dedicated development test process, outside a saved world.
## Exercises the installed adapter against an actual game Карта instance.
## No simulated PaxGame: activation is called explicitly; focused-body detection
## still requires a real world and is not claimed as covered by this test.

var _errors: Array[String] = []
var _checks: Array[String] = []

func start(mod: Node, output_dir: String) -> Dictionary:
	_errors.clear()
	_checks.clear()
	var map_script: Script = load("res://scripts/ui/Карта.gd")
	if map_script == null:
		return {"ok": false, "error": "Game map class unavailable"}
	print("ATLAS_MAP_BASE ", map_script.get_instance_base_type())
	for method: Dictionary in map_script.get_script_method_list():
		if str(method.name) in ["настроить", "задать_тело", "_перерисовать_поверхность", "_размер", "_отправить_вид"]:
			print("ATLAS_MAP_METHOD ", JSON.stringify(method))
	var saved_records: Array = mod.get("_maps")
	var was_processing: bool = mod.is_processing()
	mod.set_process(false)
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1920, 1080)
	host.disable_3d = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mod.get_tree().root.add_child(host)
	var map: Node = map_script.new() as Node
	if map == null:
		host.queue_free()
		mod.set_process(was_processing)
		return {"ok": false, "error": "Map class is not a Node"}
	print("ATLAS_MAP_INSTANCE ", map.get_class())
	host.add_child(map)
	map.set_process(false)
	await mod.get_tree().process_frame
	var surface: ShaderMaterial = map.get("мат_пов") as ShaderMaterial
	var political: ShaderMaterial = map.get("мат") as ShaderMaterial
	var vp: SubViewport = map.get("вп") as SubViewport
	var layer: Control = map.get("слой") as Control
	var overlay_original_size: Vector2 = layer.size if layer != null else Vector2.ZERO
	var background: Control = map.get("фон") as Control
	var surface_rect: ColorRect = _find_surface_rect(vp, surface) if vp != null else null
	if vp != null:
		vp.print_tree_pretty()
		_print_controls(vp)
	for key: String in ["фон", "слой", "вп", "мат", "мат_пов", "холст"]:
		var value: Variant = map.get(key)
		print("ATLAS_MAP_PROPERTY ", key, " ", value.get_class() if value is Object else str(value))
	if background != null:
		print("ATLAS_MAP_RECT ", background.size, " ", background.get_global_transform_with_canvas().get_scale())
	if map.has_method("_размер"):
		print("ATLAS_MAP_SIZE_METHOD ", map.call("_размер"))
	if surface == null or political == null or vp == null or layer == null:
		_errors.append("Real Карта._ready did not initialize materials/viewport; inspect ATLAS_MAP_METHOD signatures")
	else:
		# The redraw routine copies surface settings from the body's material.
		var earth: ShaderMaterial = ShaderMaterial.new()
		earth.shader = load("res://shaders/planet.gdshader") as Shader
		var render_script: Script = load(str(mod.call("path", "dev/render_test.gd")))
		if render_script != null:
			var helper: RefCounted = render_script.new()
			var earth_uniforms: Dictionary = helper.call("_earth_uniforms")
			for key: String in earth_uniforms:
				earth.set_shader_parameter(key, earth_uniforms[key])
				surface.set_shader_parameter(key, earth_uniforms[key])
				political.set_shader_parameter(key, earth_uniforms[key])
		earth.set_shader_parameter("temperature", 0.345)
		map.set("мат_земли", earth)
		surface.set_shader_parameter("temperature", 0.345)
		political.set_shader_parameter("hover_id", 321.0)
		var original_surface: Shader = surface.shader
		var original_map: Shader = political.shader
		mod.call("_attach", map)
		var record: Dictionary = {}
		var records: Array = mod.get("_maps")
		for item: Dictionary in records:
			if item.node.get_ref() == map:
				record = item
		_check(not record.is_empty(), "real map attached")
		if not record.is_empty():
			var shaders: Dictionary = mod.get("_shaders")
			mod.call("_set_active", record, true)
			_check(layer.size.is_equal_approx(overlay_original_size), "activation preserves overlay size")
			_check(political.shader == shaders.political and surface.shader == shaders.surface, "both modified shaders installed")
			_check(map.get("мат") == political and map.get("мат_пов") == surface, "existing material objects preserved")
			_check(is_equal_approx(float(political.get_shader_parameter("hover_id")), 321.0), "political parameters preserved")
			_check(is_equal_approx(float(surface.get_shader_parameter("temperature")), 0.345), "body climate preserved")
			_check(surface.get_shader_parameter("atlas_elevation") != null, "elevation bound")
			_check(surface_rect != null, "actual surface ColorRect found in viewport")
			if surface_rect != null:
				_check(surface_rect.material == surface, "viewport ColorRect uses surface material")
				_check(surface_rect.size.is_equal_approx(Vector2(vp.size)), "actual surface ColorRect covers native viewport")
			map.set("_снимок_параметров", "")
			map.call("_перерисовать_поверхность")
			_check(surface.get_shader_parameter("atlas_elevation") != null, "redraw preserves elevation")
			_check(is_equal_approx(float(surface.get_shader_parameter("atlas_has_elevation")), 1.0), "redraw preserves elevation enable flag")
			_check(is_equal_approx(float(surface.get_shader_parameter("use_map")), 1.0), "redraw preserves actual Earth map")
			_check(is_equal_approx(float(surface.get_shader_parameter("use_ocean")), 1.0), "redraw preserves ocean mask")
			_check(is_equal_approx(float(surface.get_shader_parameter("water")), 0.71), "redraw preserves test sea level")
			_check(vp.size.x > 0 and vp.size.y > 0 and maxi(vp.size.x, vp.size.y) <= 4096, "viewport size valid and capped")
			var original_quality: float = float(mod.get("_quality"))
			mod.set("_quality", 2.0)
			mod.call("_resize", record)
			_check(layer.size.is_equal_approx(overlay_original_size), "200 percent quality preserves overlay size")
			if surface_rect != null:
				_check(surface_rect.size.is_equal_approx(Vector2(vp.size)), "200 percent quality fills surface viewport")
			mod.set("_quality", original_quality)
			mod.call("_resize", record)
			if DisplayServer.get_name() != "headless":
				(map as CanvasLayer).visible = true
				political.set_shader_parameter("view_center", Vector2(0.5806, 0.2111))
				political.set_shader_parameter("view_zoom", 13.0)
				surface.set_shader_parameter("view_center", Vector2(0.5806, 0.2111))
				surface.set_shader_parameter("view_zoom", 13.0)
				host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				for frame: int in range(3):
					await mod.get_tree().process_frame
					await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(output_dir)
				var shot: Image = host.get_texture().get_image()
				_check(shot.save_png(output_dir.path_join("actual-map-modified.png")) == OK, "real map screenshot saved")
			host.size = Vector2i(2400, 1350)
			await mod.get_tree().process_frame
			var overlay_resized_size: Vector2 = layer.size
			mod.call("_resize", record)
			_check(layer.size.is_equal_approx(overlay_resized_size), "adapter resize preserves game overlay size")
			if surface_rect != null:
				_check(surface_rect.size.is_equal_approx(Vector2(vp.size)), "actual surface ColorRect follows resize")
			mod.call("_set_active", record, false)
			_check(layer.size.is_equal_approx(overlay_resized_size), "deactivation preserves game overlay size")
			_check(political.shader == original_map and surface.shader == original_surface, "original shaders restored for non-Earth/disabled mode")
			var map_size: Vector2 = background.size if background != null else Vector2(host.size)
			var expected: Vector2i = Vector2i((map_size * Vector2(record.ratio)).round()).max(Vector2i.ONE)
			_check(vp.size == expected, "original surface ratio restored")
			if surface_rect != null:
				_check(surface_rect.size.is_equal_approx(Vector2(vp.size)), "actual surface ColorRect covers restored viewport")
			mod.call("_set_active", record, true)
			mod.call("_set_active", record, false)
			_check(political.shader == original_map and surface.shader == original_surface, "repeated activation reversible")
	# Filter out only this test's map. Preserve preexisting live adapter records.
	var retained: Array[Dictionary] = []
	for item: Dictionary in saved_records:
		if item.node.get_ref() != map:
			retained.append(item)
	mod.set("_maps", retained)
	host.queue_free()
	await mod.get_tree().process_frame
	mod.set_process(was_processing)
	var report: Dictionary = {"ok": _errors.is_empty(), "checks": _checks, "errors": _errors,
		"limitations": "Real map and adapter methods; manual activation, no world simulation or focused-body detection"}
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file: FileAccess = FileAccess.open(output_dir.path_join("adapter-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("ATLAS_ADAPTER_RESULT ", JSON.stringify(report))
	return report

func _check(condition: bool, name: String) -> void:
	if condition:
		_checks.append(name)
	else:
		_errors.append(name)

func _find_surface_rect(node: Node, surface: ShaderMaterial) -> ColorRect:
	if node is ColorRect and (node as ColorRect).material == surface:
		return node as ColorRect
	for child: Node in node.get_children():
		var result: ColorRect = _find_surface_rect(child, surface)
		if result != null:
			return result
	return null

func _print_controls(node: Node) -> void:
	if node is Control:
		var item: Control = node as Control
		print("ATLAS_VIEWPORT_CONTROL ", item.get_path(), " size=", item.size, " material=", item.material)
	for child: Node in node.get_children():
		_print_controls(child)
