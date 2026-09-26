extends PanelContainer
## The controller owns persistence and the settings transaction.

signal preview_changed(settings: Dictionary)
signal apply_requested(settings: Dictionary)
signal cancel_requested
signal reset_requested
signal edit_mode_changed(enabled: bool)
signal order_changed(order: Array)
signal sound_preview_requested

const THEME_IDS: Array[String] = ["graphite", "midnight", "slate"]
const FONT_SIZES: Array[int] = [12, 14, 16]
const SWATCHES: Array[String] = ["#279cab", "#4da1f7", "#9470e4", "#eab84e", "#ed7977", "#93a4b7"]
const COMMAND_IDS: Array[String] = ["orders", "plans", "laws", "objects", "mining", "research"]

var draft: Dictionary = {}
var _mod: PaxMod
var _commands: Array[Dictionary] = []
var _controls: Dictionary = {}
var _font_buttons: Array[Button] = []
var _order_box: GridContainer
var _feedback_body: VBoxContainer
var _settings_body: VBoxContainer
var _accent_row: HBoxContainer
var _reorder_hint: Label
var _font_section: VBoxContainer
var _font_line: HBoxContainer
var _font_caption: Label
var _font_stacked: bool = false
var _updating: bool = false
var _editing: bool = false
var _built: bool = false
var _row_script: Script
var _order_tweens: Array[Tween] = []
var _order_generation: int = 0

func setup(mod: PaxMod, initial: Dictionary, commands: Array[Dictionary]) -> void:
	_mod = mod
	_commands = commands.duplicate(true)
	_row_script = load(_mod.path("drag_row.gd")) as Script
	if not _built:
		_build()
	begin(initial)

func begin(current: Dictionary) -> void:
	draft = current.duplicate(true)
	if _editing:
		_editing = false
		edit_mode_changed.emit(false)
	if _built:
		_sync_controls()
		(_controls["feedback_expanded"] as Button).set_pressed_no_signal(false)
		_feedback_toggled(false)

func set_commands(commands: Array[Dictionary]) -> void:
	_commands = commands.duplicate(true)
	if _built:
		_rebuild_order()

func set_edit_mode(enabled: bool) -> void:
	if _editing == enabled:
		return
	_editing = enabled
	if _built:
		(_controls["edit_mode"] as CheckButton).set_pressed_no_signal(enabled)
		_reorder_hint.visible = enabled
		_settings_body.add_theme_constant_override("separation", 6 if enabled else 8)
		_rebuild_order()
	edit_mode_changed.emit(enabled)

func request_order_move(source_id: String, target_id: String) -> void:
	_move_to(source_id, target_id)

func _tr(key: String) -> String:
	return _mod.tr_key("pax_interface_" + key)

func _build() -> void:
	_built = true
	name = "PaxInterfaceSettings"
	custom_minimum_size = Vector2(360, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_compact_layout)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12 if side in ["left", "right"] else 11)
	add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)
	var title: Label = Label.new()
	title.text = _tr("title")
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(title)
	var close: Button = _button("close", "CloseSettings")
	close.text = "×"
	close.tooltip_text = _tr("close")
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(func() -> void: cancel_requested.emit())
	header.add_child(close)
	outer.add_child(HSeparator.new())
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	_settings_body = body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	_section(body, "appearance")
	var theme_row: HBoxContainer = _row(body, "theme")
	var theme_select: OptionButton = OptionButton.new()
	theme_select.name = "Theme"
	theme_select.add_theme_font_size_override("font_size", 14)
	theme_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for theme_id: String in THEME_IDS:
		theme_select.add_item(_tr("theme_" + theme_id))
	theme_select.item_selected.connect(_theme_changed)
	theme_row.add_child(theme_select)
	_controls["theme"] = theme_select
	_build_accent(body)
	_build_slider(body, "opacity", "transparency", 0, 50, 1)
	_build_slider(body, "scale", "scale", 80, 125, 5)
	_font_section = VBoxContainer.new()
	_font_section.name = "FontSizeRow"
	_font_section.add_theme_constant_override("separation", 5)
	body.add_child(_font_section)
	_font_line = HBoxContainer.new()
	_font_line.add_theme_constant_override("separation", 8)
	_font_section.add_child(_font_line)
	_font_caption = Label.new()
	_font_caption.text = _tr("font_size")
	_font_caption.add_theme_font_size_override("font_size", 14)
	_font_caption.custom_minimum_size.x = 102
	_font_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_font_line.add_child(_font_caption)
	var font_row: HBoxContainer = HBoxContainer.new()
	font_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_row.add_theme_constant_override("separation", 4)
	_font_line.add_child(font_row)
	var font_group: ButtonGroup = ButtonGroup.new()
	for font_index: int in range(FONT_SIZES.size()):
		var font_button: Button = _button("font_" + str(FONT_SIZES[font_index]), "Font" + str(FONT_SIZES[font_index]))
		font_button.toggle_mode = true
		font_button.button_group = font_group
		_compact_button(font_button, 5, 5)
		font_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		font_button.pressed.connect(_font_changed.bind(FONT_SIZES[font_index]))
		font_row.add_child(font_button)
		_font_buttons.append(font_button)
	_section(body, "layout")
	_build_toggle(body, "edit_mode", "edit_mode", false)
	_reorder_hint = Label.new()
	_reorder_hint.text = _tr("compact_reorder_hint")
	_reorder_hint.tooltip_text = _tr("reorder_hint")
	_reorder_hint.add_theme_font_size_override("font_size", 12)
	_reorder_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reorder_hint.modulate = Color(0.76, 0.83, 0.92)
	_reorder_hint.hide()
	body.add_child(_reorder_hint)
	_order_box = GridContainer.new()
	_order_box.columns = 2
	_order_box.name = "CommandOrder"
	_order_box.add_theme_constant_override("h_separation", 6)
	_order_box.add_theme_constant_override("v_separation", 6)
	body.add_child(_order_box)
	_build_toggle(body, "labels", "show_labels", true)
	body.add_child(HSeparator.new())
	var feedback: Button = _button("compact_feedback", "FeedbackDisclosure")
	feedback.toggle_mode = true
	feedback.alignment = HORIZONTAL_ALIGNMENT_LEFT
	feedback.tooltip_text = _tr("compact_feedback_hint")
	feedback.toggled.connect(_feedback_toggled)
	body.add_child(feedback)
	_controls["feedback_expanded"] = feedback
	_feedback_body = VBoxContainer.new()
	_feedback_body.name = "FeedbackOptions"
	_feedback_body.add_theme_constant_override("separation", 7)
	_feedback_body.hide()
	body.add_child(_feedback_body)
	_build_toggle(_feedback_body, "motion", "motion", true)
	_build_toggle(_feedback_body, "sound_enabled", "sound_enabled", true)
	_build_slider(_feedback_body, "volume", "volume", 0, 100, 1)
	var sound_test: Button = _button("sound_preview", "PreviewSound")
	sound_test.pressed.connect(func() -> void: sound_preview_requested.emit())
	_feedback_body.add_child(sound_test)
	_controls["sound_preview"] = sound_test
	outer.add_child(HSeparator.new())
	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	outer.add_child(footer)
	var reset: Button = _button("reset", "ResetSettings")
	reset.pressed.connect(func() -> void: reset_requested.emit())
	footer.add_child(reset)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel: Button = _button("cancel", "CancelSettings")
	cancel.pressed.connect(func() -> void: cancel_requested.emit())
	footer.add_child(cancel)
	var apply: Button = _button("apply", "ApplySettings")
	apply.set_meta("pax_interface_primary", true)
	apply.pressed.connect(func() -> void: apply_requested.emit(draft.duplicate(true)))
	footer.add_child(apply)
	call_deferred("_compact_layout")

func _button(key: String, node_name: String) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = _tr(key)
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size.y = 30
	return button

func _compact_button(button: BaseButton, horizontal_margin: int, vertical_margin: int) -> void:
	# The shared skin preserves these content margins when creating its styles.
	for key: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBoxEmpty = StyleBoxEmpty.new()
		style.content_margin_left = horizontal_margin
		style.content_margin_right = horizontal_margin
		style.content_margin_top = vertical_margin
		style.content_margin_bottom = vertical_margin
		button.add_theme_stylebox_override(key, style)

func _section(parent: VBoxContainer, title_key: String) -> void:
	if parent.get_child_count() > 0:
		parent.add_child(HSeparator.new())
	var label: Label = Label.new()
	label.text = _tr(title_key)
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(0.80, 0.88, 0.97)
	parent.add_child(label)

func _row(parent: VBoxContainer, title_key: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = _tr(title_key)
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size.x = 151
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return row

func _build_accent(parent: VBoxContainer) -> void:
	_accent_row = _row(parent, "accent")
	(_accent_row.get_child(0) as Label).custom_minimum_size.x = 102
	_accent_row.add_theme_constant_override("separation", 5)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_row.add_child(row)
	for hex: String in SWATCHES:
		var swatch: Button = Button.new()
		swatch.name = "Accent" + hex.trim_prefix("#")
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_font_size_override("font_size", 12)
		_compact_button(swatch, 2, 2)
		swatch.tooltip_text = hex.to_upper()
		swatch.pressed.connect(_accent_changed.bind(Color.html(hex)))
		row.add_child(swatch)
		var color: ColorRect = ColorRect.new()
		color.color = Color.html(hex)
		color.mouse_filter = Control.MOUSE_FILTER_IGNORE
		color.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		color.offset_left = 3
		color.offset_top = 3
		color.offset_right = -3
		color.offset_bottom = -3
		swatch.add_child(color)
	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.name = "CustomAccent"
	picker.custom_minimum_size = Vector2(22, 22)
	picker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.add_theme_font_size_override("font_size", 12)
	_compact_button(picker, 2, 2)
	picker.edit_alpha = false
	picker.tooltip_text = _tr("custom_accent")
	picker.color_changed.connect(_accent_changed)
	row.add_child(picker)
	_controls["accent"] = picker
	var code: Label = Label.new()
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	code.add_theme_font_size_override("font_size", 12)
	row.add_child(code)
	_controls["accent_code"] = code

func _build_slider(parent: VBoxContainer, key: String, title_key: String,
		minimum: float, maximum: float, increment: float) -> void:
	var row: HBoxContainer = _row(parent, title_key)
	var slider: HSlider = HSlider.new()
	slider.name = key.to_pascal_case()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(64, 26)
	slider.value_changed.connect(_slider_changed.bind(key))
	row.add_child(slider)
	_controls[key] = slider
	var amount: Label = Label.new()
	amount.add_theme_font_size_override("font_size", 14)
	amount.custom_minimum_size.x = 39
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	_controls[key + "_value"] = amount

func _build_toggle(parent: VBoxContainer, key: String, title_key: String,
		initial: bool) -> void:
	var row: HBoxContainer = _row(parent, title_key)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var toggle: CheckButton = CheckButton.new()
	toggle.name = key.to_pascal_case()
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.tooltip_text = _tr(title_key)
	toggle.custom_minimum_size.y = 28
	toggle.set_pressed_no_signal(initial)
	toggle.toggled.connect(_toggle_changed.bind(key))
	row.add_child(toggle)
	_controls[key] = toggle

func _compact_layout() -> void:
	if not _built or not _controls.has("accent_code"):
		return
	(_controls["accent_code"] as Label).visible = size.x >= 396.0 and int(draft.get("font_size", 14)) <= 14
	var should_stack: bool = size.x < 378.0 or (size.x < 405.0 and int(draft.get("font_size", 14)) > 14)
	if should_stack != _font_stacked and is_instance_valid(_font_caption):
		_font_stacked = should_stack
		_font_caption.reparent(_font_section if _font_stacked else _font_line, false)
		(_font_section if _font_stacked else _font_line).move_child(_font_caption, 0)

func _feedback_toggled(expanded: bool) -> void:
	_feedback_body.visible = expanded
	var button: Button = _controls["feedback_expanded"] as Button
	button.text = _tr("compact_feedback_open" if expanded else "compact_feedback")

func _sync_controls() -> void:
	_updating = true
	var theme_select: OptionButton = _controls["theme"] as OptionButton
	theme_select.select(maxi(0, THEME_IDS.find(str(draft.get("theme", "graphite")))))
	var accent: Color = Color.from_string(str(draft.get("accent", "#279cab")), Color("279cab"))
	(_controls["accent"] as ColorPickerButton).color = accent
	(_controls["accent_code"] as Label).text = "#" + accent.to_html(false).to_upper()
	_sync_slider("opacity", (1.0 - float(draft.get("opacity", 0.85))) * 100.0)
	_sync_slider("scale", float(draft.get("scale", 1.0)) * 100.0)
	_sync_slider("volume", float(draft.get("volume", 0.35)) * 100.0)
	for font_index: int in range(_font_buttons.size()):
		_font_buttons[font_index].set_pressed_no_signal(int(draft.get("font_size", 14)) == FONT_SIZES[font_index])
	for key: String in ["labels", "motion", "sound_enabled"]:
		(_controls[key] as CheckButton).set_pressed_no_signal(bool(draft.get(key, true)))
	(_controls["edit_mode"] as CheckButton).set_pressed_no_signal(_editing)
	_reorder_hint.visible = _editing
	_settings_body.add_theme_constant_override("separation", 6 if _editing else 8)
	_update_sound_controls()
	_rebuild_order()
	_compact_layout()
	_updating = false

func _sync_slider(key: String, value: float) -> void:
	(_controls[key] as HSlider).set_value_no_signal(value)
	(_controls[key + "_value"] as Label).text = "%d%%" % roundi(value)

func _theme_changed(index: int) -> void:
	if not _updating and index >= 0 and index < THEME_IDS.size():
		draft["theme"] = THEME_IDS[index]
		_publish()

func _accent_changed(color: Color) -> void:
	if _updating:
		return
	draft["accent"] = "#" + color.to_html(false)
	_updating = true
	(_controls["accent"] as ColorPickerButton).color = color
	(_controls["accent_code"] as Label).text = str(draft["accent"]).to_upper()
	_updating = false
	_publish()

func _font_changed(value: int) -> void:
	if not _updating:
		draft["font_size"] = value
		_compact_layout()
		_publish()

func _slider_changed(value: float, key: String) -> void:
	if _updating:
		return
	draft[key] = (1.0 - value / 100.0) if key == "opacity" else value / 100.0
	(_controls[key + "_value"] as Label).text = "%d%%" % roundi(value)
	_publish()

func _toggle_changed(enabled: bool, key: String) -> void:
	if _updating:
		return
	if key == "edit_mode":
		set_edit_mode(enabled)
		return
	draft[key] = enabled
	if key == "sound_enabled":
		_update_sound_controls()
	_publish()

func _update_sound_controls() -> void:
	var enabled: bool = bool(draft.get("sound_enabled", true))
	(_controls["volume"] as HSlider).editable = enabled
	(_controls["sound_preview"] as Button).disabled = not enabled

func _ordered_ids() -> Array:
	var result: Array = []
	var requested: Array = draft.get("order", COMMAND_IDS.duplicate())
	for id_value: Variant in requested:
		var id: String = str(id_value)
		if COMMAND_IDS.has(id) and not result.has(id):
			result.append(id)
	for id: String in COMMAND_IDS:
		if not result.has(id):
			result.append(id)
	return result

func _visible_order() -> Array:
	var result: Array = []
	for id: String in _ordered_ids():
		var available: bool = true
		for command: Dictionary in _commands:
			if str(command.get("id", "")) == id:
				available = bool(command.get("visible", true))
				break
		if available:
			result.append(id)
	return result

func _rebuild_order() -> void:
	_order_generation += 1
	for tween: Tween in _order_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_order_tweens.clear()
	for child: Node in _order_box.get_children():
		_order_box.remove_child(child)
		child.queue_free()
	var order: Array = _visible_order()
	for index: int in range(order.size()):
		var id: String = str(order[index])
		var command: Dictionary = {"id": id, "title": _tr("command_" + id)}
		for candidate: Dictionary in _commands:
			if str(candidate.get("id", "")) == id:
				command = candidate
				break
		var row: PanelContainer = _row_script.new() as PanelContainer
		row.call("setup", command, _editing, index, order.size(), get_instance_id(),
			_tr("drag_command"), _tr("move_up"), _tr("move_down"))
		row.connect("move_requested", _move_to)
		row.connect("step_requested", _move_step)
		_order_box.add_child(row)

func _move_to(source_id: String, target_id: String) -> void:
	if not _editing:
		return
	var order: Array = _ordered_ids()
	var from: int = order.find(source_id)
	var to: int = order.find(target_id)
	if from < 0 or to < 0 or from == to:
		return
	order.remove_at(from)
	order.insert(to, source_id)
	_accept_order(order)

func _move_step(id: String, direction: int) -> void:
	if not _editing:
		return
	var order: Array = _ordered_ids()
	var visible_order: Array = _visible_order()
	var from: int = order.find(id)
	var visible_to: int = visible_order.find(id) + direction
	if from < 0 or visible_to < 0 or visible_to >= visible_order.size():
		return
	var to: int = order.find(visible_order[visible_to])
	order.remove_at(from)
	order.insert(to, id)
	_accept_order(order)

func _accept_order(order: Array) -> void:
	var old_positions: Dictionary = {}
	if _editing and bool(draft.get("motion", true)):
		for child: Node in _order_box.get_children():
			if child is Control:
				old_positions[str(child.name)] = (child as Control).position
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	var focus_command: String = ""
	var focus_name: String = ""
	if is_instance_valid(previous_focus) and _order_box.is_ancestor_of(previous_focus):
		focus_name = str(previous_focus.name)
		var ancestor: Node = previous_focus.get_parent()
		while ancestor != null and ancestor.get_parent() != _order_box:
			ancestor = ancestor.get_parent()
		if ancestor != null:
			focus_command = str(ancestor.name)
	draft["order"] = order.duplicate()
	_rebuild_order()
	if not old_positions.is_empty():
		call_deferred("_animate_order", _order_generation, old_positions)
	if not focus_command.is_empty():
		call_deferred("_restore_order_focus", focus_command, focus_name)
	order_changed.emit(order.duplicate())
	_publish()

func _animate_order(generation: int, old_positions: Dictionary) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if generation != _order_generation or not is_inside_tree() or not _editing:
		return
	for child: Node in _order_box.get_children():
		if not child is Control or not old_positions.has(str(child.name)):
			continue
		var row: Control = child as Control
		var destination: Vector2 = row.position
		var origin: Vector2 = old_positions[str(child.name)]
		if origin.distance_to(destination) < 1.0:
			continue
		row.position = origin
		var tween: Tween = create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(row, "position", destination, 0.18)
		_order_tweens.append(tween)

func _restore_order_focus(command_node: String, control_name: String) -> void:
	if not is_inside_tree() or not visible:
		return
	var row: Node = _order_box.get_node_or_null(NodePath(command_node))
	if row == null:
		return
	var target: Button = row.find_child(control_name, true, false) as Button
	if target == null or target.disabled:
		target = row.find_child("DragHandle", true, false) as Button
	if target != null and not target.disabled:
		target.grab_focus()

func _publish() -> void:
	preview_changed.emit(draft.duplicate(true))
