extends Node
## Rearranges the real map quick card; all original callbacks stay connected.

const LAYOUT_PROPERTIES: Array[String] = ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "custom_minimum_size", "size_flags_horizontal", "size_flags_vertical", "scale", "pivot_offset", "theme"]
var panel: PanelContainer
var _mod: PaxMod
var _game: PaxGame
var _root: Control
var _map: CanvasLayer
var _native_text: RichTextLabel
var _native_content: Control
var _native_content_visible: bool = true
var _panel_original: Dictionary = {}
var _moved: Array[Dictionary] = []
var _content: VBoxContainer
var _header: HBoxContainer
var _title: Label
var _owner: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _grid: VBoxContainer
var _values: Dictionary = {}
var _labels: Dictionary = {}
var _extra: RichTextLabel
var _actions: HBoxContainer
var _occupy: Button
var _close_button: Button
var _scout: Button
var _scout_icon: Texture2D
var _scout_original: Dictionary = {}
var _scout_native_text: String = ""
var _scout_display_text: String = ""
var _size: Vector2 = Vector2(1422, 800)
var _header_bottom: float = 106.0
var _dock_top: float = 732.0
var _settings: Dictionary = {}
var _elapsed: float = 0.0
var _last_text: String = ""
var _last_language: String = ""
var _applied_scale: Vector2 = Vector2.ZERO
var _active: bool = false
var _main_has_map: bool = false


func setup(mod: PaxMod, game: PaxGame, root: Control) -> void:
	restore()
	_mod = mod
	_game = game
	_root = root
	_main_has_map = is_instance_valid(game) and is_instance_valid(game.main) and _has(game.main, "полит_карта")
	_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	sync()


func configure(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	_last_language = ""
	sync()
	layout(_size, _header_bottom, _dock_top)


func layout(size: Vector2, header_bottom: float, dock_top: float) -> void:
	_size = size
	_header_bottom = header_bottom
	_dock_top = dock_top
	if not is_instance_valid(panel) or not is_instance_valid(_root) or not is_instance_valid(_content):
		return
	var width: float = minf(320.0, maxf(200.0, size.x - 32.0))
	var available: float = maxf(180.0, dock_top - header_bottom - 26.0)
	var body_height: float = maxf(0.0, _body.get_combined_minimum_size().y)
	var fixed_height: float = _header.get_combined_minimum_size().y + _actions.get_combined_minimum_size().y + 62.0
	if _owner.visible:
		fixed_height += _owner.get_combined_minimum_size().y + 4.0
	if is_instance_valid(_occupy) and _occupy.visible:
		fixed_height += _occupy.get_combined_minimum_size().y + 8.0
	_scroll.custom_minimum_size = Vector2(0.0, minf(body_height, maxf(40.0, available - fixed_height)))
	var height: float = minf(available, fixed_height + body_height)
	var local_point: Vector2 = Vector2(maxf(16.0, size.x - width - 18.0), header_bottom + 10.0)
	var viewport_point: Vector2 = _root.get_global_transform_with_canvas() * local_point
	panel.position = panel.get_canvas_transform().affine_inverse() * viewport_point
	panel.size = Vector2(width, height)
	var root_transform: Transform2D = _root.get_global_transform_with_canvas()
	var canvas_transform: Transform2D = panel.get_canvas_transform()
	var desired_scale: Vector2 = Vector2(root_transform.x.length() / maxf(canvas_transform.x.length(), 0.001), root_transform.y.length() / maxf(canvas_transform.y.length(), 0.001))
	# Do not overwrite the opening tween's scale every polling tick.
	if not desired_scale.is_equal_approx(_applied_scale):
		panel.scale = desired_scale
		_applied_scale = desired_scale


func sync() -> void:
	if not _active or not is_instance_valid(_game) or not is_instance_valid(_game.main):
		return
	var candidate: CanvasLayer = _game.main.get("полит_карта") as CanvasLayer if _main_has_map else null
	if candidate != _map or not is_instance_valid(panel):
		_detach()
		if not _attach(candidate):
			return
	_sync_scout()
	if not panel.visible or not _map.visible:
		return
	var language: String = _game.language()
	var current_text: String = _native_text.text
	if current_text != _last_text or language != _last_language:
		_last_text = current_text
		_last_language = language
		_update_content()
	layout(_size, _header_bottom, _dock_top)


func restore() -> void:
	_active = false
	set_process(false)
	_detach()
	_mod = null
	_game = null
	_root = null
	_main_has_map = false


func _attach(map: CanvasLayer) -> bool:
	if not is_instance_valid(map) or map.is_queued_for_deletion():
		return false
	for key: String in ["панель", "панель_текст", "панель_занять", "панель_разведать", "панель_подробнее", "справка", "выбрана"]:
		if not _has(map, key):
			return false
	var source: PanelContainer = map.get("панель") as PanelContainer
	var text: RichTextLabel = map.get("панель_текст") as RichTextLabel
	var occupy: Button = map.get("панель_занять") as Button
	var explore: Button = map.get("панель_разведать") as Button
	var detail: Button = map.get("панель_подробнее") as Button
	if not is_instance_valid(source) or not is_instance_valid(text) or not is_instance_valid(occupy) or not is_instance_valid(explore) or not is_instance_valid(detail):
		return false
	# This adapter intentionally accepts only the verified native card shape.
	if not is_instance_valid(text.get_parent()) or not is_instance_valid(explore.get_parent()):
		return false
	if source.get_parent() != map or text.get_parent().get_parent() != source or occupy.get_parent() != explore.get_parent() or detail.get_parent() != explore.get_parent():
		return false
	var close_candidates: Array[Button] = []
	for child: Node in explore.get_parent().get_children():
		if child is Button and child != occupy and child != explore and child != detail:
			close_candidates.append(child as Button)
	if close_candidates.size() != 1:
		return false
	_map = map
	panel = source
	_native_text = text
	_native_content = text.get_parent() as Control
	_native_content_visible = _native_content.visible
	_occupy = occupy
	_close_button = close_candidates[0]
	_scout = explore
	var had_primary: bool = explore.has_meta("pax_interface_primary")
	_scout_original = {"had_primary": had_primary, "primary": explore.get_meta("pax_interface_primary") if had_primary else false, "icon": explore.icon, "expand_icon": explore.expand_icon, "had_icon_width": explore.has_theme_constant_override("icon_max_width"), "icon_width": explore.get_theme_constant("icon_max_width")}
	_scout_native_text = explore.text
	_scout_display_text = ""
	_scout_icon = _make_scout_icon()
	explore.set_meta("pax_interface_primary", true)
	var had_role: bool = panel.has_meta("pax_interface_role")
	_panel_original = {"parent": panel.get_parent(), "index": panel.get_index(), "visible": panel.visible, "text": text.text, "had_role": had_role, "role": panel.get_meta("pax_interface_role") if had_role else ""}
	for property: String in LAYOUT_PROPERTIES:
		_panel_original[property] = panel.get(property)
	# Snapshot every sibling index before moving any of them.
	for control: Control in [text, occupy, explore, detail, _close_button]:
		var saved: Dictionary = {"node": control, "parent": control.get_parent(), "index": control.get_index(), "visible": control.visible, "tooltip_text": control.tooltip_text, "focus_mode": control.focus_mode}
		for property: String in LAYOUT_PROPERTIES:
			saved[property] = control.get(property)
		_moved.append(saved)
	panel.set_meta("pax_interface_role", "card")
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size = Vector2(320, 0)
	_content = VBoxContainer.new()
	_content.name = "InterfaceRegionCard"
	_content.add_theme_constant_override("separation", 8)
	panel.add_child(_content)
	_native_content.hide()
	_header = HBoxContainer.new()
	_header.alignment = BoxContainer.ALIGNMENT_END
	_header.add_theme_constant_override("separation", 8)
	_content.add_child(_header)
	_title = Label.new()
	_title.name = "ProvinceTitle"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 18)
	_header.add_child(_title)
	_close_button.reparent(_header, false)
	_close_button.custom_minimum_size = Vector2(28, 28)
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.focus_mode = Control.FOCUS_ALL
	_owner = Label.new()
	_owner.name = "ProvinceOwner"
	_owner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_owner)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 0)
	_body.add_child(_grid)
	for key: String in ["area", "terrain", "water"]:
		_grid.add_child(HSeparator.new())
		var row: HBoxContainer = HBoxContainer.new()
		row.custom_minimum_size.y = 30
		row.add_theme_constant_override("separation", 10)
		_grid.add_child(row)
		var caption: Label = Label.new()
		caption.custom_minimum_size.x = 108
		row.add_child(caption)
		_labels[key] = caption
		var value: Label = Label.new()
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value)
		_values[key] = value
	_grid.add_child(HSeparator.new())
	_extra = RichTextLabel.new()
	_extra.bbcode_enabled = true
	_extra.fit_content = true
	_extra.scroll_active = false
	_extra.custom_minimum_size.x = 0
	_body.add_child(_extra)
	text.reparent(_body, false)
	text.custom_minimum_size.x = 0
	text.hide()
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_content.add_child(_actions)
	for button: Button in [explore, detail]:
		button.reparent(_actions, false)
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
	# A situational native action gets its own full-width row, never disappears.
	occupy.reparent(_content, false)
	occupy.custom_minimum_size = Vector2(0, 34)
	occupy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	occupy.focus_mode = Control.FOCUS_ALL
	_sync_scout()
	panel.visibility_changed.connect(_visibility_changed)
	if map.has_signal("выбрана_провинция"):
		map.connect("выбрана_провинция", _selected)
	_last_text = ""
	_last_language = ""
	_applied_scale = Vector2.ZERO
	layout(_size, _header_bottom, _dock_top)
	return true


func _update_content() -> void:
	_close_button.tooltip_text = _tr("region_close")
	for key: String in _labels:
		(_labels[key] as Label).text = _tr("region_" + key)
	var info: Dictionary = _information()
	if not _structured(info):
		_fallback()
		return
	var area: String = str(_map.call("_тыс", float(info["площадь"])))
	var owner_color: Color = info.get("цвет_владельца", Color(0.7, 0.7, 0.7))
	var water_line: String = _game.tr_key("карта_будет_вода") if bool(info.get("будет_вода", false)) else _game.tr_key("карта_у_воды" if bool(info.get("у_воды", false)) else "карта_без_воды")
	var basic_lines: Array[String] = ["[b]%s[/b]" % str(info["имя"]), _game.tr_key("карта_площадь") % [area], "%s: [color=#%s]%s[/color]" % [_game.tr_key("карта_владелец"), owner_color.to_html(false), str(info["владелец"])], "%s: %s" % [_game.tr_key("карта_местность"), str(info["тип"])], water_line]
	var remaining: Array[String] = []
	var matched: Array[String] = []
	for line: String in _native_text.text.split("\n"):
		# Exact native strings only. Unrecognised BBCode survives unchanged.
		var plain_water: bool = line == "[color=#6fa8dc]%s[/color]" % water_line
		if basic_lines.has(line):
			matched.append(line)
		elif plain_water:
			matched.append(water_line)
		else:
			remaining.append(line)
	for line: String in basic_lines:
		if not matched.has(line):
			_fallback()
			return
	_title.text = str(info["имя"])
	_title.show()
	_owner.text = str(info["владелец"])
	_owner.tooltip_text = _game.tr_key("карта_владелец")
	_owner.show()
	(_values["area"] as Label).text = _tr("region_area_value") % [area]
	(_values["terrain"] as Label).text = str(info["тип"])
	(_values["water"] as Label).text = _tr("region_water_future" if bool(info.get("будет_вода", false)) else ("region_water_yes" if bool(info.get("у_воды", false)) else "region_water_no"))
	(_values["water"] as Label).tooltip_text = water_line
	_grid.show()
	_native_text.hide()
	_extra.text = "\n".join(PackedStringArray(remaining))
	_extra.visible = not _extra.text.is_empty()


func _structured(info: Dictionary) -> bool:
	for key: String in ["имя", "владелец", "тип"]:
		if not info.get(key) is String or str(info[key]).is_empty():
			return false
		# Names supplied by another mod may contain markup. Keep the original
		# RichTextLabel in that case instead of printing BBCode tags as plain text.
		if str(info[key]).contains("[") or str(info[key]).contains("]") or str(info[key]).contains("\n"):
			return false
	var numeric_area: bool = info.get("площадь") is float or info.get("площадь") is int
	if not numeric_area or not is_finite(float(info["площадь"])) or float(info["площадь"]) < 0.0:
		return false
	return (info.has("у_воды") or info.has("будет_вода")) and _map.has_method("_тыс") and (not info.has("цвет_владельца") or info["цвет_владельца"] is Color)


func _information() -> Dictionary:
	var provider_value: Variant = _map.get("справка")
	if not provider_value is Callable:
		return {}
	var provider: Callable = provider_value
	if not provider.is_valid() or int(_map.get("выбрана")) <= 0:
		return {}
	var value: Variant = provider.call(int(_map.get("выбрана")))
	return value if value is Dictionary else {}


func _fallback() -> void:
	_title.text = ""
	_title.hide()
	_owner.hide()
	_grid.hide()
	_extra.hide()
	_native_text.show()


func _make_scout_icon() -> Texture2D:
	# Original vector artwork in the same 24 px line style as icons.gd.
	var svg: String = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#e6edf5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M4 3l12 5-3 7L1 10zM15 10l5 2-1 3-5-2M9 14v3M9 17l-5 5M9 17l6 5M9 17v5"/></g></svg>'
	var image: Image = Image.new()
	if image.load_svg_from_string(svg, 2.0) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _sync_scout() -> void:
	if not is_instance_valid(_scout) or _scout_icon == null:
		return
	var native_text: String = _scout.text
	if native_text == _scout_display_text:
		return
	_scout_native_text = native_text
	# Only the verified decorative telescope prefix is replaced. The translated
	# native action wording and all its callbacks are retained verbatim.
	if native_text.begins_with("🔭"):
		var caption: String = native_text.trim_prefix("🔭").trim_prefix("\uFE0F").strip_edges()
		if not caption.is_empty():
			_scout_display_text = caption
			_scout.text = caption
			_scout.icon = _scout_icon
			_scout.expand_icon = true
			_scout.add_theme_constant_override("icon_max_width", 18)
			return
	_scout_display_text = native_text
	# Unknown custom captions/icons are left intact, including text from mods.
	if _scout.icon == _scout_icon:
		_restore_scout_icon()


func _restore_scout_icon() -> void:
	if not is_instance_valid(_scout) or _scout_original.is_empty():
		return
	_scout.icon = _scout_original["icon"] as Texture2D
	_scout.expand_icon = bool(_scout_original["expand_icon"])
	if bool(_scout_original["had_icon_width"]):
		_scout.add_theme_constant_override("icon_max_width", int(_scout_original["icon_width"]))
	else:
		_scout.remove_theme_constant_override("icon_max_width")


func _restore_scout() -> void:
	if not is_instance_valid(_scout) or _scout_original.is_empty():
		return
	if _scout.text == _scout_display_text:
		_scout.text = _scout_native_text
	if _scout.icon == _scout_icon:
		_restore_scout_icon()
	if bool(_scout_original["had_primary"]):
		_scout.set_meta("pax_interface_primary", _scout_original["primary"])
	else:
		_scout.remove_meta("pax_interface_primary")


func _detach() -> void:
	_restore_scout()
	if is_instance_valid(panel) and panel.visibility_changed.is_connected(_visibility_changed):
		panel.visibility_changed.disconnect(_visibility_changed)
	if is_instance_valid(_map) and _map.has_signal("выбрана_провинция") and _map.is_connected("выбрана_провинция", _selected):
		_map.disconnect("выбрана_провинция", _selected)
	for saved: Dictionary in _moved:
		if not is_instance_valid(saved.get("node")) or not is_instance_valid(saved.get("parent")):
			continue
		var node: Control = saved["node"] as Control
		var parent: Node = saved["parent"] as Node
		if not is_instance_valid(node) or not is_instance_valid(parent):
			continue
		node.reparent(parent, false)
		for property: String in LAYOUT_PROPERTIES + ["focus_mode"]:
			node.set(property, saved[property])
		if node == _close_button:
			node.tooltip_text = str(saved["tooltip_text"])
		if node == _native_text:
			node.visible = bool(saved["visible"])
	for saved: Dictionary in _moved:
		if not is_instance_valid(saved.get("node")) or not is_instance_valid(saved.get("parent")):
			continue
		var node: Control = saved["node"] as Control
		var parent: Node = saved["parent"] as Node
		if is_instance_valid(node) and is_instance_valid(parent) and node.get_parent() == parent:
			parent.move_child(node, mini(int(saved["index"]), parent.get_child_count() - 1))
	if is_instance_valid(_native_content):
		_native_content.visible = _native_content_visible
	if is_instance_valid(_content):
		_content.hide()
		_content.queue_free()
	if is_instance_valid(panel):
		for property: String in LAYOUT_PROPERTIES:
			if _panel_original.has(property):
				panel.set(property, _panel_original[property])
		if bool(_panel_original.get("had_role", false)):
			panel.set_meta("pax_interface_role", _panel_original["role"])
		else:
			panel.remove_meta("pax_interface_role")
	# Native visibility, current selected text and conditional actions stay live;
	# restoring their old selection would undo legitimate gameplay since setup.
	_moved.clear()
	_panel_original.clear()
	_values.clear()
	_labels.clear()
	panel = null
	_map = null
	_native_text = null
	_native_content = null
	_content = null
	_applied_scale = Vector2.ZERO
	_scout = null
	_scout_icon = null
	_scout_original.clear()
	_scout_native_text = ""
	_scout_display_text = ""


func _tr(suffix: String) -> String:
	return _mod.tr_key("pax_interface_" + suffix)


func _has(object: Object, key: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property["name"]) == key:
			return true
	return false


func _selected(_id: int) -> void:
	call_deferred("sync")


func _visibility_changed() -> void:
	call_deferred("sync")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.10:
		_elapsed = 0.0
		sync()


func _exit_tree() -> void:
	restore()
