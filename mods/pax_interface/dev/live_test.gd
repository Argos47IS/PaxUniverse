extends RefCounted
## Full native world; invoked only by --interface-live-test in the isolated QA profile.

const COMMANDS: Array[String] = ["orders", "plans", "laws", "objects", "mining", "research"]
const WINDOWS: Dictionary = {
	"orders": "окно_приказов", "plans": "окно_проектов", "laws": "окно_законов",
	"objects": "окно_спецпроектов", "mining": "окно_добычи", "research": "окно_науки",
}
const SETTING_KEYS: Array[String] = ["theme", "accent", "opacity", "scale", "font_size", "labels", "sound_enabled", "volume", "motion", "order"]
const PROFILE_PATH: String = "user://mod_settings/pax_interface.json"

var _report: Dictionary = {"checks": {}, "failures": [], "screenshots": [], "rects": {}}
var _output: String = ""
var _old_profile: String = ""
var _had_profile: bool = false


func start(mod: Node) -> void:
	var tree: SceneTree = mod.get_tree()
	print("INTERFACE_LIVE_PROFILE ", OS.get_user_data_dir())
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"):
		push_error("Interface live test requires the isolated Pax Universe Atlas QA profile")
		tree.quit(2)
		return
	_output = OS.get_environment("PAX_UI_TEST_OUTPUT")
	if _output.is_empty() or not _output.is_absolute_path():
		push_error("PAX_UI_TEST_OUTPUT must be an absolute artifact directory")
		tree.quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_had_profile = FileAccess.file_exists(PROFILE_PATH)
	if _had_profile:
		_old_profile = FileAccess.get_file_as_string(PROFILE_PATH)
	var game_settings: FileAccess = FileAccess.open("user://settings.json", FileAccess.WRITE)
	game_settings.store_string(JSON.stringify({"язык": "ru", "заставка": false, "провайдеры": {"мозг": {"режим": "выкл"}}}))
	game_settings.close()
	# The first GPU run already tested automatic activation. Hold this QA-only
	# adapter until native controls have been snapshotted independently of its backups.
	mod.set("_unloaded", true)
	var main: Node = load("res://scripts/Main.gd").new()
	main.set("слот", "interface_qa_" + str(Time.get_ticks_msec()))
	if tree.current_scene != null:
		tree.current_scene.queue_free()
		await tree.process_frame
	tree.root.size = Vector2i(1920, 1080)
	tree.root.add_child(main)
	tree.current_scene = main
	await tree.process_frame
	_check("full_world_startup", is_instance_valid(Pax.game))
	if not is_instance_valid(Pax.game):
		_finish(tree)
		return
	var native_snapshot: Dictionary = _snapshot_native(main)
	mod.set("_unloaded", false)
	mod.call("_world_ready", Pax.game)
	_report["activation_mode"] = "Explicit world_ready after independent native snapshot; automatic activation covered by first GPU run"
	Pax.game.set_speed(0)
	main.call("_открыть_карту_тела", int(main.get("индекс_земли")))
	var map: CanvasLayer = main.get("полит_карта") as CanvasLayer
	if map != null:
		map.call("показать", true)
		map.set("центр", Vector2(0.5806, 0.2111))
		map.set("зум", 13.0)
		map.call("_отправить_вид")
	var menu: CanvasLayer = main.get("меню") as CanvasLayer
	if menu != null:
		menu.call("закрыть")
	await _settle(tree, 0.6)
	var panel: PanelContainer = mod.get("_panel") as PanelContainer
	var dock: HBoxContainer = mod.get("_dock") as HBoxContainer
	var ui_root: Control = mod.get("_root") as Control
	var proxies: Dictionary = mod.get("_proxies")
	var skin: Node = mod.get("_skin") as Node
	var audio: Node = mod.get("_audio") as Node
	_check("map_visible", is_instance_valid(map) and map.visible)
	_check("atlas_loaded_alongside", is_instance_valid(Pax.get_mod("earth_atlas")))
	_check("interface_created", is_instance_valid(panel) and is_instance_valid(dock) and is_instance_valid(ui_root))
	_check("six_command_proxies", proxies.size() == COMMANDS.size())
	var border_button: CheckButton = mod.get("_borders") as CheckButton
	var layer_button: Button = mod.get("_layers_button") as Button
	_check("map_border_control_available", is_instance_valid(border_button) and border_button.is_visible_in_tree())
	if is_instance_valid(border_button):
		var initial_border: bool = border_button.button_pressed
		border_button.button_pressed = not initial_border
		_check("map_border_uses_native_callback", bool(map.get("границы")) == not initial_border)
		border_button.button_pressed = initial_border
	if is_instance_valid(layer_button):
		var layer_window: Control = map.get("окно_слоёв") as Control
		layer_button.pressed.emit()
		_check("map_layers_native_window_opens", layer_window.visible)
		layer_button.pressed.emit()
		_check("map_layers_native_window_closes", not layer_window.visible)
	else:
		_check("map_layers_button_exists", false)
	if not is_instance_valid(panel) or not is_instance_valid(dock) or not is_instance_valid(ui_root) or proxies.size() != COMMANDS.size():
		_report["initial_tree"] = _tree_rects(main, 0, 4)
		_finish(tree)
		return
	var initial: Dictionary = (mod.get("_prefs") as Dictionary).duplicate(true)
	var baseline: Dictionary = initial.duplicate(true)
	baseline.merge({"theme": "graphite", "accent": "#279cab", "opacity": 0.96, "scale": 1.0, "font_size": 14, "labels": true, "sound_enabled": true, "volume": 0.35, "motion": true, "order": COMMANDS.duplicate()}, true)
	mod.call("apply_settings", baseline)
	await _settle(tree)
	var dock_id: int = dock.get_instance_id()
	var panel_id: int = panel.get_instance_id()
	mod.call("_world_ready", Pax.game)
	mod.call("_world_ready", Pax.game)
	await _settle(tree)
	_check("repeated_world_ready_preserves_dock", is_instance_valid(dock) and (mod.get("_dock") as Node).get_instance_id() == dock_id)
	_check("repeated_world_ready_preserves_panel", is_instance_valid(panel) and (mod.get("_panel") as Node).get_instance_id() == panel_id)
	_check("repeated_world_ready_no_duplicate_commands", (mod.get("_proxies") as Dictionary).size() == COMMANDS.size() and _dock_order(dock, proxies).size() == COMMANDS.size())
	_check_bounds("default_1920", tree, panel, dock, proxies, false)
	await _screenshot(tree, "default-1920.png")

	for id: String in COMMANDS:
		var button: Button = proxies.get(id) as Button
		var window: Control = main.get(WINDOWS[id]) as Control
		_check("native_" + id + "_exists", is_instance_valid(button) and is_instance_valid(window))
		if not is_instance_valid(button) or not is_instance_valid(window):
			continue
		_check("native_" + id + "_target", button.get_meta("win", null) == window)
		if window.visible:
			main.call("_переключить_окно", window)
			await _settle(tree)
		button.pressed.emit()
		await _settle(tree)
		_check("native_" + id + "_opens", window.visible)
		button.pressed.emit()
		await _settle(tree)
		_check("native_" + id + "_closes", not window.visible)
	_check_speed_callbacks(main, mod)

	var first: Button = proxies.get("orders") as Button
	var normal_style: StyleBoxFlat = first.get_theme_stylebox("normal") as StyleBoxFlat
	var before_color: Color = normal_style.bg_color if normal_style != null else Color.TRANSPARENT
	var minimum_before: Vector2 = first.custom_minimum_size
	first.mouse_entered.emit()
	await _settle(tree, 0.16)
	var hovered_style: StyleBoxFlat = first.get_theme_stylebox("normal") as StyleBoxFlat
	_check("hover_changes_background", hovered_style != null and not hovered_style.bg_color.is_equal_approx(before_color))
	await _screenshot(tree, "button-hover.png")
	var hover_color: Color = hovered_style.bg_color if hovered_style != null else Color.TRANSPARENT
	first.button_down.emit()
	await _settle(tree, 0.09)
	var pressed_style: StyleBoxFlat = first.get_theme_stylebox("normal") as StyleBoxFlat
	_check("press_changes_background", pressed_style != null and not pressed_style.bg_color.is_equal_approx(hover_color))
	_check("press_preserves_minimum_size", first.custom_minimum_size == minimum_before)
	await _screenshot(tree, "button-pressed.png")
	first.button_up.emit()
	first.mouse_exited.emit()
	await _settle(tree)
	_check("hover_returns_to_rest", normal_style != null and normal_style.bg_color.is_equal_approx(before_color))

	var settings_button: Button = mod.get("_settings_button") as Button
	_check("settings_button_exists", is_instance_valid(settings_button))
	if is_instance_valid(settings_button):
		settings_button.pressed.emit()
	else:
		mod.call("open_settings")
	await _settle(tree)
	_check("settings_button_opens_panel", panel.visible)
	_check_bounds("settings_1920", tree, panel, dock, proxies, true)
	await _screenshot(tree, "settings-1920.png")
	var saved_before_preview: String = FileAccess.get_file_as_string(PROFILE_PATH) if FileAccess.file_exists(PROFILE_PATH) else ""
	var draft: Dictionary = baseline.duplicate(true)
	draft["theme"] = "midnight"
	draft["accent"] = "#4da1f7"
	draft["opacity"] = 0.5
	mod.call("preview_settings", draft)
	panel.call("begin", mod.get("_prefs"))
	await _settle(tree)
	_check("preview_updates_live_settings", _settings_match(mod.get("_prefs"), draft))
	_check("preview_does_not_save", FileAccess.get_file_as_string(PROFILE_PATH) == saved_before_preview)
	var preview_style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check("minimum_opacity_reaches_background", preview_style != null and is_equal_approx(preview_style.bg_color.a, 0.5))
	_check("opacity_does_not_dim_window_contents", is_equal_approx(panel.modulate.a, 1.0))
	await _screenshot(tree, "theme-midnight.png")
	draft["theme"] = "slate"
	mod.call("preview_settings", draft)
	panel.call("begin", mod.get("_prefs"))
	await _settle(tree)
	await _screenshot(tree, "theme-slate.png")
	var cancel_button: Button = panel.find_child("CancelSettings", true, false) as Button
	if cancel_button != null:
		cancel_button.pressed.emit()
	else:
		mod.call("cancel_settings")
	await _settle(tree)
	_check("cancel_closes_panel", not panel.visible)
	_check("cancel_restores_original_settings", _settings_match(mod.get("_prefs"), baseline))
	_check("cancel_does_not_save", FileAccess.get_file_as_string(PROFILE_PATH) == saved_before_preview)

	var labels_before: Dictionary = {}
	for id: String in COMMANDS:
		labels_before[id] = str((proxies[id] as Button).get("caption").visible)
	mod.call("open_settings")
	await _settle(tree)
	var applied: Dictionary = baseline.duplicate(true)
	var reversed: Array = COMMANDS.duplicate()
	reversed.reverse()
	applied.merge({"theme": "midnight", "accent": "#4da1f7", "scale": 1.05, "font_size": 16, "labels": false, "sound_enabled": false, "volume": 0.17, "order": reversed}, true)
	mod.call("preview_settings", applied)
	panel.call("begin", applied)
	var apply_button: Button = panel.find_child("ApplySettings", true, false) as Button
	_check("apply_button_exists", is_instance_valid(apply_button))
	if apply_button != null:
		apply_button.pressed.emit()
	else:
		mod.call("apply_settings", applied)
	await _settle(tree)
	_check("apply_closes_panel", not panel.visible)
	_check("apply_updates_live_settings", _settings_match(mod.get("_prefs"), applied))
	_check("apply_saves_profile", _settings_match(_persisted_preferences(), applied))
	_check("dock_follows_saved_order", _dock_order(dock, proxies) == reversed)
	var labels_changed: bool = true
	for id: String in COMMANDS:
		var button: Button = proxies[id] as Button
		labels_changed = labels_changed and not (button.get("caption") as Label).visible and not button.tooltip_text.is_empty()
	_check("hidden_labels_keep_tooltips", labels_changed)
	_check("scale_requested_is_preserved", is_equal_approx(float((mod.get("_prefs") as Dictionary).get("scale", 0.0)), 1.05))
	if is_instance_valid(audio):
		audio.call("hover", first)
		audio.call("click", first)
		await tree.process_frame
		var quiet: bool = not bool(audio.get("sound_enabled"))
		var players: Array = audio.get("_players")
		for player: AudioStreamPlayer in players:
			quiet = quiet and not player.playing
		_check("mute_stops_and_suppresses_voices", quiet)
	else:
		_check("mute_stops_and_suppresses_voices", false, "Audio controller missing")

	mod.call("open_settings")
	await _settle(tree)
	var previous_order: Array = _dock_order(dock, proxies)
	panel.call("set_edit_mode", true)
	_check("order_editor_enters_edit_mode", bool(mod.get("_editing")))
	panel.call("request_order_move", "research", "orders")
	await _settle(tree)
	var panel_draft: Dictionary = panel.get("draft")
	_check("order_editor_updates_preview", _dock_order(dock, proxies) != previous_order and _dock_order(dock, proxies) == panel_draft.get("order", []))
	var reset_button: Button = panel.find_child("ResetSettings", true, false) as Button
	if reset_button != null:
		reset_button.pressed.emit()
	else:
		mod.call("reset_settings")
	await _settle(tree)
	var reset_values: Dictionary = mod.get("_prefs")
	_check("reset_previews_default_theme", str(reset_values.get("theme", "")) == "graphite")
	_check("reset_previews_default_order", reset_values.get("order", []) == COMMANDS)
	_check("reset_waits_for_apply_to_save", _settings_match(_persisted_preferences(), applied))
	mod.call("cancel_settings")
	await _settle(tree)
	_check("cancel_after_reset_restores_applied_profile", _settings_match(mod.get("_prefs"), applied))

	mod.call("open_settings")
	var compact: Dictionary = baseline.duplicate(true)
	compact.merge({"scale": 1.25, "font_size": 16, "sound_enabled": false}, true)
	mod.call("preview_settings", compact)
	panel.call("begin", mod.get("_prefs"))
	tree.root.size = Vector2i(1280, 720)
	await _settle(tree, 0.55)
	_check_bounds("settings_1280_scale125", tree, panel, dock, proxies, true)
	_report["compact_actual_root_scale"] = str(ui_root.scale)
	_report["compact_requested_scale"] = float((mod.get("_prefs") as Dictionary).get("scale", 0.0))
	await _screenshot(tree, "settings-1280-scale125.png")
	mod.call("cancel_settings")
	tree.root.size = Vector2i(1920, 1080)
	mod.call("apply_settings", baseline)
	await _settle(tree)

	var probe: Button = Button.new()
	probe.name = "InterfaceSkinProbe"
	probe.text = "QA"
	probe.position = Vector2(16, 100)
	probe.custom_minimum_size = Vector2(73, 27)
	var original_normal: StyleBoxFlat = StyleBoxFlat.new()
	original_normal.bg_color = Color("263042")
	probe.add_theme_stylebox_override("normal", original_normal)
	var semantic: Color = Color(0.1, 0.8, 0.1)
	probe.add_theme_color_override("font_color", semantic)
	Pax.game.hud_layer().add_child(probe)
	await _settle(tree)
	_check("dynamic_button_is_skinned", probe.get_theme_stylebox("normal") != original_normal)
	_check("dynamic_hud_control_enters_wrapper", is_instance_valid(ui_root) and ui_root.is_ancestor_of(probe))
	_check("semantic_text_color_preserved", probe.get_theme_color("font_color").is_equal_approx(semantic))
	for index: int in range(12):
		probe.mouse_entered.emit()
		probe.button_down.emit()
		probe.button_up.emit()
		probe.mouse_exited.emit()
	await _settle(tree)
	_check("rapid_actions_preserve_layout", probe.custom_minimum_size == Vector2(73, 27))
	if is_instance_valid(skin):
		var records: Dictionary = skin.get("_records")
		_check("dynamic_button_registered_once", records.has(probe.get_instance_id()))
		if records.has(probe.get_instance_id()):
			var record: Dictionary = records[probe.get_instance_id()]
			var tween: Tween = record.get("tween") as Tween
			_check("rapid_hover_does_not_queue_tweens", tween == null or not tween.is_running())
	var no_motion: Dictionary = baseline.duplicate(true)
	no_motion["motion"] = false
	mod.call("preview_settings", no_motion)
	probe.mouse_entered.emit()
	if is_instance_valid(skin):
		_check("motion_switch_reaches_skin", not bool(skin.get("_motion")))
		var records: Dictionary = skin.get("_records")
		if records.has(probe.get_instance_id()):
			var record: Dictionary = records[probe.get_instance_id()]
			var tween: Tween = record.get("tween") as Tween
			_check("motion_off_is_immediate", tween == null or not tween.is_running())
	probe.hide()
	var motion_runner: RefCounted = load(str(mod.call("path", "dev/motion_test.gd"))).new()
	var motion_report: Dictionary = await motion_runner.run(mod)
	_report["motion_audio_input"] = motion_report
	for key: String in motion_report.get("checks", {}):
		_check("motion_audio_" + key, bool(motion_report.checks[key]))
	var concept_runner: RefCounted = load(str(mod.call("path", "dev/concept_test.gd"))).new()
	var concept_report: Dictionary = await concept_runner.run(mod, _output)
	_report["concept"] = concept_report
	for key: String in concept_report.get("checks", {}):
		_check("concept_" + key, bool(concept_report.checks[key]))
	var native_bottom: Control = main.get("низ_панель") as Control
	mod.call("_mod_unloaded")
	mod.set_process(false)
	await _settle(tree)
	_check("unload_restores_native_bottom", is_instance_valid(native_bottom) and native_bottom.is_visible_in_tree())
	_check("unload_restores_original_style", is_instance_valid(probe) and probe.get_theme_stylebox("normal") == original_normal)
	_check("unload_removes_added_overrides", is_instance_valid(probe) and not probe.has_theme_stylebox_override("hover"))
	_check("unload_preserves_semantic_color", is_instance_valid(probe) and probe.get_theme_color("font_color").is_equal_approx(semantic))
	_check("unload_removes_custom_dock", not is_instance_valid(dock) or not dock.is_inside_tree())
	_check_native_restore(native_snapshot)
	main.call("_переключить_окно", main.get("окно_приказов"))
	await _settle(tree)
	_check("native_window_opens_after_unload", (main.get("окно_приказов") as Control).visible)
	main.call("_переключить_окно", main.get("окно_приказов"))
	await _settle(tree)
	await _screenshot(tree, "unloaded-native-1920.png")
	if is_instance_valid(probe):
		probe.queue_free()
	var roles_runner: RefCounted = load(str(mod.call("path", "dev/roles_test.gd"))).new()
	var roles_report: Dictionary = await roles_runner.run(mod, _output)
	_report["roles"] = roles_report
	for key: String in roles_report.get("checks", {}):
		_check("roles_" + key, bool(roles_report.checks[key]))
	_report["limitations"] = "Native Main and original callbacks; signals are emitted by the QA harness rather than OS mouse automation. Fresh world only. Audio comfort still needs listening, not inferred from playback state."
	_finish(tree)


func _check(key: String, passed: bool, detail: String = "") -> void:
	(_report["checks"] as Dictionary)[key] = passed
	if not passed:
		(_report["failures"] as Array).append({"check": key, "detail": detail})
		print("INTERFACE_ASSERT_FAILED ", key, " ", detail)


func _snapshot_native(main: Node) -> Dictionary:
	var snapshot: Dictionary = {}
	for key: String in ["кнопка_помощника", "кнопка_связей", "кнопка_державы"]:
		var button: Button = main.get(key) as Button
		if button == null:
			continue
		snapshot[key] = {
			"node": button, "parent": button.get_parent(),
			"properties": {"text": button.text, "icon": button.icon, "expand_icon": button.expand_icon, "clip_text": button.clip_text},
			"constant_present": button.has_theme_constant_override("icon_max_width"),
			"constant_value": button.get_theme_constant("icon_max_width"),
			"font_present": button.has_theme_font_size_override("font_size"),
			"font_value": button.get_theme_font_size("font_size"),
			"meta_present": button.has_meta("pax_interface_selected"),
			"meta_value": button.get_meta("pax_interface_selected") if button.has_meta("pax_interface_selected") else null,
		}
	var title: Label = main.get("заголовок") as Label
	var window_frame: MarginContainer = (main.get("низ_столб") as Control).get_parent() as MarginContainer
	if window_frame != null:
		snapshot["window_frame"] = {"node": window_frame, "parent": window_frame.get_parent(), "properties": {}, "margin_present": window_frame.has_theme_constant_override("margin_bottom"), "margin_value": window_frame.get_theme_constant("margin_bottom")}
	if title != null:
		snapshot["title"] = {"node": title, "parent": title.get_parent(), "properties": {"clip_text": title.clip_text, "text_overrun_behavior": title.text_overrun_behavior, "tooltip_text": title.tooltip_text}}
	var header: Control = main.get("верх_панель") as Control
	if header != null:
		snapshot["header"] = {"node": header, "parent": header.get_parent(), "properties": {"clip_contents": header.clip_contents}}
	var next: Control = main.get("кнопка_до_события") as Control
	if next != null:
		snapshot["next_event"] = {"node": next, "parent": next.get_parent(), "properties": {"visible": next.visible}}
	return snapshot


func _check_native_restore(snapshot: Dictionary) -> void:
	_check("native_snapshot_covers_controls", snapshot.size() == 7)
	for key: String in snapshot:
		var record: Dictionary = snapshot[key]
		var control: Control = record["node"] as Control
		_check("restore_" + key + "_alive", is_instance_valid(control))
		if not is_instance_valid(control):
			continue
		_check("restore_" + key + "_parent", control.get_parent() == record["parent"])
		var properties: Dictionary = record["properties"]
		if record.has("margin_present"):
			_check("restore_native_window_clearance", control.has_theme_constant_override("margin_bottom") == bool(record.margin_present) and control.get_theme_constant("margin_bottom") == int(record.margin_value))
		for property: String in properties:
			_check("restore_" + key + "_" + property, control.get(property) == properties[property])
		if record.has("constant_present"):
			_check("restore_" + key + "_font_presence", control.has_theme_font_size_override("font_size") == bool(record["font_present"]))
			_check("restore_" + key + "_font_value", control.get_theme_font_size("font_size") == int(record["font_value"]))
			_check("restore_" + key + "_icon_constant_presence", control.has_theme_constant_override("icon_max_width") == bool(record["constant_present"]))
			_check("restore_" + key + "_icon_constant_value", control.get_theme_constant("icon_max_width") == int(record["constant_value"]))
			_check("restore_" + key + "_selected_meta_presence", control.has_meta("pax_interface_selected") == bool(record["meta_present"]))
			var selected_meta: Variant = control.get_meta("pax_interface_selected") if control.has_meta("pax_interface_selected") else null
			_check("restore_" + key + "_selected_meta_value", selected_meta == record["meta_value"])


func _check_speed_callbacks(main: Node, mod: Node) -> void:
	var speeds: Array = main.get("кнопки_скорости")
	var skin: Node = mod.get("_skin") as Node
	var records: Dictionary = skin.get("_records") if is_instance_valid(skin) else {}
	_check("speed_controls_present", speeds.size() >= 2)
	for index: int in range(speeds.size()):
		var button: BaseButton = speeds[index] as BaseButton
		_check("speed_" + str(index) + "_is_button", is_instance_valid(button))
		if not is_instance_valid(button):
			continue
		_check("speed_" + str(index) + "_skinned", records.has(button.get_instance_id()))
		button.pressed.emit()
		var accepted: bool = not bool(main.get("автоигра")) if index == 0 else bool(main.get("автоигра")) and int(main.get("скорость_наблюдения")) == index
		_check("speed_" + str(index) + "_native_callback", accepted)
		# No frame is yielded while simulation is running.
		Pax.game.set_speed(0)
		_check("speed_" + str(index) + "_returns_to_pause", not bool(main.get("автоигра")))
	var always_pause: Button = mod.get("_pause_button") as Button
	if speeds.size() > 1 and is_instance_valid(always_pause):
		(speeds[1] as BaseButton).pressed.emit()
		always_pause.pressed.emit()
		_check("always_available_pause_uses_native_command", not bool(main.get("автоигра")))
	else:
		_check("always_available_pause_uses_native_command", false)
	Pax.game.set_speed(0)


func _settings_match(actual: Variant, expected: Dictionary) -> bool:
	if not actual is Dictionary:
		return false
	var values: Dictionary = actual
	for key: String in SETTING_KEYS:
		if not expected.has(key):
			continue
		if not values.has(key):
			return false
		if expected[key] is float or expected[key] is int:
			if not is_equal_approx(float(values[key]), float(expected[key])):
				return false
		elif values[key] != expected[key]:
			return false
	return true


func _persisted_preferences() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not parsed is Dictionary:
		return {}
	var profile: Dictionary = parsed
	return profile.get("appearance", {})


func _dock_order(dock: HBoxContainer, proxies: Dictionary) -> Array:
	var order: Array = []
	for child: Node in dock.get_children():
		for key: String in COMMANDS:
			if proxies.get(key) == child:
				order.append(key)
	return order


func _settle(tree: SceneTree, seconds: float = 0.28) -> void:
	await tree.create_timer(seconds).timeout
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _screenshot(tree: SceneTree, filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var result: Error = tree.root.get_texture().get_image().save_png(_output.path_join(filename))
	_check("screenshot_" + filename, result == OK)
	if result == OK:
		(_report["screenshots"] as Array).append(filename)


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _rect_sample(control: Control) -> Dictionary:
	var logical: Rect2 = _screen_rect(control)
	return {"logical": str(logical), "pixels": str(control.get_viewport().get_final_transform() * logical)}


func _check_bounds(label: String, tree: SceneTree, panel: PanelContainer, dock: HBoxContainer, proxies: Dictionary, panel_expected: bool) -> void:
	# Control transforms are logical canvas units, not native window pixels.
	# Main uses content_scale, so those spaces differ at both tested resolutions.
	var viewport: Rect2 = tree.root.get_visible_rect().grow(2.0)
	var rects: Dictionary = {"viewport_logical": str(viewport), "window_pixels": str(tree.root.size), "final_transform": str(tree.root.get_final_transform()), "dock": _rect_sample(dock), "panel": _rect_sample(panel)}
	_check(label + "_dock_in_view", viewport.encloses(_screen_rect(dock)) and dock.size.x > 0.0 and dock.size.y > 0.0)
	var commands_ok: bool = true
	for id: String in COMMANDS:
		var button: Button = proxies.get(id) as Button
		if not is_instance_valid(button):
			commands_ok = false
			continue
		var rect: Rect2 = _screen_rect(button)
		rects[id] = _rect_sample(button)
		commands_ok = commands_ok and viewport.encloses(rect) and rect.size.x >= 20.0 and rect.size.y >= 20.0 and button.is_visible_in_tree()
	_check(label + "_all_commands_in_view", commands_ok)
	if panel_expected:
		_check(label + "_panel_in_view", panel.visible and viewport.encloses(_screen_rect(panel)))
		var actions_ok: bool = true
		for name: String in ["CloseSettings", "CancelSettings", "ApplySettings", "ResetSettings"]:
			var button: Button = panel.find_child(name, true, false) as Button
			if not is_instance_valid(button):
				actions_ok = false
				continue
			rects[name] = _rect_sample(button)
			actions_ok = actions_ok and button.is_visible_in_tree() and viewport.encloses(_screen_rect(button))
		_check(label + "_panel_actions_in_view", actions_ok)
	var main: Node = Pax.game.main
	var header: Control = main.get("верх_панель") as Control
	var header_ok: bool = is_instance_valid(header) and header.is_visible_in_tree() and viewport.encloses(_screen_rect(header))
	_check(label + "_header_in_view", header_ok)
	if is_instance_valid(header):
		rects["header"] = _rect_sample(header)
	var header_buttons_ok: bool = true
	for key: String in ["кнопка_помощника", "кнопка_связей", "кнопка_державы", "кнопка_карты", "кнопка_перемотки", "кнопка_до_события"]:
		var control: Control = main.get(key) as Control
		if not is_instance_valid(control):
			header_buttons_ok = false
			continue
		rects[key] = _rect_sample(control)
		header_buttons_ok = header_buttons_ok and control.is_visible_in_tree() and viewport.encloses(_screen_rect(control))
	_check(label + "_header_actions_in_view", header_buttons_ok)
	var speeds_ok: bool = true
	var speeds: Array = main.get("кнопки_скорости")
	for index: int in range(speeds.size()):
		var button: Control = speeds[index] as Control
		if not is_instance_valid(button):
			speeds_ok = false
			continue
		rects["speed_" + str(index)] = _rect_sample(button)
		speeds_ok = speeds_ok and button.is_visible_in_tree() and viewport.encloses(_screen_rect(button))
	_check(label + "_all_speeds_in_view", not speeds.is_empty() and speeds_ok)
	(_report["rects"] as Dictionary)[label] = rects
	if not viewport.encloses(_screen_rect(dock)) or (panel_expected and not viewport.encloses(_screen_rect(panel))) or not commands_ok or not header_ok or not header_buttons_ok or not speeds_ok:
		_report[label + "_tree"] = _tree_rects(panel, 0, 6) + _tree_rects(dock, 0, 3) + _tree_rects(header, 0, 5)
		print("INTERFACE_BAD_RECTS ", label, " ", JSON.stringify(rects))


func _tree_rects(node: Node, depth: int, maximum: int) -> Array:
	var rows: Array = []
	if not is_instance_valid(node) or depth > maximum:
		return rows
	if node is Control:
		var control: Control = node as Control
		rows.append({"path": str(control.get_path()), "class": control.get_class(), "visible": control.is_visible_in_tree(), "rect": _rect_sample(control), "minimum": str(control.get_combined_minimum_size()), "scale": str(control.scale), "clip": control.clip_contents})
	for child: Node in node.get_children():
		rows.append_array(_tree_rects(child, depth + 1, maximum))
	return rows


func _finish(tree: SceneTree) -> void:
	if _had_profile:
		var original: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
		original.store_string(_old_profile)
		original.close()
	elif FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE_PATH))
	_report["ok"] = (_report["failures"] as Array).is_empty()
	_report["assertion_count"] = (_report["checks"] as Dictionary).size()
	var file: FileAccess = FileAccess.open(_output.path_join("live-test-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	print("INTERFACE_LIVE_RESULT ", JSON.stringify(_report))
	tree.quit(0 if bool(_report["ok"]) else 1)
