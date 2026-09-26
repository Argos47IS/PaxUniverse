extends PaxMod
## UI adapter for Main 0.15.1. Native callbacks and game windows remain authoritative.

const IDS: Array[String] = ["orders", "plans", "laws", "objects", "mining", "research"]
const WINDOW_PROPERTIES: Array[String] = ["окно_приказов", "окно_проектов", "окно_законов", "окно_спецпроектов", "окно_добычи", "окно_науки"]
const BUTTON_PROPERTIES: Array[String] = ["кнопка_приказов", "кнопка_проектов", "кнопка_законов", "", "кнопка_добычи", ""]
const DEFAULTS: Dictionary = {"theme": "graphite", "accent": "#279cab", "opacity": 0.96, "scale": 1.0, "font_size": 14, "labels": true, "motion": true, "sound_enabled": true, "volume": 0.35, "order": ["orders", "plans", "laws", "objects", "mining", "research"]}

var _prefs: Dictionary = {}
var _opening: Dictionary = {}
var _game: PaxGame
var _has_player_role: bool = false
var _root: Control
var _panel: PanelContainer
var _dock: HBoxContainer
var _tools: HBoxContainer
var _dock_panel: PanelContainer
var _settings_button: Button
var _pause_button: Button
var _skin: Node
var _audio: Node
var _motion: Node
var _native_bar: Control
var _native_buttons: HBoxContainer
var _proxies: Dictionary = {}
var _native: Dictionary = {}
var _extras: Dictionary = {}
var _icons: Dictionary = {}
var _moved: Array[Dictionary] = []
var _properties: Array[Dictionary] = []
var _owned: Array[Node] = []
var _unloaded: bool = false
var _editing: bool = false
var _timer: float = 0.0
var _last_size: Vector2 = Vector2.ZERO
var _header: PanelContainer
var _top_nav: HBoxContainer
var _top_info: HBoxContainer
var _stars: Control
var _title: Label
var _order_tween: Tween
var _native_overrides: Array[Dictionary] = []
var _done_button: Button
var _hud_layer: CanvasLayer
var _metrics: HBoxContainer
var _brand: Label
var _date_label: Label
var _date_context: Label
var _date_box: VBoxContainer
var _nav_group: HBoxContainer
var _time_group: HBoxContainer
var _header_labels: Dictionary = {}
var _header_sources: Dictionary = {}
var _commands_signature: String = ""
var _observe_button: Button
var _dock_row: HBoxContainer
var _dock_aux: HBoxContainer
var _tools_panel: PanelContainer
var _context_tabs: Control
var _native_window_frame: MarginContainer
var _region: Node
var _role_windows: Node
var _zoom_in: Button
var _zoom_out: Button
var _layout_signature: String = ""
var _layout_passes: int = 0
var _layout_calls: int = 0
var _discovery_clock: float = 0.0
var _compact_header: bool = false
var _map: CanvasLayer
var _borders: CheckButton
var _layers_button: Button

func _mod_loaded() -> void:
	_unloaded = false
	_prefs = _sanitize(get_setting("appearance", DEFAULTS))
	var icon_script: Script = load_resource("icons.gd") as Script
	for key: String in IDS + ["settings", "atlas", "pause", "assistant", "relations", "state", "generic", "clock", "observe", "layers", "mail", "diplomacy", "person", "organization", "business", "principles", "charter", "development", "resources", "goals", "history", "market"]:
		_icons[key] = icon_script.make(key)
	_skin = (load_resource("skin.gd") as Script).new()
	_audio = (load_resource("ui_audio.gd") as Script).new()
	_motion = (load_resource("window_motion.gd") as Script).new()
	_region = (load_resource("region_card.gd") as Script).new()
	_role_windows = (load_resource("role_windows.gd") as Script).new()
	add_child(_skin)
	add_child(_audio)
	add_child(_motion)
	add_child(_region)
	add_child(_role_windows)
	_audio.call("setup", self)
	_skin.connect("hovered", _audio.hover)
	_skin.connect("activated", _audio.click)
	_configure()
	set_process(true)
	if not get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.connect(_node_added)
	call_deferred("_catch_up")

func _sanitize(input: Variant) -> Dictionary:
	var data: Dictionary = input if input is Dictionary else {}
	var result: Dictionary = DEFAULTS.duplicate(true)
	if str(data.get("theme", "")) in ["graphite", "midnight", "slate"]:
		result.theme = str(data.theme)
	var accent: String = str(data.get("accent", DEFAULTS.accent))
	if Color.html_is_valid(accent):
		result.accent = "#" + Color.html(accent).to_html(false)
	for key: String in ["opacity", "scale", "volume"]:
		if data.get(key) is float or data.get(key) is int:
			var value: float = float(data[key])
			if is_finite(value):
				result[key] = clampf(value, 0.5 if key == "opacity" else (0.8 if key == "scale" else 0.0), 1.25 if key == "scale" else 1.0)
	var requested_font: Variant = data.get("font_size", 14)
	if (requested_font is int or requested_font is float) and is_finite(float(requested_font)) and int(requested_font) in [12, 14, 16]:
		result.font_size = int(requested_font)
	for key: String in ["labels", "motion", "sound_enabled"]:
		if data.get(key) is bool:
			result[key] = data[key]
	var order: Array = []
	if data.get("order") is Array:
		for key: Variant in data.order:
			if key is String and key in IDS and not order.has(key):
				order.append(key)
	for key: String in IDS:
		if not order.has(key):
			order.append(key)
	result.order = order
	return result

func _configure() -> void:
	for component: Node in [_skin, _audio, _motion, _region]:
		if is_instance_valid(component):
			component.call("configure", _prefs)
	_layout_signature = ""
	_layout_passes = 3
	_layout()
	_sync_buttons()
	_apply_order()

func _catch_up() -> void:
	if _unloaded:
		return
	var game: PaxGame = Pax.game
	if not is_instance_valid(game) or not is_instance_valid(game.main) or not game.main.is_node_ready():
		return
	if _has(game.main, "_игра_готова") and not bool(game.main.get("_игра_готова")):
		return
	if game != _game or not is_instance_valid(_root):
		_world_ready(game)

func _has(object: Object, key: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == key:
			return true
	return false

func _world_ready(game: PaxGame) -> void:
	if _unloaded:
		return
	if game == _game and is_instance_valid(_root):
		return
	_detach()
	var main: Node = game.main
	for key: String in ["низ_панель", "низ_кнопки", "верх_панель"]:
		if not _has(main, key) or not is_instance_valid(main.get(key)):
			log_error(tr_key("pax_interface_adapter_error") + " " + key)
			return
	_game = game
	_has_player_role = _has(main, "роль_игрока")
	_native_bar = main.get("низ_панель") as Control
	_native_buttons = main.get("низ_кнопки") as HBoxContainer
	for index: int in range(IDS.size()):
		# Role changes reuse these buttons but replace their target window.
		var property: String = BUTTON_PROPERTIES[index]
		var named: Button = main.get(property) as Button if not property.is_empty() and _has(main, property) else null
		if is_instance_valid(named) and named.get_parent() == _native_buttons:
			_native[IDS[index]] = named
			continue
		var window: Control = main.get(WINDOW_PROPERTIES[index]) as Control if _has(main, WINDOW_PROPERTIES[index]) else null
		if not is_instance_valid(window):
			continue
		for child: Node in _native_buttons.get_children():
			if child is Button and child.get_meta("win", null) == window:
				_native[IDS[index]] = child
				break
	if _native.size() != IDS.size():
		log_error(tr_key("pax_interface_adapter_error"))
		_game = null
		_has_player_role = false
		_native.clear()
		return
	var layer: CanvasLayer = game.hud_layer()
	_hud_layer = layer
	_root = Control.new()
	_root.name = "PaxInterfaceHUD"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_root)
	for child: Node in layer.get_children():
		if child is Control and child != _root and not child.is_queued_for_deletion():
			_move(child as Control, _root)
	_save_property(_native_bar, "visible")
	_native_bar.hide()
	_build_header(main)
	_build_dock()
	if _has(main, "низ_столб"):
		_native_window_frame = (main.get("низ_столб") as Control).get_parent() as MarginContainer
		if is_instance_valid(_native_window_frame):
			_native_overrides.append({"node": _native_window_frame, "kind": "constant", "key": "margin_bottom", "present": _native_window_frame.has_theme_constant_override("margin_bottom"), "value": _native_window_frame.get_theme_constant("margin_bottom")})
	if _has(main, "вкладки_группы"):
		_context_tabs = main.get("вкладки_группы") as Control
		_move(_context_tabs, _root)
		_tag(_context_tabs, "chrome")
	_region.call("setup", self, game, _root)
	_role_windows.call("setup", self, main)
	_panel = (load_resource("settings_panel.gd") as Script).new()
	_root.add_child(_panel)
	_panel.hide()
	_panel.set_meta("pax_interface_role", "card")
	_panel.call("setup", self, _prefs, _commands())
	_panel.connect("preview_changed", preview_settings)
	_panel.connect("apply_requested", apply_settings)
	_panel.connect("cancel_requested", cancel_settings)
	_panel.connect("reset_requested", reset_settings)
	_panel.connect("edit_mode_changed", _set_edit_mode)
	_panel.connect("sound_preview_requested", _audio.preview)
	_panel.visibility_changed.connect(_panel_visibility)
	var windows: Array = main.get("окна_модов")
	windows.append(_panel)
	_settings_button.set_meta("win", _panel)
	for id_key: String in IDS:
		_proxies[id_key].owner_token = _panel.get_instance_id()
	_skin.call("watch_tree", main)
	for property: Dictionary in main.get_property_list():
		if str(property.name).begins_with("окно_"):
			var value: Variant = main.get(property.name)
			if value is Control:
				_motion.call("watch", value)
	_motion.call("watch", _panel)
	_discover_extras()
	_connect_map_tools()
	_configure()
	log_info("Pax Interface attached to native HUD.")

func _save_property(node: Object, key: String) -> void:
	for record: Dictionary in _properties:
		if record.node == node and record.key == key:
			return
	_properties.append({"node": node, "key": key, "value": node.get(key)})

func _update_saved_property(node: Object, key: String, value: Variant) -> void:
	for record: Dictionary in _properties:
		if record.node == node and record.key == key:
			record.value = value
			return

func _move(node: Control, parent: Node) -> void:
	var record: Dictionary = {"node": node, "parent": node.get_parent(), "index": node.get_index(), "layout": {}}
	for key: String in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "size_flags_horizontal", "size_flags_vertical", "custom_minimum_size"]:
		record.layout[key] = node.get(key)
	_moved.append(record)
	node.reparent(parent, false)

func _tag(control: Control, role: String) -> void:
	_native_overrides.append({"node": control, "kind": "meta", "key": "pax_interface_role", "present": control.has_meta("pax_interface_role"), "value": control.get_meta("pax_interface_role", "")})
	control.set_meta("pax_interface_role", role)

func _separator(parent: BoxContainer) -> void:
	var line: VSeparator = VSeparator.new()
	line.custom_minimum_size.x = 8
	parent.add_child(line)

func _native_header_button(main: Node, key: String, icon_key: String, parent: Node) -> Button:
	var button: Button = main.get(key) as Button
	_move(button, parent)
	for property: String in ["icon", "expand_icon", "text", "tooltip_text", "focus_mode", "alignment"]:
		_save_property(button, property)
	_header_sources[button] = {"property": key, "icon_key": icon_key, "text": button.text, "icon": button.icon, "tooltip_text": button.tooltip_text, "rendered_text": button.text, "rendered_icon": button.icon, "rendered_tooltip_text": button.tooltip_text}
	_header_labels[button] = _clean_text(button.text)
	_native_overrides.append({"node": button, "kind": "constant", "key": "icon_max_width", "present": button.has_theme_constant_override("icon_max_width"), "value": button.get_theme_constant("icon_max_width")})
	_native_overrides.append({"node": button, "kind": "font", "key": "font_size", "present": button.has_theme_font_size_override("font_size"), "value": button.get_theme_font_size("font_size")})
	_native_overrides.append({"node": button, "kind": "meta", "key": "pax_interface_selected", "present": button.has_meta("pax_interface_selected"), "value": button.get_meta("pax_interface_selected", false)})
	_tag(button, "nav")
	button.focus_mode = Control.FOCUS_ALL
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 17)
	button.custom_minimum_size = Vector2(70, 30)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_render_header_button(button)
	return button

func _build_header(main: Node) -> void:
	_header = main.get("верх_панель") as PanelContainer
	_move(_header, _root)
	_save_property(_header, "clip_contents")
	_tag(_header, "header")
	var old_row: HBoxContainer = _header.get_child(0) as HBoxContainer
	if old_row == null:
		return
	_save_property(old_row, "visible")
	old_row.hide()
	_top_nav = HBoxContainer.new()
	_top_nav.name = "IntegratedHeader"
	_top_nav.add_theme_constant_override("separation", 8)
	_header.add_child(_top_nav)
	_owned.append(_top_nav)
	_brand = Label.new()
	_brand.text = tr_key("pax_interface_brand")
	_brand.add_theme_font_size_override("font_size", 12)
	_brand.add_theme_color_override("font_color", Color("aebdce"))
	_brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_nav.add_child(_brand)
	_separator(_top_nav)
	_nav_group = HBoxContainer.new()
	_nav_group.add_theme_constant_override("separation", 6)
	_top_nav.add_child(_nav_group)
	_native_header_button(main, "кнопка_помощника", "assistant", _nav_group)
	_native_header_button(main, "кнопка_связей", "relations", _nav_group)
	_native_header_button(main, "кнопка_державы", "state", _nav_group)
	_stars = main.get("звёзды_ряд") as Control
	_metrics = (load_resource("header_metrics.gd") as Script).new()
	_metrics.name = "SocietyRatings"
	_metrics.call("setup", _stars)
	_top_nav.add_child(_metrics)
	_separator(_top_nav)
	_title = main.get("заголовок") as Label
	_date_box = VBoxContainer.new()
	_date_box.name = "DateContext"
	_date_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_date_box.add_theme_constant_override("separation", 1)
	_top_nav.add_child(_date_box)
	_date_label = Label.new()
	_date_label.name = "GameDate"
	_date_label.add_theme_font_size_override("font_size", 14)
	_date_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_date_label.clip_text = true
	_date_box.add_child(_date_label)
	_date_context = Label.new()
	_date_context.name = "PlanetSeason"
	_date_context.add_theme_font_size_override("font_size", 10)
	_date_context.add_theme_color_override("font_color", Color("9eadbf"))
	_date_context.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_date_context.clip_text = true
	_date_box.add_child(_date_context)
	_separator(_top_nav)
	_time_group = HBoxContainer.new()
	_time_group.name = "TimeControls"
	_time_group.add_theme_constant_override("separation", 5)
	_top_nav.add_child(_time_group)
	_native_header_button(main, "кнопка_перемотки", "clock", _time_group)
	_observe_button = Button.new()
	_observe_button.name = "Observe"
	_observe_button.text = tr_key("pax_interface_observe")
	_observe_button.tooltip_text = _observe_button.text
	_observe_button.icon = _icons.observe
	_observe_button.expand_icon = true
	_observe_button.add_theme_font_size_override("font_size", 11)
	_observe_button.add_theme_constant_override("icon_max_width", 17)
	_observe_button.custom_minimum_size = Vector2(87, 30)
	_observe_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_observe_button.set_meta("pax_interface_role", "nav")
	_observe_button.pressed.connect(func() -> void: _game.set_speed(0 if bool(main.get("автоигра")) else 1))
	_time_group.add_child(_observe_button)
	for speed: Variant in main.get("кнопки_скорости"):
		if speed is Control:
			_move(speed, _time_group)
			_tag(speed, "nav")
			speed.custom_minimum_size = Vector2(28, 30)
			speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var next: Control = main.get("кнопка_до_события") as Control
	if next != null:
		_move(next, _time_group)
		_tag(next, "nav")
		next.custom_minimum_size = Vector2(24, 30)
		next.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _build_dock() -> void:
	_dock_panel = PanelContainer.new()
	_dock_panel.name = "PaxCommandDock"
	_dock_panel.set_meta("pax_interface_role", "dock")
	_root.add_child(_dock_panel)
	_dock_row = HBoxContainer.new()
	_dock_row.add_theme_constant_override("separation", 9)
	var dock_inset: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		dock_inset.add_theme_constant_override("margin_" + side, 12)
	for side: String in ["top", "bottom"]:
		dock_inset.add_theme_constant_override("margin_" + side, 6)
	_dock_panel.add_child(dock_inset)
	dock_inset.add_child(_dock_row)
	_dock = HBoxContainer.new()
	_dock.name = "Commands"
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.add_theme_constant_override("separation", 0)
	_dock_row.add_child(_dock)
	for key: String in IDS:
		var button: Button = (load_resource("dock_button.gd") as Script).new()
		button.name = "Command_" + key
		button.set("command_id", key)
		button.set_meta("pax_interface_role", "command")
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(56, 38)
		button.clip_text = true
		button.set_meta("win", (_native[key] as Button).get_meta("win"))
		button.call("build_content", _icons[key])
		button.pressed.connect(_activate.bind(key))
		button.connect("move_requested", _move_command)
		_dock.add_child(button)
		_proxies[key] = button
	_separator(_dock_row)
	_dock_aux = HBoxContainer.new()
	_dock_aux.name = "MapNavigation"
	_dock_aux.add_theme_constant_override("separation", 7)
	_dock_row.add_child(_dock_aux)
	var map_button: Button = _native_header_button(_game.main, "кнопка_карты", "atlas", _dock_aux)
	map_button.custom_minimum_size = Vector2(112, 36)
	for step: int in [-1, 1]:
		var zoom: Button = Button.new()
		zoom.name = "ZoomIn" if step > 0 else "ZoomOut"
		zoom.text = "+" if step > 0 else "−"
		zoom.tooltip_text = tr_key("pax_interface_zoom_in" if step > 0 else "pax_interface_zoom_out")
		zoom.custom_minimum_size = Vector2(34, 36)
		zoom.add_theme_font_size_override("font_size", 22)
		zoom.set_meta("pax_interface_role", "tool")
		zoom.pressed.connect(_zoom_map.bind(step))
		_dock_aux.add_child(zoom)
		if step > 0:
			_zoom_in = zoom
		else:
			_zoom_out = zoom
	_tools_panel = PanelContainer.new()
	_tools_panel.name = "MapToolsFrame"
	_tools_panel.set_meta("pax_interface_role", "chrome")
	_root.add_child(_tools_panel)
	_tools = HBoxContainer.new()
	_tools.name = "PaxMapTools"
	_tools.add_theme_constant_override("separation", 0)
	_tools_panel.add_child(_tools)
	_settings_button = Button.new()
	_settings_button.name = "InterfaceSettingsButton"
	_settings_button.text = tr_key("pax_interface_settings_button")
	_settings_button.icon = _icons.settings
	_settings_button.expand_icon = true
	_settings_button.add_theme_constant_override("icon_max_width", 17)
	_settings_button.add_theme_font_size_override("font_size", 12)
	_settings_button.custom_minimum_size = Vector2(106, 31)
	_settings_button.set_meta("pax_interface_role", "tool")
	_settings_button.pressed.connect(open_settings)
	_tools.add_child(_settings_button)
	_pause_button = (_game.main.get("кнопки_скорости") as Array)[0] as Button
	_done_button = Button.new()
	_done_button.name = "FinishReordering"
	_done_button.text = tr_key("pax_interface_edit_done")
	_done_button.tooltip_text = tr_key("pax_interface_edit_done_hint")
	_done_button.custom_minimum_size = Vector2(72, 31)
	_done_button.set_meta("pax_interface_primary", true)
	_done_button.set_meta("pax_interface_role", "tool")
	_done_button.hide()
	_done_button.pressed.connect(func() -> void: _panel.call("set_edit_mode", false))
	_tools.add_child(_done_button)

func _zoom_map(direction: int) -> void:
	if is_instance_valid(_map) and _map.visible and _map.has_method("навести_на"):
		_map.call("навести_на", _map.get("центр"), float(_map.get("зум")) * (1.18 if direction > 0 else 1.0 / 1.18))

func _commands() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in IDS:
		var native: Button = _native.get(key) as Button
		var content: Dictionary = _command_content(native, key)
		result.append({"id": key, "title": content.title, "icon": _command_icon(key, native), "visible": native.visible if is_instance_valid(native) else true})
	return result

func _command_content(native: Button, key: String) -> Dictionary:
	var title: String = _clean_text(native.text) if is_instance_valid(native) else tr_key("pax_interface_command_" + key)
	var full: String = title
	var count: String = ""
	if title.ends_with("•"):
		count = "•"
		title = title.trim_suffix("•").strip_edges()
	elif title.ends_with(")"):
		var open_at: int = title.rfind("(")
		if open_at >= 0:
			var candidate: String = title.substr(open_at + 1, title.length() - open_at - 2).strip_edges()
			# Only a trailing numeric badge belongs outside the native caption.
			if candidate.is_valid_int():
				count = candidate
				title = title.substr(0, open_at).strip_edges()
	return {"title": title, "count": count, "full": full}

func _role() -> String:
	if _has_player_role and is_instance_valid(_game) and is_instance_valid(_game.main):
		return str(_game.main.get("роль_игрока"))
	return "страна"

func _semantic_icon(key: String) -> Texture2D:
	var role: String = _role()
	var icon_key: String = key
	if key == "state":
		icon_key = "person" if role == "человек" else ("organization" if role == "организация" else key)
	elif key == "laws":
		icon_key = "principles" if role == "человек" else ("charter" if role == "организация" else key)
	elif key == "mining" and role in ["человек", "организация"]:
		icon_key = "business"
	return _icons.get(icon_key) as Texture2D

func _command_icon(key: String, native: Button) -> Texture2D:
	if is_instance_valid(native) and native.icon != null:
		return native.icon
	return _semantic_icon(key)

func _sync_commands() -> void:
	if not is_instance_valid(_panel):
		return
	var commands: Array[Dictionary] = _commands()
	var parts: Array = []
	for command: Dictionary in commands:
		var icon: Texture2D = command.icon as Texture2D
		parts.append([command.id, command.title, command.visible, icon.get_instance_id() if icon != null else 0])
	var signature: String = JSON.stringify(parts)
	if signature != _commands_signature:
		_commands_signature = signature
		_panel.call("set_commands", commands)
		_layout_signature = ""

func _sync_window_binding(native: Button, proxy: Button) -> void:
	var candidate: Variant = native.get_meta("win", null)
	var window: Control = candidate as Control if candidate is Control and is_instance_valid(candidate) else null
	var previous: Variant = proxy.get_meta("win", null)
	if window == null:
		if not proxy.has_meta("win"):
			return
		proxy.remove_meta("win")
	elif previous == window:
		return
	else:
		proxy.set_meta("win", window)
		_motion.call("watch", window)
	_skin.call("refresh", proxy)

func _capture_header_sources() -> void:
	# Our compact captions differ from native text. Track the last rendered
	# values so role/language updates remain authoritative, including on detach.
	for button: Button in _header_sources:
		if not is_instance_valid(button):
			continue
		var source: Dictionary = _header_sources[button]
		for property: String in ["text", "icon", "tooltip_text"]:
			var value: Variant = button.get(property)
			if value != source["rendered_" + property]:
				source[property] = value
				source["rendered_" + property] = value
				_update_saved_property(button, property, value)
				_layout_signature = ""
		_header_labels[button] = _clean_text(str(source.text))

func _render_header_button(button: Button) -> void:
	var source: Dictionary = _header_sources[button]
	var compact: bool = _compact_header and button.get_parent() != _dock_aux
	button.text = "" if compact else str(_header_labels[button])
	button.tooltip_text = str(_header_labels[button])
	button.icon = source.icon as Texture2D if source.icon is Texture2D else _semantic_icon(str(source.icon_key))
	source.rendered_text = button.text
	source.rendered_tooltip_text = button.tooltip_text
	source.rendered_icon = button.icon

func _clean_text(text: String) -> String:
	var start: int = 0
	while start < text.length():
		var code: int = text.unicode_at(start)
		if (code >= 48 and code <= 122) or (code >= 0x400 and code <= 0x52f):
			break
		start += 1
	return text.substr(start).strip_edges()

func _activate(key: String) -> void:
	if _editing:
		return
	var button: Button = _native.get(key) as Button
	if is_instance_valid(button) and not button.disabled:
		if is_instance_valid(_panel) and _panel.visible:
			cancel_settings()
		button.pressed.emit()

func _discover_extras() -> void:
	if not is_instance_valid(_native_buttons):
		return
	for child: Node in _native_buttons.get_children():
		if not child is Button or child in _native.values() or _extras.has(child.get_instance_id()):
			continue
		var native: Button = child as Button
		var proxy: Button = Button.new()
		proxy.expand_icon = true
		proxy.add_theme_constant_override("icon_max_width", 20)
		proxy.custom_minimum_size = Vector2(96, 31)
		proxy.set_meta("pax_interface_role", "tool")
		proxy.add_theme_font_size_override("font_size", 12)
		proxy.icon = _icons.atlas if native.text.contains("HD") else _icons.generic
		proxy.pressed.connect(func() -> void:
			if is_instance_valid(native) and not native.disabled:
				if _panel.visible:
					cancel_settings()
				if native.toggle_mode:
					native.button_pressed = not native.button_pressed
				native.pressed.emit())
		_tools.add_child(proxy)
		_tools.move_child(proxy, 0)
		_extras[native.get_instance_id()] = {"native": native, "proxy": proxy}
		var window: Variant = native.get_meta("win", null)
		if window is Control:
			proxy.set_meta("win", window)
			_motion.call("watch", window)

func _sync_buttons() -> void:
	if not is_instance_valid(_dock):
		return
	for key: String in IDS:
		var native: Button = _native.get(key) as Button
		var proxy: Button = _proxies.get(key) as Button
		if not is_instance_valid(native) or not is_instance_valid(proxy):
			continue
		proxy.disabled = native.disabled and not _editing
		proxy.visible = native.visible
		var content: Dictionary = _command_content(native, key)
		proxy.tooltip_text = str(content.full)
		proxy.call("set_content", str(content.title), str(content.count), bool(_prefs.labels), _editing)
		proxy.call("set_content_icon", _command_icon(key, native))
		_sync_window_binding(native, proxy)
		proxy.set("editing", _editing)
		proxy.mouse_default_cursor_shape = Control.CURSOR_MOVE if _editing else Control.CURSOR_POINTING_HAND
	for record: Dictionary in _extras.values():
		var native: Button = record.native as Button
		var proxy: Button = record.proxy as Button
		if is_instance_valid(native) and is_instance_valid(proxy):
			proxy.visible = native.visible
			proxy.disabled = native.disabled
			proxy.text = _clean_text(native.text)
			_sync_window_binding(native, proxy)
			proxy.toggle_mode = native.toggle_mode
			if native.toggle_mode:
				proxy.set_pressed_no_signal(native.button_pressed)
		elif is_instance_valid(proxy):
			proxy.hide()
	if is_instance_valid(_game) and _game.main.has_method("_окна_группы"):
		for pair: Array in [["кнопка_связей", "связи"], ["кнопка_державы", "держава"]]:
			var selected: bool = false
			var windows: Array = _game.main.call("_окна_группы", pair[1])
			for entry: Variant in windows:
				var window: Control = entry.get("окно") as Control if entry is Dictionary else entry as Control
				if is_instance_valid(window):
					selected = selected or window.visible
			(_game.main.get(pair[0]) as Button).set_meta("pax_interface_selected", selected)
	_sync_commands()
	_sync_header()
	_sync_context_tabs()
	if is_instance_valid(_map):
		if is_instance_valid(_zoom_in):
			_zoom_in.disabled = not _map.visible
			_zoom_out.disabled = not _map.visible
		if is_instance_valid(_borders):
			_borders.visible = _map.visible and bool(_map.get("с_провинциями"))
		if is_instance_valid(_layers_button):
			_layers_button.visible = _map.visible

func _sync_context_tabs() -> void:
	if not is_instance_valid(_context_tabs) or not _context_tabs.visible or not is_instance_valid(_game):
		return
	var main: Node = _game.main
	var row: HBoxContainer = main.get("вкладки_ряд") as HBoxContainer
	var windows: Array = main.call("_окна_группы", str(main.get("_группа_сейчас")))
	var index: int = 0
	var pruned: bool = false
	for child: Node in row.get_children():
		if not child is Button or child.is_queued_for_deletion():
			continue
		var button: Button = child as Button
		if index >= windows.size():
			break
		var entry: Dictionary = windows[index]
		index += 1
		if button.has_meta("pax_interface_tab"):
			continue
		if not pruned:
			# Main rebuilds these buttons on every tab switch. Only live nodes
			# need restoration; discard snapshots of earlier generations.
			for records: Array in [_properties, _native_overrides]:
				for saved_index: int in range(records.size() - 1, -1, -1):
					if not is_instance_valid(records[saved_index]["node"]):
						records.remove_at(saved_index)
			pruned = true
		var window: Control = entry.get("окно") as Control
		for property: String in ["text", "icon", "expand_icon", "focus_mode", "custom_minimum_size"]:
			_save_property(button, property)
		for key: String in ["win", "pax_interface_tab"]:
			_native_overrides.append({"node": button, "kind": "meta", "key": key, "present": button.has_meta(key), "value": button.get_meta(key) if button.has_meta(key) else null})
		_native_overrides.append({"node": button, "kind": "constant", "key": "icon_max_width", "present": button.has_theme_constant_override("icon_max_width"), "value": button.get_theme_constant("icon_max_width")})
		button.set_meta("pax_interface_tab", true)
		button.set_meta("win", window)
		_tag(button, "nav")
		button.text = _clean_text(button.text)
		button.icon = _icons.generic
		var tab_icons: Dictionary = {"окно_контактов": "relations", "окно_входящих": "mail", "окно_дипломатии": "diplomacy", "окно_развития": "development", "окно_ресурсов": "resources", "окно_профиля": "person", "список_обёртка": "goals", "окно_хроники": "history", "окно_мира": "market"}
		for property: String in tab_icons:
			if _has(main, property) and main.get(property) == window:
				button.icon = _icons[tab_icons[property]]
				break
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
		button.custom_minimum_size = Vector2(106, 32)
		button.focus_mode = Control.FOCUS_ALL
		_skin.call("refresh", button)

func _connect_map_tools() -> void:
	if not is_instance_valid(_game) or not _has(_game.main, "полит_карта"):
		return
	var map: CanvasLayer = _game.main.get("полит_карта") as CanvasLayer
	if not is_instance_valid(map) or map == _map:
		return
	if is_instance_valid(_map) and _map.is_connected("выбрана_провинция", _map_selection_changed):
		_map.disconnect("выбрана_провинция", _map_selection_changed)
	_map = map
	if map.has_signal("выбрана_провинция") and not map.is_connected("выбрана_провинция", _map_selection_changed):
		map.connect("выбрана_провинция", _map_selection_changed)
	if _has(map, "кнопка_границ"):
		_borders = map.get("кнопка_границ") as CheckButton
		if is_instance_valid(_borders):
			_move(_borders, _tools)
			_save_property(_borders, "focus_mode")
			_borders.focus_mode = Control.FOCUS_ALL
			_borders.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			_borders.custom_minimum_size = Vector2(128, 31)
			_tag(_borders, "tool")
			_tools.move_child(_borders, 0)
	if map.has_method("переключить_окно_слоёв"):
		_layers_button = Button.new()
		_layers_button.name = "MapLayers"
		_layers_button.text = tr_key("pax_interface_layers")
		_layers_button.icon = _icons.layers
		_layers_button.expand_icon = true
		_layers_button.add_theme_constant_override("icon_max_width", 18)
		_layers_button.custom_minimum_size = Vector2(84, 31)
		_layers_button.set_meta("pax_interface_role", "tool")
		_layers_button.add_theme_font_size_override("font_size", 12)
		_layers_button.pressed.connect(func() -> void: map.call("переключить_окно_слоёв"))
		_tools.add_child(_layers_button)
		_tools.move_child(_layers_button, 1)
		_layers_button.set_meta("win", map.get("окно_слоёв"))
	for key: String in ["окно_слоёв", "карточка", "панель", "карточка_отряда"]:
		if _has(map, key) and map.get(key) is Control:
			_motion.call("watch", map.get(key))

func _map_selection_changed(province_id: int) -> void:
	if province_id > 0 and is_instance_valid(_panel) and _panel.visible:
		cancel_settings()

func _apply_order() -> void:
	if not is_instance_valid(_dock):
		return
	var before: Dictionary = {}
	for child: Control in _dock.get_children():
		before[child] = child.position
	for index: int in range(_prefs.order.size()):
		var button: Button = _proxies.get(_prefs.order[index]) as Button
		if is_instance_valid(button):
			_dock.move_child(button, index)
	if bool(_prefs.motion) and _editing:
		call_deferred("_animate_order", before)

func _animate_order(before: Dictionary) -> void:
	if not is_instance_valid(_dock):
		return
	if _order_tween != null:
		_order_tween.kill()
	_order_tween = create_tween().set_parallel(true)
	for child: Control in _dock.get_children():
		var target: Vector2 = child.position
		child.position = before.get(child, target)
		_order_tween.tween_property(child, "position", target, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _move_command(source: String, target: String) -> void:
	if _editing and is_instance_valid(_panel):
		_panel.call("request_order_move", source, target)

func _set_edit_mode(enabled: bool) -> void:
	_editing = enabled
	if is_instance_valid(_done_button):
		_done_button.visible = enabled
	_sync_buttons()

func open_settings() -> void:
	if not is_instance_valid(_panel):
		return
	if _panel.visible:
		cancel_settings()
		return
	if is_instance_valid(_map) and _map.visible:
		_map.call("выбрать", 0)
	_opening = _prefs.duplicate(true)
	_panel.call("begin", _prefs)
	_game.main.call("_переключить_окно", _panel)
	_layout()

func preview_settings(settings: Dictionary) -> void:
	_prefs = _sanitize(settings)
	_configure()

func apply_settings(settings: Dictionary) -> void:
	preview_settings(settings)
	set_setting("appearance", _prefs.duplicate(true))
	_opening.clear()
	_set_edit_mode(false)
	_panel.hide()

func cancel_settings() -> void:
	if not _opening.is_empty():
		_prefs = _opening.duplicate(true)
	_opening.clear()
	_set_edit_mode(false)
	_configure()
	if is_instance_valid(_panel):
		_panel.hide()

func reset_settings() -> void:
	preview_settings(DEFAULTS)
	_panel.call("begin", _prefs)

func _panel_visibility() -> void:
	# Native hotkeys or group buttons can close our registered window too.
	if is_instance_valid(_panel) and not _panel.visible and not _opening.is_empty():
		cancel_settings()

func _sync_header() -> void:
	if not is_instance_valid(_metrics) or not is_instance_valid(_game):
		return
	_capture_header_sources()
	for button: Button in _header_sources:
		if is_instance_valid(button):
			_render_header_button(button)
	_metrics.call("sync")
	if is_instance_valid(_title):
		var parts: PackedStringArray = _title.text.split("·")
		var date_text: String = parts[0].strip_edges() if not parts.is_empty() else _game.date_text()
		var date: Dictionary = _game.date()
		if date_text.contains(".") and int(date.get("month", 0)) in range(1, 13):
			date_text = tr_key("pax_interface_date_format") % [int(date.day), tr_key("pax_interface_month_" + str(int(date.month))), int(date.year)]
		_date_label.text = date_text
		_date_context.text = (parts[2].strip_edges() + " · " + parts[1].strip_edges()) if parts.size() >= 3 else _game.focused_body()
		_date_box.tooltip_text = _title.text
	_observe_button.set_meta("pax_interface_selected", bool(_game.main.get("автоигра")))

func _caption_width(button: Button, caption: String, font_size: int, icon_width: float, minimum: float) -> float:
	var font: Font = button.get_theme_font("font")
	var width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var margins: float = 0.0
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		margins = maxf(margins, button.get_theme_stylebox(state).get_minimum_size().x)
	if button.icon != null:
		width += icon_width + float(button.get_theme_constant("h_separation"))
	return maxf(minimum, ceilf(width + margins + 2.0))

func _header_group_width(group: HBoxContainer, wide: bool, font_ratio: float) -> float:
	var width: float = 0.0
	var count: int = 0
	var speeds: Array = _game.main.get("кнопки_скорости")
	for child: Node in group.get_children():
		if not child is Control or not (child as Control).visible:
			continue
		var control: Control = child as Control
		var child_width: float = control.get_combined_minimum_size().x
		if child is Button and _header_labels.has(child):
			var minimum: float = (156.0 if wide else 140.0) if group == _time_group else (92.0 if wide else 76.0)
			child_width = _caption_width(child as Button, str(_header_labels[child]), roundi((13.0 if wide else 12.0) * font_ratio), 20.0 if wide else 17.0, minimum)
		elif child == _observe_button:
			child_width = _caption_width(_observe_button, tr_key("pax_interface_observe"), roundi((13.0 if wide else 11.0) * font_ratio), 17.0, 104.0 if wide else 87.0)
		elif child in speeds:
			child_width = maxf(34.0 if wide else 28.0, control.get_minimum_size().x)
		width += child_width
		count += 1
	return width + float(maxi(0, count - 1) * group.get_theme_constant("separation"))

func _full_header_width(wide: bool, font_ratio: float) -> float:
	# Measure the full variant independently of current compact captions. Only
	# society metrics may consume the remaining width; the nav text never clips.
	var width: float = _header.get_theme_stylebox("panel").get_minimum_size().x
	var count: int = 0
	for child: Node in _top_nav.get_children():
		if not child is Control or not (child as Control).visible:
			continue
		var child_width: float = (child as Control).get_combined_minimum_size().x
		if child == _brand:
			child_width = maxf(132.0 if wide else 107.0, _brand.get_theme_font("font").get_string_size(tr_key("pax_interface_brand"), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi((15.0 if wide else 12.0) * font_ratio)).x)
		elif child == _nav_group or child == _time_group:
			child_width = _header_group_width(child as HBoxContainer, wide, font_ratio)
		elif child == _date_box:
			child_width = 172.0 if wide else 154.0
		width += child_width
		count += 1
	return width + float(maxi(0, count - 1) * _top_nav.get_theme_constant("separation"))

func _layout() -> void:
	if not is_instance_valid(_root):
		return
	_capture_header_sources()
	var viewport_size: Vector2 = _root.get_viewport_rect().size
	var ui_scale: float = float(_prefs.scale)
	var logical: Vector2 = viewport_size / ui_scale
	var dock_height: float = maxf(56.0, _dock_panel.get_combined_minimum_size().y) if is_instance_valid(_dock_panel) else 56.0
	var signature: String = str(logical) + ":" + str(_prefs.font_size) + ":" + str(_prefs.labels) + ":" + str(dock_height)
	if signature != _layout_signature:
		# Containers propagate their new minimum sizes after this frame. Resize
		# again after that settles, including wide-to-narrow viewport changes.
		_layout_passes = maxi(_layout_passes, 3)
	if signature == _layout_signature and _layout_passes <= 0:
		return
	_layout_signature = signature
	_layout_passes = maxi(0, _layout_passes - 1)
	_layout_calls += 1
	_root.scale = Vector2.ONE * ui_scale
	_root.size = logical
	_last_size = viewport_size
	var wide: bool = logical.x >= 1600.0
	var font_ratio: float = float(_prefs.font_size) / 14.0
	var header_height: float = 52.0 if wide else 48.0
	if is_instance_valid(_header):
		_metrics.call("configure_layout", wide, font_ratio)
		_compact_header = _full_header_width(wide, font_ratio) > logical.x - 2.0
		_header.position = Vector2.ZERO
		_header.custom_minimum_size = Vector2(0, header_height)
		_header.size = Vector2(logical.x, header_height)
		_header.clip_contents = false
		_brand.text = tr_key("pax_interface_brand_short") if _compact_header else tr_key("pax_interface_brand")
		_brand.custom_minimum_size.x = 32 if _compact_header else (132 if wide else 107)
		_brand.add_theme_font_size_override("font_size", roundi((15.0 if wide else 12.0) * font_ratio))
		_date_box.custom_minimum_size.x = 133 if _compact_header else (172 if wide else 154)
		_date_label.add_theme_font_size_override("font_size", roundi((16.0 if wide else 14.0) * font_ratio))
		_date_context.add_theme_font_size_override("font_size", roundi((12.0 if wide else 10.0) * font_ratio))
		for button: Button in _header_labels:
			if not is_instance_valid(button) or button.get_parent() == _dock_aux:
				continue
			_render_header_button(button)
			var caption_font: int = roundi((13.0 if wide else 12.0) * font_ratio)
			var minimum: float = (156.0 if wide else 140.0) if button.get_parent() == _time_group else (92.0 if wide else 76.0)
			var caption_width: float = _caption_width(button, str(_header_labels[button]), caption_font, 20.0 if wide else 17.0, minimum)
			button.custom_minimum_size = Vector2(28.0 if _compact_header else caption_width, 36 if wide else 30)
			button.add_theme_font_size_override("font_size", caption_font)
			button.add_theme_constant_override("icon_max_width", 20 if wide else 17)
		_observe_button.text = "" if _compact_header else tr_key("pax_interface_observe")
		var observe_width: float = _caption_width(_observe_button, tr_key("pax_interface_observe"), roundi((13.0 if wide else 11.0) * font_ratio), 17.0, 104.0 if wide else 87.0)
		_observe_button.custom_minimum_size = Vector2(28.0 if _compact_header else observe_width, 36 if wide else 30)
		_observe_button.add_theme_font_size_override("font_size", roundi((13.0 if wide else 11.0) * font_ratio))
		for speed: Control in _game.main.get("кнопки_скорости"):
			speed.custom_minimum_size = Vector2(34 if wide else 28, 36 if wide else 30)
	if is_instance_valid(_dock_panel):
		_dock_panel.position = Vector2(0, logical.y - dock_height)
		_dock_panel.size = Vector2(logical.x, dock_height)
	if is_instance_valid(_tools_panel):
		_tools_panel.position = Vector2(14, logical.y - dock_height - 45)
		_tools_panel.reset_size()
	if is_instance_valid(_native_window_frame):
		_native_window_frame.add_theme_constant_override("margin_bottom", roundi(dock_height + 55.0))
	if is_instance_valid(_panel):
		var width: float = 420.0 if logical.x >= 1250.0 else 390.0
		_panel.position = Vector2(logical.x - width - 14, header_height + 10)
		_panel.size = Vector2(width, minf(648.0, maxf(260.0, logical.y - 124)))
	if is_instance_valid(_context_tabs):
		_context_tabs.position = Vector2(14, header_height + 10)
		_context_tabs.reset_size()
	if is_instance_valid(_region):
		_region.call("layout", logical, header_height + 4.0, logical.y - dock_height)

func _process(delta: float) -> void:
	if _unloaded:
		return
	_timer += delta
	_discovery_clock += delta
	if _timer < 0.12:
		return
	_timer = 0.0
	if _discovery_clock >= 0.6:
		_discovery_clock = 0.0
		_catch_up()
		if is_instance_valid(_root):
			_discover_extras()
			_connect_map_tools()
	if not is_instance_valid(_root):
		return
	_layout()
	_sync_buttons()

func _node_added(node: Node) -> void:
	if _unloaded or not is_instance_valid(_root) or not node is Control:
		return
	if node.get_parent() == _hud_layer:
		call_deferred("_adopt_dynamic", weakref(node))

func _adopt_dynamic(reference: WeakRef) -> void:
	var control: Control = reference.get_ref() as Control
	if _unloaded or not is_instance_valid(_root) or not is_instance_valid(control) or control == _root or control.get_parent() != _hud_layer:
		return
	_move(control, _root)
	_skin.call("watch_tree", control)
	_motion.call("watch", control)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and is_instance_valid(_panel) and _panel.visible:
		cancel_settings()
		get_viewport().set_input_as_handled()

func _detach() -> void:
	_capture_header_sources()
	if is_instance_valid(_map) and _map.is_connected("выбрана_провинция", _map_selection_changed):
		_map.disconnect("выбрана_провинция", _map_selection_changed)
	if not _opening.is_empty():
		_prefs = _opening.duplicate(true)
	if _order_tween != null:
		_order_tween.kill()
	if is_instance_valid(_motion):
		_motion.call("restore")
	if is_instance_valid(_region):
		_region.call("restore")
	if is_instance_valid(_role_windows):
		_role_windows.call("restore")
	if is_instance_valid(_skin):
		_skin.call("restore")
	if is_instance_valid(_game) and is_instance_valid(_game.main) and is_instance_valid(_panel):
		var windows: Array = _game.main.get("окна_модов")
		windows.erase(_panel)
	for record: Dictionary in _properties:
		if is_instance_valid(record.node):
			record.node.set(record.key, record.value)
	_properties.clear()
	for record: Dictionary in _native_overrides:
		if not is_instance_valid(record.node):
			continue
		if record.kind == "constant":
			if record.present:
				record.node.add_theme_constant_override(record.key, record.value)
			else:
				record.node.remove_theme_constant_override(record.key)
		elif record.kind == "font":
			if record.present:
				record.node.add_theme_font_size_override(record.key, record.value)
			else:
				record.node.remove_theme_font_size_override(record.key)
		elif record.present:
			record.node.set_meta(record.key, record.value)
		else:
			record.node.remove_meta(record.key)
	_native_overrides.clear()
	_moved.reverse()
	for record: Dictionary in _moved:
		if is_instance_valid(record.node) and is_instance_valid(record.parent):
			var node: Control = record.node as Control
			node.reparent(record.parent, false)
			record.parent.move_child(node, mini(int(record.index), record.parent.get_child_count() - 1))
			for key: String in record.layout:
				node.set(key, record.layout[key])
	_moved.clear()
	if is_instance_valid(_map) and is_instance_valid(_borders):
		_borders.visible = bool(_map.get("с_провинциями"))
	for node: Node in _owned:
		if is_instance_valid(node):
			node.queue_free()
	_owned.clear()
	if is_instance_valid(_root):
		# F6 can build the replacement before queue_free is flushed. Detach the
		# empty old wrapper now so the new adapter cannot adopt it as native UI.
		if _root.get_parent() != null:
			_root.get_parent().remove_child(_root)
		_root.queue_free()
	_root = null
	_panel = null
	_header = null
	_native_window_frame = null
	_native.clear()
	_header_labels.clear()
	_header_sources.clear()
	_commands_signature = ""
	_layout_signature = ""
	_proxies.clear()
	_extras.clear()
	_opening.clear()
	_editing = false
	_game = null
	_has_player_role = false
	_hud_layer = null
	_map = null
	_borders = null
	_layers_button = null

func _mod_unloaded() -> void:
	_unloaded = true
	set_process(false)
	if get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	_detach()
	if is_instance_valid(_audio):
		_audio.call("stop_all")
