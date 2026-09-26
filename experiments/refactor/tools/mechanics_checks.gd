extends RefCounted
## External experiment harness. It must never be distributed as a game mod.
## Run after performance sampling: save/load replaces Main and Pax.game.

var _report: Dictionary = {}


func start(main: Node, game: PaxGame) -> Dictionary:
	_report = {"checks": {}, "failures": [], "skipped": {}, "timings_ms": {}, "scope": "Fresh offline experiment world only; no user campaigns or external AI."}
	var isolated: bool = OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Refactor QA")
	_check("isolated_profile", isolated)
	_check("world_available", is_instance_valid(main) and is_instance_valid(game))
	if not isolated or not is_instance_valid(main) or not is_instance_valid(game):
		return _finish()
	var tree: SceneTree = main.get_tree()
	game.set_speed(0)
	print("MECHANICS_CHECKPOINT begin")
	_check_world(main, game)
	await _check_native_windows(main, tree)
	_report.skipped["external_ai"] = "External AI providers are disabled; online generation, service latency and generated strategy quality are not tested."
	_report.skipped["war_and_peace_actions"] = "Method names are reflected, but command preconditions and authoritative war/peace state invariants are not documented. No guessed diplomatic commands are sent."
	_report.skipped["long_campaign"] = "Only a bounded time progression smoke test is performed; multi-year economic and military stability is not established."
	var idle: bool = await _check_time(main, game, tree)
	if not idle:
		_report.skipped["save_load"] = "The native time pipeline did not become idle before the bounded timeout. Main was not freed or replaced while its work could still be suspended."
		_report.skipped["character_and_chronicle"] = "No fixture mutations while the native time pipeline is busy."
		_report.skipped["role_ui"] = "No role switching while the native time pipeline is busy."
		return _finish()
	var character_name: String = _check_character(game)
	_check_chronicle(game)
	await _check_save_load(main, game, tree, character_name)
	# Role changes can reconnect native handlers. Test them last, after normal
	# windows, time progression and save/load, in the current restored Main.
	if is_instance_valid(Pax.game) and is_instance_valid(Pax.game.main):
		await _check_roles(Pax.game.main, tree)
	print("MECHANICS_CHECKPOINT complete")
	return _finish()


func _check_world(main: Node, game: PaxGame) -> void:
	var factions: Array = game.factions()
	var bodies: PackedStringArray = game.body_names()
	_report["world"] = {"faction_count": factions.size(), "body_count": bodies.size(), "earth_population": game.people("Земля"), "role": str(main.get("роль_игрока")), "day": game.day(), "date": game.date()}
	_check("factions_present", not factions.is_empty())
	_check("earth_present", bodies.has("Земля"))
	var named: int = 0
	for value: Variant in factions:
		if value is Dictionary and not str((value as Dictionary).get("имя", "")).is_empty():
			named += 1
	_report.world["named_factions"] = named
	_check("faction_names_present", named > 0)
	if main.has_method("_заполнить_дипломатию"):
		var started: int = Time.get_ticks_usec()
		main.call("_заполнить_дипломатию")
		_report.timings_ms["diplomacy_population"] = _elapsed(started)
		var window: Control = main.get("окно_дипломатии") as Control
		var list: Control = main.get("список_дипломатии") as Control
		_check("diplomacy_controls_exist", is_instance_valid(window) and is_instance_valid(list))
		if is_instance_valid(list):
			_report.world["diplomacy_child_count"] = list.get_child_count()
	else:
		_report.skipped["diplomacy_view"] = "Main._заполнить_дипломатию is unavailable in this build."


func _check_roles(main: Node, tree: SceneTree) -> void:
	print("MECHANICS_CHECKPOINT roles")
	if not main.has_method("_интерфейс_по_роли"):
		_report.skipped["role_ui"] = "Native role UI method is unavailable."
		return
	var original: String = str(main.get("роль_игрока"))
	var roles: Dictionary = {}
	var native_buttons: Array[Dictionary] = []
	for key: String in ["кнопка_державы", "кнопка_законов", "кнопка_добычи"]:
		var button: Button = main.get(key) as Button
		if is_instance_valid(button):
			native_buttons.append({"node": button, "text": button.text, "icon": button.icon, "tooltip": button.tooltip_text, "has_win": button.has_meta("win"), "win": button.get_meta("win") if button.has_meta("win") else null})
	for role: String in ["человек", "организация", "страна"]:
		main.set("роль_игрока", role)
		main.call("_интерфейс_по_роли")
		await tree.process_frame
		var captions: Dictionary = {}
		for key: String in ["кнопка_державы", "кнопка_законов", "кнопка_добычи"]:
			var button: Button = main.get(key) as Button
			# Pax Interface intentionally uses an icon plus tooltip in compact mode.
			var identifiable: bool = is_instance_valid(button) and (not button.text.is_empty() or (button.icon != null and not button.tooltip_text.is_empty()))
			_check("role_" + role + "_" + key, identifiable and not button.get_signal_connection_list("pressed").is_empty())
			if is_instance_valid(button):
				captions[key] = button.text
		roles[role] = captions
	main.set("роль_игрока", original)
	main.call("_интерфейс_по_роли")
	# Native role setup is normally selected before Main starts. Its country
	# branch need not undo a previous organization/person presentation.
	for record: Dictionary in native_buttons:
		var button: Button = record.node as Button
		button.text = str(record.text)
		button.icon = record.icon as Texture2D
		button.tooltip_text = str(record.tooltip)
		if bool(record.has_win):
			button.set_meta("win", record.win)
		elif button.has_meta("win"):
			button.remove_meta("win")
	await tree.process_frame
	_check("role_restored", str(main.get("роль_игрока")) == original)
	_report["role_captions"] = roles


func _check_native_windows(main: Node, tree: SceneTree) -> void:
	print("MECHANICS_CHECKPOINT native_windows")
	# Existing native window toggles only; do not execute their game commands.
	for key: String in ["кнопка_законов", "кнопка_добычи"]:
		var button: Button = main.get(key) as Button
		if not is_instance_valid(button) or not button.has_meta("win"):
			_report.skipped["window_" + key] = "Native button does not expose its win metadata."
			continue
		var window: Control = button.get_meta("win") as Control
		if not is_instance_valid(window):
			_report.skipped["window_" + key] = "Native window was not created."
			continue
		window.hide()
		button.pressed.emit()
		await tree.process_frame
		_check("window_" + key + "_opens", window.is_visible_in_tree())
		button.pressed.emit()
		await tree.process_frame
		_check("window_" + key + "_closes", not window.visible)


func _check_time(main: Node, game: PaxGame, tree: SceneTree) -> bool:
	print("MECHANICS_CHECKPOINT time")
	var observation: Dictionary = {"signals": 0, "days_reported": 0}
	var listener: Callable = func(source: PaxGame, _from_day: int, days: int) -> void:
		if source == game:
			observation["signals"] = int(observation["signals"]) + 1
			observation["days_reported"] = int(observation["days_reported"]) + days
	var can_observe: bool = Pax.has_signal("days_passed")
	if can_observe:
		Pax.connect("days_passed", listener)
	var before: int = game.day()
	var started: int = Time.get_ticks_usec()
	game.set_speed(1)
	var native_start: Dictionary = {"auto": bool(main.get("автоигра")), "speed": int(main.get("скорость_наблюдения")), "time_jump": bool(main.get("идёт_перемотка"))}
	while game.day() <= before and Time.get_ticks_usec() - started < 12000000:
		await tree.process_frame
	game.set_speed(0)
	var first_advance: int = game.day()
	_report.timings_ms["first_observed_time_step"] = _elapsed(started)
	var settle_started: int = Time.get_ticks_usec()
	var completion_ui: Dictionary = {"pressed": false, "buttons": []}
	var completion_presses: Array[Dictionary] = []
	var last_inspection: int = 0
	# Pausing stops new work; a native multi-frame time jump must first finish.
	while (bool(main.get("идёт_перемотка")) or bool(main.get("провайдер_ждёт_ответа"))) and Time.get_ticks_usec() - settle_started < 12000000:
		if int(observation["signals"]) > 0 and not bool(main.get("провайдер_ждёт_ответа")) and completion_presses.size() < 32 and Time.get_ticks_usec() - last_inspection > 250000:
			completion_ui = _finish_native_time_dialog(main)
			if bool(completion_ui["pressed"]):
				completion_presses.append({"text": completion_ui.get("pressed_text", ""), "handler": completion_ui.get("native_handler", ""), "elapsed_ms": _elapsed(settle_started)})
			last_inspection = Time.get_ticks_usec()
		await tree.process_frame
	game.set_speed(0)
	var after: int = game.day()
	var stopped: int = after
	await tree.create_timer(0.6).timeout
	var idle: bool = not bool(main.get("идёт_перемотка")) and not bool(main.get("провайдер_ждёт_ответа"))
	_check("time_advances", after > before)
	_check("time_pauses", not bool(main.get("автоигра")) and game.day() == stopped)
	_check("time_pipeline_idle", idle)
	if can_observe:
		_check("time_signal_emitted", int(observation["signals"]) > 0)
		Pax.disconnect("days_passed", listener)
	else:
		_report.skipped["days_passed_signal"] = "Pax.days_passed is unavailable."
	_report.timings_ms["time_progression_and_pause_check"] = _elapsed(started)
	completion_ui["pressed_count"] = completion_presses.size()
	completion_ui["press_limit"] = 32
	completion_ui["presses"] = completion_presses
	_report["time"] = {"from_day": before, "first_advance_day": first_advance, "to_day": after, "signals": observation["signals"], "reported_days": observation["days_reported"], "requested_speed": 1, "native_start_state": native_start, "native_final_state": _pipeline_state(main), "completion_ui": completion_ui, "safe_to_reload": idle, "timeout_seconds": 12, "pause_settle_ms": _elapsed(settle_started), "pause_policy": "Request native speed 1, stop after the first observed day, finish any completed report through its identified native callback, then verify 600 ms with no further days."}
	return idle


func _finish_native_time_dialog(main: Node) -> Dictionary:
	var result: Dictionary = {"pressed": false, "buttons": []}
	for key: String in ["окно_перемотки", "окно_отчёта"]:
		var window: Node = main.get(key) as Node
		if not is_instance_valid(window):
			continue
		for child: Node in window.find_children("*", "BaseButton", true, false):
			var button: BaseButton = child as BaseButton
			if not button.is_visible_in_tree() or button.disabled:
				continue
			var descriptions: Array[Dictionary] = []
			var is_completion: bool = false
			var matched_handler: String = ""
			var text: String = (button as Button).text if button is Button else ""
			for connection: Dictionary in button.get_signal_connection_list("pressed"):
				var callback: Callable = connection.callable
				var owner: Object = callback.get_object()
				var owned_by_window: bool = owner == window or (owner is Node and window.is_ancestor_of(owner as Node))
				descriptions.append({"method": str(callback.get_method()), "bound_to_main": owner == main, "owned_by_window": owned_by_window})
				if callback.get_object() == main and str(callback.get_method()) == "_перемотка_кончилась":
					is_completion = true
					matched_handler = "Main._перемотка_кончилась"
				elif key == "окно_перемотки" and owned_by_window and str(callback.get_method()) == "_дальше" and (text.strip_edges().begins_with("Дальше") or text.strip_edges() == "Конец"):
					is_completion = true
					matched_handler = "Перемотка._дальше"
			(result["buttons"] as Array).append({"window": key, "text": text, "callbacks": descriptions})
			if is_completion:
				button.pressed.emit()
				result["pressed"] = true
				result["pressed_text"] = text
				result["native_handler"] = matched_handler
				return result
	return result


func _pipeline_state(main: Node) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["автоигра", "скорость_наблюдения", "идёт_перемотка", "провайдер_ждёт_ответа", "_ждём_последствий", "_сбой_итогов", "мотаем_до_события", "дней_перемотки"]:
		if _has_property(main, key):
			result[key] = main.get(key)
	for key: String in ["окно_отчёта", "окно_дилеммы", "окно_перемотки"]:
		var node: Node = main.get(key) as Node
		if node is CanvasItem:
			result[key + "_visible"] = (node as CanvasItem).is_visible_in_tree()
	return result


func _check_character(game: PaxGame) -> String:
	print("MECHANICS_CHECKPOINT character")
	if game.people("Земля") <= 0.0:
		_report.skipped["character"] = "The test world has no Earth population; add_character requires inhabitants."
		return ""
	var character_name: String = "Проверка Refactor " + str(Time.get_ticks_msec())
	var info: Dictionary = {"имя": character_name, "кто": "инженер", "лор": "Вымышленный персонаж отдельной тестовой партии.", "характер": "спокойный", "возраст": 35, "чем_занят": "проверяет оборудование", "хочет": "закончить проверку"}
	var started: int = Time.get_ticks_usec()
	var added: bool = game.add_character("Земля", info, "", false)
	_report.timings_ms["add_character"] = _elapsed(started)
	_check("character_created", added)
	_check("character_lookup", game.has_character(character_name))
	return character_name if added else ""


func _check_chronicle(game: PaxGame) -> void:
	var world: Object = game.world as Object
	if not is_instance_valid(world) or not _has_property(world, "хроника"):
		_report.skipped["chronicle"] = "World chronicle collection is unavailable."
		return
	var before: int = (world.get("хроника") as Array).size()
	game.chronicle("Земля", "Проверка записи истории в отдельной экспериментальной партии.", "neutral", 2)
	var after: int = (world.get("хроника") as Array).size()
	_check("chronicle_entry_added", after > before)
	_report["chronicle"] = {"before": before, "after": after}


func _check_save_load(main: Node, game: PaxGame, tree: SceneTree, character_name: String) -> void:
	print("MECHANICS_CHECKPOINT save")
	if not main.has_method("_сохранить_игру") or not main.has_method("_загрузить_игру"):
		_report.skipped["save_load"] = "Native Main save/load methods are unavailable."
		return
	var save_script: Script = load("res://scripts/Сейв.gd") as Script
	if save_script == null or not save_script.has_method("есть") or not save_script.has_method("загрузить"):
		_report.skipped["save_load"] = "The native save storage contract is unavailable."
		return
	# Main creates several services with slot-bound paths (notably Память).
	# Changing only Main.слот would split a campaign across two directories.
	var slot: String = str(main.get("слот"))
	if not slot.begins_with("refactor_baseline_") or not slot.trim_prefix("refactor_baseline_").is_valid_int():
		_report.skipped["save_load"] = "Caller did not provide the documented fresh refactor_baseline_<ticks> slot; save refused."
		return
	var memory_fixture: Dictionary = _prepare_memory_fixture(game)
	var expected: Dictionary = _snapshot(game, main)
	if not memory_fixture.is_empty():
		expected["pax_memory_fixture"] = memory_fixture["record"].duplicate(true)
	var signals: Dictionary = {"saving": 0, "loaded": 0, "loaded_events": []}
	var on_saving: Callable = func(_game: PaxGame, _state: Dictionary) -> void: signals["saving"] = int(signals["saving"]) + 1
	var on_loaded: Callable = func(_game: PaxGame, _state: Dictionary) -> void:
		signals["loaded"] = int(signals["loaded"]) + 1
		signals["loaded_events"].append({"game_id": _game.get_instance_id(), "main_id": _game.main.get_instance_id() if is_instance_valid(_game.main) else 0, "state_keys": _state.keys(), "memory_mod_payload": _state.get("pax_memory", null)})
	Pax.connect("saving", on_saving)
	Pax.connect("loaded", on_loaded)
	var started: int = Time.get_ticks_usec()
	await main.call("_сохранить_игру")
	_report.timings_ms["native_save"] = _elapsed(started)
	var exists: bool = bool(save_script.call("есть", slot))
	_check("save_created", exists)
	if not exists:
		Pax.disconnect("saving", on_saving)
		Pax.disconnect("loaded", on_loaded)
		return
	started = Time.get_ticks_usec()
	var serialized: Dictionary = save_script.call("загрузить", slot) as Dictionary
	_report.timings_ms["native_storage_read"] = _elapsed(started)
	_check("save_storage_readable", not serialized.is_empty())
	_report["save_load"] = {"slot": slot, "expected": expected, "storage_top_level_keys": serialized.keys(), "saving_signals": signals["saving"], "load_mode": "new Main with existing slot; normal native initialization"}
	_report.save_load["storage_size"] = _measure_save_storage(save_script, slot)
	if not memory_fixture.is_empty():
		_check_serialized_memory(serialized, memory_fixture)
	var main_script: Script = main.get_script() as Script
	var restored: Node = main_script.new() as Node
	_check("fresh_main_has_load_method", restored.has_method("_загрузить_игру"))
	if not restored.has_method("_загрузить_игру"):
		restored.free()
		Pax.disconnect("saving", on_saving)
		Pax.disconnect("loaded", on_loaded)
		return
	restored.set("слот", slot)
	print("MECHANICS_CHECKPOINT replace_main")
	tree.current_scene = null
	main.queue_free()
	await tree.process_frame
	started = Time.get_ticks_usec()
	tree.root.add_child(restored)
	tree.current_scene = restored
	await tree.process_frame
	var wait_started: int = Time.get_ticks_usec()
	while (not is_instance_valid(Pax.game) or Pax.game.main != restored) and Time.get_ticks_usec() - wait_started < 10000000:
		await tree.process_frame
	_report.timings_ms["fresh_main_load_and_world_ready"] = _elapsed(started)
	var attached: bool = is_instance_valid(Pax.game) and Pax.game.main == restored
	_check("saved_world_attaches_to_new_main", attached)
	if attached:
		var loaded_game: PaxGame = Pax.game
		loaded_game.set_speed(0)
		var actual: Dictionary = _snapshot(loaded_game, restored)
		_report.save_load["actual"] = actual
		for key: String in ["day", "date", "role", "faction_names", "body_names"]:
			_check("save_restores_" + key, actual[key] == expected[key])
		if not character_name.is_empty():
			_check("save_restores_character", loaded_game.has_character(character_name))
		else:
			_report.skipped["save_character"] = "No successfully created character fixture."
		if not memory_fixture.is_empty():
			_check_restored_memory(loaded_game, memory_fixture)
	_report.save_load["loaded_signals"] = signals["loaded"]
	_report.save_load["loaded_events"] = signals["loaded_events"]
	_check("native_saving_signal", int(signals["saving"]) > 0)
	_check("native_loaded_signal", int(signals["loaded"]) > 0)
	Pax.disconnect("saving", on_saving)
	Pax.disconnect("loaded", on_loaded)
	print("MECHANICS_CHECKPOINT loaded")


func _prepare_memory_fixture(game: PaxGame) -> Dictionary:
	if not Pax.has_mod("pax_memory"):
		return {}
	var mod: Node = Pax.get_mod("pax_memory")
	var available: bool = is_instance_valid(mod) and mod.has_method("remember") and mod.has_method("context_for") and mod.has_method("_save_state")
	_check("memory_adapter_available", available)
	if not available:
		return {}
	var store: Object = mod.get("_store") as Object
	var populated: bool = is_instance_valid(store) and store.has_method("count") and int(store.call("count")) > 0
	_check("memory_world_evidence_present", populated)
	if not populated:
		return {}
	var marker: String = "qa_roundtrip_" + str(Time.get_ticks_usec())
	var entities: Array = ["Земля", marker]
	var record: Dictionary = {"id": marker, "timestamp": game.day(), "entities": entities, "type": "qa_fixture", "importance": 0.9, "confidence": 1.0, "source": "qa_fixture", "text": "Изолированная проверка сохранения памяти: " + marker, "tags": ["roundtrip"]}
	var added: Dictionary = mod.call("remember", record) as Dictionary
	_check("memory_roundtrip_fixture_added", bool(added.get("ok", false)))
	if not bool(added.get("ok", false)):
		return {}
	var state: Dictionary = mod.call("_save_state", game) as Dictionary
	var stored: Dictionary = _memory_record(state, marker)
	_check("memory_fixture_exported_before_save", not stored.is_empty())
	var context: Dictionary = mod.call("context_for", marker, entities, game.day(), 1200) as Dictionary
	_check("memory_fixture_retrievable_before_save", str(context.get("text", "")).contains(marker) and (context.get("selected_ids", []) as Array).has(marker))
	_report["memory_save_load"] = {"fixture_id": marker, "fixture_source": "qa_fixture", "records_before_save": int(store.call("count")), "expected_record": stored.duplicate(true)}
	return {"id": marker, "entities": entities, "record": stored.duplicate(true)}


func _memory_record(state: Dictionary, id: String) -> Dictionary:
	var memory: Variant = state.get("memory")
	if not memory is Dictionary:
		return {}
	var records: Variant = (memory as Dictionary).get("records")
	if not records is Array:
		return {}
	for value: Variant in records:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == id:
			return (value as Dictionary).duplicate(true)
	return {}


func _check_serialized_memory(serialized: Dictionary, fixture: Dictionary) -> void:
	var mods_state: Variant = serialized.get("моды")
	_report.memory_save_load["serialized_mods_type"] = type_string(typeof(mods_state))
	if not mods_state is Dictionary or not (mods_state as Dictionary).get("pax_memory") is Dictionary:
		_report.skipped["serialized_memory_layout"] = "Native save does not expose a dictionary at моды.pax_memory; no alternative layout was guessed. The new-Main roundtrip is checked independently."
		return
	var state: Dictionary = (mods_state as Dictionary)["pax_memory"] as Dictionary
	var record: Dictionary = _memory_record(state, str(fixture["id"]))
	_report.memory_save_load["serialized_record"] = record.duplicate(true)
	_report.memory_save_load["serialized_json_equal"] = JSON.stringify(record) == JSON.stringify(fixture["record"])
	_report.memory_save_load["serialized_field_types"] = {}
	for key: String in record:
		_report.memory_save_load["serialized_field_types"][key] = [type_string(typeof(record[key])), type_string(typeof((fixture["record"] as Dictionary).get(key)))]
	# JSON has a single number type. The native reader returns 1.0 for an in-memory
	# timestamp of 1; compare every field after the same JSON normalization.
	_check("memory_fixture_written_in_native_save", not record.is_empty() and _json_equal(record, fixture["record"]))


func _check_restored_memory(game: PaxGame, fixture: Dictionary) -> void:
	var mod: Node = Pax.get_mod("pax_memory")
	var available: bool = is_instance_valid(mod) and mod.has_method("_save_state") and mod.has_method("context_for")
	_check("memory_adapter_after_load", available)
	if not available:
		return
	var state: Dictionary = mod.call("_save_state", game) as Dictionary
	var record: Dictionary = _memory_record(state, str(fixture["id"]))
	_check("memory_fixture_restores_exact_record", not record.is_empty() and record == fixture["record"])
	var context: Dictionary = mod.call("context_for", str(fixture["id"]), fixture["entities"], game.day(), 1200) as Dictionary
	_check("memory_fixture_retrievable_after_load", str(context.get("text", "")).contains(str(fixture["id"])) and (context.get("selected_ids", []) as Array).has(str(fixture["id"])))
	var memory: Dictionary = state.get("memory", {}) as Dictionary
	_report.memory_save_load["records_after_load"] = (memory.get("records", []) as Array).size()
	_report.memory_save_load["actual_record"] = record
	_report.memory_save_load["adapter_lifecycle_trace"] = (mod.get("_lifecycle_trace") as Array).duplicate(true)


func _json_equal(first: Variant, second: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(first)) == JSON.parse_string(JSON.stringify(second))


func _measure_save_storage(save_script: Script, slot: String) -> Dictionary:
	if not save_script.has_method("папка"):
		return {"measured": false, "reason": "Native save directory method is unavailable."}
	var directory: String = ProjectSettings.globalize_path(str(save_script.call("папка", slot))).replace("\\", "/").simplify_path().trim_suffix("/")
	var profile: String = OS.get_user_data_dir().replace("\\", "/").simplify_path().trim_suffix("/")
	if not profile.ends_with("/Pax Universe Refactor QA") or not directory.begins_with(profile + "/") or directory.get_file() != slot:
		return {"measured": false, "reason": "Native save directory is outside the verified QA slot."}
	var totals: Dictionary = {"measured": true, "file_count": 0, "total_bytes": 0, "world_json_bytes": 0, "skipped_links": 0, "unreadable": 0}
	_measure_directory(directory, totals)
	return totals


func _measure_directory(path: String, totals: Dictionary) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		totals["unreadable"] = int(totals["unreadable"]) + 1
		return
	for name: String in directory.get_files():
		if directory.is_link(name):
			totals["skipped_links"] = int(totals["skipped_links"]) + 1
			continue
		var file: FileAccess = FileAccess.open(path.path_join(name), FileAccess.READ)
		if file == null:
			totals["unreadable"] = int(totals["unreadable"]) + 1
			continue
		var bytes: int = file.get_length()
		file.close()
		totals["file_count"] = int(totals["file_count"]) + 1
		totals["total_bytes"] = int(totals["total_bytes"]) + bytes
		if name == "мир.json":
			totals["world_json_bytes"] = int(totals["world_json_bytes"]) + bytes
	for name: String in directory.get_directories():
		if directory.is_link(name):
			totals["skipped_links"] = int(totals["skipped_links"]) + 1
			continue
		_measure_directory(path.path_join(name), totals)


func _snapshot(game: PaxGame, main: Node) -> Dictionary:
	var names: Array[String] = []
	for value: Variant in game.factions():
		if value is Dictionary:
			names.append(str((value as Dictionary).get("имя", "")))
	names.sort()
	var bodies: PackedStringArray = game.body_names()
	bodies.sort()
	return {"day": game.day(), "date": game.date().duplicate(true), "role": str(main.get("роль_игрока")), "faction_names": names, "body_names": bodies}


func _has_property(object: Object, name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if str(property.name) == name:
			return true
	return false


func _elapsed(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _check(name: String, passed: bool) -> void:
	_report.checks[name] = passed
	if not passed:
		(_report.failures as Array).append(name)
		push_warning("MECHANICS_CHECK_FAILED " + name)


func _finish() -> Dictionary:
	_report["ok"] = (_report.failures as Array).is_empty()
	_report["assertion_count"] = (_report.checks as Dictionary).size()
	return _report
