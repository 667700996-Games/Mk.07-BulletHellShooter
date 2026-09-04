#!/usr/bin/env python3
"""Create and verify an offline, release-candidate-bound crash support bundle.

The tool never launches the game, captures a process, or uploads data. Collection
is an explicit support action over files supplied by the operator. Text artifacts
are normalized and common user-path/email/host fields are redacted; native binary
dumps remain sensitive and require a separate acknowledgement flag.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
from typing import Any, Dict, Mapping, Sequence

import release_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
TOOL_NAME = "crash_support_bundle.py"
MANIFEST_NAME = "support-manifest.json"
SCHEMA_VERSION = 1
MAX_RUNTIME_LOG_BYTES = 16 * 1024 * 1024
MAX_DIAGNOSTICS_BYTES = 1024 * 1024
MAX_TEXT_REPORT_BYTES = 32 * 1024 * 1024
MAX_BINARY_REPORT_BYTES = 256 * 1024 * 1024
CASE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
UTC_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
EMAIL_RE = re.compile(r"(?i)(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
UNIX_HOME_RE = re.compile(r"/(Users|home)/[^/\s:\r\n]+")
WINDOWS_HOME_RE = re.compile(
    r"(?i)([A-Z]:[\\/](?:Users|Documents and Settings)[\\/])[^\\/\s:\r\n]+"
)
IDENTITY_FIELD_RE = re.compile(
    r"(?im)^(\s*(?:user(?:name)?|account|host(?:name)?|computer_name|machine_name)\s*[:=]\s*)[^\r\n]+$"
)
DIAGNOSTICS_KEYS = {
    "schema_version",
    "generated_at",
    "disclosure",
    "network_transmission",
    "identity_fields_collected",
    "build_identity",
    "retention_limit",
    "prior_session_unclean",
    "recovered_from_backup",
    "journal_reset_after_corruption",
    "history",
    "current_session",
}
NATIVE_REPORTS = {
    "Windows Desktop": {
        ".dmp": "binary",
        ".txt": "text",
        ".log": "text",
    },
    "macOS": {
        ".ips": "text",
        ".crash": "text",
        ".txt": "text",
        ".core": "binary",
    },
    "Linux": {
        ".core": "binary",
        ".dump": "binary",
        ".txt": "text",
        ".log": "text",
    },
}
TOP_LEVEL_KEYS = {
    "artifacts",
    "candidate_id",
    "candidate_manifest",
    "case_id",
    "collected_at_utc",
    "package",
    "preset",
    "privacy",
    "schema_version",
    "source_tree",
    "tool",
}
ARTIFACT_KEYS = {
    "candidate_marker_present",
    "content_kind",
    "path",
    "review_required_before_sharing",
    "role",
    "sanitized",
    "sha256",
    "size",
}
DESCRIPTOR_KEYS = {"path", "sha256", "size"}
PRIVACY_CONTRACT = {
    "automatic_collection": False,
    "automatic_upload": False,
    "network_transmission": False,
    "operator_supplied_files_only": True,
    "raw_binary_native_reports_may_contain_sensitive_data": True,
}


class CrashSupportError(candidate.ReleaseError):
    """Crash support input or bundle is unsafe, malformed, or unbound."""


def _exact(value: Mapping[str, Any], expected: set[str], context: str) -> None:
    actual = set(value)
    if actual != expected:
        raise CrashSupportError(
            f"{context} fields differ; extra={sorted(actual - expected)}, "
            f"missing={sorted(expected - actual)}"
        )


def _timestamp(value: str | None) -> str:
    if value is None:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if UTC_RE.fullmatch(value) is None:
        raise CrashSupportError("collection timestamp must use UTC second precision")
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise CrashSupportError("collection timestamp is not a real UTC date") from exc
    return value


def _case_id(value: str) -> str:
    if CASE_ID_RE.fullmatch(value) is None:
        raise CrashSupportError(
            "case ID must be 1-64 filename-safe ASCII letters, digits, dots, dashes, or underscores"
        )
    return value


def _regular_input(path: Path, maximum: int, context: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise CrashSupportError(f"{context} must be a regular non-symlink file: {path}")
    size = path.stat().st_size
    if size <= 0 or size > maximum:
        raise CrashSupportError(f"{context} size must be between 1 and {maximum} bytes")
    return path.resolve()


def _sanitize_text(raw: bytes) -> bytes:
    text = raw.decode("utf-8", errors="replace").replace("\x00", "")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = EMAIL_RE.sub("<redacted-email>", text)
    text = UNIX_HOME_RE.sub(lambda match: f"/{match.group(1)}/<redacted-user>", text)
    text = WINDOWS_HOME_RE.sub(lambda match: f"{match.group(1)}<redacted-user>", text)
    text = IDENTITY_FIELD_RE.sub(lambda match: f"{match.group(1)}<redacted>", text)
    if not text.endswith("\n"):
        text += "\n"
    return text.encode("utf-8")


def _descriptor(path: Path) -> Dict[str, Any]:
    return {
        "path": path.name,
        "sha256": candidate._sha256_file(path),
        "size": path.stat().st_size,
    }


def _artifact_descriptor(
    path: Path,
    role: str,
    content_kind: str,
    sanitized: bool,
    candidate_id: str,
) -> Dict[str, Any]:
    marker_present = False
    if content_kind in ("text", "json"):
        marker_present = candidate_id.encode("utf-8") in path.read_bytes()
    return {
        **_descriptor(path),
        "candidate_marker_present": marker_present,
        "content_kind": content_kind,
        "review_required_before_sharing": True,
        "role": role,
        "sanitized": sanitized,
    }


def _atomic_copy(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", dir=destination.parent
    )
    temporary = Path(temporary_name)
    try:
        with source.open("rb") as input_handle, os.fdopen(descriptor, "wb") as output_handle:
            shutil.copyfileobj(input_handle, output_handle, length=1024 * 1024)
            output_handle.flush()
            os.fsync(output_handle.fileno())
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def _candidate_context(
    root: Path, metadata_path: Path, candidate_root: Path, preset_name: str
) -> tuple[Dict[str, Any], Dict[str, Any], Path, Dict[str, Any]]:
    metadata, presets = candidate.load_and_validate_config(root, metadata_path)
    preset_matches = [item for item in presets if item.get("name") == preset_name]
    if len(preset_matches) != 1:
        raise CrashSupportError(f"unsupported release preset: {preset_name!r}")
    candidate_dir = candidate_root / candidate._candidate_id(metadata)
    manifest = candidate.verify_candidate(root, metadata_path, candidate_dir)
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        raise CrashSupportError("candidate packages are malformed")
    package_matches = [
        item for item in packages if isinstance(item, dict) and item.get("preset") == preset_name
    ]
    if len(package_matches) != 1:
        raise CrashSupportError(f"candidate package is missing for preset: {preset_name}")
    source_hashes = manifest.get("source_config_sha256")
    tool_path = root / "tools" / TOOL_NAME
    if (
        not isinstance(source_hashes, dict)
        or source_hashes.get(TOOL_NAME) != candidate._sha256_file(tool_path)
    ):
        raise CrashSupportError("candidate does not bind this crash support tool")
    return metadata, manifest, candidate_dir, dict(package_matches[0])


def _validated_diagnostics(path: Path, candidate_id: str) -> bytes:
    source = _regular_input(path, MAX_DIAGNOSTICS_BYTES, "diagnostics export")
    try:
        value = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CrashSupportError(f"diagnostics export is not valid UTF-8 JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise CrashSupportError("diagnostics export root must be an object")
    _exact(value, DIAGNOSTICS_KEYS, "diagnostics export")
    if value.get("network_transmission") is not False or value.get("identity_fields_collected") is not False:
        raise CrashSupportError("diagnostics export violates the offline identity-free contract")
    build_identity = value.get("build_identity")
    if not isinstance(build_identity, dict) or build_identity.get("candidate_id") != candidate_id:
        raise CrashSupportError("diagnostics export belongs to a different release candidate")
    return candidate._canonical_json(value)


def collect_bundle(
    root: Path,
    metadata_path: Path,
    candidate_root: Path,
    output_root: Path,
    case_id: str,
    preset_name: str,
    runtime_log: Path,
    diagnostics: Path | None,
    native_report: Path | None,
    include_sensitive_native_report: bool,
    collected_at_utc: str | None = None,
) -> Path:
    safe_case_id = _case_id(case_id)
    metadata, manifest, candidate_dir, package = _candidate_context(
        root, metadata_path, candidate_root, preset_name
    )
    candidate_id = candidate._candidate_id(metadata)
    runtime_source = _regular_input(runtime_log, MAX_RUNTIME_LOG_BYTES, "runtime log")
    native_source: Path | None = None
    native_kind = ""
    native_extension = ""
    if native_report is not None:
        if not include_sensitive_native_report:
            raise CrashSupportError(
                "native reports require --include-sensitive-native-report acknowledgement"
            )
        native_extension = native_report.suffix.lower()
        native_kind = NATIVE_REPORTS[preset_name].get(native_extension, "")
        if not native_kind:
            raise CrashSupportError(
                f"unsupported {preset_name} native report extension: {native_extension or '<none>'}"
            )
        maximum = MAX_TEXT_REPORT_BYTES if native_kind == "text" else MAX_BINARY_REPORT_BYTES
        native_source = _regular_input(native_report, maximum, "native report")

    candidate_output_root = output_root / candidate_id
    if candidate_output_root.exists() and (
        candidate_output_root.is_symlink() or not candidate_output_root.is_dir()
    ):
        raise CrashSupportError(f"support output root is unsafe: {candidate_output_root}")
    candidate_output_root.mkdir(parents=True, exist_ok=True)
    bundle_path = candidate_output_root / safe_case_id
    if bundle_path.exists() or bundle_path.is_symlink():
        raise CrashSupportError(f"support case already exists; refusing overwrite: {bundle_path}")
    staging = Path(tempfile.mkdtemp(prefix=f".{safe_case_id}.pending.", dir=candidate_output_root))
    try:
        artifacts: list[Dict[str, Any]] = []
        runtime_output = staging / "runtime.log"
        candidate._atomic_write(runtime_output, _sanitize_text(runtime_source.read_bytes()))
        artifacts.append(
            _artifact_descriptor(runtime_output, "runtime_log", "text", True, candidate_id)
        )

        if diagnostics is not None:
            diagnostics_output = staging / "diagnostics.json"
            candidate._atomic_write(
                diagnostics_output, _validated_diagnostics(diagnostics, candidate_id)
            )
            artifacts.append(
                _artifact_descriptor(
                    diagnostics_output, "diagnostics_export", "json", True, candidate_id
                )
            )

        if native_source is not None:
            native_output = staging / f"native-crash{native_extension}"
            if native_kind == "text":
                candidate._atomic_write(native_output, _sanitize_text(native_source.read_bytes()))
                sanitized = True
            else:
                _atomic_copy(native_source, native_output)
                sanitized = False
            artifacts.append(
                _artifact_descriptor(
                    native_output, "native_report", native_kind, sanitized, candidate_id
                )
            )

        manifest_path = candidate_dir / candidate.MANIFEST_NAME
        support_manifest = {
            "artifacts": artifacts,
            "candidate_id": candidate_id,
            "candidate_manifest": _descriptor(manifest_path),
            "case_id": safe_case_id,
            "collected_at_utc": _timestamp(collected_at_utc),
            "package": {
                "path": package["path"],
                "sha256": package["sha256"],
                "size": package["size"],
            },
            "preset": preset_name,
            "privacy": dict(PRIVACY_CONTRACT),
            "schema_version": SCHEMA_VERSION,
            "source_tree": manifest["source_tree"],
            "tool": {
                "name": TOOL_NAME,
                "sha256": manifest["source_config_sha256"][TOOL_NAME],
            },
        }
        candidate._atomic_write(staging / MANIFEST_NAME, candidate._canonical_json(support_manifest))
        os.replace(staging, bundle_path)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    verify_bundle(root, metadata_path, candidate_root, bundle_path)
    return bundle_path


def _verify_descriptor(
    value: Any, expected: Mapping[str, Any], context: str
) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise CrashSupportError(f"{context} must be an object")
    _exact(value, DESCRIPTOR_KEYS, context)
    if value != expected:
        raise CrashSupportError(f"{context} differs from its candidate-bound file")
    return dict(value)


def _verify_artifact(
    bundle_path: Path, value: Any, candidate_id: str, seen_roles: set[str]
) -> str:
    if not isinstance(value, dict):
        raise CrashSupportError("support artifact must be an object")
    _exact(value, ARTIFACT_KEYS, "support artifact")
    role = value.get("role")
    contracts = {
        "runtime_log": ({"text"}, MAX_RUNTIME_LOG_BYTES, True),
        "diagnostics_export": ({"json"}, MAX_DIAGNOSTICS_BYTES, True),
        "native_report": ({"text", "binary"}, MAX_BINARY_REPORT_BYTES, None),
    }
    if role not in contracts or role in seen_roles:
        raise CrashSupportError(f"support artifact role is unknown or duplicated: {role!r}")
    seen_roles.add(str(role))
    content_kinds, maximum, expected_sanitized = contracts[str(role)]
    content_kind = value.get("content_kind")
    if content_kind not in content_kinds:
        raise CrashSupportError(f"{role} content kind is invalid")
    sanitized = value.get("sanitized")
    if not isinstance(sanitized, bool) or (
        expected_sanitized is not None and sanitized is not expected_sanitized
    ):
        raise CrashSupportError(f"{role} sanitization marker is invalid")
    if role == "native_report" and sanitized is not (content_kind == "text"):
        raise CrashSupportError("native report sanitization differs from its content kind")
    if value.get("review_required_before_sharing") is not True:
        raise CrashSupportError(f"{role} must retain the share-review warning")
    name = value.get("path")
    if not isinstance(name, str) or PurePosixPath(name).name != name or name == MANIFEST_NAME:
        raise CrashSupportError(f"support artifact path is unsafe: {name!r}")
    path = bundle_path / name
    if path.is_symlink() or not path.is_file():
        raise CrashSupportError(f"support artifact is missing or unsafe: {name}")
    size = path.stat().st_size
    if not isinstance(value.get("size"), int) or size <= 0 or size > maximum:
        raise CrashSupportError(f"support artifact size is invalid: {name}")
    digest = value.get("sha256")
    if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
        raise CrashSupportError(f"support artifact digest is invalid: {name}")
    if value["size"] != size or digest != candidate._sha256_file(path):
        raise CrashSupportError(f"support artifact checksum or size differs: {name}")
    marker = candidate_id.encode("utf-8") in path.read_bytes() if content_kind != "binary" else False
    if value.get("candidate_marker_present") is not marker:
        raise CrashSupportError(f"support artifact candidate marker is inaccurate: {name}")
    if role == "diagnostics_export":
        _validated_diagnostics(path, candidate_id)
    return name


def verify_bundle(
    root: Path, metadata_path: Path, candidate_root: Path, bundle_path: Path
) -> Dict[str, Any]:
    if bundle_path.is_symlink() or not bundle_path.is_dir():
        raise CrashSupportError(f"support bundle is missing or unsafe: {bundle_path}")
    manifest_path = bundle_path / MANIFEST_NAME
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise CrashSupportError("support manifest is missing or unsafe")
    try:
        value = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CrashSupportError(f"support manifest is invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise CrashSupportError("support manifest root must be an object")
    if manifest_path.read_bytes() != candidate._canonical_json(value):
        raise CrashSupportError("support manifest is not canonical JSON")
    _exact(value, TOP_LEVEL_KEYS, "support manifest")
    if value.get("schema_version") != SCHEMA_VERSION:
        raise CrashSupportError("support manifest schema version differs")
    raw_case_id = value.get("case_id")
    if not isinstance(raw_case_id, str):
        raise CrashSupportError("support case ID must be a string")
    case_id = _case_id(raw_case_id)
    if bundle_path.name != case_id:
        raise CrashSupportError("support directory does not match its case ID")
    collected = value.get("collected_at_utc")
    if not isinstance(collected, str) or _timestamp(collected) != collected:
        raise CrashSupportError("support collection timestamp is invalid")
    preset_name = value.get("preset")
    if not isinstance(preset_name, str):
        raise CrashSupportError("support preset is invalid")
    metadata, release_manifest, candidate_dir, package = _candidate_context(
        root, metadata_path, candidate_root, preset_name
    )
    candidate_id = candidate._candidate_id(metadata)
    if value.get("candidate_id") != candidate_id or value.get("source_tree") != release_manifest.get("source_tree"):
        raise CrashSupportError("support bundle belongs to a different source candidate")
    _verify_descriptor(
        value.get("candidate_manifest"),
        _descriptor(candidate_dir / candidate.MANIFEST_NAME),
        "candidate manifest descriptor",
    )
    expected_package = {
        "path": package["path"],
        "sha256": package["sha256"],
        "size": package["size"],
    }
    _verify_descriptor(value.get("package"), expected_package, "candidate package descriptor")
    if value.get("privacy") != PRIVACY_CONTRACT:
        raise CrashSupportError("support privacy contract differs")
    expected_tool = {
        "name": TOOL_NAME,
        "sha256": release_manifest["source_config_sha256"][TOOL_NAME],
    }
    if value.get("tool") != expected_tool:
        raise CrashSupportError("support tool binding differs")
    artifacts = value.get("artifacts")
    if not isinstance(artifacts, list) or not 1 <= len(artifacts) <= 3:
        raise CrashSupportError("support artifact list must contain one to three files")
    roles = [item.get("role") if isinstance(item, dict) else None for item in artifacts]
    expected_order = [role for role in ("runtime_log", "diagnostics_export", "native_report") if role in roles]
    if roles != expected_order or roles[0] != "runtime_log":
        raise CrashSupportError("support artifact roles are missing or out of canonical order")
    seen_roles: set[str] = set()
    expected_entries = {MANIFEST_NAME}
    for artifact in artifacts:
        expected_entries.add(_verify_artifact(bundle_path, artifact, candidate_id, seen_roles))
    actual_entries = {path.name for path in bundle_path.iterdir()}
    if actual_entries != expected_entries:
        raise CrashSupportError(
            f"support directory contents differ; extra={sorted(actual_entries - expected_entries)}, "
            f"missing={sorted(expected_entries - actual_entries)}"
        )
    return value


def _fixture_diagnostics(candidate_id: str) -> Dict[str, Any]:
    return {
        "build_identity": {"candidate_id": candidate_id},
        "current_session": {},
        "disclosure": "LOCAL MANUAL EXPORT. This is not a native crash dump.",
        "generated_at": 1735689600,
        "history": [],
        "identity_fields_collected": False,
        "journal_reset_after_corruption": False,
        "network_transmission": False,
        "prior_session_unclean": True,
        "recovered_from_backup": False,
        "retention_limit": 12,
        "schema_version": 2,
    }


def run_self_test(root: Path, metadata_path: Path) -> None:
    _, presets = candidate.load_and_validate_config(root, metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_crash_support.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        fixture_build = base / "build"
        candidate._create_fake_exports(fixture_build, presets)
        fixture_dist = base / "dist"
        candidate.package_candidate(fixture_root, fixture_metadata, fixture_build, fixture_dist)
        fixture_meta = candidate._load_json(fixture_metadata)
        fixture_id = candidate._candidate_id(fixture_meta)
        runtime_log = base / "input-runtime.log"
        runtime_log.write_text(
            "Godot Engine\n/Users/alice/project/game.gd\n"
            "C:\\Users\\Bob\\save.dat\ncontact=pilot@example.com\n"
            f"PSYCHIC_VECTOR_SESSION event=begin candidate={fixture_id} sequence=4\n",
            encoding="utf-8",
        )
        diagnostics = base / "input-diagnostics.json"
        diagnostics.write_bytes(candidate._canonical_json(_fixture_diagnostics(fixture_id)))
        native_report = base / "input.ips"
        native_report.write_text(
            "username: alice\nPath: /Users/alice/Library/Application Support/game\n",
            encoding="utf-8",
        )
        first = collect_bundle(
            fixture_root,
            fixture_metadata,
            fixture_dist,
            base / "support-a",
            "CASE-0001",
            "macOS",
            runtime_log,
            diagnostics,
            native_report,
            True,
            "2025-01-01T00:00:00Z",
        )
        second = collect_bundle(
            fixture_root,
            fixture_metadata,
            fixture_dist,
            base / "support-b",
            "CASE-0001",
            "macOS",
            runtime_log,
            diagnostics,
            native_report,
            True,
            "2025-01-01T00:00:00Z",
        )
        first_files = sorted(path.name for path in first.iterdir())
        if first_files != sorted(path.name for path in second.iterdir()):
            raise CrashSupportError("self-test support file set is not deterministic")
        for name in first_files:
            if (first / name).read_bytes() != (second / name).read_bytes():
                raise CrashSupportError(f"self-test support output is not deterministic: {name}")
        combined_text = (first / "runtime.log").read_text(encoding="utf-8") + (
            first / "native-crash.ips"
        ).read_text(encoding="utf-8")
        for secret in ("alice", "Bob", "pilot@example.com"):
            if secret in combined_text:
                raise CrashSupportError("self-test text redaction retained an identity fixture")
        manifest = verify_bundle(fixture_root, fixture_metadata, fixture_dist, first)
        if not manifest["artifacts"][0]["candidate_marker_present"]:
            raise CrashSupportError("self-test lost the runtime candidate marker")
        tampered = first / "runtime.log"
        original = tampered.read_bytes()
        tampered.write_bytes(original + b"tamper\n")
        try:
            verify_bundle(fixture_root, fixture_metadata, fixture_dist, first)
        except CrashSupportError:
            pass
        else:
            raise CrashSupportError("self-test accepted a tampered support artifact")
        tampered.write_bytes(original)
        try:
            collect_bundle(
                fixture_root,
                fixture_metadata,
                fixture_dist,
                base / "support-c",
                "CASE-0002",
                "macOS",
                runtime_log,
                None,
                native_report,
                False,
                "2025-01-01T00:00:00Z",
            )
        except CrashSupportError as exc:
            if "acknowledgement" not in str(exc):
                raise
        else:
            raise CrashSupportError("self-test accepted a native report without acknowledgement")
    print(
        "CRASH_SUPPORT_TEST_OK candidate=bound files=hashed text=redacted "
        "binary=explicit-only upload=disabled tamper=blocked deterministic=ok"
    )


def _resolve(root: Path, value: Path) -> Path:
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("collect", "verify", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--candidate-root", type=Path, default=Path("dist"))
    parser.add_argument("--output-root", type=Path, default=Path("dist/crash-support"))
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--case-id")
    parser.add_argument("--preset", choices=tuple(NATIVE_REPORTS))
    parser.add_argument("--runtime-log", type=Path)
    parser.add_argument("--diagnostics", type=Path)
    parser.add_argument("--native-report", type=Path)
    parser.add_argument("--include-sensitive-native-report", action="store_true")
    parser.add_argument("--collected-at-utc")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = _resolve(root, args.metadata)
    candidate_root = _resolve(root, args.candidate_root)
    try:
        if args.command == "self-test":
            run_self_test(root, metadata_path)
        elif args.command == "collect":
            if args.case_id is None or args.preset is None or args.runtime_log is None:
                raise CrashSupportError(
                    "collect requires --case-id, --preset, and --runtime-log"
                )
            output_root = _resolve(root, args.output_root)
            bundle = collect_bundle(
                root,
                metadata_path,
                candidate_root,
                output_root,
                args.case_id,
                args.preset,
                _resolve(root, args.runtime_log),
                _resolve(root, args.diagnostics) if args.diagnostics else None,
                _resolve(root, args.native_report) if args.native_report else None,
                args.include_sensitive_native_report,
                args.collected_at_utc,
            )
            manifest = verify_bundle(root, metadata_path, candidate_root, bundle)
            print(
                f"CRASH_SUPPORT_COLLECT_OK candidate={manifest['candidate_id']} "
                f"case={manifest['case_id']} preset={manifest['preset']} "
                f"artifacts={len(manifest['artifacts'])} path={bundle}"
            )
        else:
            if args.bundle is None:
                raise CrashSupportError("verify requires --bundle")
            bundle = _resolve(root, args.bundle)
            manifest = verify_bundle(root, metadata_path, candidate_root, bundle)
            print(
                f"CRASH_SUPPORT_VERIFY_OK candidate={manifest['candidate_id']} "
                f"case={manifest['case_id']} preset={manifest['preset']} "
                f"artifacts={len(manifest['artifacts'])}"
            )
    except (CrashSupportError, candidate.ReleaseError, OSError) as exc:
        print(f"CRASH_SUPPORT_FAILED {exc}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
