extends RefCounted
## External QA host only. Never include this file in a distributed mod.
## Uses an already running fresh world; does not load user saves or start a world.

const PROFILE: String = "Pax Universe Atlas QA"
const SETTINGS_FILE: String = "user://mod_settings/earth_atlas.json"
const KEYS: Array[String] = ["enabled", "quality", "natural", "political", "urban"]

var _report: Dictionary = {"checks": {}, "failures": [], "screenshots": [], "quality_sizes": {}}
var _tree: SceneTree
var _output: String
var _had_settings: bool
var _settings_bytes: PackedByteArray
var _runtime: Dictionary = {}
var _map: CanvasLayer
var _main: Node
var _center: Vector2
var _zoom: float
var _was_visible: bool

func start(mod: Node, output: String) -> Dictionary:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if profile != OS.get_environment("APPDATA").replace("\\", "/").path_join(PROFILE):
		return {"ok": false, "error": "Refused: exact isolated Atlas QA profile required"}
	if not output.is_absolute_path() or output.is_empty():
		return {"ok": false, "error": "An absolute artifact directory is required"}
	if not is_instance_valid(mod) or str(mod.get("id")) != "earth_atlas" or not is_instance_valid(Pax.game):
		return {"ok": false, "error": "A loaded Atlas instance and a fresh QA world are required"}
	_tree = mod.get_tree()
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "error": "This compatibility test requires GPU rendering"}
	_main = Pax.game.main
	_map = _main.get("полит_карта") as CanvasLayer
	if not is_instance_valid(_map) or _map.get("мат_земли") != Pax.game.body_material("Земля"):
		return {"ok": false, "error": "Open the real Earth map before running the test"}
	_output = output
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		return {"ok": false, "error": "Cannot create artifact directory"}
	_had_settings = FileAccess.file_exists(SETTINGS_FILE)
	_settings_bytes = FileAccess.get_file_as_bytes(SETTINGS_FILE) if _had_settings else PackedByteArray()
	for key: String in KEYS:
		_runtime[key] = mod.get("_" + key)
	_center = _map.get("центр")
	_zoom = float(_map.get("зум"))
	_was_visible = _map.visible
	_checkpoint("exercise_begin")
	await _exercise(mod)
	_checkpoint("exercise_complete")
	await _restore(mod)
	_checkpoint("restore_complete")
	_report["ok"] = (_report.failures as Array).is_empty()
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	_report["passed_count"] = int(_report.assertion_count) - (_report.failures as Array).size()
	_report["mod_version"] = "unknown"
	_checkpoint("metadata_begin")
	for installed_mod: Dictionary in Pax.mods():
		if str(installed_mod.get("id", "")) == "earth_atlas":
			_report["mod_version"] = str(installed_mod.get("version", "unknown"))
			break
	_report["game_version"] = Pax.text("res://data/version.txt").strip_edges()
	_report["renderer"] = RenderingServer.get_video_adapter_name()
	_checkpoint("metadata_complete")
	_report["limitations"] = "Fresh world on GPU; actual control signals and native map switching. Lifecycle callbacks are invoked by the external QA host, not launcher checkbox clicks. No saved-world loading or long simulation."
	var file: FileAccess = FileAccess.open(_output.path_join("atlas-compatibility-report.json"), FileAccess.WRITE)
	_checkpoint("final_report_opened")
	if file != null:
		_report["stage"] = "complete"
		_report["completed"] = true
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	_checkpoint("final_report_saved")
	print("ATLAS_COMPATIBILITY_RESULT ", JSON.stringify(_report))
	return _report

func _exercise(mod: Node) -> void:
	await _settle()
	_check("automatic_world_connection", mod.get("_game") == Pax.game)
	var record: Dictionary = _record(mod)
	if not _check("real_map_discovered_once", not record.is_empty() and _record_count(mod) == 1):
		return
	var elevation: Texture2D = mod.get("_elevation") as Texture2D
	_check("elevation_10800x5400", elevation != null and elevation.get_size() == Vector2(10800, 5400))
	var panel: PanelContainer = mod.get("_settings_window") as PanelContainer
	var button: Button = mod.get("_settings_button") as Button
	if not _check("settings_controls_exist", is_instance_valid(panel) and is_instance_valid(button)):
		return
	var toggles: Array[Node] = panel.find_children("*", "CheckButton", true, false)
	var options: Array[Node] = panel.find_children("*", "OptionButton", true, false)
	var sliders: Array[Node] = panel.find_children("*", "HSlider", true, false)
	if not _check("actual_control_inventory", toggles.size() == 1 and options.size() == 1 and sliders.size() == 3):
		return
	var enabled: CheckButton = toggles[0] as CheckButton
	var quality: OptionButton = options[0] as OptionButton
	_check("four_quality_choices", quality.item_count == 4)
	if panel.visible:
		button.pressed.emit()
	button.pressed.emit()
	await _settle()
	_check("settings_native_button_opens", panel.is_visible_in_tree())
	_check("settings_inside_viewport", _inside(panel))
	for control: Node in toggles + options + sliders:
		_check("settings_control_visible_" + str(control.get_index()), (control as Control).is_visible_in_tree() and _inside(control as Control))
	await _capture("atlas-settings.png")
	button.pressed.emit()
	await _settle()
	_check("settings_native_button_closes", not panel.visible)
	var political: ShaderMaterial = _map.get("мат") as ShaderMaterial
	var surface: ShaderMaterial = _map.get("мат_пов") as ShaderMaterial
	_report["earth_map_name"] = str(Pax.game.body("Земля").get("карта", ""))
	_report["native_map_inputs"] = {}
	for key: String in ["use_map", "use_ocean", "use_height", "map_tint"]:
		_report.native_map_inputs[key] = surface.get_shader_parameter(key)
	for key: String in ["map_albedo", "map_ocean", "map_height"]:
		var input_texture: Texture2D = surface.get_shader_parameter(key) as Texture2D
		_report.native_map_inputs[key] = {"available": input_texture != null,
			"size": [input_texture.get_width(), input_texture.get_height()] if input_texture != null else [],
			"resource_path": input_texture.resource_path if input_texture != null else ""}
	var original_map: Shader = record.original_map
	var original_surface: Shader = record.original_surface
	var native_values: Dictionary = {}
	for key: String in ["temperature", "water", "biomass", "radiation", "use_map", "use_ocean", "map_albedo", "map_ocean"]:
		native_values[key] = surface.get_shader_parameter(key)
	var overlay: Control = _map.get("слой") as Control
	var overlay_size: Vector2 = overlay.size
	enabled.button_pressed = false
	await _settle()
	_check("disable_restores_both_native_shaders", political.shader == original_map and surface.shader == original_surface)
	_check("disable_saved", _saved().get("enabled", true) == false)
	await _capture("atlas-disabled.png")
	enabled.button_pressed = true
	await _settle()
	_check("enable_reapplies_both_shaders", political.shader == (mod.get("_shaders") as Dictionary).political and surface.shader == (mod.get("_shaders") as Dictionary).surface)
	_check("enable_saved", _saved().get("enabled", false) == true)
	var sizes: Array[Vector2i] = []
	var scales: Array[float] = [0.5, 1.0, 1.5, 2.0]
	for index: int in range(scales.size()):
		quality.select(index)
		quality.item_selected.emit(index)
		await _settle()
		var viewport: SubViewport = _map.get("вп") as SubViewport
		sizes.append(viewport.size)
		_report.quality_sizes[str(scales[index])] = [viewport.size.x, viewport.size.y]
		var rect: Control = record.surface_rect.get_ref() as Control
		_check("quality_" + str(scales[index]) + "_applied_and_saved", is_equal_approx(float(mod.get("_quality")), scales[index]) and is_equal_approx(float(_saved().get("quality", -1)), scales[index]))
		_check("quality_" + str(scales[index]) + "_valid_surface", viewport.size.x > 0 and viewport.size.y > 0 and maxi(viewport.size.x, viewport.size.y) <= 4096 and rect.size.is_equal_approx(Vector2(viewport.size)))
		_check("quality_" + str(scales[index]) + "_overlay_unchanged", overlay.size.is_equal_approx(overlay_size))
	_check("quality_changes_actual_resolution", sizes[0].x < sizes[1].x and sizes[1].x < sizes[2].x and sizes[2].x <= sizes[3].x)
	_check("native_quality_doubles_half_resolution", abs(sizes[1].x - sizes[0].x * 2) <= 2 and abs(sizes[1].y - sizes[0].y * 2) <= 2)
	quality.select(1)
	quality.item_selected.emit(1)
	var keys: Array[String] = ["natural", "political", "urban"]
	var values: Array[float] = [0.63, 0.37, 0.24]
	for index: int in range(sliders.size()):
		var slider: HSlider = sliders[index] as HSlider
		slider.value = 0.0
		await _settle()
		var target: ShaderMaterial = political if keys[index] == "political" else surface
		_check(keys[index] + "_minimum_updates_shader", is_zero_approx(float(target.get_shader_parameter("atlas_" + keys[index]))))
		slider.value = values[index]
		await _settle()
		_check(keys[index] + "_callback_updates_shader_and_save", is_equal_approx(float(target.get_shader_parameter("atlas_" + keys[index])), values[index]) and is_equal_approx(float(_saved().get(keys[index], -1)), values[index]))
	_map.set("_снимок_параметров", "")
	_map.call("_перерисовать_поверхность")
	await _settle()
	for key: String in native_values:
		_check("redraw_preserves_native_" + key, surface.get_shader_parameter(key) == native_values[key])
	_check("redraw_preserves_elevation", surface.get_shader_parameter("atlas_elevation") == elevation and is_equal_approx(float(surface.get_shader_parameter("atlas_has_elevation")), 1.0))
	await _capture("atlas-enabled.png")
	var button_connections: int = button.pressed.get_connections().size()
	for iteration: int in range(3):
		mod.call("_world_ready", Pax.game)
		await _settle()
	_check("repeated_world_ready_keeps_one_record", _record_count(mod) == 1)
	_check("repeated_world_ready_keeps_same_controls", mod.get("_settings_window") == panel and mod.get("_settings_button") == button)
	_check("repeated_world_ready_no_duplicate_callbacks", button.pressed.get_connections().size() == button_connections and _node_connections(mod) == 1)
	var mars_index: int = Pax.game.body_names().find("Марс")
	if _check("mars_exists_for_native_switch", mars_index >= 0):
		_main.call("_открыть_карту_тела", mars_index)
		await _settle()
		_check("native_switch_selected_mars", _map.get("мат_земли") == Pax.game.body_material("Марс"))
		_check("mars_uses_native_shaders", political.shader == original_map and surface.shader == original_surface)
		_main.call("_открыть_карту_тела", int(_main.get("индекс_земли")))
		await _settle()
		_check("return_to_earth_reactivates_atlas", surface.shader == (mod.get("_shaders") as Dictionary).surface)
	mod.call("_mod_unloaded")
	# Registry removal is synchronous. Check while the queued panel is still a
	# valid Object instead of passing a freed instance into Array.has later.
	_check("unload_unregisters_window", not (_main.get("окна_модов") as Array).has(panel))
	await _settle()
	_check("unload_restores_native_materials", _map.get("мат") == political and _map.get("мат_пов") == surface and political.shader == original_map and surface.shader == original_surface)
	_check("unload_removes_callbacks", _node_connections(mod) == 0)
	_check("unload_frees_controls", not is_instance_valid(panel) and not is_instance_valid(button))
	mod.call("_mod_loaded")
	await _settle(0.65)
	_check("hot_load_catches_existing_world", mod.get("_game") == Pax.game and _record_count(mod) == 1)
	_check("hot_load_restores_atlas", surface.shader == (mod.get("_shaders") as Dictionary).surface and political.shader == (mod.get("_shaders") as Dictionary).political)
	_check("hot_load_one_callback", _node_connections(mod) == 1)
	_check("hot_load_settings_remain_saved", is_equal_approx(float(mod.get("_natural")), values[0]) and is_equal_approx(float(mod.get("_political")), values[1]) and is_equal_approx(float(mod.get("_urban")), values[2]) and is_equal_approx(float(mod.get("_quality")), 1.0))

func _restore(mod: Node) -> void:
	_checkpoint("restore_begin")
	_main.call("_открыть_карту_тела", int(_main.get("индекс_земли")))
	_checkpoint("restore_native_earth_opened")
	_map.set("центр", _center)
	_map.set("зум", _zoom)
	_map.call("_отправить_вид")
	_map.call("показать", _was_visible)
	_checkpoint("restore_map_view_set")
	mod.call("_mod_unloaded")
	_checkpoint("restore_mod_unloaded")
	await _settle()
	_checkpoint("restore_unload_settled")
	_restore_settings_file()
	_checkpoint("restore_settings_first_write")
	mod.call("_mod_loaded")
	_checkpoint("restore_mod_loaded_called")
	await _settle(0.65)
	_checkpoint("restore_reload_settled")
	# Restore byte-for-byte again after lifecycle work, including absence of a file.
	_restore_settings_file()
	_checkpoint("restore_settings_final_write")
	_check("qa_settings_bytes_restored", FileAccess.file_exists(SETTINGS_FILE) == _had_settings and (not _had_settings or FileAccess.get_file_as_bytes(SETTINGS_FILE) == _settings_bytes))
	for key: String in KEYS:
		_check("runtime_restored_" + key, mod.get("_" + key) == _runtime[key])

func _restore_settings_file() -> void:
	if _had_settings:
		var file: FileAccess = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_settings_bytes)
			file.close()
	elif FileAccess.file_exists(SETTINGS_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))

func _record(mod: Node) -> Dictionary:
	for item: Dictionary in mod.get("_maps"):
		if item.node.get_ref() == _map:
			return item
	return {}

func _record_count(mod: Node) -> int:
	var count: int = 0
	for item: Dictionary in mod.get("_maps"):
		if item.node.get_ref() == _map:
			count += 1
	return count

func _node_connections(mod: Node) -> int:
	var count: int = 0
	for connection: Dictionary in _tree.node_added.get_connections():
		var callback: Callable = connection.callable
		if callback.get_object() == mod and callback.get_method() == "_node_added":
			count += 1
	return count

func _saved() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE))
	return value if value is Dictionary else {}

func _inside(control: Control) -> bool:
	var bounds: Rect2 = control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	return Rect2(Vector2.ZERO, _tree.root.get_visible_rect().size).grow(1.0).encloses(bounds)

func _settle(seconds: float = 0.08) -> void:
	await _tree.create_timer(seconds).timeout
	await _tree.process_frame
	await RenderingServer.frame_post_draw

func _capture(filename: String) -> void:
	await _settle()
	var image: Image = _tree.root.get_texture().get_image()
	var result: Error = image.save_png(_output.path_join(filename))
	_check("capture_" + filename, result == OK and not image.is_empty())
	if result == OK:
		_report.screenshots.append(filename)

func _check(name: String, success: bool) -> bool:
	_report.checks[name] = success
	if not success:
		_report.failures.append(name)
	print("ATLAS_CHECK ", name, " ", "PASS" if success else "FAIL")
	_checkpoint("check:" + name)
	return success

func _checkpoint(stage: String) -> void:
	_report["stage"] = stage
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	_report["passed_count"] = int(_report.assertion_count) - (_report.failures as Array).size()
	_report["completed"] = stage == "final_report_saved"
	print("ATLAS_STAGE ", stage)
	var progress: FileAccess = FileAccess.open(_output.path_join("atlas-progress.json"), FileAccess.WRITE)
	if progress != null:
		progress.store_string(JSON.stringify(_report, "\t"))
		progress.close()
