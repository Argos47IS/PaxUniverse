extends Node2D
## Background-only relief. Draws behind the native StyleBox, text and icons.
## Geometry is cached on resize; interaction updates vertex colours only.

var _host: WeakRef
var _vertices: PackedVector2Array = PackedVector2Array()
var _colors: PackedColorArray = PackedColorArray()
var _extent: Vector2 = Vector2.ZERO
var _radius: float = 4.0
var _fill: Color = Color("142230")
var _accent: Color = Color("279cab")
var _blend: Vector3 = Vector3.ZERO
var _role: StringName = &"tool"
var _disabled: bool = false
var _configured: bool = false


func setup(host: Control) -> void:
	name = "PaxInterfaceRelief"
	show_behind_parent = true
	set_meta("pax_interface_skip_skin", true)
	_host = weakref(host)
	host.resized.connect(_resize)
	_resize()


func paint(fill: Color, accent: Color, blend: Vector3, role: StringName, radius: float, disabled: bool = false) -> void:
	# Main may replace an idle button's native StyleBox. Reinstalling our style
	# must not recolour/requeue the unchanged relief. Resizing has its own path.
	if _configured and _fill == fill and _accent == accent and _blend == blend and _role == role and _radius == radius and _disabled == disabled:
		return
	_configured = true
	var geometry_changed: bool = not is_equal_approx(_radius, radius)
	_fill = fill
	_accent = accent
	_blend = blend
	_role = role
	_disabled = disabled
	_radius = radius
	if geometry_changed:
		_rebuild_geometry()
	else:
		_recolor()
	queue_redraw()


func _resize() -> void:
	var host: Control = _host.get_ref() as Control if _host != null else null
	if is_instance_valid(host):
		_extent = host.size
		_rebuild_geometry()
		queue_redraw()


func _rebuild_geometry() -> void:
	_vertices.resize(20)
	_colors.resize(20)
	var inset: float = 0.65
	var radius: float = clampf(_radius - inset, 0.1, maxf(0.1, minf(_extent.x, _extent.y) * 0.5 - inset))
	var centers: Array[Vector2] = [Vector2(radius + inset, radius + inset), Vector2(_extent.x - radius - inset, radius + inset), Vector2(_extent.x - radius - inset, _extent.y - radius - inset), Vector2(radius + inset, _extent.y - radius - inset)]
	for corner: int in range(4):
		for step: int in range(5):
			var angle: float = PI + float(corner) * PI * 0.5 + float(step) * PI * 0.125
			_vertices[corner * 5 + step] = centers[corner] + Vector2(cos(angle), sin(angle)) * radius
	_recolor()


func _recolor() -> void:
	var top_lift: float = 0.075
	var bottom_shade: float = 0.16
	if _role in [&"header", &"chrome", &"dock", &"card"]:
		top_lift = 0.035
		bottom_shade = 0.10
	elif _role == &"command":
		top_lift = 0.055
		bottom_shade = 0.13
	top_lift *= 1.0 - 0.65 * _blend.y
	if _disabled:
		top_lift *= 0.5
	var top: Color = _fill.lightened(top_lift)
	var bottom: Color = _fill.darkened(bottom_shade)
	top.a = _fill.a
	bottom.a = _fill.a
	for index: int in range(_vertices.size()):
		var vertical: float = clampf(_vertices[index].y / maxf(_extent.y, 1.0), 0.0, 1.0)
		_colors[index] = top.lerp(bottom, vertical)


func _draw() -> void:
	if _extent.x < 3.0 or _extent.y < 3.0 or _vertices.size() != 20:
		return
	draw_polygon(_vertices, _colors)
	var inset: float = maxf(4.0, _radius + 1.0)
	if _extent.x <= inset * 2.0:
		return
	var strength: float = 0.10 if _role in [&"header", &"chrome", &"dock", &"card"] else 0.16
	strength *= (1.0 - 0.75 * _blend.y) * (0.5 if _disabled else 1.0)
	var edge: Color = Color(0.55, 0.72, 0.86, strength * _fill.a)
	draw_line(Vector2(inset, 1.6), Vector2(_extent.x - inset, 1.6), edge, 1.0, true)
	draw_line(Vector2(inset, _extent.y - 1.6), Vector2(_extent.x - inset, _extent.y - 1.6), Color(0.015, 0.025, 0.035, 0.45 * _fill.a), 1.0, true)
	if _blend.z > 0.001 or _blend.x > 0.001:
		var glow: Color = _accent
		glow.a = (0.42 * _blend.z + 0.10 * _blend.x) * _fill.a
		draw_line(Vector2(inset, _extent.y - 2.8), Vector2(_extent.x - inset, _extent.y - 2.8), glow, 1.0, true)


func _exit_tree() -> void:
	var host: Control = _host.get_ref() as Control if _host != null else null
	if is_instance_valid(host) and host.resized.is_connected(_resize):
		host.resized.disconnect(_resize)
