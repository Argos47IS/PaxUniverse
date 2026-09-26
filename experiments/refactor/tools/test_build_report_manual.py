"""Manual-review report checks using public reviews and original synthetic data."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest

import build_report as report


class ManualReportChecks(unittest.TestCase):
    def test_real_review_counts_are_derived(self):
        source = Path(__file__).resolve().parent.parent / "manual-review.json"
        data = report.read_manual_ai(source)
        counts = {item["variant"]: item for item in data["variants"]}
        self.assertEqual(len(data["rows"]), 20)
        self.assertEqual(counts["baseline"]["counts"]["pass"], 1)
        self.assertEqual(counts["augmented"]["counts"]["pass"], 3)
        self.assertEqual(counts["baseline"]["total"], 10)
        self.assertEqual(counts["augmented"]["total"], 10)
        markup = report.manual_ai_section(data)
        self.assertIn("<b>1/10</b>", markup)
        self.assertIn("<b>3/10</b>", markup)
        self.assertIn("prompt replay", markup)
        self.assertIn("Малая выборка", markup)
        self.assertIn("ложный отрицательный результат", markup)
        self.assertIn("не JSON или имя страны", markup)

    def test_allowlist_drops_private_fields_and_does_not_trust_counts(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "review.json"
            row = {"case_id": "heldout_01_sample", "variant": "baseline", "verdict": "fail",
                   "reasons": ["Наше объяснение <script>alert(1)</script>"],
                   "raw_answer": "RAW_ANSWER_CANARY", "thinking": "THINKING_CANARY"}
            path.write_text(json.dumps({"model": "qwen3.5:4b", "results": [row, row],
                "counts": {"baseline": {"pass": 999}}, "native_prompt": "PROMPT_CANARY",
                "credentials": "CREDENTIAL_CANARY",
                "actual_native_integration": {"raw": "NATIVE_CANARY"}}), encoding="utf-8")
            data = report.read_manual_ai(path)
            serialized = json.dumps(data)
            for marker in ("RAW_ANSWER_CANARY", "THINKING_CANARY", "PROMPT_CANARY",
                           "CREDENTIAL_CANARY", "NATIVE_CANARY"):
                self.assertNotIn(marker, serialized)
            self.assertEqual(data["variants"][0]["total"], 1)
            self.assertEqual(data["variants"][0]["counts"]["pass"], 0)
            self.assertEqual(data["rejected_rows"], 1)
            markup = report.manual_ai_section(data)
            self.assertNotIn("<script>", markup)
            self.assertIn("&lt;script&gt;", markup)

    def test_cli_retains_automatic_chart_and_28_of_29(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = Path(__file__).resolve().parent.parent / "manual-review.json"
            integration = root / "integration.json"
            checks = {f"check_{index}": True for index in range(28)}
            checks["current_date_matches_game_components"] = False
            integration.write_text(json.dumps({"ok": False, "checks": checks,
                "failures": ["current_date_matches_game_components"], "cases": [
                    {"id": "current_date", "elapsed_ms": 10, "received": True,
                     "native_schema": True, "body_memory_marker_count": 1,
                     "context_callback_calls": 1}]}), encoding="utf-8")
            ai = root / "ai.json"
            ai.write_text(json.dumps({"model": "qwen3.5:4b", "split": "dev", "results": [
                {"case_id": "dev_01_fixture", "variant": "baseline",
                 "score": {"verdict": "fail"}, "metrics": {"latency_ms": 20}}]}), encoding="utf-8")
            output = root / "output"
            with contextlib.redirect_stdout(io.StringIO()):
                code = report.main(["--manual-ai", str(source), "--ai", str(ai),
                    "--native-ai", str(integration), "--native-ai-date-format-reviewed", str(integration),
                    "--inventory", str(root / "absent.json"), "--audit", str(root / "absent.json"),
                    "--output", str(output)])
            self.assertEqual(code, 0)
            data = json.loads((output / "measurements.json").read_text(encoding="utf-8"))
            markup = (output / "report.html").read_text(encoding="utf-8")
            self.assertEqual(len(data["manual_ai"]["rows"]), 20)
            self.assertEqual(data["native_ai"][0]["checks"]["passed"], 28)
            self.assertEqual(data["native_ai"][0]["checks"]["total"], 29)
            self.assertEqual(data["ai"][0]["variants"][0]["counts"]["fail"], 1)
            self.assertIn("Распределение результатов", markup)
            self.assertIn("<b>28/29</b>", markup)
            self.assertIn('id="manual-ai-review"', markup)
            self.assertIn("не выполнила требование формата ДД.ММ.ГГГГ", markup)
            self.assertEqual(markup.count('id="manual-ai-review"'), 1)

    def test_missing_or_unjustified_review_not_counted(self):
        with tempfile.TemporaryDirectory() as folder:
            missing = report.read_manual_ai(Path(folder) / "missing.json")
            self.assertEqual(missing["rows"], [])
            self.assertIn("нет подтверждённых", report.manual_ai_section(missing))
            path = Path(folder) / "empty-reasons.json"
            path.write_text(json.dumps({"results": [
                {"case_id": "heldout_01_empty", "variant": "baseline", "verdict": "pass"}]}), encoding="utf-8")
            self.assertEqual(report.read_manual_ai(path)["rows"], [])


if __name__ == "__main__":
    unittest.main()
