extends RefCounted
## Concept layout and real native card checks inside the existing QA world.

var _report: Dictionary = {"checks": {}, "failures": [], "screenshots": []}
var _output: String = ""


func run(mod: Node, output: String) -> Dictionary:
	_report = {"checks": {}, "failures": [], "screenshots": []}
	_output = output
	var tree: SceneTree = mod.get_tree()
	var root: Window = tree.root
	var game: PaxGame = mod.get("_game") as PaxGame
	var map: CanvasLayer = mod.get("_map") as CanvasLayer
	var region: Node = mod.get("_region") as Node
	var settings: PanelContainer = mod.get("_panel") as PanelContainer
	_check("live_components_exist", is_instance_valid(game) and is_instance_valid(map) and is_instance_valid(region) and is_instance_valid(settings))
	if not is_instance_valid(game) or not is_instance_valid(map) or not is_instance_valid(region) or not is_instance_valid(settings):
		return _finish()
	_check("isolated_profile", OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"))
	if not bool((_report["checks"] as Dictionary)["isolated_profile"]):
		return _finish()
	var old_window: Dictionary = {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect, "content_scale_factor": root.content_scale_factor}
	var old_preferences: Dictionary = (mod.get("_prefs") as Dictionary).duplicate(true)
	var old_opening: Dictionary = (mod.get("_opening") as Dictionary).duplicate(true)
	var old_draft: Dictionary = (settings.get("draft") as Dictionary).duplicate(true)
	var old_settings_visible: bool = settings.visible
	var old_editing: bool = bool(mod.get("_editing"))
	var old_selection: int = int(map.get("выбрана"))
	var old_center: Vector2 = map.get("центр")
	var old_zoom: float = float(map.get("зум"))
	var old_click: Vector2 = map.get("точка_клика")
	var old_map_visible: bool = map.visible
	var details: Control = map.get("карточка") as Control
	var old_details_visible: bool = details.visible
	var profile_path: String = "user://mod_settings/pax_interface.json"
	var old_profile: String = FileAccess.get_file_as_string(profile_path) if FileAccess.file_exists(profile_path) else ""
	var baseline: Dictionary = old_preferences.duplicate(true)
	baseline.merge({"theme": "graphite", "accent": "#279cab", "opacity": 0.96, "scale": 1.0, "font_size": 14, "labels": true, "motion": true, "sound_enabled": false, "order": ["orders", "plans", "laws", "objects", "mining", "research"]}, true)
	if settings.visible:
		mod.call("cancel_settings")
	details.hide()
	mod.call("preview_settings", baseline)
	settings.call("begin", baseline)
	map.call("показать", true)
	map.call("выбрать", 0)
	_window(root, Vector2i(1920, 1080), Vector2i(1920, 1080))
	await _wait(tree, 0.65)
	_check_layout("native1920", mod, false)
	_check_metrics(mod)
	_check_badge(mod)
	var header: Control = mod.get("_header") as Control
	_check("wide_header_is_single_row_at_most_56", header.size.y <= 56.0 and (mod.get("_top_nav") as Node) is HBoxContainer and not bool(mod.get("_compact_header")))
	await _screenshot(tree, "concept-default-native1920.png")

	var selection: Dictionary = _pick_province(map)
	var selected: int = int(selection.get("id", 0))
	_check("real_province_found_from_uv", selected > 0)
	if selected > 0:
		map.set("точка_клика", selection["uv"])
		map.call("выбрать", selected)
		region.call("sync")
		await _wait(tree, 0.35)
		var card: PanelContainer = region.get("panel") as PanelContainer
		var native_card: PanelContainer = map.get("панель") as PanelContainer
		var provider: Callable = map.get("справка")
		var info: Dictionary = provider.call(selected)
		_report["province"] = {"id": selected, "uv": str(selection["uv"]), "name": str(info.get("имя", "")), "owner": str(info.get("владелец", "")), "area": info.get("площадь"), "terrain": str(info.get("тип", ""))}
		_check("card_is_genuine_native_panel", card == native_card and card.visible and card.get_parent() == map)
		var title: Label = region.get("_title") as Label
		var owner: Label = region.get("_owner") as Label
		var values: Dictionary = region.get("_values")
		_check("card_title_matches_live_province", title.visible and title.text == str(info.get("имя", "")))
		_check("card_owner_matches_live_province", owner.visible and owner.text == str(info.get("владелец", "")))
		var formatted_area: String = str(map.call("_тыс", float(info.get("площадь", 0))))
		_check("card_area_matches_native_formatter", values.has("area") and (values["area"] as Label).text == game.tr_key("pax_interface_region_area_value") % [formatted_area])
		_check("card_terrain_matches_live_province", values.has("terrain") and (values["terrain"] as Label).text == str(info.get("тип", "")))
		var bounds: Rect2 = root.get_visible_rect().grow(2.0)
		var card_rect: Rect2 = _rect(card)
		_report["card_rect"] = str(card_rect)
		_check("card_fits_below_header_and_above_dock", bounds.encloses(card_rect) and card_rect.position.y >= _rect(header).end.y and card_rect.end.y <= _rect(mod.get("_dock_panel") as Control).position.y)
		_check("card_native_actions_remain_inside", card.is_ancestor_of(map.get("панель_разведать")) and card.is_ancestor_of(map.get("панель_подробнее")) and card.is_ancestor_of(map.get("панель_занять")))
		_check("card_native_scout_callback_retained", _has_callback(map.get("панель_разведать") as Button, map))
		var scout: Button = map.get("панель_разведать") as Button
		var native_scout_caption: String = game.tr_key("карта_разведать")
		var expected_scout_caption: String = native_scout_caption.trim_prefix("🔭").trim_prefix("\uFE0F").strip_edges() if native_scout_caption.begins_with("🔭") else native_scout_caption
		_check("card_scout_is_primary_action", bool(scout.get_meta("pax_interface_primary", false)))
		_check("card_scout_preserves_native_translated_words", scout.text == expected_scout_caption)
		_check("card_scout_uses_vector_for_native_telescope", not native_scout_caption.begins_with("🔭") or (scout.icon != null and scout.icon == region.get("_scout_icon")))
		_report["scout_caption"] = {"native": native_scout_caption, "displayed": scout.text, "vector_icon": scout.icon == region.get("_scout_icon")}
		_check("card_native_claim_callback_retained", _has_callback(map.get("панель_занять") as Button, map))
		_check("card_claim_visibility_matches_native_data", (map.get("панель_занять") as Button).visible == bool(info.get("можно_занять", false)))
		await _screenshot(tree, "card-1920.png")
		(map.get("панель_подробнее") as Button).pressed.emit()
		await _wait(tree, 0.28)
		_check("card_details_uses_native_handler", details.visible and (map.get("карточка_имя") as Label).text == str(info.get("имя", "")))
		details.hide()
		(region.get("_close_button") as Button).pressed.emit()
		await _wait(tree, 0.22)
		_check("card_close_uses_native_deselection", int(map.get("выбрана")) == 0 and not card.visible)
		map.call("выбрать", selected)
		await _wait(tree, 0.23)
		mod.call("open_settings")
		await _wait(tree, 0.30)
		_check("card_to_settings_has_no_two_visible_panels", settings.visible and not card.visible)
		map.call("выбрать", selected)
		await _wait(tree, 0.30)
		_check("settings_to_card_has_no_two_visible_panels", card.visible and not settings.visible)
		if settings.visible:
			mod.call("cancel_settings")
		map.call("выбрать", 0)

	await _check_context_tabs(mod, game, tree)
	var zoom_in: Button = mod.get("_zoom_in") as Button
	var zoom_out: Button = mod.get("_zoom_out") as Button
	_check("zoom_controls_available", is_instance_valid(zoom_in) and is_instance_valid(zoom_out) and not zoom_in.disabled and not zoom_out.disabled)
	if is_instance_valid(zoom_in) and is_instance_valid(zoom_out):
		map.call("навести_на", old_center, 8.0)
		var before_zoom: float = float(map.get("зум"))
		zoom_in.pressed.emit()
		var after_plus: float = float(map.get("зум"))
		zoom_out.pressed.emit()
		var after_minus: float = float(map.get("зум"))
		_check("zoom_plus_changes_real_map_zoom", after_plus > before_zoom)
		_check("zoom_minus_returns_real_map_zoom", after_minus < after_plus and is_equal_approx(after_minus, before_zoom))
		_report["zoom_values"] = [before_zoom, after_plus, after_minus]
	map.call("навести_на", old_center, old_zoom)
	_window(root, Vector2i(1920, 1080), Vector2i(1422, 800))
	await _wait(tree, 0.60)
	_check_layout("stretch1422", mod, false)
	await _screenshot(tree, "concept-default-stretch1422.png")
	_window(root, Vector2i(1920, 1080), Vector2i(1920, 1080))
	mod.call("open_settings")
	settings.call("begin", mod.get("_prefs"))
	await _wait(tree, 0.60)
	_check_layout("settings1920", mod, true)
	await _screenshot(tree, "concept-settings1920.png")
	await _check_feedback(settings, tree)
	settings.call("set_edit_mode", true)
	await _wait(tree, 0.30)
	var grid: GridContainer = settings.get("_order_box") as GridContainer
	_check("settings_order_editor_is_six_items_two_columns", is_instance_valid(grid) and grid.columns == 2 and grid.get_child_count() == 6 and bool(mod.get("_editing")))
	await _screenshot(tree, "settings-edit-grid.png")
	settings.call("set_edit_mode", false)
	var compact: Dictionary = baseline.duplicate(true)
	compact["scale"] = 1.25
	compact["font_size"] = 16
	mod.call("preview_settings", compact)
	settings.call("begin", mod.get("_prefs"))
	_window(root, Vector2i(1280, 720), Vector2i(1280, 720))
	await _wait(tree, 0.65)
	_check_layout("compact1280_scale125", mod, true)
	await _screenshot(tree, "concept-1280-scale125.png")
	mod.call("cancel_settings")
	mod.call("preview_settings", baseline)
	settings.call("begin", baseline)
	_window(root, Vector2i(1920, 1080), Vector2i(1920, 1080))
	await _wait(tree, 0.85)
	var calls_before: int = int(mod.get("_layout_calls"))
	await _wait(tree, 0.70)
	var calls_after: int = int(mod.get("_layout_calls"))
	_check("settled_idle_does_not_repeat_layout", calls_before == calls_after)
	_report["idle_layout_calls"] = {"before": calls_before, "after": calls_after}
	await _performance(tree)

	# Restore UI preferences without persisting a profile or undoing game state.
	if settings.visible:
		mod.call("cancel_settings")
	mod.call("preview_settings", old_preferences)
	settings.call("begin", old_draft)
	mod.set("_opening", old_opening)
	settings.visible = old_settings_visible
	settings.call("set_edit_mode", old_editing)
	for property: String in old_window:
		root.set(property, old_window[property])
	map.call("навести_на", old_center, old_zoom)
	map.set("точка_клика", old_click)
	map.call("выбрать", old_selection)
	map.call("показать", old_map_visible)
	details.visible = old_details_visible
	await _wait(tree, 0.35)
	_check("profile_file_unchanged", (FileAccess.get_file_as_string(profile_path) if FileAccess.file_exists(profile_path) else "") == old_profile)
	_report["action_scope"] = "Real native Details/Close, map zoom, Contacts/Inbox/Diplomacy window tabs executed. No messages sent or gameplay orders issued; Scout/Claim retain their real native signal callbacks."
	return _finish()


func _pick_province(map: CanvasLayer) -> Dictionary:
	var provinces: Object = map.get("пров")
	if not is_instance_valid(provinces) or not provinces.has_method("id_uv"):
		return {}
	var provider: Callable = map.get("справка")
	if not provider.is_valid():
		return {}
	for uv: Vector2 in [Vector2(0.62, 0.25), Vector2(0.586, 0.21), Vector2(0.574, 0.205), Vector2(0.635, 0.188), Vector2(0.558, 0.22)]:
		var id: int = int(provinces.call("id_uv", uv.x, uv.y))
		if id <= 0:
			continue
		var info: Dictionary = provider.call(id)
		if not str(info.get("имя", "")).is_empty() and float(info.get("площадь", 0)) > 0.0:
			return {"id": id, "uv": uv}
	return {}


func _check_metrics(mod: Node) -> void:
	var metrics: Node = mod.get("_metrics") as Node
	var source: HBoxContainer = metrics.get("source") as HBoxContainer
	metrics.call("sync")
	var cells: Dictionary = metrics.get("cells")
	var count: int = 0
	var accurate: bool = true
	var observed: Array = []
	for native_cell: Node in source.get_children():
		var caption: Label = native_cell.find_child("подпись", true, false) as Label
		var stars: Label = native_cell.find_child("звёзды", true, false) as Label
		if caption == null or stars == null:
			continue
		count += 1
		var record: Dictionary = cells.get(str(native_cell.name), {})
		var rating: int = stars.text.count("★")
		accurate = accurate and not record.is_empty() and (record["title"] as Label).text == caption.text and int((record["meter"] as Node).get("filled")) == rating
		observed.append({"label": caption.text, "native": stars.text, "rating": rating})
	_check("header_has_six_native_society_metrics", count == 6 and cells.size() == 6)
	_check("header_metrics_match_native_labels_and_ratings", accurate)
	_report["metrics"] = observed


func _check_badge(mod: Node) -> void:
	var native_buttons: Dictionary = mod.get("_native")
	var proxies: Dictionary = mod.get("_proxies")
	var native: Button = native_buttons.get("plans") as Button
	var proxy: Button = proxies.get("plans") as Button
	var badge: Label = proxy.get("badge") as Label
	var expression: RegEx = RegEx.new()
	expression.compile("\\(([0-9]+)\\)")
	var found: RegExMatch = expression.search(native.text)
	var expected: String = found.get_string(1) if found != null else ("•" if native.text.strip_edges().ends_with("•") else "")
	_check("plans_badge_preserves_native_count", badge.text == expected and badge.visible == (not expected.is_empty()))
	_report["plans_badge"] = {"native_text": native.text, "badge": badge.text, "visible": badge.visible}


func _check_layout(label: String, mod: Node, settings_visible: bool) -> void:
	var root: Control = mod.get("_root") as Control
	var visible: Rect2 = root.get_viewport_rect().grow(2.0)
	var header: Control = mod.get("_header") as Control
	var dock: Control = mod.get("_dock_panel") as Control
	var settings: Control = mod.get("_panel") as Control
	_check(label + "_header_inside_viewport", visible.encloses(_rect(header)))
	var header_buttons: Array[BaseButton] = _visible_buttons(header)
	var header_buttons_inside: bool = not header_buttons.is_empty()
	var header_buttons_contained: bool = not header_buttons.is_empty()
	var header_button_rects: Array = []
	for button: BaseButton in header_buttons:
		var button_rect: Rect2 = _rect(button)
		header_buttons_inside = header_buttons_inside and visible.encloses(button_rect) and button_rect.has_area()
		header_buttons_contained = header_buttons_contained and _rect(header).grow(1.0).encloses(button_rect)
		header_button_rects.append({"path": str(button.get_path()), "caption": (button as Button).text if button is Button else "", "rect": str(button_rect)})
	_check(label + "_all_header_buttons_inside_viewport", header_buttons_inside)
	_check(label + "_all_header_buttons_inside_header", header_buttons_contained)
	_report[label + "_header_button_rects"] = header_button_rects
	_check(label + "_dock_inside_viewport", visible.encloses(_rect(dock)))
	var proxies: Dictionary = mod.get("_proxies")
	var commands_inside: bool = proxies.size() == 6
	var contents_inside: bool = true
	var content_rects: Dictionary = {}
	for button: Button in proxies.values():
		commands_inside = commands_inside and button.is_visible_in_tree() and visible.encloses(_rect(button))
		var caption: Label = button.get("caption") as Label
		var content: Control = button.get("content") as Control
		if is_instance_valid(caption) and caption.visible:
			contents_inside = contents_inside and is_instance_valid(content) and _rect(button).grow(1.0).encloses(_rect(content))
			if is_instance_valid(content):
				content_rects[str(button.get("command_id"))] = {"button": str(_rect(button)), "content": str(_rect(content))}
	_check(label + "_all_six_commands_inside_viewport", commands_inside)
	_check(label + "_dock_content_fits_each_button", contents_inside)
	_report[label + "_dock_content_rects"] = content_rects
	if settings_visible:
		_check(label + "_settings_inside_viewport", settings.visible and visible.encloses(_rect(settings)))
		var actions_inside: bool = true
		for name: String in ["CloseSettings", "ApplySettings", "CancelSettings", "ResetSettings"]:
			var action: Control = settings.find_child(name, true, false) as Control
			actions_inside = actions_inside and is_instance_valid(action) and action.is_visible_in_tree() and visible.encloses(_rect(action))
		_check(label + "_settings_actions_visible", actions_inside)
	_report[label + "_rects"] = {"viewport": str(visible), "root_scale": str(root.scale), "header": str(_rect(header)), "dock": str(_rect(dock)), "settings": str(_rect(settings)), "header_logical_height": header.size.y}


func _has_callback(button: Button, native_owner: Object) -> bool:
	for connection: Dictionary in button.get_signal_connection_list("pressed"):
		var callback: Callable = connection["callable"]
		if callback.is_valid() and callback.get_object() == native_owner:
			return true
	return false


func _visible_buttons(node: Node) -> Array[BaseButton]:
	var result: Array[BaseButton] = []
	for child: Node in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is BaseButton and (child as BaseButton).is_visible_in_tree():
			result.append(child as BaseButton)
		result.append_array(_visible_buttons(child))
	return result


func _check_context_tabs(mod: Node, game: PaxGame, tree: SceneTree) -> void:
	var main: Node = game.main
	var trigger: Button = main.get("кнопка_связей") as Button
	var tabs: Control = main.get("вкладки_группы") as Control
	var row: Control = main.get("вкладки_ряд") as Control
	var entries: Array = main.call("_окна_группы", "связи")
	_check("context_tabs_native_components_exist", is_instance_valid(trigger) and is_instance_valid(tabs) and is_instance_valid(row) and entries.size() == 3)
	if not is_instance_valid(trigger) or not is_instance_valid(tabs) or not is_instance_valid(row) or entries.size() != 3:
		return
	var old_group: String = str(main.get("_группа_сейчас"))
	var initial_properties: int = (mod.get("_properties") as Array).size()
	var initial_overrides: int = (mod.get("_native_overrides") as Array).size()
	var old_windows: Dictionary = {}
	var old_list_open: bool = bool(main.get("список_открыт"))
	for property: Dictionary in main.get_property_list():
		var name: String = str(property["name"])
		if name.begins_with("окно_") or name == "список_обёртка":
			var candidate: Variant = main.get(name)
			if candidate is Control and is_instance_valid(candidate):
				old_windows[candidate] = (candidate as Control).visible
	for window: Control in main.get("окна_модов"):
		if is_instance_valid(window):
			old_windows[window] = window.visible
	if old_group == "связи":
		trigger.pressed.emit()
	trigger.pressed.emit()
	await _wait(tree, 0.45)
	var header: Control = mod.get("_header") as Control
	_check("context_tabs_opened_by_native_header_button", tabs.is_visible_in_tree() and str(main.get("_группа_сейчас")) == "связи")
	_check("context_tabs_below_header_inside_viewport", tree.root.get_visible_rect().grow(2.0).encloses(_rect(tabs)) and _rect(tabs).position.y >= _rect(header).end.y)
	var captions: Array = []
	var expression: RegEx = RegEx.new()
	expression.compile("\\p{L}.*")
	var native_keys: Array[String] = ["контакты", "вх_кнопка", "дип_кнопка"]
	var buttons: Array[BaseButton] = _visible_buttons(row)
	var correct_text: bool = buttons.size() == 3
	var correct_callbacks: bool = buttons.size() == 3
	var correct_icons: bool = buttons.size() == 3
	for index: int in range(mini(3, buttons.size())):
		var button: Button = buttons[index] as Button
		var found: RegExMatch = expression.search(game.tr_key(native_keys[index]))
		var expected: String = found.get_string().strip_edges() if found != null else ""
		correct_text = correct_text and button != null and button.text == expected and not expected.is_empty()
		correct_callbacks = correct_callbacks and button != null and _has_callback(button, main)
		correct_icons = correct_icons and button != null and button.icon != null
		captions.append({"key": native_keys[index], "expected": expected, "actual": button.text if button != null else ""})
	_check("context_tabs_three_native_translated_captions", correct_text)
	_check("context_tabs_keep_three_native_handlers", correct_callbacks)
	_check("context_tabs_have_three_line_icons", correct_icons)
	_report["context_tabs"] = {"captions": captions, "rect": str(_rect(tabs))}
	await _screenshot(tree, "context-tabs.png")
	var skin: Node = mod.get("_skin") as Node
	for index: int in range(3):
		# Native switching rebuilds these buttons; never reuse the previous nodes.
		buttons = _visible_buttons(row)
		if buttons.size() != 3:
			_check("context_tab_" + str(index) + "_native_window_selected", false)
			continue
		buttons[index].pressed.emit()
		await _wait(tree, 0.45)
		var target: Control = (entries[index] as Dictionary)["окно"] as Control
		var exactly_target: bool = target.is_visible_in_tree()
		for other: Dictionary in entries:
			var other_window: Control = other["окно"] as Control
			exactly_target = exactly_target and other_window.visible == (other_window == target)
		_check("context_tab_" + str(index) + "_native_window_selected", exactly_target)
		_check("context_tab_" + str(index) + "_window_clears_map_tools", not _rect(target).intersects(_rect(mod.get("_tools_panel") as Control)))
		buttons = _visible_buttons(row)
		var selection_matches: bool = buttons.size() == 3
		var records: Dictionary = skin.get("_buttons")
		for tab_index: int in range(mini(3, buttons.size())):
			var button: BaseButton = buttons[tab_index]
			var linked: Control = button.get_meta("win") as Control if button.has_meta("win") else null
			var record: Dictionary = records.get(button.get_instance_id(), {})
			var blend: Vector3 = record.get("blend", Vector3.ZERO)
			selection_matches = selection_matches and linked == (entries[tab_index] as Dictionary)["окно"] and (blend.z > 0.95 if tab_index == index else blend.z < 0.05)
		_check("context_tab_" + str(index) + "_highlight_matches_window", selection_matches)
	trigger.pressed.emit()
	await _wait(tree, 0.25)
	var all_closed: bool = not tabs.visible and str(main.get("_группа_сейчас")).is_empty()
	for entry: Dictionary in entries:
		all_closed = all_closed and not (entry["окно"] as Control).visible
	_check("context_tabs_close_through_same_native_button", all_closed)
	_check("context_tab_rebuilds_keep_only_one_generation_of_snapshots", (mod.get("_properties") as Array).size() <= initial_properties + 15 and (mod.get("_native_overrides") as Array).size() <= initial_overrides + 12)
	for window: Control in old_windows:
		if is_instance_valid(window):
			window.visible = bool(old_windows[window])
	main.set("_группа_сейчас", old_group)
	main.set("список_открыт", old_list_open)
	main.call("_обновить_вкладки_группы")
	main.call("_подсветить_низ")
	await _wait(tree, 0.25)
	_check("context_tabs_previous_group_restored", str(main.get("_группа_сейчас")) == old_group)


func _check_feedback(settings: Control, tree: SceneTree) -> void:
	var disclosure: Button = settings.find_child("FeedbackDisclosure", true, false) as Button
	var scroll: ScrollContainer = settings.find_child("SettingsScroll", true, false) as ScrollContainer
	var preview: Button = settings.find_child("PreviewSound", true, false) as Button
	_check("feedback_controls_exist", is_instance_valid(disclosure) and is_instance_valid(scroll) and is_instance_valid(preview))
	if not is_instance_valid(disclosure) or not is_instance_valid(scroll) or not is_instance_valid(preview):
		return
	var old_expanded: bool = disclosure.button_pressed
	var old_scroll: int = scroll.scroll_vertical
	disclosure.button_pressed = true
	await _wait(tree, 0.25)
	scroll.scroll_vertical = 10000
	await _wait(tree, 0.25)
	_check("feedback_sound_preview_visible_inside_scroll", preview.is_visible_in_tree() and _rect(scroll).grow(1.0).encloses(_rect(preview)))
	var footer_visible: bool = true
	for name: String in ["ResetSettings", "CancelSettings", "ApplySettings"]:
		var action: Control = settings.find_child(name, true, false) as Control
		footer_visible = footer_visible and action.is_visible_in_tree() and _rect(settings).grow(1.0).encloses(_rect(action)) and tree.root.get_visible_rect().encloses(_rect(action)) and _rect(action).position.y >= _rect(scroll).end.y
	_check("feedback_footer_stays_visible_below_scroll", footer_visible)
	await _screenshot(tree, "feedback-settings.png")
	disclosure.button_pressed = old_expanded
	await _wait(tree, 0.20)
	scroll.scroll_vertical = old_scroll


func _performance(tree: SceneTree) -> void:
	var samples: Array[float] = []
	var first_frame: int = Engine.get_frames_drawn()
	var previous: int = Time.get_ticks_usec()
	for index: int in range(120):
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	samples.sort()
	_report["performance"] = {"samples": samples.size(), "mean_ms": total / float(samples.size()), "p95_ms": samples[int(ceil(0.95 * float(samples.size()))) - 1], "first_drawn_frame": first_frame, "last_drawn_frame": Engine.get_frames_drawn(), "drawn_frames": Engine.get_frames_drawn() - first_frame, "scope": "120 process-frame intervals of this QA run only. No baseline or comparative FPS claim."}
	_check("performance_sampled_120_frames", samples.size() == 120 and Engine.get_frames_drawn() > first_frame)


func _window(root: Window, pixels: Vector2i, logical: Vector2i) -> void:
	root.size = pixels
	root.content_scale_size = logical
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0


func _rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func _wait(tree: SceneTree, seconds: float) -> void:
	await tree.create_timer(seconds).timeout
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _screenshot(tree: SceneTree, filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		_check("screenshot_" + filename, false)
		return
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var error: Error = tree.root.get_texture().get_image().save_png(_output.path_join(filename))
	_check("screenshot_" + filename, error == OK)
	if error == OK:
		(_report["screenshots"] as Array).append(filename)


func _check(name: String, condition: bool) -> void:
	(_report["checks"] as Dictionary)[name] = condition
	if not condition:
		(_report["failures"] as Array).append(name)


func _finish() -> Dictionary:
	_report["ok"] = (_report["failures"] as Array).is_empty()
	_report["assertion_count"] = (_report["checks"] as Dictionary).size()
	return _report
