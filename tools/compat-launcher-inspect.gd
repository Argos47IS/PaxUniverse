extends Node
## External QA autoload. Observe the native launcher without invoking its actions.

const QA_PROFILE: String = "/Pax Universe Atlas QA"
var _output: String = ""

func _ready() -> void:
	set_process(false)
	call_deferred("_inspect")

func _inspect() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with(QA_PROFILE):
		push_error("COMPAT_LAUNCHER_INSPECT_REFUSED: isolated Atlas QA profile required")
		return
	_output = OS.get_environment("PAX_COMPAT_OUTPUT")
	if _output.is_empty() or not _output.is_absolute_path():
		push_error("COMPAT_LAUNCHER_INSPECT_REFUSED: absolute PAX_COMPAT_OUTPUT required")
		return
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(_output)
	if mkdir_error != OK:
		push_error("COMPAT_LAUNCHER_INSPECT_REFUSED: output directory unavailable")
		return
	for sample: int in range(3):
		await get_tree().create_timer(2.0).timeout
		await get_tree().process_frame
		_write_snapshot(sample)
	print("COMPAT_LAUNCHER_INSPECT_COMPLETE: native scene left running")

func _write_snapshot(sample: int) -> void:
	var tree: SceneTree = get_tree()
	var scene: Node = tree.current_scene
	var report: Dictionary = {
		"sample": sample,
		"data_version": FileAccess.get_file_as_string("res://data/version.txt").strip_edges(),
		"current_scene": str(scene.get_path()) if is_instance_valid(scene) else "",
		"scene_script": _script_path(scene),
		"window_size": str(tree.root.size),
		"viewport": str(tree.root.get_visible_rect()),
		"visible_buttons": [],
		"visible_windows": [],
		"constraints": "Read-only UI inspection. No actions, gate changes, scene changes or process exit. Input field contents are omitted.",
	}
	var pax: Node = tree.root.get_node_or_null("Pax")
	if is_instance_valid(pax):
		var pax_script: Script = pax.get_script() as Script
		var constants: Dictionary = pax_script.get_script_constant_map() if pax_script != null else {}
		var loader: Script = constants.get("Моды") as Script
		if loader != null:
			report["loader_allowed"] = bool(loader.call("разрешены"))
			report["loader_version"] = str(loader.call("версия_игры"))
		var manifests: Array = pax.call("mods")
		var active_mods: Array = []
		for manifest: Dictionary in manifests:
			active_mods.append({"id": str(manifest.get("id", "")), "version": str(manifest.get("version", ""))})
		report["active_mods"] = active_mods
		if pax.has_method("код_запускался"):
			report["mod_code_started"] = bool(pax.call("код_запускался"))
	_walk(tree.root, report)
	var filename: String = "launcher-inspect-%d.json" % sample
	var file: FileAccess = FileAccess.open(_output.path_join(filename), FileAccess.WRITE)
	if file == null:
		push_error("COMPAT_LAUNCHER_INSPECT_WRITE_FAILED: " + filename)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMPAT_LAUNCHER_INSPECT ", JSON.stringify(report))

func _walk(node: Node, report: Dictionary) -> void:
	if node is Window and (node as Window).visible:
		var window: Window = node as Window
		(report.visible_windows as Array).append({"path": str(node.get_path()), "title": window.title, "size": str(window.size), "position": str(window.position)})
	if node is BaseButton and (node as BaseButton).is_visible_in_tree():
		var button: BaseButton = node as BaseButton
		var record: Dictionary = {
			"path": str(button.get_path()), "class": button.get_class(),
			"text": (button as Button).text if button is Button else "",
			"disabled": button.disabled, "pressed": button.button_pressed,
			"rect": str(button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)),
			"script": _script_path(button), "pressed_callbacks": [],
		}
		for connection: Dictionary in button.get_signal_connection_list("pressed"):
			var callback: Callable = connection.get("callable", Callable())
			var target: Object = callback.get_object()
			(record.pressed_callbacks as Array).append({
				"method": str(callback.get_method()),
				"target_class": target.get_class() if is_instance_valid(target) else "",
				"target_path": str((target as Node).get_path()) if target is Node and is_instance_valid(target) and (target as Node).is_inside_tree() else "",
				"target_script": _script_path(target),
			})
		(report.visible_buttons as Array).append(record)
	for child: Node in node.get_children():
		_walk(child, report)

func _script_path(object: Object) -> String:
	if not is_instance_valid(object):
		return ""
	var script: Script = object.get_script() as Script
	return script.resource_path if script != null else ""
