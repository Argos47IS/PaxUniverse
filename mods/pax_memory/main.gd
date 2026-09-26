extends PaxMod
## Narrow adapter: native request construction, provider, response schema and world rules remain authoritative.

const EVIDENCE_BUDGET: int = 2400
const MAX_MODEL_TEXT: int = 1000
const SAVE_VERSION: int = 1
var _store: RefCounted
var _game: PaxGame
var _provider: Node
var _native_status: Callable
var _connections: Array[Dictionary] = []
var _pending_state: Dictionary = {}
var _pending_game: PaxGame
var _preserved_state: Dictionary = {}
var _state_read_only: bool = false
var _last_selection: Dictionary = {}
var _retrieval_cache: Dictionary = {}
var _last_request_entities: Array = []
var _last_request_day: int = -1
var _last_context_chars: int = 0
var _enabled: bool = true
var _hooked: bool = false
var _unloaded: bool = false
var context_calls: int = 0
var cache_hits: int = 0
var _lifecycle_trace: Array[Dictionary] = []

func _mod_loaded() -> void:
    var store_script: Script = load_resource("memory_store.gd") as Script
    if store_script == null:
        log_warning(tr_key("pax_memory.unavailable"))
        return
    _store = store_script.new() as RefCounted
    _enabled = bool(get_setting("enabled", true))
    Pax.register_command("memory_status", _command_status, tr_key("pax_memory.command_help"))
    call_deferred("_catch_up")

func _catch_up() -> void:
    if not _unloaded and is_instance_valid(Pax.game) and _game != Pax.game:
        _world_ready(Pax.game)

func _world_ready(game: PaxGame) -> void:
    _trace_lifecycle("world_ready", game)
    if _unloaded or _store == null or not is_instance_valid(game):
        return
    if _same_world(_game, game):
        _game = game
        _attach_provider()
        return
    _detach()
    _game = game
    _apply_saved_state(_pending_state if _same_world(_pending_game, game) else {})
    _pending_state.clear()
    _pending_game = null
    _record_world()
    _attach_provider()

func _apply_saved_state(state: Dictionary) -> void:
    _trace_lifecycle("apply_saved_state", _game, state)
    _store.call("clear")
    _retrieval_cache.clear()
    _last_selection.clear()
    _last_context_chars = 0
    _preserved_state = state.duplicate(true)
    _state_read_only = false
    if state.is_empty():
        return
    var version: Variant = state.get("version")
    var valid_version: bool = (version is int or version is float) and float(version) == float(SAVE_VERSION)
    if not valid_version or not state.get("memory") is Dictionary:
        _state_read_only = true
    else:
        var imported: Dictionary = _store.call("import_state", state["memory"])
        _state_read_only = not bool(imported.get("ok", false))
    if _state_read_only:
        # Future or damaged data is returned verbatim on the next save. Do not
        # overwrite it with an empty store or inject partially understood evidence.
        log_warning(tr_key("pax_memory.invalid_save"))

func _attach_provider() -> void:
    if _hooked or _unloaded or not _enabled or _state_read_only or not is_instance_valid(_game):
        return
    if not is_instance_valid(_game.main) or not _has_property(_game.main, "provider"):
        log_warning(tr_key("pax_memory.incompatible"))
        return
    _provider = _game.main.get("provider") as Node
    if not is_instance_valid(_provider) or not _has_property(_provider, "статус_стороны"):
        log_warning(tr_key("pax_memory.incompatible"))
        return
    var callback: Variant = _provider.get("статус_стороны")
    if not callback is Callable:
        log_warning(tr_key("pax_memory.incompatible"))
        return
    var native: Callable = callback
    if not native.is_valid() or native.get_argument_count() != 0 or native == Callable(self, "_status_with_memory"):
        log_warning(tr_key("pax_memory.incompatible"))
        return
    _native_status = native
    _provider.set("статус_стороны", Callable(self, "_status_with_memory"))
    _hooked = true
    # These channels concern the player's assistant or a world report. Private
    # character dialogue and interpreted orders have no reliable owner metadata here.
    for signal_name: String in ["ответ_помощника", "итоги_готовы"]:
        if _compatible_response_signal(signal_name):
            var listener: Callable = Callable(self, "_observe_response").bind(signal_name)
            if _provider.is_connected(signal_name, listener):
                continue
            var error: Error = _provider.connect(signal_name, listener)
            if error == OK:
                _connections.append({"signal": signal_name, "listener": listener})
    var exit_listener: Callable = Callable(self, "_provider_exiting")
    if not _provider.is_connected("tree_exiting", exit_listener):
        var exit_error: Error = _provider.connect("tree_exiting", exit_listener)
        if exit_error == OK:
            _connections.append({"signal": "tree_exiting", "listener": exit_listener})
    log_info(tr_key("pax_memory.ready"))

func _game_loaded(game: PaxGame, state: Dictionary) -> void:
    _trace_lifecycle("game_loaded", game, state)
    _pending_game = game
    _pending_state = state.duplicate(true)
    if _same_world(_game, game) and _store != null:
        _game = game
        _detach()
        _apply_saved_state(_pending_state)
        _pending_game = null
        _pending_state.clear()
        _record_world()
        _attach_provider()

func _save_state(source: PaxGame) -> Dictionary:
    _trace_lifecycle("save_state", source)
    if _same_world(source, _pending_game):
        return _pending_state.duplicate(true)
    if not _same_world(source, _game):
        return {}
    if _state_read_only or _store == null:
        return _preserved_state.duplicate(true)
    var state: Dictionary = _preserved_state.duplicate(true)
    state["version"] = SAVE_VERSION
    state["memory"] = _store.call("export_state")
    return state

func _trace_lifecycle(stage: String, game: PaxGame, state: Dictionary = {}) -> void:
    var memory_state: Variant = state.get("memory")
    var records: int = -1
    if memory_state is Dictionary and (memory_state as Dictionary).get("records") is Array:
        records = ((memory_state as Dictionary)["records"] as Array).size()
    _lifecycle_trace.append({"stage": stage,
        "game_id": game.get_instance_id() if is_instance_valid(game) else 0,
        "main_id": game.main.get_instance_id() if is_instance_valid(game) and is_instance_valid(game.main) else 0,
        "active_game_id": _game.get_instance_id() if is_instance_valid(_game) else 0,
        "pending_game_id": _pending_game.get_instance_id() if is_instance_valid(_pending_game) else 0,
        "state_keys": state.keys(), "state_record_count": records})
    if _lifecycle_trace.size() > 40:
        _lifecycle_trace.pop_front()

func _days_passed(game: PaxGame, _from_day: int, _days: int) -> void:
    if _same_world(game, _game):
        _game = game
        _record_world()

func _same_world(first: PaxGame, second: PaxGame) -> bool:
    if not is_instance_valid(first) or not is_instance_valid(second):
        return false
    # Native save loading and world_ready use different PaxGame wrappers for
    # the same Main. Main is the live-world identity; a slot name is not enough.
    return first == second or (is_instance_valid(first.main) and is_instance_valid(second.main) and first.main == second.main)

func _record_world() -> void:
    if _state_read_only or _store == null or not is_instance_valid(_game):
        return
    var faction: Dictionary = _game.player_faction()
    var country: String = str(faction.get("имя", ""))
    var body: String = _game.focused_body()
    if body.is_empty():
        body = _game.home_body()
    var entities: Array = _scope_entities()
    if entities.is_empty():
        return
    # Structured state, no invented chronology or inference from a generated narrative.
    var facts: Dictionary = {"date": _game.date(), "body": body, "player": country}
    remember({"timestamp": _game.day(), "entities": entities, "type": "world_state", "fact_key": "current_state", "importance": 0.4, "confidence": 1.0, "source": "game_event", "text": JSON.stringify(facts), "tags": ["world"]})

func remember(record: Dictionary) -> Dictionary:
    if _unloaded or _store == null or _state_read_only:
        return {"ok": false, "error": "saved_state_read_only" if _state_read_only else "store_unavailable"}
    var old_revision: int = int(_store.get("revision"))
    var result: Dictionary = _store.call("add", record)
    if int(_store.get("revision")) != old_revision:
        _retrieval_cache.clear()
    return result

func context_for(query: String, entities: Array, day: int, budget_chars: int = EVIDENCE_BUDGET) -> Dictionary:
    if _unloaded or _store == null or _state_read_only:
        return {"text": "", "selected_ids": [], "reasons": [], "char_count": 0,
            "estimated_tokens_conservative": 0, "error": "saved_state_read_only" if _state_read_only else "store_unavailable"}
    # Include all query inputs and the store revision; changed world evidence cannot reuse a stale result.
    var cache_key: String = JSON.stringify([int(_store.get("revision")), query, entities, day, budget_chars])
    if _retrieval_cache.get("key", "") == cache_key:
        cache_hits += 1
        return (_retrieval_cache["value"] as Dictionary).duplicate(true)
    var selected: Dictionary = _store.call("retrieve", query, entities, day, budget_chars, 8)
    _retrieval_cache = {"key": cache_key, "value": selected.duplicate(true)}
    return selected

func _status_with_memory() -> String:
    var original: String = str(_native_status.call()) if _native_status.is_valid() else ""
    if _unloaded or not _enabled or _state_read_only or not is_instance_valid(_game):
        return original
    context_calls += 1
    var entities: Array = _scope_entities()
    _last_context_chars = 0
    if entities.is_empty():
        return original
    _last_request_entities = entities.duplicate()
    _last_request_day = _game.day()
    # The native callback has no request argument. Scope by active world/player;
    # exact task-aware retrieval is exposed by context_for, not fabricated here.
    var prefix: String = "\n\n<PAX_MEMORY>\n" + tr_key("pax_memory.context_header") + "\n"
    var suffix: String = "\n</PAX_MEMORY>"
    var budget: int = maxi(0, EVIDENCE_BUDGET - prefix.length() - suffix.length())
    _last_selection = context_for("", entities, _game.day(), budget)
    var text: String = str(_last_selection.get("text", ""))
    if text.is_empty():
        return original
    _last_context_chars = prefix.length() + text.length() + suffix.length()
    return original + prefix + text + suffix

func _observe_response(value: Variant, channel: String) -> void:
    if _unloaded or _state_read_only or not _enabled or not is_instance_valid(_game) or not value is Dictionary:
        return
    if _last_request_day != _game.day() or _last_request_entities != _scope_entities():
        return
    var response: Dictionary = value
    var text_value: Variant = response.get("ответ", response.get("answer", response.get("текст", "")))
    if not text_value is String:
        return
    var text: String = text_value
    if text.strip_edges().is_empty():
        return
    var entities: Array = _last_request_entities.duplicate()
    remember({"timestamp": _game.day(), "entities": entities, "type": "dialogue", "importance": 0.35, "confidence": 0.35, "source": "ai_response", "text": text.left(MAX_MODEL_TEXT), "tags": [channel]})

func _scope_entities() -> Array:
    var entities: Array = []
    if not is_instance_valid(_game):
        return entities
    var body: String = _game.focused_body()
    if body.is_empty():
        body = _game.home_body()
    if not body.is_empty():
        entities.append(body)
    var country: String = str(_game.player_faction().get("имя", ""))
    if not country.is_empty() and not entities.has(country):
        entities.append(country)
    return entities

func _compatible_response_signal(signal_name: String) -> bool:
    for description: Dictionary in _provider.get_signal_list():
        if str(description.get("name", "")) != signal_name:
            continue
        var args: Array = description.get("args", [])
        if args.size() != 1:
            return false
        var argument: Dictionary = args[0]
        return int(argument.get("type", TYPE_NIL)) in [TYPE_NIL, TYPE_DICTIONARY]
    return false

func _provider_exiting() -> void:
    _detach()

func _has_property(object: Object, name: String) -> bool:
    for property: Dictionary in object.get_property_list():
        if str(property.name) == name:
            return true
    return false

func _command_status(_args: PackedStringArray) -> String:
    var records: int = int(_store.call("count")) if _store != null else 0
    return tr_key("pax_memory.status") % [records, tr_key("pax_memory.enabled" if _hooked else "pax_memory.disabled"), _last_context_chars]

func _detach() -> void:
    if is_instance_valid(_provider):
        for item: Dictionary in _connections:
            if _provider.is_connected(str(item.signal), item.listener):
                _provider.disconnect(str(item.signal), item.listener)
        if _hooked and _provider.get("статус_стороны") == Callable(self, "_status_with_memory"):
            _provider.set("статус_стороны", _native_status)
    _connections.clear()
    _retrieval_cache.clear()
    _last_selection.clear()
    _last_request_entities.clear()
    _last_request_day = -1
    _last_context_chars = 0
    _provider = null
    _native_status = Callable()
    _hooked = false

func _mod_unloaded() -> void:
    _unloaded = true
    _detach()
    _game = null
    _pending_game = null
    _pending_state.clear()
