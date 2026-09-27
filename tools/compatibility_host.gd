extends Node
## External QA autoload; never distribute this file inside a mod.
## It uses the game's normal activation and scanner, without modifying either.

var _output: String
var _report: Dictionary = {"checks": {}, "failures": []}

func _ready() -> void:
    print("COMPAT_PHASE host_ready")
    call_deferred("_run")

func _check(name: String, result: bool) -> void:
    _report.checks[name] = result
    if not result:
        _report.failures.append(name)
        push_error("COMPAT_FAIL " + name)

func _validation_clean(report: String) -> bool:
    var lines: PackedStringArray = report.strip_edges().split("\n")
    return not lines.is_empty() and lines[-1].strip_edges() == "0 error(s), 0 warning(s)"

func _nested_checks_passed(value: Variant) -> bool:
    if not value is Dictionary:
        return false
    var result: Dictionary = value as Dictionary
    if result.get("ok") != true or not result.get("checks") is Dictionary or not result.get("failures") is Array:
        return false
    var checks: Dictionary = result["checks"] as Dictionary
    if checks.is_empty() or not (result["failures"] as Array).is_empty():
        return false
    for passed: Variant in checks.values():
        if not passed is bool or not bool(passed):
            return false
    return true

func _run() -> void:
    print("COMPAT_PHASE host_run")
    if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"):
        push_error("Compatibility host requires the isolated Atlas QA profile.")
        get_tree().quit(2)
        return
    _output = OS.get_environment("PAX_COMPAT_OUTPUT")
    if _output.is_empty() or not _output.is_absolute_path():
        get_tree().quit(2)
        return
    DirAccess.make_dir_recursive_absolute(_output)
    var stage: String = OS.get_environment("PAX_COMPAT_STAGE")
    _report.stage = stage
    # Keep typed literals out of a conditional expression in this exported runtime.
    var checked_ids: Array[String] = ["earth_atlas"]
    if stage != "nativeextras":
        checked_ids.append("pax_interface")
    _report.version = FileAccess.get_file_as_string("res://data/version.txt").strip_edges()
    var loader: Script = load("res://scripts/моды/Моды.gd")
    _report.loader_version = loader.call("версия_игры")
    await get_tree().create_timer(1.0).timeout
    # Since 0.15.1 the launcher keeps mod code asleep until a licensed game starts.
    # This is the normal activation entry point; all sandbox checks stay enabled.
    print("COMPAT_PHASE activate_mods")
    Pax.call("включить_моды")
    await get_tree().process_frame
    _check("atlas_loaded", is_instance_valid(Pax.get_mod("earth_atlas")))
    if stage == "nativeextras":
        _check("interface_disabled_for_control", not is_instance_valid(Pax.get_mod("pax_interface")))
    else:
        _check("interface_loaded", is_instance_valid(Pax.get_mod("pax_interface")))
    _report.problems = Pax.run_command("problems")
    var validation_all: String = Pax.run_command("check")
    _report.validation_all = validation_all
    _report.all_installed_packages_validation_clean = _validation_clean(validation_all)
    _report.validation_scope = "Strict checks for maintained Atlas/HUD; full installed-package diagnostics retained separately."
    var validation: String = ""
    var owned_validation_ok: bool = true
    for mod_id: String in checked_ids:
        var own_validation: String = Pax.run_command("check " + mod_id)
        validation += own_validation + "\n"
        owned_validation_ok = owned_validation_ok and _validation_clean(own_validation)
    _report.validation = validation
    print("COMPAT_VALIDATION ", validation)
    _check("validator_no_errors", owned_validation_ok)
    for id: String in checked_ids:
        var pattern: RegEx = RegEx.new()
        pattern.compile("\\[" + id + "\\] checked [1-9][0-9]* files, [1-9][0-9]* JSON")
        _check(id + "_files_checked", pattern.search(validation) != null)
    if not (_report.failures as Array).is_empty():
        _finish()
        return
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
    if stage == "nativeextras":
        var repository_path: String = get_script().resource_path.get_base_dir().get_base_dir()
        var native_runner: RefCounted = load(repository_path.path_join("tests/store_coexist_test.gd")).new()
        _report.native_control = await native_runner.start_native_control(_output)
        _check("native_control_completed", _nested_checks_passed(_report.native_control))
        _finish()
        return
    _check("atlas_automatic_world_ready", atlas.get("_game") == Pax.game)
    _check("hud_automatic_world_ready", hud.get("_game") == Pax.game)
    _check("hud_automatic_controls", is_instance_valid(hud.get("_dock")))
    var surface: ShaderMaterial = map.get("мат_пов") as ShaderMaterial
    _check("atlas_automatic_shader", surface.shader == (atlas.get("_shaders") as Dictionary).get("surface"))
    if DisplayServer.get_name() != "headless":
        await RenderingServer.frame_post_draw
        _check("automatic_screenshot", get_tree().root.get_texture().get_image().save_png(_output.path_join("automatic-world.png")) == OK)
    var repository: String = get_script().resource_path.get_base_dir().get_base_dir()
    var inventory_tool: RefCounted = load(repository.path_join("tests/pax_interface/compatibility_inventory.gd")).new()
    var inventory: Dictionary = inventory_tool.capture(main, hud)
    var inventory_file: FileAccess = FileAccess.open(_output.path_join("ui-inventory.json"), FileAccess.WRITE)
    inventory_file.store_string(JSON.stringify(inventory, "\t"))
    inventory_file.close()
    _write_report()
    if not (_report.failures as Array).is_empty():
        _finish()
        return
    if stage == "interface":
        var optional_runner: RefCounted = load(repository.path_join("tests/pax_interface/optional_window_binding_test.gd")).new()
        _report.optional_window_bindings = await optional_runner.start(hud)
        _check("optional_window_bindings", _nested_checks_passed(_report.optional_window_bindings))
        _write_report()
        if not (_report.failures as Array).is_empty():
            _finish()
            return
        var content_runner: RefCounted = load(repository.path_join("tests/pax_interface/native_content_rebuild_test.gd")).new()
        _report.native_content_rebuild = await content_runner.start(hud)
        _check("native_content_rebuild", _nested_checks_passed(_report.native_content_rebuild))
        _write_report()
        if not (_report.failures as Array).is_empty():
            _finish()
            return
        var runner: RefCounted = load(repository.path_join("tests/pax_interface/live_test.gd")).new()
        await runner.start(hud)
        return
    if stage == "atlas":
        var runner: RefCounted = load(repository.path_join("tests/earth_atlas/compatibility_test.gd")).new()
        _report.atlas = await runner.start(atlas, _output)
        _check("atlas_functional_tests", _nested_checks_passed(_report.atlas))
    if stage == "coexist":
        var runner: RefCounted = load(repository.path_join("tests/store_coexist_test.gd")).new()
        _report.coexist = await runner.start(_output)
        _check("store_coexist_tests", _nested_checks_passed(_report.coexist))
    if stage == "reload":
        var runner: RefCounted = load(repository.path_join("tests/compatibility_reload.gd")).new()
        _report.reload = await runner.start(_output)
        _check("reload_functional_tests", _nested_checks_passed(_report.reload))
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
