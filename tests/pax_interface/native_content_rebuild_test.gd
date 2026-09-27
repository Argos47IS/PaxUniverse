extends RefCounted
## External regression for native windows rebuilt after the HUD decorates them.
## Mirrors remove(old content) / add(new VBox) / get_child(0), without third-party code.

var _report: Dictionary = {}


func start(hud: Node) -> Dictionary:
	_report = {"checks": {}, "failures": [], "scope": "Own UI fixture only; no native dialogs, gameplay commands, settings or saves changed."}
	var isolated: bool = OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA")
	_check("isolated_profile", isolated)
	_check("hud_available", is_instance_valid(hud))
	if not isolated or not is_instance_valid(hud):
		return _finish()
	var game: PaxGame = hud.get("_game") as PaxGame
	var skin: Node = hud.get("_skin") as Node
	var motion: Node = hud.get("_motion") as Node
	_check("live_controllers_available", is_instance_valid(game) and is_instance_valid(game.main) and is_instance_valid(skin) and is_instance_valid(motion))
	if not bool(_report.checks.live_controllers_available):
		return _finish()
	var tree: SceneTree = hud.get_tree()
	var original_preferences: String = JSON.stringify(hud.get("_prefs"))
	var initial_motion: int = (motion.get("_records") as Dictionary).size()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "NativeContentRebuildQA"
	layer.layer = 128
	game.main.add_child(layer)
	var background: ColorRect = ColorRect.new()
	background.set_meta("pax_interface_skip_skin", true)
	background.color = Color.BLACK
	background.position = Vector2(360, 160)
	background.size = Vector2(260, 180)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "RebuiltNativeWindow"
	panel.position = background.position
	panel.custom_minimum_size = background.size
	panel.size = background.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var original_style: StyleBoxFlat = StyleBoxFlat.new()
	original_style.bg_color = Color("243544")
	panel.add_theme_stylebox_override("panel", original_style)
	var old_content: ScrollContainer = ScrollContainer.new()
	old_content.name = "OldNativeContent"
	panel.add_child(old_content)
	layer.add_child(panel)
	await _settle(tree)
	var panel_id: int = panel.get_instance_id()
	var records: Dictionary = skin.get("_records")
	var record: Dictionary = records.get(panel_id, {})
	var relief: Node2D = record.get("relief") as Node2D
	_check("panel_received_actual_skin_relief", is_instance_valid(relief) and relief.get_parent() == panel)
	_check("decoration_excluded_from_default_children", panel.get_child_count() == 1 and panel.get_child(0) == old_content and panel.get_child_count(true) == 2)
	if is_instance_valid(relief):
		_check("internal_relief_stays_visible_behind_parent", relief.is_visible_in_tree() and relief.show_behind_parent)
		_check("internal_relief_keeps_draw_geometry", (relief.get("_vertices") as PackedVector2Array).size() == 20 and (relief.get("_colors") as PackedColorArray).size() == 20)
	else:
		_check("internal_relief_stays_visible_behind_parent", false)
		_check("internal_relief_keeps_draw_geometry", false)
	panel.remove_child(old_content)
	old_content.queue_free()
	_check("removing_native_content_leaves_no_public_child", panel.get_child_count() == 0 and panel.get_child_count(true) == 1)
	var new_content: VBoxContainer = VBoxContainer.new()
	new_content.name = "NewNativeContent"
	panel.add_child(new_content)
	# This must work synchronously; a later reorder would be too late for the caller.
	var first_child: Node = panel.get_child(0)
	_check("immediate_first_child_is_replacement_vbox", first_child == new_content and first_child is VBoxContainer)
	var action: Button = Button.new()
	action.name = "RebuiltContentAction"
	action.text = "QA rebuilt action"
	var calls: Array[int] = [0]
	action.pressed.connect(func() -> void: calls[0] += 1)
	if first_child is VBoxContainer:
		first_child.add_child(action)
	else:
		action.queue_free()
	await _settle(tree)
	var action_valid: bool = is_instance_valid(action) and action.is_inside_tree()
	_check("native_action_attached_to_replacement_content", action_valid and action.get_parent() == new_content)
	_check("native_action_is_visible_and_skinned", action_valid and action.is_visible_in_tree() and records.has(action.get_instance_id()))
	if action_valid:
		action.pressed.emit()
	_check("rebuilt_action_callback_executes_once", calls[0] == 1)
	_check("content_rebuild_keeps_same_relief", is_instance_valid(relief) and record.get("relief") == relief and relief.get_parent() == panel)
	_check("rebuild_keeps_native_public_child_count", panel.get_child_count() == 1 and panel.get_child(0) == new_content)
	var styled: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	_check("panel_border_style_still_uses_relief_fill", styled != null and not styled.draw_center)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame: Image = tree.root.get_texture().get_image()
		var top: Color = _sample(frame, tree.root, panel, Vector2(panel.size.x * 0.75, panel.size.y * 0.30))
		var bottom: Color = _sample(frame, tree.root, panel, Vector2(panel.size.x * 0.75, panel.size.y * 0.70))
		var top_brightness: float = (top.r + top.g + top.b) / 3.0
		var bottom_brightness: float = (bottom.r + bottom.g + bottom.b) / 3.0
		_report["render_samples"] = {"top": top.to_html(), "bottom": bottom.to_html(), "brightness_difference": top_brightness - bottom_brightness}
		_check("internal_relief_renders_a_visible_gradient", top_brightness > bottom_brightness + 0.003 and bottom_brightness > 0.01)
	else:
		_check("internal_relief_renders_a_visible_gradient", false)
	# Closing overlays are decorative siblings as well and must not alter public order.
	motion.call("watch", panel)
	await _settle(tree)
	var sibling_count: int = layer.get_child_count()
	panel.hide()
	var motion_record: Dictionary = (motion.get("_records") as Dictionary).get(panel_id, {})
	var ghost_layer: CanvasLayer = motion_record.get("ghost_layer") as CanvasLayer
	if bool(motion.get("_motion")) and DisplayServer.get_name() != "headless":
		_check("closing_overlay_created_without_public_sibling", is_instance_valid(ghost_layer) and layer.get_child_count() == sibling_count and layer.get_child_count(true) == sibling_count + 1)
	else:
		_check("closing_overlay_created_without_public_sibling", layer.get_child_count() == sibling_count)
	await _settle(tree)
	_check("closing_overlay_released", motion_record.get("ghost_layer") == null and layer.get_child_count(true) == sibling_count)
	var relief_id: int = relief.get_instance_id() if is_instance_valid(relief) else 0
	layer.queue_free()
	await _settle(tree)
	_check("fixture_skin_record_removed", not records.has(panel_id))
	_check("fixture_relief_removed", relief_id == 0 or not is_instance_id_valid(relief_id))
	_check("fixture_motion_record_removed", (motion.get("_records") as Dictionary).size() == initial_motion)
	_check("appearance_preferences_unchanged", JSON.stringify(hud.get("_prefs")) == original_preferences)
	return _finish()


func _sample(frame: Image, viewport: Window, panel: Control, local: Vector2) -> Color:
	var point: Vector2 = panel.get_global_transform_with_canvas() * local
	var visible: Rect2 = viewport.get_visible_rect()
	var scale: Vector2 = Vector2(frame.get_size()) / visible.size
	var pixel: Vector2i = Vector2i((point - visible.position) * scale)
	return frame.get_pixel(clampi(pixel.x, 0, frame.get_width() - 1), clampi(pixel.y, 0, frame.get_height() - 1))


func _settle(tree: SceneTree) -> void:
	await tree.create_timer(0.22).timeout
	await tree.process_frame


func _check(name: String, condition: bool) -> void:
	(_report.checks as Dictionary)[name] = condition
	if not condition:
		(_report.failures as Array).append(name)


func _finish() -> Dictionary:
	_report["ok"] = (_report.failures as Array).is_empty()
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	return _report
