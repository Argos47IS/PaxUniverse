extends RefCounted
## Role adapters in the existing isolated world. No Main creation, orders or saves.

const IDS: Array[String] = ["orders", "plans", "laws", "objects", "mining", "research"]
const PROFILE: String = "user://mod_settings/pax_interface.json"

var _report: Dictionary = {}
var _output: String = ""
var _detach_sequence: int = 0


func run(mod: Node, output: String) -> Dictionary:
	_report = {"checks": {}, "failures": [], "screenshots": [], "roles": {}, "window_details": {}, "fixtures": {}}
	_output = output
	var game: PaxGame = Pax.game
	_check("isolated_profile", OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"))
	_check("role_api_available", is_instance_valid(game) and is_instance_valid(game.main) and game.main.has_method("_интерфейс_по_роли"))
	if not bool((_report["checks"] as Dictionary)["isolated_profile"]) or not bool((_report["checks"] as Dictionary)["role_api_available"]):
		return _finish()
	var tree: SceneTree = mod.get_tree()
	var main: Node = game.main
	var old_unloaded: bool = bool(mod.get("_unloaded"))
	var old_processing: bool = mod.is_processing()
	var old_attached: bool = is_instance_valid(mod.get("_root"))
	var old_preferences: Dictionary = (mod.get("_prefs") as Dictionary).duplicate(true)
	var old_window: Dictionary = {}
	for key: String in ["size", "content_scale_size", "content_scale_mode", "content_scale_aspect", "content_scale_factor"]:
		old_window[key] = tree.root.get(key)
	var profile_before: String = FileAccess.get_file_as_string(PROFILE) if FileAccess.file_exists(PROFILE) else ""
	await _detach(mod, tree)
	var native: Dictionary = _snapshot_native(main)
	var old_role: String = str(main.get("роль_игрока"))
	var affairs_before: Variant = main.get("дела")
	var affairs_serialized: String = JSON.stringify(affairs_before)
	var old_affairs_window: Control = main.get("окно_дел") as Control
	var preferences: Dictionary = old_preferences.duplicate(true)
	preferences.merge({"scale": 1.0, "font_size": 14, "labels": true, "motion": true, "sound_enabled": false}, true)
	mod.set("_prefs", preferences)
	for role: String in ["человек", "организация"]:
		await _detach(mod, tree)
		_restore_native(main, native)
		main.set("роль_игрока", role)
		main.call("_интерфейс_по_роли")
		_hide_windows(main)
		_window(tree.root, Vector2i(1920, 1080))
		var expected: Dictionary = _native_captions(main)
		mod.set("_unloaded", false)
		mod.set_process(true)
		mod.call("_world_ready", game)
		await _settle(tree, 0.65)
		var ready: bool = _hud_ready(mod)
		_check(role + "_cold_role_hud_attaches", ready)
		if not ready:
			continue
		_check_role_presentations(role, mod, main, expected)
		_check_bounds(role + "_1920", mod, tree)
		await _screenshot(tree, "role-" + role + "-hud1920.png")
		await _check_proxy(role, "mining", "окно_дел", mod, main, tree, true)
		await _check_proxy(role, "laws", "окно_законов", mod, main, tree, false)
		await _check_customization(role, mod, expected, tree)
		var compact: Dictionary = preferences.duplicate(true)
		compact.merge({"scale": 1.25, "font_size": 16}, true)
		mod.call("preview_settings", compact)
		_window(tree.root, Vector2i(1280, 720))
		await _settle(tree, 0.65)
		_check_bounds(role + "_1280_scale125", mod, tree)
		await _screenshot(tree, "role-" + role + "-hud1280-scale125.png")
		mod.call("preview_settings", preferences)
	# Exercise a changed native win while the same HUD and proxy remain alive.
	await _detach(mod, tree)
	_restore_native(main, native)
	main.set("роль_игрока", old_role)
	_window(tree.root, Vector2i(1920, 1080))
	mod.set("_prefs", preferences)
	mod.set("_unloaded", false)
	mod.set_process(true)
	mod.call("_world_ready", game)
	await _settle(tree, 0.65)
	var original_proxy: Button = (mod.get("_proxies") as Dictionary).get("mining") as Button
	var prior_window: Control = original_proxy.get_meta("win") as Control if is_instance_valid(original_proxy) and original_proxy.has_meta("win") else null
	main.set("роль_игрока", "человек")
	main.call("_интерфейс_по_роли")
	var hot_expected: Dictionary = _native_captions(main)
	await _settle(tree, 0.60)
	_check("hot_role_keeps_existing_proxy", is_instance_valid(original_proxy) and (mod.get("_proxies") as Dictionary).get("mining") == original_proxy)
	if _hud_ready(mod):
		var new_window: Control = original_proxy.get_meta("win") as Control if original_proxy.has_meta("win") else null
		_check("hot_role_updates_native_window_target", new_window == main.get("окно_дел") and (new_window != prior_window if old_role == "страна" else true))
		_check_role_presentations("hot_person", mod, main, hot_expected)
		await _check_proxy("hot_person", "mining", "окно_дел", mod, main, tree, false)
		await _check_window_rebinding(mod, tree)
	await _detach(mod, tree)
	main.set("роль_игрока", old_role)
	_restore_native(main, native)
	var created_affairs: Control = main.get("окно_дел") as Control
	if old_affairs_window == null and is_instance_valid(created_affairs):
		created_affairs.hide()
		created_affairs.queue_free()
		main.set("окно_дел", null)
	for key: String in old_window:
		tree.root.set(key, old_window[key])
	mod.set("_prefs", old_preferences)
	mod.set("_unloaded", old_unloaded)
	mod.set_process(old_processing)
	_check("native_button_text_and_targets_restored", _matches_native(native))
	if old_attached and not old_unloaded:
		mod.call("_world_ready", game)
	await _settle(tree, 0.35)
	_check("player_role_restored", str(main.get("роль_игрока")) == old_role)
	_check("main_affairs_data_unchanged", JSON.stringify(main.get("дела")) == affairs_serialized)
	_check("profile_file_unchanged", (FileAccess.get_file_as_string(PROFILE) if FileAccess.file_exists(PROFILE) else "") == profile_before)
	_report["scope"] = "Existing isolated world; UI role selection and native windows only. One fictional workshop rendered directly in Affairs, without modifying Main affairs, issuing orders or saving a profile."
	return _finish()


func _check_role_presentations(role: String, mod: Node, main: Node, expected: Dictionary) -> void:
	var proxies: Dictionary = mod.get("_proxies")
	var native: Dictionary = mod.get("_native")
	var state: Button = main.get("кнопка_державы") as Button
	var icons: Dictionary = mod.get("_icons")
	var organization: bool = role == "организация"
	_check(role + "_header_keeps_role_caption", state.text == str(expected["state"]))
	_check(role + "_header_uses_role_icon", state.icon != null and state.icon == icons.get("organization" if organization else "person"))
	_check(role + "_native_mining_identity", native.get("mining") == main.get("кнопка_добычи"))
	_check(role + "_native_mining_targets_affairs", (main.get("кнопка_добычи") as Button).get_meta("win") == main.get("окно_дел"))
	for id: String in ["laws", "mining"]:
		var proxy: Button = proxies.get(id) as Button
		var caption: Label = proxy.get("caption") as Label
		var icon: TextureRect = proxy.get("content_icon") as TextureRect
		_check(role + "_" + id + "_caption_matches_native", caption.text == str(expected[id]))
		_check(role + "_" + id + "_semantic_icon_exists", is_instance_valid(icon) and icon.texture != null)
		var icon_key: String = "business" if id == "mining" else ("charter" if organization else "principles")
		_check(role + "_" + id + "_semantic_icon_matches_role", is_instance_valid(icon) and icon.texture == icons.get(icon_key))
	var labels: Array = [str(expected["state"]), str(expected["laws"]), str(expected["mining"])]
	if (Pax.game as PaxGame).language() == "ru":
		_check(role + "_native_role_labels_are_expected", labels == (["Организация", "Устав", "Дела"] if role == "организация" else ["Досье", "Принципы", "Дела"]))
	(_report["roles"] as Dictionary)[role] = {"captions": labels, "native_mining_win": str((main.get("кнопка_добычи") as Button).get_meta("win"))}


func _check_proxy(role: String, id: String, property: String, mod: Node, main: Node, tree: SceneTree, populate: bool) -> void:
	_hide_windows(main)
	var target: Control = main.get(property) as Control
	var proxy: Button = (mod.get("_proxies") as Dictionary).get(id) as Button
	var native: Button = (mod.get("_native") as Dictionary).get(id) as Button
	_check(role + "_" + id + "_proxy_links_native_window", is_instance_valid(target) and is_instance_valid(proxy) and proxy.has_meta("win") and proxy.get_meta("win") == target)
	if not is_instance_valid(target) or not is_instance_valid(proxy):
		return
	var calls: Array[int] = [0]
	var observer: Callable = func() -> void: calls[0] += 1
	native.pressed.connect(observer)
	proxy.pressed.emit()
	await _settle(tree, 0.35)
	_check(role + "_" + id + "_proxy_executes_native_handler", calls[0] == 1 and target.is_visible_in_tree())
	_check(role + "_" + id + "_selected_follows_open_window", _selected(mod, proxy) > 0.95)
	var motion: Node = mod.get("_motion") as Node
	_check(role + "_" + id + "_native_window_has_motion", (motion.get("_records") as Dictionary).has(target.get_instance_id()))
	if populate:
		var affairs_script: Script = load("res://scripts/Дела.gd") as Script
		var input: Dictionary = {"вид": "бизнес", "название": "Мастерская", "работников": 12}
		var fixture: Dictionary = affairs_script.call("новое", 1, input, Pax.game.day())
		(_report["fixtures"] as Dictionary)[role] = {"input": input.duplicate(true), "factory_result": fixture.duplicate(true)}
		target.call("показать", [fixture], {})
		await _settle(tree, 0.30)
		_check(role + "_affairs_fixture_has_visible_content", _visible_text(target).contains("Мастерская"))
		(_report["fixtures"] as Dictionary)[role]["shown_text"] = _visible_text(target)
		_write_json("role-" + role + "-affairs-fixture.json", (_report["fixtures"] as Dictionary)[role])
	if role != "hot_person":
		var preferences: Dictionary = (mod.get("_prefs") as Dictionary).duplicate(true)
		_window(tree.root, Vector2i(1422, 800))
		await _settle(tree, 0.65)
		_check_bounds(role + "_" + id + "_1422", mod, tree)
		(_report["roles"] as Dictionary)[role][id + "_window_rect"] = str(_rect(target))
		await _screenshot(tree, "role-" + role + "-" + id + "-1422.png")
		await _check_open_window(role + "_" + id + "_1422", target, mod, tree)
		var compact: Dictionary = preferences.duplicate(true)
		compact.merge({"scale": 1.25, "font_size": 16}, true)
		mod.call("preview_settings", compact)
		_window(tree.root, Vector2i(1280, 720))
		await _settle(tree, 0.65)
		_check_bounds(role + "_" + id + "_1280_scale125", mod, tree)
		await _screenshot(tree, "role-" + role + "-" + id + "-1280-scale125.png")
		await _check_open_window(role + "_" + id + "_1280_scale125", target, mod, tree)
		mod.call("preview_settings", preferences)
		await _settle(tree, 0.40)
	proxy.pressed.emit()
	await _settle(tree, 0.30)
	_check(role + "_" + id + "_proxy_closes_native_window", calls[0] == 2 and not target.visible)
	_check(role + "_" + id + "_selected_clears_after_close", _selected(mod, proxy) < 0.05)
	if native.pressed.is_connected(observer):
		native.pressed.disconnect(observer)
	_window(tree.root, Vector2i(1920, 1080))
	await _settle(tree, 0.45)


func _check_customization(role: String, mod: Node, expected: Dictionary, tree: SceneTree) -> void:
	mod.call("open_settings")
	await _settle(tree, 0.30)
	var panel: Control = mod.get("_panel") as Control
	var commands: Array = panel.get("_commands")
	var grid: GridContainer = panel.get("_order_box") as GridContainer
	var proxies: Dictionary = mod.get("_proxies")
	for id: String in ["laws", "mining"]:
		var row: Control = grid.get_node_or_null("Order_" + id) as Control
		var title_ok: bool = is_instance_valid(row) and str(row.get("command_title")) == str(expected[id])
		var proxy_icon: TextureRect = (proxies[id] as Button).get("content_icon") as TextureRect
		var spec_ok: bool = false
		for command: Dictionary in commands:
			if str(command.get("id", "")) == id:
				spec_ok = str(command.get("title", "")) == str(expected[id]) and command.get("icon") == proxy_icon.texture
		var displayed_icon_ok: bool = false
		if is_instance_valid(row):
			for candidate: Node in row.find_children("*", "TextureRect", true, false):
				displayed_icon_ok = displayed_icon_ok or (candidate as TextureRect).texture == proxy_icon.texture
		_check(role + "_customization_" + id + "_role_title", title_ok)
		_check(role + "_customization_" + id + "_role_icon", spec_ok and displayed_icon_ok)
	await _screenshot(tree, "role-" + role + "-customization1920.png")
	mod.call("cancel_settings")
	await _settle(tree, 0.25)


func _check_open_window(label: String, window: Control, mod: Node, tree: SceneTree) -> void:
	var viewport: Rect2 = tree.root.get_visible_rect()
	var header: Control = mod.get("_header") as Control
	var tools: Control = mod.get("_tools_panel") as Control
	var bounds: Rect2 = _rect(window)
	_check(label + "_opened_window_inside_viewport", window.is_visible_in_tree() and viewport.grow(2.0).encloses(bounds))
	_check(label + "_opened_window_below_header_above_tools", bounds.position.y >= _rect(header).end.y - 1.0 and bounds.end.y <= _rect(tools).position.y + 1.0)
	var details: Dictionary = {"window": _control_details(window), "viewport": str(viewport), "header": str(_rect(header)), "tools": str(_rect(tools)), "parents": [], "tree": _control_tree(window), "actions": []}
	var parent: Node = window.get_parent()
	while parent is Control:
		(details["parents"] as Array).append(_control_details(parent as Control))
		parent = parent.get_parent()
	var actions: Array[Control] = []
	_collect_actions(window, actions)
	_check(label + "_native_actions_present", actions.size() >= 2)
	var saved_scrolls: Dictionary = {}
	var all_actions_reachable: bool = true
	for action: Control in actions:
		# Scroll to controls without invoking their commands. A clipped body is
		# allowed, but every native action must be reachable inside the panel.
		var ancestor: Node = action.get_parent()
		while ancestor != null and ancestor != window:
			if ancestor is ScrollContainer:
				var scroll: ScrollContainer = ancestor as ScrollContainer
				if not saved_scrolls.has(scroll):
					saved_scrolls[scroll] = Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical)
				scroll.ensure_control_visible(action)
				await tree.process_frame
			ancestor = ancestor.get_parent()
		var effective: Rect2 = viewport.intersection(_rect(window))
		ancestor = action.get_parent()
		while ancestor is Control:
			if (ancestor as Control).clip_contents:
				effective = effective.intersection(_rect(ancestor as Control))
			ancestor = ancestor.get_parent()
		var reachable: bool = action.is_visible_in_tree() and effective.grow(2.0).encloses(_rect(action))
		all_actions_reachable = all_actions_reachable and reachable
		var record: Dictionary = _control_details(action)
		record["effective_clip"] = str(effective)
		record["reachable"] = reachable
		(details["actions"] as Array).append(record)
	_check(label + "_native_actions_fit_or_can_scroll_into_view", all_actions_reachable)
	for scroll: ScrollContainer in saved_scrolls:
		var position: Vector2i = saved_scrolls[scroll]
		scroll.scroll_horizontal = position.x
		scroll.scroll_vertical = position.y
	var filename: String = "role-" + label + "-window-details.json"
	(_report["window_details"] as Dictionary)[label] = {"file": filename, "window": details["window"], "actions": details["actions"]}
	_write_json(filename, details)
	await _settle(tree, 0.08)


func _control_details(control: Control) -> Dictionary:
	var result: Dictionary = {"path": str(control.get_path()), "class": control.get_class(), "rect": str(_rect(control)), "local_position": str(control.position), "size": str(control.size), "minimum": str(control.get_minimum_size()), "combined_minimum": str(control.get_combined_minimum_size()), "custom_minimum": str(control.custom_minimum_size), "scale": str(control.scale), "flags_horizontal": control.size_flags_horizontal, "flags_vertical": control.size_flags_vertical, "visible": control.visible, "in_tree": control.is_visible_in_tree(), "clip_contents": control.clip_contents, "mouse_filter": control.mouse_filter, "focus_mode": control.focus_mode, "has_focus": control.has_focus()}
	if control is Button or control is Label or control is RichTextLabel or control is LineEdit or control is TextEdit:
		result["text"] = str(control.get("text"))
	if control is BaseButton:
		result["disabled"] = (control as BaseButton).disabled
		result["pressed_connections"] = (control as BaseButton).get_signal_connection_list("pressed").size()
	if control is ScrollContainer:
		var scroll: ScrollContainer = control as ScrollContainer
		result["scroll"] = {"x": scroll.scroll_horizontal, "y": scroll.scroll_vertical, "horizontal_mode": scroll.horizontal_scroll_mode, "vertical_mode": scroll.vertical_scroll_mode}
	return result


func _control_tree(node: Node) -> Array:
	var result: Array = []
	if node is Control:
		result.append(_control_details(node as Control))
	for child: Node in node.get_children():
		result.append_array(_control_tree(child))
	return result


func _collect_actions(node: Node, result: Array[Control]) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is BaseButton or node is LineEdit or node is TextEdit:
		result.append(node as Control)
	for child: Node in node.get_children():
		_collect_actions(child, result)


func _write_json(filename: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(filename), FileAccess.WRITE)
	_check("diagnostic_" + filename, file != null)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _check_window_rebinding(mod: Node, tree: SceneTree) -> void:
	var skin: Node = mod.get("_skin") as Node
	var holder: Control = Control.new()
	holder.name = "RoleBindingFixture"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(mod.get("_root") as Control).add_child(holder)
	var first: Panel = Panel.new()
	var second: Panel = Panel.new()
	first.hide()
	second.hide()
	holder.add_child(first)
	holder.add_child(second)
	var proxy: Button = Button.new()
	proxy.text = "QA"
	proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hidden: Button = Button.new()
	hidden.hide()
	holder.add_child(proxy)
	holder.add_child(hidden)
	await _settle(tree, 0.20)
	var baseline: int = (skin.get("_window_bindings") as Dictionary).size()
	var peak: int = baseline
	var bounded: bool = true
	var hidden_rebound: bool = true
	var proxy_rebound: bool = true
	for iteration: int in range(20):
		for window: Control in [first, second, null]:
			for button: Button in [proxy, hidden]:
				if window == null:
					button.remove_meta("win")
				else:
					button.set_meta("win", window)
			await _settle(tree, 0.12)
			var binding_count: int = (skin.get("_window_bindings") as Dictionary).size()
			peak = maxi(peak, binding_count)
			bounded = bounded and binding_count == baseline + (1 if window != null else 0)
			var records: Dictionary = skin.get("_buttons")
			var proxy_record: Dictionary = records.get(proxy.get_instance_id(), {})
			var hidden_record: Dictionary = records.get(hidden.get_instance_id(), {})
			var expected_id: int = window.get_instance_id() if window != null else 0
			proxy_rebound = proxy_rebound and int(proxy_record.get("linked_id", -1)) == expected_id
			hidden_rebound = hidden_rebound and int(hidden_record.get("linked_id", -1)) == expected_id
	_check("window_rebinding_20_cycles_stays_bounded", bounded)
	_check("window_rebinding_visible_proxy_tracks_a_b_null", proxy_rebound)
	_check("window_rebinding_hidden_button_tracks_a_b_null", hidden_rebound)
	proxy.set_meta("win", second)
	hidden.set_meta("win", second)
	await _settle(tree, 0.12)
	second.queue_free()
	await _settle(tree, 0.20)
	_check("window_rebinding_freed_target_releases_binding", (skin.get("_window_bindings") as Dictionary).size() == baseline)
	proxy.remove_meta("win")
	hidden.remove_meta("win")
	await _settle(tree, 0.15)
	var final_records: Dictionary = skin.get("_buttons")
	_check("window_rebinding_freed_target_to_null_clears_ids", int((final_records.get(proxy.get_instance_id(), {}) as Dictionary).get("linked_id", -1)) == 0 and int((final_records.get(hidden.get_instance_id(), {}) as Dictionary).get("linked_id", -1)) == 0)
	_report["window_rebinding"] = {"cycles": 20, "baseline": baseline, "peak": peak, "final": (skin.get("_window_bindings") as Dictionary).size()}
	holder.queue_free()
	await _settle(tree, 0.20)
	_check("window_rebinding_fixture_cleanup", (skin.get("_window_bindings") as Dictionary).size() == baseline)


func _snapshot_native(main: Node) -> Dictionary:
	var result: Dictionary = {"buttons": [], "windows": {}, "group": main.get("_группа_сейчас"), "list_open": main.get("список_открыт")}
	var seen: Dictionary = {}
	for property: Dictionary in main.get_property_list():
		var key: String = str(property["name"])
		var value: Variant = main.get(key)
		if value is Control and (key.begins_with("окно_") or key == "список_обёртка"):
			(result["windows"] as Dictionary)[value] = (value as Control).visible
		if not value is Button or seen.has(value):
			continue
		seen[value] = true
		var button: Button = value as Button
		(result["buttons"] as Array).append({"node": button, "text": button.text, "icon": button.icon, "tooltip_text": button.tooltip_text, "visible": button.visible, "disabled": button.disabled, "meta": button.get_meta("win") if button.has_meta("win") else null, "has_meta": button.has_meta("win"), "pressed": button.get_signal_connection_list("pressed")})
	return result


func _restore_native(main: Node, snapshot: Dictionary) -> void:
	_hide_windows(main)
	for record: Dictionary in snapshot["buttons"]:
		var button: Button = record["node"] as Button
		if not is_instance_valid(button):
			continue
		for connection: Dictionary in button.get_signal_connection_list("pressed"):
			button.pressed.disconnect(connection["callable"])
		for connection: Dictionary in record["pressed"]:
			var callback: Callable = connection["callable"]
			if callback.is_valid():
				button.pressed.connect(callback, int(connection["flags"]))
		for key: String in ["text", "icon", "tooltip_text", "visible", "disabled"]:
			button.set(key, record[key])
		if bool(record["has_meta"]):
			button.set_meta("win", record["meta"])
		elif button.has_meta("win"):
			button.remove_meta("win")
	for window: Control in snapshot["windows"]:
		if is_instance_valid(window):
			window.visible = bool(snapshot["windows"][window])
	main.set("_группа_сейчас", snapshot["group"])
	main.set("список_открыт", snapshot["list_open"])
	main.call("_обновить_вкладки_группы")
	main.call("_подсветить_низ")


func _matches_native(snapshot: Dictionary) -> bool:
	for record: Dictionary in snapshot["buttons"]:
		var button: Button = record["node"] as Button
		if not is_instance_valid(button) or button.text != str(record["text"]) or button.has_meta("win") != bool(record["has_meta"]):
			return false
		if bool(record["has_meta"]) and button.get_meta("win") != record["meta"]:
			return false
	return true


func _native_captions(main: Node) -> Dictionary:
	var result: Dictionary = {}
	var expression: RegEx = RegEx.new()
	expression.compile("\\p{L}.*")
	for id: String in {"state": "кнопка_державы", "laws": "кнопка_законов", "mining": "кнопка_добычи"}:
		var key: String = {"state": "кнопка_державы", "laws": "кнопка_законов", "mining": "кнопка_добычи"}[id]
		var found: RegExMatch = expression.search((main.get(key) as Button).text)
		result[id] = found.get_string().strip_edges() if found != null else ""
	return result


func _hud_ready(mod: Node) -> bool:
	return is_instance_valid(mod.get("_root")) and is_instance_valid(mod.get("_panel")) and (mod.get("_proxies") as Dictionary).size() == IDS.size()


func _selected(mod: Node, button: Button) -> float:
	var skin: Node = mod.get("_skin") as Node
	var records: Dictionary = skin.get("_buttons")
	var record: Dictionary = records.get(button.get_instance_id(), {})
	return (record.get("blend", Vector3.ZERO) as Vector3).z


func _hide_windows(main: Node) -> void:
	for property: Dictionary in main.get_property_list():
		var key: String = str(property["name"])
		if key.begins_with("окно_") or key == "список_обёртка":
			var value: Variant = main.get(key)
			if value is Control:
				(value as Control).hide()


func _check_bounds(label: String, mod: Node, tree: SceneTree) -> void:
	var header: Control = mod.get("_header") as Control
	var dock: Control = mod.get("_dock_panel") as Control
	var viewport: Rect2 = tree.root.get_visible_rect().grow(2.0)
	_check(label + "_header_in_view", viewport.encloses(_rect(header)))
	_check(label + "_dock_in_view", viewport.encloses(_rect(dock)))
	var buttons_inside: bool = true
	var captions_fit: bool = true
	for node: Node in header.find_children("*", "BaseButton", true, false):
		var button: BaseButton = node as BaseButton
		if button.is_visible_in_tree():
			buttons_inside = buttons_inside and viewport.encloses(_rect(button)) and _rect(header).grow(1.0).encloses(_rect(button))
			if button is Button and not (button as Button).text.is_empty():
				var caption_button: Button = button as Button
				var required: float = caption_button.get_theme_font("font").get_string_size(caption_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_button.get_theme_font_size("font_size")).x + caption_button.get_theme_stylebox("normal").get_minimum_size().x
				if caption_button.icon != null:
					var icon_limit: int = caption_button.get_theme_constant("icon_max_width")
					required += float(icon_limit if icon_limit > 0 else caption_button.icon.get_width()) + caption_button.get_theme_constant("h_separation")
				captions_fit = captions_fit and caption_button.size.x + 1.0 >= required
	_check(label + "_header_buttons_in_view", buttons_inside)
	_check(label + "_visible_header_captions_fit", captions_fit)
	var commands_inside: bool = true
	for button: Button in (mod.get("_proxies") as Dictionary).values():
		if button.is_visible_in_tree():
			commands_inside = commands_inside and viewport.encloses(_rect(button)) and _rect(button).grow(1.0).encloses(_rect(button.get("content") as Control))
	_check(label + "_command_contents_in_view", commands_inside)


func _visible_text(node: Node) -> String:
	var result: String = ""
	if node is Control and not (node as Control).is_visible_in_tree():
		return result
	if node is Label or node is RichTextLabel or node is Button:
		result += str(node.get("text")) + "\n"
	for child: Node in node.get_children():
		result += _visible_text(child)
	return result


func _detach(mod: Node, tree: SceneTree) -> void:
	var adapter: Node = mod.get("_role_windows") as Node
	var originals: Array[Dictionary] = []
	if is_instance_valid(adapter):
		for record: Dictionary in (adapter.get("_records") as Dictionary).values():
			originals.append({"node": record.node, "minimum": record.minimum})
			for item: Dictionary in record.scrolls:
				originals.append(item.duplicate())
	mod.set("_unloaded", true)
	mod.call("_detach")
	await tree.process_frame
	await tree.process_frame
	if not originals.is_empty():
		var restored: bool = true
		for record: Dictionary in originals:
			var control: Control = (record.node as WeakRef).get_ref() as Control
			if is_instance_valid(control):
				restored = restored and control.custom_minimum_size == record.minimum
				if record.has("flags"):
					restored = restored and control.size_flags_vertical == int(record.flags)
		_detach_sequence += 1
		_check("role_window_original_layout_restored_" + str(_detach_sequence), restored)


func _window(root: Window, dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _settle(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds).timeout
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _screenshot(tree: SceneTree, filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var error: Error = tree.root.get_texture().get_image().save_png(_output.path_join(filename))
	_check("screenshot_" + filename, error == OK)
	if error == OK:
		(_report["screenshots"] as Array).append(filename)


func _check(name: String, passed: bool) -> void:
	(_report["checks"] as Dictionary)[name] = passed
	if not passed:
		(_report["failures"] as Array).append(name)
		print("INTERFACE_ROLE_ASSERT_FAILED ", name)


func _finish() -> Dictionary:
	_report["ok"] = (_report["failures"] as Array).is_empty()
	_report["assertion_count"] = (_report["checks"] as Dictionary).size()
	return _report
