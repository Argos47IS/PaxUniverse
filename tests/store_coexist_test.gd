extends RefCounted
## External QA only. Uses installed mods; contains no third-party code or assets.
## Covers HUD coexistence, not Cosmic Expansion simulation or campaign balance.

var _report: Dictionary = {"checks": {}, "failures": [], "observations": {}, "screenshots": [], "scope": "Installed Atlas/HUD coexistence with Cosmic Expansion and Event Banners UI; no simulation, saved campaigns, network or asset redistribution."}
var _tree: SceneTree
var _output: String

func start_native_control(output: String) -> Dictionary:
	_output = output
	_tree = Pax.get_tree()
	_report = {"checks": {}, "failures": [], "observations": {}, "screenshots": [], "scope": "Diagnostic control without Pax Interface: original Cosmic native window callbacks only; engine errors remain failures in the outer runner."}
	_phase("native_control_start")
	_check("isolated_profile", OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"))
	var game: PaxGame = Pax.game
	var cosmic: Node = Pax.get_mod("cosmic_expansion")
	_check("native_control_hud_absent", not is_instance_valid(Pax.get_mod("pax_interface")))
	_check("native_control_cosmic_loaded", is_instance_valid(cosmic))
	_check("native_control_banners_loaded", is_instance_valid(Pax.get_mod("event_banners")))
	_check("native_control_world_exists", is_instance_valid(game) and is_instance_valid(game.main))
	if not (_report.failures as Array).is_empty():
		return _finish()
	game.set_speed(0)
	var original_day: int = game.day()
	var main: Node = game.main
	var planets: Control = main.get("окно_планет") as Control
	_check("native_control_planets_exists", is_instance_valid(planets))
	if not is_instance_valid(planets):
		return _finish()
	var planets_before: bool = planets.visible
	var windows_before: Array = []
	for value: Variant in main.get("окна_модов"):
		if value is Control:
			windows_before.append({"node": value, "visible": (value as Control).visible})
	var details: Dictionary = {}
	for spec: Array in [["arks", "_ковчеги", "_окно_ковчегов"], ["bestiary", "_снайяд", "_окно"]]:
		var label: String = "native_control_" + str(spec[0])
		_phase(label + "_inspect")
		var module: Node = cosmic.get(str(spec[1])) as Node
		_check(label + "_module_created", is_instance_valid(module))
		if not is_instance_valid(module):
			continue
		var button: Button = module.get("_вход") as Button
		var window: Control = module.get(str(spec[2])) as Control
		_check(label + "_button_exists", is_instance_valid(button))
		_check(label + "_window_exists", is_instance_valid(window))
		if not is_instance_valid(button) or not is_instance_valid(window):
			continue
		_check(label + "_button_is_in_tree", button.is_inside_tree())
		_check(label + "_entry_inside_native_planets", planets.is_ancestor_of(button))
		_check(label + "_window_registered", (main.get("окна_модов") as Array).has(window))
		_check(label + "_callback_exists", not button.get_signal_connection_list("pressed").is_empty())
		var children: Array = []
		for child: Node in planets.get_children():
			children.append(_node_info(child))
		details[str(spec[0])] = {"button": _node_info(button), "window": _node_info(window), "planets": _node_info(planets), "planets_children": children, "route": "original native button.pressed; no HUD loaded; no science/discovery unlock or OS click"}
		if not button.is_inside_tree():
			continue
		_phase(label + "_before_show_planets")
		window.hide()
		planets.show()
		await _settle(0.3)
		var calls: Array[int] = [0]
		var counter: Callable = func() -> void: calls[0] += 1
		button.pressed.connect(counter)
		_phase(label + "_before_press_open")
		button.pressed.emit()
		_phase(label + "_after_press_open")
		await _settle(0.3)
		_check(label + "_opens_window", window.is_visible_in_tree())
		_check(label + "_callback_called_once", calls[0] == 1)
		_phase(label + "_before_press_close")
		button.pressed.emit()
		_phase(label + "_after_press_close")
		await _settle(0.3)
		_check(label + "_closes_window", not window.visible)
		_check(label + "_callback_once_per_press", calls[0] == 2)
		if button.pressed.is_connected(counter):
			button.pressed.disconnect(counter)
	for record: Dictionary in windows_before:
		var control: Control = record.node as Control
		if is_instance_valid(control):
			control.visible = bool(record.visible)
	planets.visible = planets_before
	game.set_speed(0)
	_check("native_control_day_unchanged", game.day() == original_day)
	(_report.observations as Dictionary)["native_cosmic_ui"] = details
	_phase("native_control_finish")
	return _finish()

func start(output: String) -> Dictionary:
	_output = output
	_phase("start")
	_tree = Pax.get_tree()
	_check("isolated_profile", OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"))
	var game: PaxGame = Pax.game
	_check("world_exists", is_instance_valid(game) and is_instance_valid(game.main))
	var hud: Node = Pax.get_mod("pax_interface")
	var atlas: Node = Pax.get_mod("earth_atlas")
	var banners: Node = Pax.get_mod("event_banners")
	var cosmic: Node = Pax.get_mod("cosmic_expansion")
	for pair: Array in [["hud", hud], ["atlas", atlas], ["banners", banners], ["cosmic", cosmic]]:
		_check(str(pair[0]) + "_loaded", is_instance_valid(pair[1]))
	if not (_report.failures as Array).is_empty():
		return _finish()
	var main: Node = game.main
	var old_preferences: Dictionary = (hud.get("_prefs") as Dictionary).duplicate(true)
	var preference_file: String = "user://mod_settings/pax_interface.json"
	var preference_hash: String = FileAccess.get_sha256(preference_file) if FileAccess.file_exists(preference_file) else "absent"
	var original_day: int = game.day()
	var original_auto: bool = bool(main.get("автоигра"))
	game.set_speed(0)
	# The public banner API honors user preferences. The isolated profile must
	# enable its card path; never rewrite settings just to produce a passing test.
	_check("banner_cards_enabled", int(banners.call("get_setting", "cards", 1)) != 0)
	_check("banner_pause_enabled", int(banners.call("get_setting", "pause", 1)) != 0)
	_check("banner_public_api", banners.has_method("push"))
	_check("banner_queue_idle", not bool(banners.get("_разбираю")) and (banners.get("_очередь") as Array).is_empty())
	_check("observer_mode_off", not original_auto)
	if not (_report.failures as Array).is_empty():
		return _finish()
	var card: CanvasItem = main.get("карточка") as CanvasItem
	var old_card_visible: bool = card.visible if is_instance_valid(card) else false
	if is_instance_valid(card):
		card.hide()
	_phase("before_cosmic_ui")
	await _cosmic_ui(game, hud, cosmic)
	_phase("after_cosmic_ui")
	for scale: float in [1.0, 1.25]:
		var preferences: Dictionary = old_preferences.duplicate(true)
		preferences.merge({"scale": scale, "sound_enabled": false}, true)
		hud.call("preview_settings", preferences)
		await _settle(0.35)
		var label: String = "banner_scale_" + str(scale).replace(".", "_")
		_phase(label + "_before_public_push")
		await _banner_card(label, game, hud, banners)
		_phase(label + "_finished")
		game.set_speed(0)
		if bool(banners.get("_разбираю")):
			# Do not enqueue a second event while a failed first request is pending.
			break
	hud.call("preview_settings", old_preferences)
	game.set_speed(0)
	if is_instance_valid(card):
		card.visible = old_card_visible
	await _settle(0.3)
	_check("hud_preferences_restored", (hud.get("_prefs") as Dictionary) == old_preferences)
	_check("hud_settings_file_unchanged", (FileAccess.get_sha256(preference_file) if FileAccess.file_exists(preference_file) else "absent") == preference_hash)
	_check("world_day_unchanged", game.day() == original_day)
	_check("observer_mode_unchanged", bool(main.get("автоигра")) == original_auto)
	_check("banner_queue_empty_at_end", not bool(banners.get("_разбираю")) and (banners.get("_очередь") as Array).is_empty())
	_check_skin("final", hud)
	return _finish()

func _cosmic_ui(game: PaxGame, hud: Node, cosmic: Node) -> void:
	var main: Node = game.main
	var planets: Control = main.get("окно_планет") as Control
	_check("cosmic_native_planets_window", is_instance_valid(planets))
	if not is_instance_valid(planets):
		return
	var windows_before: Array = []
	for value: Variant in main.get("окна_модов"):
		if value is Control:
			windows_before.append({"node": value, "visible": (value as Control).visible})
	var planets_before: bool = planets.visible
	var details: Dictionary = {}
	for spec: Array in [["arks", "_ковчеги", "_окно_ковчегов"], ["bestiary", "_снайяд", "_окно"]]:
		var label: String = "cosmic_" + str(spec[0])
		_phase(label + "_inspect")
		var module: Node = cosmic.get(str(spec[1])) as Node
		_check(label + "_module_created", is_instance_valid(module))
		if not is_instance_valid(module):
			continue
		var button: Button = module.get("_вход") as Button
		var window: Control = module.get(str(spec[2])) as Control
		_check(label + "_native_entry_created", is_instance_valid(button))
		_check(label + "_window_created", is_instance_valid(window))
		if not is_instance_valid(button) or not is_instance_valid(window):
			continue
		_check(label + "_native_entry_is_in_tree", button.is_inside_tree())
		var diagnostic: Dictionary = _cosmic_diagnostic(game, hud, button, planets)
		var in_planets: bool = planets.is_ancestor_of(button)
		var entry: Button = button if in_planets else null
		var route: String = "native planets button" if in_planets else "missing"
		var proxy_route: bool = false
		if not in_planets:
			var extras: Dictionary = hud.get("_extras") as Dictionary
			var extra: Dictionary = extras.get(button.get_instance_id(), {}) as Dictionary
			var proxy: Button = extra.get("proxy") as Button
			var tools: Control = hud.get("_tools") as Control
			proxy_route = extra.get("native") == button and is_instance_valid(proxy) and is_instance_valid(tools) and tools.is_ancestor_of(proxy)
			if proxy_route:
				entry = proxy
				route = "HUD extra proxy -> existing native button"
		_check(label + "_entry_has_native_or_hud_route", in_planets or proxy_route)
		_check(label + "_window_registered", (main.get("окна_модов") as Array).has(window))
		_check(label + "_native_callback_exists", not button.get_signal_connection_list("pressed").is_empty())
		if not is_instance_valid(entry):
			details[str(spec[0])] = {"route": route, "diagnostic": diagnostic}
			continue
		_check(label + "_entry_callback_exists", not entry.get_signal_connection_list("pressed").is_empty())
		# Buttons can live in the planets window or in a native extra-button
		# slot represented by the HUD's proxy. Both must retain the actual route.
		# Science/discovery gates stay intact: hidden controls are handler tests,
		# never claimed as successful OS clicks or newly unlocked features.
		_phase(label + "_before_show_planets")
		window.hide()
		planets.show()
		await _settle(0.3)
		_check(label + "_entry_preserves_visibility_gate", entry.visible == button.visible)
		_check(label + "_entry_preserves_disabled_state", entry.disabled == button.disabled)
		if button.visible:
			_check(label + "_visible_entry_inside_viewport", entry.is_visible_in_tree() and _tree.root.get_visible_rect().grow(2.0).encloses(_rect(entry)) and entry.size.x > 0.0 and entry.size.y > 0.0)
		details[str(spec[0])] = {"entry_visible_by_game_rules": button.visible, "entry_disabled": button.disabled, "native_parent": str(button.get_parent().name), "actual_entry_parent": str(entry.get_parent().name), "window_parent": str(window.get_parent().name), "route": route, "activation": "actual entry.pressed emitted; native callback counted; no research/discovery unlock or OS click", "diagnostic": diagnostic}
		var calls: Array[int] = [0]
		var counter: Callable = func() -> void: calls[0] += 1
		button.pressed.connect(counter)
		_phase(label + "_before_press_open")
		entry.pressed.emit()
		_phase(label + "_after_press_open")
		await _settle(0.3)
		_check(label + "_entry_invokes_native_once", calls[0] == 1)
		_check(label + "_native_entry_opens_window", window.is_visible_in_tree())
		var skin: Node = hud.get("_skin") as Node
		_check(label + "_entry_has_skin", is_instance_valid(skin) and (skin.get("_records") as Dictionary).has(entry.get_instance_id()))
		_phase(label + "_before_press_close")
		entry.pressed.emit()
		_phase(label + "_after_press_close")
		await _settle(0.3)
		_check(label + "_entry_invokes_native_once_per_press", calls[0] == 2)
		_check(label + "_native_entry_closes_window", not window.visible)
		if button.pressed.is_connected(counter):
			button.pressed.disconnect(counter)

	for record: Dictionary in windows_before:
		var control: Control = record.node as Control
		if is_instance_valid(control):
			control.visible = bool(record.visible)
	planets.visible = planets_before
	(_report.observations as Dictionary)["cosmic_ui"] = details

func _cosmic_diagnostic(game: PaxGame, hud: Node, button: Button, planets: Control) -> Dictionary:
	var details: Dictionary = {"native": _node_info(button), "hud_layer": _node_info(game.hud_layer()), "hud_root": _node_info(hud.get("_root") as Node), "planets": _node_info(planets), "planets_children": [], "extras": [], "native_bottom_buttons": []}
	for child: Node in planets.get_children():
		(details.planets_children as Array).append(_node_info(child))
	for key: Variant in (hud.get("_extras") as Dictionary):
		var record: Dictionary = (hud.get("_extras") as Dictionary)[key]
		var native: Node = record.get("native") as Node
		(details.extras as Array).append({"key": str(key), "matches_entry": native == button, "native": _node_info(native), "proxy": _node_info(record.get("proxy") as Node)})
	var bottom: Node = game.main.get("низ_кнопки") as Node
	if is_instance_valid(bottom):
		for child: Node in bottom.get_children():
			if child is Button:
				var info: Dictionary = _node_info(child)
				info["has_win_meta"] = child.has_meta("win")
				(details.native_bottom_buttons as Array).append(info)
	return details

func _node_info(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {"exists": false}
	var ancestors: Array = []
	var parent: Node = node.get_parent()
	var cursor: Node = parent
	while is_instance_valid(cursor) and ancestors.size() < 12:
		ancestors.append({"name": str(cursor.name), "class": cursor.get_class(), "id": cursor.get_instance_id()})
		cursor = cursor.get_parent()
	var result: Dictionary = {"exists": true, "id": node.get_instance_id(), "class": node.get_class(), "name": str(node.name), "in_tree": node.is_inside_tree(), "path": str(node.get_path()) if node.is_inside_tree() else "", "parent": str(parent.name) if is_instance_valid(parent) else "none", "ancestors": ancestors}
	var script: Script = node.get_script() as Script
	result["script"] = script.resource_path if is_instance_valid(script) else ""
	if node is Control:
		result["visible"] = (node as Control).visible
		result["visible_in_tree"] = (node as Control).is_visible_in_tree()
	return result

func _phase(name: String) -> void:
	# Same stderr stream as engine errors preserves phase boundaries.
	printerr("STORE_COEXIST_PHASE " + name)

func _banner_card(label: String, game: PaxGame, hud: Node, banners: Node) -> void:
	_check(label + "_queue_idle_before_push", not bool(banners.get("_разбираю")))
	var marker: String = "Pax coexist QA " + label
	banners.call("push", {"тело": game.home_body(), "тон": "нейтрально", "вес": 4, "что": marker, "последствия": ["Synthetic UI test only"], "цитата": ""})
	var overlay: Control
	var deadline: int = Time.get_ticks_msec() + 27000
	while Time.get_ticks_msec() < deadline:
		overlay = _find_banner_overlay(_tree.root, banners)
		if is_instance_valid(overlay):
			break
		await _tree.create_timer(0.1).timeout
	_check(label + "_public_push_created_overlay", is_instance_valid(overlay))
	if not is_instance_valid(overlay):
		return
	await _settle(0.45)
	var viewport: Rect2 = _tree.root.get_visible_rect()
	var bounds: Rect2 = _rect(overlay)
	var content: Control = _banner_content(overlay)
	_check(label + "_overlay_visible", overlay.is_visible_in_tree())
	_check(label + "_overlay_fills_viewport", bounds.position.distance_to(viewport.position) <= 2.0 and bounds.end.distance_to(viewport.end) <= 2.0)
	_check(label + "_content_exists", is_instance_valid(content))
	if is_instance_valid(content):
		_check(label + "_content_inside_viewport", viewport.grow(2.0).encloses(_rect(content)))
	_check(label + "_modal_receives_input", overlay.mouse_filter == Control.MOUSE_FILTER_STOP)
	(_report.observations as Dictionary)[label] = {"viewport": str(viewport), "overlay": str(bounds), "content": str(_rect(content)) if is_instance_valid(content) else "missing", "hud_scale": str((hud.get("_root") as Control).scale), "overlay_parent": str(overlay.get_parent().name), "api": "event_banners.push", "close_route": "overlay.gui_input -> existing native callback"}
	await _screenshot(label + ".png")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = overlay.size * 0.5
	click.global_position = bounds.get_center()
	# Emit the real Control input signal: keeps the installed mod's close
	# callback and coroutine cleanup, without relying on OS focus automation.
	overlay.gui_input.emit(click)
	deadline = Time.get_ticks_msec() + 2000
	while is_instance_valid(overlay) and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	game.set_speed(0)
	await _settle(0.2)
	_check(label + "_native_input_closes_overlay", not is_instance_valid(overlay))
	_check(label + "_queue_drained", not bool(banners.get("_разбираю")) and (banners.get("_очередь") as Array).is_empty())
	_check_skin(label, hud)

func _find_banner_overlay(node: Node, banners: Node) -> Control:
	if node is Control:
		for connection: Dictionary in node.get_signal_connection_list("gui_input"):
			var callback: Callable = connection.get("callable", Callable())
			if callback.is_valid() and callback.get_object() == banners and callback.get_method() == &"_нажали":
				return node as Control
	for child: Node in node.get_children():
		var found: Control = _find_banner_overlay(child, banners)
		if is_instance_valid(found):
			return found
	return null

func _banner_content(overlay: Control) -> Control:
	for child: Node in overlay.get_children():
		if child is CenterContainer and child.get_child_count() > 0:
			return child.get_child(0) as Control
	return null

func _check_skin(label: String, hud: Node) -> void:
	var skin: Node = hud.get("_skin") as Node
	var dock: Control = hud.get("_dock") as Control
	var proxies: Dictionary = hud.get("_proxies") as Dictionary
	_check(label + "_hud_dock_alive", is_instance_valid(dock) and dock.is_visible_in_tree())
	var ready: bool = is_instance_valid(skin) and bool(skin.get("_active")) and not proxies.is_empty()
	if ready:
		var records: Dictionary = skin.get("_records") as Dictionary
		for value: Variant in proxies.values():
			if not is_instance_valid(value) or not records.has((value as Control).get_instance_id()):
				ready = false
	_check(label + "_hud_skin_still_tracks_proxies", ready)

func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)

func _settle(seconds: float) -> void:
	await _tree.create_timer(seconds).timeout
	await _tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var result: Error = _tree.root.get_texture().get_image().save_png(_output.path_join(name))
	_check("screenshot_" + name, result == OK)
	if result == OK:
		(_report.screenshots as Array).append(name)

func _check(name: String, value: bool) -> void:
	(_report.checks as Dictionary)[name] = value
	if not value:
		(_report.failures as Array).append(name)
		push_error("STORE_COEXIST_FAIL " + name)

func _finish() -> Dictionary:
	_report.ok = (_report.failures as Array).is_empty()
	var file: FileAccess = FileAccess.open(_output.path_join("store-coexist-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t"))
		file.close()
	return _report
