extends RefCounted
## Read-only external QA inventory. Never include this helper in an installable mod.
## It records UI structure and chrome captions, not dialog bodies, saves or source code.

var _main: Node
var _hud: Node
var _map: Node
var _buttons: Dictionary = {}
var _properties_by_id: Dictionary = {}
var _original_header_row: Control
var _native_bottom: Control
var _replacements: Dictionary = {}


func capture(main: Node, hud: Node) -> Dictionary:
	_main = main
	_hud = hud
	_map = _node_property(main, "полит_карта")
	_buttons.clear()
	_properties_by_id.clear()
	_replacements.clear()
	_original_header_row = null
	_native_bottom = _node_property(main, "низ_кнопки") as Control
	var header: Control = _node_property(main, "верх_панель") as Control
	if is_instance_valid(header) and header.get_child_count() > 0:
		_original_header_row = header.get_child(0) as Control
	var result: Dictionary = {
		"scope": "UI structure and chrome button captions only; no callbacks invoked, state changed, dialog bodies, saves or source code read.",
		"main_controls": _control_properties(main, "main"),
		"map_controls": _control_properties(_map, "map"),
		"rows": {}, "buttons": [], "potentially_lost_header_buttons": [],
		"limits": "Visibility and bounds are structural observations, not an occlusion or end-to-end click test. Hidden native controls with live proxies are expected."
	}
	_index_replacements()
	var rows: Dictionary = {
		"original_header_row": _original_header_row,
		"header": header,
		"native_bottom": _native_bottom,
		"native_context_tabs": _node_property(main, "вкладки_группы"),
		"mod_header": _node_property(hud, "_top_nav"),
		"mod_dock": _node_property(hud, "_dock"),
		"mod_tools": _node_property(hud, "_tools"),
		"mod_aux": _node_property(hud, "_dock_aux")
	}
	for key: String in rows:
		var row: Control = rows[key] as Control
		if is_instance_valid(row):
			result.rows[key] = _describe(row)
			_collect_buttons(row, key)
	# Include named buttons without walking into native dialogs or custom text fields.
	for owner: Node in [main, _map]:
		if not is_instance_valid(owner):
			continue
		for property: Dictionary in owner.get_property_list():
			if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
				continue
			var value: Variant = owner.get(property.name)
			if value is BaseButton:
				_add_button(value as BaseButton, "named_control")
	for record: Dictionary in _buttons.values():
		var id: int = int(record.id)
		record["properties"] = _properties_by_id.get(id, [])
		record["replacement"] = _replacements.get(id, {})
		var trapped: bool = bool(record["inside_original_header_row"]) and bool(record["visible"]) and not bool(record["visible_in_tree"])
		var replacement: Dictionary = record["replacement"]
		var represented: bool = bool(replacement.get("visible_in_tree", false))
		record["potentially_lost_header_action"] = trapped and not represented
		(result.buttons as Array).append(record)
		if bool(record["potentially_lost_header_action"]):
			(result.potentially_lost_header_buttons as Array).append({
				"id": id, "name": record.name, "properties": record.properties,
				"text": record.text, "tooltip": record.tooltip,
				"hidden_ancestors": record.hidden_ancestors,
				"verification": "Compare native visibility before HUD attach, preserve the same button or native handler, then verify a visible replacement and one callback invocation in the isolated QA world."
			})
	result["button_count"] = _buttons.size()
	return result


func _control_properties(owner: Node, prefix: String) -> Array:
	var result: Array = []
	if not is_instance_valid(owner):
		return result
	for property: Dictionary in owner.get_property_list():
		if int(property.get("type", TYPE_NIL)) != TYPE_OBJECT:
			continue
		var value: Variant = owner.get(property.name)
		if not value is Control:
			continue
		var control: Control = value as Control
		var record: Dictionary = _describe(control)
		record["property"] = str(property.name)
		result.append(record)
		var id: int = control.get_instance_id()
		if not _properties_by_id.has(id):
			_properties_by_id[id] = []
		(_properties_by_id[id] as Array).append(prefix + "." + str(property.name))
	return result


func _index_replacements() -> void:
	var natives: Variant = _property(_hud, "_native")
	var proxies: Variant = _property(_hud, "_proxies")
	if natives is Dictionary and proxies is Dictionary:
		for key: Variant in natives:
			_add_replacement((natives as Dictionary)[key] as Node, (proxies as Dictionary).get(key) as Control, "command:" + str(key))
	var extras: Variant = _property(_hud, "_extras")
	if extras is Dictionary:
		for record: Variant in (extras as Dictionary).values():
			if record is Dictionary:
				_add_replacement(record.get("native") as Node, record.get("proxy") as Control, "extra")


func _add_replacement(native: Node, proxy: Control, kind: String) -> void:
	if not is_instance_valid(native) or not is_instance_valid(proxy):
		return
	var record: Dictionary = _describe(proxy)
	record["kind"] = kind
	_replacements[native.get_instance_id()] = record


func _collect_buttons(node: Node, row: String) -> void:
	if node is BaseButton:
		_add_button(node as BaseButton, row)
	for child: Node in node.get_children():
		_collect_buttons(child, row)


func _add_button(button: BaseButton, row: String) -> void:
	var id: int = button.get_instance_id()
	if _buttons.has(id):
		var existing: Dictionary = _buttons[id]
		if not (existing.rows as Array).has(row):
			(existing.rows as Array).append(row)
		return
	var record: Dictionary = _describe(button)
	record["text"] = button.text if button is Button else ""
	record["tooltip"] = button.tooltip_text
	record["disabled"] = button.disabled
	record["toggle_mode"] = button.toggle_mode
	record["pressed"] = button.button_pressed
	record["focus_mode"] = button.focus_mode
	record["mouse_filter"] = button.mouse_filter
	record["rows"] = [row]
	record["inside_original_header_row"] = _contains(_original_header_row, button)
	record["inside_native_bottom"] = _contains(_native_bottom, button)
	record["pressed_connection_count"] = button.get_signal_connection_list("pressed").size()
	var win: Variant = button.get_meta("win") if button.has_meta("win") else null
	record["win"] = _identity(win as Node) if win is Node and is_instance_valid(win) else {}
	record["hud_role"] = str(button.get_meta("pax_interface_role", ""))
	_buttons[id] = record


func _describe(control: Control) -> Dictionary:
	var result: Dictionary = _identity(control)
	result["visible"] = control.visible
	result["visible_in_tree"] = control.is_visible_in_tree()
	result["queued_for_deletion"] = control.is_queued_for_deletion()
	result["hidden_ancestors"] = _hidden_ancestors(control)
	var rect: Rect2 = control.get_global_rect()
	result["rect"] = {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y}
	result["viewport_contains_rect"] = control.get_viewport_rect().grow(1.0).encloses(rect)
	return result


func _identity(node: Node) -> Dictionary:
	if not is_instance_valid(node):
		return {}
	var parent: Node = node.get_parent()
	return {"id": node.get_instance_id(), "name": str(node.name), "class": node.get_class(), "path": str(node.get_path()) if node.is_inside_tree() else "", "parent": str(parent.get_path()) if is_instance_valid(parent) and parent.is_inside_tree() else ""}


func _hidden_ancestors(node: Node) -> Array:
	var result: Array = []
	var ancestor: Node = node.get_parent()
	while is_instance_valid(ancestor):
		if (ancestor is CanvasItem and not (ancestor as CanvasItem).visible) or (ancestor is CanvasLayer and not (ancestor as CanvasLayer).visible):
			result.append(_identity(ancestor))
		ancestor = ancestor.get_parent()
	return result


func _contains(parent: Node, child: Node) -> bool:
	return is_instance_valid(parent) and (parent == child or parent.is_ancestor_of(child))


func _property(owner: Node, name: String) -> Variant:
	if not is_instance_valid(owner):
		return null
	for property: Dictionary in owner.get_property_list():
		if str(property.name) == name:
			return owner.get(name)
	return null


func _node_property(owner: Node, name: String) -> Node:
	return _property(owner, name) as Node
