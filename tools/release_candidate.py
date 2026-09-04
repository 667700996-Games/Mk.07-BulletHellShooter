#!/usr/bin/env python3
"""Validate and package deterministic unsigned PSYCHIC VECTOR candidates.

Configuration and the packager's deterministic behavior can be checked without
Godot export templates. The ``package`` command consumes already exported files;
it never invokes Godot, signs code, uploads artifacts, or mutates source files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from typing import Any, Dict, Iterable, List, Mapping, Sequence, Tuple
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
VALIDATION_WORKFLOW = Path(".github/workflows/validation.yml")
RELEASE_WORKFLOW = Path(".github/workflows/release-candidate.yml")
MANIFEST_NAME = "release-manifest.json"
SEMVER_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)
SAFE_TOKEN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
EXPECTED_PLATFORM_RULES = {
    "Windows Desktop": ("Windows Desktop", {"x86_64"}, ".exe"),
    "macOS": ("macOS", {"universal"}, ".zip"),
    "Linux": ("Linux/X11", {"x86_64"}, ".x86_64"),
}
REQUIRED_EXPORT_EXCLUDES = {
    ".github/*",
    "assets/store/*",
    "build/*",
    "dist/*",
    "docs/*",
    "native-evidence/*",
    "playtests/*",
    "release/signing_policy.json",
    "tests/*",
    "tools/*",
}
SOURCE_TREE_EXCLUDED_ROOTS = {
    ".git", ".godot", "build", "dist", "native-evidence", "playtests"
}


class ReleaseError(RuntimeError):
    """A release contract or artifact verification failure."""


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def _load_json(path: Path) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReleaseError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReleaseError(f"expected a JSON object in {path}")
    return value


def _parse_cfg(path: Path) -> Dict[str, Dict[str, str]]:
    """Parse the simple section/key subset shared by Godot cfg files."""
    sections: Dict[str, Dict[str, str]] = {}
    current: Dict[str, str] | None = None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ReleaseError(f"cannot read configuration {path}: {exc}") from exc
    for line_number, source_line in enumerate(lines, start=1):
        line = source_line.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            if not section or section in sections:
                raise ReleaseError(f"invalid or duplicate section at {path}:{line_number}")
            current = {}
            sections[section] = current
            continue
        if current is None or "=" not in line:
            raise ReleaseError(f"unsupported configuration line at {path}:{line_number}")
        key, raw_value = line.split("=", 1)
        key = key.strip()
        if not key or key in current:
            raise ReleaseError(f"invalid or duplicate key at {path}:{line_number}")
        current[key] = raw_value.strip()
    return sections


def _cfg_string(raw: str, context: str) -> str:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ReleaseError(f"{context} must be a quoted string") from exc
    if not isinstance(value, str):
        raise ReleaseError(f"{context} must be a string")
    return value


def _metadata_presets(metadata: Mapping[str, Any]) -> List[Dict[str, Any]]:
    presets = metadata.get("presets")
    if not isinstance(presets, list) or not presets or not all(isinstance(item, dict) for item in presets):
        raise ReleaseError("release metadata presets must be a non-empty object array")
    return list(presets)


def _validate_relative_path(raw: str, context: str) -> PurePosixPath:
    candidate = PurePosixPath(raw)
    if candidate.is_absolute() or ".." in candidate.parts or "." in candidate.parts:
        raise ReleaseError(f"{context} must be a normalized relative path: {raw}")
    return candidate


def load_and_validate_config(
    root: Path = ROOT, metadata_path: Path = DEFAULT_METADATA
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    metadata = _load_json(metadata_path)
    errors: List[str] = []

    required_types = {
        "schema_version": int,
        "product_name": str,
        "artifact_name": str,
        "version": str,
        "build_number": int,
        "release_channel": str,
        "godot_version": str,
        "macos_bundle_identifier": str,
        "unsigned": bool,
    }
    for key, expected_type in required_types.items():
        if not isinstance(metadata.get(key), expected_type):
            errors.append(f"metadata {key} must be {expected_type.__name__}")
    if metadata.get("schema_version") != 1:
        errors.append("metadata schema_version must be 1")
    version = str(metadata.get("version", ""))
    if not SEMVER_RE.fullmatch(version):
        errors.append(f"metadata version is not SemVer: {version!r}")
    release_channel = str(metadata.get("release_channel", ""))
    version_without_build = version.split("+", 1)[0]
    prerelease = version_without_build.split("-", 1)[1] if "-" in version_without_build else ""
    if release_channel == "stable":
        if prerelease:
            errors.append("stable release metadata may not use a prerelease version")
    elif not prerelease or prerelease.split(".", 1)[0] != release_channel:
        errors.append(
            f"release channel {release_channel!r} does not match version prerelease {prerelease!r}"
        )
    if int(metadata.get("build_number", 0) or 0) <= 0:
        errors.append("metadata build_number must be positive")
    if int(metadata.get("build_number", 0) or 0) > 65535:
        errors.append("metadata build_number exceeds the desktop resource-version limit of 65535")
    if metadata.get("unsigned") is not True:
        errors.append("this pipeline is intentionally unsigned; metadata unsigned must be true")
    for token_key in ("artifact_name", "release_channel"):
        token = str(metadata.get(token_key, ""))
        if not SAFE_TOKEN_RE.fullmatch(token):
            errors.append(f"metadata {token_key} is not filename-safe: {token!r}")
    godot_version = str(metadata.get("godot_version", ""))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", godot_version):
        errors.append(f"metadata godot_version must be pinned to x.y.z: {godot_version!r}")
    macos_bundle_identifier = str(metadata.get("macos_bundle_identifier", ""))
    if not re.fullmatch(r"[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*){2,}", macos_bundle_identifier):
        errors.append("metadata macos_bundle_identifier must use a lowercase reverse-DNS form")

    project_path = root / "project.godot"
    export_path = root / "export_presets.cfg"
    workflow_path = root / VALIDATION_WORKFLOW
    project_cfg = _parse_cfg(project_path)
    export_cfg = _parse_cfg(export_path)
    application = project_cfg.get("application", {})
    debug = project_cfg.get("debug", {})
    editor = project_cfg.get("editor", {})
    rendering = project_cfg.get("rendering", {})
    try:
        project_name = _cfg_string(application.get("config/name", ""), "application config/name")
        project_version = _cfg_string(application.get("config/version", ""), "application config/version")
        main_scene = _cfg_string(application.get("run/main_scene", ""), "application run/main_scene")
    except ReleaseError as exc:
        errors.append(str(exc))
        project_name = project_version = main_scene = ""
    if project_name != metadata.get("product_name"):
        errors.append(f"project name {project_name!r} does not match release metadata")
    if project_version != version:
        errors.append(f"project version {project_version!r} does not match metadata {version!r}")
    if not main_scene.startswith("res://") or not (root / main_scene.removeprefix("res://")).is_file():
        errors.append(f"project main scene does not resolve: {main_scene!r}")
    if editor.get("export/convert_text_resources_to_binary") != "false":
        errors.append(
            "project editor/export/convert_text_resources_to_binary must be explicitly false "
            "to preserve nested combat arrays"
        )
    if application.get("run/flush_stdout_on_print") != "true":
        errors.append("project application run/flush_stdout_on_print must be explicitly true")
    debug_boolean_contract = (
        "file_logging/enable_file_logging",
        "file_logging/enable_file_logging.pc",
        "settings/gdscript/always_track_call_stacks",
    )
    for setting in debug_boolean_contract:
        if debug.get(setting) != "true":
            errors.append(f"project debug {setting} must be explicitly true")
    try:
        runtime_log_path = _cfg_string(
            debug.get("file_logging/log_path", ""), "debug file_logging/log_path"
        )
        if runtime_log_path != "user://logs/psychic_vector.log":
            errors.append("project debug file_logging/log_path differs from the data policy")
    except ReleaseError as exc:
        errors.append(str(exc))
    if debug.get("file_logging/max_log_files") != "5":
        errors.append("project debug file_logging/max_log_files must be exactly 5")
    try:
        crash_message = _cfg_string(
            debug.get("settings/crash_handler/message", ""),
            "debug settings/crash_handler/message",
        )
        if not crash_message.strip():
            errors.append("project crash handler support message must not be empty")
    except ReleaseError as exc:
        errors.append(str(exc))
    for texture_setting in (
        "textures/vram_compression/import_s3tc_bptc",
        "textures/vram_compression/import_etc2_astc",
    ):
        if rendering.get(texture_setting) != "true":
            errors.append(f"project rendering {texture_setting} must be explicitly enabled")

    try:
        workflow_text = workflow_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read validation workflow: {exc}")
        workflow_text = ""
    workflow_version = re.search(r"(?m)^\s+version:\s*['\"]?([0-9]+\.[0-9]+\.[0-9]+)['\"]?\s*$", workflow_text)
    if workflow_version is None or workflow_version.group(1) != godot_version:
        actual = workflow_version.group(1) if workflow_version else "missing"
        errors.append(f"validation workflow Godot version {actual!r} does not match {godot_version!r}")
    if not re.search(r"(?m)^\s+include-templates:\s*false\s*$", workflow_text):
        errors.append("validation workflow must explicitly remain template-independent")

    release_workflow_path = root / RELEASE_WORKFLOW
    try:
        release_workflow_text = release_workflow_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"cannot read release-candidate workflow: {exc}")
        release_workflow_text = ""
    release_version = re.search(
        r"(?m)^\s+version:\s*['\"]?([0-9]+\.[0-9]+\.[0-9]+)['\"]?\s*$",
        release_workflow_text,
    )
    if release_version is None or release_version.group(1) != godot_version:
        actual = release_version.group(1) if release_version else "missing"
        errors.append(f"release workflow Godot version {actual!r} does not match {godot_version!r}")
    release_contract = {
        "manual workflow trigger": "workflow_dispatch:",
        "export templates": "include-templates: true",
        "source validation": "bash tools/validate.sh",
        "export artifact audit": "python3 tools/export_artifact_audit.py audit",
        "export runtime smoke": "build/linux/PsychicVector.x86_64 --headless --log-file /tmp/psychic-vector-export-smoke.log --quit-after 300 -- --smoke-export",
        "native smoke matrix": "native-smoke:",
        "Windows native runner": "os: windows-latest",
        "macOS native runner": "os: macos-latest",
        "Linux native runner": "os: ubuntu-latest",
        "candidate artifact download": "uses: actions/download-artifact@v8",
        "native candidate smoke": "python tools/native_candidate_smoke.py smoke --candidate-root dist",
        "native smoke preset": '--preset "${{ matrix.preset }}"',
        "native certification profile": "--profile certification",
        "native smoke receipt": '--receipt "native-evidence/receipts/${{ matrix.slug }}.json"',
        "native smoke log": '--log-output "native-evidence/logs/${{ matrix.slug }}.log"',
        "native evidence artifact": "name: native-smoke-evidence-${{ matrix.slug }}",
        "native matrix aggregation": "native-smoke-matrix:",
        "native matrix evidence download": "pattern: native-smoke-evidence-*",
        "native matrix receipt": "python tools/native_smoke_evidence.py record --candidate-root dist",
        "native matrix artifact": "name: psychic-vector-native-smoke-matrix",
        "candidate packaging": "python3 tools/release_candidate.py package",
        "candidate verification": "python3 tools/release_candidate.py verify",
        "artifact upload": "uses: actions/upload-artifact@v7",
        "missing-artifact failure": "if-no-files-found: error",
    }
    for contract_name, needle in release_contract.items():
        if needle not in release_workflow_text:
            errors.append(f"release workflow is missing {contract_name}: {needle!r}")

    try:
        expected_presets = _metadata_presets(metadata)
    except ReleaseError as exc:
        errors.append(str(exc))
        expected_presets = []
    seen_names: set[str] = set()
    seen_slugs: set[str] = set()
    seen_paths: set[str] = set()
    normalized_presets: List[Dict[str, Any]] = []
    core_version = version.split("+", 1)[0].split("-", 1)[0]
    build_number = int(metadata.get("build_number", 0) or 0)
    windows_resource_version = f"{core_version}.{build_number}"
    for index, expected in enumerate(expected_presets):
        context = f"metadata preset {index}"
        missing = [
            key
            for key in ("name", "platform", "architecture", "feature", "slug", "export_path")
            if not isinstance(expected.get(key), str) or not expected[key]
        ]
        if missing:
            errors.append(f"{context} has missing string fields: {', '.join(missing)}")
            continue
        name = expected["name"]
        slug = expected["slug"]
        output = expected["export_path"]
        if name in seen_names:
            errors.append(f"duplicate preset name: {name}")
        if slug in seen_slugs or not SAFE_TOKEN_RE.fullmatch(slug):
            errors.append(f"duplicate or unsafe preset slug: {slug}")
        if output in seen_paths:
            errors.append(f"duplicate preset export path: {output}")
        seen_names.add(name)
        seen_slugs.add(slug)
        seen_paths.add(output)
        if not re.fullmatch(r"[a-z][a-z0-9_]*", expected["feature"]):
            errors.append(f"{context} feature is not a safe snake_case token")
        try:
            relative_output = _validate_relative_path(output, f"{context} export_path")
            if not relative_output.parts or relative_output.parts[0] != "build":
                errors.append(f"{context} export_path must be under build/")
        except ReleaseError as exc:
            errors.append(str(exc))

        rule = EXPECTED_PLATFORM_RULES.get(name)
        if rule is None:
            errors.append(f"unsupported desktop preset name: {name}")
        else:
            expected_platform, architectures, suffix = rule
            if expected["platform"] != expected_platform:
                errors.append(f"{name} platform must be {expected_platform!r}")
            if expected["architecture"] not in architectures:
                errors.append(f"{name} architecture must be one of {sorted(architectures)}")
            if not output.endswith(suffix):
                errors.append(f"{name} export_path must end in {suffix}")

        section = export_cfg.get(f"preset.{index}")
        options = export_cfg.get(f"preset.{index}.options")
        if section is None or options is None:
            errors.append(f"export preset {index} or its options section is missing")
            continue
        string_contract = {
            "name": name,
            "platform": expected["platform"],
            "export_path": output,
            "export_filter": "all_resources",
        }
        for key, expected_value in string_contract.items():
            try:
                actual_value = _cfg_string(section.get(key, ""), f"preset {name} {key}")
            except ReleaseError as exc:
                errors.append(str(exc))
                continue
            if actual_value != expected_value:
                errors.append(f"preset {name} {key} {actual_value!r} != {expected_value!r}")
        if (
            section.get("runnable") != "true"
            or section.get("advanced_options") != "false"
            or section.get("dedicated_server") != "false"
            or section.get("script_export_mode") != "2"
        ):
            errors.append(
                f"preset {name} must be runnable, non-advanced, non-server, and use script mode 2"
            )
        try:
            excludes = {
                item.strip()
                for item in _cfg_string(section.get("exclude_filter", ""), f"preset {name} exclude_filter").split(",")
                if item.strip()
            }
            if excludes != REQUIRED_EXPORT_EXCLUDES:
                errors.append(
                    f"preset {name} exclusion set must be exactly "
                    f"{sorted(REQUIRED_EXPORT_EXCLUDES)}"
                )
        except ReleaseError as exc:
            errors.append(str(exc))
        try:
            include_filter = _cfg_string(
                section.get("include_filter", ""), f"preset {name} include_filter"
            )
            if include_filter:
                errors.append(f"preset {name} must not add an include-only filter")
        except ReleaseError as exc:
            errors.append(str(exc))
        try:
            custom_features = {
                item.strip()
                for item in _cfg_string(
                    section.get("custom_features", ""), f"preset {name} custom_features"
                ).split(",")
                if item.strip()
            }
            expected_features = {"psychic_vector_release", expected["feature"]}
            if custom_features != expected_features:
                errors.append(
                    f"preset {name} custom features {sorted(custom_features)} != {sorted(expected_features)}"
                )
        except ReleaseError as exc:
            errors.append(str(exc))
        try:
            architecture = _cfg_string(options.get("binary_format/architecture", ""), f"preset {name} architecture")
            if architecture != expected["architecture"]:
                errors.append(f"preset {name} architecture {architecture!r} != {expected['architecture']!r}")
        except ReleaseError as exc:
            errors.append(str(exc))
        if name == "macOS" and options.get("codesign/codesign") != "0":
            errors.append("unsigned macOS preset must have codesign/codesign=0")
        if name in ("Windows Desktop", "Linux") and options.get("binary_format/embed_pck") != "true":
            errors.append(f"preset {name} must embed its PCK for a single self-contained export")
        if options.get("texture_format/s3tc_bptc") != "true":
            errors.append(f"preset {name} must enable the desktop S3TC/BPTC texture path")
        expected_etc2_astc = "true" if name == "macOS" else "false"
        if options.get("texture_format/etc2_astc") != expected_etc2_astc:
            errors.append(
                f"preset {name} ETC2/ASTC setting must be {expected_etc2_astc}"
            )
        if name == "Windows Desktop":
            for key in ("application/file_version", "application/product_version"):
                try:
                    value = _cfg_string(options.get(key, ""), f"preset {name} {key}")
                    if value != windows_resource_version:
                        errors.append(
                            f"preset {name} {key} {value!r} != {windows_resource_version!r}"
                        )
                except ReleaseError as exc:
                    errors.append(str(exc))
        elif name == "macOS":
            mac_version_contract = {
                "application/bundle_identifier": macos_bundle_identifier,
                "application/short_version": core_version,
                "application/version": str(build_number),
            }
            for key, expected_value in mac_version_contract.items():
                try:
                    value = _cfg_string(options.get(key, ""), f"preset {name} {key}")
                    if value != expected_value:
                        errors.append(
                            f"preset {name} {key} {value!r} != {expected_value!r}"
                        )
                except ReleaseError as exc:
                    errors.append(str(exc))
        normalized_presets.append(dict(expected))

        export_command = (
            f'godot --headless --path . --export-release "{name}" {output}'
        )
        if export_command not in release_workflow_text:
            errors.append(f"release workflow is missing exact export command for {name}")

    preset_sections = sorted(
        key for key in export_cfg if re.fullmatch(r"preset\.[0-9]+", key)
    )
    if len(preset_sections) != len(expected_presets):
        errors.append(
            f"export preset count {len(preset_sections)} does not match metadata {len(expected_presets)}"
        )
    if seen_names != set(EXPECTED_PLATFORM_RULES):
        errors.append(f"desktop preset set must be exactly {sorted(EXPECTED_PLATFORM_RULES)}")

    if errors:
        raise ReleaseError("release configuration failed:\n- " + "\n- ".join(errors))
    return metadata, normalized_presets


def _candidate_id(metadata: Mapping[str, Any]) -> str:
    return f"{metadata['artifact_name']}-{metadata['version']}-build.{metadata['build_number']}-unsigned"


def _source_config_hashes(root: Path, metadata_path: Path) -> Dict[str, str]:
    sources = {
        "crash_support_bundle.py": root / "tools" / "crash_support_bundle.py",
        "export_artifact_audit.py": root / "tools" / "export_artifact_audit.py",
        "linux_delivery.py": root / "tools" / "linux_delivery.py",
        "native_candidate_smoke.py": root / "tools" / "native_candidate_smoke.py",
        "native_smoke_evidence.py": root / "tools" / "native_smoke_evidence.py",
        "release_candidate.py": root / "tools" / "release_candidate.py",
        "release_channel.py": root / "tools" / "release_channel.py",
        "release_delta.py": root / "tools" / "release_delta.py",
        "release-candidate.yml": root / RELEASE_WORKFLOW,
        "signed_delivery.py": root / "tools" / "signed_delivery.py",
        "signing_policy.json": root / "release" / "signing_policy.json",
        "signing_provenance.py": root / "tools" / "signing_provenance.py",
        "validate.sh": root / "tools" / "validate.sh",
        "validation.yml": root / VALIDATION_WORKFLOW,
        "export_presets.cfg": root / "export_presets.cfg",
        "project.godot": root / "project.godot",
        "release_metadata.json": metadata_path,
    }
    return {name: _sha256_file(path) for name, path in sorted(sources.items())}


def _source_tree_fingerprint(root: Path) -> Dict[str, Any]:
    entries: List[Tuple[str, Path]] = []
    for directory, child_directories, filenames in os.walk(root, topdown=True, followlinks=False):
        directory_path = Path(directory)
        retained_directories: List[str] = []
        for name in sorted(child_directories):
            path = directory_path / name
            relative = path.relative_to(root)
            if relative.parts[0] in SOURCE_TREE_EXCLUDED_ROOTS or name == "__pycache__":
                continue
            if path.is_symlink():
                raise ReleaseError(f"source tree may not contain symbolic links: {relative.as_posix()}")
            retained_directories.append(name)
        child_directories[:] = retained_directories
        for name in sorted(filenames):
            path = directory_path / name
            relative = path.relative_to(root)
            if path.is_symlink():
                raise ReleaseError(f"source tree may not contain symbolic links: {relative.as_posix()}")
            if name == ".DS_Store" or path.suffix in (".log", ".pyc"):
                continue
            entries.append((relative.as_posix(), path))
    entries.sort(key=lambda item: item[0])
    digest = hashlib.sha256()
    total_bytes = 0
    for relative, path in entries:
        path_bytes = relative.encode("utf-8")
        size = path.stat().st_size
        file_digest = bytes.fromhex(_sha256_file(path))
        digest.update(len(path_bytes).to_bytes(4, "big"))
        digest.update(path_bytes)
        digest.update(size.to_bytes(8, "big"))
        digest.update(file_digest)
        total_bytes += size
    return {
        "algorithm": "sha256-framed-path-size-content-v1",
        "bytes": total_bytes,
        "files": len(entries),
        "sha256": digest.hexdigest(),
    }


def _artifact_path(build_root: Path, preset: Mapping[str, Any]) -> Path:
    relative = _validate_relative_path(str(preset["export_path"]), "preset export_path")
    return build_root.joinpath(*relative.parts[1:])


def _collect_artifacts(build_root: Path, preset: Mapping[str, Any]) -> List[Path]:
    primary = _artifact_path(build_root, preset)
    if not primary.is_file():
        raise ReleaseError(f"missing exported artifact for {preset['name']}: {primary}")
    paths = [primary]
    for path in paths:
        if path.is_symlink():
            raise ReleaseError(f"release artifacts may not be symbolic links: {path}")
        if path.stat().st_size <= 0:
            raise ReleaseError(f"release artifact is empty: {path}")
    names = [path.name for path in paths]
    if len(names) != len(set(names)):
        raise ReleaseError(f"artifact names collide for {preset['name']}")
    return sorted(paths, key=lambda item: item.name)


def _archive_info(name: str, executable: bool = False) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    mode = 0o100755 if executable else 0o100644
    info.external_attr = mode << 16
    return info


def _package_one(
    output_path: Path,
    metadata: Mapping[str, Any],
    preset: Mapping[str, Any],
    artifacts: Sequence[Path],
) -> Dict[str, Any]:
    content_files = [
        {"path": path.name, "sha256": _sha256_file(path), "size": path.stat().st_size}
        for path in artifacts
    ]
    embedded = {
        "architecture": preset["architecture"],
        "build_number": metadata["build_number"],
        "files": content_files,
        "platform": preset["platform"],
        "preset": preset["name"],
        "product_name": metadata["product_name"],
        "schema_version": 1,
        "unsigned": True,
        "version": metadata["version"],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output_path.name}.", dir=output_path.parent)
    os.close(file_descriptor)
    temporary_path = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary_path, "w", allowZip64=True) as archive:
            base = str(metadata["artifact_name"])
            archive.writestr(_archive_info(f"{base}/RELEASE.json"), _canonical_json(embedded))
            for artifact in artifacts:
                executable = artifact.suffix in (".exe", ".x86_64")
                archive.writestr(
                    _archive_info(f"{base}/{artifact.name}", executable),
                    artifact.read_bytes(),
                )
        os.replace(temporary_path, output_path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()
    return {
        "architecture": preset["architecture"],
        "contents": content_files,
        "path": output_path.name,
        "platform": preset["platform"],
        "preset": preset["name"],
        "sha256": _sha256_file(output_path),
        "size": output_path.stat().st_size,
    }


def package_candidate(
    root: Path,
    metadata_path: Path,
    build_root: Path,
    dist_root: Path,
) -> Path:
    metadata, presets = load_and_validate_config(root, metadata_path)
    candidate_id = _candidate_id(metadata)
    candidate_dir = dist_root / candidate_id
    if candidate_dir.exists() and (not candidate_dir.is_dir() or candidate_dir.is_symlink()):
        raise ReleaseError(f"candidate output directory is unsafe: {candidate_dir}")
    candidate_dir.mkdir(parents=True, exist_ok=True)
    package_entries: List[Dict[str, Any]] = []
    for preset in presets:
        filename = f"{candidate_id}-{preset['slug']}.zip"
        artifacts = _collect_artifacts(build_root, preset)
        package_entries.append(_package_one(candidate_dir / filename, metadata, preset, artifacts))
    manifest = {
        "build_number": metadata["build_number"],
        "candidate_id": candidate_id,
        "godot_version": metadata["godot_version"],
        "packages": sorted(package_entries, key=lambda item: item["preset"]),
        "product_name": metadata["product_name"],
        "release_channel": metadata["release_channel"],
        "schema_version": 2,
        "source_config_sha256": _source_config_hashes(root, metadata_path),
        "source_tree": _source_tree_fingerprint(root),
        "unsigned": True,
        "version": metadata["version"],
    }
    manifest_path = candidate_dir / MANIFEST_NAME
    _atomic_write(manifest_path, _canonical_json(manifest))
    verify_candidate(root, metadata_path, candidate_dir)
    return manifest_path


def _safe_archive_names(archive: zipfile.ZipFile) -> List[str]:
    names: List[str] = []
    for info in archive.infolist():
        path = PurePosixPath(info.filename)
        if path.is_absolute() or ".." in path.parts or info.is_dir():
            raise ReleaseError(f"unsafe or unexpected archive member: {info.filename}")
        if info.filename in names:
            raise ReleaseError(f"duplicate archive member: {info.filename}")
        names.append(info.filename)
    return names


def _verify_package(path: Path, expected: Mapping[str, Any], metadata: Mapping[str, Any]) -> None:
    if path.is_symlink() or not path.is_file():
        raise ReleaseError(f"package is missing or not a regular file: {path}")
    if path.stat().st_size != expected.get("size"):
        raise ReleaseError(f"package size mismatch: {path.name}")
    if _sha256_file(path) != expected.get("sha256"):
        raise ReleaseError(f"package checksum mismatch: {path.name}")
    base = str(metadata["artifact_name"])
    expected_contents = expected.get("contents")
    if not isinstance(expected_contents, list):
        raise ReleaseError(f"package contents are invalid: {path.name}")
    content_contract: List[Dict[str, Any]] = []
    content_names: set[str] = set()
    for item in expected_contents:
        if not isinstance(item, dict):
            raise ReleaseError(f"package content entries must be objects: {path.name}")
        item_path = item.get("path")
        item_size = item.get("size")
        item_hash = item.get("sha256")
        if (
            not isinstance(item_path, str)
            or PurePosixPath(item_path).name != item_path
            or not isinstance(item_size, int)
            or item_size <= 0
            or not isinstance(item_hash, str)
            or re.fullmatch(r"[0-9a-f]{64}", item_hash) is None
        ):
            raise ReleaseError(f"package content contract is invalid: {path.name}")
        if item_path in content_names or item_path == "RELEASE.json":
            raise ReleaseError(f"package content path is duplicated or reserved: {path.name}:{item_path}")
        content_names.add(item_path)
        content_contract.append(item)
    expected_names = [f"{base}/RELEASE.json"] + [f"{base}/{item['path']}" for item in content_contract]
    try:
        with zipfile.ZipFile(path, "r") as archive:
            names = _safe_archive_names(archive)
            if names != expected_names:
                raise ReleaseError(f"package member order/content mismatch: {path.name}")
            embedded_bytes = archive.read(f"{base}/RELEASE.json")
            embedded = json.loads(embedded_bytes)
            embedded_contract = {
                "architecture": expected["architecture"],
                "build_number": metadata["build_number"],
                "files": content_contract,
                "platform": expected["platform"],
                "preset": expected["preset"],
                "product_name": metadata["product_name"],
                "schema_version": 1,
                "unsigned": True,
                "version": metadata["version"],
            }
            if embedded != embedded_contract:
                raise ReleaseError(f"embedded release metadata mismatch: {path.name}")
            if embedded_bytes != _canonical_json(embedded_contract):
                raise ReleaseError(f"embedded release metadata is not canonical: {path.name}")
            for info in archive.infolist():
                expected_executable = info.filename.endswith((".exe", ".x86_64"))
                expected_mode = 0o100755 if expected_executable else 0o100644
                if (
                    info.date_time != (1980, 1, 1, 0, 0, 0)
                    or info.compress_type != zipfile.ZIP_STORED
                    or info.create_system != 3
                    or info.external_attr >> 16 != expected_mode
                ):
                    raise ReleaseError(f"package member metadata is not normalized: {path.name}:{info.filename}")
            for item in content_contract:
                data = archive.read(f"{base}/{item['path']}")
                if len(data) != item["size"] or _sha256_bytes(data) != item["sha256"]:
                    raise ReleaseError(f"embedded artifact mismatch: {path.name}:{item['path']}")
    except (OSError, zipfile.BadZipFile, KeyError, json.JSONDecodeError) as exc:
        raise ReleaseError(f"cannot verify package {path.name}: {exc}") from exc


def verify_candidate(root: Path, metadata_path: Path, candidate_dir: Path) -> Dict[str, Any]:
    metadata, presets = load_and_validate_config(root, metadata_path)
    if not candidate_dir.is_dir() or candidate_dir.is_symlink():
        raise ReleaseError(f"candidate directory is missing or unsafe: {candidate_dir}")
    manifest_path = candidate_dir / MANIFEST_NAME
    if manifest_path.is_symlink():
        raise ReleaseError(f"manifest may not be a symbolic link: {manifest_path}")
    manifest = _load_json(manifest_path)
    if manifest_path.read_bytes() != _canonical_json(manifest):
        raise ReleaseError("release manifest is not canonical JSON")
    expected_header = {
        "build_number": metadata["build_number"],
        "candidate_id": _candidate_id(metadata),
        "godot_version": metadata["godot_version"],
        "product_name": metadata["product_name"],
        "release_channel": metadata["release_channel"],
        "schema_version": 2,
        "source_config_sha256": _source_config_hashes(root, metadata_path),
        "source_tree": _source_tree_fingerprint(root),
        "unsigned": True,
        "version": metadata["version"],
    }
    for key, expected_value in expected_header.items():
        if manifest.get(key) != expected_value:
            raise ReleaseError(f"manifest {key} does not match current release contract")
    packages = manifest.get("packages")
    if not isinstance(packages, list) or len(packages) != len(presets):
        raise ReleaseError("manifest package count does not match release presets")
    package_order = [item.get("preset") if isinstance(item, dict) else None for item in packages]
    if package_order != sorted(package_order, key=lambda item: str(item)):
        raise ReleaseError("manifest packages are not in deterministic preset order")
    expected_by_name = {preset["name"]: preset for preset in presets}
    seen: set[str] = set()
    expected_files = {MANIFEST_NAME}
    for package in packages:
        if not isinstance(package, dict):
            raise ReleaseError("manifest packages must be objects")
        preset_name = package.get("preset")
        if preset_name in seen or preset_name not in expected_by_name:
            raise ReleaseError(f"manifest contains duplicate or unknown preset: {preset_name!r}")
        seen.add(str(preset_name))
        preset = expected_by_name[str(preset_name)]
        if package.get("platform") != preset["platform"] or package.get("architecture") != preset["architecture"]:
            raise ReleaseError(f"manifest platform contract mismatch: {preset_name}")
        package_name = package.get("path")
        if not isinstance(package_name, str) or PurePosixPath(package_name).name != package_name:
            raise ReleaseError(f"manifest package path is unsafe: {package_name!r}")
        expected_name = f"{_candidate_id(metadata)}-{preset['slug']}.zip"
        if package_name != expected_name:
            raise ReleaseError(f"manifest package name {package_name!r} != {expected_name!r}")
        expected_files.add(package_name)
        _verify_package(candidate_dir / package_name, package, metadata)
    actual_entries = {path.name for path in candidate_dir.iterdir()}
    if actual_entries != expected_files:
        extra = sorted(actual_entries - expected_files)
        missing = sorted(expected_files - actual_entries)
        raise ReleaseError(f"candidate directory contents differ; extra={extra}, missing={missing}")
    return manifest


def _create_fake_exports(build_root: Path, presets: Iterable[Mapping[str, Any]]) -> None:
    for index, preset in enumerate(presets):
        primary = _artifact_path(build_root, preset)
        primary.parent.mkdir(parents=True, exist_ok=True)
        primary.write_bytes((f"fixture:{preset['name']}:{index}\n").encode("utf-8") * (index + 2))


def _copy_contract_fixture(source_root: Path, source_metadata: Path, target_root: Path) -> Path:
    relative_files = (
        Path("LICENSE"),
        Path("project.godot"),
        Path("export_presets.cfg"),
        Path("tools/crash_support_bundle.py"),
        Path("tools/export_artifact_audit.py"),
        Path("tools/linux_delivery.py"),
        Path("tools/native_candidate_smoke.py"),
        Path("tools/native_smoke_evidence.py"),
        Path("tools/release_candidate.py"),
        Path("tools/release_channel.py"),
        Path("tools/release_delta.py"),
        Path("tools/signed_delivery.py"),
        Path("tools/signing_provenance.py"),
        Path("tools/validate.sh"),
        Path("release/signing_policy.json"),
        VALIDATION_WORKFLOW,
        RELEASE_WORKFLOW,
    )
    for relative in relative_files:
        target = target_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((source_root / relative).read_bytes())
    target_metadata = target_root / "release" / "release_metadata.json"
    target_metadata.parent.mkdir(parents=True, exist_ok=True)
    target_metadata.write_bytes(source_metadata.read_bytes())
    target_scene = target_root / "scenes" / "main.tscn"
    target_scene.parent.mkdir(parents=True, exist_ok=True)
    target_scene.write_text("[gd_scene format=3]\n", encoding="utf-8")
    return target_metadata


def _assert_contract_mutation_rejected(
    fixture_root: Path,
    fixture_metadata: Path,
    relative_path: Path,
    source: str,
    replacement: str,
    expected_message: str,
) -> None:
    path = fixture_root / relative_path
    original = path.read_text(encoding="utf-8")
    if original.count(source) < 1:
        raise ReleaseError(f"self-test mutation source is absent: {relative_path}:{source}")
    path.write_text(original.replace(source, replacement, 1), encoding="utf-8")
    try:
        load_and_validate_config(fixture_root, fixture_metadata)
    except ReleaseError as exc:
        if expected_message not in str(exc):
            raise ReleaseError(
                f"self-test rejected {relative_path} for the wrong reason: {exc}"
            ) from exc
    else:
        raise ReleaseError(f"self-test accepted invalid release contract: {relative_path}")
    finally:
        path.write_text(original, encoding="utf-8")


def run_self_test(root: Path, metadata_path: Path) -> None:
    metadata, presets = load_and_validate_config(root, metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_release_test.") as temporary:
        base = Path(temporary)
        build_root = base / "build"
        _create_fake_exports(build_root, presets)
        first_manifest = package_candidate(root, metadata_path, build_root, base / "dist-a")
        second_manifest = package_candidate(root, metadata_path, build_root, base / "dist-b")
        first_dir = first_manifest.parent
        second_dir = second_manifest.parent
        first_files = sorted(path.name for path in first_dir.iterdir())
        second_files = sorted(path.name for path in second_dir.iterdir())
        if first_files != second_files:
            raise ReleaseError("self-test package file sets are not deterministic")
        for filename in first_files:
            if (first_dir / filename).read_bytes() != (second_dir / filename).read_bytes():
                raise ReleaseError(f"self-test output is not byte deterministic: {filename}")
        verify_candidate(root, metadata_path, first_dir)
        manifest = _load_json(first_manifest)
        victim = first_dir / manifest["packages"][0]["path"]
        original = victim.read_bytes()
        victim.write_bytes(original + b"tamper")
        try:
            verify_candidate(root, metadata_path, first_dir)
        except ReleaseError as exc:
            if "checksum mismatch" not in str(exc) and "size mismatch" not in str(exc):
                raise
        else:
            raise ReleaseError("self-test accepted a tampered package")
        fixture_root = base / "contract-fixture"
        fixture_metadata = _copy_contract_fixture(root, metadata_path, fixture_root)
        fixture_build = base / "contract-build"
        _, fixture_presets = load_and_validate_config(fixture_root, fixture_metadata)
        _create_fake_exports(fixture_build, fixture_presets)
        fixture_candidate = package_candidate(
            fixture_root, fixture_metadata, fixture_build, base / "contract-dist"
        ).parent
        fixture_scene = fixture_root / "scenes" / "main.tscn"
        fixture_scene_original = fixture_scene.read_text(encoding="utf-8")
        fixture_scene.write_text(fixture_scene_original + "# source drift\n", encoding="utf-8")
        try:
            verify_candidate(fixture_root, fixture_metadata, fixture_candidate)
        except ReleaseError as exc:
            if "source_tree" not in str(exc):
                raise ReleaseError(f"source-tree drift failed for the wrong reason: {exc}") from exc
        else:
            raise ReleaseError("self-test accepted source-tree drift")
        finally:
            fixture_scene.write_text(fixture_scene_original, encoding="utf-8")
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("project.godot"),
            f'config/version="{metadata["version"]}"',
            'config/version="9.9.9-invalid"',
            "does not match metadata",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("export_presets.cfg"),
            'platform="Windows Desktop"',
            'platform="Broken Desktop"',
            "platform",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("export_presets.cfg"),
            'binary_format/architecture="x86_64"',
            'binary_format/architecture="arm64"',
            "architecture",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("export_presets.cfg"),
            "dist/*,",
            "",
            "exclusion set",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("project.godot"),
            "textures/vram_compression/import_etc2_astc=true",
            "textures/vram_compression/import_etc2_astc=false",
            "import_etc2_astc must be explicitly enabled",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            Path("project.godot"),
            "file_logging/max_log_files=5",
            "file_logging/max_log_files=50",
            "max_log_files must be exactly 5",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            RELEASE_WORKFLOW,
            "include-templates: true",
            "include-templates: false",
            "release workflow is missing export templates",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            RELEASE_WORKFLOW,
            'godot --headless --path . --export-release "Linux" build/linux/PsychicVector.x86_64',
            'godot --headless --path . --export-release "Linux" build/linux/Wrong.x86_64',
            "release workflow is missing exact export command for Linux",
        )
        _assert_contract_mutation_rejected(
            fixture_root,
            fixture_metadata,
            RELEASE_WORKFLOW,
            "python tools/native_candidate_smoke.py smoke --candidate-root dist",
            "python tools/native_candidate_smoke.py smoke --candidate-root broken",
            "release workflow is missing native candidate smoke",
        )
    print(
        "RELEASE_CANDIDATE_TEST_OK "
        f"version={metadata['version']} build={metadata['build_number']} "
        f"presets={len(presets)} contract_drift=blocked pipeline_drift=blocked source_tree_drift=blocked deterministic=ok "
        "tamper=blocked unsigned=explicit"
    )


def _default_candidate_dir(metadata: Mapping[str, Any], dist_root: Path) -> Path:
    return dist_root / _candidate_id(metadata)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check", help="validate version, engine, and export preset contracts")
    package_parser = subparsers.add_parser("package", help="package existing unsigned desktop exports")
    package_parser.add_argument("--build-root", type=Path, default=Path("build"))
    package_parser.add_argument("--dist-root", type=Path, default=Path("dist"))
    verify_parser = subparsers.add_parser("verify", help="verify a candidate manifest and all package bytes")
    verify_parser.add_argument("--candidate-dir", type=Path)
    verify_parser.add_argument("--dist-root", type=Path, default=Path("dist"))
    subparsers.add_parser("self-test", help="exercise deterministic packaging and tamper rejection")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = args.metadata if args.metadata.is_absolute() else root / args.metadata
    try:
        if args.command == "check":
            metadata, presets = load_and_validate_config(root, metadata_path)
            print(
                "RELEASE_CONFIG_OK "
                f"version={metadata['version']} build={metadata['build_number']} "
                f"godot={metadata['godot_version']} presets={len(presets)} unsigned=explicit"
            )
        elif args.command == "package":
            build_root = args.build_root if args.build_root.is_absolute() else root / args.build_root
            dist_root = args.dist_root if args.dist_root.is_absolute() else root / args.dist_root
            manifest_path = package_candidate(root, metadata_path, build_root, dist_root)
            print(f"RELEASE_PACKAGE_OK manifest={manifest_path}")
        elif args.command == "verify":
            metadata, _ = load_and_validate_config(root, metadata_path)
            if args.candidate_dir is not None:
                candidate_dir = args.candidate_dir if args.candidate_dir.is_absolute() else root / args.candidate_dir
            else:
                dist_root = args.dist_root if args.dist_root.is_absolute() else root / args.dist_root
                candidate_dir = _default_candidate_dir(metadata, dist_root)
            manifest = verify_candidate(root, metadata_path, candidate_dir)
            print(
                "RELEASE_VERIFY_OK "
                f"candidate={manifest['candidate_id']} packages={len(manifest['packages'])}"
            )
        elif args.command == "self-test":
            run_self_test(root, metadata_path)
        else:
            parser.error(f"unknown command: {args.command}")
    except ReleaseError as exc:
        print(f"RELEASE_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
