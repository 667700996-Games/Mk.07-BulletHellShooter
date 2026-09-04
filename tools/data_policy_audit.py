#!/usr/bin/env python3
"""Validate the local-data/no-network contract against production sources."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "resources" / "data_policy.json"
PRODUCTION_DIRECTORIES = (
    "autoload", "audio", "boss", "bullet", "core", "effects", "enemy",
    "pattern", "player", "resources", "stage", "ui",
)
NETWORK_API_PATTERN = re.compile(
    r"\b(?:HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|"
    r"PacketPeerUDP|UDPServer|TCPServer|StreamPeerTCP|ENetMultiplayerPeer|"
    r"MultiplayerAPI|XMLRPC)\b"
)
EXPECTED_DATASETS = {
    "settings_progression_records": {
        "trigger": "automatic_local_persistence",
        "path": "user://psychic_vector.cfg",
        "retention_limit": 60,
        "retention_unit": "campaign_runs",
    },
    "replay_vault": {
        "trigger": "automatic_local_persistence",
        "path": "user://psychic_vector_replays",
        "retention_limit": 12,
        "retention_unit": "replays",
    },
    "session_journal": {
        "trigger": "automatic_local_persistence",
        "path": "user://psychic_vector_session_journal.json",
        "retention_limit": 12,
        "retention_unit": "completed_sessions",
        "build_context": "release_candidate_id",
    },
    "playtest_export": {
        "trigger": "user_action_only",
        "path": "user://psychic_vector_playtest.json",
        "retention_limit": 1,
        "retention_unit": "replaceable_export",
    },
    "diagnostics_export": {
        "trigger": "user_action_only",
        "path": "user://psychic_vector_diagnostics.json",
        "retention_limit": 1,
        "retention_unit": "replaceable_export",
        "build_context": "release_candidate_id",
    },
}


class PolicyError(RuntimeError):
    pass


def _read_text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def _constant(source: str, name: str) -> str:
    match = re.search(rf'^const\s+{re.escape(name)}\s*:=\s*"([^"]+)"', source, re.MULTILINE)
    if not match:
        raise PolicyError(f"missing string constant: {name}")
    return match.group(1)


def _integer_constant(source: str, name: str) -> int:
    match = re.search(rf"^const\s+{re.escape(name)}\s*:=\s*(\d+)", source, re.MULTILINE)
    if not match:
        raise PolicyError(f"missing integer constant: {name}")
    return int(match.group(1))


def _load_policy() -> dict[str, Any]:
    try:
        value = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PolicyError(f"data policy is unreadable: {exc}") from exc
    if not isinstance(value, dict):
        raise PolicyError("data policy root must be an object")
    return value


def _audit_policy_document(policy: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if policy.get("schema_version") != 1:
        raise PolicyError("data policy schema_version must be 1")
    if policy.get("product") != "PSYCHIC VECTOR":
        raise PolicyError("data policy product identity changed")
    for flag in ("network_transmission", "online_telemetry", "identity_fields_collected"):
        if policy.get(flag) is not False:
            raise PolicyError(f"{flag} must remain explicitly false")
    if policy.get("external_legal_review") != "pending":
        raise PolicyError("external legal review may change only with reviewed evidence")
    if policy.get("disclosure_locales") != ["en", "ko"]:
        raise PolicyError("data-policy disclosure locales must be exactly en and ko")
    raw_datasets = policy.get("datasets")
    if not isinstance(raw_datasets, list):
        raise PolicyError("datasets must be an array")
    datasets: dict[str, dict[str, Any]] = {}
    for raw in raw_datasets:
        if not isinstance(raw, dict) or not isinstance(raw.get("id"), str):
            raise PolicyError("every dataset must be an object with a stable id")
        dataset_id = raw["id"]
        if dataset_id in datasets:
            raise PolicyError(f"duplicate dataset id: {dataset_id}")
        datasets[dataset_id] = raw
    if set(datasets) != set(EXPECTED_DATASETS):
        raise PolicyError(f"dataset catalog drift: {sorted(datasets)}")
    for dataset_id, expected in EXPECTED_DATASETS.items():
        actual = datasets[dataset_id]
        if actual.get("destination") != "local_device":
            raise PolicyError(f"{dataset_id} destination must remain local_device")
        for key, value in expected.items():
            if actual.get(key) != value:
                raise PolicyError(f"{dataset_id}.{key} must be {value!r}")
    return datasets


def _audit_implementation(datasets: dict[str, dict[str, Any]]) -> None:
    save = _read_text("autoload/save_manager.gd")
    replay = _read_text("autoload/replay_manager.gd")
    diagnostics = _read_text("autoload/session_diagnostics.gd")
    records = _read_text("ui/records_screen.gd")
    game_text = _read_text("resources/game_text.gd")
    release_metadata = json.loads(_read_text("release/release_metadata.json"))

    contracts = {
        "settings_progression_records": (_constant(save, "SAVE_PATH"), _integer_constant(save, "MAX_RUN_HISTORY")),
        "replay_vault": (_constant(replay, "REPLAY_DIRECTORY"), _integer_constant(replay, "MAX_REPLAYS")),
        "session_journal": (_constant(diagnostics, "JOURNAL_PATH"), _integer_constant(diagnostics, "MAX_SESSION_HISTORY")),
        "playtest_export": (_constant(save, "PLAYTEST_EXPORT_PATH"), 1),
        "diagnostics_export": (_constant(diagnostics, "DIAGNOSTICS_EXPORT_PATH"), 1),
    }
    for dataset_id, (path, retention) in contracts.items():
        if datasets[dataset_id]["path"] != path:
            raise PolicyError(f"{dataset_id} policy path differs from implementation")
        if datasets[dataset_id]["retention_limit"] != retention:
            raise PolicyError(f"{dataset_id} retention differs from implementation")

    release_path = _constant(diagnostics, "RELEASE_METADATA_PATH")
    if release_path != "res://release/release_metadata.json":
        raise PolicyError("session diagnostics do not use the canonical release metadata")
    expected_candidate_id = (
        f"{release_metadata['artifact_name']}-{release_metadata['version']}-"
        f"build.{release_metadata['build_number']}-unsigned"
    )
    required_build_contract = (
        '"build_identity": current_build_identity()',
        '"build_id": current_build_id()',
        "LEGACY_BUILD_ID",
    )
    for fragment in required_build_contract:
        if fragment not in diagnostics:
            raise PolicyError(f"session build correlation is missing: {fragment}")
    if expected_candidate_id not in _read_text("tools/session_diagnostics_test.gd"):
        raise PolicyError("session diagnostics test is not pinned to the current release candidate")

    manual_calls = ("SaveManager.export_playtest_data()", "SessionDiagnostics.export_diagnostics()")
    for call in manual_calls:
        if records.count(call) != 1:
            raise PolicyError(f"manual export action is missing or duplicated: {call}")
    if game_text.count("no network transmission") != 1:
        raise PolicyError("English no-network disclosure is missing or ambiguous")
    if game_text.count("네트워크 전송") != 1:
        raise PolicyError("Korean no-network disclosure is missing or ambiguous")
    if game_text.count("release candidate ID") != 1:
        raise PolicyError("English build-correlation disclosure is missing or ambiguous")
    if game_text.count("릴리스 후보 ID") != 1:
        raise PolicyError("Korean build-correlation disclosure is missing or ambiguous")


def _audit_network_surface() -> int:
    violations: list[str] = []
    scanned = 0
    for directory in PRODUCTION_DIRECTORIES:
        for path in sorted((ROOT / directory).rglob("*.gd")):
            scanned += 1
            text = path.read_text(encoding="utf-8")
            match = NETWORK_API_PATTERN.search(text)
            if match:
                violations.append(f"{path.relative_to(ROOT)} uses {match.group(0)}")
            if re.search(r"https?://", text, re.IGNORECASE):
                violations.append(f"{path.relative_to(ROOT)} contains an HTTP URL")
    if violations:
        raise PolicyError("network surface violates the no-transmission policy: " + "; ".join(violations))
    return scanned


def main() -> int:
    try:
        datasets = _audit_policy_document(_load_policy())
        _audit_implementation(datasets)
        scanned = _audit_network_surface()
    except PolicyError as exc:
        print(f"DATA_POLICY_AUDIT_FAILED {exc}", file=sys.stderr)
        return 1
    print(
        "DATA_POLICY_AUDIT_OK "
        f"datasets={len(datasets)} source_files={scanned} network_apis=0 "
        "retention=runs60+replays12+sessions12 manual_exports=2 "
        "build_context=release_candidate_id locales=2 external_review=pending"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
