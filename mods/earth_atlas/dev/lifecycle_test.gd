extends RefCounted
## Isolated lifecycle regression: production mod and real map class, API fixture.
## Call in a dedicated launcher test process only (Pax.game must initially be null).
## Invokes lifecycle entry points as the mod loader does, never attach/activation.

class FixtureGame extends PaxGame:
	var earth: ShaderMaterial
	var windows_created: int = 0
	var buttons: Array[Button] = []
	var panels: Array[PanelContainer] = []
	var map_key: String = "earth"

	func _init(main_node: Node) -> void:
		super(main_node)
		earth = ShaderMaterial.new()
		earth.shader = load("res://shaders/planet.gdshader") as Shader

	func body(name) -> Dictionary:
		return {"имя": "Земля", "карта": map_key} if str(name) == "Земля" else {}

	func body_material(name) -> Material:
		return earth if str(name) == "Земля" else null

	# Reflected PaxGame.tr_key signature: (key: String) -> String.
	# Do not call Pax.tr_key here: it dispatches back to this fixture recursively.
	func tr_key(key: String) -> String:
		return key

	func language() -> String:
		return "ru"

	func add_window(button_text: String, content: Control, min_size: Vector2 = Vector2(380, 300)) -> PanelContainer:
		windows_created += 1
		var button: Button = Button.new()
		button.text = button_text
		main.add_child(button)
		buttons.append(button)
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size = min_size
		panel.add_child(content)
		main.add_child(panel)
		panels.append(panel)
		return panel

func start(source_mod: Node, output_dir: String) -> Dictionary:
	if Pax.game != null:
		return {"ok": false, "error": "Run lifecycle fixture in a dedicated launcher test process, not a live world"}
	var checks: Array[String] = []
	var errors: Array[String] = []
	var tree: SceneTree = source_mod.get_tree()
	# This is a dedicated test process. Disable ALL source hooks before fixtures:
	# set_process(false) alone leaves node_added retaining their ViewportTextures.
	source_mod.call("_mod_unloaded")
	source_mod.set_process(false)
	var host: SubViewport = SubViewport.new()
	host.size = Vector2i(1280, 720)
	host.disable_3d = true
	host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(host)
	var fixture_root: Node = Node.new()
	host.add_child(fixture_root)
	var game: FixtureGame = FixtureGame.new(fixture_root)
	var map_script: Script = load("res://scripts/ui/Карта.gd")
	var existing_map: CanvasLayer = map_script.new() as CanvasLayer
	fixture_root.add_child(existing_map)
	existing_map.set_process(false)
	existing_map.visible = false
	existing_map.set("мат_земли", game.earth)
	var original_surface: Shader = (existing_map.get("мат_пов") as ShaderMaterial).shader
	var original_map: Shader = (existing_map.get("мат") as ShaderMaterial).shader
	# Keep the caller's instance inert so only the fresh instance participates.
	# Subclass changes ONLY development dispatchers; production lifecycle logic is inherited.
	var path: String = source_mod.get_script().resource_path
	var wrapper: GDScript = GDScript.new()
	wrapper.source_code = "extends \"%s\"\nfunc _probe() -> void:\n\tpass\nfunc _render_test() -> void:\n\tpass\nfunc _lifecycle_test() -> void:\n\tpass\n" % path.replace("\\", "/").replace("\"", "\\\"")
	var compile_error: Error = wrapper.reload()
	if compile_error != OK:
		host.queue_free()
		return {"ok": false, "error": "Cannot build isolated mod subclass: %s" % compile_error}
	var subject: Node = wrapper.new() as Node
	for property: String in ["id", "root", "manifest"]:
		subject.set(property, source_mod.get(property))
	tree.root.add_child(subject)
	Pax.game = game
	# The map already exists BEFORE _mod_loaded. No world_ready delivery yet.
	subject.call("_mod_loaded")
	await _frames(tree, 8)
	_check(subject.get("_game") == game, "late load catches existing Pax.game", checks, errors)
	_check(_count_records(subject, existing_map) == 1, "late load finds preexisting map exactly once", checks, errors)
	_check(_is_active(subject, existing_map), "late load automatically activates Earth", checks, errors)
	_check(game.windows_created == 1, "late load creates settings once", checks, errors)
	_check(_live_buttons(game) == 1, "late load produces one settings button", checks, errors)
	# Repeated world_ready delivery must not lose original shader records or duplicate UI.
	subject.call("_world_ready", game)
	await _frames(tree, 3)
	subject.call("_world_ready", game)
	await _frames(tree, 5)
	_check(_count_records(subject, existing_map) == 1, "repeated ready keeps one map record", checks, errors)
	_check(_live_buttons(game) == 1, "repeated ready keeps one settings button", checks, errors)
	_check(game.windows_created == 1, "repeated ready does not rebuild settings", checks, errors)
	# Verify ordinary node_added still catches a map created after late loading.
	var later_map: CanvasLayer = map_script.new() as CanvasLayer
	fixture_root.add_child(later_map)
	later_map.set_process(false)
	later_map.visible = false
	later_map.set("мат_земли", game.earth)
	await _frames(tree, 5)
	_check(_count_records(subject, later_map) == 1, "future node_added discovers new map", checks, errors)
	_check(_is_active(subject, later_map), "future map automatically activates", checks, errors)
	# Toggle a different body's material; adapter's real process must restore originals.
	var other: ShaderMaterial = ShaderMaterial.new()
	other.shader = original_surface
	existing_map.set("мат_земли", other)
	await _frames(tree, 3)
	_check((existing_map.get("мат_пов") as ShaderMaterial).shader == original_surface,
		"ready repetition preserves original surface for restoration", checks, errors)
	_check((existing_map.get("мат") as ShaderMaterial).shader == original_map,
		"ready repetition preserves original political shader for restoration", checks, errors)
	_check(not _is_active(subject, existing_map), "other body automatically deactivates", checks, errors)
	subject.call("_mod_unloaded")
	Pax.game = null
	subject.queue_free()
	host.queue_free()
	await _frames(tree, 2)
	var report: Dictionary = {"ok": errors.is_empty(), "checks": checks, "errors": errors,
		"limitations": "Real production lifecycle/process and actual Карта; FixtureGame overrides body lookup and add_window, no full simulation or save loading"}
	DirAccess.make_dir_recursive_absolute(output_dir)
	var file: FileAccess = FileAccess.open(output_dir.path_join("lifecycle-report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print("ATLAS_LIFECYCLE_RESULT ", JSON.stringify(report))
	return report

func _frames(tree: SceneTree, count: int) -> void:
	for frame: int in range(count):
		await tree.process_frame

func _count_records(mod: Node, map: Node) -> int:
	var count: int = 0
	var records: Array = mod.get("_maps")
	for record: Dictionary in records:
		if record.node.get_ref() == map:
			count += 1
	return count

func _is_active(mod: Node, map: Node) -> bool:
	var records: Array = mod.get("_maps")
	for record: Dictionary in records:
		if record.node.get_ref() == map:
			return bool(record.get("active", false))
	return false

func _live_buttons(game: FixtureGame) -> int:
	var count: int = 0
	for button: Button in game.buttons:
		if is_instance_valid(button) and not button.is_queued_for_deletion():
			count += 1
	return count

func _check(condition: bool, name: String, checks: Array[String], errors: Array[String]) -> void:
	if condition:
		checks.append(name)
	else:
		errors.append(name)
