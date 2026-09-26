extends Node
## Private probe of existing native AI paths; never installed inside a scanned mod.
## Only the isolated Refactor QA profile and loopback Ollama are permitted.

const LOCAL_URL: String = "http://127.0.0.1:11434/v1"
const MODEL: String = "qwen3.5:4b"
const STATUS_MARKER: String = "PAX_REFACTOR_STATUS_PROBE"
const SYSTEM_MARKER: String = "PAX_REFACTOR_MEMORY_SYSTEM_PROBE"
const INPUT_TEXT: String = "Какая сейчас дата? Не отдавай приказов."
const RESPONSE_SIGNALS: Array[String] = ["готово", "событие_готово", "ответ_собеседника", "человек_готов", "ответ_помощника", "итоги_готовы", "канал_готов", "туннель_ошибка"]

var _output: String
var _provider: Node
var _main: Node
var _original_status: Callable
var _status_calls: int = 0
var _received: bool = false
var _started_us: int = 0
var _saved_connections: Array[Dictionary] = []
var _saved_system: String = ""
var _report: Dictionary = {"signals": [], "failures": [], "network_policy": "loopback Ollama only; native response application disconnected for the probe"}

func _ready() -> void:
    call_deferred("_run")

func _run() -> void:
    var profile: String = OS.get_user_data_dir().replace("\\", "/")
    _output = OS.get_environment("PAX_REFACTOR_OUTPUT").replace("\\", "/")
    if not profile.ends_with("/Pax Universe Refactor QA") or not _output.is_absolute_path() or not _output.contains("/.local/"):
        get_tree().quit(2)
        return
    DirAccess.make_dir_recursive_absolute(_output)
    _report.version = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
    _report.engine = str(Engine.get_version_info().string)
    Pax.call("включить_моды")
    await get_tree().process_frame
    _main = load("res://scripts/Main.gd").new()
    _main.set("слот", "refactor_ai_probe_" + str(int(Time.get_unix_time_from_system() * 1000)))
    if get_tree().current_scene != null:
        get_tree().current_scene.queue_free()
        await get_tree().process_frame
    get_tree().root.add_child(_main)
    get_tree().current_scene = _main
    await get_tree().process_frame
    if not is_instance_valid(Pax.game):
        _report.failures.append("No licensed QA world was created")
        _finish()
        return
    Pax.game.set_speed(0)
    _provider = _main.get("provider") as Node
    if _provider == null:
        _report.failures.append("Native Provider unavailable")
        _finish()
        return
    # Write known public test values; never read existing credentials or copy settings.
    _provider.set("base_url", LOCAL_URL)
    _provider.set("model", MODEL)
    # Ollama's OpenAI-compatible API accepts this non-secret placeholder.
    # The native game treats an empty key as offline even for a loopback endpoint.
    _provider.set("api_key", "ollama")
    _provider.set("настройки_закреплены", true)
    _provider.set("ожидание_сек", 85.0)
    _provider.call("_применить_таймауты")
    _report.provider = {"base_url": str(_provider.get("base_url")), "model": str(_provider.get("model")), "connected": bool(_provider.call("подключён")), "mode": str(_provider.call("имя_режима")), "ollama_root": str(_provider.call("_корень_ollama"))}
    if str(_provider.get("base_url")) != LOCAL_URL or str(_provider.get("model")) != MODEL:
        _report.failures.append("Native Provider refused the loopback test configuration")
        _finish()
        return
    if not bool(_report.provider.connected):
        _report.failures.append("Native Provider is offline; no request was attempted")
        _finish()
        return
    _original_status = _provider.get("статус_стороны")
    _report.status_native_valid = _original_status.is_valid()
    _report.status_native_method = str(_original_status.get_method()) if _original_status.is_valid() else ""
    if _original_status.is_valid():
        _provider.set("статус_стороны", Callable(self, "_decorated_status"))
    _export_private_prompts()
    _report.pure_builders = _probe_builders()
    _report.calls_before_native_request = _status_calls
    # A separate marker proves whether this native prompt field reaches the request.
    _saved_system = str(_provider.get("системный_помощник"))
    _provider.set("системный_помощник", _saved_system + "\n" + SYSTEM_MARKER + ": это диагностическая метка, не игровое событие. Не включай её в ответ.")
    var dump_path: String = _output.path_join("native-dumps")
    DirAccess.make_dir_recursive_absolute(dump_path)
    _provider.set("папка_дампа", dump_path)
    _disconnect_native_consumers()
    _connect_observers()
    _report.input = INPUT_TEXT
    _report.native_flow = "Main._спросить_помощника -> native Provider; response application suspended"
    _started_us = Time.get_ticks_usec()
    _main.call("_спросить_помощника", INPUT_TEXT)
    var deadline: int = Time.get_ticks_msec() + 90000
    while not _received and Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
    _report.response_received = _received
    _report.elapsed_ms = (Time.get_ticks_usec() - _started_us) / 1000.0
    _report.calls_after_native_request = _status_calls
    _report.dump_evidence = _scan_dump_markers(dump_path)
    if not _received:
        _report.failures.append("No native response signal within 90 seconds")
    _restore()
    _finish()

func _probe_builders() -> Dictionary:
    var result: Dictionary = {}
    for method: String in ["_мир_коротко", "_системный_по_блокам"]:
        var text: String = str(_provider.call(method))
        result[method] = {"chars": text.length(), "status_marker": text.contains(STATUS_MARKER), "status_calls": _status_calls}
    var parts: Variant = _provider.call("_надвое", {"запрос": INPUT_TEXT, "память": "Оригинальная синтетическая запись для проверки формата контекста."}, "assistant")
    var bounded: Variant = _provider.call("_уложиться", "Тестовые системные инструкции.", INPUT_TEXT, "Синтетическое досье без игровых секретов.", 128)
    _write("native-builder-values-private.json", {"parts": parts, "bounded": bounded})
    result["_надвое"] = {"result_type": typeof(parts), "status_marker": str(parts).contains(STATUS_MARKER), "status_calls": _status_calls}
    result["_уложиться"] = {"result_type": typeof(bounded), "status_marker": str(bounded).contains(STATUS_MARKER), "status_calls": _status_calls}
    return result

func _export_private_prompts() -> void:
    var data: Dictionary = {"prompts": {}, "schemas": {}, "notice": "Native runtime content, private local audit only; do not publish."}
    for field: String in ["системный", "системный_событие", "системный_разговор", "системный_человек", "системный_помощник", "системный_итоги", "блоки", "_малые_промпты"]:
        data.prompts[field] = _provider.get(field)
    # This build uses plain JSON for its interpreter; asking schema_ответа for
    # that channel triggers the native JSON parser on the literal "json".
    for channel: String in ["assistant", "talk", "event"]:
        data.schemas[channel] = _provider.call("схема_ответа", channel, false)
    var blocks: Dictionary = _provider.get("блоки")
    var small: Dictionary = _provider.get("_малые_промпты")
    _report.prompt_block_keys = blocks.keys()
    _report.small_prompt_keys = small.keys()
    _write("native-prompts-private.json", data)

func _disconnect_native_consumers() -> void:
    for signal_name: String in RESPONSE_SIGNALS:
        for connection: Dictionary in _provider.get_signal_connection_list(signal_name):
            var callback: Callable = connection.callable
            _saved_connections.append({"signal": signal_name, "callable": callback, "flags": int(connection.flags)})
            _provider.disconnect(signal_name, callback)
    _report.suspended_native_connections = _saved_connections.size()

func _connect_observers() -> void:
    for signal_name: String in ["готово", "ответ_собеседника", "человек_готов", "ответ_помощника", "итоги_готовы", "туннель_ошибка"]:
        _provider.connect(signal_name, Callable(self, "_one_arg").bind(signal_name))
    _provider.connect("событие_готово", Callable(self, "_two_args").bind("событие_готово"))
    _provider.connect("канал_готов", Callable(self, "_three_args").bind("канал_готов"))

func _one_arg(value: Variant, signal_name: String) -> void:
    _capture(signal_name, [value])

func _two_args(first: Variant, second: Variant, signal_name: String) -> void:
    _capture(signal_name, [first, second])

func _three_args(first: Variant, second: Variant, third: Variant, signal_name: String) -> void:
    _capture(signal_name, [first, second, third])

func _capture(signal_name: String, values: Array) -> void:
    _report.signals.append({"signal": signal_name, "values": values, "elapsed_ms": (Time.get_ticks_usec() - _started_us) / 1000.0})
    _received = true

func _decorated_status() -> String:
    _status_calls += 1
    return str(_original_status.call()) + "\n" + STATUS_MARKER if _original_status.is_valid() else STATUS_MARKER

func _scan_dump_markers(folder: String) -> Array:
    var results: Array = []
    var directory: DirAccess = DirAccess.open(folder)
    if directory == null:
        return results
    for name: String in directory.get_files():
        var text: String = FileAccess.get_file_as_string(folder.path_join(name))
        results.append({"file": name, "chars": text.length(), "status_marker": text.contains(STATUS_MARKER), "system_marker": text.contains(SYSTEM_MARKER), "local_url": text.contains("127.0.0.1:11434"), "model": text.contains(MODEL)})
    return results

func _restore() -> void:
    if not is_instance_valid(_provider):
        return
    if _original_status.is_valid():
        _provider.set("статус_стороны", _original_status)
    _provider.set("системный_помощник", _saved_system)
    for item: Dictionary in _saved_connections:
        var callback: Callable = item.callable
        if callback.is_valid() and not _provider.is_connected(str(item.signal), callback):
            _provider.connect(str(item.signal), callback, int(item.flags))
    _saved_connections.clear()

func _write(name: String, data: Dictionary) -> void:
    var file: FileAccess = FileAccess.open(_output.path_join(name), FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()

func _finish() -> void:
    _report.ok = (_report.failures as Array).is_empty()
    _write("ai-probe-private.json", _report)
    print("REFACTOR_AI_PROBE_COMPLETE ok=", _report.ok, " status_calls=", _status_calls)
    get_tree().quit(0 if bool(_report.ok) else 1)
