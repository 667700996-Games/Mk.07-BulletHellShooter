#!/usr/bin/env python3
"""Aggregate three canonical native runtime receipts into one candidate-bound gate."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys
import tempfile
from typing import Any, Dict, List, Mapping, Sequence, Tuple

import native_candidate_smoke as native
import release_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
MATRIX_NAME = "native-smoke-matrix.json"
MAX_JSON_BYTES = 1024 * 1024
RECEIPT_KEYS = {
    "architecture",
    "candidate_id",
    "candidate_manifest",
    "ci",
    "completed_at_utc",
    "extraction_safe",
    "godot_platform",
    "host_os",
    "package",
    "preset",
    "runtime",
    "runtime_log",
    "schema_version",
    "source_tree",
    "tool",
    "verification_kind",
}
DESCRIPTOR_KEYS = {"path", "sha256", "size"}
CI_KEYS = {"commit_sha", "provider", "repository", "run_attempt", "run_id", "workflow_ref"}
RUNTIME_KEYS = {"checks", "frame_budget_ms", "profile"}
CHECK_KEYS = {"metrics", "name", "result_line"}
SOURCE_TREE_KEYS = {"algorithm", "bytes", "files", "sha256"}
TOOL_KEYS = {"name", "sha256"}
MATRIX_KEYS = {
    "candidate_id",
    "candidate_manifest",
    "ci",
    "complete",
    "platforms",
    "schema_version",
    "source_tree",
    "tool",
    "verification_kind",
}
PLATFORM_KEYS = {"completed_at_utc", "host_os", "preset", "receipt", "runtime_log"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-fA-F]{40}$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


class EvidenceError(candidate.ReleaseError):
    """Native runtime evidence is incomplete, malformed, or no longer bound."""


def _exact(value: Mapping[str, Any], keys: set[str], context: str) -> None:
    actual = set(value)
    if actual != keys:
        raise EvidenceError(
            f"{context} fields differ; extra={sorted(actual - keys)}, missing={sorted(keys - actual)}"
        )


def _digest(value: Any, context: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise EvidenceError(f"{context} must be a lowercase SHA-256 digest")
    return value


def _positive(value: Any, context: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise EvidenceError(f"{context} must be a positive integer")
    return value


def _label(value: Any, context: str) -> str:
    if (
        not isinstance(value, str)
        or value != value.strip()
        or not value
        or len(value) > 512
        or any(ord(character) < 32 or ord(character) == 127 for character in value)
    ):
        raise EvidenceError(f"{context} is invalid")
    return value


def _timestamp(value: Any, context: str) -> str:
    value = _label(value, context)
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise EvidenceError(f"{context} must be UTC second precision") from exc
    return value


def _descriptor(value: Any, expected: Mapping[str, Any], context: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{context} must be an object")
    _exact(value, DESCRIPTOR_KEYS, context)
    if value != expected:
        raise EvidenceError(f"{context} differs from the candidate or evidence file")
    return dict(value)


def _ci(value: Any) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError("native receipt CI provenance must be an object")
    _exact(value, CI_KEYS, "native receipt CI provenance")
    provider = value.get("provider")
    optional_keys = ("commit_sha", "repository", "run_attempt", "run_id", "workflow_ref")
    if provider == "local":
        if any(value.get(key) is not None for key in optional_keys):
            raise EvidenceError("local native receipt contains invented CI provenance")
    elif provider == "github-actions":
        commit = value.get("commit_sha")
        repository = value.get("repository")
        if not isinstance(commit, str) or COMMIT_RE.fullmatch(commit) is None:
            raise EvidenceError("GitHub native receipt commit SHA is invalid")
        if not isinstance(repository, str) or REPOSITORY_RE.fullmatch(repository) is None:
            raise EvidenceError("GitHub native receipt repository is invalid")
        for key in ("run_attempt", "run_id"):
            raw = value.get(key)
            if not isinstance(raw, str) or not raw.isdigit() or int(raw) <= 0:
                raise EvidenceError(f"GitHub native receipt {key} is invalid")
        workflow_ref = _label(value.get("workflow_ref"), "GitHub native receipt workflow_ref")
        expected_prefix = f"{repository}/.github/workflows/release-candidate.yml@"
        if not workflow_ref.startswith(expected_prefix) or len(workflow_ref) == len(expected_prefix):
            raise EvidenceError("GitHub native receipt workflow_ref differs from the release workflow")
    else:
        raise EvidenceError(f"native receipt CI provider is unsupported: {provider!r}")
    return dict(value)


def _runtime(value: Any, candidate_id: str, godot_os: str, context: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise EvidenceError(f"{context} runtime result must be an object")
    _exact(value, RUNTIME_KEYS, f"{context} runtime result")
    if value.get("profile") != "certification" or value.get("frame_budget_ms") != native.FRAME_BUDGET_MS:
        raise EvidenceError(f"{context} runtime certification profile or frame budget differs")
    checks = value.get("checks")
    if not isinstance(checks, list) or len(checks) != 3:
        raise EvidenceError(f"{context} runtime certification must contain three checks")
    names = ["package-boot", "campaign-soak", "bullet-benchmark"]
    for check, expected_name in zip(checks, names):
        if not isinstance(check, dict):
            raise EvidenceError(f"{context} runtime check must be an object")
        _exact(check, CHECK_KEYS, f"{context} runtime check")
        if check.get("name") != expected_name or not isinstance(check.get("metrics"), dict):
            raise EvidenceError(f"{context} runtime check order or metrics differ")
        result_line = check.get("result_line")
        if not isinstance(result_line, str):
            raise EvidenceError(f"{context} runtime result line is invalid")
        metrics = check["metrics"]
        if expected_name == "package-boot":
            expected_line = (
                f"EXPORT_RUNTIME_SMOKE_OK candidate={candidate_id} "
                f"stages=3 characters=3 platform={godot_os}"
            )
            if result_line != expected_line or metrics != {"characters": 3, "stages": 3}:
                raise EvidenceError(f"{context} package boot result differs")
        elif expected_name == "campaign-soak":
            match = native.SOAK_RE.fullmatch(result_line)
            if match is None:
                raise EvidenceError(f"{context} soak result line is invalid")
            values = [int(item) for item in match.groups()]
            expected_metrics = {
                "runs": values[0],
                "cycles": values[1],
                "stages": values[2],
                "peak_bullets": values[3],
                "peak_enemies": values[4],
                "peak_hazards": values[5],
                "node_drift": values[6],
                "orphan_drift": values[7],
            }
            if metrics != expected_metrics or not (
                values[0:3] == [9, 3, 3]
                and values[3] <= 4000
                and values[4] <= 64
                and values[5] <= 48
                and values[6] <= 1
                and values[7] <= 2
            ):
                raise EvidenceError(f"{context} soak metrics exceed the certification contract")
        else:
            match = native.BENCHMARK_RE.fullmatch(result_line)
            if match is None:
                raise EvidenceError(f"{context} benchmark result line is invalid")
            bullets = int(match.group(1))
            frames = int(match.group(2))
            average_ms = float(match.group(3))
            expected_metrics = {
                "average_update_ms": average_ms,
                "bullets": bullets,
                "frames": frames,
            }
            if metrics != expected_metrics or not (
                bullets >= 3990 and frames == 300 and 0.0 < average_ms <= native.FRAME_BUDGET_MS
            ):
                raise EvidenceError(f"{context} benchmark metrics exceed the frame budget")
    return dict(value)


def _canonical_json(path: Path, context: str) -> Tuple[Dict[str, Any], bytes]:
    if path.is_symlink() or not path.is_file() or path.stat().st_size <= 0:
        raise EvidenceError(f"{context} is missing, empty, or unsafe: {path}")
    if path.stat().st_size > MAX_JSON_BYTES:
        raise EvidenceError(f"{context} exceeds the JSON safety budget")
    try:
        raw = path.read_bytes()
        value = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"cannot read {context}: {exc}") from exc
    if not isinstance(value, dict) or raw != candidate._canonical_json(value):
        raise EvidenceError(f"{context} must be a canonical JSON object")
    return value, raw


def _candidate_context(
    root: Path, metadata_path: Path, candidate_root: Path
) -> Tuple[Dict[str, Any], Dict[str, Any], Path, Dict[str, Mapping[str, Any]]]:
    metadata, _ = candidate.load_and_validate_config(root, metadata_path)
    candidate_dir = native._candidate_dir(candidate_root, metadata)
    manifest = candidate.verify_candidate(root, metadata_path, candidate_dir)
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        raise EvidenceError("candidate packages are invalid")
    by_preset = {
        str(item["preset"]): item
        for item in packages
        if isinstance(item, dict) and isinstance(item.get("preset"), str)
    }
    if set(by_preset) != set(native.PLATFORM_CONTRACTS):
        raise EvidenceError("candidate native preset set is incomplete")
    return metadata, manifest, candidate_dir, by_preset


def _matrix_value(
    root: Path,
    metadata_path: Path,
    candidate_root: Path,
    receipt_root: Path,
    log_root: Path,
) -> Dict[str, Any]:
    metadata, manifest, candidate_dir, packages = _candidate_context(
        root, metadata_path, candidate_root
    )
    presets = metadata.get("presets")
    if not isinstance(presets, list):
        raise EvidenceError("release metadata presets are invalid")
    slugs = {
        str(item["name"]): str(item["slug"])
        for item in presets
        if isinstance(item, dict) and "name" in item and "slug" in item
    }
    expected_receipts = {f"{slug}.json" for slug in slugs.values()}
    expected_logs = {f"{slug}.log" for slug in slugs.values()}
    if not receipt_root.is_dir() or receipt_root.is_symlink():
        raise EvidenceError(f"native receipt root is missing or unsafe: {receipt_root}")
    if not log_root.is_dir() or log_root.is_symlink():
        raise EvidenceError(f"native log root is missing or unsafe: {log_root}")
    actual_receipts = {path.name for path in receipt_root.iterdir()}
    actual_logs = {path.name for path in log_root.iterdir()}
    if actual_receipts != expected_receipts:
        raise EvidenceError("native receipt file set is incomplete or contains extras")
    if actual_logs != expected_logs:
        raise EvidenceError("native runtime log file set is incomplete or contains extras")

    manifest_path = candidate_dir / candidate.MANIFEST_NAME
    manifest_descriptor = {
        "path": candidate.MANIFEST_NAME,
        "sha256": candidate._sha256_file(manifest_path),
        "size": manifest_path.stat().st_size,
    }
    source_hashes = manifest.get("source_config_sha256")
    if not isinstance(source_hashes, dict):
        raise EvidenceError("candidate source configuration hashes are invalid")
    smoke_tool_hash = _digest(source_hashes.get("native_candidate_smoke.py"), "native smoke tool")
    matrix_tool_hash = _digest(source_hashes.get("native_smoke_evidence.py"), "native matrix tool")
    platform_records: List[Dict[str, Any]] = []
    shared_ci: Dict[str, Any] | None = None
    for preset in sorted(slugs):
        slug = slugs[preset]
        receipt_path = receipt_root / f"{slug}.json"
        receipt, receipt_raw = _canonical_json(receipt_path, f"{preset} native receipt")
        _exact(receipt, RECEIPT_KEYS, f"{preset} native receipt")
        if receipt.get("schema_version") != native.RECEIPT_SCHEMA_VERSION:
            raise EvidenceError(f"{preset} native receipt schema differs")
        contract = native.PLATFORM_CONTRACTS[preset]
        metadata_preset = native._preset_by_name(metadata, preset)
        identity = {
            "architecture": metadata_preset["architecture"],
            "candidate_id": manifest["candidate_id"],
            "extraction_safe": True,
            "godot_platform": contract["godot_os"],
            "host_os": contract["host"],
            "preset": preset,
            "schema_version": native.RECEIPT_SCHEMA_VERSION,
            "source_tree": manifest["source_tree"],
            "verification_kind": "unsigned-package-native-certification",
        }
        for key, expected in identity.items():
            if receipt.get(key) != expected:
                raise EvidenceError(f"{preset} native receipt {key} differs")
        _descriptor(receipt.get("candidate_manifest"), manifest_descriptor, f"{preset} manifest")
        package = packages[preset]
        package_descriptor = {
            "path": package["path"], "sha256": package["sha256"], "size": package["size"]
        }
        _descriptor(receipt.get("package"), package_descriptor, f"{preset} package")
        tool = receipt.get("tool")
        if not isinstance(tool, dict):
            raise EvidenceError(f"{preset} native smoke tool must be an object")
        _exact(tool, TOOL_KEYS, f"{preset} native smoke tool")
        if tool != {"name": "native_candidate_smoke.py", "sha256": smoke_tool_hash}:
            raise EvidenceError(f"{preset} native smoke tool differs")
        runtime = _runtime(
            receipt.get("runtime"), str(manifest["candidate_id"]), str(contract["godot_os"]), preset
        )
        timestamp = _timestamp(receipt.get("completed_at_utc"), f"{preset} completion time")
        ci = _ci(receipt.get("ci"))
        if shared_ci is None:
            shared_ci = ci
        elif ci != shared_ci:
            raise EvidenceError("native receipts do not share one CI provenance")
        log_path = log_root / f"{slug}.log"
        if log_path.is_symlink() or not log_path.is_file() or log_path.stat().st_size <= 0:
            raise EvidenceError(f"{preset} native runtime log is missing, empty, or unsafe")
        if log_path.stat().st_size > native.MAX_LOG_BYTES + 64:
            raise EvidenceError(f"{preset} native runtime log exceeds the safety budget")
        log_descriptor = {
            "path": log_path.name,
            "sha256": candidate._sha256_file(log_path),
            "size": log_path.stat().st_size,
        }
        _descriptor(receipt.get("runtime_log"), log_descriptor, f"{preset} runtime log")
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        for check in runtime["checks"]:
            if str(check["result_line"]) not in log_text:
                raise EvidenceError(f"{preset} runtime log is missing {check['name']}")
        platform_records.append(
            {
                "completed_at_utc": timestamp,
                "host_os": contract["host"],
                "preset": preset,
                "receipt": {
                    "path": receipt_path.name,
                    "sha256": candidate._sha256_bytes(receipt_raw),
                    "size": len(receipt_raw),
                },
                "runtime_log": log_descriptor,
            }
        )
    if shared_ci is None:
        raise EvidenceError("native matrix contains no CI provenance")
    if shared_ci.get("provider") != "github-actions":
        raise EvidenceError("complete native matrix requires GitHub Actions provenance")
    return {
        "candidate_id": manifest["candidate_id"],
        "candidate_manifest": manifest_descriptor,
        "ci": shared_ci,
        "complete": True,
        "platforms": platform_records,
        "schema_version": 1,
        "source_tree": manifest["source_tree"],
        "tool": {"name": "native_smoke_evidence.py", "sha256": matrix_tool_hash},
        "verification_kind": "complete-unsigned-native-smoke-matrix",
    }


def record_matrix(
    root: Path,
    metadata_path: Path,
    candidate_root: Path,
    receipt_root: Path,
    log_root: Path,
    matrix_path: Path,
) -> Dict[str, Any]:
    value = _matrix_value(root, metadata_path, candidate_root, receipt_root, log_root)
    if matrix_path.is_symlink() or (matrix_path.exists() and not matrix_path.is_file()):
        raise EvidenceError(f"native matrix output is unsafe: {matrix_path}")
    candidate._atomic_write(matrix_path, candidate._canonical_json(value))
    return verify_matrix(root, metadata_path, candidate_root, receipt_root, log_root, matrix_path)


def verify_matrix(
    root: Path,
    metadata_path: Path,
    candidate_root: Path,
    receipt_root: Path,
    log_root: Path,
    matrix_path: Path,
) -> Dict[str, Any]:
    actual, _ = _canonical_json(matrix_path, "native smoke matrix")
    _exact(actual, MATRIX_KEYS, "native smoke matrix")
    platforms = actual.get("platforms")
    if not isinstance(platforms, list):
        raise EvidenceError("native smoke matrix platforms must be an array")
    for item in platforms:
        if not isinstance(item, dict):
            raise EvidenceError("native smoke matrix platform entry must be an object")
        _exact(item, PLATFORM_KEYS, "native smoke matrix platform")
    expected = _matrix_value(root, metadata_path, candidate_root, receipt_root, log_root)
    if actual != expected:
        raise EvidenceError("native smoke matrix differs from its candidate, receipts, or logs")
    return actual


def run_self_test(root: Path, metadata_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="psychic_vector_native_evidence.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        metadata, presets = candidate.load_and_validate_config(fixture_root, fixture_metadata)
        build_root = base / "build"
        candidate._create_fake_exports(build_root, presets)
        candidate_root = base / "dist"
        candidate_dir = candidate.package_candidate(
            fixture_root, fixture_metadata, build_root, candidate_root
        ).parent
        manifest = candidate.verify_candidate(fixture_root, fixture_metadata, candidate_dir)
        manifest_path = candidate_dir / candidate.MANIFEST_NAME
        manifest_entry = {
            "path": candidate.MANIFEST_NAME,
            "sha256": candidate._sha256_file(manifest_path),
            "size": manifest_path.stat().st_size,
        }
        receipt_root = base / "evidence" / "receipts"
        log_root = base / "evidence" / "logs"
        receipt_root.mkdir(parents=True)
        log_root.mkdir(parents=True)
        ci_context = {
            "commit_sha": "1" * 40,
            "provider": "github-actions",
            "repository": "fixture/psychic-vector",
            "run_attempt": "1",
            "run_id": "42",
            "workflow_ref": "fixture/psychic-vector/.github/workflows/release-candidate.yml@refs/heads/main",
        }
        slugs = {str(item["name"]): str(item["slug"]) for item in metadata["presets"]}
        for preset in native.PLATFORM_CONTRACTS:
            contract = native.PLATFORM_CONTRACTS[preset]
            runtime = native.fixture_certification_runtime(
                str(manifest["candidate_id"]), str(contract["godot_os"])
            )
            log_path = log_root / f"{slugs[preset]}.log"
            result_lines = "\n".join(str(check["result_line"]) for check in runtime["checks"])
            log_path.write_text(f"fixture\n{result_lines}\n", encoding="utf-8")
            log_entry = {
                "path": log_path.name,
                "sha256": candidate._sha256_file(log_path),
                "size": log_path.stat().st_size,
            }
            receipt = native.build_receipt(
                metadata,
                manifest,
                preset,
                str(contract["host"]),
                runtime,
                manifest_entry,
                log_entry,
                "2026-01-02T03:04:05Z",
                ci_context,
            )
            (receipt_root / f"{slugs[preset]}.json").write_bytes(
                candidate._canonical_json(receipt)
            )
        matrix_path = base / "evidence" / MATRIX_NAME
        record_matrix(
            fixture_root,
            fixture_metadata,
            candidate_root,
            receipt_root,
            log_root,
            matrix_path,
        )

        original_receipts = {
            path: path.read_bytes() for path in sorted(receipt_root.glob("*.json"))
        }

        def expect_matrix_failure(expected_message: str) -> None:
            try:
                verify_matrix(
                    fixture_root,
                    fixture_metadata,
                    candidate_root,
                    receipt_root,
                    log_root,
                    matrix_path,
                )
            except EvidenceError as exc:
                if expected_message not in str(exc):
                    raise EvidenceError(
                        f"self-test rejected matrix evidence for the wrong reason: {exc}"
                    ) from exc
            else:
                raise EvidenceError("self-test accepted invalid native matrix evidence")

        for receipt_path, raw in original_receipts.items():
            local_receipt = json.loads(raw)
            local_receipt["ci"] = {
                "commit_sha": None,
                "provider": "local",
                "repository": None,
                "run_attempt": None,
                "run_id": None,
                "workflow_ref": None,
            }
            receipt_path.write_bytes(candidate._canonical_json(local_receipt))
        expect_matrix_failure("requires GitHub Actions provenance")
        for receipt_path, raw in original_receipts.items():
            receipt_path.write_bytes(raw)

        workflow_receipt_path = receipt_root / "windows-x86_64.json"
        workflow_receipt = json.loads(original_receipts[workflow_receipt_path])
        workflow_receipt["ci"]["workflow_ref"] = (
            "fixture/psychic-vector/.github/workflows/other.yml@refs/heads/main"
        )
        workflow_receipt_path.write_bytes(candidate._canonical_json(workflow_receipt))
        expect_matrix_failure("workflow_ref differs from the release workflow")
        workflow_receipt_path.write_bytes(original_receipts[workflow_receipt_path])

        linux_receipt = receipt_root / "linux-x86_64.json"
        original_linux_receipt = linux_receipt.read_bytes()
        mixed_ci_receipt = json.loads(original_linux_receipt)
        mixed_ci_receipt["ci"]["run_id"] = "43"
        linux_receipt.write_bytes(candidate._canonical_json(mixed_ci_receipt))
        expect_matrix_failure("do not share one CI provenance")
        linux_receipt.write_bytes(original_linux_receipt)

        slow_receipt = json.loads(original_linux_receipt)
        benchmark_check = slow_receipt["runtime"]["checks"][2]
        benchmark_check["metrics"]["average_update_ms"] = 99.0
        benchmark_check["result_line"] = (
            "BULLET_BENCHMARK_OK bullets=3993 frames=300 average_update_ms=99.000"
        )
        linux_receipt.write_bytes(candidate._canonical_json(slow_receipt))
        expect_matrix_failure("benchmark metrics exceed")
        linux_receipt.write_bytes(original_linux_receipt)

        victim_log = log_root / "macos-universal.log"
        original_log = victim_log.read_bytes()
        victim_log.write_bytes(original_log + b"tamper")
        try:
            verify_matrix(
                fixture_root,
                fixture_metadata,
                candidate_root,
                receipt_root,
                log_root,
                matrix_path,
            )
        except EvidenceError as exc:
            if "runtime log" not in str(exc):
                raise EvidenceError(f"self-test rejected log tamper for the wrong reason: {exc}") from exc
        else:
            raise EvidenceError("self-test accepted a modified runtime log")
        victim_log.write_bytes(original_log)
        victim_receipt = receipt_root / "windows-x86_64.json"
        hidden_receipt = base / victim_receipt.name
        victim_receipt.rename(hidden_receipt)
        try:
            verify_matrix(
                fixture_root,
                fixture_metadata,
                candidate_root,
                receipt_root,
                log_root,
                matrix_path,
            )
        except EvidenceError as exc:
            if "receipt file set" not in str(exc):
                raise EvidenceError(f"self-test rejected missing receipt for the wrong reason: {exc}") from exc
        else:
            raise EvidenceError("self-test accepted an incomplete platform matrix")
        hidden_receipt.rename(victim_receipt)
        verify_matrix(
            fixture_root,
            fixture_metadata,
            candidate_root,
            receipt_root,
            log_root,
            matrix_path,
        )
    print(
        "NATIVE_SMOKE_EVIDENCE_TEST_OK platforms=3 candidate=bound packages=bound "
        "logs=bound ci=consistent local=blocked workflow=bound mixed_ci=blocked frame_budget=blocked "
        "missing=blocked tamper=blocked matrix=complete"
    )


def _resolve(root: Path, value: Path) -> Path:
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("record", "verify", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--candidate-root", type=Path, default=Path("dist"))
    parser.add_argument("--receipt-root", type=Path, default=Path("native-evidence/receipts"))
    parser.add_argument("--log-root", type=Path, default=Path("native-evidence/logs"))
    parser.add_argument("--matrix-receipt", type=Path, default=Path("native-evidence") / MATRIX_NAME)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = _resolve(root, args.metadata)
    candidate_root = _resolve(root, args.candidate_root)
    receipt_root = _resolve(root, args.receipt_root)
    log_root = _resolve(root, args.log_root)
    matrix_path = _resolve(root, args.matrix_receipt)
    try:
        if args.command == "self-test":
            run_self_test(root, metadata_path)
        elif args.command == "record":
            value = record_matrix(
                root, metadata_path, candidate_root, receipt_root, log_root, matrix_path
            )
            print(
                f"NATIVE_SMOKE_MATRIX_OK candidate={value['candidate_id']} "
                f"platforms={len(value['platforms'])} ci={value['ci']['provider']} complete=true"
            )
        else:
            value = verify_matrix(
                root, metadata_path, candidate_root, receipt_root, log_root, matrix_path
            )
            print(
                f"NATIVE_SMOKE_MATRIX_VERIFY_OK candidate={value['candidate_id']} "
                f"platforms={len(value['platforms'])} ci={value['ci']['provider']} complete=true"
            )
    except (OSError, ValueError, EvidenceError, native.NativeSmokeError, candidate.ReleaseError) as exc:
        print(f"NATIVE_SMOKE_EVIDENCE_FAILED {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
