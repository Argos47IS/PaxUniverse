extends Button

signal move_requested(source_id: String, target_id: String)
var command_id: String
var owner_token: int
var editing: bool = false
var caption: Label
var badge: Label
var grip: Label
var content: HBoxContainer
var content_icon: TextureRect
var _signature: String = ""

func build_content(texture: Texture2D) -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.offset_left = 8
	center.offset_right = -8
	add_child(center)
	content = HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	center.add_child(content)
	grip = Label.new()
	grip.text = "⠿"
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_theme_color_override("font_color", Color("7d93ab"))
	grip.hide()
	content.add_child(grip)
	var image: TextureRect = TextureRect.new()
	content_icon = image
	image.texture = texture
	image.custom_minimum_size = Vector2(20, 20)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(image)
	caption = Label.new()
	caption.name = "Caption"
	caption.add_theme_font_size_override("font_size", 13)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(caption)
	badge = Label.new()
	badge.name = "CountBadge"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 11)
	badge.custom_minimum_size = Vector2(21, 21)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle: StyleBoxFlat = StyleBoxFlat.new()
	circle.bg_color = Color("187c89")
	circle.set_corner_radius_all(11)
	circle.content_margin_left = 5
	circle.content_margin_right = 5
	badge.add_theme_stylebox_override("normal", circle)
	content.add_child(badge)
	content.minimum_size_changed.connect(_fit_minimum)
	resized.connect(queue_redraw)
	call_deferred("_fit_minimum")

func _fit_minimum() -> void:
	if is_instance_valid(content):
		custom_minimum_size.x = maxf(56.0, content.get_combined_minimum_size().x + 20.0)

func set_content(title: String, count: String, labels: bool, edit: bool) -> void:
	var signature: String = title + count + str(labels) + str(edit)
	if signature == _signature:
		return
	_signature = signature
	caption.text = title
	caption.visible = labels
	badge.text = count
	badge.visible = not count.is_empty()
	grip.visible = edit
	editing = edit
	_fit_minimum()
	queue_redraw()

func set_content_icon(texture: Texture2D) -> void:
	if is_instance_valid(content_icon) and content_icon.texture != texture:
		content_icon.texture = texture

func _draw() -> void:
	if get_index() > 0:
		draw_line(Vector2(0, 10), Vector2(0, size.y - 10), Color(0.32, 0.43, 0.54, 0.52), 1)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not editing:
		return null
	var label: Label = Label.new()
	label.text = tooltip_text
	set_drag_preview(label)
	return {"pax_interface_order": owner_token, "id": command_id, "title": tooltip_text}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return editing and data is Dictionary and int(data.get("pax_interface_order", -1)) == owner_token and str(data.get("id", "")) != command_id

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position, data):
		move_requested.emit(str(data["id"]), command_id)
