extends Node
## Visual-only transitions. Native visibility and command handling stay native.

const OPEN_SECONDS: float = 0.20
const CLOSE_SECONDS: float = 0.16
const TRAVEL_PIXELS: float = 8.0

var _motion: bool = true
var _records: Dictionary = {}
var _restoring: bool = false


func configure(settings: Dictionary) -> void:
	_motion = bool(settings.get("motion", true))
	if not _motion:
		for key: Variant in _records.keys():
			var record: Dictionary = _records[key]
			_cancel_open(record)
			_remove_ghost(record)


func watch(window: Control) -> void:
	if not is_instance_valid(window) or _records.has(window.get_instance_id()):
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var key: int = window.get_instance_id()
	var visibility_callback: Callable = _visibility_changed.bind(key)
	var exit_callback: Callable = _window_exiting.bind(key)
	_records[key] = {
		"window": window,
		"modulate": window.modulate,
		"scale": window.scale,
		"pivot": window.pivot_offset,
		"shown": window.is_visible_in_tree(),
		"shown_frame": Engine.get_frames_drawn(),
		"generation": 0,
		"open_tween": null,
		"ghost_tween": null,
		"ghost": null,
		"ghost_layer": null,
		"visibility_callback": visibility_callback,
		"exit_callback": exit_callback,
	}
	window.visibility_changed.connect(visibility_callback)
	window.tree_exiting.connect(exit_callback)


func restore() -> void:
	_restoring = true
	for key: Variant in _records.keys():
		var record: Dictionary = _records[key]
		_cancel_open(record)
		_remove_ghost(record)
		_disconnect(record)
	_records.clear()
	set_process(false)
	_restoring = false


func _visibility_changed(key: int) -> void:
	if _restoring or not _records.has(key):
		return
	var record: Dictionary = _records[key]
	var window: Control = record["window"] as Control
	if not is_instance_valid(window):
		return
	var shown: bool = window.is_visible_in_tree()
	var was_shown: bool = bool(record["shown"])
	record["shown"] = shown
	if shown == was_shown:
		return
	if shown:
		record["shown_frame"] = Engine.get_frames_drawn()
		_remove_ghost(record)
		_cancel_open(record)
		if _motion:
			_open(key, record)
	else:
		# A hidden ancestor or an exiting world must not leave a floating panel.
		if _motion and not window.visible and _parent_visible(window):
			_close(key, record)
		else:
			_remove_ghost(record)
		_cancel_open(record)


func _open(key: int, record: Dictionary) -> void:
	var window: Control = record["window"] as Control
	# Capture any legitimate layout/scale changes made while the window was shut.
	record["modulate"] = window.modulate
	record["scale"] = window.scale
	record["pivot"] = window.pivot_offset
	record["generation"] = int(record["generation"]) + 1
	var target_modulate: Color = record["modulate"]
	var target_scale: Vector2 = record["scale"]
	var extent: float = maxf(window.size.x, window.size.y)
	var start_factor: float = 1.0 - clampf(TRAVEL_PIXELS / maxf(extent, 1.0), 0.0, 0.035)
	# Changing the pivot of an already scaled native window would shift its
	# final position, so preserve that pivot and animate around it instead.
	window.pivot_offset = Vector2(window.size.x, 0.0) if target_scale.is_equal_approx(Vector2.ONE) else Vector2(record["pivot"])
	window.scale = target_scale * start_factor
	window.modulate = Color(target_modulate.r, target_modulate.g, target_modulate.b, 0.0)
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(window, "modulate", target_modulate, OPEN_SECONDS)
	tween.tween_property(window, "scale", target_scale, OPEN_SECONDS)
	tween.chain().tween_callback(_finish_open.bind(key, int(record["generation"])))
	record["open_tween"] = tween


func _finish_open(key: int, generation: int) -> void:
	if not _records.has(key):
		return
	var record: Dictionary = _records[key]
	if int(record["generation"]) != generation:
		return
	record["open_tween"] = null
	_restore_visuals(record)


func _cancel_open(record: Dictionary) -> void:
	var tween: Tween = record.get("open_tween") as Tween
	if tween != null:
		if tween.is_valid():
			tween.kill()
		record["open_tween"] = null
		_restore_visuals(record)


func _restore_visuals(record: Dictionary) -> void:
	var window: Control = record["window"] as Control
	if is_instance_valid(window):
		window.modulate = record["modulate"]
		window.scale = record["scale"]
		window.pivot_offset = record["pivot"]


func _close(key: int, record: Dictionary) -> void:
	_remove_ghost(record)
	var window: Control = record["window"] as Control
	if DisplayServer.get_name() == "headless" or Engine.get_frames_drawn() <= int(record["shown_frame"]):
		return
	var viewport: Viewport = window.get_viewport()
	if viewport == null:
		return
	var visible_rect: Rect2 = viewport.get_visible_rect()
	var capture_rect: Rect2 = _capture_rect(window, visible_rect)
	if capture_rect.size.x < 2.0 or capture_rect.size.y < 2.0:
		return
	var viewport_texture: ViewportTexture = viewport.get_texture()
	if viewport_texture == null:
		return
	# Capture immediately in visibility_changed, before the next frame redraws.
	# No file is written; the ghost contains the previous composited framebuffer.
	var frame: Image = viewport_texture.get_image()
	if frame == null or frame.is_empty() or visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
		return
	var pixels_per_unit: Vector2 = Vector2(frame.get_size()) / visible_rect.size
	var pixel_start: Vector2i = Vector2i(((capture_rect.position - visible_rect.position) * pixels_per_unit).floor())
	var pixel_end: Vector2i = Vector2i(((capture_rect.end - visible_rect.position) * pixels_per_unit).ceil())
	var pixel_rect: Rect2i = Rect2i(pixel_start, pixel_end - pixel_start).intersection(Rect2i(Vector2i.ZERO, frame.get_size()))
	if pixel_rect.size.x <= 0 or pixel_rect.size.y <= 0:
		return
	var crop: Image = frame.get_region(pixel_rect)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "InterfaceWindowExit"
	layer.layer = _canvas_layer(window) + 1
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# The transient visual overlay is not a native sibling window or content node.
	window.get_parent().add_child(layer, false, Node.INTERNAL_MODE_BACK)
	var ghost: TextureRect = TextureRect.new()
	ghost.name = "WindowSnapshot"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.focus_mode = Control.FOCUS_NONE
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ghost.texture = ImageTexture.create_from_image(crop)
	ghost.position = visible_rect.position + Vector2(pixel_rect.position) / pixels_per_unit
	ghost.size = Vector2(pixel_rect.size) / pixels_per_unit
	layer.add_child(ghost)
	record["ghost"] = ghost
	record["ghost_layer"] = layer
	var tween: Tween = create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ghost, "modulate:a", 0.0, CLOSE_SECONDS)
	tween.tween_property(ghost, "position:y", ghost.position.y + TRAVEL_PIXELS, CLOSE_SECONDS)
	tween.chain().tween_callback(_finish_ghost.bind(key, ghost.get_instance_id()))
	record["ghost_tween"] = tween


func _capture_rect(window: Control, viewport_rect: Rect2) -> Rect2:
	var transform: Transform2D = window.get_global_transform_with_canvas()
	# Native windows are axis-aligned. Skip rotated/skewed custom windows rather
	# than copy pixels beyond a polygonal clip and cover neighbouring controls.
	if not _axis_aligned(transform):
		return Rect2()
	var result: Rect2 = _transformed_rect(window, transform).intersection(viewport_rect)
	var ancestor: Node = window.get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is Control:
			var control: Control = ancestor as Control
			if control.clip_contents:
				var clip_transform: Transform2D = control.get_global_transform_with_canvas()
				if not _axis_aligned(clip_transform):
					return Rect2()
				result = result.intersection(_transformed_rect(control, clip_transform))
		ancestor = ancestor.get_parent()
	return result


func _transformed_rect(control: Control, transform: Transform2D) -> Rect2:
	var result: Rect2 = Rect2(transform * Vector2.ZERO, Vector2.ZERO)
	result = result.expand(transform * Vector2(control.size.x, 0.0))
	result = result.expand(transform * control.size)
	return result.expand(transform * Vector2(0.0, control.size.y))


func _axis_aligned(transform: Transform2D) -> bool:
	return absf(transform.x.y) < 0.001 and absf(transform.y.x) < 0.001


func _canvas_layer(window: Control) -> int:
	var ancestor: Node = window.get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasLayer:
			return (ancestor as CanvasLayer).layer
		ancestor = ancestor.get_parent()
	return 0


func _parent_visible(window: Control) -> bool:
	if not window.is_inside_tree() or window.is_queued_for_deletion():
		return false
	var ancestor: Node = window.get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasItem and not (ancestor as CanvasItem).is_visible_in_tree():
			return false
		if ancestor is CanvasLayer and not (ancestor as CanvasLayer).visible:
			return false
		ancestor = ancestor.get_parent()
	return true


func _finish_ghost(key: int, instance_id: int) -> void:
	if not _records.has(key):
		return
	var record: Dictionary = _records[key]
	var ghost: TextureRect = record.get("ghost") as TextureRect
	if is_instance_valid(ghost) and ghost.get_instance_id() == instance_id:
		_remove_ghost(record)


func _remove_ghost(record: Dictionary) -> void:
	var tween: Tween = record.get("ghost_tween") as Tween
	if tween != null and tween.is_valid():
		tween.kill()
	record["ghost_tween"] = null
	var layer: CanvasLayer = record.get("ghost_layer") as CanvasLayer
	if is_instance_valid(layer):
		layer.visible = false
		layer.queue_free()
	record["ghost"] = null
	record["ghost_layer"] = null


func _window_exiting(key: int) -> void:
	if not _records.has(key):
		return
	var record: Dictionary = _records[key]
	_cancel_open(record)
	_remove_ghost(record)
	_disconnect(record)
	_records.erase(key)
	if _records.is_empty():
		set_process(false)


func _disconnect(record: Dictionary) -> void:
	var window: Control = record["window"] as Control
	if not is_instance_valid(window):
		return
	var visibility_callback: Callable = record["visibility_callback"]
	var exit_callback: Callable = record["exit_callback"]
	if window.visibility_changed.is_connected(visibility_callback):
		window.visibility_changed.disconnect(visibility_callback)
	if window.tree_exiting.is_connected(exit_callback):
		window.tree_exiting.disconnect(exit_callback)


func _process(_delta: float) -> void:
	for key: Variant in _records.keys():
		var record: Dictionary = _records[key]
		if record.get("ghost_layer") == null:
			continue
		var window: Control = record["window"] as Control
		if not is_instance_valid(window) or not _parent_visible(window):
			_remove_ghost(record)


func _exit_tree() -> void:
	restore()
