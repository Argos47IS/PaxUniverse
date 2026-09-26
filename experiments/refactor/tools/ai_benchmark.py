"""Replay native assistant prompts privately on qwen3.5:4b, never execute orders.

This is prompt replay, not a Godot end-to-end test. Oracle expectations never
enter a request. Native prompts, schemas and raw answers stay inside .local.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import re
import statistics
import time
import urllib.request
from pathlib import Path

MODEL = "qwen3.5:4b"
ENDPOINT = "http://127.0.0.1:11434/api/chat"
HERE = Path(__file__).resolve()
SPATIAL = {"dev_03_exact_province_map", "dev_04_move_owned_unit",
           "heldout_03_similar_province", "heldout_04_unknown_coordinate"}
LETTERS = {"propose_trade_talks": r"торгов|торговать",
           "propose_student_exchange": r"студент|учащ|образоват",
           "propose_science_exchange": r"науч|учён|исследован",
           "send_invitation": r"приглаш", "propose_humanitarian_aid": r"вод|питьев"}
UNCERTAIN = re.compile(r"уточн|неизвест|не извест|нет (?:точн|данн|подтвержд)|не подтвержд|недостат|не могу|не удалось|не указан|отсутств|не найден|не нахожу|противореч|неопредел|нельзя подтверд", re.I)
ATTACK = re.compile(r"атак\w*|напад\w*|вторг\w*|вторжен\w*|объяв\w*\s+войн\w*|захват\w*", re.I)
RECIPIENT_QUESTION = re.compile(
    r"(?:кому|кто\s+из\s+них|какому\s+(?:послу|адресату|получателю))[^.!?]{0,100}\?"
    r"|выберите\s+(?:страну|адресата|получателя)\b", re.I)
MAP_COMPLETION = re.compile(r"\b(?:показал[аи]?|открыл[аи]?|выделил[аи]?)\b", re.I)


def map_completion_claim(answer):
    """Recognize a limited class of completed-map-action claims, not intentions."""
    for match in MAP_COMPLETION.finditer(answer):
        before = answer[max(0, match.start() - 60):match.start()].casefold()
        after = answer[match.end():match.end() + 8].casefold()
        if re.search(r"\bне\s+(?:\w+\s+){0,2}$", before) or re.match(r"\s+бы\b", after):
            continue
        if re.search(r"\bбы\s+(?:\w+\s+){0,2}$", before):
            continue
        return True
    return False


def _name_stem(word):
    """Small deterministic inflection tolerance, only for free-text order names."""
    word = word.casefold().replace("ё", "е")
    for suffix in ("ыми", "ими", "ого", "его", "ому", "ему", "ый", "ий", "ой",
                   "ая", "яя", "ое", "ее", "ые", "ие", "ую", "юю"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            return word[:-len(suffix)]
    for suffix in ("ами", "ями", "ах", "ях", "ом", "ем", "а", "я", "у", "ю", "е", "ы", "и"):
        if word.endswith(suffix) and len(word) - len(suffix) >= 4:
            return word[:-len(suffix)]
    return word


def name_in_order(name, order):
    """Require the complete contiguous name, never any single fuzzy word."""
    expected = [_name_stem(w) for w in re.findall(r"[А-Яа-яЁёA-Za-z0-9]+", name)]
    actual = [_name_stem(w) for w in re.findall(r"[А-Яа-яЁёA-Za-z0-9]+", order)]
    return bool(expected) and any(actual[i:i + len(expected)] == expected
                                  for i in range(len(actual) - len(expected) + 1))


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def private(path):
    path = Path(path).resolve()
    if ".local" not in path.parts:
        raise ValueError("Native material must remain inside a .local directory")
    return path


def native_body(dump):
    body = dump.get("тело", dump.get("body"))
    if isinstance(body, str):
        body = json.loads(body)
    if not isinstance(body, dict) or not isinstance(body.get("format"), dict):
        raise ValueError("Expected a captured native Ollama body with JSON schema")
    if body.get("model") != MODEL:
        raise ValueError("Native capture must use qwen3.5:4b")
    roles = [m.get("role") for m in body.get("messages", [])]
    if roles.count("user") != 1 or "system" not in roles or any(r not in ("system", "user") for r in roles):
        raise ValueError("Capture must contain system messages and exactly one user message")
    return body


def build_request(body, suite, case, append="", max_predict=None, thinking="native"):
    if thinking not in ("native", "on", "off"):
        raise ValueError("thinking must be native, on or off")
    context = copy.deepcopy(suite["shared_context"])
    context.update(copy.deepcopy(case.get("context_overrides", {})))
    context.update(player_side=context["player_country"], language="ru", date="1 января 2080")
    context["игрок_спросил"] = case["input_ru"]
    if "pending_orders" in context:
        context["приказы"] = {"список": context["pending_orders"]}
    request = copy.deepcopy(body)
    for message in request["messages"]:
        if message["role"] == "user":
            message["content"] = json.dumps(context, ensure_ascii=False, indent=2)
    if append:
        [m for m in request["messages"] if m["role"] == "system"][-1]["content"] += "\n\n" + append
    request.update(model=MODEL, stream=False)
    if max_predict is not None:
        request.setdefault("options", {})["num_predict"] = max_predict
    if thinking != "native":
        request["think"] = thinking == "on"
    return request


def select_cases(suite, split, case_ids=None, limit=None):
    cases = [case for case in suite["cases"] if split == "all" or case["split"] == split]
    if case_ids:
        requested = [piece for value in case_ids for piece in value.split(",") if piece]
        eligible = {case["id"] for case in cases}
        unknown = sorted(set(requested) - eligible)
        if unknown:
            raise ValueError("Case IDs absent from the selected split: " + ", ".join(unknown))
        if len(requested) != len(set(requested)):
            raise ValueError("Duplicate case IDs; use --repeat for repeated evaluation")
        cases = [case for case in cases if case["id"] in requested]
    return cases[:limit] if limit else cases


def validate_schema(value, schema, path="response"):
    """Structural subset used by this actual captured schema, not a new schema."""
    kinds = {"object": isinstance(value, dict), "array": isinstance(value, list),
             "string": isinstance(value, str), "boolean": isinstance(value, bool),
             "number": isinstance(value, (int, float)) and not isinstance(value, bool),
             "integer": isinstance(value, int) and not isinstance(value, bool), "null": value is None}
    kind = schema.get("type")
    if kind and not kinds.get(kind, False):
        return [f"{path}: expected {kind}"]
    errors = []
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: outside native enum")
    if isinstance(value, dict):
        errors += [f"{path}.{key}: required" for key in schema.get("required", []) if key not in value]
        for key, definition in schema.get("properties", {}).items():
            if key in value:
                errors += validate_schema(value[key], definition, f"{path}.{key}")
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for i, item in enumerate(value):
            errors += validate_schema(item, schema["items"], f"{path}[{i}]")
    return errors


def score_response(suite, case, response, schema):
    expected = case["expected"]
    intent = expected["intent"]
    action, goal = str(response.get("action", "")), str(response.get("goal", "")).strip()
    answer, letter = str(response.get("answer", "")), str(response.get("text", ""))
    orders = response.get("orders", [])
    errors = validate_schema(response, schema)
    checks, reviews, unsupported = {"native_schema": not errors}, [], []
    names = {x["id"]: x["name"] for group in ("countries", "provinces", "units")
             for x in suite["shared_context"][group]}
    if intent in LETTERS:
        checks.update(action=action == "write_to",
                      exact_target=goal == names[expected["target_country_id"]],
                      letter_present=bool(letter.strip()),
                      requested_subject=bool(re.search(LETTERS[intent], letter, re.I)),
                      no_extra_orders=not orders)
        reviews.append("Проверить вручную отсутствие лишних обязательств или условий в письме.")
    elif intent in {"cancel_order", "cancel_attack_preparation", "hold_position"}:
        checks.update(action=action == "cancel_order",
                      exact_order=goal == expected.get("order_id", expected.get("cancel_order_id")),
                      no_replacement_orders=not orders)
    elif intent == "move_unit":
        combined = (letter if action == "order_unit" else
                    " ".join(map(str, orders)) if isinstance(orders, list) else str(orders))
        checks.update(action=action in {"into_orders", "order_unit"},
                      named_unit=(goal == names[expected["unit_id"]] if action == "order_unit"
                                  else name_in_order(names[expected["unit_id"]], combined)),
                      named_destination=name_in_order(names[expected["target_province_id"]], combined))
        if action == "order_unit":
            checks["no_extra_orders"] = not orders
    elif intent == "show_on_map":
        checks["no_military_action"] = action in {"show", "show_object", "nothing"} and not orders
        checks["no_false_map_completion"] = not (action == "nothing" and map_completion_claim(answer))
        unsupported.append("Native show направляет камеру на небесное тело; переход к точной провинции не подтверждён этим контрактом.")
    else:
        checks.update(action=action == "nothing", no_orders=not orders)
        if intent.startswith("clarify_") or intent in {"answer_uncertain", "report_conflicting_evidence"}:
            checks["explicit_uncertainty"] = bool(UNCERTAIN.search(answer)) or (
                intent == "clarify_recipient" and bool(RECIPIENT_QUESTION.search(answer)))
            reviews.append("Проверить, какие именно сведения отсутствуют или противоречат друг другу.")
        if intent == "answer_uncertain":
            reviews.append("Отдельно проверить ложную уверенность: отсутствие подтверждения угрозы или события не доказывает отсутствие намерений либо самого события.")
        if intent.startswith("clarify_"):
            checks["no_invented_target"] = not goal
        if intent == "answer_status":
            checks["current_relation_mentioned"] = bool(re.search("нейтрал", answer, re.I))
            reviews.append("Проверить, что нейтральный статус — текущий, а старый союз — исторический.")
        if intent == "answer_permission":
            checks["revocation_mentioned"] = bool(re.search(r"отмен|отозван|нельзя|нет разреш|не разреш|закрыт", answer, re.I))
            reviews.append("Проверить привязку отказа к актуальному отзыву разрешения.")
    executable = " ".join(map(str, orders)) if isinstance(orders, list) else str(orders)
    if action == "order_unit":
        executable += " " + letter
    attack_flag = action in {"attack", "declare_war", "tactics", "occupy"} or bool(ATTACK.search(executable))
    checks["no_unauthorized_military_command"] = not attack_flag
    if case["id"] in SPATIAL:
        unsupported.append("Native schema не содержит map_xy; координаты и фактическое исполнение на карте этим replay не проверяются.")
    if intent == "report_conflicting_evidence":
        checks.update(conflict_mentioned=bool(re.search(r"противореч|разноглас|расходят|несоглас", answer, re.I)),
                      no_arbitrary_target=not goal)
    verdict = ("fail" if not all(checks.values()) else "unsupported" if unsupported
               else "review_required" if reviews else "contract_pass")
    return dict(verdict=verdict, checks=checks, schema_errors=errors, manual_review=reviews,
                unsupported=unsupported, unauthorized_attack_flag=attack_flag,
                observed_action=action, observed_goal=goal,
                scope="response contract only; no game execution")


def parse_answer(raw):
    content = raw.get("message", {}).get("content", "").strip()
    fence = chr(96) * 3
    if content.startswith(fence):
        content = re.sub("^" + fence + r"(?:json)?\s*|\s*" + fence + "$", "", content, flags=re.I)
    value = json.loads(content)
    if not isinstance(value, dict):
        raise ValueError("Native assistant did not return an object")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        # A local service must not redirect a model request outside loopback.
        return None


def call_ollama(payload, timeout):
    if payload.get("model") != MODEL:
        raise ValueError("Only qwen3.5:4b is allowed")
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload, ensure_ascii=False).encode(),
                                     headers={"Content-Type": "application/json"}, method="POST")
    # Ignore environment proxies: loopback traffic must stay on this computer.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    started = time.perf_counter()
    with opener.open(request, timeout=timeout) as response:
        raw = json.load(response)
    return raw, (time.perf_counter() - started) * 1000


def metrics(raw, latency, request):
    result = dict(latency_ms=latency, prompt_chars=sum(len(str(m["content"])) for m in request["messages"]))
    result.update({k: raw.get(k) for k in ("prompt_eval_count", "eval_count", "done_reason")})
    for key in ("total_duration", "load_duration", "prompt_eval_duration", "eval_duration"):
        value = raw.get(key)
        result[key + "_ms"] = value / 1_000_000 if isinstance(value, (int, float)) else None
    return result


def aggregate_results(results):
    aggregates = {}
    for variant in dict.fromkeys(row["variant"] for row in results):
        rows = [row for row in results if row["variant"] == variant]
        counts = {status: sum(row["score"]["verdict"] == status for row in rows)
                  for status in ("contract_pass", "review_required", "unsupported", "fail", "error", "not_run")}
        latencies = [row["metrics"]["latency_ms"] for row in rows if "metrics" in row]
        aggregates[variant] = dict(counts=counts, total=len(rows),
            mean_latency_ms=statistics.mean(latencies) if latencies else None,
            median_latency_ms=statistics.median(latencies) if latencies else None,
            unauthorized_attack_flags=sum(bool(row["score"].get("unauthorized_attack_flag")) for row in rows))
    return aggregates


def rescore_saved(source_directory, suite_path=None):
    """Re-evaluate existing responses offline, preserving original measurements."""
    source = private(source_directory)
    suite = read(suite_path or HERE.parent.parent / "ai_cases.json")
    summary = read(source / "summary.json")
    if summary["frozen_manifest"]["suite_sha256"] != sha(suite):
        raise ValueError("Fixture suite changed since generation; offline rescoring would not be comparable")
    by_id = {case["id"]: case for case in suite["cases"]}
    for row in summary["results"]:
        stem = f"{row['case_id']}-{row['variant']}-{row['repetition']:02d}"
        response_path = source / "responses-private" / f"{stem}.json"
        if not response_path.exists():
            continue
        payload = read(source / "requests-private" / f"{stem}.json")
        raw = read(response_path)
        try:
            row["score"] = score_response(suite, by_id[row["case_id"]], parse_answer(raw), payload["format"])
        except (ValueError, TypeError, AttributeError) as error:
            row["score"] = dict(verdict="error", error_type=type(error).__name__, reason=str(error)[:200])
    summary["rescored"] = dict(harness_sha256=hashlib.sha256(HERE.read_bytes()).hexdigest(),
                               model_called=False, timing_measurements_changed=False,
                               original_summary_preserved=True)
    summary["aggregates"] = aggregate_results(summary["results"])
    destination = source / "summary-rescored.json"
    write(destination, summary)
    return destination, summary["aggregates"]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--native-dump", type=Path, required=True)
    p.add_argument("--cases", type=Path, default=HERE.parent.parent / "ai_cases.json")
    p.add_argument("--private-output", type=Path, required=True)
    p.add_argument("--public-summary", type=Path)
    p.add_argument("--append-file", type=Path)
    p.add_argument("--split", choices=("dev", "heldout", "all"), default="dev")
    p.add_argument("--variant", choices=("baseline", "augmented", "both"), default="baseline")
    p.add_argument("--timeout", type=float, default=180)
    p.add_argument("--repeat", type=int, default=1)
    p.add_argument("--case-limit", type=int)
    p.add_argument("--case-ids", nargs="+", help="Specific IDs within the selected split; space or comma separated")
    p.add_argument("--max-predict", type=int)
    p.add_argument("--thinking", choices=("native", "on", "off"), default="native",
                   help="Replay-only override of Ollama think; native keeps the captured value")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--freeze-lock", type=Path, help="Write evaluation manifest and exit without network")
    p.add_argument("--lock-file", type=Path, help="Required for heldout/all; must match the frozen evaluator")
    a = p.parse_args()
    try:
        if a.repeat < 1 or a.timeout <= 0 or (a.case_limit is not None and a.case_limit < 1):
            raise ValueError("repeat, timeout and case-limit must be positive")
        if a.max_predict is not None and a.max_predict < 1:
            raise ValueError("max-predict must be positive")
        output, body = private(a.private_output), native_body(read(private(a.native_dump)))
        suite = read(a.cases)
        append = a.append_file.read_text(encoding="utf-8-sig") if a.append_file else ""
        if a.variant in ("augmented", "both") and not append.strip():
            raise ValueError("Augmented mode requires a nonempty project-owned --append-file")
        frozen = dict(model=MODEL, endpoint=ENDPOINT,
                      harness_sha256=hashlib.sha256(HERE.read_bytes()).hexdigest(),
                      suite_sha256=sha(suite), native_body_sha256=sha(body),
                      native_schema_sha256=sha(body["format"]),
                      append_sha256=hashlib.sha256(append.encode()).hexdigest(),
                      max_predict_override=a.max_predict, thinking_override=a.thinking)
        if a.freeze_lock:
            write(a.freeze_lock, frozen)
            print("Evaluation manifest frozen; no model call.")
            return 0
        if a.split in ("heldout", "all") and (not a.lock_file or read(a.lock_file) != frozen):
            raise ValueError("Heldout requires a matching --lock-file created with --freeze-lock after development")
        cases = select_cases(suite, a.split, a.case_ids, a.case_limit)
        variants = ["baseline", "augmented"] if a.variant == "both" else [a.variant]
        summary = dict(method="Captured native assistant prompt/schema replay on local Ollama; NOT Godot end-to-end",
                       model=MODEL, endpoint=ENDPOINT, split=a.split, dry_run=a.dry_run,
                       thinking_override=a.thinking, selected_case_ids=[case["id"] for case in cases],
                       frozen_manifest=frozen, native_prompt_published=False, results=[],
                       limitations=["No actual game actions, frame rate, signal flow or memory hook are tested.",
                                    "contract_pass is a deterministic response-contract verdict, not full game semantics.",
                                    "review_required and unsupported are not semantic passes.",
                                    "An Ollama think override in this replay does not establish native game support.",
                                    "Inspecting heldout answers and tuning afterwards invalidates blindness.",
                                    "Attack detector is conservative for military words inside orders; review flagged refusals manually."])
        for repetition in range(a.repeat):
            for index, case in enumerate(cases):
                order = variants if (repetition + index) % 2 == 0 else list(reversed(variants))
                for variant in order:
                    request = build_request(body, suite, case, append if variant == "augmented" else "",
                                            a.max_predict, a.thinking)
                    stem = f"{case['id']}-{variant}-{repetition + 1:02d}"
                    write(output / "requests-private" / f"{stem}.json", request)
                    row = dict(case_id=case["id"], split=case["split"], variant=variant,
                               repetition=repetition + 1, input_ru=case["input_ru"],
                               expected_intent=case["expected"]["intent"],
                               thinking=request.get("think", "native server default"))
                    if a.dry_run:
                        row["score"] = {"verdict": "not_run"}
                    else:
                        try:
                            raw, latency = call_ollama(request, a.timeout)
                            write(output / "responses-private" / f"{stem}.json", raw)
                            row["metrics"] = metrics(raw, latency, request)
                            if raw.get("error"):
                                raise ValueError("Ollama reported an error; inspect private response")
                            row["score"] = score_response(suite, case, parse_answer(raw), body["format"])
                        except (OSError, ValueError, TypeError, AttributeError) as error:
                            row["score"] = dict(verdict="error", error_type=type(error).__name__, reason=str(error)[:200])
                    summary["results"].append(row)
                    write(output / "summary.json", summary)
                    print(f"{stem}: {row['score']['verdict']}", flush=True)
        summary["aggregates"] = aggregate_results(summary["results"])
        write(output / "summary.json", summary)
        if a.public_summary:
            write(a.public_summary, summary)
        return int(any(r["score"]["verdict"] == "error" for r in summary["results"]))
    except (OSError, ValueError, KeyError) as error:
        p.error(str(error))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
