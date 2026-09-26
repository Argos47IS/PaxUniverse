extends Node
## End-to-end native assistant checks in a fresh, isolated QA world.
## The only network destination is local Ollama. Native dumps stay in .local.

const LOCAL_URL: String = "http://127.0.0.1:11434/v1"
const MODEL: String = "qwen3.5:4b"
const RESPONSE_SIGNALS: Array[String] = ["готово", "событие_готово", "ответ_собеседника", "человек_готов", "ответ_помощника", "итоги_готовы", "канал_готов", "туннель_ошибка"]

var _output: String = ""
var _main: Node
var _provider: Node
var _memory: Node
var _response: Dictionary = {}
var _received: bool = false
var _request_error: String = ""
var _saved_connections: Array[Dictionary] = []
var _report: Dictionary = {"checks": {}, "failures": [], "cases": [],
	"network_policy": "loopback Ollama only", "model": MODEL,
	"scope": "Native assistant, actual memory mod and one validated celestial-body camera action; no province-accuracy claim"}
var _private: Dictionary = {"cases": [], "notice": "Private local evidence; do not publish native prompts, schemas or raw responses."}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	_output = OS.get_environment("PAX_REFACTOR_OUTPUT").replace("\\", "/")
	if not profile.ends_with("/Pax Universe Refactor QA") or not _output.is_absolute_path() or not _output.contains("/.local/"):
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_report["version"] = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
	_report["engine"] = str(Engine.get_version_info().string)
	await get_tree().create_timer(1.0).timeout
	Pax.call("включить_моды")
	await get_tree().process_frame
	_main = load("res://scripts/Main.gd").new()
	_main.set("слот", "refactor_ai_integration_" + str(int(Time.get_unix_time_from_system() * 1000)))
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
		await get_tree().process_frame
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await get_tree().process_frame
	_check("fresh_world_created", is_instance_valid(Pax.game))
	if not is_instance_valid(Pax.game):
		_finish()
		return
	Pax.game.set_speed(0)
	_provider = _main.get("provider") as Node
	if is_instance_valid(_provider):
		_report["reasoning_property"] = _reasoning_property_metadata()
	_memory = Pax.get_mod("pax_memory") as Node
	var hooked: bool = is_instance_valid(_memory) and bool(_memory.get("_hooked"))
	_check("actual_memory_mod_hooked", hooked)
	if not hooked or not is_instance_valid(_provider):
		_finish()
		return
	_check("memory_owns_native_status_wrapper", _provider.get("статус_стороны") == Callable(_memory, "_status_with_memory"))
	_provider.set("base_url", LOCAL_URL)
	_provider.set("model", MODEL)
	_provider.set("api_key", "ollama")
	_provider.set("настройки_закреплены", true)
	_provider.set("ожидание_сек", 60.0)
	_provider.call("_применить_таймауты")
	var local_ready: bool = str(_provider.get("base_url")) == LOCAL_URL and str(_provider.get("model")) == MODEL and bool(_provider.call("подключён"))
	_check("native_provider_uses_local_qwen", local_ready)
	if not local_ready:
		_finish()
		return
	_disconnect_consumers_except_memory()
	_provider.connect("ответ_помощника", Callable(self, "_assistant_response"))
	_provider.connect("туннель_ошибка", Callable(self, "_provider_error"))
	var memory_listener: Callable = Callable(_memory, "_observe_response").bind("ответ_помощника")
	_check("memory_response_observer_stays_connected", _provider.is_connected("ответ_помощника", memory_listener))
	var actual_date: Dictionary = Pax.game.date()
	var date_result: Dictionary = await _ask("current_date", "Какая текущая дата в игре? Ответь цифрами в формате ДД.ММ.ГГГГ. Никаких действий и приказов не нужно.")
	var date_answer: String = str(_response.get("ответ", ""))
	var date_pattern: RegEx = RegEx.new()
	date_pattern.compile("(?<![0-9])0?%d[./-]0?%d[./-]%d(?![0-9])" % [int(actual_date.get("day", -1)), int(actual_date.get("month", -1)), int(actual_date.get("year", -1))])
	_check("current_date_matches_game_components", bool(date_result.get("received", false)) and date_pattern.search(date_answer) != null)
	_check("date_response_has_no_actions", _no_actions(_response))
	_report["expected_date"] = actual_date
	if not bool(date_result.get("received", false)):
		_finish()
		return
	var entities: Array = _memory.call("_scope_entities")
	var remembered: Dictionary = _memory.call("remember", {"timestamp": Pax.game.day(), "entities": entities,
		"type": "qa_fixture", "fact_key": "qa_control_number", "importance": 1.0, "confidence": 1.0,
		"source": "game_event", "text": "Контрольный номер испытания: 7319. Это синтетические данные QA, а не событие игрового мира.", "tags": ["qa"]})
	_check("explicit_synthetic_qa_fact_added", bool(remembered.get("ok", false)))
	var memory_result: Dictionary = await _ask("memory_number", "Какой контрольный номер испытания указан в дополнительной памяти QA? Назови его цифрами. Если записи нет, скажи, что номер неизвестен. Никаких действий и приказов.")
	var number_pattern: RegEx = RegEx.new()
	number_pattern.compile("(?<![0-9])7319(?![0-9])")
	_check("model_reads_control_number_from_mod_memory", bool(memory_result.get("received", false)) and number_pattern.search(str(_response.get("ответ", ""))) != null)
	_check("memory_response_has_no_actions", _no_actions(_response))
	var selection: Dictionary = _memory.get("_last_selection")
	_check("qa_record_was_actually_selected", (selection.get("selected_ids", []) as Array).has(str(remembered.get("id", ""))))
	_check("qa_number_present_in_native_request_body", bool(memory_result.get("qa_number_in_body", false)))
	if not bool(memory_result.get("received", false)):
		_finish()
		return
	var moon_result: Dictionary = await _ask("show_moon", "Покажи небесное тело Луна: переведи к нему камеру. Только показ, никаких приказов, перелётов и изменений мира.")
	var moon_response: Dictionary = _response.duplicate(true)
	var safe_show: bool = bool(moon_result.get("received", false)) and bool(moon_result.get("native_schema", false)) and _safe_moon_show(moon_response)
	_check("moon_response_is_validated_show_only", safe_show)
	_report["camera_action_applied"] = false
	if safe_show:
		# Native consumers are still disconnected, so this is the only application.
		_main.call("_ответ_помощника", moon_response)
		_report["camera_action_applied"] = true
		var deadline: int = Time.get_ticks_msec() + 5000
		while Pax.game.focused_body() != "Луна" and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	_check("native_camera_targets_moon", safe_show and Pax.game.focused_body() == "Луна")
	_report["focused_body_after_show"] = Pax.game.focused_body()
	_report["memory_records_after_responses"] = int((_memory.get("_store") as RefCounted).call("count"))
	_finish()


func _ask(case_id: String, input: String) -> Dictionary:
	_response = {}
	_received = false
	_request_error = ""
	var folder: String = _output.path_join("native-dumps").path_join(case_id)
	DirAccess.make_dir_recursive_absolute(folder)
	_provider.set("папка_дампа", folder)
	var calls_before: int = int(_memory.get("context_calls"))
	var started: int = Time.get_ticks_usec()
	_main.call("_спросить_помощника", input)
	var deadline: int = Time.get_ticks_msec() + 65000
	while not _received and _request_error.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var elapsed_ms: float = (Time.get_ticks_usec() - started) / 1000.0
	var evidence: Dictionary = _read_native_evidence(folder, input)
	var summary: Dictionary = {"id": case_id, "received": _received, "elapsed_ms": elapsed_ms,
		"context_callback_calls": int(_memory.get("context_calls")) - calls_before,
		"native_schema": bool(evidence.get("native_schema", false)),
		"memory_marker_in_body": bool(evidence.get("memory_marker_in_body", false)),
		"qa_number_in_body": bool(evidence.get("qa_number_in_body", false)),
		"body_memory_marker_count": int(evidence.get("body_memory_marker_count", 0)),
		"request_input_in_body": bool(evidence.get("request_input_in_body", false)),
		"loopback_request": bool(evidence.get("loopback_request", false)),
		"context_addition_chars": int(_memory.get("_last_context_chars")),
		"schema_errors": evidence.get("schema_errors", []), "transport_error": not _request_error.is_empty()}
	_report["cases"].append(summary)
	_private["cases"].append({"id": case_id, "input": input, "native_response": _response.duplicate(true), "transport_error": _request_error, "evidence": evidence})
	_check(case_id + "_response_received", _received and _request_error.is_empty())
	_check(case_id + "_native_schema", bool(summary["native_schema"]))
	_check(case_id + "_actual_native_memory_context", int(summary["context_callback_calls"]) > 0 and bool(summary["memory_marker_in_body"]) and int(summary["body_memory_marker_count"]) == 1 and int(summary["context_addition_chars"]) <= 2400)
	_check(case_id + "_loopback_request", bool(summary["loopback_request"]))
	_check(case_id + "_native_request_contains_case_input", bool(summary["request_input_in_body"]))
	return summary


func _read_native_evidence(folder: String, input: String) -> Dictionary:
	var evidence: Dictionary = {"native_schema": false, "schema_errors": [], "memory_marker_in_body": false, "qa_number_in_body": false, "loopback_request": false}
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return evidence
	var request: Dictionary = {}
	var answer: Dictionary = {}
	for name: String in directory.get_files():
		if not name.ends_with(".json"):
			continue
		var wrapper: Dictionary = _dictionary(FileAccess.get_file_as_string(folder.path_join(name)))
		if wrapper.has("url"):
			request = wrapper
		elif wrapper.has("код"):
			answer = wrapper
	var body: Dictionary = _dictionary(request.get("тело", {}))
	var body_text: String = JSON.stringify(body)
	evidence["memory_marker_in_body"] = body_text.contains("<PAX_MEMORY>")
	evidence["body_memory_marker_count"] = body_text.count("<PAX_MEMORY>")
	evidence["qa_number_in_body"] = body_text.contains("7319")
	evidence["request_input_in_body"] = body_text.contains(input)
	evidence["loopback_request"] = str(request.get("url", "")).begins_with("http://127.0.0.1:11434/") and str(body.get("model", "")) == MODEL
	evidence["request_chars"] = body_text.length()
	var envelope: Dictionary = _dictionary(answer.get("тело", {}))
	var message: Dictionary = _dictionary(envelope.get("message", {}))
	var raw_response: Dictionary = _dictionary(message.get("content", ""))
	var schema: Dictionary = _dictionary(body.get("format", {}))
	var errors: Array[String] = []
	if schema.is_empty() or raw_response.is_empty() or int(answer.get("код", 0)) != 200:
		errors.append("native_schema_or_successful_raw_response_absent")
	else:
		_validate_schema(raw_response, schema, "response", errors)
	evidence["schema_errors"] = errors
	evidence["native_schema"] = errors.is_empty()
	evidence["raw_response"] = raw_response
	evidence["native_schema_definition"] = schema
	evidence["token_usage"] = {"prompt_eval_count": envelope.get("prompt_eval_count", null), "eval_count": envelope.get("eval_count", null)}
	return evidence


func _validate_schema(value: Variant, schema: Dictionary, path: String, errors: Array[String]) -> void:
	var kind: String = str(schema.get("type", ""))
	var valid_type: bool = true
	match kind:
		"object": valid_type = value is Dictionary
		"array": valid_type = value is Array
		"string": valid_type = value is String
		"boolean": valid_type = value is bool
		"number": valid_type = value is int or value is float
		"integer": valid_type = (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))
		"null": valid_type = value == null
		"": pass
		_: valid_type = false
	if not valid_type:
		errors.append(path + ": expected " + kind)
		return
	if schema.has("enum") and schema["enum"] is Array and not (schema["enum"] as Array).has(value):
		errors.append(path + ": outside native enum")
	if value is Dictionary:
		var object: Dictionary = value
		for required: String in schema.get("required", []):
			if not object.has(required):
				errors.append(path + "." + required + ": required")
		var properties: Dictionary = schema.get("properties", {})
		for key: String in properties:
			if object.has(key) and properties[key] is Dictionary:
				_validate_schema(object[key], properties[key], path + "." + key, errors)
	elif value is Array and schema.get("items") is Dictionary:
		var values: Array = value
		for index: int in range(values.size()):
			_validate_schema(values[index], schema["items"], path + "[%d]" % index, errors)


func _dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value
	if value is String:
		var parser: JSON = JSON.new()
		if parser.parse(value) == OK and parser.data is Dictionary:
			return parser.data
	return {}


func _reasoning_property_metadata() -> Dictionary:
	# Only this known non-secret UI option is inspected. Never enumerate values
	# of credential/configuration fields or dump a provider configuration.
	var result: Dictionary = {}
	for property: Dictionary in _provider.get_property_list():
		if str(property.get("name", "")) == "размышления":
			result["current"] = str(_provider.get("размышления"))
			result["hint"] = int(property.get("hint", 0))
			result["hint_string"] = str(property.get("hint_string", ""))
			var script: Script = _provider.get_script() as Script
			if script != null:
				result["default"] = script.get_property_default_value("размышления")
			break
	return result


func _no_actions(response: Dictionary) -> bool:
	return str(response.get("действие", "")) == "ничего" and _empty_orders(response)


func _empty_orders(response: Dictionary) -> bool:
	for key: String in ["приказы", "план", "отложено"]:
		if not response.get(key) is Array or not (response[key] as Array).is_empty():
			return false
	return true


func _safe_moon_show(response: Dictionary) -> bool:
	return str(response.get("действие", "")) == "показать" and str(response.get("цель", "")).strip_edges() == "Луна" and _empty_orders(response) and float(response.get("скорость", -1)) == 0.0 and not bool(response.get("назад", true)) and str(response.get("текст", "")).is_empty()


func _disconnect_consumers_except_memory() -> void:
	for signal_name: String in RESPONSE_SIGNALS:
		if not _provider.has_signal(signal_name):
			continue
		for connection: Dictionary in _provider.get_signal_connection_list(signal_name):
			var callback: Callable = connection["callable"]
			if callback.get_object() == _memory:
				continue
			_saved_connections.append({"signal": signal_name, "callable": callback, "flags": int(connection["flags"])})
			_provider.disconnect(signal_name, callback)
	_report["suspended_native_connections"] = _saved_connections.size()


func _assistant_response(value: Dictionary) -> void:
	_response = value.duplicate(true)
	_received = true


func _provider_error(value: Variant) -> void:
	_request_error = str(value)


func _restore_consumers() -> void:
	if not is_instance_valid(_provider):
		return
	for name: String in ["ответ_помощника", "туннель_ошибка"]:
		var listener: Callable = Callable(self, "_assistant_response" if name == "ответ_помощника" else "_provider_error")
		if _provider.is_connected(name, listener):
			_provider.disconnect(name, listener)
	for item: Dictionary in _saved_connections:
		var callback: Callable = item["callable"]
		if callback.is_valid() and not _provider.is_connected(str(item["signal"]), callback):
			_provider.connect(str(item["signal"]), callback, int(item["flags"]))
	_saved_connections.clear()


func _check(name: String, passed: bool) -> void:
	_report["checks"][name] = passed
	if not passed:
		_report["failures"].append(name)


func _write(name: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_output.path_join(name), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func _finish() -> void:
	_restore_consumers()
	_report["ok"] = (_report["failures"] as Array).is_empty()
	_report["schema_validation_subset"] = "type, required, enum, properties, items from the actual captured native schema"
	_write("ai-integration-private.json", _private)
	_write("ai-integration.json", _report)
	print("REFACTOR_AI_INTEGRATION_COMPLETE ok=", _report["ok"], " cases=", (_report["cases"] as Array).size())
	get_tree().quit(0 if bool(_report["ok"]) else 1)
