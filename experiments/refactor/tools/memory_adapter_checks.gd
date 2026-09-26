extends RefCounted
## Synchronous integration checks for an already loaded mod in an isolated QA world.
## Only the test mod's state and callback are temporarily changed and then restored.

class ProviderFixture:
	extends Node
	signal ответ_помощника(value: Dictionary)
	signal итоги_готовы(first: Dictionary, second: Dictionary)
	var статус_стороны: Callable

var _checks: Dictionary = {}
var _probe_native: Callable
var _probe_calls: int = 0
var _probe_result: String = ""


func start(game: PaxGame) -> Dictionary:
	_checks.clear()
	var memory: Node = Pax.get_mod("pax_memory") as Node
	_expect("loaded_memory_mod", is_instance_valid(memory) and bool(memory.get("_hooked")))
	if not is_instance_valid(memory) or not bool(memory.get("_hooked")):
		return _finish()
	var provider: Node = memory.get("_provider") as Node
	var original_state: Dictionary = memory.call("_save_state", game)
	var original_callback: Callable = memory.get("_native_status")
	var installed_callback: Callable = provider.get("статус_стороны")
	_probe_native = original_callback
	_probe_calls = 0
	_probe_result = ""
	memory.set("_native_status", Callable(self, "_count_native"))
	var augmented: String = str(installed_callback.call())
	memory.set("_native_status", original_callback)
	_expect("native_callback_delegated_once_and_preserved", _probe_calls == 1 and augmented.begins_with(_probe_result))
	var addition_chars: int = augmented.length() - _probe_result.length()
	_expect("complete_context_suffix_bounded", addition_chars > 0 and addition_chars <= 2400 and augmented.contains("<PAX_MEMORY>") and augmented.ends_with("</PAX_MEMORY>"))
	var entities: Array = memory.call("_scope_entities")
	var day: int = game.day()
	var query: String = "qa_memory_cache_probe"
	memory.call("context_for", query, entities, day)
	var before_hits: int = int(memory.get("cache_hits"))
	var repeated: Dictionary = memory.call("context_for", query, entities, day)
	_expect("identical_context_uses_cache", int(memory.get("cache_hits")) == before_hits + 1)
	var record: Dictionary = {"text": query + " verified event", "timestamp": day, "entities": entities,
		"type": "event", "source": "game_event", "importance": 1.0, "confidence": 1.0, "tags": []}
	var added: Dictionary = memory.call("remember", record)
	var after_add: Dictionary = memory.call("context_for", query, entities, day)
	_expect("mutation_invalidates_context_cache", added.get("ok", false) and int(after_add.get("revision", 0)) > int(repeated.get("revision", 0)) and str(after_add.get("text", "")).contains(query))
	var cached: Dictionary = memory.call("context_for", query, entities, day)
	cached["text"] = "external mutation"
	cached["selected_ids"].append("external mutation")
	if not cached["reasons"].is_empty():
		cached["reasons"][0]["score"] = -999.0
	var untouched: Dictionary = memory.call("context_for", query, entities, day)
	_expect("cached_results_are_deep_copies", str(untouched["text"]) != "external mutation" and not untouched["selected_ids"].has("external mutation") and not untouched["reasons"].is_empty() and float(untouched["reasons"][0]["score"]) >= 0.0)
	var connections: Array = memory.get("_connections")
	var private_dialogue_connected: bool = false
	for connection: Dictionary in connections:
		if str(connection["signal"]) in ["готово", "ответ_собеседника", "человек_готов"]:
			private_dialogue_connected = true
	_expect("private_dialogue_and_orders_not_globally_observed", not private_dialogue_connected)
	var own_listeners: Array = connections.duplicate(true)
	memory.call("_detach")
	var removed: bool = true
	for connection: Dictionary in own_listeners:
		if provider.is_connected(str(connection["signal"]), connection["listener"]):
			removed = false
	_expect("detach_restores_native_and_removes_owned_signals", provider.get("статус_стороны") == original_callback and removed)
	memory.call("_world_ready", game)
	_expect("reattach_same_world_restores_wrapper_once", bool(memory.get("_hooked")) and provider.get("статус_стороны") == Callable(memory, "_status_with_memory") and (memory.get("_connections") as Array).size() == own_listeners.size())
	# A separate non-tree fixture tests corrupt/future saves without poisoning the active mod.
	var fixture: Node = (memory.get_script() as Script).new() as Node
	var live_store: RefCounted = memory.get("_store") as RefCounted
	var fixture_store: RefCounted = (live_store.get_script() as Script).new() as RefCounted
	fixture.set("id", "pax_memory_test_fixture")
	fixture.set("_store", fixture_store)
	fixture.set("_game", game)
	fixture.set("_enabled", false)
	fixture.call("remember", record)
	var fixture_before: Dictionary = fixture.call("context_for", query, entities, day)
	fixture.call("_game_loaded", game, {})
	var fixture_after: Dictionary = fixture.call("context_for", query, entities, day)
	_expect("new_state_clears_old_records_and_cached_context", str(fixture_before["text"]).contains(query) and not str(fixture_after["text"]).contains(query) and int(fixture_after["revision"]) > int(fixture_before["revision"]))
	var future: Dictionary = {"version": 99, "memory": {"future_format": ["retain", {"nested": 7}]}, "extra": "preserve"}
	fixture.call("_game_loaded", game, future)
	var frozen_add: Dictionary = fixture.call("remember", record)
	var frozen_context: Dictionary = fixture.call("context_for", query, entities, day)
	var saved_future: Dictionary = fixture.call("_save_state", game)
	var preserved_once: bool = JSON.stringify(saved_future) == JSON.stringify(future)
	saved_future["memory"]["future_format"].append("outside mutation")
	var saved_again: Dictionary = fixture.call("_save_state", game)
	_expect("future_save_round_trip_without_mutation_or_injection", preserved_once and JSON.stringify(saved_again) == JSON.stringify(future) and not frozen_add.get("ok", true) and str(frozen_context["text"]).is_empty())
	var corrupt: Dictionary = {"version": 1, "memory": {"version": 1, "revision": 0, "records": [{"broken": true}]}}
	fixture.call("_game_loaded", game, corrupt)
	_expect("damaged_known_version_retained_verbatim", JSON.stringify(fixture.call("_save_state", game)) == JSON.stringify(corrupt) and bool(fixture.get("_state_read_only")))
	var test_provider: ProviderFixture = ProviderFixture.new()
	fixture.set("_provider", test_provider)
	_expect("signal_argument_shape_checked_before_connect", bool(fixture.call("_compatible_response_signal", "ответ_помощника")) and not bool(fixture.call("_compatible_response_signal", "итоги_готовы")) and not bool(fixture.call("_has_property", test_provider, "missing_property")))
	var third_party_callback: Callable = Callable(self, "_third_party_status")
	test_provider.статус_стороны = third_party_callback
	fixture.set("_native_status", original_callback)
	fixture.set("_hooked", true)
	fixture.call("_detach")
	_expect("detach_does_not_overwrite_another_owner", test_provider.статус_стороны == third_party_callback and provider.get("статус_стороны") == Callable(memory, "_status_with_memory"))
	# Native 0.15.1 emits loaded and world_ready using distinct PaxGame wrappers
	# bound to one Main. A wrapper identity check would silently drop this payload.
	var payload_store: RefCounted = (live_store.get_script() as Script).new() as RefCounted
	payload_store.call("add", record)
	var payload: Dictionary = {"version": 1, "memory": payload_store.call("export_state")}
	var second_wrapper: PaxGame = (game.get_script() as Script).new(game.main) as PaxGame
	fixture.set("_game", null)
	fixture.call("_game_loaded", game, payload)
	fixture.call("_world_ready", second_wrapper)
	var transferred: Dictionary = fixture.call("context_for", query, entities, day)
	var transferred_save: Dictionary = fixture.call("_save_state", game)
	_expect("distinct_wrappers_for_same_main_keep_loaded_memory", second_wrapper != game and str(transferred["text"]).contains(query) and not transferred_save.is_empty())
	var foreign_main: Node = Node.new()
	var foreign_wrapper: PaxGame = (game.get_script() as Script).new(game.main) as PaxGame
	foreign_wrapper.main = foreign_main
	fixture.set("_game", null)
	fixture.call("_game_loaded", foreign_wrapper, payload)
	fixture.call("_world_ready", game)
	var rejected_foreign: Dictionary = fixture.call("context_for", query, entities, day)
	_expect("different_main_does_not_adopt_pending_memory", not bool(fixture.call("_same_world", foreign_wrapper, game)) and not str(rejected_foreign["text"]).contains(query))
	fixture.free()
	test_provider.free()
	foreign_main.free()
	# Restore the active mod's journal through the same save lifecycle as the game.
	memory.call("_game_loaded", game, original_state)
	var final_context: Dictionary = memory.call("context_for", query, entities, day)
	_expect("active_mod_restored_after_checks", bool(memory.get("_hooked")) and provider.get("статус_стороны") == Callable(memory, "_status_with_memory") and not str(final_context["text"]).contains(query))
	_probe_native = Callable()
	var benchmark: Dictionary = _microbenchmark(memory)
	_expect("microbenchmark_paths_preserve_context_and_ids", bool(benchmark["results_identical"]) and bool(benchmark["cache_hits_verified"]))
	var report: Dictionary = _finish()
	report["microbenchmark"] = benchmark
	return report


func _microbenchmark(memory: Node) -> Dictionary:
	# This is a one-machine microbenchmark of retrieval work, not game FPS, model
	# inference, networking or a whole-game before/after performance measurement.
	# Build a separate non-tree adapter/store; never touch the live journal or callback.
	var fixture: Node = (memory.get_script() as Script).new() as Node
	var live_store: RefCounted = memory.get("_store") as RefCounted
	var store: RefCounted = (live_store.get_script() as Script).new() as RefCounted
	fixture.set("_store", store)
	fixture.set("_enabled", false)
	var entities: Array = ["Земля", "Benchmarkland"]
	for index: int in range(2048):
		var scope: Array = entities.duplicate() if index < 48 else ["Земля", "Otherland%d" % index]
		store.call("add", {"text": "Synthetic continuity report %d" % index,
			"timestamp": index, "entities": scope, "type": "event", "source": "game_event",
			"importance": 0.5, "confidence": 1.0, "tags": ["benchmark"]})
	var query: String = "continuity"
	var day: int = 4096
	var iterations: int = 200
	var reference: Dictionary = store.call("retrieve", query, entities, day, 2400, 8)
	var expected_ids: Array = reference["selected_ids"]
	var expected_signature: String = JSON.stringify([reference["text"], expected_ids])
	var expected_checksum: String = expected_signature.sha256_text()
	var results_identical: bool = int(store.call("count")) == 2048 and expected_ids.size() == 8
	var cache_hits_verified: bool = true
	var batches: Array[Dictionary] = []
	for batch: int in range(3):
		# Warm the same single-entry cache before each batch. Alternate measurement
		# order; correctness hashing runs afterwards and is excluded from both timings.
		fixture.call("context_for", query, entities, day, 2400)
		var paths: Array[String] = ["cached", "uncached"]
		if batch % 2 == 1:
			paths.reverse()
		var measurement: Dictionary = {"batch": batch + 1, "order": paths.duplicate(),
			"operations_per_path": iterations, "context_checksum_sha256": expected_checksum}
		for path: String in paths:
			var outputs: Array[Dictionary] = []
			var old_hits: int = int(fixture.get("cache_hits"))
			var started: int = Time.get_ticks_usec()
			for operation: int in range(iterations):
				if path == "cached":
					outputs.append(fixture.call("context_for", query, entities, day, 2400))
				else:
					outputs.append(store.call("retrieve", query, entities, day, 2400, 8))
			var elapsed_us: int = Time.get_ticks_usec() - started
			var hit_delta: int = int(fixture.get("cache_hits")) - old_hits
			var identical: bool = outputs.size() == iterations
			for output: Dictionary in outputs:
				var signature: String = JSON.stringify([output["text"], output["selected_ids"]])
				if output["selected_ids"] != expected_ids or signature.sha256_text() != expected_checksum:
					identical = false
			measurement[path + "_us"] = elapsed_us
			measurement[path + "_us_per_operation"] = float(elapsed_us) / float(iterations)
			measurement[path + "_cache_hits"] = hit_delta
			measurement[path + "_results_identical"] = identical
			results_identical = results_identical and identical
			cache_hits_verified = cache_hits_verified and hit_delta == (iterations if path == "cached" else 0)
		batches.append(measurement)
	fixture.free()
	return {"records": int(store.call("count")), "matching_scope_records": 48,
		"selected_records": expected_ids.size(), "batches": batches,
		"results_identical": results_identical, "cache_hits_verified": cache_hits_verified,
		"measurement": "one-machine synchronous microbenchmark; microseconds; not game FPS",
		"timed_work": "actual adapter context_for cache vs actual store retrieve; result-array append in both; setup and checksum verification excluded",
		"limitations": "Repeated identical query with warm cache and 48 candidates. Does not measure changing queries, model latency or overall frame rate. No assertion that caching is faster."}


func _count_native() -> String:
	_probe_calls += 1
	_probe_result = str(_probe_native.call())
	return _probe_result


func _third_party_status() -> String:
	return "third-party owner"


func _expect(name: String, passed: bool) -> void:
	_checks[name] = passed


func _finish() -> Dictionary:
	var failures: Array[String] = []
	for name: String in _checks:
		if not _checks[name]:
			failures.append(name)
	return {"ok": failures.is_empty(), "check_count": _checks.size(), "checks": _checks.duplicate(), "failures": failures}
