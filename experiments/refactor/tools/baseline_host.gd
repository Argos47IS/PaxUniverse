extends Node
## Measures the untouched exported game in an isolated profile before experimental mods.

var _output: String
var _report: Dictionary = {"checks": {}, "failures": [], "metrics": {}, "skipped": []}
var _native_status: Callable
var _status_calls: int = 0

func _ready() -> void:
    call_deferred("_run")

func _check(name: String, passed: bool) -> void:
    _report.checks[name] = passed
    if not passed:
        _report.failures.append(name)
        push_error("REFACTOR_FAIL " + name)

func _run() -> void:
    if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Refactor QA"):
        get_tree().quit(2)
        return
    _output = OS.get_environment("PAX_REFACTOR_OUTPUT")
    if not _output.is_absolute_path():
        get_tree().quit(2)
        return
    _report.version = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
    _report.engine = Engine.get_version_info().string
    # Retain the native loader resource for the activation lifetime, as in the established QA host.
    var loader: Script = load("res://scripts/моды/Моды.gd")
    _report.loader_version = loader.call("версия_игры")
    _report.metrics.harness_ready_engine_ms = Time.get_ticks_usec() / 1000.0
    _report.with_mods = OS.get_environment("PAX_REFACTOR_MODS") == "1"
    # Let the launcher finish construction before activating mods that watch node_added.
    await get_tree().create_timer(1.0).timeout
    print("BASELINE_CHECKPOINT activate")
    # The current build initializes Pax.game only after normal licensed activation.
    Pax.call("включить_моды")
    print("BASELINE_CHECKPOINT activated")
    if bool(_report.with_mods):
        _report.mod_validation = Pax.run_command("check")
        _check("mods_validator", str(_report.mod_validation).contains("0 error(s), 0 warning(s)"))
    await get_tree().process_frame
    var start: int = Time.get_ticks_usec()
    var main: Node = load("res://scripts/Main.gd").new()
    main.set("слот", "refactor_baseline_" + str(int(Time.get_unix_time_from_system() * 1000)))
    if get_tree().current_scene != null:
        get_tree().current_scene.queue_free()
        await get_tree().process_frame
    get_tree().root.size = Vector2i(1920, 1080)
    get_tree().root.add_child(main)
    get_tree().current_scene = main
    await get_tree().process_frame
    _check("world_created", is_instance_valid(Pax.game))
    if not is_instance_valid(Pax.game):
        _finish()
        return
    Pax.game.set_speed(0)
    _report.metrics.world_creation_ms = (Time.get_ticks_usec() - start) / 1000.0
    main.call("_открыть_карту_тела", int(main.get("индекс_земли")))
    var map: CanvasLayer = main.get("полит_карта") as CanvasLayer
    map.call("показать", true)
    map.set("центр", Vector2(0.5806, 0.2111))
    map.set("зум", 13.0)
    map.call("_отправить_вид")
    var menu: CanvasLayer = main.get("меню") as CanvasLayer
    if menu != null:
        menu.call("закрыть")
    await RenderingServer.frame_post_draw
    _report.metrics.first_world_frame_engine_ms = Time.get_ticks_usec() / 1000.0
    _report.rendering = {"driver": RenderingServer.get_current_rendering_method(), "viewport": str(get_tree().root.size), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
    await get_tree().create_timer(3.0).timeout
    _report.frame_sample = await _sample_frames(10.0)
    await RenderingServer.frame_post_draw
    _check("screenshot", get_tree().root.get_texture().get_image().save_png(_output.path_join("world.png")) == OK)
    _report.provider_probe = _probe_provider(main)
    var own_directory: String = get_script().resource_path.get_base_dir()
    var memory_checks: String = own_directory.path_join("memory_store_checks.gd")
    if FileAccess.file_exists(memory_checks):
        var store_script: Script = load(own_directory.path_join("../../../mods/pax_memory/memory_store.gd"))
        var memory_runner: RefCounted = load(memory_checks).new()
        _report.memory_component = memory_runner.start(store_script)
        _check("memory_component", bool(_report.memory_component.get("ok", false)))
    if Pax.has_mod("pax_memory"):
        var adapter_runner: RefCounted = load(own_directory.path_join("memory_adapter_checks.gd")).new()
        _report.memory_adapter = adapter_runner.start(Pax.game)
        _check("memory_adapter", bool(_report.memory_adapter.get("ok", false)))
    var checks_path: String = get_script().resource_path.get_base_dir().path_join("mechanics_checks.gd")
    if FileAccess.file_exists(checks_path) and OS.get_environment("PAX_REFACTOR_SKIP_MECHANICS") != "1":
        var checks: RefCounted = load(checks_path).new()
        _report.mechanics = await checks.start(main, Pax.game)
        _check("mechanics", bool(_report.mechanics.get("ok", false)))
    else:
        _report.skipped.append("Mechanics checks omitted from this isolated performance/activation run")
    _finish()

func _sample_frames(seconds: float) -> Dictionary:
    var times: Array[float] = []
    var process_times: Array[float] = []
    var start: int = Time.get_ticks_usec()
    var previous: int = start
    while (Time.get_ticks_usec() - start) / 1000000.0 < seconds:
        await get_tree().process_frame
        var now: int = Time.get_ticks_usec()
        times.append((now - previous) / 1000.0)
        process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
        previous = now
    var duration: float = (previous - start) / 1000000.0
    var sorted: Array[float] = times.duplicate()
    sorted.sort()
    var sum_ms: float = 0.0
    for value: float in times:
        sum_ms += value
    return {
        "duration_s": duration, "start_engine_ms": start / 1000.0, "frames": times.size(),
        "fps": times.size() / duration, "frame_mean_ms": sum_ms / times.size(),
        "frame_p50_ms": sorted[int(sorted.size() * 0.5)], "frame_p95_ms": sorted[int(sorted.size() * 0.95)],
        "frame_p99_ms": sorted[int(sorted.size() * 0.99)], "frame_ms": times,
        "engine_process_ms": process_times, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
        "note": "Wall-clock intervals at process_frame; includes frame pacing. Not an exclusive simulation CPU timer."
    }

func _probe_provider(main: Node) -> Dictionary:
    var provider: Node = main.get("provider") as Node
    if provider == null:
        return {"available": false}
    var report: Dictionary = {"available": true, "network_called": false}
    report.connected = provider.call("подключён")
    report.context_window = provider.call("окно_контекста")
    _native_status = provider.get("статус_стороны")
    report.native_status_valid = _native_status.is_valid()
    if _native_status.is_valid():
        report.native_status_method = str(_native_status.get_method())
        var original: String = str(_native_status.call())
        report.original_status_chars = original.length()
        provider.set("статус_стороны", Callable(self, "_decorated_status"))
        var brief: String = str(provider.call("_мир_коротко"))
        var system: String = str(provider.call("_системный_по_блокам"))
        provider.set("статус_стороны", _native_status)
        report.callback_count = _status_calls
        report.marker_in_brief = brief.contains("PAX_REFACTOR_STATUS_PROBE")
        report.marker_in_system = system.contains("PAX_REFACTOR_STATUS_PROBE")
        report.brief_chars = brief.length()
        report.system_chars = system.length()
        report.original_preserved = system.contains(original) or brief.contains(original)
    _report.skipped.append("External AI generation: offline baseline; real-model latency measured separately")
    return report

func _decorated_status() -> String:
    _status_calls += 1
    return str(_native_status.call()) + "\nPAX_REFACTOR_STATUS_PROBE"

func _finish() -> void:
    _report.ok = (_report.failures as Array).is_empty()
    var file: FileAccess = FileAccess.open(_output.path_join("baseline.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(_report, "\t"))
    file.close()
    print("REFACTOR_BASELINE_COMPLETE ok=", _report.ok)
    get_tree().quit(0 if bool(_report.ok) else 1)
