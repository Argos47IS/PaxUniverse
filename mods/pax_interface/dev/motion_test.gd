extends RefCounted
## Run inside the existing isolated live world. No process exit or saved data.

const QUADRANTS: Array[Color] = [Color(0.8, 0.1, 0.2), Color(0.1, 0.75, 0.25), Color(0.1, 0.3, 0.9), Color(0.9, 0.65, 0.1)]
var _report: Dictionary = {"checks": {}, "failures": []}


func run(mod: Node) -> Dictionary:
	_report = {"checks": {}, "failures": []}
	var tree: SceneTree = mod.get_tree()
	var motion: Node = mod.get("_motion") as Node
	var audio: Node = mod.get("_audio") as Node
	var skin: Node = mod.get("_skin") as Node
	_check("controllers_exist", is_instance_valid(motion) and is_instance_valid(audio) and is_instance_valid(skin))
	if not is_instance_valid(motion) or not is_instance_valid(audio) or not is_instance_valid(skin):
		return _finish()
	_check("isolated_live_profile", OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"))
	if not bool((_report["checks"] as Dictionary)["isolated_live_profile"]):
		return _finish()
	var root: Window = tree.root
	var old_window: Dictionary = {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect, "content_scale_factor": root.content_scale_factor}
	var old_motion: bool = bool(motion.get("_motion"))
	var old_audio: Dictionary = {"sound_enabled": audio.get("sound_enabled"), "volume": audio.get("volume")}
	var old_mouse: Vector2 = root.get_mouse_position()
	var old_skin_roots: Array = (skin.get("_roots") as Array).duplicate()
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i(1422, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.content_scale_factor = 1.0
	await _wait(tree, 0.12)

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "InterfaceMotionQA"
	layer.layer = 128
	root.add_child(layer)
	var fixture: ColorRect = ColorRect.new()
	fixture.name = "NativeTransitionProbe"
	fixture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fixture.position = Vector2(260, 180)
	fixture.size = Vector2(240, 180)
	fixture.color = Color(0.12, 0.13, 0.14)
	fixture.hide()
	layer.add_child(fixture)
	var fixture_id: int = fixture.get_instance_id()
	for index: int in range(4):
		var patch: ColorRect = ColorRect.new()
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		patch.color = QUADRANTS[index]
		patch.position = Vector2(float(index % 2) * 120.0, 90.0 if index >= 2 else 0.0)
		patch.size = Vector2(120, 90)
		fixture.add_child(patch)
	motion.call("configure", {"motion": true})
	motion.call("watch", fixture)
	var records: Dictionary = motion.get("_records")
	var panel: Control = mod.get("_panel") as Control
	_check("actual_settings_panel_watched", is_instance_valid(panel) and records.has(panel.get_instance_id()))
	var target_modulate: Color = fixture.modulate
	var target_scale: Vector2 = fixture.scale
	var target_pivot: Vector2 = fixture.pivot_offset
	var target_position: Vector2 = fixture.position
	fixture.show()
	_check("opening_starts_transparent", fixture.modulate.a < target_modulate.a)
	_check("opening_preserves_native_position", fixture.position == target_position)
	await _wait(tree, 0.23)
	_check("opening_reaches_original_alpha", fixture.modulate.is_equal_approx(target_modulate))
	_check("opening_restores_scale_and_pivot", fixture.scale.is_equal_approx(target_scale) and fixture.pivot_offset.is_equal_approx(target_pivot))
	var before_frame: Image = root.get_texture().get_image()
	_report["coordinate_system"] = {"window_pixels": str(root.size), "visible_rect": str(root.get_visible_rect()), "framebuffer_pixels": str(before_frame.get_size()), "final_transform": str(root.get_final_transform()), "window_transform": str(fixture.get_global_transform_with_canvas()), "content_scale_size": str(root.content_scale_size)}
	_check("dpi_fixture_has_real_framebuffer", before_frame.get_width() == 1920 and before_frame.get_height() == 1080)
	fixture.hide()
	var record: Dictionary = records[fixture.get_instance_id()]
	var ghost: TextureRect = record.get("ghost") as TextureRect
	_check("closing_keeps_native_window_hidden", not fixture.visible)
	_check("closing_creates_visual_only_ghost", is_instance_valid(ghost) and ghost.mouse_filter == Control.MOUSE_FILTER_IGNORE and ghost.focus_mode == Control.FOCUS_NONE)
	if is_instance_valid(ghost):
		var snapshot: Image = ghost.texture.get_image()
		_report["ghost"] = {"position": str(ghost.position), "size": str(ghost.size), "image_pixels": str(snapshot.get_size())}
		_check("ghost_dpi_geometry_matches_panel", ghost.position.distance_to(fixture.position) < 1.5 and ghost.size.distance_to(fixture.size) < 2.0)
		_check("ghost_captures_the_correct_framebuffer_region", _matches_quadrants(snapshot))
	else:
		_check("ghost_dpi_geometry_matches_panel", false)
		_check("ghost_captures_the_correct_framebuffer_region", false)
	await _wait(tree, 0.20)
	_check("closing_releases_ghost_after_160ms", record.get("ghost") == null and record.get("ghost_layer") == null)

	fixture.show()
	await _wait(tree, 0.07)
	fixture.hide()
	fixture.show()
	_check("rapid_reopen_removes_old_ghost", record.get("ghost") == null and fixture.visible)
	await _wait(tree, 0.23)
	_check("rapid_reopen_has_no_queued_transition", fixture.modulate.is_equal_approx(target_modulate) and record.get("open_tween") == null and record.get("ghost") == null)
	motion.call("configure", {"motion": false})
	fixture.hide()
	_check("motion_off_hides_without_ghost", not fixture.visible and record.get("ghost") == null)
	fixture.show()
	_check("motion_off_opens_immediately", fixture.modulate.is_equal_approx(target_modulate) and record.get("open_tween") == null)

	var button: Button = Button.new()
	button.name = "SelfHidingInputProbe"
	button.text = "QA"
	button.position = Vector2(60, 60)
	button.size = Vector2(120, 48)
	var events: Dictionary = {"presses": 0, "mouse_motion": 0, "mouse_down": 0, "mouse_up": 0, "activated": 0, "activated_null": 0}
	# Connect the native behaviour first: the skin must still sound afterwards.
	button.pressed.connect(func() -> void:
		events["presses"] = int(events["presses"]) + 1
		fixture.hide()
	)
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			events["mouse_motion"] = int(events["mouse_motion"]) + 1
		elif event is InputEventMouseButton:
			var mouse: InputEventMouseButton = event as InputEventMouseButton
			var event_key: String = "mouse_down" if mouse.pressed else "mouse_up"
			events[event_key] = int(events[event_key]) + 1
	)
	fixture.add_child(button)
	var activation_callback: Callable = func(source: BaseButton) -> void:
		events["activated"] = int(events["activated"]) + 1
		if source == null:
			events["activated_null"] = int(events["activated_null"]) + 1
	skin.connect("activated", activation_callback)
	skin.call("watch_tree", layer)
	await _wait(tree, 0.05)
	await _audio_checks(tree, audio, button)
	audio.call("configure", {"sound_enabled": true, "volume": 0.35})
	audio.call("stop_all")
	# The preceding hide/show resets BaseButton.hovering. Simulate a fresh
	# pointer entry instead of relying on the viewport's cached hovered control.
	await tree.process_frame
	_motion_event(root, Vector2(4, 4))
	await tree.process_frame
	var viewport_point: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	var window_point: Vector2 = root.get_final_transform() * viewport_point
	_report["input_coordinates"] = {"viewport": str(viewport_point), "window": str(window_point)}
	_motion_event(root, window_point)
	await tree.process_frame
	_report["input_ready"] = {"hovered": button.is_hovered(), "disabled": button.disabled, "visible": button.is_visible_in_tree(), "rect": str(button.get_global_rect())}
	_button_event(root, window_point, true)
	await tree.process_frame
	_button_event(root, window_point, false)
	await tree.process_frame
	_report["input_events"] = events.duplicate(true)
	_check("input_route_mouse_motion_reaches_button", int(events["mouse_motion"]) > 0)
	_check("input_route_down_and_up_reach_button", int(events["mouse_down"]) > 0 and int(events["mouse_up"]) > 0)
	_check("input_route_invokes_native_callback_once", int(events["presses"]) == 1 and not fixture.visible)
	_check("self_hiding_real_click_emits_one_sound", int(events["activated"]) == 1 and int(events["activated_null"]) == 1 and int(audio.get("_last_click_ms")) >= 0)
	audio.call("stop_all")
	var activations_before: int = int(events["activated"])
	button.pressed.emit()
	_check("hidden_proxy_signal_does_not_emit_sound", int(events["activated"]) == activations_before and _playing(audio) == 0)
	skin.disconnect("activated", activation_callback)
	fixture.hide()
	layer.queue_free()
	await tree.process_frame
	_check("fixture_exit_cleans_motion_registry", not records.has(fixture_id))
	skin.set("_roots", old_skin_roots)
	audio.call("stop_all")
	audio.call("configure", old_audio)
	motion.call("configure", {"motion": old_motion})
	for property: String in old_window:
		root.set(property, old_window[property])
	await _wait(tree, 0.12)
	_motion_event(root, root.get_final_transform() * old_mouse)
	_report["sound_validation"] = "Runtime voice/state assertions only; subjective comfort has not been auditioned by this test."
	return _finish()


func _audio_checks(tree: SceneTree, audio: Node, button: Button) -> void:
	audio.call("configure", {"sound_enabled": true, "volume": 0.35})
	audio.call("stop_all")
	var players: Array = audio.get("_players")
	_check("audio_has_two_single_voice_players", players.size() == 2 and (players[0] as AudioStreamPlayer).max_polyphony == 1 and (players[1] as AudioStreamPlayer).max_polyphony == 1)
	audio.call("hover", button)
	var hover_slot: int = int(audio.get("_active_slot"))
	_check("hover_starts_its_stream", hover_slot >= 0 and _playing(audio) == 1 and (players[hover_slot] as AudioStreamPlayer).stream == audio.get("_hover_stream"))
	var hover_time: int = int(audio.get("_last_hover_ms"))
	for index: int in range(40):
		audio.call("hover", button)
	_check("rapid_hover_does_not_accumulate", int(audio.get("_active_slot")) == hover_slot and int(audio.get("_last_hover_ms")) == hover_time and _playing(audio) == 1)
	audio.call("click", button)
	var click_slot: int = int(audio.get("_active_slot"))
	_check("click_takes_priority_over_hover", click_slot >= 0 and click_slot != hover_slot and (players[click_slot] as AudioStreamPlayer).stream == audio.get("_click_stream") and _playing(audio) <= 2)
	audio.call("hover", button)
	_check("hover_is_suppressed_during_click", int(audio.get("_active_slot")) == click_slot)
	var click_time: int = int(audio.get("_last_click_ms"))
	for index: int in range(40):
		audio.call("click", button)
	_check("duplicate_click_signals_do_not_accumulate", int(audio.get("_active_slot")) == click_slot and int(audio.get("_last_click_ms")) == click_time and _playing(audio) <= 2)
	await tree.create_timer(0.035).timeout
	_check("click_releases_the_hover_tail", hover_slot >= 0 and not (players[hover_slot] as AudioStreamPlayer).playing and _playing(audio) <= 1)
	audio.call("configure", {"sound_enabled": false, "volume": 0.35})
	audio.call("hover", button)
	audio.call("click", button)
	_check("mute_stops_and_blocks_all_voices", _playing(audio) == 0)
	audio.call("configure", {"sound_enabled": true, "volume": 0.0})
	audio.call("preview")
	_check("zero_volume_is_silent", _playing(audio) == 0)
	audio.call("configure", {"sound_enabled": true, "volume": 0.17})
	audio.call("click", button)
	var volume_slot: int = int(audio.get("_active_slot"))
	_check("volume_controls_actual_player_gain", volume_slot >= 0 and is_equal_approx(db_to_linear((players[volume_slot] as AudioStreamPlayer).volume_db), 0.17))
	audio.call("stop_all")
	button.disabled = true
	audio.call("hover", button)
	audio.call("click", button)
	_check("disabled_button_is_silent", _playing(audio) == 0)
	button.disabled = false
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio.call("hover", button)
	audio.call("click", button)
	_check("pointer_ignoring_button_is_silent", _playing(audio) == 0)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.hide()
	audio.call("hover", button)
	audio.call("click", button)
	_check("hidden_button_is_silent", _playing(audio) == 0)
	button.show()
	audio.call("stop_all")


func _matches_quadrants(image: Image) -> bool:
	var samples: Array = []
	var matches: bool = true
	for index: int in range(4):
		var fraction: Vector2 = Vector2(0.25 + float(index % 2) * 0.5, 0.75 if index >= 2 else 0.25)
		var color: Color = image.get_pixel(int(float(image.get_width()) * fraction.x), int(float(image.get_height()) * fraction.y))
		var expected: Color = QUADRANTS[index]
		var error: float = maxf(absf(color.r - expected.r), maxf(absf(color.g - expected.g), absf(color.b - expected.b)))
		matches = matches and error < 0.03
		samples.append({"actual": color.to_html(), "expected": expected.to_html(), "error": error})
	_report["ghost_pixel_samples"] = samples
	return matches


func _playing(audio: Node) -> int:
	var count: int = 0
	for player: AudioStreamPlayer in audio.get("_players"):
		if player.playing:
			count += 1
	return count


func _motion_event(root: Window, point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button_event(root: Window, point: Vector2, down: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _wait(tree: SceneTree, duration: float) -> void:
	await tree.create_timer(duration).timeout
	await tree.process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _check(name: String, condition: bool) -> void:
	(_report["checks"] as Dictionary)[name] = condition
	if not condition:
		(_report["failures"] as Array).append(name)


func _finish() -> Dictionary:
	_report["ok"] = (_report["failures"] as Array).is_empty()
	_report["assertion_count"] = (_report["checks"] as Dictionary).size()
	return _report
