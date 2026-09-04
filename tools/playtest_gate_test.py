#!/usr/bin/env python3

import json
import tempfile
import unittest
from pathlib import Path

import playtest_gate


def fixture(cohort: str, runs: int = 12) -> dict:
    difficulty = playtest_gate.COHORT_RULES[cohort]["difficulty"]
    clear_rates = {"novice": 0.75, "core": 0.50, "expert": 0.25}
    clear_count = round(runs * clear_rates[cohort])
    entries = []
    for index in range(runs):
        cleared = index < clear_count
        character = index % 3
        entries.append(
            {
                "timestamp": 999_000 + index,
                "character": character,
                "difficulty": difficulty,
                "stage_id": ["neon_district_01", "null_tempest_02", "helios_forge_03"][index % 3],
                "cleared": cleared,
                "assisted": False,
                "total_score": 500_000 + character * 15_000 + index * 100,
                "deaths": index % 3,
                "barriers_used": index % 2,
                "clear_time": 210.0 + index if cleared else 0.0,
                "risk_bank_bonus": 20_000 if index % 2 == 0 else 0,
                "boss_phase_metrics": [
                    {"phase": phase + 1, "overdrive": phase == 7 and index % 3 == 0}
                    for phase in range(8 if cleared else 3)
                ],
            }
        )
    return {
        "schema_version": 3,
        "privacy": "Local gameplay metrics only; no player identity or network data.",
        "runs": entries,
        "stage_summaries": {
            "neon_district_01": {},
            "null_tempest_02": {},
            "helios_forge_03": {},
        },
    }


class PlaytestGateTest(unittest.TestCase):
    def test_ready_cohorts_are_aggregate_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            inputs = {}
            for cohort in playtest_gate.COHORT_RULES:
                path = Path(directory, f"{cohort}.json")
                path.write_text(json.dumps(fixture(cohort)), encoding="utf-8")
                inputs[cohort] = [path]
            report = playtest_gate.build_report(inputs)
        self.assertEqual(report["status"], "ready")
        encoded = json.dumps(report)
        self.assertNotIn('"timestamp":', encoded)
        self.assertNotIn('"boss_phase_metrics":', encoded)
        self.assertNotIn("999000", encoded)
        for cohort in playtest_gate.COHORT_RULES:
            self.assertEqual(report["cohorts"][cohort]["status"], "ready")

    def test_missing_cohorts_fail_readiness_without_fabricating_runs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "novice.json")
            path.write_text(json.dumps(fixture("novice")), encoding="utf-8")
            report = playtest_gate.build_report({"novice": [path], "core": [], "expert": []})
        self.assertEqual(report["status"], "not_ready")
        self.assertEqual(report["cohorts"]["core"]["summary"]["runs"], 0)

    def test_overlapping_archive_exports_do_not_duplicate_runs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory, "core_01.json")
            second = Path(directory, "core_02.json")
            payload = fixture("core")
            first.write_text(json.dumps(payload), encoding="utf-8")
            second.write_text(json.dumps(payload), encoding="utf-8")
            result = playtest_gate.analyze_cohort(
                "core",
                [playtest_gate.load_export(first), playtest_gate.load_export(second)],
            )
        self.assertEqual(result["summary"]["runs"], 12)
        self.assertEqual(result["status"], "ready")

    def test_invalid_or_identity_bearing_contract_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "invalid.json")
            path.write_text(json.dumps({"schema_version": 2, "runs": []}), encoding="utf-8")
            with self.assertRaises(playtest_gate.ExportError):
                playtest_gate.load_export(path)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(PlaytestGateTest)
    result = unittest.TextTestRunner(verbosity=0).run(suite)
    if result.wasSuccessful():
        print("PLAYTEST_GATE_TEST_OK cohorts=3 coverage=character+stage metrics=clear+overdrive+risk privacy=aggregate_only")
    raise SystemExit(0 if result.wasSuccessful() else 1)
