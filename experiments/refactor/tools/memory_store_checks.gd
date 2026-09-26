extends RefCounted
## External checks: keep this file outside the installed mod.

var _checks: Dictionary = {}


func start(store_script: Variant) -> Dictionary:
	_checks.clear()
	var store: Variant = store_script.new()
	var first: Dictionary = store.add(_record("Россия заключила мир", ["Земля", "Россия"], 10))
	_expect("add_record", first.get("ok", false) and store.count() == 1)
	var first_revision: int = int(store.revision)
	var same: Dictionary = _record("  РОССИЯ  заключила\nмир ", ["россия", "земля"], 10)
	var duplicate: Dictionary = store.add(same)
	_expect("normalized_dedup", duplicate.get("duplicate", false) and duplicate.get("id") == first.get("id") and store.count() == 1)
	_expect("unchanged_duplicate_keeps_revision", int(store.revision) == first_revision)
	store.add(_record("Россия заключила мир", ["Земля", "Россия"], 20))
	_expect("new_observation_updates_freshness_without_copy", store.count() == 1 and int(store.export_state()["records"][0]["timestamp"]) == 20)
	store.add(_record("Франция заключила мир", ["Земля", "Франция"], 21))
	var scoped: Dictionary = store.retrieve("мир", ["Земля", "Россия"], 30)
	_expect("all_entities_required_not_union", scoped["selected_ids"].size() == 1 and not str(scoped["text"]).contains("Франция"))
	_expect("entity_names_are_exact", store.retrieve("мир", ["Рос"], 30)["selected_ids"].is_empty())
	_expect("unknown_entity_returns_empty", store.retrieve("мир", ["Несуществующая страна"], 30)["selected_ids"].is_empty())
	_expect("query_terms_match_without_entities", store.retrieve("Франция", [], 30)["selected_ids"].size() == 1)
	_expect("unrelated_query_does_not_inject_random_facts", store.retrieve("квантовая телепортация", [], 30)["selected_ids"].is_empty())
	_expect("source_and_confidence_in_evidence", str(scoped["text"]).contains("source=\"game_event\"") and str(scoped["text"]).contains("confidence=1.00"))
	_expect("explain_selection", scoped["reasons"].size() == 1 and scoped["reasons"][0]["matched_terms"].has("мир"))
	var saved: Dictionary = store.export_state()
	saved["records"][0]["text"] = "Изменено снаружи"
	_expect("export_is_deep_copy", not str(store.retrieve("мир", ["Россия"], 30)["text"]).contains("Изменено снаружи"))
	var source_record: Dictionary = _record("Исходная запись", ["Луна"], 5)
	store.add(source_record)
	source_record["entities"].append("Франция")
	source_record["text"] = "Изменено снаружи"
	_expect("input_is_not_aliased", store.retrieve("Исходная", ["Луна", "Франция"], 30)["selected_ids"].is_empty())
	var tagged: Dictionary = _record("Согласована поставка", ["Марс"], 7)
	tagged["tags"] = ["экономика"]
	store.add(tagged)
	var tag_result: Dictionary = store.retrieve("экономика", [], 30)
	_expect("tag_index_used", tag_result["selected_ids"].size() == 1 and tag_result["reasons"][0]["matched_tags"].has("экономика"))
	var pending: Dictionary = _record("Постройте лунную базу", ["Луна"], 8)
	pending["type"] = "order"
	pending["status"] = "pending"
	store.add(pending)
	var completed: Dictionary = _record("Постройте марсианскую базу", ["Марс"], 8)
	completed["type"] = "completed_order"
	completed["status"] = "executed"
	store.add(completed)
	_expect("orders_never_become_facts", store.retrieve("Постройте", [], 30)["selected_ids"].is_empty())
	_expect("commands_remain_in_journal", store.count() == 6)
	store.add(_record("Событие из будущего", ["Венера"], 100))
	_expect("future_evidence_excluded", store.retrieve("", ["Венера"], 99)["selected_ids"].is_empty())
	var invalid: Dictionary = _record("Испорченный вес", [], 1)
	invalid["confidence"] = NAN
	_expect("nonfinite_weight_rejected", not store.add(invalid).get("ok", true))
	invalid = _record("Неверная дата", [], 1)
	invalid["timestamp"] = 1.5
	_expect("fractional_day_rejected", not store.add(invalid).get("ok", true))
	invalid = _record("Неверные сущности", [], 1)
	invalid["entities"] = [42]
	_expect("nonstring_entity_rejected", not store.add(invalid).get("ok", true))
	var same_id: Dictionary = _record("Другое событие", [], 1)
	same_id["id"] = first["id"]
	_expect("explicit_id_collision_rejected", not store.add(same_id).get("ok", true))
	var long_store: Variant = store_script.new()
	long_store.add(_record("😀я".repeat(700), ["Земля"], 1))
	_expect("record_text_bounded_in_unicode_characters", str(long_store.export_state()["records"][0]["text"]).length() == 1200)
	var unicode_context: Dictionary = long_store.retrieve("", ["Земля"], 2, 1400)
	var unicode_text: String = str(unicode_context["text"])
	_expect("unicode_context_budget", not unicode_text.is_empty() and unicode_text.length() <= 1400 and unicode_context["char_count"] == unicode_text.length())
	_expect("token_estimate_explicit_not_exact", unicode_context["estimated_tokens_conservative"] == unicode_text.to_utf8_buffer().size() and str(unicode_context["token_estimate_method"]).contains("not_exact"))
	_expect("too_small_budget_never_truncates_fact", long_store.retrieve("", ["Земля"], 2, 100)["selected_ids"].is_empty())
	_expect("zero_budget_empty", long_store.retrieve("", [], 2, 0)["text"] == "")
	_expect("negative_budget_empty", long_store.retrieve("", [], 2, -1)["text"] == "")
	_expect("zero_limit_empty", long_store.retrieve("", [], 2, 1400, 0)["selected_ids"].is_empty())
	var quoted_store: Variant = store_script.new()
	quoted_store.add(_record("Первая строка\n\"вторая строка\"", [], 1))
	var quoted: String = str(quoted_store.retrieve("", [], 2)["text"])
	_expect("evidence_quoted_one_line", not quoted.contains("\n") and quoted.contains("\\n") and quoted.contains("\\\""))
	var facts: Variant = store_script.new()
	var peace: Dictionary = _record("Война продолжается", ["Россия"], 10)
	peace["fact_key"] = "war_status"
	facts.add(peace)
	var ended: Dictionary = _record("Война закончилась", ["Россия"], 20)
	ended["fact_key"] = "war_status"
	facts.add(ended)
	_expect("explicit_fact_supersession", facts.count() == 1 and str(facts.retrieve("война", ["Россия"], 30)["text"]).contains("закончилась"))
	_expect("superseded_fact_not_retrievable", not str(facts.retrieve("продолжается", ["Россия"], 30)["text"]).contains("продолжается"))
	_expect("older_fact_rejected", not facts.add(peace).get("ok", true) and facts.count() == 1)
	ended["timestamp"] = 40
	facts.add(ended)
	peace["timestamp"] = 35
	_expect("newer_duplicate_protects_fact_watermark", not facts.add(peace).get("ok", true))
	var another_country: Dictionary = _record("Война продолжается", ["Франция"], 41)
	another_country["fact_key"] = "war_status"
	facts.add(another_country)
	_expect("fact_keys_scoped_by_entities", facts.count() == 2 and str(facts.retrieve("", ["Россия"], 50)["text"]).contains("закончилась"))
	var claim: Dictionary = _record("Война началась снова", ["Россия"], 42)
	claim["fact_key"] = "war_status"
	claim["source"] = "model_claim"
	claim["confidence"] = 0.5
	facts.add(claim)
	_expect("untrusted_claim_does_not_replace_game_fact", facts.count() == 3 and str(facts.retrieve("", ["Россия"], 50)["text"]).contains("закончилась"))
	var confirmation_store: Variant = store_script.new()
	var uncertain: Dictionary = _record("Война закончилась", ["Россия"], 12)
	uncertain["confidence"] = 0.5
	confirmation_store.add(uncertain)
	var ongoing: Dictionary = _record("Война продолжается", ["Россия"], 20)
	ongoing["fact_key"] = "war_status"
	confirmation_store.add(ongoing)
	var confirmation: Dictionary = _record("Война закончилась", ["Россия"], 30)
	confirmation["fact_key"] = "war_status"
	confirmation_store.add(confirmation)
	_expect("verified_duplicate_removes_conflicting_previous_fact", confirmation_store.count() == 1 and not str(confirmation_store.retrieve("", ["Россия"], 40)["text"]).contains("продолжается"))
	_expect("verified_duplicate_raises_confidence", float(confirmation_store.export_state()["records"][0]["confidence"]) == 1.0)
	var restored: Variant = store_script.new()
	var load_result: Dictionary = restored.import_state(facts.export_state())
	_expect("version_one_round_trip", load_result.get("ok", false) and restored.count() == facts.count())
	_expect("restored_fact_index_rejects_stale", not restored.add(peace).get("ok", true))
	var before: String = JSON.stringify(restored.export_state())
	var corrupt: Dictionary = facts.export_state()
	corrupt["records"].append({"text": "Нет обязательных полей"})
	_expect("corrupted_import_rejected_atomically", not restored.import_state(corrupt).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	corrupt = facts.export_state()
	corrupt["version"] = 2
	_expect("unknown_version_rejected_atomically", not restored.import_state(corrupt).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	corrupt = facts.export_state()
	corrupt["records"][0]["importance"] = INF
	_expect("nonfinite_import_rejected_atomically", not restored.import_state(corrupt).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	corrupt = facts.export_state()
	corrupt["records"].append(corrupt["records"][0].duplicate(true))
	_expect("duplicate_import_rejected_atomically", not restored.import_state(corrupt).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	corrupt = facts.export_state()
	var conflict: Dictionary = corrupt["records"][0].duplicate(true)
	conflict["id"] = "conflict"
	conflict["text"] = "Старый противоречащий факт"
	corrupt["records"].append(conflict)
	_expect("conflicting_fact_import_rejected_atomically", not restored.import_state(corrupt).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	var legacy: Array = [_record("Старое событие", ["Луна"], 2)]
	_expect("legacy_requires_opt_in", not restored.import_state(legacy).get("ok", true) and JSON.stringify(restored.export_state()) == before)
	var legacy_result: Dictionary = restored.import_state(legacy, true)
	_expect("explicit_legacy_migration", legacy_result.get("ok", false) and legacy_result.get("migrated_legacy", false) and restored.count() == 1)
	var prior_clear_revision: int = int(restored.revision)
	restored.clear()
	_expect("world_clear_removes_records_and_indexes", restored.count() == 0 and restored.retrieve("", ["Луна"], 3)["selected_ids"].is_empty())
	_expect("world_clear_advances_revision", int(restored.revision) > prior_clear_revision)
	var after_clear: Dictionary = restored.add(_record("Мир в новой партии", ["Луна"], 0))
	_expect("new_world_does_not_share_old_dedup", after_clear.get("ok", false) and not after_clear.get("duplicate", true))
	var capped: Variant = store_script.new()
	var begin_us: int = Time.get_ticks_usec()
	for index: int in range(2050):
		capped.add(_record("Событие %d" % index, ["Сущность%d" % index], index))
	var ingestion_us: int = Time.get_ticks_usec() - begin_us
	_expect("bounded_record_count", capped.count() == 2048)
	_expect("evicted_record_removed_from_indexes", capped.retrieve("", ["Сущность0"], 3000)["selected_ids"].is_empty())
	_expect("newest_record_kept", capped.retrieve("", ["Сущность2049"], 3000)["selected_ids"].size() == 1)
	begin_us = Time.get_ticks_usec()
	for index: int in range(100):
		capped.retrieve("Событие", ["Сущность2049"], 3000)
	var retrieve_us: int = Time.get_ticks_usec() - begin_us
	var failures: Array[String] = []
	for key: String in _checks:
		if not _checks[key]:
			failures.append(key)
	return {"ok": failures.is_empty(), "checks": _checks.duplicate(), "check_count": _checks.size(),
		"failures": failures, "metrics": {"records": capped.count(), "ingest_2050_us": ingestion_us,
		"retrieve_100_scoped_us": retrieve_us, "timings_are_single_run_microseconds": true}}


func _record(text: String, entities: Array, day: int) -> Dictionary:
	return {"text": text, "entities": entities, "timestamp": day, "type": "event",
		"source": "game_event", "importance": 0.5, "confidence": 1.0, "tags": []}


func _expect(name: String, condition: bool) -> void:
	_checks[name] = condition
