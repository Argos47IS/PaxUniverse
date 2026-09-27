extends RefCounted
## External regression: a real extra button may execute a command without any window.
## Run only in the isolated QA world. No gameplay callbacks, settings or saves changed.

var _report: Dictionary = {}


func start(hud: Node) -> Dictionary:
	_report = {"checks": {}, "failures": [], "scope": "Own UI fixture and counter callback only; no game commands, messages or saves."}
	var isolated: bool = OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA")
	_check("isolated_profile", isolated)
	_check("hud_available", is_instance_valid(hud))
	if not isolated or not is_instance_valid(hud):
		return _finish()
	var bar: HBoxContainer = hud.get("_native_buttons") as HBoxContainer
	var root: Control = hud.get("_root") as Control
	var skin: Node = hud.get("_skin") as Node
	var motion: Node = hud.get("_motion") as Node
	_check("live_components_available", is_instance_valid(bar) and is_instance_valid(root) and is_instance_valid(skin) and is_instance_valid(motion))
	if not bool(_report.checks.live_components_available):
		return _finish()
	var tree: SceneTree = hud.get_tree()
	var old_preferences: String = JSON.stringify(hud.get("_prefs"))
	var extras: Dictionary = hud.get("_extras")
	var initial_extras: int = extras.size()
	var initial_bindings: int = (skin.get("_window_bindings") as Dictionary).size()
	var initial_motion: int = (motion.get("_records") as Dictionary).size()
	var calls: Array[int] = [0]
	var native: Button = Button.new()
	native.name = "QAOptionalWindowNative"
	native.text = "QA optional window"
	native.pressed.connect(func() -> void: calls[0] += 1)
	var native_id: int = native.get_instance_id()
	bar.add_child(native)
	hud.call("_discover_extras")
	hud.call("_sync_buttons")
	await _settle(tree)
	var record: Dictionary = extras.get(native_id, {})
	var proxy: Button = record.get("proxy") as Button
	_check("windowless_native_is_discovered", is_instance_valid(proxy) and record.get("native") == native)
	if not is_instance_valid(proxy):
		native.queue_free()
		await _settle(tree)
		return _finish()
	var proxy_id: int = proxy.get_instance_id()
	_check("windowless_proxy_is_visible", proxy.is_visible_in_tree() and proxy.text == native.text and not proxy.disabled)
	_check("windowless_buttons_keep_absent_metadata", not native.has_meta("win") and not proxy.has_meta("win"))
	_check("windowless_does_not_bind_a_window", (skin.get("_window_bindings") as Dictionary).size() == initial_bindings)
	proxy.pressed.emit()
	_check("proxy_executes_original_callback_once", calls[0] == 1)
	for iteration: int in range(24):
		hud.call("_discover_extras")
		hud.call("_sync_buttons")
	await _settle(tree)
	_check("repeated_discovery_keeps_one_proxy", extras.size() == initial_extras + 1 and (extras[native_id] as Dictionary).get("proxy") == proxy)
	_check("repeated_windowless_sync_does_not_execute_command", calls[0] == 1 and not proxy.has_meta("win"))
	_check("repeated_windowless_sync_keeps_bindings_bounded", (skin.get("_window_bindings") as Dictionary).size() == initial_bindings)
	var first: Panel = Panel.new()
	first.name = "QAOptionalWindowFirst"
	first.hide()
	root.add_child(first)
	var second: Panel = Panel.new()
	second.name = "QAOptionalWindowSecond"
	second.hide()
	root.add_child(second)
	await _settle(tree)
	var bounded: bool = true
	var stable_connections: bool = true
	var exact_targets: bool = true
	var metadata_cleared: bool = true
	var callbacks_preserved: bool = true
	for cycle: int in range(4):
		for window: Control in [first, second]:
			native.set_meta("win", window)
			hud.call("_sync_buttons")
			await _settle(tree)
			var window_id: int = window.get_instance_id()
			var bindings: Dictionary = skin.get("_window_bindings")
			var binding: Dictionary = bindings.get(window_id, {})
			var members: Dictionary = binding.get("buttons", {})
			exact_targets = exact_targets and proxy.has_meta("win") and proxy.get_meta("win") == window and members.has(native_id) and members.has(proxy_id) and members.size() == 2
			bounded = bounded and bindings.size() == initial_bindings + 1
			var before: int = window.get_signal_connection_list("visibility_changed").size()
			for iteration: int in range(24):
				hud.call("_sync_buttons")
			await _settle(tree)
			stable_connections = stable_connections and window.get_signal_connection_list("visibility_changed").size() == before
			callbacks_preserved = callbacks_preserved and native.get_signal_connection_list("pressed").size() >= 1 and calls[0] == 1
			native.remove_meta("win")
			hud.call("_sync_buttons")
			await _settle(tree)
			metadata_cleared = metadata_cleared and not proxy.has_meta("win") and _linked_id(skin, native_id) == 0 and _linked_id(skin, proxy_id) == 0
			bounded = bounded and (skin.get("_window_bindings") as Dictionary).size() == initial_bindings
	_check("late_window_assignment_tracks_native_and_proxy", exact_targets)
	_check("window_removal_clears_proxy_and_skin_targets", metadata_cleared)
	_check("four_rebinding_cycles_keep_one_shared_skin_binding", bounded)
	_check("repeated_sync_does_not_duplicate_visibility_connections", stable_connections)
	_check("rebinding_does_not_execute_or_remove_native_callback", callbacks_preserved)
	proxy.pressed.emit()
	_check("windowless_callback_still_executes_once_after_rebinding", calls[0] == 2)
	native.disabled = true
	hud.call("_sync_buttons")
	proxy.pressed.emit()
	_check("disabled_extra_does_not_execute_callback", proxy.disabled and calls[0] == 2)
	_report["cycles"] = 4
	_report["sync_calls_per_state"] = 24
	_report["callback_count"] = calls[0]
	# Remove only the fixture's bookkeeping. Normal world lifecycle handles real extras.
	extras.erase(native_id)
	proxy.queue_free()
	native.queue_free()
	first.queue_free()
	second.queue_free()
	await _settle(tree)
	_check("fixture_extra_removed", extras.size() == initial_extras and not extras.has(native_id))
	_check("fixture_skin_bindings_removed", (skin.get("_window_bindings") as Dictionary).size() == initial_bindings)
	_check("fixture_button_records_removed", not (skin.get("_buttons") as Dictionary).has(native_id) and not (skin.get("_buttons") as Dictionary).has(proxy_id))
	_check("fixture_motion_records_removed", (motion.get("_records") as Dictionary).size() == initial_motion)
	_check("appearance_preferences_unchanged", JSON.stringify(hud.get("_prefs")) == old_preferences)
	return _finish()


func _linked_id(skin: Node, id: int) -> int:
	var records: Dictionary = skin.get("_buttons")
	return int((records.get(id, {}) as Dictionary).get("linked_id", -1))


func _settle(tree: SceneTree) -> void:
	await tree.create_timer(0.20).timeout
	await tree.process_frame


func _check(name: String, condition: bool) -> void:
	(_report.checks as Dictionary)[name] = condition
	if not condition:
		(_report.failures as Array).append(name)


func _finish() -> Dictionary:
	_report["ok"] = (_report.failures as Array).is_empty()
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	return _report
