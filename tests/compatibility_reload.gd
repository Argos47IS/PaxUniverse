extends RefCounted
## External QA only: exercise the real reload/toggle lifecycle in the same world.

const MODS_PROFILE: String = "user://mods.json"
const SETTINGS_PATHS: Array[String] = ["user://mod_settings/earth_atlas.json", "user://mod_settings/pax_interface.json"]
const ATLAS_VALUES: Array[String] = ["_enabled", "_quality", "_natural", "_political", "_urban"]
const IDS: Array[String] = ["earth_atlas", "pax_interface"]

var _report: Dictionary = {"checks": {}, "failures": []}
var _tree: SceneTree
var _main: Node
var _map: CanvasLayer
var _output: String
var _original_map: Shader
var _original_surface: Shader
var _atlas_values: Dictionary = {}
var _hud_values: Dictionary = {}
var _native_parents: Array[Dictionary] = []
var _initial_windows: int = 0
var _files: Dictionary = {}

func start(output: String) -> Dictionary:
	_report = {"checks": {}, "failures": []}
	_output = output
	var isolated: bool = OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA")
	_check("isolated_profile", isolated)
	_check("absolute_output", not output.is_empty() and output.is_absolute_path())
	if not isolated or output.is_empty() or not output.is_absolute_path():
		return _finish(false)
	var game: PaxGame = Pax.game
	_check("existing_world", is_instance_valid(game) and is_instance_valid(game.main))
	if not is_instance_valid(game) or not is_instance_valid(game.main):
		return _finish()
	_main = game.main
	_tree = _main.get_tree()
	_map = _main.get("полит_карта") as CanvasLayer
	var atlas: Node = Pax.get_mod("earth_atlas")
	var hud: Node = Pax.get_mod("pax_interface")
	_check("both_mod_instances_exist", is_instance_valid(atlas) and is_instance_valid(hud))
	_check("earth_map_exists", is_instance_valid(_map))
	if not is_instance_valid(atlas) or not is_instance_valid(hud) or not is_instance_valid(_map):
		return _finish()
	_check("no_pending_interface_preview", (hud.get("_opening") as Dictionary).is_empty())
	if not (hud.get("_opening") as Dictionary).is_empty():
		return _finish()
	var map_record: Dictionary = _atlas_map_record(atlas)
	_check("atlas_has_original_shaders", map_record.has("original_map") and map_record.has("original_surface"))
	if not map_record.has("original_map") or not map_record.has("original_surface"):
		return _finish()
	_original_map = map_record.original_map as Shader
	_original_surface = map_record.original_surface as Shader
	for key: String in ATLAS_VALUES:
		_atlas_values[key] = atlas.get(key)
	_hud_values = (hud.get("_prefs") as Dictionary).duplicate(true)
	_initial_windows = _window_count()
	_capture_native_parents(hud)
	for path: String in [MODS_PROFILE] + SETTINGS_PATHS:
		_files[path] = _file_snapshot(path)
	var original_selection: Dictionary = {}
	if bool((_files[MODS_PROFILE] as Dictionary).exists):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MODS_PROFILE))
		_check("mods_profile_is_json_object", parsed is Dictionary)
		if not parsed is Dictionary:
			return _finish()
		original_selection = (parsed as Dictionary).duplicate(true)
	var disabled: Variant = original_selection.get("disabled", [])
	_check("mods_profile_disabled_is_array", disabled is Array)
	if not disabled is Array:
		return _finish()
	_check("both_mods_selected", not disabled.has("earth_atlas") and not disabled.has("pax_interface"))
	if disabled.has("earth_atlas") or disabled.has("pax_interface"):
		return _finish()
	_report["game_version"] = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
	_report["scope"] = "Same native Main; three public forced reloads and one off/on pair per mod. Only isolated QA selection is changed; settings are compared byte-for-byte and restored if needed."
	_check_state("initial", true, true)
	for iteration: int in range(3):
		var old_ids: Dictionary = _instance_ids()
		var old_hud: Node = Pax.get_mod("pax_interface")
		var old_root: Control = old_hud.get("_root") as Control if is_instance_valid(old_hud) else null
		var old_root_reference: WeakRef = weakref(old_root) if is_instance_valid(old_root) else null
		Pax.reload_mods(true)
		await _settle()
		var label: String = "reload_%d" % (iteration + 1)
		_check_state(label, true, true)
		_check(label + "_previous_hud_root_freed", old_root_reference != null and old_root_reference.get_ref() == null)
		var new_hud: Node = Pax.get_mod("pax_interface")
		var new_root: Control = new_hud.get("_root") as Control if is_instance_valid(new_hud) else null
		_check(label + "_new_hud_root_owned_by_native_layer", is_instance_valid(new_root) and is_instance_valid(Pax.game) and new_root.get_parent() == Pax.game.hud_layer())
		var restoration_records_live: bool = is_instance_valid(new_hud)
		if is_instance_valid(new_hud):
			# An old queued wrapper used to be adopted as native UI during reload.
			# Once freed, it left a dead restoration entry in the replacement HUD.
			for record: Dictionary in new_hud.get("_moved"):
				restoration_records_live = restoration_records_live and is_instance_valid(record.get("node"))
		_check(label + "_restoration_records_have_live_nodes", restoration_records_live)
		var new_ids: Dictionary = _instance_ids()
		for id: String in IDS:
			_check(label + "_" + id + "_instance_replaced", int(new_ids.get(id, 0)) > 0 and new_ids.get(id) != old_ids.get(id))
	for id: String in IDS:
		if not _write_selection(original_selection, id, true):
			break
		Pax.reload_mods()
		await _settle()
		_check_state(id + "_off", id != "earth_atlas", id != "pax_interface")
		if id == "pax_interface":
			await _check_native_command()
		if not _write_selection(original_selection, id, false):
			break
		Pax.reload_mods()
		await _settle()
		_check_state(id + "_on", true, true)
	# Restore exact original bytes, including formatting and an originally absent file.
	# Reload once only if an incomplete toggle or unexpected write needs recovery.
	var needs_reload: bool = not is_instance_valid(Pax.get_mod("earth_atlas")) or not is_instance_valid(Pax.get_mod("pax_interface"))
	for path: String in SETTINGS_PATHS:
		needs_reload = needs_reload or not _file_matches(path)
	for path: String in _files:
		_check("restore_" + path.get_file(), _restore_file(path, _files[path]))
	if needs_reload:
		Pax.reload_mods(true)
		await _settle()
	_check_state("restored", true, true)
	_check("selection_bytes_restored", _file_matches(MODS_PROFILE))
	return _finish()

func _settle() -> void:
	await _tree.create_timer(1.0).timeout
	await _tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _instance_ids() -> Dictionary:
	var result: Dictionary = {}
	for id: String in IDS:
		var instance: Node = Pax.get_mod(id)
		result[id] = instance.get_instance_id() if is_instance_valid(instance) else 0
	return result

func _write_selection(original: Dictionary, id: String, disabled: bool) -> bool:
	var selection: Dictionary = original.duplicate(true)
	var excluded: Array = (selection.get("disabled", []) as Array).duplicate()
	if disabled:
		if not excluded.has(id):
			excluded.append(id)
	else:
		excluded.erase(id)
	selection["disabled"] = excluded
	var file: FileAccess = FileAccess.open(MODS_PROFILE, FileAccess.WRITE)
	var opened: bool = file != null
	_check(id + ("_disable" if disabled else "_enable") + "_selection_written", opened)
	if not opened:
		return false
	file.store_string(JSON.stringify(selection, "\t"))
	file.close()
	return true

func _check_state(label: String, expect_atlas: bool, expect_hud: bool) -> void:
	_check(label + "_same_native_main", is_instance_valid(_main) and _tree.current_scene == _main and is_instance_valid(Pax.game) and Pax.game.main == _main)
	var atlas: Node = Pax.get_mod("earth_atlas")
	var hud: Node = Pax.get_mod("pax_interface")
	_check(label + "_atlas_presence", is_instance_valid(atlas) == expect_atlas)
	_check(label + "_hud_presence", is_instance_valid(hud) == expect_hud)
	_check(label + "_atlas_instance_count", _count_mod(_tree.root, "earth_atlas") == (1 if expect_atlas else 0))
	_check(label + "_hud_instance_count", _count_mod(_tree.root, "pax_interface") == (1 if expect_hud else 0))
	_check(label + "_hud_root_count", _count_name(_tree.root, "PaxInterfaceHUD") == (1 if expect_hud else 0))
	_check(label + "_registered_window_count", _window_count() == _initial_windows - (0 if expect_atlas else 1) - (0 if expect_hud else 1))
	var surface: ShaderMaterial = _map.get("мат_пов") as ShaderMaterial
	var political: ShaderMaterial = _map.get("мат") as ShaderMaterial
	if expect_atlas and is_instance_valid(atlas):
		_check(label + "_atlas_attached_automatically", atlas.get("_game") == Pax.game)
		_check(label + "_one_map_adapter", _atlas_map_count(atlas) == 1)
		var record: Dictionary = _atlas_map_record(atlas)
		_check(label + "_native_shader_baseline_preserved", record.get("original_map") == _original_map and record.get("original_surface") == _original_surface)
		var shaders: Dictionary = atlas.get("_shaders")
		var expected_surface: Shader = shaders.get("surface") as Shader if bool(_atlas_values.get("_enabled", true)) else _original_surface
		var expected_map: Shader = shaders.get("political") as Shader if bool(_atlas_values.get("_enabled", true)) else _original_map
		_check(label + "_atlas_shader_active", surface.shader == expected_surface and political.shader == expected_map)
		var values_match: bool = true
		for key: String in ATLAS_VALUES:
			values_match = values_match and atlas.get(key) == _atlas_values[key]
		_check(label + "_atlas_preferences_unchanged", values_match)
		var atlas_panel: Control = atlas.get("_settings_window") as Control
		var atlas_button: Button = atlas.get("_settings_button") as Button
		_check(label + "_atlas_controls_live", is_instance_valid(atlas_panel) and is_instance_valid(atlas_button) and atlas_panel.is_inside_tree() and atlas_button.is_inside_tree())
	else:
		_check(label + "_native_shaders_restored", surface.shader == _original_surface and political.shader == _original_map)
	if expect_hud and is_instance_valid(hud):
		_check(label + "_hud_attached_automatically", hud.get("_game") == Pax.game)
		_check(label + "_hud_preferences_unchanged", hud.get("_prefs") == _hud_values)
		var proxies: Dictionary = hud.get("_proxies")
		_check(label + "_six_command_proxies", proxies.size() == 6)
		var targets_valid: bool = true
		var native: Dictionary = hud.get("_native")
		for key: String in proxies:
			var proxy: Button = proxies[key] as Button
			var source: Button = native.get(key) as Button
			targets_valid = targets_valid and is_instance_valid(proxy) and is_instance_valid(source)
			if is_instance_valid(proxy) and is_instance_valid(source):
				targets_valid = targets_valid and proxy.is_inside_tree() and proxy.get_meta("win", null) == source.get_meta("win", null)
		_check(label + "_proxy_native_targets_preserved", targets_valid)
		var visible_atlas_proxies: int = 0
		for record: Dictionary in (hud.get("_extras") as Dictionary).values():
			var source: Button = record.get("native") as Button
			var proxy: Button = record.get("proxy") as Button
			if is_instance_valid(source) and is_instance_valid(proxy) and proxy.is_visible_in_tree() and is_instance_valid(atlas) and source == atlas.get("_settings_button"):
				visible_atlas_proxies += 1
		_check(label + "_single_atlas_tool_proxy", visible_atlas_proxies == (1 if expect_atlas else 0))
	else:
		var parents_restored: bool = true
		for record: Dictionary in _native_parents:
			var node: Node = record.node as Node
			parents_restored = parents_restored and is_instance_valid(node) and is_instance_valid(record.parent) and node.get_parent() == record.parent
		_check(label + "_native_hud_parents_restored", parents_restored)
		_check(label + "_native_bottom_visible", (_main.get("низ_панель") as Control).is_visible_in_tree())
	for path: String in SETTINGS_PATHS:
		_check(label + "_unchanged_" + path.get_file(), _file_matches(path))

func _capture_native_parents(hud: Node) -> void:
	var relevant: Array[Node] = []
	for key: String in ["верх_панель", "кнопка_помощника", "кнопка_связей", "кнопка_державы", "кнопка_карты", "кнопка_перемотки"]:
		var node: Node = _main.get(key) as Node
		if is_instance_valid(node):
			relevant.append(node)
	var recorded: Array[int] = []
	for record: Dictionary in hud.get("_moved"):
		var node: Node = record.node as Node
		if is_instance_valid(node) and node in relevant and not recorded.has(node.get_instance_id()):
			_native_parents.append({"node": node, "parent": record.parent})
			recorded.append(node.get_instance_id())
	_check("native_parent_snapshot_complete", _native_parents.size() == relevant.size() and relevant.size() == 6)

func _check_native_command() -> void:
	var button: Button = _main.get("кнопка_приказов") as Button
	var window: Control = _main.get("окно_приказов") as Control
	_check("standalone_atlas_native_orders_available", is_instance_valid(button) and is_instance_valid(window) and button.is_visible_in_tree())
	if not is_instance_valid(button) or not is_instance_valid(window):
		return
	var before: bool = window.visible
	button.pressed.emit()
	await _settle()
	_check("standalone_atlas_native_orders_toggle", window.visible != before)
	button.pressed.emit()
	await _settle()
	_check("standalone_atlas_native_orders_restored", window.visible == before)

func _atlas_map_record(atlas: Node) -> Dictionary:
	for record: Dictionary in atlas.get("_maps"):
		if (record.node as WeakRef).get_ref() == _map:
			return record
	return {}

func _atlas_map_count(atlas: Node) -> int:
	var count: int = 0
	for record: Dictionary in atlas.get("_maps"):
		if (record.node as WeakRef).get_ref() == _map:
			count += 1
	return count

func _window_count() -> int:
	var count: int = 0
	for candidate: Variant in _main.get("окна_модов"):
		if candidate is Node and is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			count += 1
	return count

func _count_mod(node: Node, id: String) -> int:
	var count: int = 1 if node is PaxMod and (node as PaxMod).id == id and not node.is_queued_for_deletion() else 0
	for child: Node in node.get_children():
		count += _count_mod(child, id)
	return count

func _count_name(node: Node, expected: String) -> int:
	var count: int = 1 if str(node.name) == expected and not node.is_queued_for_deletion() else 0
	for child: Node in node.get_children():
		count += _count_name(child, expected)
	return count

func _file_snapshot(path: String) -> Dictionary:
	var exists: bool = FileAccess.file_exists(path)
	return {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}

func _file_matches(path: String) -> bool:
	var before: Dictionary = _files[path]
	var after: Dictionary = _file_snapshot(path)
	return before.exists == after.exists and before.bytes == after.bytes

func _restore_file(path: String, snapshot: Dictionary) -> bool:
	if _file_matches(path):
		return true
	if bool(snapshot.exists):
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_buffer(snapshot.bytes as PackedByteArray)
		file.close()
	elif FileAccess.file_exists(path):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			return false
	return _file_matches(path)

func _check(name: String, result: bool) -> void:
	(_report.checks as Dictionary)[name] = result
	if not result:
		(_report.failures as Array).append(name)
		print("COMPAT_RELOAD_FAILED ", name)

func _finish(write_report: bool = true) -> Dictionary:
	_report["ok"] = (_report.failures as Array).is_empty()
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	if write_report and not _output.is_empty():
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(_output)
		var file: FileAccess = FileAccess.open(_output.path_join("reload-test-report.json"), FileAccess.WRITE) if directory_error == OK else null
		if file != null:
			file.store_string(JSON.stringify(_report, "\t"))
			file.close()
		else:
			_check("report_file_written", false)
			_report["ok"] = false
	print("COMPAT_RELOAD_RESULT ", JSON.stringify(_report))
	return _report
