extends RefCounted
## Automatic discovery regression + read-only live-world audit.
## Does not call _attach, _set_active, _process or _world_ready manually.
## Run from a dedicated development mod/console after the mod has been loaded.
## Launcher can verify node discovery; full success requires a real running world.

func start(mod: Node, output_dir: String) -> Dictionary:
	var tree: SceneTree = mod.get_tree()
	var game: PaxGame = Pax.game
	var game_script: Script = load("res://scripts/моды/PaxGame.gd")
	for method: Dictionary in game_script.get_script_method_list():
		if str(method.name) == "_init":
			print("ATLAS_PAXGAME_INIT ", JSON.stringify(method))
	var report: Dictionary = audit(mod)
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(960, 540)
	host.disable_3d = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var script: Script = load("res://scripts/ui/Карта.gd")
	var map: CanvasLayer = script.new() as CanvasLayer
	if map == null:
		host.queue_free()
		return {"ok": false, "error": "Expected CanvasLayer map class"}
	host.add_child(map)
	map.visible = false
	map.set_process(false)
	var earth: Material = game.body_material("Земля") if game != null else null
	if earth != null:
		map.set("мат_земли", earth)
	var original_map: Shader = (map.get("мат") as ShaderMaterial).shader
	var original_surface: Shader = (map.get("мат_пов") as ShaderMaterial).shader
	# Only natural SceneTree node_added and process callbacks drive the mod.
	for frame: int in range(5):
		await tree.process_frame
	var record: Dictionary = {}
	var records: Array = mod.get("_maps")
	for item: Dictionary in records:
		if item.node.get_ref() == map:
			record = item
	report["automatic_node_added_attached"] = not record.is_empty()
	report["fixture_script_path"] = script.resource_path
	report["fixture_activated_without_manual_calls"] = bool(record.get("active", false))
	var shaders: Dictionary = mod.get("_shaders")
	report["fixture_shader_swapped"] = (map.get("мат_пов") as ShaderMaterial).shader == shaders.get("surface")
	if earth != null and bool(record.get("active", false)):
		# A second body uses a distinct material, just as a real body switch does.
		var other_body: ShaderMaterial = ShaderMaterial.new()
		other_body.shader = load("res://shaders/planet.gdshader") as Shader
		map.set("мат_земли", other_body)
		for frame: int in range(3):
			await tree.process_frame
		report["automatic_other_body_restored"] = (
			(map.get("мат") as ShaderMaterial).shader == original_map
			and (map.get("мат_пов") as ShaderMaterial).shader == original_surface
			and not bool(record.get("active", true)))
	host.queue_free()
	await tree.process_frame
	report["ok"] = (game != null and bool(report.get("mod_game_matches_live_game", false))
		and bool(report["automatic_node_added_attached"])
		and bool(report["fixture_activated_without_manual_calls"])
		and bool(report.get("automatic_other_body_restored", false))
		and bool(report.get("settings_button_found", false)))
	report["limitations"] = "Existing-world audit plus real-map node discovery/automatic frame processing; startup callback dispatch itself requires a world-start test"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file: FileAccess = FileAccess.open(output_dir.path_join("auto-path-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("ATLAS_AUTO_PATH_RESULT ", JSON.stringify(report))
	return report

func audit(mod: Node) -> Dictionary:
	var game: PaxGame = Pax.game
	var report: Dictionary = {"live_game_available": game != null,
		"mod_game_available": mod.get("_game") != null,
		"mod_game_matches_live_game": game != null and mod.get("_game") == game,
		"mod_processing": mod.is_processing(), "enabled": mod.get("_enabled")}
	var maps: Array[Dictionary] = []
	var earth: Material = game.body_material("Земля") if game != null else null
	var body: Dictionary = game.body("Земля") if game != null else {}
	report["earth_material_available"] = earth != null
	report["earth_body_has_map_key"] = body.has("карта")
	report["earth_body_map_value"] = str(body.get("карта", ""))
	var records: Array = mod.get("_maps")
	for record: Dictionary in records:
		var node: Node = record.node.get_ref() as Node
		if node == null:
			continue
		maps.append({"path": str(node.get_path()), "script_path": node.get_script().resource_path,
			"active": record.get("active", false), "earth_material_matches": node.get("мат_земли") == earth})
	report["tracked_maps"] = maps
	var label: String = str(mod.call("tr_key", "earth_atlas_button"))
	report["settings_button_found"] = _has_button(mod.get_tree().root, label)
	return report

func _has_button(node: Node, label: String) -> bool:
	if node is Button and (node as Button).text == label:
		return true
	for child: Node in node.get_children():
		if _has_button(child, label):
			return true
	return false
