extends Node
## External QA autoload; never distribute this file inside a mod.
## It uses the game's normal activation and scanner, without modifying either.

var _output: String
var _report: Dictionary = {"checks": {}, "failures": []}

func _ready() -> void:
    call_deferred("_run")

func _check(name: String, result: bool) -> void:
    _report.checks[name] = result
    if not result:
        _report.failures.append(name)
        push_error("COMPAT_FAIL " + name)

func _run() -> void:
    if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"):
        push_error("Compatibility host requires the isolated Atlas QA profile.")
        get_tree().quit(2)
        return
    _output = OS.get_environment("PAX_COMPAT_OUTPUT")
    if _output.is_empty() or not _output.is_absolute_path():
        get_tree().quit(2)
        return
    DirAccess.make_dir_recursive_absolute(_output)
    _report.version = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
    var loader: Script = load("res://scripts/моды/Моды.gd")
    _report.loader_version = loader.call("версия_игры")
    await get_tree().create_timer(1.0).timeout
    # Since 0.15.1 the launcher keeps mod code asleep until a licensed game starts.
    # This is the normal activation entry point; all sandbox checks stay enabled.
    Pax.call("включить_моды")
    await get_tree().process_frame
    _check("atlas_loaded", is_instance_valid(Pax.get_mod("earth_atlas")))
    _check("interface_loaded", is_instance_valid(Pax.get_mod("pax_interface")))
    _report.problems = Pax.run_command("problems")
    var validation: String = Pax.run_command("check")
    _report.validation = validation
    print("COMPAT_VALIDATION ", validation)
    _check("validator_no_errors", validation.contains("0 error(s), 0 warning(s)"))
    for id: String in ["earth_atlas", "pax_interface"]:
        var pattern: RegEx = RegEx.new()
        pattern.compile("\\[" + id + "\\] checked [1-9][0-9]* files, [1-9][0-9]* JSON")
        _check(id + "_files_checked", pattern.search(validation) != null)
    if not (_report.failures as Array).is_empty():
        _finish()
        return
    var stage: String = OS.get_environment("PAX_COMPAT_STAGE")
    if stage == "validate":
        _finish()
        return
    get_tree().root.size = Vector2i(1920, 1080)
    var main: Node = load("res://scripts/Main.gd").new()
    main.set("слот", "compat_qa_" + str(Time.get_ticks_msec()))
    if get_tree().current_scene != null:
        get_tree().current_scene.queue_free()
        await get_tree().process_frame
    get_tree().root.add_child(main)
    get_tree().current_scene = main
    await get_tree().process_frame
    _check("world_created", is_instance_valid(Pax.game))
    if not is_instance_valid(Pax.game):
        _finish()
        return
    Pax.game.set_speed(0)
    main.call("_открыть_карту_тела", int(main.get("индекс_земли")))
    var map: CanvasLayer = main.get("полит_карта") as CanvasLayer
    map.call("показать", true)
    map.set("центр", Vector2(0.5806, 0.2111))
    map.set("зум", 13.0)
    map.call("_отправить_вид")
    var menu: CanvasLayer = main.get("меню") as CanvasLayer
    if menu != null:
        menu.call("закрыть")
    await get_tree().create_timer(1.0).timeout
    var atlas: Node = Pax.get_mod("earth_atlas")
    var hud: Node = Pax.get_mod("pax_interface")
    _check("atlas_automatic_world_ready", atlas.get("_game") == Pax.game)
    _check("hud_automatic_world_ready", hud.get("_game") == Pax.game)
    _check("hud_automatic_controls", is_instance_valid(hud.get("_dock")))
    var surface: ShaderMaterial = map.get("мат_пов") as ShaderMaterial
    _check("atlas_automatic_shader", surface.shader == (atlas.get("_shaders") as Dictionary).get("surface"))
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        _check("automatic_screenshot", get_tree().root.get_texture().get_image().save_png(_output.path_join("automatic-world.png")) == OK)
    _write_report()
    if not (_report.failures as Array).is_empty():
        _finish()
        return
    var repository: String = get_script().resource_path.get_base_dir().get_base_dir()
    if stage == "interface":
        var runner: RefCounted = load(repository.path_join("tests/pax_interface/live_test.gd")).new()
        await runner.start(hud)
        return
    if stage == "atlas":
        var runner: RefCounted = load(repository.path_join("tests/earth_atlas/compatibility_test.gd")).new()
        _report.atlas = await runner.start(atlas, _output)
        _check("atlas_functional_tests", bool(_report.atlas.get("ok", false)))
    if stage == "reload":
        var runner: RefCounted = load(repository.path_join("tests/compatibility_reload.gd")).new()
        _report.reload = await runner.start(_output)
        _check("reload_functional_tests", bool(_report.reload.get("ok", false)))
    _finish()

func _write_report() -> void:
    _report.ok = (_report.failures as Array).is_empty()
    var file: FileAccess = FileAccess.open(_output.path_join("compatibility-report.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(_report, "\t"))
    file.close()

func _finish() -> void:
    _write_report()
    print("COMPAT_RESULT ", JSON.stringify(_report))
    get_tree().quit(0 if bool(_report.ok) else 1)
