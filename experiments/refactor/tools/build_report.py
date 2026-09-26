#!/usr/bin/env python3
"""Build a portable Russian HTML report from explicitly selected experiment runs.

Only allowlisted measurements are published. Native prompts, generated replies,
private context, endpoints, license data, campaign contents and raw logs are never
copied. Missing or failed runs remain visibly missing/failed in the report.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
from pathlib import Path
import re
import statistics
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[3]
LOCAL = ROOT / ".local" / "Pax Universe Refactor"
VERDICTS = {
    "contract_pass": ("Контракт выполнен", "#5fd1b0"),
    "review_required": ("Нужна ручная оценка", "#e6bd6c"),
    "unsupported": ("Не поддерживается проверкой", "#a691d6"),
    "fail": ("Проверка не пройдена", "#ee8290"),
    "error": ("Ошибка запроса", "#c9556c"),
    "not_run": ("Не запускалось", "#687b8e"),
    "unknown": ("Нет надёжной оценки", "#8094a6"),
}
STATUS = {"passed": "Подтверждено", "failed": "Есть ошибки", "not_verified": "Не подтверждено"}
SKIP_RU = {
    "external_ai": "внешние AI-провайдеры в офлайн-проверке механики",
    "war_and_peace_actions": "полный цикл объявления войны и заключения мира",
    "long_campaign": "многолетняя игровая партия",
    "save_load": "сохранение и загрузка: этап не завершён или пропущен",
    "character_and_chronicle": "создание персонажа и запись хроники",
    "role_ui": "интерфейс разных игровых ролей",
    "serialized_memory_layout": "внутренний формат памяти в файле сохранения",
    "save_character": "восстановление персонажа из сохранения",
}


def number(value):
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) else None


def numeric(data, keys):
    data = data if isinstance(data, dict) else {}
    return {key: number(data.get(key)) for key in keys if number(data.get(key)) is not None}


def safe_id(value):
    value = str(value)
    return value if len(value) <= 140 and re.fullmatch(r"[\w.\-:]+", value, re.UNICODE) else "unnamed_check"


def read_json(path: Path | None):
    if path is None or not path.is_file():
        return {}, "missing"
    if path.name.lower() in {"license.json", "account.json", "credentials.json", "settings.json"}:
        raise ValueError("Credentials and application settings are not report inputs")
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        return (value, "read") if isinstance(value, dict) else ({}, "invalid_shape")
    except (OSError, UnicodeError, json.JSONDecodeError):
        return {}, "unreadable"


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path and path.is_file() else None


def check_group(value):
    value = value if isinstance(value, dict) else {}
    checks = {safe_id(k): v for k, v in value.get("checks", {}).items() if isinstance(v, bool)} if isinstance(value.get("checks"), dict) else {}
    failures = [key for key, passed in checks.items() if not passed]
    for item in value.get("failures", []) if isinstance(value.get("failures"), list) else []:
        name = safe_id(item)
        if name not in failures:
            failures.append(name)
    skips = value.get("skipped", {})
    # Publish skip identifiers, never arbitrary diagnostic text containing context.
    skipped = [safe_id(k) for k in skips] if isinstance(skips, dict) else ["unspecified_skip"] * len(skips) if isinstance(skips, list) else []
    status = "failed" if failures or value.get("ok") is False else "passed" if checks and value.get("ok") is True else "not_verified"
    return {"status": status, "passed": sum(checks.values()), "total": len(checks), "checks": checks, "failures": failures, "skipped": skipped}


def extract_benchmark(adapter):
    if not isinstance(adapter, dict):
        return None
    # Accept the actual named container or discover a dictionary with the exact
    # measured schema, without copying unrelated strings/records.
    candidates = [adapter]
    while candidates:
        value = candidates.pop()
        if isinstance(value.get("batches"), list) and "results_identical" in value:
            batches = []
            for row in value["batches"]:
                if isinstance(row, dict):
                    item = numeric(row, ["batch", "operations_per_path", "cached_us", "uncached_us", "cached_us_per_operation", "uncached_us_per_operation", "cached_cache_hits", "uncached_cache_hits"])
                    item.update({k: row[k] for k in ["cached_results_identical", "uncached_results_identical"] if isinstance(row.get(k), bool)})
                    batches.append(item)
            return {**numeric(value, ["records", "matching_scope_records", "selected_records"]), "batches": batches, "results_identical": value.get("results_identical") is True, "cache_hits_verified": value.get("cache_hits_verified") is True, "unit": "microseconds"}
        candidates.extend(child for child in value.values() if isinstance(child, dict))
    return None


def read_run(path: Path | None, label: str):
    baseline_path = path / "baseline.json" if path and path.is_dir() else path
    if path and not path.exists() and path.suffix != ".json":
        baseline_path = path / "baseline.json"
    raw, read_status = read_json(baseline_path)
    process_path = baseline_path.parent / "process-metrics.json" if baseline_path else None
    process, process_status = read_json(process_path)
    samples = [numeric(row, ["wall_ms", "cpu_seconds", "working_set_bytes", "private_bytes"]) for row in process.get("samples", []) if isinstance(row, dict)]
    frames = raw.get("frame_sample", {})
    mechanics = raw.get("mechanics", {})
    save = mechanics.get("save_load", {}) if isinstance(mechanics, dict) else {}
    groups = {key: check_group(raw.get(key)) for key in ["mechanics", "memory_component", "memory_adapter"]}
    root_checks = check_group(raw)
    failed = raw.get("ok") is False or bool(root_checks["failures"]) or any(group["status"] == "failed" for group in groups.values()) or (number(process.get("exit_code")) not in (None, 0))
    complete = read_status == process_status == "read" and raw.get("ok") is True and process.get("exit_code") == 0
    metrics = numeric(raw.get("metrics"), ["harness_ready_engine_ms", "world_creation_ms", "first_world_frame_engine_ms"])
    metrics.update(numeric(frames, ["fps", "frame_mean_ms", "frame_p50_ms", "frame_p95_ms", "frame_p99_ms", "duration_s", "frames", "nodes"]))
    metrics.update(numeric(mechanics.get("timings_ms", {}) if isinstance(mechanics, dict) else {}, ["native_save", "native_storage_read", "fresh_main_load_and_world_ready", "first_observed_time_step", "time_progression_and_pause_check"]))
    peaks = [row["working_set_bytes"] for row in samples if "working_set_bytes" in row]
    if peaks:
        metrics["peak_working_set_mib"] = max(peaks) / 1048576
    cpu_samples = [row for row in samples if "cpu_seconds" in row and row.get("wall_ms", 0) > 0]
    if cpu_samples:
        last_cpu = cpu_samples[-1]
        metrics["observed_process_cpu_seconds"] = last_cpu["cpu_seconds"]
        metrics["cpu_observation_wall_seconds"] = last_cpu["wall_ms"] / 1000
        processors = number(process.get("logical_processors"))
        if processors and processors > 0:
            metrics["logical_processors"] = processors
            metrics["observed_process_cpu_percent"] = 100 * last_cpu["cpu_seconds"] / (last_cpu["wall_ms"] / 1000) / processors
    rendering = raw.get("rendering", {})
    storage = save.get("storage_size", {}) if isinstance(save, dict) else {}
    memory_save = mechanics.get("memory_save_load", {}) if isinstance(mechanics, dict) else {}
    time_data = mechanics.get("time", {}) if isinstance(mechanics, dict) else {}
    return {
        "label": label, "run": safe_id(baseline_path.parent.name) if baseline_path else "not_selected",
        "status": "failed" if failed else "passed" if complete else "not_verified",
        "input_status": read_status, "process_status": process_status,
        "baseline_sha256": checksum(baseline_path), "process_sha256": checksum(process_path),
        "version": str(raw.get("version", "unknown"))[:24], "with_mods": raw.get("with_mods") is True,
        "exit_code": number(process.get("exit_code")), "metrics": metrics,
        "frame_ms": [v for v in frames.get("frame_ms", []) if number(v) is not None][:20000] if isinstance(frames, dict) else [],
        "process_samples": samples,
        "rendering": {**numeric(rendering, ["max_fps", "vsync"]), "viewport": str(rendering.get("viewport", "unknown"))[:40], "driver": safe_id(rendering.get("driver", "unknown"))},
        "checks": root_checks, "groups": groups,
        "storage": {"measured": storage.get("measured") is True, **numeric(storage, ["file_count", "total_bytes", "world_json_bytes", "skipped_links", "unreadable"])},
        "memory_roundtrip": numeric(memory_save, ["records_before_save", "records_after_load"]),
        "time": {**numeric(time_data, ["from_day", "to_day", "signals", "reported_days", "requested_speed"]), "safe_to_reload": time_data.get("safe_to_reload") is True},
        "cache_benchmark": extract_benchmark(raw.get("memory_adapter")),
    }


def read_ai(path: Path, label: str):
    path = path / "summary.json" if path.is_dir() else path
    raw, status = read_json(path)
    rows = []
    for row in raw.get("results", []):
        if not isinstance(row, dict):
            continue
        score = row.get("score", {}) if isinstance(row.get("score"), dict) else {}
        verdict = "not_run" if raw.get("dry_run") else score.get("verdict", "unknown")
        if verdict not in VERDICTS:
            verdict = "unknown"
        rows.append({"case_id": safe_id(row.get("case_id", "unknown")), "split": safe_id(row.get("split", raw.get("split", "unknown"))), "variant": safe_id(row.get("variant", "unknown")), "repetition": number(row.get("repetition")), "verdict": verdict,
                     "manual_review_items": len(score.get("manual_review", [])) if isinstance(score.get("manual_review"), list) else 0,
                     "unsupported_items": len(score.get("unsupported", [])) if isinstance(score.get("unsupported"), list) else 0,
                     "checks": {safe_id(k): v for k, v in score.get("checks", {}).items() if isinstance(v, bool)} if isinstance(score.get("checks"), dict) else {},
                     "metrics": numeric(row.get("metrics"), ["latency_ms", "prompt_chars", "prompt_eval_count", "eval_count", "load_duration_ms", "prompt_eval_duration_ms", "eval_duration_ms"]),
                     "unauthorized_attack_flag": score.get("unauthorized_attack_flag") is True})
    variants = []
    for variant in sorted({row["variant"] for row in rows}):
        selected = [row for row in rows if row["variant"] == variant]
        counts = {key: sum(row["verdict"] == key for row in selected) for key in VERDICTS}
        latencies = [row["metrics"]["latency_ms"] for row in selected if "latency_ms" in row["metrics"]]
        tokens = [row["metrics"]["prompt_eval_count"] for row in selected if "prompt_eval_count" in row["metrics"]]
        variants.append({"variant": variant, "counts": counts, "total": len(selected), "median_latency_ms": statistics.median(latencies) if latencies else None, "mean_prompt_tokens": statistics.mean(tokens) if tokens else None, "attack_flags": sum(row["unauthorized_attack_flag"] for row in selected)})
    frozen = raw.get("frozen_manifest", {})
    hashes = {key: value for key, value in frozen.items() if key.endswith("_sha256") and isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value)}
    return {"label": label, "input_status": status, "sha256": checksum(path), "model": safe_id(raw.get("model", "unknown")), "split": safe_id(raw.get("split", "unknown")), "dry_run": raw.get("dry_run") is True, "variants": variants, "rows": rows, "frozen_hashes": hashes,
            "scope": "synthetic_response_contract_replay_not_game_execution"}


def read_manual_ai(path: Path | None):
    """Publish only our reviewed verdicts/reasons, never arbitrary source fields."""
    if path is None:
        return None
    raw, status = read_json(path)
    rows, seen, rejected = [], set(), 0
    candidates = raw.get("results", [])
    if not isinstance(candidates, list):
        candidates = []
    for row in candidates:
        if not isinstance(row, dict):
            rejected += 1
            continue
        case_id, variant, verdict = row.get("case_id"), row.get("variant"), row.get("verdict")
        if (not isinstance(case_id, str) or not re.fullmatch(r"heldout_\d{2}_[a-z0-9_]+", case_id)
                or variant not in ("baseline", "augmented") or verdict not in ("pass", "fail", "unsupported")
                or (case_id, variant) in seen):
            rejected += 1
            continue
        reasons = [value.strip()[:500] for value in row.get("reasons", [])[:2]
                   if isinstance(value, str) and value.strip()] if isinstance(row.get("reasons"), list) else []
        if not reasons:
            rejected += 1
            continue
        seen.add((case_id, variant))
        item = {"case_id": case_id, "variant": variant, "verdict": verdict, "reasons": reasons}
        if isinstance(row.get("caveat"), str):
            item["caveat"] = row["caveat"].strip()[:600]
        for field in ["wording_regex_false_negative", "native_operation_valid"]:
            if isinstance(row.get(field), bool):
                item[field] = row[field]
        rows.append(item)
    # Counts in the input are not trusted: derive denominators from unique rows.
    variants = []
    for variant in ("baseline", "augmented"):
        selected = [row for row in rows if row["variant"] == variant]
        if selected:
            variants.append({"variant": variant, "total": len(selected),
                             "counts": {verdict: sum(row["verdict"] == verdict for row in selected)
                                        for verdict in ("pass", "fail", "unsupported")}})
    hashes = {field: raw[field] for field in ["frozen_harness_sha256", "candidate_sha256"]
              if isinstance(raw.get(field), str) and re.fullmatch(r"[0-9a-f]{64}", raw[field])}
    return {"input_status": status, "sha256": checksum(path), "source_run": safe_id(raw.get("source_run", "unknown")),
            "model": safe_id(raw.get("model", "unknown")), "rows": rows, "variants": variants,
            "rejected_rows": rejected, "frozen_hashes": hashes,
            "frozen_manifest_matches_saved_lock": raw.get("frozen_manifest_matches_saved_lock") is True,
            "scope": "manual_semantic_review_of_frozen_prompt_replay_not_game_execution"}


def read_integration(path: Path, date_format_reviewed=False):
    path = path / "ai-integration.json" if path.is_dir() else path
    raw, status = read_json(path)
    cases = []
    for row in raw.get("cases", []):
        if not isinstance(row, dict):
            continue
        item = {"id": safe_id(row.get("id", "unknown")),
                **numeric(row, ["elapsed_ms", "body_memory_marker_count", "context_addition_chars", "context_callback_calls"])}
        item.update({key: row[key] for key in ["received", "loopback_request", "memory_marker_in_body", "native_schema", "qa_number_in_body", "request_input_in_body", "transport_error"] if isinstance(row.get(key), bool)})
        item["schema_error_count"] = len(row["schema_errors"]) if isinstance(row.get("schema_errors"), list) else None
        cases.append(item)
    latencies = [row["elapsed_ms"] for row in cases if row.get("received") is True and "elapsed_ms" in row]
    checks = check_group(raw)
    date_failed = "current_date_matches_game_components" in checks["failures"]
    measurements = numeric(raw, ["elapsed_ms", "calls_before_native_request", "calls_after_native_request", "response_count", "context_calls", "cache_hits", "memory_records_after_responses"])
    if cases:
        measurements.update({"case_count": len(cases), "responses_received": sum(row.get("received") is True for row in cases),
                             "native_schema_passed": sum(row.get("native_schema") is True for row in cases),
                             "memory_marker_present": sum(row.get("memory_marker_in_body") is True for row in cases),
                             "single_memory_marker": sum(row.get("body_memory_marker_count") == 1 for row in cases),
                             "context_callback_observed": sum(number(row.get("context_callback_calls")) is not None and row["context_callback_calls"] > 0 for row in cases),
                             "latency_sample_count": len(latencies)})
        if latencies:
            measurements["median_latency_ms"] = statistics.median(latencies)
    observations = {key: raw[key] for key in ["camera_action_applied"] if isinstance(raw.get(key), bool)}
    # The reviewer explicitly attests this one interpretation. Preserve the
    # automated failure and never infer the answer's content from a failed check.
    date_review = "correct_date_words_numeric_format_not_met" if date_format_reviewed and date_failed else None
    return {"input_status": status, "sha256": checksum(path), "checks": check_group(raw),
            "ok": raw.get("ok") if isinstance(raw.get("ok"), bool) else None,
            "response_received": all(row.get("received") is True for row in cases) if cases else raw.get("response_received") if isinstance(raw.get("response_received"), bool) else None,
            "cases": cases, "measurements": measurements, "observations": observations, "manual_date_review": date_review,
            "scope": "native_request_memory_context_and_selected_validated_action_only_no_general_gameplay_quality_claim"}


def read_audit(inventory: Path, audit: Path):
    original, original_status = read_json(inventory)
    scripts, audit_status = read_json(audit)
    inspected = scripts.get("scripts", {})
    values = [value for value in inspected.values() if isinstance(value, dict)] if isinstance(inspected, dict) else []
    return {"inventory_status": original_status, "audit_status": audit_status,
            **numeric(original, ["count", "bytes"]), "independent_copy": original.get("independent_copy") is True,
            "scripts_inspected": len(values) if audit_status == "read" else None,
            "source_text_available": sum(value.get("has_source") is True for value in values) if audit_status == "read" else None}


def esc(value):
    return html.escape(str(value), quote=True)


def fmt(value, decimals=2):
    return "нет данных" if number(value) is None else f"{value:,.{decimals}f}".replace(",", " ").replace(".", ",")


def badge(status):
    return f'<span class="badge {esc(status)}">{esc(STATUS.get(status, status))}</span>'


def bars(title, unit, values, hint=""):
    available = [float(v) for _, v, _ in values if number(v) is not None]
    maximum = max(available, default=0) or 1
    shapes = []
    for index, (label, value, color) in enumerate(values):
        y = 28 + index * 38
        shapes.append(f'<text x="0" y="{y + 14}" fill="#a9bbca" font-size="13">{esc(label)}</text>')
        if number(value) is not None:
            width = max(1, float(value) / maximum * 210)
            shapes.append(f'<rect x="82" y="{y}" width="{width:.2f}" height="22" rx="4" fill="{color}"/>')
        shapes.append(f'<text x="{82 + (float(value) / maximum * 210 if number(value) is not None else 0) + 9:.2f}" y="{y + 15}" fill="#e7edf4" font-size="13">{esc(fmt(value))} {esc(unit) if number(value) is not None else ""}</text>')
    height = 40 + len(values) * 38
    return f'<article class="chart"><h3>{esc(title)}</h3><svg viewBox="0 0 455 {height}" role="img" aria-label="{esc(title)}">{"".join(shapes)}</svg><p class="muted small">{esc(hint)}</p></article>'


def frame_svg(before, after):
    series = [(before, "#849bb0"), (after, "#49c8bd")]
    existing = [float(v) for run, _ in series for v in run["frame_ms"]]
    if not existing:
        return '<p class="muted">Интервалы кадров не предоставлены.</p>'
    ceiling = max(existing) * 1.12 or 1
    paths = []
    for run, color in series:
        values = run["frame_ms"]
        if len(values) < 2:
            continue
        step = max(1, len(values) // 700)
        pts = [(i, values[i]) for i in range(0, len(values), step)]
        points = " ".join(f"{42 + i / (len(values) - 1) * 825:.1f},{200 - float(v) / ceiling * 170:.1f}" for i, v in pts)
        paths.append(f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="1.8"/>')
    return f'<svg class="wide-chart" viewBox="0 0 900 235" role="img" aria-label="Интервалы кадров"><path d="M42 25V201H875" stroke="#42566a" fill="none"/><text x="44" y="18" fill="#a9bbca" font-size="13">мс на кадр · верхняя граница {fmt(ceiling, 1)}</text>{"".join(paths)}<text x="42" y="225" fill="#a9bbca" font-size="12">начало измерения</text><text x="710" y="225" fill="#a9bbca" font-size="12">конец измерения</text></svg>'


def check_table(before, after):
    labels = {"mechanics": "Механика, окна и сохранение", "memory_component": "Хранилище памяти", "memory_adapter": "Подключение памяти к игре"}
    lines = []
    for key, label in labels.items():
        cells = []
        for run in [before, after]:
            group = run["groups"][key]
            cells.append(f'<td>{group["passed"]} / {group["total"]} {badge(group["status"])}</td>')
        lines.append(f'<tr><th>{label}</th>{"".join(cells)}</tr>')
    return '<div class="table-wrap"><table><thead><tr><th>Проверка</th><th>До</th><th>После</th></tr></thead><tbody>' + "".join(lines) + '</tbody></table></div>'


def ai_sections(groups):
    if not groups:
        return '<p class="notice">AI-измерения не переданы. Качество ответов и задержка модели не подтверждены.</p>'
    content = []
    for group in groups:
        title = f'{group["label"]} · {group["split"]} · {group["model"]}'
        content.append(f'<article class="panel"><h3>{esc(title)}</h3>')
        if not group["variants"]:
            content.append('<p class="notice">Нет завершённых оценок в выбранном файле.</p></article>')
            continue
        for variant in group["variants"]:
            total = max(1, variant["total"])
            x = 0.0
            parts = []
            for key, (label, color) in VERDICTS.items():
                count = variant["counts"][key]
                if count:
                    width = count / total * 900
                    parts.append(f'<rect x="{x:.2f}" width="{width:.2f}" height="28" fill="{color}"><title>{esc(label)}: {count}</title></rect>')
                    x += width
            legend = "".join(f'<span><i style="background:{color}"></i>{esc(label)}: <b>{variant["counts"][key]}</b></span>' for key, (label, color) in VERDICTS.items() if variant["counts"][key])
            if variant["variant"] == "augmented":
                content.append('<p class="notice">Отклонённый экспериментальный кандидат общих правил промпта. Он не входит в поставляемый pax_memory; эти результаты не характеризуют работающий мод памяти.</p>')
            content.append(f'<h4>{esc(variant["variant"])} · {variant["total"]} ответов</h4><svg viewBox="0 0 900 28" role="img" aria-label="Распределение результатов">{"".join(parts)}</svg><div class="legend">{legend}</div><p class="muted small">Медиана ответа: {fmt(variant["median_latency_ms"])} мс. Средний вход модели: {fmt(variant["mean_prompt_tokens"], 0)} токенов по счётчику провайдера. Флагов потенциально несогласованной атаки: {variant["attack_flags"]}; это не доказательство исполнения атаки в игре.</p>')
        content.append('</article>')
    return "".join(content)


def manual_ai_section(group):
    if group is None:
        return ""
    if group["input_status"] != "read" or not group["rows"]:
        return '<article class="panel"><h3>Ручная оценка смысла</h3><p class="notice">В выбранном файле нет подтверждённых ручных оценок. Успехи не подсчитываются.</p></article>'
    labels = {"baseline": "Исходный промпт", "augmented": "Отклонённый кандидат"}
    verdicts = {"pass": "Засчитано", "fail": "Ошибка", "unsupported": "Не поддерживается"}
    summary_rows = "".join(
        f'<tr><th>{labels[item["variant"]]}</th><td><b>{item["counts"]["pass"]}/{item["total"]}</b></td>'
        f'<td>{item["counts"]["fail"]}</td><td>{item["counts"]["unsupported"]}</td></tr>'
        for item in group["variants"])
    detailed_rows = []
    for row in group["rows"]:
        explanation = " ".join(row["reasons"])
        if row.get("caveat"):
            explanation += " Оговорка: " + row["caveat"]
        detailed_rows.append(f'<tr><th>{esc(row["case_id"])}<br><span class="muted">{labels[row["variant"]]}</span></th>'
                             f'<td>{verdicts[row["verdict"]]}</td><td>{esc(explanation)}</td></tr>')
    wording_note = ""
    if any(row["case_id"] == "heldout_05_corrected_recipient" and row["variant"] == "augmented"
           and row.get("wording_regex_false_negative") and row.get("native_operation_valid") for row in group["rows"]):
        wording_note = '<p class="muted small">Дополнительный смысловой критерий: у письма в augmented правильны write_to и имя адресата; приглашение понятно без буквального слова из regex. Частная проверка текста дала ложный отрицательный результат. Итоговая ручная ошибка — добавленная не запрошенная тема энергетики и торговли, а не JSON или имя страны.</p>'
    rejected_note = (f'<p class="notice">Исключено некорректных или повторных строк: {group["rejected_rows"]}. '
                     'Знаменатели получены только из уникальных допустимых оценок.</p>') if group["rejected_rows"] else ""
    return (
        '<article class="panel" id="manual-ai-review"><h3>Ручная оценка смысла — отдельный итог</h3>'
        '<p>Строгий вердикт проверяет требования исходного сценария, согласованность действия и полей ответа, '
        'адресата и опору на доступные сведения. Ложное сообщение о выполнении или существенная выдуманная деталь '
        'считаются ошибкой. Отдельные оговорки сохранены; правильная структура JSON сама по себе не означает успех.</p>'
        '<div class="table-wrap"><table><thead><tr><th>Вариант</th><th>Засчитано / всего</th>'
        '<th>Ошибки</th><th>Не поддерживается</th></tr></thead><tbody>' + summary_rows + '</tbody></table></div>'
        f'<p class="notice">Малая выборка: сценариев heldout — {len({row["case_id"] for row in group["rows"]})}, '
        f'вариантов — {len(group["variants"])}; по одному ответу на условие. '
        'Это prompt replay, а не исполнение этих команд внутри игры. Разницу нельзя обобщать как улучшение модели '
        'или рабочего мода памяти. Кандидат не поставляется.</p>'
        '<p class="muted small">Ручная оценка выполнена после замороженного прогона и не заменяет автоматические графики. '
        'Она учитывает смысловые ошибки, которых не видят шаблоны текста. Сценарии и автоматический оценщик '
        'после этой выборки не перенастраивались.</p>' + wording_note + rejected_note
        + '<details><summary>Краткие основания по каждому ответу</summary><div class="table-wrap"><table>'
        '<thead><tr><th>Сценарий и вариант</th><th>Вердикт</th><th>Причины без полного ответа модели</th></tr></thead>'
        '<tbody>' + "".join(detailed_rows) + '</tbody></table></div></details></article>')


def integration_sections(items):
    if not items:
        return '<p class="muted">Отдельный результат штатного AI-запроса в игре не предоставлен.</p>'
    result = []
    names = {"current_date": "Текущая игровая дата", "memory_number": "Контрольный факт из памяти", "show_moon": "Показ Луны"}
    for index, item in enumerate(items, 1):
        checks, metrics = item["checks"], item["measurements"]
        result.append(f'<h4>Нативный AI-прогон {index} {badge(checks["status"])}</h4>')
        if item["cases"]:
            count = metrics["case_count"]
            result.append(f'<p>Получено ответов: <b>{metrics["responses_received"]}/{count}</b>. Медиана задержки: <b>{fmt(metrics.get("median_latency_ms"))} мс</b> по {metrics["latency_sample_count"]} ответам. Автоматические проверки: <b>{checks["passed"]}/{checks["total"]}</b>.</p>')
            rows = "".join(f'<tr><th>{esc(names.get(row["id"], row["id"]))}</th><td>{"да" if row.get("received") is True else "не подтверждено"}</td><td>{fmt(row.get("elapsed_ms"))} мс</td><td>{"да" if row.get("native_schema") is True else "не подтверждено"}</td><td>{fmt(row.get("body_memory_marker_count"), 0)}</td></tr>' for row in item["cases"])
            result.append('<div class="table-wrap"><table><thead><tr><th>Сценарий</th><th>Ответ</th><th>Задержка</th><th>Схема ответа</th><th>Маркеров памяти</th></tr></thead><tbody>' + rows + '</tbody></table></div>')
            result.append(f'<p>Callback памяти вызван в {metrics["context_callback_observed"]}/{count} запросах; ровно один маркер памяти обнаружен в {metrics["single_memory_marker"]}/{count}. Валидна проверяемая часть нативной схемы: {metrics["native_schema_passed"]}/{count}.</p>')
        else:
            result.append(f'<p>Ответ получен: {"да" if item["response_received"] is True else "не подтверждено"}; длительность {fmt(metrics.get("elapsed_ms"))} мс. Проверки: {checks["passed"]}/{checks["total"]}.</p>')
        if checks["checks"].get("model_reads_control_number_from_mod_memory") is True:
            result.append('<p>Модель прочитала контрольный факт из памяти мода: это подтверждено отдельной проверкой ответа.</p>')
        if item["observations"].get("camera_action_applied") is True and checks["checks"].get("native_camera_targets_moon") is True:
            result.append('<p>Проверенная команда показа действительно переключила штатную камеру на Луну. Этот конкретный переход проверен в игре; перенос вывода на все команды не выполняется.</p>')
        if checks["failures"]:
            result.append('<p class="fail-list">Не пройдены: ' + "; ".join(esc(value) for value in checks["failures"]) + '.</p>')
        if item.get("manual_date_review"):
            result.append('<p class="notice">Ручная проверка: модель назвала правильную игровую дату словами, но не выполнила требование формата ДД.ММ.ГГГГ. Это нарушение формата ответа, а не установленная ошибка памяти. Автоматическая проверка оставлена неуспешной; весь прогон не объявляется прошедшим.</p>')
        elif "current_date_matches_game_components" in checks["failures"]:
            result.append('<p class="notice">Проверка числового ответа с текущей датой не пройдена. Без отдельной проверки текста причина не установлена; из этого результата нельзя заключить, что сломана память.</p>')
    return "".join(result)


def repeat_sections(groups):
    before, after = groups.get("before", []), groups.get("after", [])
    if not before and not after:
        return ""
    measured = [
        ("Первый готовый кадр мира от запуска", "first_world_frame_engine_ms", "мс"),
        ("Создание мира", "world_creation_ms", "мс"),
        ("Частота кадров", "fps", "FPS"),
        ("P95 интервала кадров", "frame_p95_ms", "мс"),
        ("Пиковая занятая RAM", "peak_working_set_mib", "МиБ"),
    ]
    charts = []
    for title, key, unit in measured:
        values = []
        for runs, label, color in [(before, "До", "#849bb0"), (after, "После", "#49c8bd")]:
            samples = [run["metrics"][key] for run in runs if run["status"] == "passed" and key in run["metrics"]]
            values.append((label, statistics.median(samples) if samples else None, color))
        charts.append(bars(title, unit, values, "Медиана только завершённых прогонов с этим измерением. Все выбранные прогоны и статусы приведены в таблице."))
    rows = []
    for label, runs in [("До", before), ("После", after)]:
        for run in runs:
            cells = "".join(f'<td>{fmt(run["metrics"].get(key))}</td>' for _, key, _ in measured)
            rows.append(f'<tr><th>{label} · {esc(run["run"])} {badge(run["status"])}</th>{cells}</tr>')
    columns = "".join(f'<th>{esc(title)} · {esc(unit)}</th>' for title, _, unit in measured)
    unsuccessful = [run["run"] for run in before + after if run["status"] != "passed"]
    failure_note = '<p class="notice">Из медианы исключены неподтверждённые или неуспешные прогоны: ' + ", ".join(esc(name) for name in unsuccessful) + '.</p>' if unsuccessful else ""
    return f'<section><div class="section-label">08 / ПОВТОРНЫЕ ЗАМЕРЫ</div><h2>Проверка разброса отдельной серией</h2><p>Выбрано прогонов: до — {len(before)}, после — {len(after)}. Эта серия измеряет запуск и отрисовку; она не заменяет полный тест механики и сохранений выше. Исходные одиночные результаты сохранены отдельно.</p>{failure_note}<div class="grid two">{"".join(charts)}</div><div class="table-wrap"><table><thead><tr><th>Прогон</th>{columns}</tr></thead><tbody>{"".join(rows)}</tbody></table></div><p class="muted">Малая серия показывает наблюдаемый разброс, но не устанавливает причину разницы. RAM включает весь процесс и тестовый стенд. Более долгий запуск или больший объём памяти остаются в таблице; ускорение по этим показателям не предполагается заранее.</p></section>'


def build_html(data):
    before, after, audit = data["before"], data["after"], data["audit"]
    complete = before["status"] == after["status"] == "passed"
    headline = "Оба игровых прогона завершены без ошибок проверки." if complete else "Сравнение незавершено или содержит ошибки. Ограничения показаны ниже."
    comparisons = [
        ("Частота кадров", "fps", "FPS", "Ограничитель 30 FPS не позволяет судить о предельной скорости игры."),
        ("95% кадров быстрее этого времени", "frame_p95_ms", "мс", "P95: только 5% измеренных интервалов кадров длиннее. Меньше — лучше."),
        ("Первый готовый кадр мира от запуска", "first_world_frame_engine_ms", "мс", "Время от запуска движка, включая активацию, создание мира и подготовку карты в стенде."),
        ("Создание нового мира", "world_creation_ms", "мс", "Время от создания Main до первого готового кадра мира в стенде."),
        ("Пиковая занятая RAM", "peak_working_set_mib", "МиБ", "Working set всего процесса, максимум выборок за прогон; не выделенная память одного мода."),
        ("Накопленное CPU-время процесса", "observed_process_cpu_seconds", "с", "Сумма времени потоков к последней выборке. Включает запуск и тесты: после изменения проверок больше. Это не нагрузка одного мода или чистой симуляции."),
        ("Запись сохранения", "native_save", "мс", "Штатная запись тестовой партии; состав сохранения после мода может быть больше."),
        ("Загрузка в новый Main", "fresh_main_load_and_world_ready", "мс", "Включает создание сцены и восстановление мира, не только чтение файла."),
    ]
    graphs = "".join(bars(title, unit, [("До", before["metrics"].get(key), "#849bb0"), ("После", after["metrics"].get(key), "#49c8bd")], hint) for title, key, unit, hint in comparisons)
    bench = after.get("cache_benchmark") or before.get("cache_benchmark")
    if bench and bench["batches"]:
        cached = [row["cached_us_per_operation"] for row in bench["batches"] if "cached_us_per_operation" in row]
        uncached = [row["uncached_us_per_operation"] for row in bench["batches"] if "uncached_us_per_operation" in row]
        bench_chart = bars("Повторный поиск одной и той же информации", "мкс/запрос", [("Поиск", statistics.median(uncached) if uncached else None, "#849bb0"), ("Кэш", statistics.median(cached) if cached else None, "#49c8bd")], "Медиана независимых серий. Микросекунды на один запрос, не миллисекунды и не FPS.")
        proof = f'{len(bench["batches"])} серий; {bench.get("records", "?")} записей; {bench.get("matching_scope_records", "?")} кандидатов. Результаты совпали: {"да" if bench["results_identical"] else "НЕТ"}. Попадания в кэш проверены: {"да" if bench["cache_hits_verified"] else "НЕТ"}.'
    else:
        bench_chart = '<p class="notice">Микрозамер кэша не предоставлен. Ускорение поиска не подтверждено этим отчётом.</p>'
        proof = "Для вывода об оптимизации нужны фактические серии с проверкой одинакового результата."
    failures = []
    for run in [before, after]:
        for name in run["checks"]["failures"]:
            failures.append(f'<li><b>{esc(run["label"])}</b>: {esc(name)}</li>')
        for group_name, group in run["groups"].items():
            for name in group["failures"]:
                failures.append(f'<li><b>{esc(run["label"])}</b>, {esc(group_name)}: {esc(name)}</li>')
        if run["status"] == "not_verified":
            failures.append(f'<li><b>{esc(run["label"])}</b>: нет полного подтверждения отчётом и кодом завершения процесса.</li>')
    failure_html = '<ul class="fail-list">' + "".join(failures) + '</ul>' if failures else '<p>В выбранных игровых отчётах ошибок проверки не отмечено. Это не распространяется на непроверенные функции.</p>'
    native_ai = integration_sections(data["native_ai"])
    storage_rows = "".join(f'<tr><th>{esc(run["label"])}</th><td>{fmt(run["storage"].get("total_bytes"), 0)} байт</td><td>{fmt(run["storage"].get("file_count"), 0)}</td><td>{fmt(run["memory_roundtrip"].get("records_after_load"), 0)}</td></tr>' for run in [before, after])
    skip_rows = "".join(f'<li><b>{esc(run["label"])}</b>: {esc("; ".join(SKIP_RU.get(key, key) for key in run["groups"]["mechanics"]["skipped"]) or "пропуски механики не перечислены")}</li>' for run in [before, after])
    audit_size = fmt(audit.get("bytes", 0) / 1e9, 3) if number(audit.get("bytes")) is not None else "нет данных"
    config_equal = before["rendering"] == after["rendering"] and before["version"] == after["version"]
    verification = data.get("original_verification", {})
    original_note = (f'Повторная проверка SHA-256: {fmt(verification.get("checked_files"), 0)} файлов оригинала без изменений.'
                     if verification.get("ok") is True else 'Повторная проверка всех файлов оригинала не подтверждена этим отчётом.')
    launch = data.get("launcher_smoke", {})
    launch_note = (f'Обычный запуск копии без QA-autoload: {fmt(launch.get("elapsed_ms", 0) / 1000, 3)} с до автоматического выхода, код 0, ошибок и предупреждений об утечках нет.'
                   if launch.get("status") == "clean_automatic_exit" and launch.get("exit_code") == 0 and launch.get("runtime_error_count") == 0 and launch.get("objectdb_leak_warning") is False
                   else 'Чистое завершение отдельного обычного запуска не подтверждено этим отчётом.')
    completion_notes = f'<section class="panel"><h2>Контроль оригинала и обычного запуска</h2><p>{esc(original_note)}</p><p>{esc(launch_note)}</p><p class="muted">Первый короткий smoke на 120 кадров оставил ошибку ресурсов при выходе; повтор на 1200 кадров её не воспроизвёл. Интерактивная готовность меню этим запуском не проверяется; создание мира проверено отдельно.</p><h3>Исправленная несовместимость сохранения памяти</h3><p>При загрузке и готовности мира игра передавала разные обёртки PaxGame для одного Main. Мод принимал их за разные партии и терял загруженную память. Теперь сравнивается живой Main; две регрессионные проверки подтверждают сохранение памяти своей партии и отказ от данных чужой.</p><p class="muted">Автоматический callback не передаёт текст вопроса: он отбирает память по текущему телу и игроку. Поиск с учётом запроса доступен через отдельный context_for для вызывающего кода.</p></section>'
    return f'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>Pax Universe — эксперимент и измерения</title><style>{STYLE}</style></head>
<body><header><div class="eyebrow">PAX UNIVERSE / ENGINEERING REPORT</div><h1>Что изменилось<br><em>и что удалось проверить</em></h1><p class="lead">Эксперимент в отдельной копии игры. Структурированная память для AI, проверка совместимости и измерения с сохранёнными ограничениями.</p><div class="chips"><span>Версия {esc(after["version"] if after["version"] != "unknown" else before["version"])}</span><span>{esc(data["generated_utc"][:10])} UTC</span><span>Исходная установка не заменяется</span></div></header>
<main><section class="panel status-panel"><h2>{esc(headline)}</h2><div class="run-pair"><p><b>До</b> · {esc(before["run"])} {badge(before["status"])}</p><p><b>После</b> · {esc(after["run"])} {badge(after["status"])}</p></div><p class="muted">Два одиночных прогона показывают наблюдение на этой машине, а не универсальный выигрыш производительности. Отрицательные результаты сохранены.</p></section>
<section><div class="section-label">01 / ГРАНИЦЫ РАБОТЫ</div><h2>Что было доступно</h2><div class="stats"><article><b>{fmt(audit.get("count"), 0)}</b><span>файлов в независимой копии</span></article><article><b>{audit_size} ГБ</b><span>суммарный размер, десятичные единицы</span></article><article><b>{fmt(audit.get("scripts_inspected"), 0)} / {fmt(audit.get("source_text_available"), 0)}</b><span>скриптов изучено / с доступным исходным текстом</span></article></div><div class="grid three"><article class="panel"><h3>Закрытое ядро</h3><p>Экспорт игры предоставляет исполняемые ресурсы и сведения об API. Полный исходный текст ядра недоступен: переписывание всей архитектуры этим экспериментом не выполнено.</p></article><article class="panel"><h3>Предел 30 FPS</h3><p>Стенд ограничивает частоту кадров. Значение около 30 FPS само по себе не доказывает ускорение или отсутствие нагрузки.</p></article><article class="panel"><h3>Синтетические AI-сценарии</h3><p>Replay проверяет ответы на вымышленные ситуации. Перемещение к точной провинции и исполнение приказов на карте не подтверждены этим контрактом.</p></article></div></section>
<section><div class="section-label">02 / ИЗМЕНЕНИЯ</div><h2>Память стала отдельным проверяемым компонентом</h2><div class="flow"><article><b>1</b><h3>Записать факт</h3><p>Запись хранит дату, участников, источник и уверенность. Ответ модели остаётся сообщением модели, а не доказанным событием.</p></article><article><b>2</b><h3>Найти относящееся к вопросу</h3><p>Индекс отбирает записи по участникам и словам. Информация о другой стране и ещё не наступившие события исключаются.</p></article><article><b>3</b><h3>Передать короткую выдержку</h3><p>Контекст ограничен по размеру. Приказы не превращаются в факты. Штатный контекст и формат ответа игры сохраняются.</p></article><article><b>4</b><h3>Сохранить вместе с партией</h3><p>Память проходит через callbacks сохранения мода. Проверка в новом Main ищет тот же контрольный факт после загрузки.</p></article></div><p class="notice">Это адаптер и самостоятельное хранилище памяти. Полная автономная стратегия AI, новые модели юнитов и переработка закрытого игрового ядра не заявляются готовыми.</p></section>
<section><div class="section-label">03 / ИЗМЕРЕНИЯ ИГРЫ</div><h2>До и после — в одинаковых единицах</h2><p class="muted">Конфигурации графики и версии {"совпадают" if config_equal else "различаются или не подтверждены"}: {esc(before["rendering"]["viewport"])} → {esc(after["rendering"]["viewport"])}. VSync: {esc(before["rendering"].get("vsync", "?"))} → {esc(after["rendering"].get("vsync", "?"))}. Лимит FPS: {esc(before["rendering"].get("max_fps", "?"))} → {esc(after["rendering"].get("max_fps", "?"))}.</p><div class="grid two">{graphs}</div><article class="panel"><h3>Все измеренные интервалы кадров</h3><p class="legend"><span><i style="background:#849bb0"></i>До</span><span><i style="background:#49c8bd"></i>После</span></p>{frame_svg(before, after)}<p class="muted small">Горизонтальная ось нормализована по длине каждого прогона. Линия включает ожидание следующего кадра и синхронизацию, а не только работу CPU.</p></article></section>
<section><div class="section-label">04 / ОПТИМИЗАЦИЯ ПОИСКА</div><h2>Повторный вопрос использует готовый результат</h2><div class="grid two">{bench_chart}<article class="panel"><h3>Как работает кэш</h3><p>Ключ включает вопрос, участников, игровой день, размер контекста и версию хранилища. При появлении или изменении записи результат пересчитывается.</p><p>{esc(proof)}</p><p class="muted">Проверяется повторяющийся запрос с прогретым кэшем. Это не измерение скорости модели, новых вопросов или всей игры. Совпадение результатов проверяется отдельно от таймера.</p></article></div></section>
<section><div class="section-label">05 / AI</div><h2>Качество ответа не равно исполнению в игре</h2><p>Рабочий мод pax_memory добавляет структурированную память к штатному контексту игры. Общие правила поведения из экспериментального промпта не поставляются: кандидат augmented отклонён и хранится отдельно в experiments/refactor/prompts/assistant_candidate.txt.</p><p class="muted">Зелёный сегмент означает выполнение автоматического контракта ответа. Ручная оценка, неподдерживаемые случаи и незапущенные тесты показаны отдельно и не входят в успешные.</p>{ai_sections(data["ai"])}{manual_ai_section(data.get("manual_ai"))}<article class="panel"><h3>Проверка штатного пути запроса</h3>{native_ai}<p class="muted small">Полученный ответ и вызов hook подтверждают интеграцию на проверенном пути. Они не подтверждают правильность всех игровых действий или долгосрочной стратегии.</p></article></section>
<section><div class="section-label">06 / ПРОВЕРКИ</div><h2>Сохранение, интерфейс и границы результата</h2>{check_table(before, after)}<div class="table-wrap"><table><thead><tr><th>Прогон</th><th>Размер всего слота</th><th>Файлов</th><th>Записей памяти после загрузки</th></tr></thead><tbody>{storage_rows}</tbody></table></div><article class="panel"><h3>Ошибки выбранных прогонов</h3>{failure_html}<h3>Что не проверено</h3><ul>{skip_rows}</ul><p>Длительные кампании, все комбинации дипломатии и войны, разные компьютеры и полный набор внешних AI-провайдеров этим кратким прогоном не покрыты.</p></article></section>
<section><div class="section-label">07 / ИСПРАВЛЕНИЯ СТЕНДА</div><h2>Ошибки проверки отделены от ошибок игры</h2><div class="grid three"><article class="panel"><h3>Корректный JSON</h3><p>PowerShell превращал пустой список отключённых модов в null. Явный массив [] и проверка типа перед запуском устранили ошибку экспериментального bootstrap.</p></article><article class="panel"><h3>Цельная тестовая партия</h3><p>Смена имени слота уже работающего Main разделяла мир и папку памяти. Теперь проверка сохраняет исходный свежий слот и загружает его целиком.</p></article><article class="panel"><h3>Завершение перемотки</h3><p>Стенд ждёт окончания расчёта и использует настоящую кнопку подтверждения отчёта. Занятая сцена не освобождается принудительно ради успешной проверки.</p></article></div></section>
{completion_notes}{repeat_sections(data.get("repeat_performance", {}))}<footer><h3>Проверяемые данные</h3><p>Рядом находится <a href="measurements.json">measurements.json</a>: числа, имена проверок и SHA-256 входных отчётов. Нативные промпты, ответы модели, лицензии, пути профиля и содержимое сохранений исключены по списку разрешённых полей.</p><p class="muted small">Отчёт работает без интернета, внешних шрифтов и CDN. Сформирован: {esc(data["generated_utc"])}.</p></footer></main></body></html>'''


STYLE = r'''
:root{--bg:#09121d;--panel:#111f2d;--edge:#283d50;--ink:#e6edf3;--muted:#a9bbca;--accent:#49c8bd}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:radial-gradient(ellipse at 85% 0,#173343 0,transparent 36%),var(--bg);color:var(--ink);font:16px/1.65 "Segoe UI",Arial,sans-serif}header,main{max-width:1160px;margin:auto;padding:0 28px}header{padding-top:74px;padding-bottom:45px;border-bottom:1px solid var(--edge)}.eyebrow,.section-label{font-size:12px;letter-spacing:.2em;color:var(--accent);font-weight:700}h1{font-size:clamp(36px,5vw,64px);line-height:1.12;letter-spacing:-.035em;margin:22px 0}h1 em{font-style:normal;color:var(--accent)}h2{font-size:clamp(25px,3vw,34px);line-height:1.3;margin:12px 0 24px;letter-spacing:-.02em}h3{font-size:19px;line-height:1.4;margin:0 0 12px}h4{margin:24px 0 12px}p{margin:0 0 16px;overflow-wrap:anywhere}.lead{max-width:850px;font-size:19px;color:#b9c9d8}.chips,.run-pair,.legend{display:flex;flex-wrap:wrap;gap:12px}.chips span{border:1px solid var(--edge);border-radius:6px;padding:6px 12px;font-size:13px;color:var(--muted)}section{margin:42px 0 62px}.panel,.chart{padding:25px;border:1px solid var(--edge);border-radius:12px;background:linear-gradient(155deg,#152737a0,#0e1c29e8);box-shadow:inset 0 1px #ffffff06}.panel{margin-bottom:18px}.status-panel{border-left:3px solid var(--accent);margin-top:34px}.status-panel h2{font-size:24px}.grid{display:grid;gap:18px}.two{grid-template-columns:repeat(2,minmax(0,1fr))}.three{grid-template-columns:repeat(3,minmax(0,1fr))}.muted{color:var(--muted)}.small{font-size:13px}.badge{display:inline-block;font-size:12px;border-radius:4px;padding:3px 9px;margin-left:8px;border:1px solid currentColor;white-space:nowrap}.passed{color:#5fd1b0}.failed{color:#ee8290}.not_verified{color:#e6bd6c}.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin:22px 0}.stats article{border-bottom:2px solid var(--edge);padding:12px 0 22px}.stats b{display:block;font-size:35px;color:var(--accent);letter-spacing:-.025em}.stats span{color:var(--muted);font-size:14px}.flow{display:grid;grid-template-columns:repeat(4,1fr);gap:22px;margin:30px 0}.flow article>b{display:inline-grid;place-items:center;width:37px;height:37px;background:#173945;border:1px solid #397b86;color:var(--accent);border-radius:8px;margin-bottom:17px}.flow p{color:var(--muted);font-size:14px}.flow h3{font-size:17px}.notice{padding:18px 21px;border-left:2px solid #b99e62;background:#bc975d0b;color:#d4c8ad}.chart p{margin-bottom:0;min-height:3.2em}.chart svg,.panel svg{display:block;width:100%;height:auto;overflow:visible}.legend{gap:10px 20px;margin:12px 0 18px;font-size:13px;color:var(--muted)}.legend i{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:7px}.legend b{color:var(--ink)}.table-wrap{overflow:auto;margin-bottom:22px}table{width:100%;border-collapse:collapse;background:#0f1c29}th,td{padding:15px 17px;border-bottom:1px solid var(--edge);text-align:left;font-size:14px}thead th{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}tbody th{font-weight:500}.fail-list{color:#efadba;overflow-wrap:anywhere}li{margin:7px 0}footer{padding:26px 0 65px;border-top:1px solid var(--edge)}a{color:var(--accent);text-underline-offset:3px}@media(max-width:780px){header,main{padding-left:20px;padding-right:20px}header{padding-top:42px}.two,.three,.flow{grid-template-columns:1fr}.stats{gap:12px}.stats b{font-size:24px}.stats span{font-size:12px}.panel,.chart{padding:20px}.flow{gap:4px}.flow article{border-bottom:1px solid var(--edge);padding:14px 0}.flow article>b{float:left;margin-right:15px;margin-bottom:5px}.flow p{clear:both}section{margin-bottom:46px}.run-pair{display:block}.badge{margin-top:6px}}@media print{body{background:white;color:#162536}header,main{max-width:none;padding:0}header{padding-bottom:20px}.panel,.chart,table{background:white;box-shadow:none}.muted,.lead,.legend,.chips span{color:#394f62}.grid{break-inside:avoid}.chart svg text,.panel svg text{fill:#263c51}.panel{break-inside:avoid}section{margin:24px 0}.notice{color:#524628}footer{padding-bottom:0}.badge{color:#34465a}a{color:#15616b}}
'''


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, help="Run directory or baseline.json; absence stays unverified")
    parser.add_argument("--after", type=Path, help="Run directory or baseline.json")
    parser.add_argument("--perf-before", type=Path, action="append", default=[], help="Separate repeat-performance run before memory; repeatable")
    parser.add_argument("--perf-after", type=Path, action="append", default=[], help="Separate repeat-performance run after memory; repeatable")
    parser.add_argument("--ai-baseline", type=Path, action="append", default=[], help="Explicit baseline AI summary; repeatable")
    parser.add_argument("--ai-after", type=Path, action="append", default=[], help="Rejected augmented prompt candidate summary, not shipped memory mod; repeatable")
    parser.add_argument("--ai", type=Path, action="append", default=[], help="Additional AI summary, e.g. heldout; repeatable")
    parser.add_argument("--native-ai", type=Path, action="append", default=[], help="Optional native integration JSON; only allowlisted scalars/checks published")
    parser.add_argument("--manual-ai", type=Path, help="Own manual-review.json; only verdicts, short reasons and hashes are published")
    parser.add_argument("--native-ai-date-format-reviewed", type=Path, action="append", default=[], help="Attest manual review of this selected integration: correct date in words, requested numeric format not met; does not change failed check")
    parser.add_argument("--inventory", type=Path, default=LOCAL / "original-inventory.json")
    parser.add_argument("--audit", type=Path, default=LOCAL / "runs" / "audit-01" / "runtime-inventory.json")
    parser.add_argument("--original-verification", type=Path, default=LOCAL / "original-verification.json")
    parser.add_argument("--launcher-smoke", type=Path, help="Own launcher-smoke.json; only status, counters and flags published")
    parser.add_argument("--output", type=Path, required=True, help="Directory for report.html and measurements.json")
    args = parser.parse_args(argv)
    ai = [(path, "Базовый AI") for path in args.ai_baseline] + [(path, "Отклонённый кандидат промпта") for path in args.ai_after] + [(path, "Дополнительный AI-прогон") for path in args.ai]
    normalized = lambda path: (path / "ai-integration.json" if path.is_dir() else path).resolve()
    reviewed = {normalized(path) for path in args.native_ai_date_format_reviewed}
    if reviewed - {normalized(path) for path in args.native_ai}:
        parser.error("--native-ai-date-format-reviewed must identify an input selected by --native-ai")
    verification, _ = read_json(args.original_verification)
    launcher, _ = read_json(args.launcher_smoke)
    data = {"schema_version": 2, "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "before": read_run(args.before, "До"), "after": read_run(args.after, "После"), "audit": read_audit(args.inventory, args.audit),
            "repeat_performance": {"before": [read_run(path, "До") for path in args.perf_before], "after": [read_run(path, "После") for path in args.perf_after]},
            "ai": [read_ai(path, label) for path, label in ai], "native_ai": [read_integration(path, normalized(path) in reviewed) for path in args.native_ai],
            "manual_ai": read_manual_ai(args.manual_ai),
            "original_verification": {**numeric(verification, ["checked_files"]), "ok": verification.get("ok") is True, "sha256": checksum(args.original_verification)},
            "launcher_smoke": {**numeric(launcher, ["exit_code", "elapsed_ms", "requested_frames", "runtime_error_count"]), "status": safe_id(launcher.get("status", "not_verified")), **{key: launcher[key] for key in ["shutdown_resource_error", "objectdb_leak_warning", "menu_ready_verified", "automatic_exit"] if isinstance(launcher.get(key), bool)}, "sha256": checksum(args.launcher_smoke)},
            "ai_prompt_candidate": {"variant": "augmented", "disposition": "rejected_experimental_candidate_not_shipped", "shipped_memory_mod_adds_generic_prompt_rules": False},
            "privacy": {"allowlist_only": True, "native_prompts_included": False, "raw_answers_included": False, "credentials_included": False, "save_contents_included": False},
            "limitations": ["Closed exported core; no full-source refactor", "30 FPS cap; single-machine single-run comparison", "AI replay uses synthetic entities; spatial game execution unsupported", "Microbenchmark is repeated warm-cache retrieval, not game FPS"]}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "measurements.json").write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (args.output / "report.html").write_text(build_html(data), encoding="utf-8")
    print(json.dumps({"report_created": True, "before_status": data["before"]["status"], "after_status": data["after"]["status"], "ai_summaries": len(data["ai"]), "output": str(args.output)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
