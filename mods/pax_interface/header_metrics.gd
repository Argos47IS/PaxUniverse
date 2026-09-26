extends HBoxContainer
## Uses the native society labels/ratings. Draw only when their values change.

class Meter extends Control:
	var filled: int = 0
	var tint: Color = Color("e46e68")
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(47, 9)
	func _draw() -> void:
		var start: float = floorf((size.x - 47.0) * 0.5)
		for index: int in range(5):
			var rect: Rect2 = Rect2(start + index * 10.0, 1, 7, 6)
			draw_rect(rect, Color(tint, 0.9) if index < filled else Color(tint, 0.14))
			draw_rect(rect, Color(tint.lightened(0.22), 0.7 if index < filled else 0.38), false, 1.0)
			if index < filled:
				draw_line(rect.position, rect.position + Vector2(6, 0), Color.WHITE * Color(1, 1, 1, 0.22))

var source: HBoxContainer
var cells: Dictionary = {}

func configure_layout(wide: bool, font_ratio: float) -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 14 if wide else 8)
	for record: Dictionary in cells.values():
		(record.column as Control).size_flags_horizontal = Control.SIZE_FILL
		(record.title as Label).add_theme_font_size_override("font_size", roundi((12.0 if wide else 10.0) * font_ratio))

func setup(native_stars: HBoxContainer) -> void:
	source = native_stars
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_constant_override("separation", 8)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sync()

func sync() -> void:
	if not is_instance_valid(source):
		return
	visible = source.visible
	for native_cell: Node in source.get_children():
		var label: Label = native_cell.find_child("подпись", true, false) as Label
		var stars: Label = native_cell.find_child("звёзды", true, false) as Label
		if label == null or stars == null:
			continue
		var key: String = str(native_cell.name)
		if not cells.has(key):
			var column: VBoxContainer = VBoxContainer.new()
			column.name = "Rating_" + key
			column.size_flags_horizontal = Control.SIZE_FILL
			column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			column.add_theme_constant_override("separation", 3)
			add_child(column)
			var title: Label = Label.new()
			title.name = "Caption"
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 10)
			title.add_theme_color_override("font_color", Color("b8c4d3"))
			column.add_child(title)
			var meter: Meter = Meter.new()
			column.add_child(meter)
			cells[key] = {"column": column, "title": title, "meter": meter, "last": ""}
		var record: Dictionary = cells[key]
		var signature: String = label.text + stars.text + (native_cell as Control).tooltip_text
		if record.last == signature:
			continue
		record.last = signature
		(record.title as Label).text = label.text
		(record.column as Control).tooltip_text = (native_cell as Control).tooltip_text
		var meter: Meter = record.meter as Meter
		meter.filled = stars.text.count("★")
		meter.tint = Color("68c488") if meter.filled >= 4 else (Color("e9c452") if meter.filled >= 2 else Color("e6736d"))
		meter.queue_redraw()
