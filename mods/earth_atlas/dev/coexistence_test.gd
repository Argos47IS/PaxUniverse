extends RefCounted
## Full-world regression using the mounted, unmodified 0.1.1 legacy mod.
## The caller mounts the legacy package, unloads its initial instance, then starts Main.
## Only development dispatchers are suppressed in the legacy subclass below.

const LEGACY_ROOT: String = "res://mods/earth_atlas_hd/"

func start(new_mod: Node, output_dir: String) -> Dictionary:
	var checks: Array[String] = []
	var errors: Array[String] = []
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/Pax Universe Atlas QA"):
		return _report(output_dir, checks, ["Coexistence test requires the isolated QA profile"])
	var game: PaxGame = Pax.game
	if not is_instance_valid(game) or not is_instance_valid(game.main):
		return _report(output_dir, checks, ["Coexistence test requires a real running world"])
	var tree: SceneTree = new_mod.get_tree()
	var map: CanvasLayer = game.main.get("полит_карта") as CanvasLayer
	if map == null:
		return _report(output_dir, checks, ["The full-world Earth map is unavailable"])
	var initial: Dictionary = _map_record(new_mod, map)
	if initial.is_empty() or not bool(initial.get("active", false)):
		return _report(output_dir, checks, ["The new mod must own the active Earth map initially"])
	var original_surface: Shader = initial.get("original_surface") as Shader
	var original_political: Shader = initial.get("original_map") as Shader
	var surface: ShaderMaterial = map.get("мат_пов") as ShaderMaterial
	var political: ShaderMaterial = map.get("мат") as ShaderMaterial
	var new_button: Button = new_mod.get("_settings_button") as Button
	if new_button == null:
		return _report(output_dir, checks, ["The new mod settings button is unavailable"])
	var labels: Array[String] = [new_button.text, str(new_mod.call("tr_key", "earth_atlas_hd_button"))]
	_check(_button_count(game.main, labels) == 1, "new mod starts with exactly one Atlas button", checks, errors)
	_check(original_surface != surface.shader and original_political != political.shader,
		"initial Atlas records retain distinct original shaders", checks, errors)
	var legacy_entry: String = LEGACY_ROOT.path_join("main.gd")
	if not FileAccess.file_exists(legacy_entry):
		return _report(output_dir, checks, ["Mount the original earth_atlas_hd 0.1.1 package before this test"])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_ROOT.path_join("mod.json")))
	if not parsed is Dictionary:
		return _report(output_dir, checks, ["The mounted legacy manifest is invalid"])
	var manifest: Dictionary = parsed
	if str(manifest.get("id", "")) != "earth_atlas_hd" or str(manifest.get("version", "")) != "0.1.1":
		return _report(output_dir, checks, ["Expected the real earth_atlas_hd 0.1.1 manifest"])
	var wrapper: GDScript = GDScript.new()
	wrapper.source_code = "extends \"%s\"\nfunc _live_test() -> void:\n\tpass\nfunc _render_test() -> void:\n\tpass\nfunc _lifecycle_test() -> void:\n\tpass\n" % legacy_entry
	var compile_error: Error = wrapper.reload()
	if compile_error != OK:
		return _report(output_dir, checks, ["Cannot compile legacy development wrapper: %s" % compile_error])
	var legacy: PaxMod = wrapper.new() as PaxMod
	legacy.id = "earth_atlas_hd"
	legacy.root = LEGACY_ROOT
	legacy.manifest = manifest
	# Match Pax's ordering: node_added fires before the legacy _mod_loaded callback.
	tree.root.add_child(legacy)
	_check(surface.shader == original_surface and political.shader == original_political,
		"new mod restores both original shaders synchronously before legacy load", checks, errors)
	_check(_active_count(new_mod) == 0,
		"new mod releases every active map before legacy load", checks, errors)
	_check(_button_count(game.main, labels) == 0,
		"new mod removes its button before legacy creates UI", checks, errors)
	legacy.call("_mod_loaded")
	await _frames(tree, 10)
	var legacy_shaders: Dictionary = legacy.get("_shaders")
	_check(legacy.get("_game") == game, "real legacy lifecycle catches the existing world", checks, errors)
	_check(surface.shader == legacy_shaders.get("surface") and political.shader == legacy_shaders.get("political"),
		"legacy mod alone controls both map shaders", checks, errors)
	_check(_active_count(new_mod) == 0 and bool(_map_record(legacy, map).get("active", false)),
		"only legacy map records are active while both nodes exist", checks, errors)
	_check(_button_count(game.main, labels) == 1,
		"both installed versions produce one live Atlas button", checks, errors)
	# A repeated world callback must also respect the live legacy instance.
	new_mod.call("_world_ready", game)
	await tree.create_timer(0.65).timeout
	await _frames(tree, 4)
	_check(_active_count(new_mod) == 0 and _button_count(game.main, labels) == 1,
		"world callbacks and periodic catch-up keep the new mod yielded", checks, errors)
	# A deferred callback queued before unload can still run before queue_free.
	legacy.call_deferred("_catch_up")
	legacy.call("_mod_unloaded")
	legacy.queue_free()
	await tree.create_timer(0.65).timeout
	await _frames(tree, 6)
	var new_shaders: Dictionary = new_mod.get("_shaders")
	_check(surface.shader == new_shaders.get("surface") and political.shader == new_shaders.get("political"),
		"new mod automatically reclaims both shaders after legacy removal", checks, errors)
	_check(bool(_map_record(new_mod, map).get("active", false)),
		"new mod automatically activates its map record after legacy removal", checks, errors)
	_check(_button_count(game.main, labels) == 1,
		"late legacy catch-up after unload leaves one new Atlas button", checks, errors)
	var resumed: Dictionary = _map_record(new_mod, map)
	_check(resumed.get("original_surface") == original_surface and resumed.get("original_map") == original_political,
		"handover preserves vanilla originals instead of nesting Atlas shaders", checks, errors)
	new_mod.call("_mod_unloaded")
	await _frames(tree, 3)
	_check(surface.shader == original_surface and political.shader == original_political,
		"unloading the surviving new mod restores both original shaders", checks, errors)
	_check(_button_count(game.main, labels) == 0,
		"unloading both versions removes all Atlas buttons", checks, errors)
	# The development caller guards its live dispatcher against recursive runs.
	# Reinitialize normally so later full-world UI and screenshot checks stay valid.
	new_mod.call("_mod_loaded")
	await tree.create_timer(0.65).timeout
	await _frames(tree, 6)
	new_shaders = new_mod.get("_shaders")
	_check(surface.shader == new_shaders.get("surface") and political.shader == new_shaders.get("political")
		and bool(_map_record(new_mod, map).get("active", false)) and _button_count(game.main, labels) == 1,
		"normal new-mod reinitialization restores the test caller's map and UI", checks, errors)
	return _report(output_dir, checks, errors)

func _frames(tree: SceneTree, count: int) -> void:
	for frame: int in range(count):
		await tree.process_frame

func _map_record(mod: Node, map: Node) -> Dictionary:
	var records: Array = mod.get("_maps")
	for record: Dictionary in records:
		var ref: WeakRef = record.get("node") as WeakRef
		if ref != null and ref.get_ref() == map:
			return record
	return {}

func _active_count(mod: Node) -> int:
	var count: int = 0
	var records: Array = mod.get("_maps")
	for record: Dictionary in records:
		var ref: WeakRef = record.get("node") as WeakRef
		if ref != null and is_instance_valid(ref.get_ref()) and bool(record.get("active", false)):
			count += 1
	return count

func _button_count(main: Node, labels: Array[String]) -> int:
	var count: int = 0
	for node: Node in main.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and not button.is_queued_for_deletion() and labels.has(button.text):
			count += 1
	return count

func _check(condition: bool, name: String, checks: Array[String], errors: Array[String]) -> void:
	if condition:
		checks.append(name)
	else:
		errors.append(name)

func _report(output_dir: String, checks: Array[String], errors: Array[String]) -> Dictionary:
	var report: Dictionary = {"ok": errors.is_empty(), "checks": checks, "errors": errors,
		"legacy_source": LEGACY_ROOT, "legacy_version": "0.1.1",
		"limitations": "Real full world and legacy lifecycle; wrapper suppresses development dispatchers only; does not change loader flags or Pax instances"}
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file: FileAccess = FileAccess.open(output_dir.path_join("coexistence-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("ATLAS_COEXISTENCE_RESULT ", JSON.stringify(report))
	return report
