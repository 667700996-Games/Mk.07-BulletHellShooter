#!/usr/bin/env python3
"""Aggregate privacy-safe Combat Archive exports into a release gate.

The tool never emits raw runs or timestamps. Cohort labels are supplied by the
researcher, not collected by the game, and should describe experience bands
only (novice/core/expert), never participant identity.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 3
COHORT_RULES: dict[str, dict[str, Any]] = {
    "novice": {
        "difficulty": "story",
        "min_runs": 12,
        "clear_rate": (0.50, 0.95),
        "max_overdrive_rate": 0.70,
    },
    "core": {
        "difficulty": "normal",
        "min_runs": 12,
        "clear_rate": (0.30, 0.80),
        "max_overdrive_rate": 0.55,
    },
    "expert": {
        "difficulty": "expert",
        "min_runs": 12,
        "clear_rate": (0.10, 0.60),
        "max_overdrive_rate": 0.45,
    },
}
MIN_RUNS_PER_CHARACTER = 3
MIN_RUNS_PER_STAGE = 3
MAX_CHARACTER_SCORE_SPREAD = 0.18
MIN_RISK_ENGAGEMENT_RATE = 0.25


class ExportError(ValueError):
    pass


def load_export(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ExportError(f"{path}: unreadable JSON ({error})") from error
    if not isinstance(payload, dict) or payload.get("schema_version") != SCHEMA_VERSION:
        raise ExportError(f"{path}: expected Combat Archive schema {SCHEMA_VERSION}")
    if not isinstance(payload.get("runs"), list):
        raise ExportError(f"{path}: runs must be an array")
    privacy = payload.get("privacy", "")
    if not isinstance(privacy, str) or "no player identity" not in privacy.lower():
        raise ExportError(f"{path}: privacy declaration is missing or incompatible")
    return payload


def _gate(gate_id: str, passed: bool, value: Any, target: str) -> dict[str, Any]:
    return {"id": gate_id, "status": "pass" if passed else "fail", "value": value, "target": target}


def _safe_number(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return default
    return max(0.0, float(value))


def analyze_cohort(cohort: str, payloads: list[dict[str, Any]]) -> dict[str, Any]:
    rules = COHORT_RULES[cohort]
    difficulty = rules["difficulty"]
    known_stages: set[str] = set()
    raw_runs: list[dict[str, Any]] = []
    for payload in payloads:
        stage_summaries = payload.get("stage_summaries", {})
        if isinstance(stage_summaries, dict):
            known_stages.update(str(stage_id) for stage_id in stage_summaries)
        raw_runs.extend(run for run in payload["runs"] if isinstance(run, dict))

    # Combat Archive exports are rolling snapshots, so consecutive batch files can
    # contain the same run. Exact canonical fingerprints prevent overlapping
    # exports from inflating the release sample while retaining genuinely distinct
    # attempts. Fingerprints never leave this process or appear in the report.
    unique_runs: list[dict[str, Any]] = []
    seen_runs: set[str] = set()
    for run in raw_runs:
        fingerprint = json.dumps(run, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        if fingerprint in seen_runs:
            continue
        seen_runs.add(fingerprint)
        unique_runs.append(run)

    runs = [
        run
        for run in unique_runs
        if run.get("difficulty") == difficulty and not bool(run.get("assisted", False))
    ]
    run_count = len(runs)
    clear_count = sum(bool(run.get("cleared", False)) for run in runs)
    clear_rate = clear_count / run_count if run_count else 0.0
    character_counts = {str(index): sum(int(run.get("character", -1)) == index for run in runs) for index in range(3)}
    stage_counts = {
        stage_id: sum(str(run.get("stage_id", "")) == stage_id for run in runs)
        for stage_id in sorted(known_stages)
    }

    phase_count = 0
    overdrive_count = 0
    for run in runs:
        metrics = run.get("boss_phase_metrics", [])
        if not isinstance(metrics, list):
            continue
        for metric in metrics:
            if isinstance(metric, dict):
                phase_count += 1
                overdrive_count += int(bool(metric.get("overdrive", False)))
    overdrive_rate = overdrive_count / phase_count if phase_count else 1.0

    cleared_scores: dict[int, list[float]] = {0: [], 1: [], 2: []}
    for run in runs:
        character = int(run.get("character", -1))
        if bool(run.get("cleared", False)) and character in cleared_scores:
            cleared_scores[character].append(_safe_number(run.get("total_score")))
    character_medians = {
        str(character): statistics.median(scores) if scores else 0.0
        for character, scores in cleared_scores.items()
    }
    nonzero_medians = [value for value in character_medians.values() if value > 0.0]
    score_spread = (
        (max(nonzero_medians) - min(nonzero_medians)) / statistics.mean(nonzero_medians)
        if len(nonzero_medians) == 3
        else 1.0
    )
    risk_runs = sum(_safe_number(run.get("risk_bank_bonus")) > 0.0 for run in runs)
    risk_engagement_rate = risk_runs / run_count if run_count else 0.0
    deaths = [_safe_number(run.get("deaths")) for run in runs]
    barriers = [_safe_number(run.get("barriers_used")) for run in runs]
    clear_times = [_safe_number(run.get("clear_time")) for run in runs if bool(run.get("cleared", False))]

    gates = [
        _gate("sample_size", run_count >= rules["min_runs"], run_count, f">={rules['min_runs']} unassisted {difficulty} runs"),
        _gate(
            "character_coverage",
            all(count >= MIN_RUNS_PER_CHARACTER for count in character_counts.values()),
            character_counts,
            f">={MIN_RUNS_PER_CHARACTER} runs per character",
        ),
        _gate(
            "stage_coverage",
            bool(stage_counts) and all(count >= MIN_RUNS_PER_STAGE for count in stage_counts.values()),
            stage_counts,
            f">={MIN_RUNS_PER_STAGE} runs per catalog stage",
        ),
        _gate(
            "clear_rate",
            rules["clear_rate"][0] <= clear_rate <= rules["clear_rate"][1],
            round(clear_rate, 4),
            f"{rules['clear_rate'][0]:.0%}..{rules['clear_rate'][1]:.0%}",
        ),
        _gate(
            "boss_overdrive",
            phase_count > 0 and overdrive_rate <= rules["max_overdrive_rate"],
            round(overdrive_rate, 4),
            f"<={rules['max_overdrive_rate']:.0%} of observed boss phases",
        ),
        _gate(
            "character_score_spread",
            len(nonzero_medians) == 3 and score_spread <= MAX_CHARACTER_SCORE_SPREAD,
            {"medians": character_medians, "spread": round(score_spread, 4)},
            f"<={MAX_CHARACTER_SCORE_SPREAD:.0%} across cleared-run medians",
        ),
        _gate(
            "risk_engagement",
            risk_engagement_rate >= MIN_RISK_ENGAGEMENT_RATE,
            round(risk_engagement_rate, 4),
            f">={MIN_RISK_ENGAGEMENT_RATE:.0%} of runs bank a nonzero reserve",
        ),
    ]
    return {
        "cohort": cohort,
        "difficulty": difficulty,
        "status": "ready" if all(gate["status"] == "pass" for gate in gates) else "not_ready",
        "summary": {
            "runs": run_count,
            "clears": clear_count,
            "clear_rate": round(clear_rate, 4),
            "median_deaths": statistics.median(deaths) if deaths else 0.0,
            "median_barriers": statistics.median(barriers) if barriers else 0.0,
            "median_clear_time": statistics.median(clear_times) if clear_times else 0.0,
            "overdrive_rate": round(overdrive_rate, 4),
            "risk_engagement_rate": round(risk_engagement_rate, 4),
        },
        "gates": gates,
    }


def build_report(inputs: dict[str, list[Path]]) -> dict[str, Any]:
    cohorts: dict[str, Any] = {}
    for cohort in COHORT_RULES:
        payloads = [load_export(path) for path in inputs.get(cohort, [])]
        cohorts[cohort] = analyze_cohort(cohort, payloads)
    ready = all(result["status"] == "ready" for result in cohorts.values())
    return {
        "report_schema": 1,
        "privacy": "Aggregate gameplay metrics only; raw runs, timestamps, paths, and participant identity are omitted.",
        "status": "ready" if ready else "not_ready",
        "cohorts": cohorts,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    for cohort in COHORT_RULES:
        parser.add_argument(f"--{cohort}", action="append", type=Path, default=[], metavar="EXPORT.json")
    parser.add_argument("--output", type=Path, help="also write the aggregate report to this path")
    parser.add_argument("--require-ready", action="store_true", help="exit 1 unless every cohort gate passes")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    inputs = {cohort: list(getattr(args, cohort)) for cohort in COHORT_RULES}
    if not any(inputs.values()):
        print("PLAYTEST_GATE_ERROR at least one cohort export is required", file=sys.stderr)
        return 2
    try:
        report = build_report(inputs)
    except ExportError as error:
        print(f"PLAYTEST_GATE_ERROR {error}", file=sys.stderr)
        return 2
    encoded = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True)
    print(encoded)
    if args.output:
        try:
            args.output.write_text(encoded + "\n", encoding="utf-8")
        except OSError as error:
            print(f"PLAYTEST_GATE_ERROR could not write {args.output}: {error}", file=sys.stderr)
            return 2
    print(f"PLAYTEST_GATE_{report['status'].upper()} cohorts=3 raw_runs_omitted=true")
    return 1 if args.require_ready and report["status"] != "ready" else 0


if __name__ == "__main__":
    raise SystemExit(main())
