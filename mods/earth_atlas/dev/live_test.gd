extends RefCounted
## Full Main startup; MUST run only with the separate QA user profile.

func start(mod: Node) -> void:
    var tree: SceneTree = mod.get_tree()
    print("ATLAS_LIVE_PROFILE ", OS.get_user_data_dir())
    if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"):
        push_error("Atlas live test requires the isolated QA profile")
        tree.quit(2)
        return
    var test_coexistence: bool = OS.get_cmdline_user_args().has("--atlas-coexist-live-test")
    if test_coexistence and is_instance_valid(Pax.get_mod("earth_atlas_hd")):
        # QA only: retain mounted legacy resources but start the world on 0.2.0.
        Pax.call("_выгрузить_код", "earth_atlas_hd")
        await tree.process_frame
    var settings: FileAccess = FileAccess.open("user://settings.json", FileAccess.WRITE)
    settings.store_string(JSON.stringify({"язык": "ru", "заставка": false, "провайдеры": {"мозг": {"режим": "выкл"}}}))
    settings.close()
    var main: Node = load("res://scripts/Main.gd").new()
    main.set("слот", "atlas_qa_" + str(Time.get_ticks_msec()))
    if tree.current_scene != null:
        tree.current_scene.queue_free()
        await tree.process_frame
    tree.root.add_child(main)
    tree.current_scene = main
    await tree.process_frame
    print("ATLAS_LIVE_WORLD ", is_instance_valid(Pax.game))
    if not is_instance_valid(Pax.game):
        tree.quit(3)
        return
    Pax.game.set_speed(0)
    tree.root.size = Vector2i(1920, 1080)
    main.call("_открыть_карту_тела", int(main.get("индекс_земли")))
    var map: CanvasLayer = main.get("полит_карта") as CanvasLayer
    map.call("показать", true)
    map.set("центр", Vector2(0.5806, 0.2111))
    map.set("зум", 13.0)
    map.call("_отправить_вид")
    var menu: CanvasLayer = main.get("меню") as CanvasLayer
    if menu != null:
        menu.call("закрыть")
    for frame: int in range(30):
        await tree.process_frame
    var output_dir: String = OS.get_environment("PAX_ATLAS_TEST_OUTPUT")
    var runner: RefCounted = load(str(mod.call("path", "dev/auto_path_test.gd"))).new()
    var report: Dictionary = await runner.start(mod, output_dir)
    if test_coexistence:
        var coexist_runner: RefCounted = load(str(mod.call("path", "dev/coexistence_test.gd"))).new()
        var coexist_report: Dictionary = await coexist_runner.start(mod, output_dir)
        report["coexistence"] = coexist_report
        report["ok"] = bool(report["ok"]) and bool(coexist_report.get("ok", false))
    report["full_world_startup"] = true
    report["map_visible"] = map.visible
    report["hud_visible"] = Pax.game.hud_layer().visible
    var surface: ShaderMaterial = map.get("мат_пов") as ShaderMaterial
    var shaders: Dictionary = mod.get("_shaders")
    report["actual_surface_shader_matches"] = surface.shader == shaders.surface
    report["actual_political_shader_matches"] = (map.get("мат") as ShaderMaterial).shader == shaders.political
    report["atlas_urban"] = surface.get_shader_parameter("atlas_urban")
    report["atlas_natural"] = surface.get_shader_parameter("atlas_natural")
    report["atlas_has_elevation"] = surface.get_shader_parameter("atlas_has_elevation")
    report["surface_size"] = str((map.get("вп") as SubViewport).size)
    report["ok"] = bool(report["ok"]) and map.visible and Pax.game.hud_layer().visible and bool(report["actual_surface_shader_matches"]) and bool(report["actual_political_shader_matches"])
    report["limitations"] = "Full fresh world with original game UI and automatic mod activation; user saves and long-running simulation not tested"
    var settings_button: Button = mod.get("_settings_button") as Button
    var settings_panel: PanelContainer = mod.get("_settings_window") as PanelContainer
    settings_button.pressed.emit()
    report["settings_open"] = settings_panel.visible
    settings_button.pressed.emit()
    report["settings_close"] = not settings_panel.visible
    report["ok"] = bool(report["ok"]) and bool(report["settings_open"]) and bool(report["settings_close"])
    if DisplayServer.get_name() != "headless":
        for frame: int in range(4):
            await tree.process_frame
            await RenderingServer.frame_post_draw
        var shot: Image = tree.root.get_texture().get_image()
        shot.save_png(output_dir.path_join("live-world.png"))
        mod.set("_enabled", false)
        for frame: int in range(4):
            await tree.process_frame
            await RenderingServer.frame_post_draw
        tree.root.get_texture().get_image().save_png(output_dir.path_join("live-world-before.png"))
        mod.set("_enabled", true)
    var panel: PanelContainer = mod.get("_settings_window") as PanelContainer
    mod.call("_mod_unloaded")
    mod.set_process(false)
    var windows: Array = main.get("окна_модов")
    report["unload_unregisters_window"] = not windows.has(panel)
    main.call("_переключить_окно", main.get("окно_приказов"))
    report["ok"] = bool(report["ok"]) and bool(report["unload_unregisters_window"])
    var file: FileAccess = FileAccess.open(output_dir.path_join("live-world-report.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(report, "\t"))
    print("ATLAS_LIVE_RESULT ", JSON.stringify(report))
    tree.quit(0 if bool(report.get("ok", false)) else 1)
