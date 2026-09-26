extends Node
## Reversible skin for existing controls. It changes neither layout nor callbacks.

signal hovered(button: BaseButton)
signal activated(button: BaseButton)

const ACTIVE_STYLES: Array[StringName] = [&"normal", &"hover", &"pressed", &"hover_pressed"]
const ANIMATED_TEXT_COLORS: Array[StringName] = [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]
const RELIEF_SCRIPT: Script = preload("res://mods/pax_interface/skin/finish.gd")
const PALETTES: Dictionary = {
	"graphite": [Color("0c1721"), Color("172635"), Color("384d60")],
	"midnight": [Color("0b1320"), Color("162337"), Color("344762")],
	"slate": [Color("182431"), Color("263849"), Color("50657a")],
}

var _settings: Dictionary = {}
var _roots: Array[WeakRef] = []
var _records: Dictionary = {}
var _buttons: Dictionary = {}
var _window_bindings: Dictionary = {}
var _tree: SceneTree
var _active: bool = false
var _elapsed: float = 0.0
var _background: Color = Color("0c1721")
var _surface: Color = Color("172635")
var _border: Color = Color("384d60")
var _accent: Color = Color("279cab")
var _text: Color = Color("e2ebef")
var _muted: Color = Color("a0b3be")
var _opacity: float = 0.96
var _font_ratio: float = 1.0
var _motion: bool = true


func configure(settings: Dictionary) -> void:
	var palette: Array = PALETTES.get(str(settings.get("theme", "graphite")), PALETTES["graphite"])
	var accent: Color = Color.from_string(str(settings.get("accent", "#279cab")), Color("279cab"))
	accent.a = 1.0
	var opacity: float = clampf(float(settings.get("opacity", 0.96)), 0.5, 1.0)
	var font_ratio: float = clampf(float(settings.get("font_size", 14)), 12.0, 16.0) / 14.0
	var motion: bool = bool(settings.get("motion", true))
	var colours_changed: bool = _background != palette[0] or _surface != palette[1] or _border != palette[2] or _accent != accent
	var opacity_changed: bool = not is_equal_approx(_opacity, opacity)
	var font_changed: bool = not is_equal_approx(_font_ratio, font_ratio)
	var motion_changed: bool = _motion != motion
	if not colours_changed and not opacity_changed and not font_changed and not motion_changed:
		return
	_settings = {"theme": str(settings.get("theme", "graphite")), "accent": accent, "opacity": opacity, "font_size": font_ratio * 14.0, "motion": motion}
	_background = palette[0]
	_surface = palette[1]
	_border = palette[2]
	_accent = accent
	_opacity = opacity
	_font_ratio = font_ratio
	_motion = motion
	for key: Variant in _records:
		var record: Dictionary = _records[key]
		var control: Control = _control(record)
		if not is_instance_valid(control):
			continue
		if colours_changed:
			_apply_control(control, record)
		else:
			if opacity_changed:
				_update_opacity(control, record)
			if font_changed:
				_apply_fonts(control, record)
				_update_tooltip_fonts(record)
		if motion_changed and not _motion and control is BaseButton:
			_kill_tween(record)
			_paint_button(record["target"], control.get_instance_id())


func refresh(control: Control) -> void:
	## Optional: refresh after changing pax_interface_role on an existing control.
	if not is_instance_valid(control):
		return
	var id: int = control.get_instance_id()
	if _records.has(id):
		var record: Dictionary = _records[id]
		record["role"] = _role_of(control)
		_apply_control(control, record)
	elif _active and _in_scope(control):
		_capture(control)


func watch_tree(root: Node) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	for entry: WeakRef in _roots:
		if entry.get_ref() == root:
			return
	_roots.append(weakref(root))
	_active = true
	_tree = root.get_tree()
	if not _tree.node_added.is_connected(_node_added):
		_tree.node_added.connect(_node_added)
	_visit(root)
	set_process(true)


func restore() -> void:
	_active = false
	set_process(false)
	if is_instance_valid(_tree) and _tree.node_added.is_connected(_node_added):
		_tree.node_added.disconnect(_node_added)
	for key: Variant in _records.keys():
		var record: Dictionary = _records[key]
		_kill_tween(record)
		_release_decoration(record)
		_unbind_window(record)
		var control: Control = _control(record)
		if not is_instance_valid(control):
			continue
		for hook: Array in record["hooks"]:
			var event: StringName = hook[0]
			var callback: Callable = hook[1]
			if control.is_connected(event, callback):
				control.disconnect(event, callback)
		_restore_overrides(control, record)
	_records.clear()
	_buttons.clear()
	_clear_window_bindings()
	_roots.clear()
	_tree = null


func _exit_tree() -> void:
	restore()


func _visit(node: Node) -> void:
	if node.has_meta("pax_interface_skip_skin") and bool(node.get_meta("pax_interface_skip_skin")):
		return
	if node is Control:
		_capture(node as Control)
	for child: Node in node.get_children(true):
		_visit(child)


func _node_added(node: Node) -> void:
	if _active and node is Control:
		# Let the creator finish assigning its theme overrides first.
		_capture_deferred.call_deferred(weakref(node))


func _capture_deferred(reference: WeakRef) -> void:
	if not _active:
		return
	var control: Control = reference.get_ref() as Control
	if is_instance_valid(control) and control.is_inside_tree() and _in_scope(control):
		_capture(control)


func _in_scope(node: Node) -> bool:
	var ancestor: Node = node
	while is_instance_valid(ancestor):
		if ancestor.has_meta("pax_interface_skip_skin") and bool(ancestor.get_meta("pax_interface_skip_skin")):
			return false
		ancestor = ancestor.get_parent()
	for reference: WeakRef in _roots:
		var root: Node = reference.get_ref() as Node
		if is_instance_valid(root) and (root == node or root.is_ancestor_of(node)):
			return true
	return false


func _capture(control: Control) -> void:
	var id: int = control.get_instance_id()
	if _records.has(id):
		return
	var record: Dictionary = {
		"id": id, "node": weakref(control), "styles": {}, "colors": {}, "fonts": {}, "constants": {}, "hooks": [],
		"owned_styles": {}, "relief": null, "role": _role_of(control),
		"theme": control.theme, "skin_theme": null, "blend": Vector3.ZERO,
		"self_modulate": control.self_modulate,
		"target": Vector3(-1.0, -1.0, -1.0), "hover": false,
		"focus": control.has_focus(), "down": false, "tween": null,
		"activation_armed": false, "activation_generation": 0,
		"linked_window": null, "linked_id": 0, "selected_meta": false,
		"toggle_pressed": false, "disabled": false, "text_color": null,
		"font_floor": _font_floor(control),
	}
	_records[id] = record
	_connect(control, record, &"tree_exiting", _forgotten.bind(id))
	if control is BaseButton:
		_buttons[id] = record
		_connect(control, record, &"mouse_entered", _hover_changed.bind(id, true, false))
		_connect(control, record, &"mouse_exited", _hover_changed.bind(id, false, false))
		_connect(control, record, &"focus_entered", _hover_changed.bind(id, true, true))
		_connect(control, record, &"focus_exited", _hover_changed.bind(id, false, true))
		_connect(control, record, &"button_down", _down_changed.bind(id, true))
		_connect(control, record, &"button_up", _down_changed.bind(id, false))
		_connect(control, record, &"pressed", _activated.bind(id))
		_connect(control, record, &"toggled", _toggled.bind(id))
	_apply_control(control, record)


func _connect(control: Control, record: Dictionary, event: StringName, callback: Callable) -> void:
	control.connect(event, callback)
	(record["hooks"] as Array).append([event, callback])


func _control(record: Dictionary) -> Control:
	var reference: WeakRef = record.get("node") as WeakRef
	return reference.get_ref() as Control if reference != null else null


func _role_of(control: Control) -> StringName:
	return StringName(str(control.get_meta("pax_interface_role"))) if control.has_meta("pax_interface_role") else &""


func _forgotten(id: int) -> void:
	# Disconnecting/restoring themes can emit focus/visibility signals. Remove
	# the button from routing first so cleanup cannot subscribe it again.
	_buttons.erase(id)
	if _records.has(id):
		var record: Dictionary = _records[id]
		_kill_tween(record)
		_release_decoration(record)
		_unbind_window(record)
		# Reparenting can cause tree_exiting without freeing. Restore before losing it.
		var control: Control = _control(record)
		if is_instance_valid(control):
			for hook: Array in record["hooks"]:
				if control.is_connected(hook[0], hook[1]):
					control.disconnect(hook[0], hook[1])
			_restore_overrides(control, record)
	_records.erase(id)


func _apply_control(control: Control, record: Dictionary) -> void:
	_apply_tooltip_theme(control, record)
	if control is BaseButton:
		_apply_button(control as BaseButton, record)
	elif control is PanelContainer or control is Panel:
		var panel: StyleBoxFlat = _flat(_with_alpha(_background, _opacity), _with_alpha(_border, 0.92), 5, _original_style(control, record, &"panel"))
		panel.shadow_color = Color(0.015, 0.025, 0.04, 0.40)
		panel.shadow_size = 5
		panel.shadow_offset = Vector2(0.0, 2.0)
		var role: StringName = record["role"]
		if role in [&"header", &"dock", &"chrome"]:
			panel.set_border_width_all(0)
			panel.set_corner_radius_all(2 if role == &"chrome" else 0)
			panel.border_width_bottom = 1 if role != &"dock" else 0
			panel.border_width_top = 1 if role != &"header" else 0
			panel.shadow_size = 3 if role != &"chrome" else 0
			panel.shadow_offset = Vector2(0.0, -1.0 if role == &"dock" else 1.0)
		_style(control, record, &"panel", panel)
		_decorate(control, record, panel, Vector3.ZERO)
	elif control is LineEdit:
		_style(control, record, &"normal", _flat(_with_alpha(_background.darkened(0.16), _opacity), _border, 5, _original_style(control, record, &"normal")))
		_style(control, record, &"read_only", _flat(_with_alpha(_background, _opacity), _border.darkened(0.15), 5, _original_style(control, record, &"read_only")))
		_style(control, record, &"focus", _focus_style())
		_color(control, record, &"selection_color", _with_alpha(_accent, 0.35))
		_color(control, record, &"caret_color", _text)
	elif control is TextEdit:
		_style(control, record, &"normal", _flat(_with_alpha(_background, _opacity), _border, 5, _original_style(control, record, &"normal")))
		_style(control, record, &"focus", _focus_style())
		_color(control, record, &"selection_color", _with_alpha(_accent, 0.35))
		_color(control, record, &"caret_color", _text)
	elif control is TabContainer or control is TabBar:
		_apply_tabs(control, record)
	elif control is Slider:
		_apply_slider(control, record)
	elif control is ScrollBar:
		_apply_scrollbar(control, record)
	elif control is HSeparator or control is VSeparator:
		var separator: StyleBoxLine = StyleBoxLine.new()
		separator.color = _with_alpha(_border.lerp(_background, 0.20), 0.72)
		separator.thickness = 1
		separator.vertical = control is VSeparator
		separator.grow_begin = -6.0 if control is VSeparator else 0.0
		separator.grow_end = -6.0 if control is VSeparator else 0.0
		_style(control, record, &"separator", separator)
		_constant(control, record, &"separation", 8 if control is HSeparator else 6)
	elif control is ProgressBar:
		_style(control, record, &"background", _flat(_with_alpha(_background, _opacity), _border, 4, _original_style(control, record, &"background")))
		var original_fill: StyleBox = _original_style(control, record, &"fill")
		var fill_color: Color = _accent
		if original_fill is StyleBoxFlat:
			var old_color: Color = (original_fill as StyleBoxFlat).bg_color
			if old_color.s > 0.4:
				fill_color = old_color
		_style(control, record, &"fill", _flat(_with_alpha(fill_color, 0.85), fill_color, 4, original_fill))
	elif control is Tree or control is ItemList:
		_style(control, record, &"panel", _flat(_with_alpha(_background, _opacity), _border, 5, _original_style(control, record, &"panel")))
		_style(control, record, &"selected", _flat(_with_alpha(_accent, 0.24), _accent, 4, _original_style(control, record, &"selected")))
		_style(control, record, &"selected_focus", _flat(_with_alpha(_accent, 0.29), _accent.lightened(0.2), 4, _original_style(control, record, &"selected_focus")))
	_apply_text(control, record)
	if control is BaseButton:
		record["text_color"] = null
		_paint_button(record["blend"], control.get_instance_id())


func _apply_tooltip_theme(control: Control, record: Dictionary) -> void:
	if not (control is BaseButton or control is LineEdit or control is TextEdit or control is Tree or control is ItemList) and control.tooltip_text.is_empty():
		return
	# A local duplicate preserves the game's fonts/icons and skins engine-created popups.
	var original: Theme = record["theme"] as Theme
	var theme: Theme = original.duplicate() as Theme if original != null else Theme.new()
	theme.set_color(&"font_color", &"TooltipLabel", _text)
	theme.set_font_size(&"font_size", &"TooltipLabel", maxi(12, roundi(13.0 * _font_ratio)))
	var tooltip: StyleBoxFlat = _flat(_with_alpha(_background, maxf(_opacity, 0.96)), _border, 4)
	tooltip.content_margin_left = 10.0
	tooltip.content_margin_right = 10.0
	tooltip.content_margin_top = 7.0
	tooltip.content_margin_bottom = 7.0
	theme.set_stylebox(&"panel", &"TooltipPanel", tooltip)
	theme.set_stylebox(&"panel", &"PopupMenu", tooltip.duplicate() as StyleBoxFlat)
	theme.set_stylebox(&"hover", &"PopupMenu", _flat(_with_alpha(_accent, 0.23), _accent, 4))
	theme.set_color(&"font_color", &"PopupMenu", _text)
	theme.set_color(&"font_hover_color", &"PopupMenu", Color.WHITE)
	theme.set_color(&"font_disabled_color", &"PopupMenu", _muted.darkened(0.3))
	theme.set_font_size(&"font_size", &"PopupMenu", roundi(14.0 * _font_ratio))
	record["skin_theme"] = theme
	control.theme = theme


func _apply_text(control: Control, record: Dictionary) -> void:
	_apply_fonts(control, record)
	if not (control is Label or control is RichTextLabel or control is BaseButton or control is LineEdit or control is TextEdit or control is TabBar or control is TabContainer or control is Tree or control is ItemList or control is ProgressBar):
		return
	if control is RichTextLabel:
		_neutral_color(control, record, &"default_color", _text)
	else:
		_neutral_color(control, record, &"font_color", _text)
	if control is LineEdit:
		_neutral_color(control, record, &"font_placeholder_color", _muted)
	if control is BaseButton:
		_neutral_color(control, record, &"font_hover_color", Color.WHITE)
		_neutral_color(control, record, &"font_pressed_color", _accent.lightened(0.6))
		_neutral_color(control, record, &"font_hover_pressed_color", Color.WHITE)
		_neutral_color(control, record, &"font_focus_color", Color.WHITE)
		_neutral_color(control, record, &"font_disabled_color", _muted.darkened(0.25))


func _apply_fonts(control: Control, record: Dictionary) -> void:
	if control is RichTextLabel:
		for key: StringName in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size", &"mono_font_size"]:
			_font(control, record, key)
	elif control is Label or control is BaseButton or control is LineEdit or control is TextEdit or control is TabBar or control is TabContainer or control is Tree or control is ItemList or control is ProgressBar:
		_font(control, record, &"font_size")


func _update_tooltip_fonts(record: Dictionary) -> void:
	var theme: Theme = record.get("skin_theme") as Theme
	if theme != null:
		theme.set_font_size(&"font_size", &"TooltipLabel", maxi(12, roundi(13.0 * _font_ratio)))
		theme.set_font_size(&"font_size", &"PopupMenu", roundi(14.0 * _font_ratio))


func _update_opacity(control: Control, record: Dictionary) -> void:
	var styles: Dictionary = record["owned_styles"]
	if control is BaseButton:
		if styles.has(&"disabled"):
			(styles[&"disabled"] as StyleBoxFlat).bg_color.a = _opacity
		_paint_button(record["blend"], control.get_instance_id())
	else:
		for key: StringName in styles:
			if key in [&"panel", &"normal", &"read_only", &"background", &"tab_unselected", &"tab_selected", &"tab_hovered"]:
				var style: StyleBoxFlat = styles[key] as StyleBoxFlat
				if style != null:
					style.bg_color.a = _opacity
		if control is PanelContainer or control is Panel:
			var panel: StyleBoxFlat = styles.get(&"panel") as StyleBoxFlat
			if panel != null:
				_decorate(control, record, panel, Vector3.ZERO)
	var theme: Theme = record.get("skin_theme") as Theme
	if theme != null:
		var tooltip: StyleBoxFlat = theme.get_stylebox(&"panel", &"TooltipPanel") as StyleBoxFlat
		var popup: StyleBoxFlat = theme.get_stylebox(&"panel", &"PopupMenu") as StyleBoxFlat
		if tooltip != null:
			tooltip.bg_color.a = maxf(_opacity, 0.96)
		if popup != null:
			popup.bg_color.a = maxf(_opacity, 0.96)


func _apply_button(button: BaseButton, record: Dictionary) -> void:
	_kill_tween(record)
	var original: StyleBox = _original_style(button, record, &"normal")
	var dynamic: StyleBoxFlat = _flat(_with_alpha(_surface, _opacity), _border, 4, original)
	record["dynamic"] = dynamic
	record["margins"] = Vector2(dynamic.content_margin_top, dynamic.content_margin_bottom)
	for key: StringName in ACTIVE_STYLES:
		_style(button, record, key, dynamic)
	_style(button, record, &"disabled", _flat(_with_alpha(_background.lightened(0.025), _opacity), _border.darkened(0.2), 4, original))
	var focus: StyleBoxFlat = _focus_style()
	record["focus_style"] = focus
	_style(button, record, &"focus", focus)
	record["target"] = Vector3(-1.0, -1.0, -1.0)
	_sync_button(button, record, 0.0)


func _apply_tabs(control: Control, record: Dictionary) -> void:
	_style(control, record, &"panel", _flat(_with_alpha(_background, _opacity), _border, 7, _original_style(control, record, &"panel")))
	_style(control, record, &"tab_unselected", _flat(_with_alpha(_surface, _opacity), _border, 5, _original_style(control, record, &"tab_unselected")))
	_style(control, record, &"tab_selected", _flat(_with_alpha(_surface.lerp(_accent, 0.18), _opacity), _accent, 5, _original_style(control, record, &"tab_selected")))
	_style(control, record, &"tab_hovered", _flat(_with_alpha(_surface.lerp(_accent, 0.12), _opacity), _accent.lightened(0.15), 5, _original_style(control, record, &"tab_hovered")))
	_neutral_color(control, record, &"font_selected_color", Color.WHITE)
	_neutral_color(control, record, &"font_unselected_color", _muted)


func _apply_slider(control: Control, record: Dictionary) -> void:
	var track: StyleBoxFlat = _flat(_with_alpha(_border.darkened(0.2), _opacity), _border, 3, _original_style(control, record, &"slider"))
	_style(control, record, &"slider", track)
	_style(control, record, &"grabber_area", _flat(_accent.darkened(0.1), _accent, 3, _original_style(control, record, &"grabber_area")))
	_style(control, record, &"grabber_area_highlight", _flat(_accent.lightened(0.12), _accent.lightened(0.25), 3, _original_style(control, record, &"grabber_area_highlight")))


func _apply_scrollbar(control: Control, record: Dictionary) -> void:
	_style(control, record, &"scroll", _flat(_with_alpha(_background, 0.65), Color.TRANSPARENT, 3, _original_style(control, record, &"scroll")))
	_style(control, record, &"grabber", _flat(_border.lightened(0.12), _border.lightened(0.12), 4, _original_style(control, record, &"grabber")))
	_style(control, record, &"grabber_highlight", _flat(_accent.darkened(0.12), _accent, 4, _original_style(control, record, &"grabber_highlight")))
	_style(control, record, &"grabber_pressed", _flat(_accent, _accent.lightened(0.1), 4, _original_style(control, record, &"grabber_pressed")))


func _hover_changed(id: int, entered: bool, keyboard: bool) -> void:
	if not _active or not _buttons.has(id):
		return
	var record: Dictionary = _buttons[id]
	var button: BaseButton = _control(record) as BaseButton
	if not is_instance_valid(button):
		return
	var was_hot: bool = bool(record["hover"]) or bool(record["focus"])
	record["focus" if keyboard else "hover"] = entered
	if entered and not was_hot and not button.disabled:
		hovered.emit(button)
	_sync_button(button, record, 0.12 if entered else 0.16)


func _down_changed(id: int, down: bool) -> void:
	if not _active or not _buttons.has(id):
		return
	var record: Dictionary = _buttons[id]
	record["down"] = down
	var button: BaseButton = _control(record) as BaseButton
	if is_instance_valid(button):
		if down:
			record["activation_generation"] = int(record["activation_generation"]) + 1
			record["activation_armed"] = not button.disabled and button.is_visible_in_tree() and button.mouse_filter != Control.MOUSE_FILTER_IGNORE
		else:
			# Godot may emit pressed after button_up within the same input event.
			_disarm_activation.call_deferred(id, int(record["activation_generation"]))
		_sync_button(button, record, 0.07 if down else 0.11)


func _disarm_activation(id: int, generation: int) -> void:
	if _buttons.has(id):
		var record: Dictionary = _buttons[id]
		if int(record["activation_generation"]) == generation:
			record["activation_armed"] = false


func _activated(id: int) -> void:
	if not _active or not _buttons.has(id):
		return
	var record: Dictionary = _buttons[id]
	var button: BaseButton = _control(record) as BaseButton
	var armed: bool = bool(record["activation_armed"])
	record["activation_armed"] = false
	if is_instance_valid(button) and not button.disabled:
		if button.is_visible_in_tree() and button.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			activated.emit(button)
		elif armed:
			# A native Apply/Cancel callback may already have hidden its window.
			# An actual button_down authorizes this one sound; hidden proxy signals
			# without a visible press remain silent and cannot double the UI sound.
			activated.emit(null)
		if _buttons.has(id) and is_instance_valid(button):
			_sync_button(button, _buttons[id], 0.11)


func _toggled(_pressed: bool, id: int) -> void:
	if _active and _buttons.has(id):
		var record: Dictionary = _buttons[id]
		var button: BaseButton = _control(record) as BaseButton
		if is_instance_valid(button):
			_sync_button(button, record, 0.11)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed < 0.08:
		return
	_elapsed = 0.0
	# No repeated scene traversal. Main refreshes bottom-button styles itself.
	for key: Variant in _buttons:
		var record: Dictionary = _buttons[key]
		var button: BaseButton = _control(record) as BaseButton
		if not is_instance_valid(button):
			continue
		# Hidden native buttons still own the callbacks behind our visible proxies.
		# A role change can retarget them without showing them or their old window.
		var visible: bool = button.is_visible_in_tree()
		var window_id: int = _button_window_id(button)
		var retargeted: bool = window_id != int(record["linked_id"])
		if not visible:
			if retargeted:
				_sync_button(button, record, 0.0)
			continue
		var dynamic: StyleBoxFlat = record.get("dynamic") as StyleBoxFlat
		if dynamic != null and button.get_theme_stylebox(&"normal") != dynamic:
			for style_key: StringName in ACTIVE_STYLES:
				button.add_theme_stylebox_override(style_key, dynamic)
			record["text_color"] = null
			_paint_button(record["blend"], button.get_instance_id())
		var selected_meta: bool = bool(button.get_meta("pax_interface_selected", false))
		if retargeted or selected_meta != bool(record["selected_meta"]) or button.button_pressed != bool(record["toggle_pressed"]) or button.disabled != bool(record["disabled"]):
			_sync_button(button, record, 0.12)


func _button_window(button: BaseButton) -> CanvasItem:
	var candidate: Variant = button.get_meta("win") if button.has_meta("win") else null
	return candidate as CanvasItem if is_instance_valid(candidate) and candidate is CanvasItem else null


func _button_window_id(button: BaseButton) -> int:
	var window: CanvasItem = _button_window(button)
	return window.get_instance_id() if window != null else 0


func _sync_button(button: BaseButton, record: Dictionary, duration: float) -> void:
	if button.disabled:
		record["activation_armed"] = false
	record["selected_meta"] = bool(button.get_meta("pax_interface_selected", false))
	record["toggle_pressed"] = button.button_pressed
	record["disabled"] = button.disabled
	var selected: bool = button.toggle_mode and button.button_pressed
	selected = selected or bool(record["selected_meta"])
	var linked: CanvasItem = _button_window(button)
	_bind_window(record, linked, button.get_instance_id())
	if linked != null:
		selected = selected or linked.is_visible_in_tree()
	var hot: bool = bool(record["hover"]) or bool(record["focus"])
	var pressed: bool = bool(record["down"]) and not button.disabled
	var target: Vector3 = Vector3(1.0 if hot and not button.disabled else 0.0, 1.0 if pressed else 0.0, 1.0 if selected else 0.0)
	if (record["target"] as Vector3).is_equal_approx(target):
		return
	record["target"] = target
	_kill_tween(record)
	if not _motion or duration <= 0.0 or not is_inside_tree():
		_paint_button(target, button.get_instance_id())
		return
	var tween: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	record["tween"] = tween
	tween.tween_method(_paint_button.bind(button.get_instance_id()), record["blend"], target, duration)


func _bind_window(record: Dictionary, window: CanvasItem, id: int) -> void:
	var window_id: int = window.get_instance_id() if is_instance_valid(window) else 0
	if int(record.get("linked_id", 0)) == window_id:
		if window_id == 0:
			return
		if _window_bindings.has(window_id):
			var current: Dictionary = _window_bindings[window_id]
			if (current["buttons"] as Dictionary).has(id):
				return
	_unbind_window(record)
	if window_id == 0:
		return
	# Native and proxy buttons can target the same panel. Subscribe ONCE per
	# panel, then fan out to its button IDs instead of competing bound callbacks.
	if not _window_bindings.has(window_id):
		var callback: Callable = _window_visibility_changed.bind(window_id)
		_window_bindings[window_id] = {"node": weakref(window), "callback": callback, "buttons": {}}
		if not window.visibility_changed.is_connected(callback):
			window.visibility_changed.connect(callback)
	var binding: Dictionary = _window_bindings[window_id]
	(binding["buttons"] as Dictionary)[id] = true
	record["linked_window"] = weakref(window)
	record["linked_id"] = window_id


func _unbind_window(record: Dictionary) -> void:
	var window_id: int = int(record.get("linked_id", 0))
	if _window_bindings.has(window_id):
		var binding: Dictionary = _window_bindings[window_id]
		var buttons: Dictionary = binding["buttons"]
		buttons.erase(int(record["id"]))
		if buttons.is_empty():
			_disconnect_window(binding)
			_window_bindings.erase(window_id)
	record["linked_window"] = null
	record["linked_id"] = 0


func _disconnect_window(binding: Dictionary) -> void:
	var reference: WeakRef = binding["node"] as WeakRef
	var window: CanvasItem = reference.get_ref() as CanvasItem
	var callback: Callable = binding["callback"]
	if is_instance_valid(window) and window.visibility_changed.is_connected(callback):
		window.visibility_changed.disconnect(callback)


func _clear_window_bindings() -> void:
	for key: Variant in _window_bindings:
		_disconnect_window(_window_bindings[key])
	_window_bindings.clear()


func _window_visibility_changed(window_id: int) -> void:
	if not _active or not _window_bindings.has(window_id):
		return
	var binding: Dictionary = _window_bindings[window_id]
	var listeners: Dictionary = binding["buttons"]
	# A callback may retarget/reparent a button. Snapshot IDs on this infrequent
	# event, never in the per-frame path.
	for id: Variant in listeners.keys():
		if _buttons.has(id):
			var record: Dictionary = _buttons[id]
			var button: BaseButton = _control(record) as BaseButton
			if is_instance_valid(button):
				_sync_button(button, record, 0.12)


func _paint_button(blend: Vector3, id: int) -> void:
	if not _buttons.has(id):
		return
	var record: Dictionary = _buttons[id]
	record["blend"] = blend
	var style: StyleBoxFlat = record.get("dynamic") as StyleBoxFlat
	if style == null:
		return
	var button: BaseButton = _control(record) as BaseButton
	if not is_instance_valid(button):
		return
	var role: StringName = record["role"]
	var base: Color = _background.lerp(_surface, 0.64) if role == &"command" else _surface
	var primary: bool = bool(button.get_meta("pax_interface_primary", false))
	var tint: Color = base.lerp(_accent, 0.19 * blend.z + 0.10 * blend.x + (0.17 if primary else 0.0))
	tint = tint.darkened(0.15 * blend.y)
	style.bg_color = _with_alpha(tint, _opacity)
	var border_accent: float = maxf(maxf(blend.z * 0.78, blend.x * 0.62), 0.70 if primary else 0.0)
	style.border_color = _border.lerp(_accent, border_accent).lightened(0.035 * blend.x)
	style.shadow_color = Color(0.005, 0.014, 0.025, 0.46 - 0.14 * blend.y)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0.0, 1.5 - blend.y)
	if role == &"command":
		var outlined: bool = blend.x > 0.025 or blend.z > 0.025
		style.set_border_width_all(1 if outlined else 0)
		style.border_width_right = 1
		if not outlined:
			style.border_color.a = 0.60
		style.shadow_size = 0
	var focus: StyleBoxFlat = record.get("focus_style") as StyleBoxFlat
	if focus != null:
		focus.border_color = _with_alpha(_accent.lightened(0.1), 0.64 * blend.x)
	var text_color: Color = _text.lerp(Color.WHITE, 0.6 * blend.x).lerp(_accent.lightened(0.68), blend.z * 0.50)
	if record["text_color"] == null or not (record["text_color"] as Color).is_equal_approx(text_color):
		record["text_color"] = text_color
		for key: StringName in ANIMATED_TEXT_COLORS:
			_neutral_color(button, record, key, text_color)
	if button is TextureButton:
		var original_tint: Color = record["self_modulate"]
		var icon_tint: Color = Color.WHITE.lerp(_accent.lightened(0.65), blend.x * 0.35 + blend.z * 0.25).darkened(0.12 * blend.y)
		button.self_modulate = original_tint * icon_tint
	_decorate(button, record, style, blend)
	var margins: Vector2 = record["margins"]
	# Opposite margin deltas move content one pixel without changing minimum size.
	var shift: float = minf(1.0, margins.y) * blend.y
	style.content_margin_top = margins.x + shift
	style.content_margin_bottom = margins.y - shift


func _decorate(control: Control, record: Dictionary, style: StyleBoxFlat, blend: Vector3) -> void:
	var role: StringName = record["role"]
	if (control is TextureButton or control is LinkButton) and role == &"":
		return
	var relief: Node2D = record.get("relief") as Node2D
	if not is_instance_valid(relief):
		relief = RELIEF_SCRIPT.new() as Node2D
		record["relief"] = relief
		control.add_child(relief)
		relief.call("setup", control)
	# The native StyleBox retains borders, shadows, padding and focus. Its centre
	# is rendered by the child BEHIND it, so gradients never wash over text/icons.
	style.draw_center = false
	if role == &"":
		role = &"tool" if control is BaseButton else &"card"
	relief.call("paint", style.bg_color, _accent, blend, role, float(style.corner_radius_top_left), control is BaseButton and (control as BaseButton).disabled)


func _release_decoration(record: Dictionary) -> void:
	var relief: Node2D = record.get("relief") as Node2D
	if is_instance_valid(relief):
		relief.hide()
		if relief.get_parent() != null:
			relief.get_parent().remove_child(relief)
		relief.queue_free()
	record["relief"] = null


func _kill_tween(record: Dictionary) -> void:
	var tween: Tween = record.get("tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	record["tween"] = null


func _flat(fill: Color, border: Color, radius: int, original: StyleBox = null) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.corner_detail = 5
	style.anti_aliasing = true
	if original != null:
		style.content_margin_left = original.get_margin(SIDE_LEFT)
		style.content_margin_right = original.get_margin(SIDE_RIGHT)
		style.content_margin_top = original.get_margin(SIDE_TOP)
		style.content_margin_bottom = original.get_margin(SIDE_BOTTOM)
	return style


func _focus_style() -> StyleBoxFlat:
	return _flat(Color.TRANSPARENT, _with_alpha(_accent.lightened(0.1), 0.64), 4)


func _with_alpha(value: Color, opacity: float) -> Color:
	return Color(value.r, value.g, value.b, opacity)


func _original_style(control: Control, record: Dictionary, key: StringName) -> StyleBox:
	var styles: Dictionary = record["styles"]
	if not styles.has(key):
		styles[key] = {"present": control.has_theme_stylebox_override(key), "value": control.get_theme_stylebox(key)}
	var saved: Dictionary = styles[key]
	return saved["value"] as StyleBox


func _style(control: Control, record: Dictionary, key: StringName, value: StyleBox) -> void:
	_original_style(control, record, key)
	(record["owned_styles"] as Dictionary)[key] = value
	control.add_theme_stylebox_override(key, value)


func _original_color(control: Control, record: Dictionary, key: StringName) -> Color:
	var colors: Dictionary = record["colors"]
	if not colors.has(key):
		colors[key] = {"present": control.has_theme_color_override(key), "value": control.get_theme_color(key)}
	var saved: Dictionary = colors[key]
	return saved["value"]


func _color(control: Control, record: Dictionary, key: StringName, value: Color) -> void:
	_original_color(control, record, key)
	control.add_theme_color_override(key, value)


func _neutral_color(control: Control, record: Dictionary, key: StringName, value: Color) -> void:
	var original: Color = _original_color(control, record, key)
	# Preserve status and faction colours; normalize only neutral UI text.
	if original.s < 0.31 or (original.b >= original.r and original.s < 0.46):
		_color(control, record, key, value)


func _font(control: Control, record: Dictionary, key: StringName) -> void:
	var fonts: Dictionary = record["fonts"]
	if not fonts.has(key):
		fonts[key] = {"present": control.has_theme_font_size_override(key), "value": control.get_theme_font_size(key)}
	var saved: Dictionary = fonts[key]
	var original_size: int = int(saved["value"])
	control.add_theme_font_size_override(key, maxi(int(record.get("font_floor", 10)), roundi(float(original_size) * _font_ratio)))


func _constant(control: Control, record: Dictionary, key: StringName, value: int) -> void:
	var constants: Dictionary = record["constants"]
	if not constants.has(key):
		constants[key] = {"present": control.has_theme_constant_override(key), "value": control.get_theme_constant(key)}
	control.add_theme_constant_override(key, value)


func _font_floor(control: Control) -> int:
	var ancestor: Node = control
	while ancestor != null:
		if ancestor.name == &"PaxInterfaceSettings":
			return 12
		ancestor = ancestor.get_parent()
	return 10


func _restore_overrides(control: Control, record: Dictionary) -> void:
	for key: StringName in record["styles"]:
		var saved: Dictionary = record["styles"][key]
		if bool(saved["present"]):
			control.add_theme_stylebox_override(key, saved["value"] as StyleBox)
		else:
			control.remove_theme_stylebox_override(key)
	for key: StringName in record["colors"]:
		var saved: Dictionary = record["colors"][key]
		if bool(saved["present"]):
			control.add_theme_color_override(key, saved["value"])
		else:
			control.remove_theme_color_override(key)
	for key: StringName in record["fonts"]:
		var saved: Dictionary = record["fonts"][key]
		if bool(saved["present"]):
			control.add_theme_font_size_override(key, int(saved["value"]))
		else:
			control.remove_theme_font_size_override(key)
	for key: StringName in record["constants"]:
		var saved: Dictionary = record["constants"][key]
		if bool(saved["present"]):
			control.add_theme_constant_override(key, int(saved["value"]))
		else:
			control.remove_theme_constant_override(key)
	control.theme = record["theme"] as Theme
	if control is TextureButton:
		control.self_modulate = record["self_modulate"]
