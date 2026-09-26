extends PanelContainer
## A command row. Only its handle initiates a drag; all rows accept a drop.

signal move_requested(source_id: String, target_id: String)
signal step_requested(command_id: String, direction: int)

class DragHandle extends Button:
	var row: Control

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if disabled or not is_instance_valid(row):
			return null
		var payload: Dictionary = row.call("drag_payload")
		if payload.is_empty():
			return null
		var preview: PanelContainer = PanelContainer.new()
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("142837")
		style.border_color = Color("279cab")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		style.shadow_color = Color(0, 0, 0, 0.35)
		style.shadow_size = 8
		preview.add_theme_stylebox_override("panel", style)
		var label: Label = Label.new()
		label.text = str(payload.get("title", ""))
		label.add_theme_color_override("font_color", Color("ecf4ff"))
		label.add_theme_font_size_override("font_size", 16)
		preview.add_child(label)
		set_drag_preview(preview)
		return payload

var command_id: String = ""
var command_title: String = ""
var editing: bool = false
var owner_token: int = 0
var handle: Button
var up_button: Button
var down_button: Button
var _step_box: VBoxContainer

func setup(command: Dictionary, allow_edit: bool, index: int, count: int,
		token: int, drag_hint: String, up_hint: String, down_hint: String) -> void:
	command_id = str(command.get("id", ""))
	command_title = str(command.get("title", command_id))
	owner_token = token
	name = "Order_" + command_id
	custom_minimum_size = Vector2(0, 38)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = command_title
	var panel_style: StyleBoxEmpty = StyleBoxEmpty.new()
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 5
	panel_style.content_margin_top = 3
	panel_style.content_margin_bottom = 3
	add_theme_stylebox_override("panel", panel_style)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var grip: DragHandle = DragHandle.new()
	grip.row = self
	grip.text = "⠿"
	grip.add_theme_font_size_override("font_size", 14)
	grip.tooltip_text = drag_hint
	grip.custom_minimum_size = Vector2(18, 28)
	grip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_compact_button(grip)
	grip.mouse_default_cursor_shape = Control.CURSOR_MOVE
	grip.name = "DragHandle"
	row.add_child(grip)
	handle = grip
	grip.set_drag_forwarding(grip._get_drag_data, _can_drop_data, _drop_data)
	if command.get("icon") is Texture2D:
		var icon: TextureRect = TextureRect.new()
		icon.texture = command["icon"] as Texture2D
		icon.custom_minimum_size = Vector2(17, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var label: Label = Label.new()
	label.text = command_title
	label.add_theme_font_size_override("font_size", 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_step_box = VBoxContainer.new()
	_step_box.name = "ReorderArrows"
	_step_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_step_box.add_theme_constant_override("separation", 0)
	row.add_child(_step_box)
	up_button = Button.new()
	up_button.name = "MoveUp"
	up_button.text = "↑"
	up_button.tooltip_text = up_hint
	up_button.custom_minimum_size = Vector2(20, 15)
	up_button.add_theme_font_size_override("font_size", 12)
	_compact_button(up_button)
	up_button.pressed.connect(func() -> void: step_requested.emit(command_id, -1))
	_step_box.add_child(up_button)
	up_button.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
	down_button = Button.new()
	down_button.name = "MoveDown"
	down_button.text = "↓"
	down_button.tooltip_text = down_hint
	down_button.custom_minimum_size = Vector2(20, 15)
	down_button.add_theme_font_size_override("font_size", 12)
	_compact_button(down_button)
	down_button.pressed.connect(func() -> void: step_requested.emit(command_id, 1))
	_step_box.add_child(down_button)
	down_button.set_drag_forwarding(Callable(), _can_drop_data, _drop_data)
	set_editing(allow_edit, index, count)

func _compact_button(button: BaseButton) -> void:
	for key: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBoxEmpty = StyleBoxEmpty.new()
		style.content_margin_left = 1
		style.content_margin_right = 1
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(key, style)

func set_editing(enabled: bool, index: int, count: int) -> void:
	editing = enabled
	handle.disabled = not editing
	up_button.disabled = not editing or index <= 0
	down_button.disabled = not editing or index >= count - 1
	up_button.visible = editing
	down_button.visible = editing
	_step_box.visible = editing
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE if editing else Control.CURSOR_ARROW

func drag_payload() -> Dictionary:
	if not editing:
		return {}
	return {"pax_interface_order": owner_token, "id": command_id, "title": command_title}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not editing or not data is Dictionary:
		return false
	var payload: Dictionary = data
	return int(payload.get("pax_interface_order", -1)) == owner_token \
		and str(payload.get("id", "")) != command_id

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position, data):
		var payload: Dictionary = data
		move_requested.emit(str(payload["id"]), command_id)
