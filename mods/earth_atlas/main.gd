extends PaxMod
## Earth-only visual adapter. Internal properties are checked before use.

var _game: PaxGame
var _shaders: Dictionary = {}
var _maps: Array[Dictionary] = []
var _enabled: bool = true
var _quality: float = 1.0
var _natural: float = 0.80
var _political: float = 0.25
var _urban: float = 0.08
var _elevation: Texture2D
var _settings_window: PanelContainer
var _settings_button: Button
var _sync_elapsed: float = 0.0
var _legacy: WeakRef
var _legacy_waiting: bool = false
var _unloaded: bool = false

func _mod_loaded() -> void:
    _unloaded = false
    set_process(true)
    var migration_script: Script = load(path("settings_migration.gd"))
    migration_script.migrate(self)
    _enabled = bool(get_setting("enabled", true))
    _quality = clampf(float(get_setting("quality", 1.0)), 0.5, 2.0)
    _natural = clampf(float(get_setting("natural", 0.80)), 0.0, 1.0)
    _political = clampf(float(get_setting("political", 0.25)), 0.0, 0.6)
    _urban = clampf(float(get_setting("urban", 0.08)), 0.0, 1.0)
    var builder_script: Script = load(path("shader_builder.gd"))
    var builder: RefCounted = builder_script.new()
    _shaders = builder.build()
    if _shaders.is_empty():
        for error: String in builder.errors:
            log_error(error)
        return
    _elevation = texture("textures/elevation.png")
    process_priority = 100
    if not get_tree().node_added.is_connected(_node_added):
        get_tree().node_added.connect(_node_added)
    var legacy: PaxMod = Pax.get_mod("earth_atlas_hd")
    if is_instance_valid(legacy):
        _observe_legacy(legacy)
    call_deferred("_catch_up")
    if OS.get_cmdline_user_args().has("--atlas-render-test"):
        call_deferred("_render_test")
    if OS.get_cmdline_user_args().has("--atlas-live-test") or OS.get_cmdline_user_args().has("--atlas-coexist-live-test"):
        call_deferred("_live_test")
    if OS.get_cmdline_user_args().has("--atlas-lifecycle-test"):
        call_deferred("_lifecycle_test")
    if OS.get_cmdline_user_args().has("--atlas-distribution-test"):
        call_deferred("_distribution_test")
    log_info("Earth Atlas shaders prepared; map-only visual changes.")

func _live_test() -> void:
    if get_tree().root.has_meta("earth_atlas_live_test_running"):
        return
    get_tree().root.set_meta("earth_atlas_live_test_running", true)
    var runner: RefCounted = load(path("dev/live_test.gd")).new()
    await runner.start(self)

func _distribution_test() -> void:
    if get_tree().root.has_meta("atlas_distribution_test_running"):
        return
    get_tree().root.set_meta("atlas_distribution_test_running", true)
    var runner: Node = load(path("dev/distribution_test.gd")).new()
    get_tree().root.add_child(runner)
    runner.start(self, OS.get_environment("PAX_ATLAS_TEST_OUTPUT"))

func _legacy_alive() -> bool:
    var legacy: Node = _legacy.get_ref() as Node if _legacy != null else null
    # queue_free runs AFTER deferred calls. The old release can recreate its UI
    # while queued, so wait until its actual tree exit before taking the map back.
    return is_instance_valid(legacy) and legacy.is_inside_tree()

func _observe_legacy(legacy: PaxMod) -> void:
    _legacy = weakref(legacy)
    var cleanup: Callable = _legacy_exiting.bind(legacy)
    if not legacy.tree_exiting.is_connected(cleanup):
        legacy.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)

func _legacy_exiting(legacy: PaxMod) -> void:
    # 0.1.1 has no unloaded guard: queued _catch_up may recreate map records/UI.
    # Its cleanup is idempotent. Run it after deferred work, while get_tree is valid.
    legacy._mod_unloaded()

func _yield_to_legacy() -> void:
    # Release our originals BEFORE the older adapter can capture its baselines.
    # Never rewrite loader preferences or remove another entry from Pax.instances.
    if not _legacy_waiting:
        _restore_maps()
        _remove_settings()
        _game = null
        _legacy_waiting = true
        log_info("Legacy Atlas HD is active; waiting to avoid duplicate map adapters.")

func _lifecycle_test() -> void:
    var runner: RefCounted = load(path("dev/lifecycle_test.gd")).new()
    var report: Dictionary = await runner.start(self, OS.get_environment("PAX_ATLAS_TEST_OUTPUT"))
    get_tree().quit(0 if bool(report.get("ok", false)) else 1)

func _world_ready(game: PaxGame) -> void:
    if _unloaded:
        return
    if _legacy_alive():
        _yield_to_legacy()
        return
    if _game == game and is_instance_valid(_settings_window):
        _scan(game.main)
        return
    if _game != game:
        _restore_maps()
        _remove_settings()
    _game = game
    _scan(game.main)
    _add_settings(game)
    log_info("World connected; Atlas HD controls ready.")

func _catch_up() -> void:
    if _unloaded:
        return
    if _legacy_alive():
        _yield_to_legacy()
        return
    # Enabling/reloading a mod can happen after the world_ready event.
    var game: PaxGame = Pax.game
    if not is_instance_valid(game) or not is_instance_valid(game.main):
        return
    if not game.main.is_node_ready():
        return
    for prop: Dictionary in game.main.get_property_list():
        if str(prop.name) == "_игра_готова" and not bool(game.main.get("_игра_готова")):
            return
    if game != _game or not is_instance_valid(_settings_window):
        _world_ready(game)

func _node_added(node: Node) -> void:
    if _unloaded:
        return
    # Pax sets id BEFORE add_child and calls _mod_loaded AFTER it. This signal
    # lets us restore the map synchronously before the old version starts.
    if node is PaxMod and (node as PaxMod).id == "earth_atlas_hd":
        _observe_legacy(node as PaxMod)
        _yield_to_legacy()
        return
    var script: Script = node.get_script()
    if script != null and script.resource_path.contains("/ui/Карта.gd"):
        call_deferred("_attach", node)

func _scan(node: Node) -> void:
    _node_added(node)
    for child: Node in node.get_children():
        _scan(child)

func _attach(node: Node) -> void:
    if _unloaded or _legacy_alive():
        return
    if not is_instance_valid(node) or not node is CanvasLayer:
        return
    for record: Dictionary in _maps:
        if record.node.get_ref() == node:
            return
    var props: Dictionary = {}
    for prop: Dictionary in node.get_property_list():
        props[str(prop.name)] = true
    for key: String in ["мат", "мат_пов", "мат_земли", "вп", "слой", "фон", "_снимок_параметров"]:
        if not props.has(key):
            log_warning("Map API changed: " + key + "; original map retained.")
            return
    var material: ShaderMaterial = node.get("мат") as ShaderMaterial
    var surface: ShaderMaterial = node.get("мат_пов") as ShaderMaterial
    var viewport: SubViewport = node.get("вп") as SubViewport
    if material == null or surface == null or viewport == null:
        return
    var surface_rect: Control = _find_surface_rect(viewport, surface)
    if surface_rect == null:
        log_warning("Map surface rectangle unavailable; original map retained.")
        return
    var background: Control = node.get("фон") as Control
    if background == null:
        return
    var map_size: Vector2 = background.size.max(Vector2.ONE)
    _maps.append({"node": weakref(node), "material": material, "surface": surface,
        "original_map": material.shader, "original_surface": surface.shader,
        "ratio": Vector2(viewport.size) / map_size, "active": false,
        "surface_rect": weakref(surface_rect)})
    log_info("Map adapter attached.")

func _find_surface_rect(node: Node, material: ShaderMaterial) -> Control:
    if node is ColorRect and (node as ColorRect).material == material:
        return node as Control
    for child: Node in node.get_children():
        var found: Control = _find_surface_rect(child, material)
        if found != null:
            return found
    return null

func _process(delta: float) -> void:
    if _unloaded:
        return
    if _legacy_alive():
        _yield_to_legacy()
        return
    if _legacy_waiting:
        _legacy_waiting = false
        _legacy = null
        _catch_up()
    if _shaders.is_empty():
        return
    _sync_elapsed += delta
    if _sync_elapsed >= 0.5:
        _sync_elapsed = 0.0
        _catch_up()
    for record: Dictionary in _maps:
        var map: CanvasLayer = record.node.get_ref() as CanvasLayer
        if map == null:
            continue
        var earth: Material = _game.body_material("Земля") if is_instance_valid(_game) else null
        var current_map: String = str(_game.body("Земля").get("карта", "")) if earth != null else ""
        var desired: bool = _enabled and earth != null and map.get("мат_земли") == earth and current_map == "earth"
        if desired != bool(record.active):
            _set_active(record, desired)
        if desired and map.visible:
            _resize(record)

func _set_active(record: Dictionary, active: bool) -> void:
    var map: CanvasLayer = record.node.get_ref() as CanvasLayer
    if map == null:
        return
    var material: ShaderMaterial = record.material
    var surface: ShaderMaterial = record.surface
    if active:
        material.shader = _shaders.political
        surface.shader = _shaders.surface
    else:
        if material.shader == _shaders.political:
            material.shader = record.original_map
        if surface.shader == _shaders.surface:
            surface.shader = record.original_surface
    record.active = active
    log_info("Earth map " + ("Atlas HD active." if active else "original view restored."))
    if active:
        _apply_values(record)
    _resize(record)
    map.set("_снимок_параметров", "")
    map.call("_перерисовать_поверхность")

func _resize(record: Dictionary) -> void:
    var map: CanvasLayer = record.node.get_ref() as CanvasLayer
    var viewport: SubViewport = map.get("вп") as SubViewport
    var surface_rect: Control = record.surface_rect.get_ref() as Control
    var background: Control = map.get("фон") as Control
    var target: Vector2
    if bool(record.active):
        var pixel_scale: Vector2 = background.get_global_transform_with_canvas().get_scale().abs()
        pixel_scale *= map.get_viewport().get_stretch_transform().get_scale().abs()
        target = background.size * pixel_scale * _quality
        var cap: float = minf(1.0, 4096.0 / maxf(target.x, target.y))
        target *= cap
    else:
        target = background.size * Vector2(record.ratio)
    var size: Vector2i = Vector2i(target.round()).max(Vector2i.ONE)
    var changed: bool = viewport.size != size
    if changed:
        viewport.size = size
    if surface_rect != null and not surface_rect.size.is_equal_approx(Vector2(size)):
        surface_rect.size = Vector2(size)
        changed = true
    if changed:
        viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _apply_values(record: Dictionary) -> void:
    var surface: ShaderMaterial = record.surface
    var material: ShaderMaterial = record.material
    surface.set_shader_parameter("atlas_natural", _natural)
    surface.set_shader_parameter("atlas_urban", _urban)
    surface.set_shader_parameter("atlas_elevation", _elevation)
    surface.set_shader_parameter("atlas_has_elevation", 1.0 if _elevation != null else 0.0)
    material.set_shader_parameter("atlas_political", _political)

func _refresh() -> void:
    for record: Dictionary in _maps:
        var map: CanvasLayer = record.node.get_ref() as CanvasLayer
        if map == null or not bool(record.active):
            continue
        _apply_values(record)
        _resize(record)
        map.set("_снимок_параметров", "")
        map.call("_перерисовать_поверхность")

func _add_settings(game: PaxGame) -> void:
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    var description := Label.new()
    description.text = tr_key("earth_atlas_description")
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(description)
    var enabled := CheckButton.new()
    enabled.text = tr_key("earth_atlas_enabled")
    enabled.button_pressed = _enabled
    enabled.toggled.connect(func(value: bool):
        _enabled = value
        set_setting("enabled", value))
    box.add_child(enabled)
    var quality := OptionButton.new()
    for key: String in ["earth_atlas_quality_half", "earth_atlas_quality_native", "earth_atlas_quality_high", "earth_atlas_quality_ultra"]:
        quality.add_item(tr_key(key))
    var scales: Array[float] = [0.5, 1.0, 1.5, 2.0]
    var selected: int = scales.find(_quality)
    quality.select(selected if selected >= 0 else 1)
    quality.item_selected.connect(func(index: int):
        _quality = scales[index]
        set_setting("quality", _quality)
        _refresh())
    box.add_child(quality)
    _add_slider(box, "natural", _natural, 1.0)
    _add_slider(box, "political", _political, 0.6)
    _add_slider(box, "urban", _urban, 1.0)
    var existing_buttons: Array[Node] = game.main.find_children("*", "Button", true, false)
    _settings_window = game.add_window(tr_key("earth_atlas_button"), box, Vector2(400, 360))
    for node: Node in game.main.find_children("*", "Button", true, false):
        if not existing_buttons.has(node) and (node as Button).text == tr_key("earth_atlas_button"):
            _settings_button = node as Button
            _settings_button.set_meta("win", _settings_window)
            break

func _add_slider(box: VBoxContainer, key: String, value: float, upper: float) -> void:
    var label := Label.new()
    label.text = tr_key("earth_atlas_" + key)
    box.add_child(label)
    var slider := HSlider.new()
    slider.min_value = 0.0
    slider.max_value = upper
    slider.step = 0.01
    slider.value = value
    slider.value_changed.connect(func(current: float):
        match key:
            "natural": _natural = current
            "political": _political = current
            "urban": _urban = current
        set_setting(key, current)
        _refresh())
    box.add_child(slider)

func _mod_unloaded() -> void:
    _unloaded = true
    if get_tree().node_added.is_connected(_node_added):
        get_tree().node_added.disconnect(_node_added)
    _restore_maps()
    _remove_settings()
    _game = null
    _legacy = null
    _legacy_waiting = false

func _restore_maps() -> void:
    for record: Dictionary in _maps:
        if is_instance_valid(record.node.get_ref()) and bool(record.active):
            _set_active(record, false)
    _maps.clear()

func _remove_settings() -> void:
    if is_instance_valid(_settings_window):
        # PaxGame.add_window registers panels in Main as well as in the tree.
        if is_instance_valid(_game) and is_instance_valid(_game.main):
            for prop: Dictionary in _game.main.get_property_list():
                if str(prop.name) == "окна_модов":
                    var windows: Array = _game.main.get("окна_модов")
                    windows.erase(_settings_window)
                    break
        _settings_window.queue_free()
    if is_instance_valid(_settings_button):
        if _settings_button.get_parent() != null:
            _settings_button.get_parent().remove_child(_settings_button)
        _settings_button.queue_free()
    _settings_window = null
    _settings_button = null

func _render_test() -> void:
    var test_path: String = path("dev/render_test.gd")
    if not FileAccess.file_exists(test_path):
        log_error("Development render harness is not installed.")
        get_tree().quit(1)
        return
    var script: Script = load(test_path)
    var runner: RefCounted = script.new()
    var output_dir: String = OS.get_environment("PAX_ATLAS_TEST_OUTPUT")
    if output_dir.is_empty():
        output_dir = ProjectSettings.globalize_path("user://mod_tests/earth_atlas")
    var thumbnail := Image.new()
    if thumbnail.load_svg_from_string(FileAccess.get_file_as_string(path("thumbnail.svg"))) == OK:
        thumbnail.save_png(output_dir.path_join("thumbnail.png"))
    var adapter_script: Script = load(path("dev/adapter_test.gd"))
    var adapter_runner: RefCounted = adapter_script.new()
    var adapter: Dictionary = await adapter_runner.start(self, output_dir)
    print("ATLAS_ADAPTER_SUMMARY ", JSON.stringify(adapter))
    var report: Dictionary = await runner.start(self, _shaders, output_dir)
    print("ATLAS_RENDER_RESULT ", JSON.stringify(report))
    get_tree().quit(0 if bool(report.get("ok", false)) and bool(adapter.get("ok", false)) else 1)

