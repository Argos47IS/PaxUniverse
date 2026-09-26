extends Node
## Keep native role dialogs and their callbacks; let their existing lists scroll.

var _main: Node
var _mod: Node
var _records: Dictionary = {}
var _clock: float = 0.0

func setup(mod: Node, main: Node) -> void:
	_mod = mod
	_main = main
	set_process(true)

func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.15 or not is_instance_valid(_main) or not is_instance_valid(_mod):
		return
	_clock = 0.0
	var root: Control = _mod.get("_root") as Control
	var tools: Control = _mod.get("_tools_panel") as Control
	var header: Control = _mod.get("_header") as Control
	if not is_instance_valid(root) or not is_instance_valid(tools) or not is_instance_valid(header):
		return
	for property: String in ["окно_дел", "окно_законов"]:
		var window: Control = _main.get(property) as Control
		if not is_instance_valid(window) or not window.is_visible_in_tree():
			continue
		var id: int = window.get_instance_id()
		if not _records.has(id):
			_records[id] = {"node": weakref(window), "minimum": window.custom_minimum_size, "scrolls": [], "signature": ""}
		var record: Dictionary = _records[id]
		var changed: bool = false
		# Native show() can rebuild the list while retaining the same window.
		# Inspect only its two immediate levels, not the tree of business cards.
		for index: int in range(record.scrolls.size() - 1, -1, -1):
			if not is_instance_valid((record.scrolls[index].node as WeakRef).get_ref()):
				record.scrolls.remove_at(index)
		for child: Node in window.get_children():
			for candidate: Node in child.get_children():
				if not candidate is ScrollContainer:
					continue
				var scroll: ScrollContainer = candidate as ScrollContainer
				var known: bool = false
				for item: Dictionary in record.scrolls:
					known = known or (item.node as WeakRef).get_ref() == scroll
				if not known:
					record.scrolls.append({"node": weakref(scroll), "minimum": scroll.custom_minimum_size, "flags": scroll.size_flags_vertical})
				changed = changed or not known or scroll.custom_minimum_size.y != 32.0
		var available: float = maxf(240.0, tools.position.y - maxf(90.0, header.size.y + 16.0) - 10.0)
		var desired: Vector2 = record.minimum
		desired.y = minf(maxf(desired.y, 420.0), available)
		desired.x = minf(desired.x, root.size.x - 36.0)
		var signature: String = str(desired) + ":" + str((_mod.get("_prefs") as Dictionary).get("font_size", 14))
		if not changed and record.signature == signature and window.custom_minimum_size == desired:
			continue
		record.signature = signature
		for item: Dictionary in record.scrolls:
			var scroll: ScrollContainer = (item.node as WeakRef).get_ref() as ScrollContainer
			if is_instance_valid(scroll):
				scroll.custom_minimum_size = Vector2((item.minimum as Vector2).x, 32.0)
				scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		window.custom_minimum_size = desired
		window.reset_size()

func restore() -> void:
	set_process(false)
	for record: Dictionary in _records.values():
		for item: Dictionary in record.scrolls:
			var scroll: ScrollContainer = (item.node as WeakRef).get_ref() as ScrollContainer
			if is_instance_valid(scroll):
				scroll.custom_minimum_size = item.minimum
				scroll.size_flags_vertical = item.flags
		var window: Control = (record.node as WeakRef).get_ref() as Control
		if is_instance_valid(window):
			window.custom_minimum_size = record.minimum
			window.reset_size()
	_records.clear()
	_main = null
	_mod = null
