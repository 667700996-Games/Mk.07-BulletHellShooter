#!/usr/bin/env python3
"""Verify, safely unpack, and smoke-test one release candidate on its native OS."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import io
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Dict, List, Mapping, Sequence

import release_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
MAX_ARCHIVE_BYTES = 1024 * 1024 * 1024
QUICK_TIMEOUT_SECONDS = 90
SOAK_TIMEOUT_SECONDS = 240
BENCHMARK_TIMEOUT_SECONDS = 120
FRAME_BUDGET_MS = 16.667
PLATFORM_CONTRACTS = {
    "Windows Desktop": {"host": "Windows", "godot_os": "Windows"},
    "macOS": {"host": "Darwin", "godot_os": "macOS"},
    "Linux": {"host": "Linux", "godot_os": "Linux"},
}
RECEIPT_SCHEMA_VERSION = 2
MAX_LOG_BYTES = 4 * 1024 * 1024
SOAK_RE = re.compile(
    r"RUNTIME_SOAK_OK runs=(\d+) cycles=(\d+) stages=(\d+) peak_bullets=(\d+) "
    r"peak_enemies=(\d+) peak_hazards=(\d+) node_drift=(-?\d+) orphan_drift=(-?\d+)"
)
BENCHMARK_RE = re.compile(
    r"BULLET_BENCHMARK_OK bullets=(\d+) frames=(\d+) average_update_ms=([0-9]+(?:\.[0-9]+)?)"
)
ALLOWED_MACOS_CA_ERROR_RE = re.compile(
    r'(?m)^ERROR: Condition "ret != noErr" is true\. Returning: ""\r?\n'
    r"   at: get_system_ca_certificates \(platform/macos/os_macos\.mm:\d+\)\r?\n?"
)
ENGINE_ERROR_RE = re.compile(r"(?m)^(?:SCRIPT ERROR|ERROR):[^\r\n]*")


class NativeSmokeError(RuntimeError):
    pass


def _unexpected_runtime_errors(combined: str) -> List[str]:
    sanitized = ALLOWED_MACOS_CA_ERROR_RE.sub("", combined)
    return ENGINE_ERROR_RE.findall(sanitized)


def _safe_members(archive: zipfile.ZipFile, context: str) -> Dict[str, zipfile.ZipInfo]:
    members: Dict[str, zipfile.ZipInfo] = {}
    total_size = 0
    for info in archive.infolist():
        path = PurePosixPath(info.filename)
        mode = (info.external_attr >> 16) & 0xFFFF
        if (
            path.is_absolute()
            or ".." in path.parts
            or "\\" in info.filename
            or info.is_dir()
            or stat.S_IFMT(mode) == stat.S_IFLNK
        ):
            raise NativeSmokeError(f"{context} contains an unsafe member: {info.filename}")
        if info.filename in members:
            raise NativeSmokeError(f"{context} contains a duplicate member: {info.filename}")
        total_size += info.file_size
        if total_size > MAX_ARCHIVE_BYTES:
            raise NativeSmokeError(f"{context} exceeds the extraction safety budget")
        members[info.filename] = info
    return members


def _copy_member(
    archive: zipfile.ZipFile, info: zipfile.ZipInfo, destination: Path
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with archive.open(info, "r") as source, destination.open("wb") as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
    mode = (info.external_attr >> 16) & 0o777
    destination.chmod(mode if mode else 0o644)


def _preset_by_name(metadata: Mapping[str, Any], preset_name: str) -> Mapping[str, Any]:
    presets = metadata.get("presets")
    if not isinstance(presets, list):
        raise NativeSmokeError("release metadata presets must be an array")
    matches = [item for item in presets if isinstance(item, dict) and item.get("name") == preset_name]
    if len(matches) != 1:
        raise NativeSmokeError(f"release metadata does not define exactly one preset: {preset_name}")
    return matches[0]


def _extract_runtime(
    package_path: Path,
    preset_name: str,
    metadata: Mapping[str, Any],
    destination: Path,
) -> Path:
    preset = _preset_by_name(metadata, preset_name)
    export_path = preset.get("export_path")
    artifact_name = PurePosixPath(str(export_path)).name
    package_root = str(metadata.get("artifact_name", ""))
    outer_artifact = f"{package_root}/{artifact_name}"
    outer_metadata = f"{package_root}/RELEASE.json"
    try:
        with zipfile.ZipFile(package_path, "r") as outer:
            outer_members = _safe_members(outer, "candidate package")
            if set(outer_members) != {outer_metadata, outer_artifact}:
                raise NativeSmokeError("candidate package member set differs from the release contract")
            embedded = json.loads(outer.read(outer_metadata))
            if not isinstance(embedded, dict) or embedded.get("preset") != preset_name:
                raise NativeSmokeError("candidate package embeds the wrong preset identity")
            if preset_name != "macOS":
                executable = destination / artifact_name
                _copy_member(outer, outer_members[outer_artifact], executable)
                executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
                return executable

            inner_bytes = outer.read(outer_artifact)
        with zipfile.ZipFile(io.BytesIO(inner_bytes), "r") as inner:
            inner_members = _safe_members(inner, "macOS application archive")
            for name, info in inner_members.items():
                _copy_member(inner, info, destination.joinpath(*PurePosixPath(name).parts))
    except (OSError, zipfile.BadZipFile, KeyError, json.JSONDecodeError) as exc:
        raise NativeSmokeError(f"cannot extract native runtime: {exc}") from exc
    product_name = str(metadata.get("product_name", ""))
    executable = destination / f"{product_name}.app" / "Contents" / "MacOS" / product_name
    if not executable.is_file() or executable.is_symlink():
        raise NativeSmokeError(f"macOS application executable is missing: {executable}")
    executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
    return executable


def _candidate_dir(candidate_root: Path, metadata: Mapping[str, Any]) -> Path:
    expected = candidate_root / candidate._candidate_id(metadata)
    if not expected.is_dir() or expected.is_symlink():
        raise NativeSmokeError(f"expected candidate directory is missing or unsafe: {expected}")
    if not (expected / candidate.MANIFEST_NAME).is_file():
        raise NativeSmokeError(f"expected candidate manifest is missing: {expected}")
    return expected


def _package_for_preset(candidate_dir: Path, preset_name: str) -> Path:
    manifest = candidate._load_json(candidate_dir / candidate.MANIFEST_NAME)
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        raise NativeSmokeError("candidate manifest packages must be an array")
    matches = [item for item in packages if isinstance(item, dict) and item.get("preset") == preset_name]
    if len(matches) != 1 or not isinstance(matches[0].get("path"), str):
        raise NativeSmokeError(f"candidate manifest does not contain preset package: {preset_name}")
    package_name = str(matches[0]["path"])
    if PurePosixPath(package_name).name != package_name:
        raise NativeSmokeError(f"candidate package path is unsafe: {package_name!r}")
    return candidate_dir / package_name


def _package_entry(manifest: Mapping[str, Any], preset_name: str) -> Mapping[str, Any]:
    packages = manifest.get("packages")
    if not isinstance(packages, list):
        raise NativeSmokeError("candidate manifest packages must be an array")
    matches = [item for item in packages if isinstance(item, dict) and item.get("preset") == preset_name]
    if len(matches) != 1:
        raise NativeSmokeError(f"candidate manifest does not contain one preset package: {preset_name}")
    return matches[0]


def _ci_context() -> Dict[str, Any]:
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return {
            "commit_sha": None,
            "provider": "local",
            "repository": None,
            "run_attempt": None,
            "run_id": None,
            "workflow_ref": None,
        }
    required = {
        "commit_sha": os.environ.get("GITHUB_SHA"),
        "repository": os.environ.get("GITHUB_REPOSITORY"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "run_id": os.environ.get("GITHUB_RUN_ID"),
        "workflow_ref": os.environ.get("GITHUB_WORKFLOW_REF"),
    }
    if any(not isinstance(value, str) or not value for value in required.values()):
        raise NativeSmokeError("GitHub Actions provenance environment is incomplete")
    return {"provider": "github-actions", **required}


def _write_log(path: Path, combined: str) -> Dict[str, Any]:
    data = combined.encode("utf-8", errors="replace")
    if len(data) > MAX_LOG_BYTES:
        data = b"[truncated to final 4 MiB]\n" + data[-MAX_LOG_BYTES:]
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise NativeSmokeError(f"native smoke log output is unsafe: {path}")
    candidate._atomic_write(path, data)
    return {"path": path.name, "sha256": candidate._sha256_file(path), "size": path.stat().st_size}


def build_receipt(
    metadata: Mapping[str, Any],
    manifest: Mapping[str, Any],
    preset_name: str,
    host: str,
    runtime_result: Mapping[str, Any],
    manifest_entry: Mapping[str, Any],
    log_entry: Mapping[str, Any],
    completed_at_utc: str,
    ci_context: Mapping[str, Any],
) -> Dict[str, Any]:
    preset = _preset_by_name(metadata, preset_name)
    package = _package_entry(manifest, preset_name)
    source_hashes = manifest.get("source_config_sha256")
    if not isinstance(source_hashes, dict) or "native_candidate_smoke.py" not in source_hashes:
        raise NativeSmokeError("candidate does not bind the native smoke verifier")
    contract = PLATFORM_CONTRACTS[preset_name]
    return {
        "architecture": preset["architecture"],
        "candidate_id": manifest["candidate_id"],
        "candidate_manifest": dict(manifest_entry),
        "ci": dict(ci_context),
        "completed_at_utc": completed_at_utc,
        "extraction_safe": True,
        "godot_platform": contract["godot_os"],
        "host_os": host,
        "package": {
            "path": package["path"],
            "sha256": package["sha256"],
            "size": package["size"],
        },
        "preset": preset_name,
        "runtime": dict(runtime_result),
        "runtime_log": dict(log_entry),
        "schema_version": RECEIPT_SCHEMA_VERSION,
        "source_tree": manifest["source_tree"],
        "tool": {
            "name": "native_candidate_smoke.py",
            "sha256": source_hashes["native_candidate_smoke.py"],
        },
        "verification_kind": (
            "unsigned-package-native-certification"
            if runtime_result.get("profile") == "certification"
            else "unsigned-package-runtime-smoke"
        ),
    }


def fixture_certification_runtime(candidate_id: str, godot_os: str) -> Dict[str, Any]:
    boot = f"EXPORT_RUNTIME_SMOKE_OK candidate={candidate_id} stages=3 characters=3 platform={godot_os}"
    soak = (
        "RUNTIME_SOAK_OK runs=9 cycles=3 stages=3 peak_bullets=414 "
        "peak_enemies=21 peak_hazards=4 node_drift=0 orphan_drift=0"
    )
    benchmark = "BULLET_BENCHMARK_OK bullets=3993 frames=300 average_update_ms=2.250"
    return {
        "checks": [
            {
                "metrics": {"characters": 3, "stages": 3},
                "name": "package-boot",
                "result_line": boot,
            },
            {
                "metrics": {
                    "cycles": 3,
                    "node_drift": 0,
                    "orphan_drift": 0,
                    "peak_bullets": 414,
                    "peak_enemies": 21,
                    "peak_hazards": 4,
                    "runs": 9,
                    "stages": 3,
                },
                "name": "campaign-soak",
                "result_line": soak,
            },
            {
                "metrics": {"average_update_ms": 2.25, "bullets": 3993, "frames": 300},
                "name": "bullet-benchmark",
                "result_line": benchmark,
            },
        ],
        "frame_budget_ms": FRAME_BUDGET_MS,
        "profile": "certification",
    }


def _execute_runtime(
    executable: Path,
    temporary_root: Path,
    check_name: str,
    user_argument: str,
    quit_after: int,
    timeout_seconds: int,
) -> tuple[int, str]:
    log_path = temporary_root / f"{check_name}.log"
    command = [
        str(executable),
        "--headless",
        "--log-file",
        str(log_path),
        "--quit-after",
        str(quit_after),
        "--",
        user_argument,
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=executable.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=timeout_seconds,
            check=False,
        )
        return_code = completed.returncode
        stdout = completed.stdout
    except subprocess.TimeoutExpired as exc:
        captured = exc.stdout or ""
        if isinstance(captured, bytes):
            captured = captured.decode("utf-8", errors="replace")
        return_code = 124
        stdout = f"{captured}\nnative runtime timed out after {timeout_seconds}s\n"
    except OSError as exc:
        return 126, f"native runtime could not start: {exc}\n"
    log_text = ""
    if log_path.is_file():
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
    combined = "\n".join(part for part in (stdout, log_text) if part)
    return return_code, combined


def _runtime_results(
    executable: Path,
    temporary_root: Path,
    candidate_id: str,
    godot_os: str,
    profile: str,
    log_output_path: Path | None,
) -> tuple[Dict[str, Any], Dict[str, Any] | None]:
    specifications = [
        ("package-boot", "--smoke-export", 300, QUICK_TIMEOUT_SECONDS),
    ]
    if profile == "certification":
        specifications.extend(
            [
                ("campaign-soak", "--smoke-soak", 12000, SOAK_TIMEOUT_SECONDS),
                ("bullet-benchmark", "--benchmark-bullets", 600, BENCHMARK_TIMEOUT_SECONDS),
            ]
        )
    checks: List[Dict[str, Any]] = []
    log_sections: List[str] = []
    for name, argument, quit_after, timeout_seconds in specifications:
        return_code, combined = _execute_runtime(
            executable, temporary_root, name, argument, quit_after, timeout_seconds
        )
        log_sections.append(f"=== {name} ===\n{combined.strip()}\n")
        if name == "package-boot":
            result_line = (
                f"EXPORT_RUNTIME_SMOKE_OK candidate={candidate_id} "
                f"stages=3 characters=3 platform={godot_os}"
            )
            metrics: Dict[str, Any] = {"characters": 3, "stages": 3}
            valid = result_line in combined
        elif name == "campaign-soak":
            match = SOAK_RE.search(combined)
            if match is None:
                result_line = "RUNTIME_SOAK_OK missing"
                metrics = {}
                valid = False
            else:
                result_line = match.group(0)
                values = [int(value) for value in match.groups()]
                metrics = {
                    "runs": values[0],
                    "cycles": values[1],
                    "stages": values[2],
                    "peak_bullets": values[3],
                    "peak_enemies": values[4],
                    "peak_hazards": values[5],
                    "node_drift": values[6],
                    "orphan_drift": values[7],
                }
                valid = (
                    values[0:3] == [9, 3, 3]
                    and values[3] <= 4000
                    and values[4] <= 64
                    and values[5] <= 48
                    and values[6] <= 1
                    and values[7] <= 2
                )
        else:
            match = BENCHMARK_RE.search(combined)
            if match is None:
                result_line = "BULLET_BENCHMARK_OK missing"
                metrics = {}
                valid = False
            else:
                result_line = match.group(0)
                bullets = int(match.group(1))
                frames = int(match.group(2))
                average_ms = float(match.group(3))
                metrics = {
                    "average_update_ms": average_ms,
                    "bullets": bullets,
                    "frames": frames,
                }
                valid = bullets >= 3990 and frames == 300 and average_ms <= FRAME_BUDGET_MS
        unexpected_errors = _unexpected_runtime_errors(combined)
        if return_code != 0 or not valid or unexpected_errors:
            if log_output_path is not None:
                _write_log(log_output_path, "\n".join(log_sections))
            tail = combined[-4000:].strip()
            raise NativeSmokeError(
                f"native {name} failed: returncode={return_code} result={result_line!r} "
                f"unexpected_errors={unexpected_errors[:3]!r}\n{tail}"
            )
        checks.append({"metrics": metrics, "name": name, "result_line": result_line})
        print(result_line)
    runtime = {
        "checks": checks,
        "frame_budget_ms": FRAME_BUDGET_MS,
        "profile": profile,
    }
    log_entry = (
        _write_log(log_output_path, "\n".join(log_sections))
        if log_output_path is not None
        else None
    )
    return runtime, log_entry


def run_native_smoke(
    root: Path,
    metadata_path: Path,
    candidate_root: Path,
    preset_name: str,
    profile: str = "quick",
    receipt_path: Path | None = None,
    log_output_path: Path | None = None,
) -> Dict[str, Any] | None:
    contract = PLATFORM_CONTRACTS.get(preset_name)
    if contract is None:
        raise NativeSmokeError(f"unsupported native preset: {preset_name}")
    host = platform.system()
    if host != contract["host"]:
        raise NativeSmokeError(f"preset {preset_name} requires {contract['host']}, current host is {host}")
    if (receipt_path is None) != (log_output_path is None):
        raise NativeSmokeError("--receipt and --log-output must be supplied together")
    if profile not in ("quick", "certification"):
        raise NativeSmokeError(f"unsupported native smoke profile: {profile}")
    metadata, _presets = candidate.load_and_validate_config(root, metadata_path)
    candidate_dir = _candidate_dir(candidate_root, metadata)
    manifest = candidate.verify_candidate(root, metadata_path, candidate_dir)
    package_path = _package_for_preset(candidate_dir, preset_name)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_native_smoke.") as temporary:
        temporary_root = Path(temporary)
        executable = _extract_runtime(package_path, preset_name, metadata, temporary_root / "runtime")
        runtime_result, log_entry = _runtime_results(
            executable,
            temporary_root,
            candidate._candidate_id(metadata),
            str(contract["godot_os"]),
            profile,
            log_output_path,
        )
    receipt: Dict[str, Any] | None = None
    if receipt_path is not None and log_entry is not None:
        manifest_path = candidate_dir / candidate.MANIFEST_NAME
        manifest_entry = {
            "path": candidate.MANIFEST_NAME,
            "sha256": candidate._sha256_file(manifest_path),
            "size": manifest_path.stat().st_size,
        }
        receipt = build_receipt(
            metadata,
            manifest,
            preset_name,
            host,
            runtime_result,
            manifest_entry,
            log_entry,
            datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            _ci_context(),
        )
        if receipt_path.is_symlink() or (receipt_path.exists() and not receipt_path.is_file()):
            raise NativeSmokeError(f"native smoke receipt output is unsafe: {receipt_path}")
        candidate._atomic_write(receipt_path, candidate._canonical_json(receipt))
    print(
        f"NATIVE_CANDIDATE_SMOKE_OK candidate={candidate._candidate_id(metadata)} "
        f"preset={preset_name} host={host} profile={profile} package=verified extraction=safe "
        f"receipt={'written' if receipt is not None else 'disabled'}"
    )
    return receipt


def _fixture_package(
    path: Path,
    metadata: Mapping[str, Any],
    preset_name: str,
    unsafe_inner: bool = False,
) -> bytes:
    preset = _preset_by_name(metadata, preset_name)
    artifact_name = PurePosixPath(str(preset["export_path"])).name
    package_root = str(metadata["artifact_name"])
    artifact = b"fixture-runtime"
    if preset_name == "macOS":
        product_name = str(metadata["product_name"])
        inner_buffer = io.BytesIO()
        with zipfile.ZipFile(inner_buffer, "w", compression=zipfile.ZIP_STORED) as inner:
            executable_name = f"{product_name}.app/Contents/MacOS/{product_name}"
            executable_info = zipfile.ZipInfo(executable_name)
            executable_info.create_system = 3
            executable_info.external_attr = 0o100755 << 16
            inner.writestr(executable_info, artifact)
            if unsafe_inner:
                inner.writestr("../escape", b"forbidden")
        artifact = inner_buffer.getvalue()
    embedded = json.dumps({"preset": preset_name}).encode("utf-8")
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as outer:
        outer.writestr(f"{package_root}/RELEASE.json", embedded)
        outer.writestr(f"{package_root}/{artifact_name}", artifact)
    return b"fixture-runtime"


def run_self_test(metadata_path: Path) -> None:
    metadata = candidate._load_json(metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_native_smoke_test.") as temporary:
        base = Path(temporary)
        for preset_name in PLATFORM_CONTRACTS:
            package_path = base / f"{preset_name.replace(' ', '_')}.zip"
            expected = _fixture_package(package_path, metadata, preset_name)
            executable = _extract_runtime(package_path, preset_name, metadata, base / preset_name)
            if executable.read_bytes() != expected or not executable.stat().st_mode & stat.S_IXUSR:
                raise NativeSmokeError(f"self-test extraction differed for {preset_name}")
        unsafe_path = base / "unsafe-macos.zip"
        _fixture_package(unsafe_path, metadata, "macOS", unsafe_inner=True)
        try:
            _extract_runtime(unsafe_path, "macOS", metadata, base / "unsafe")
        except NativeSmokeError as exc:
            if "unsafe member" not in str(exc):
                raise NativeSmokeError(f"unsafe archive failed for the wrong reason: {exc}") from exc
        else:
            raise NativeSmokeError("self-test extracted a traversal member")
    allowed_noise = (
        'ERROR: Condition "ret != noErr" is true. Returning: ""\n'
        "   at: get_system_ca_certificates (platform/macos/os_macos.mm:1035)\n"
    )
    if _unexpected_runtime_errors(allowed_noise):
        raise NativeSmokeError("self-test rejected the narrowly allowed macOS CA lookup noise")
    if not _unexpected_runtime_errors("ERROR: Invalid boss definition: missing attacks\n"):
        raise NativeSmokeError("self-test accepted an unexpected engine error")
    if not _unexpected_runtime_errors("SCRIPT ERROR: Invalid call.\n"):
        raise NativeSmokeError("self-test accepted an unexpected script error")
    print("NATIVE_CANDIDATE_SMOKE_TEST_OK presets=3 outer=validated inner=validated traversal=blocked runtime_errors=blocked")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("smoke", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--candidate-root", type=Path, default=ROOT / "dist")
    parser.add_argument("--preset", choices=tuple(PLATFORM_CONTRACTS))
    parser.add_argument("--profile", choices=("quick", "certification"), default="quick")
    parser.add_argument("--receipt", type=Path)
    parser.add_argument("--log-output", type=Path)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = args.metadata if args.metadata.is_absolute() else root / args.metadata
    candidate_root = args.candidate_root if args.candidate_root.is_absolute() else root / args.candidate_root
    try:
        if args.command == "self-test":
            run_self_test(metadata_path)
        else:
            if args.preset is None:
                raise NativeSmokeError("--preset is required for the smoke command")
            receipt_path = args.receipt if args.receipt is None or args.receipt.is_absolute() else root / args.receipt
            log_output_path = (
                args.log_output
                if args.log_output is None or args.log_output.is_absolute()
                else root / args.log_output
            )
            run_native_smoke(
                root,
                metadata_path,
                candidate_root,
                args.preset,
                args.profile,
                receipt_path,
                log_output_path,
            )
    except (NativeSmokeError, candidate.ReleaseError) as exc:
        print(f"NATIVE_CANDIDATE_SMOKE_FAILED {exc}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
