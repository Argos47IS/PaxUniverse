extends RefCounted

var _out: String = ""
var _checks: Dictionary = {}

func start(mod: Node) -> void:
	var tree: SceneTree = mod.get_tree()
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Units QA"):
		push_error("Units test requires its isolated QA profile")
		tree.quit(2)
		return
	_out = OS.get_environment("PAX_UNITS_OUTPUT")
	if not _out.is_absolute_path():
		tree.quit(2)
		return
	mod.set_process(false)
	var settings: FileAccess = FileAccess.open("user://settings.json", FileAccess.WRITE)
	settings.store_string(JSON.stringify({"язык": "ru", "заставка": false, "провайдеры": {"мозг": {"режим": "выкл"}}}))
	settings.close()
	var main: Node = load("res://scripts/Main.gd").new()
	main.set("слот", "units_qa_" + str(Time.get_ticks_msec()))
	if tree.current_scene != null:
		tree.current_scene.queue_free()
		await tree.process_frame
	tree.root.size = Vector2i(1920, 1080)
	tree.root.add_child(main)
	tree.current_scene = main
	await tree.process_frame
	if not is_instance_valid(Pax.game):
		tree.quit(3)
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
	for frame: int in range(15):
		await tree.process_frame
	var figures: SubViewport = map.get("фигурки") as SubViewport
	if OS.get_environment("PAX_UNITS_STAGE") != "probe":
		await _render_test(mod, main, map, tree)
		return
	var report: Dictionary = {"version": FileAccess.get_file_as_string("res://data/version.txt"), "map_visible": map.visible, "figure_properties": _props(figures), "map_properties": _props(map), "units": _plain(map.get("отряды_карты")), "display": _plain(map.get("_показ")), "nodes": _plain(figures.get("_узлы"))}
	var tank: Dictionary = figures.call("_танк", Color("647565"))
	report["native_tank"] = _plain(tank)
	for item: Variant in tank.values():
		if item is Node and (item as Node).get_parent() == null:
			(item as Node).free()
	var file: FileAccess = FileAccess.open(_out.path_join("probe.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("UNITS_RUNTIME_PROBE_OK")
	tree.quit(0)

func _render_test(mod: Node, main: Node, map: CanvasLayer, tree: SceneTree) -> void:
	main.set_process(false)
	var original: SubViewport = map.get("фигурки") as SubViewport
	var troops: Array = []
	var display: Dictionary = {}
	for i: int in range(3):
		var uv: Vector2 = Vector2(0.5806 + (i - 1) * 0.006, 0.2111)
		var id: int = 900001 + i
		troops.append({"id": id, "uv": uv, "ряд": 0, "цвет": Color("#4c768a"), "вид": "танк", "люди": 4.0, "имя": "QA", "наш": true, "в_бою": false, "состав": {"экипаж": 4.0}, "техника": {"танки": 1}, "цель_uv": null, "подпись": "QA"})
		display[id] = uv
	map.set("отряды_карты", troops)
	map.set("_показ", display)
	map.call("_фигурки_кадр", 0.0)
	(map.get("слой") as Control).queue_redraw()
	await _shot(tree, "map-before.png")
	mod.set_process(true)
	await tree.create_timer(0.65).timeout
	_checks["automatic_attach"] = map.get("фигурки") != original
	var renderer: SubViewport = mod.get("_replacement") as SubViewport
	_checks["native_renderer_replaced"] = renderer != null and map.get("фигурки") == renderer
	if renderer == null:
		_finish(tree)
		return
	for zoom: float in [7.0, 13.0, 26.0]:
		map.set("зум", zoom)
		map.call("_отправить_вид")
		await tree.create_timer(0.6).timeout
		map.call("_фигурки_кадр", 0.0)
		await _shot(tree, "map-zoom-%d.png" % int(zoom))
		var screen: Vector2 = map.call("на_экран", troops[1].uv)
		_checks["native_selection_zoom_%d" % int(zoom)] = int(map.call("_отряд_у", screen)) == 900002
		var expected: float = {7: 24.0, 13: 32.0, 26: 36.0}[int(zoom)]
		_checks["adaptive_scale_zoom_%d" % int(zoom)] = is_equal_approx(float(renderer.get("tank_length")), expected)
	_checks["custom_tanks_built"] = int(renderer.get("tank_builds")) >= 3
	var cache: Dictionary = renderer.get("_узлы")
	var first: Dictionary = cache.values()[0]
	var tank_node: Node3D = first["техника"][0]["узел"] as Node3D
	var body: Node3D = tank_node.get_child(0) as Node3D
	_checks["forward_axis_is_native_positive_x"] = (body.basis * Vector3.FORWARD).x > 0.0
	var created: int = int(renderer.get("tank_builds"))
	for i: int in range(10):
		map.call("_фигурки_кадр", 0.0)
	_checks["models_reused_between_frames"] = int(renderer.get("tank_builds")) == created
	_checks["catalog_loaded"] = is_instance_valid(mod.get("_template"))
	var file: FileAccess = FileAccess.open(_out.path_join("renderer.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"nodes": _plain(renderer.get("_узлы")), "bounds": str(mod.get("_tank_bounds")), "tank_builds": renderer.get("tank_builds")}, "\t"))
	file.close()
	await _showcase(mod, tree)
	mod.call("_mod_unloaded")
	await tree.process_frame
	_checks["original_restored"] = map.get("фигурки") == original
	_checks["original_texture_restored"] = (map.get("показ_фигурок") as TextureRect).texture == original.get_texture()
	mod.set("_unloaded", false)
	mod.set_process(true)
	await tree.create_timer(0.65).timeout
	_checks["automatic_reattach"] = map.get("фигурки") != original
	mod.call("_mod_unloaded")
	await tree.process_frame
	_checks["second_unload_restored"] = map.get("фигурки") == original
	_finish(tree)

func _shot(tree: SceneTree, name: String) -> void:
	for i: int in range(6):
		await tree.process_frame
		await RenderingServer.frame_post_draw
	var result: Error = tree.root.get_texture().get_image().save_png(_out.path_join(name))
	_checks["screenshot_" + name] = result == OK

func _showcase(mod: Node, tree: SceneTree) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 120
	tree.root.add_child(layer)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.add_child(viewport)
	var view: TextureRect = TextureRect.new()
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.size = tree.root.get_visible_rect().size
	layer.add_child(view)
	var root: Node3D = Node3D.new()
	viewport.add_child(root)
	var tank: Node3D = mod.call("tank_instance") as Node3D
	root.add_child(tank)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#19232d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#b6c9d8")
	env.environment.ambient_light_energy = 0.65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	key.shadow_bias = 0.08
	key.shadow_normal_bias = 2.0
	root.add_child(key)
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 145, 0)
	rim.light_color = Color("#a2c2d2")
	rim.light_energy = 0.55
	root.add_child(rim)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("#26343d")
	material.roughness = 0.9
	ground.material_override = material
	root.add_child(ground)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.8
	camera.position = Vector3(10, 8, -13)
	root.add_child(camera)
	camera.look_at(Vector3(0, 0.8, -1))
	await _shot(tree, "tank-render.png")
	_checks["glb_loaded_by_game"] = tank.get_child_count() > 0
	layer.queue_free()
	await tree.process_frame

func _finish(tree: SceneTree) -> void:
	var ok: bool = true
	for value: Variant in _checks.values():
		ok = ok and bool(value)
	var file: FileAccess = FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok": ok, "checks": _checks, "scope": "Fresh native game map with three visual-only tank fixtures; no player save or simulation unit modified"}, "\t"))
	file.close()
	print("UNITS_RENDER_RESULT ", JSON.stringify(_checks))
	tree.quit(0 if ok else 1)

func _plain(value: Variant, depth: int = 0) -> Variant:
	if depth > 5:
		return str(value)
	if value is Dictionary:
		var data: Dictionary = {}
		for key: Variant in value:
			data[str(key)] = _plain(value[key], depth + 1)
		return data
	if value is Array:
		var data: Array = []
		for item: Variant in value:
			data.append(_plain(item, depth + 1))
		return data
	if value is Node:
		var n: Node = value as Node
		var data: Dictionary = {"class": n.get_class(), "name": n.name, "children": []}
		if n is Node3D:
			data["transform"] = str((n as Node3D).transform)
		for child: Node in n.get_children():
			data.children.append(_plain(child, depth + 1))
		return data
	if value == null or value is String or value is float or value is int or value is bool:
		return value
	return str(value)

func _props(node: Node) -> Dictionary:
	var values: Dictionary = {}
	var script: Script = node.get_script() as Script
	for info: Dictionary in script.get_script_property_list():
		values[str(info.name)] = _plain(node.get(str(info.name)))
	return values
