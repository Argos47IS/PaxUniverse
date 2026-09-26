extends RefCounted
## Bounded, world-local records. Retrieval returns quoted evidence, never executed orders.
## Token counts are an explicit UTF-8 byte estimate, not a model tokenizer result.

const VERSION: int = 1
const MAX_RECORDS: int = 2048
const MAX_TEXT_CHARS: int = 1200
const MAX_LABELS: int = 16
const MAX_BUDGET_CHARS: int = 24000
const MAX_SAFE_INTEGER: int = 9007199254740991

var revision: int = 0
var _next_id: int = 1
var _records: Dictionary = {}
var _order: Array[String] = []
var _dedup: Dictionary = {}
var _by_entity: Dictionary = {}
var _by_tag: Dictionary = {}
var _facts: Dictionary = {}
var _terms: Dictionary = {}


func count() -> int:
	return _records.size()


func clear() -> void:
	_records.clear()
	_order.clear()
	_dedup.clear()
	_by_entity.clear()
	_by_tag.clear()
	_facts.clear()
	_terms.clear()
	_next_id = 1
	revision += 1


func add(record: Dictionary) -> Dictionary:
	var checked: Dictionary = _validate_record(record, false)
	if not checked.get("ok", false):
		return checked
	var item: Dictionary = checked["record"]
	var fingerprint: String = _fingerprint(item)
	var fact_slot: String = _fact_slot(item)
	var previous_id: String = str(_facts.get(fact_slot, "")) if not fact_slot.is_empty() else ""
	if not previous_id.is_empty():
		var previous: Dictionary = _records[previous_id]
		if int(item["timestamp"]) < int(previous["timestamp"]):
			return {"ok": false, "error": "stale_fact", "id": previous_id}
	if _dedup.has(fingerprint):
		var same_id: String = str(_dedup[fingerprint])
		var same: Dictionary = _records[same_id]
		var same_slot: String = _fact_slot(same)
		if not fact_slot.is_empty() and not same_slot.is_empty() and fact_slot != same_slot:
			return {"ok": false, "error": "ambiguous_duplicate_fact_key", "id": same_id}
		var changed: bool = false
		if not fact_slot.is_empty():
			if not previous_id.is_empty() and previous_id != same_id:
				_remove(previous_id)
				changed = true
			if same_slot.is_empty():
				# A verified observation may confirm an older low-confidence copy.
				# Keep the confirmed timestamp, not the timestamp of an unverified claim.
				same["timestamp"] = item["timestamp"]
				same["confidence"] = 1.0
				same["fact_key"] = item["fact_key"]
				changed = true
			_facts[fact_slot] = same_id
		# A later observation advances freshness without adding another copy.
		# This also prevents an older conflicting fact replacing a newer confirmation.
		if int(item["timestamp"]) > int(same["timestamp"]):
			same["timestamp"] = item["timestamp"]
			changed = true
		if changed:
			revision += 1
		return {"ok": true, "id": same_id, "duplicate": true}
	var item_id: String = str(item["id"])
	if not item_id.is_empty() and _records.has(item_id):
		return {"ok": false, "error": "duplicate_id", "id": item_id}
	if item_id.is_empty():
		item_id = "m%d" % _next_id
		while _records.has(item_id):
			_next_id += 1
			item_id = "m%d" % _next_id
		_next_id += 1
		item["id"] = item_id
	if not previous_id.is_empty():
		_remove(previous_id)
	while _records.size() >= MAX_RECORDS:
		_remove(_order[0])
	_insert(item)
	revision += 1
	return {"ok": true, "id": item_id, "duplicate": false}


func retrieve(query: String, entities: Array, day: int, budget_chars: int = 2400, limit: int = 8) -> Dictionary:
	var result: Dictionary = {
		"text": "", "selected_ids": [], "reasons": [], "revision": revision,
		"char_count": 0, "estimated_tokens_conservative": 0,
		"token_estimate_method": "utf8_bytes_upper_estimate_not_exact"
	}
	var budget: int = clampi(budget_chars, 0, MAX_BUDGET_CHARS)
	var take: int = clampi(limit, 0, 64)
	if budget == 0 or take == 0:
		return result
	var entity_check: Dictionary = _validate_labels(entities, 96)
	if not entity_check.get("ok", false):
		result["error"] = "invalid_query_entities"
		return result
	var requested: Array = entity_check["values"]
	var candidates: Dictionary = {}
	if requested.is_empty():
		for item_id: String in _order:
			candidates[item_id] = true
	else:
		# Intersection: Earth + Russia must never admit an Earth + France record.
		var first: bool = true
		for entity: String in requested:
			var bucket: Dictionary = _by_entity.get(_normal(entity), {})
			if first:
				candidates = bucket.duplicate()
				first = false
			else:
				for item_id: String in candidates.keys():
					if not bucket.has(item_id):
						candidates.erase(item_id)
	var query_terms: Array[String] = _words(query.substr(0, MAX_TEXT_CHARS))
	var tag_hits: Dictionary = {}
	for term: String in query_terms:
		var tag_bucket: Dictionary = _by_tag.get(term, {})
		for item_id: String in tag_bucket:
			var hits: Array = tag_hits.get(item_id, [])
			hits.append(term)
			tag_hits[item_id] = hits
	var ranked: Array[Dictionary] = []
	for item_id: String in candidates:
		var item: Dictionary = _records[item_id]
		if _is_order(item) or int(item["timestamp"]) > day:
			continue
		var item_terms: Dictionary = _terms[item_id]
		var matches: Array[String] = []
		for term: String in query_terms:
			if item_terms.has(term):
				matches.append(term)
		var tags: Array = tag_hits.get(item_id, [])
		if requested.is_empty() and not query_terms.is_empty() and matches.is_empty() and tags.is_empty():
			continue
		var age: int = maxi(0, day - int(item["timestamp"]))
		var relevance: float = float(matches.size()) / float(maxi(1, query_terms.size()))
		var score: float = relevance * 4.0 + float(requested.size()) * 2.0
		score += 1.0 / (1.0 + float(age) / 30.0)
		score += float(item["importance"]) * 1.5 + float(item["confidence"])
		score += minf(1.0, float(tags.size()) * 0.25)
		ranked.append({"id": item_id, "score": score, "matched_entities": requested.duplicate(),
			"matched_terms": matches, "matched_tags": tags, "age_days": age,
			"importance": item["importance"], "confidence": item["confidence"]})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) > float(b["score"])
		return str(a["id"]) < str(b["id"])
	)
	var lines: Array[String] = []
	var used: int = 0
	for reason: Dictionary in ranked:
		var item: Dictionary = _records[str(reason["id"])]
		# JSON quoting keeps line breaks and quotes inside the evidence field.
		var line: String = "[day=%d source=%s type=%s confidence=%.2f] %s" % [
			int(item["timestamp"]), JSON.stringify(item["source"]), JSON.stringify(item["type"]),
			float(item["confidence"]), JSON.stringify(item["text"])]
		var cost: int = line.length() + (1 if not lines.is_empty() else 0)
		if used + cost > budget:
			continue
		lines.append(line)
		used += cost
		result["selected_ids"].append(item["id"])
		result["reasons"].append(reason)
		if lines.size() >= take:
			break
	var context: String = "\n".join(lines)
	result["text"] = context
	result["char_count"] = context.length()
	# Most byte-based tokenizers use <= one token per UTF-8 byte. No tokenizer is loaded.
	# This estimate covers returned evidence only, not the surrounding prompt or reply.
	result["estimated_tokens_conservative"] = context.to_utf8_buffer().size()
	return result


func export_state() -> Dictionary:
	var records: Array[Dictionary] = []
	for item_id: String in _order:
		records.append(_records[item_id].duplicate(true))
	return {"version": VERSION, "revision": revision, "next_id": _next_id, "records": records}


func import_state(value: Variant, allow_legacy: bool = false) -> Dictionary:
	var incoming: Array = []
	var incoming_revision: int = 0
	var incoming_next_id: int = 1
	var legacy: bool = value is Array and allow_legacy
	if legacy:
		incoming = value
	elif value is Dictionary:
		var state: Dictionary = value
		if not _is_integer(state.get("version")) or int(state["version"]) != VERSION:
			return {"ok": false, "error": "unsupported_version"}
		if not state.get("records") is Array or not _is_integer(state.get("revision")):
			return {"ok": false, "error": "invalid_state"}
		if not _is_integer(state.get("next_id", 1)) or int(state.get("next_id", 1)) < 1:
			return {"ok": false, "error": "invalid_next_id"}
		incoming = state["records"]
		incoming_revision = int(state["revision"])
		incoming_next_id = int(state.get("next_id", 1))
	else:
		return {"ok": false, "error": "legacy_requires_explicit_opt_in" if value is Array else "invalid_state"}
	if incoming.size() > MAX_RECORDS:
		return {"ok": false, "error": "too_many_records"}
	var prepared: Array[Dictionary] = []
	var ids: Dictionary = {}
	var fingerprints: Dictionary = {}
	var fact_slots: Dictionary = {}
	for index: int in range(incoming.size()):
		if not incoming[index] is Dictionary:
			return {"ok": false, "error": "invalid_record", "index": index}
		var raw: Dictionary = incoming[index].duplicate(true)
		if legacy and not raw.has("id"):
			raw["id"] = "legacy%d" % (index + 1)
		var checked: Dictionary = _validate_record(raw, not legacy)
		if not checked.get("ok", false):
			return {"ok": false, "error": checked.get("error", "invalid_record"), "index": index}
		var item: Dictionary = checked["record"]
		var item_id: String = str(item["id"])
		var fingerprint: String = _fingerprint(item)
		var slot: String = _fact_slot(item)
		if item_id.is_empty() or ids.has(item_id) or fingerprints.has(fingerprint):
			return {"ok": false, "error": "duplicate_or_missing_record_id", "index": index}
		if not slot.is_empty() and fact_slots.has(slot):
			return {"ok": false, "error": "conflicting_fact_versions", "index": index}
		ids[item_id] = true
		fingerprints[fingerprint] = true
		if not slot.is_empty():
			fact_slots[slot] = true
		prepared.append(item)
	# No live state is touched until every incoming record passes validation.
	clear()
	_next_id = incoming_next_id
	for item: Dictionary in prepared:
		_insert(item)
	revision = maxi(revision, incoming_revision)
	return {"ok": true, "count": count(), "migrated_legacy": legacy}


func _validate_record(raw: Dictionary, strict: bool) -> Dictionary:
	for field: String in ["text", "type", "source"]:
		if not raw.get(field) is String or str(raw[field]).strip_edges().is_empty():
			return {"ok": false, "error": "invalid_" + field}
	var timestamp_value: Variant = raw.get("timestamp", raw.get("day"))
	if not _is_integer(timestamp_value):
		return {"ok": false, "error": "invalid_timestamp"}
	if not raw.get("entities", []) is Array or not raw.get("tags", []) is Array:
		return {"ok": false, "error": "invalid_labels"}
	var entity_check: Dictionary = _validate_labels(raw.get("entities", []), 96)
	var tag_check: Dictionary = _validate_labels(raw.get("tags", []), 48)
	if not entity_check.get("ok", false) or not tag_check.get("ok", false):
		return {"ok": false, "error": "invalid_labels"}
	var importance_value: Variant = raw.get("importance", 0.5)
	var confidence_value: Variant = raw.get("confidence", 0.5)
	if not _is_unit_number(importance_value) or not _is_unit_number(confidence_value):
		return {"ok": false, "error": "invalid_weight"}
	for field: String in ["id", "fact_key", "status"]:
		if raw.has(field) and not raw[field] is String:
			return {"ok": false, "error": "invalid_" + field}
	var item_id: String = str(raw.get("id", "")).strip_edges()
	var text: String = str(raw["text"]).strip_edges()
	var kind: String = _normal(str(raw["type"]))
	var source: String = _normal(str(raw["source"]))
	var fact_key: String = str(raw.get("fact_key", "")).strip_edges()
	var status: String = _normal(str(raw.get("status", "")))
	if item_id.length() > 96 or kind.length() > 48 or source.length() > 80 or fact_key.length() > 160 or status.length() > 32:
		return {"ok": false, "error": "oversized_label"}
	if strict:
		for field: String in ["id", "timestamp", "entities", "tags", "importance", "confidence"]:
			if not raw.has(field):
				return {"ok": false, "error": "missing_" + field}
		if item_id.is_empty() or text.length() > MAX_TEXT_CHARS:
			return {"ok": false, "error": "invalid_record_size"}
	var item: Dictionary = {"id": item_id, "timestamp": int(timestamp_value),
		"entities": entity_check["values"], "type": kind, "importance": float(importance_value),
		"confidence": float(confidence_value), "source": source,
		"text": text.substr(0, MAX_TEXT_CHARS), "tags": tag_check["values"]}
	if not fact_key.is_empty():
		item["fact_key"] = fact_key
	if not status.is_empty():
		item["status"] = status
	return {"ok": true, "record": item}


func _validate_labels(values: Array, max_length: int) -> Dictionary:
	if values.size() > MAX_LABELS:
		return {"ok": false}
	var result: Array[String] = []
	var seen: Dictionary = {}
	for value: Variant in values:
		if not value is String:
			return {"ok": false}
		var label: String = str(value).strip_edges()
		var normalized: String = _normal(label)
		if normalized.is_empty() or label.length() > max_length:
			return {"ok": false}
		if not seen.has(normalized):
			seen[normalized] = true
			result.append(label)
	return {"ok": true, "values": result}


func _is_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= float(MAX_SAFE_INTEGER) and number == floor(number)


func _is_unit_number(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 and number <= 1.0


func _normal(value: String) -> String:
	var normalized: String = value.to_lower().replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	while normalized.contains("  "):
		normalized = normalized.replace("  ", " ")
	return normalized


func _words(value: String) -> Array[String]:
	var normalized: String = _normal(value)
	for separator: String in [".", ",", ":", ";", "!", "?", "/", "\\", "(", ")", "[", "]", "{", "}", "<", ">", "\"", "'", "«", "»", "—", "–", "-", "_"]:
		normalized = normalized.replace(separator, " ")
	var words: Array[String] = []
	var seen: Dictionary = {}
	for word: String in normalized.split(" ", false):
		if not seen.has(word):
			seen[word] = true
			words.append(word)
	return words


func _entity_keys(item: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for entity: String in item["entities"]:
		keys.append(_normal(entity))
	keys.sort()
	return keys


func _fingerprint(item: Dictionary) -> String:
	return JSON.stringify([_normal(str(item["text"])), _entity_keys(item), item["type"], item["source"]])


func _fact_slot(item: Dictionary) -> String:
	# Only explicitly keyed, fully trusted game observations can replace facts.
	# Claims, summaries and generated text never supersede game evidence.
	if item["source"] != "game_event" or float(item["confidence"]) != 1.0 or _is_order(item):
		return ""
	var key: String = str(item.get("fact_key", ""))
	return JSON.stringify([key, _entity_keys(item)]) if not key.is_empty() else ""


func _is_order(item: Dictionary) -> bool:
	# Commands remain in the journal/export for provenance; they are not world facts.
	return item["type"] in ["order", "command", "completed_order", "order_completed", "executed_order", "приказ", "команда"]


func _insert(item: Dictionary) -> void:
	var item_id: String = str(item["id"])
	_records[item_id] = item
	_order.append(item_id)
	_dedup[_fingerprint(item)] = item_id
	for entity: String in item["entities"]:
		_index_add(_by_entity, _normal(entity), item_id)
	for tag: String in item["tags"]:
		_index_add(_by_tag, _normal(tag), item_id)
	var terms: Dictionary = {}
	for word: String in _words(str(item["text"])):
		terms[word] = true
	_terms[item_id] = terms
	var slot: String = _fact_slot(item)
	if not slot.is_empty():
		_facts[slot] = item_id


func _remove(item_id: String) -> void:
	var item: Dictionary = _records[item_id]
	_dedup.erase(_fingerprint(item))
	for entity: String in item["entities"]:
		_index_remove(_by_entity, _normal(entity), item_id)
	for tag: String in item["tags"]:
		_index_remove(_by_tag, _normal(tag), item_id)
	var slot: String = _fact_slot(item)
	if not slot.is_empty():
		_facts.erase(slot)
	_terms.erase(item_id)
	_records.erase(item_id)
	_order.erase(item_id)


func _index_add(index: Dictionary, key: String, item_id: String) -> void:
	var bucket: Dictionary = index.get(key, {})
	bucket[item_id] = true
	index[key] = bucket


func _index_remove(index: Dictionary, key: String, item_id: String) -> void:
	var bucket: Dictionary = index.get(key, {})
	bucket.erase(item_id)
	if bucket.is_empty():
		index.erase(key)
