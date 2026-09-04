#!/usr/bin/env python3
"""Maintain a verified, local-only release channel with atomic rollback state.

The channel archives immutable unsigned candidates and changes only a canonical
JSON active pointer. It deliberately performs no signing, upload, publication,
installation, or deletion of archived candidates.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile
from typing import Any, Dict, List, Mapping, Sequence

import release_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
DEFAULT_CHANNEL_ROOT = Path("dist/release-channel")
INDEX_NAME = "release-channel.json"
INDEX_KEYS = {
    "active_candidate_id",
    "artifact_name",
    "candidates",
    "channel",
    "product_name",
    "schema_version",
    "transitions",
    "unsigned",
}
ENTRY_KEYS = {
    "build_number",
    "candidate_id",
    "manifest_path",
    "manifest_sha256",
    "packages",
    "version",
}
TRANSITION_KEYS = {
    "action",
    "from_candidate_id",
    "sequence",
    "to_candidate_id",
}
MANIFEST_KEYS = {
    "build_number",
    "candidate_id",
    "godot_version",
    "packages",
    "product_name",
    "release_channel",
    "schema_version",
    "source_config_sha256",
    "unsigned",
    "version",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class ChannelError(candidate.ReleaseError):
    """A release-channel state or archived-candidate validation failure."""


def _require_exact_keys(value: Mapping[str, Any], expected: set[str], context: str) -> None:
    actual = set(value)
    if actual != expected:
        raise ChannelError(
            f"{context} fields differ; extra={sorted(actual - expected)}, "
            f"missing={sorted(expected - actual)}"
        )


def _require_sha256(value: Any, context: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise ChannelError(f"{context} must be a lowercase SHA-256 digest")
    return value


def _resolve_under(base: Path, relative: str, context: str) -> Path:
    safe = candidate._validate_relative_path(relative, context)
    resolved_base = base.resolve()
    resolved = base.joinpath(*safe.parts).resolve()
    try:
        resolved.relative_to(resolved_base)
    except ValueError as exc:
        raise ChannelError(f"{context} escapes the channel root") from exc
    return resolved


def _channel_metadata(root: Path, metadata_path: Path) -> Dict[str, Any]:
    metadata, _ = candidate.load_and_validate_config(root, metadata_path)
    return metadata


def _new_index(metadata: Mapping[str, Any]) -> Dict[str, Any]:
    return {
        "active_candidate_id": None,
        "artifact_name": metadata["artifact_name"],
        "candidates": [],
        "channel": metadata["release_channel"],
        "product_name": metadata["product_name"],
        "schema_version": 1,
        "transitions": [],
        "unsigned": True,
    }


def _load_index(channel_root: Path) -> Dict[str, Any]:
    index_path = channel_root / INDEX_NAME
    if index_path.is_symlink():
        raise ChannelError(f"channel index may not be a symbolic link: {index_path}")
    index = candidate._load_json(index_path)
    if index_path.read_bytes() != candidate._canonical_json(index):
        raise ChannelError("release channel index is not canonical JSON")
    return index


def _candidate_artifact_name(manifest: Mapping[str, Any]) -> str:
    version = manifest.get("version")
    build_number = manifest.get("build_number")
    candidate_id = manifest.get("candidate_id")
    if not isinstance(version, str) or candidate.SEMVER_RE.fullmatch(version) is None:
        raise ChannelError("archived manifest version is not valid SemVer")
    if not isinstance(build_number, int) or isinstance(build_number, bool) or build_number < 1:
        raise ChannelError("archived manifest build_number must be a positive integer")
    if not isinstance(candidate_id, str) or candidate.SAFE_TOKEN_RE.fullmatch(candidate_id) is None:
        raise ChannelError("archived manifest candidate_id is unsafe")
    suffix = f"-{version}-build.{build_number}-unsigned"
    if not candidate_id.endswith(suffix):
        raise ChannelError("archived manifest candidate_id does not match version/build")
    artifact_name = candidate_id[: -len(suffix)]
    if not artifact_name or candidate.SAFE_TOKEN_RE.fullmatch(artifact_name) is None:
        raise ChannelError("archived candidate artifact name is unsafe")
    return artifact_name


def _package_summaries(packages: Sequence[Mapping[str, Any]]) -> List[Dict[str, Any]]:
    return [
        {
            "path": package["path"],
            "sha256": package["sha256"],
            "size": package["size"],
        }
        for package in packages
    ]


def _verify_archived_candidate(candidate_dir: Path) -> Dict[str, Any]:
    if not candidate_dir.is_dir() or candidate_dir.is_symlink():
        raise ChannelError(f"archived candidate directory is missing or unsafe: {candidate_dir}")
    manifest_path = candidate_dir / candidate.MANIFEST_NAME
    if manifest_path.is_symlink():
        raise ChannelError(f"archived manifest may not be a symbolic link: {manifest_path}")
    manifest = candidate._load_json(manifest_path)
    if manifest_path.read_bytes() != candidate._canonical_json(manifest):
        raise ChannelError("archived release manifest is not canonical JSON")
    _require_exact_keys(manifest, MANIFEST_KEYS, "archived manifest")
    if manifest.get("schema_version") != 1 or manifest.get("unsigned") is not True:
        raise ChannelError("archived manifest must be schema 1 and explicitly unsigned")
    artifact_name = _candidate_artifact_name(manifest)
    candidate_id = str(manifest["candidate_id"])
    if candidate_dir.name != candidate_id:
        raise ChannelError("archived candidate directory name does not match its manifest")
    product_name = manifest.get("product_name")
    release_channel = manifest.get("release_channel")
    godot_version = manifest.get("godot_version")
    if not isinstance(product_name, str) or not product_name:
        raise ChannelError("archived manifest product_name is invalid")
    if not isinstance(release_channel, str) or candidate.SAFE_TOKEN_RE.fullmatch(release_channel) is None:
        raise ChannelError("archived manifest release_channel is unsafe")
    if not isinstance(godot_version, str) or re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", godot_version) is None:
        raise ChannelError("archived manifest godot_version is invalid")
    source_hashes = manifest.get("source_config_sha256")
    if not isinstance(source_hashes, dict) or not source_hashes:
        raise ChannelError("archived manifest source hashes are invalid")
    for name, digest in source_hashes.items():
        if not isinstance(name, str) or not name or PurePosixPath(name).name != name:
            raise ChannelError("archived manifest source hash name is unsafe")
        _require_sha256(digest, f"archived source hash {name}")

    packages = manifest.get("packages")
    if not isinstance(packages, list) or not packages:
        raise ChannelError("archived manifest must contain packages")
    preset_order: List[str] = []
    package_names: set[str] = set()
    archive_metadata = {
        "artifact_name": artifact_name,
        "build_number": manifest["build_number"],
        "product_name": product_name,
        "version": manifest["version"],
    }
    for item in packages:
        if not isinstance(item, dict):
            raise ChannelError("archived package entries must be objects")
        if set(item) != {
            "architecture", "contents", "path", "platform", "preset", "sha256", "size"
        }:
            raise ChannelError("archived package fields differ from the packaging contract")
        preset = item.get("preset")
        platform = item.get("platform")
        architecture = item.get("architecture")
        package_name = item.get("path")
        if not all(isinstance(value, str) and value for value in (preset, platform, architecture)):
            raise ChannelError("archived package identity fields are invalid")
        if not isinstance(package_name, str) or PurePosixPath(package_name).name != package_name:
            raise ChannelError("archived package path is unsafe")
        if not package_name.startswith(f"{candidate_id}-") or not package_name.endswith(".zip"):
            raise ChannelError("archived package filename does not match candidate_id")
        if package_name in package_names or preset in preset_order:
            raise ChannelError("archived package names and presets must be unique")
        package_names.add(package_name)
        preset_order.append(preset)
        _require_sha256(item.get("sha256"), f"archived package {package_name}")
        candidate._verify_package(candidate_dir / package_name, item, archive_metadata)
    if preset_order != sorted(preset_order):
        raise ChannelError("archived packages are not in deterministic preset order")
    expected_files = {candidate.MANIFEST_NAME, *package_names}
    actual_files = {path.name for path in candidate_dir.iterdir()}
    if actual_files != expected_files:
        raise ChannelError(
            "archived candidate contents differ; "
            f"extra={sorted(actual_files - expected_files)}, missing={sorted(expected_files - actual_files)}"
        )
    return manifest


def _entry_from_manifest(channel_root: Path, archived_dir: Path, manifest: Mapping[str, Any]) -> Dict[str, Any]:
    manifest_path = archived_dir / candidate.MANIFEST_NAME
    relative_manifest = manifest_path.relative_to(channel_root).as_posix()
    return {
        "build_number": manifest["build_number"],
        "candidate_id": manifest["candidate_id"],
        "manifest_path": relative_manifest,
        "manifest_sha256": candidate._sha256_file(manifest_path),
        "packages": _package_summaries(manifest["packages"]),
        "version": manifest["version"],
    }


def _verify_entry(channel_root: Path, entry: Mapping[str, Any], index: Mapping[str, Any]) -> Dict[str, Any]:
    _require_exact_keys(entry, ENTRY_KEYS, "channel candidate entry")
    candidate_id = entry.get("candidate_id")
    if not isinstance(candidate_id, str) or candidate.SAFE_TOKEN_RE.fullmatch(candidate_id) is None:
        raise ChannelError("channel candidate_id is unsafe")
    expected_manifest_path = f"candidates/{candidate_id}/{candidate.MANIFEST_NAME}"
    if entry.get("manifest_path") != expected_manifest_path:
        raise ChannelError(f"channel manifest path is not canonical for {candidate_id}")
    manifest_path = _resolve_under(channel_root, expected_manifest_path, "channel manifest_path")
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise ChannelError(f"channel manifest is missing or unsafe for {candidate_id}")
    if candidate._sha256_file(manifest_path) != _require_sha256(
        entry.get("manifest_sha256"), f"channel manifest {candidate_id}"
    ):
        raise ChannelError(f"channel manifest checksum mismatch for {candidate_id}")
    manifest = _verify_archived_candidate(manifest_path.parent)
    identity_contract = {
        "build_number": manifest["build_number"],
        "candidate_id": manifest["candidate_id"],
        "packages": _package_summaries(manifest["packages"]),
        "version": manifest["version"],
    }
    for key, expected in identity_contract.items():
        if entry.get(key) != expected:
            raise ChannelError(f"channel entry {key} does not match archived manifest for {candidate_id}")
    if manifest["product_name"] != index["product_name"]:
        raise ChannelError(f"archived product differs from channel for {candidate_id}")
    if manifest["release_channel"] != index["channel"]:
        raise ChannelError(f"archived release channel differs for {candidate_id}")
    if _candidate_artifact_name(manifest) != index["artifact_name"]:
        raise ChannelError(f"archived artifact name differs from channel for {candidate_id}")
    return manifest


def verify_channel(
    root: Path,
    metadata_path: Path,
    channel_root: Path,
) -> Dict[str, Any]:
    metadata = _channel_metadata(root, metadata_path)
    if not channel_root.is_dir() or channel_root.is_symlink():
        raise ChannelError(f"channel root is missing or unsafe: {channel_root}")
    candidates_root = channel_root / "candidates"
    if not candidates_root.is_dir() or candidates_root.is_symlink():
        raise ChannelError(f"channel candidate archive is missing or unsafe: {candidates_root}")
    index = _load_index(channel_root)
    _require_exact_keys(index, INDEX_KEYS, "release channel index")
    header = {
        "artifact_name": metadata["artifact_name"],
        "channel": metadata["release_channel"],
        "product_name": metadata["product_name"],
        "schema_version": 1,
        "unsigned": True,
    }
    for key, expected in header.items():
        if index.get(key) != expected:
            raise ChannelError(f"channel index {key} does not match current release contract")
    entries = index.get("candidates")
    transitions = index.get("transitions")
    active = index.get("active_candidate_id")
    if not isinstance(entries, list) or not entries:
        raise ChannelError("release channel must archive at least one candidate")
    if not isinstance(transitions, list) or not transitions:
        raise ChannelError("release channel must contain at least one transition")
    if not isinstance(active, str):
        raise ChannelError("release channel active_candidate_id is invalid")

    entry_ids: List[str] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ChannelError("channel candidate entries must be objects")
        entry_id = entry.get("candidate_id")
        if entry_id in entry_ids:
            raise ChannelError(f"duplicate channel candidate entry: {entry_id!r}")
        _verify_entry(channel_root, entry, index)
        entry_ids.append(str(entry_id))

    current: str | None = None
    previously_active: set[str] = set()
    first_seen: List[str] = []
    for offset, transition in enumerate(transitions, start=1):
        if not isinstance(transition, dict):
            raise ChannelError("channel transitions must be objects")
        _require_exact_keys(transition, TRANSITION_KEYS, "channel transition")
        if transition.get("sequence") != offset:
            raise ChannelError("channel transition sequence is not contiguous")
        action = transition.get("action")
        source = transition.get("from_candidate_id")
        target = transition.get("to_candidate_id")
        if action not in ("promote", "rollback"):
            raise ChannelError(f"unknown channel transition action: {action!r}")
        if source != current or target not in entry_ids or target == current:
            raise ChannelError(f"invalid channel transition at sequence {offset}")
        if action == "rollback" and target not in previously_active:
            raise ChannelError("rollback target was never previously active")
        if target not in first_seen:
            first_seen.append(target)
        if current is not None:
            previously_active.add(current)
        current = target
    if first_seen != entry_ids:
        raise ChannelError("candidate archive order does not match first activation order")
    if current != active:
        raise ChannelError("active_candidate_id does not match the transition chain")
    return index


def _copy_verified_candidate(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        return
    staging_parent = Path(tempfile.mkdtemp(prefix=f".{target.name}.", dir=target.parent))
    staging = staging_parent / target.name
    try:
        staging.mkdir()
        for source_file in sorted(source.iterdir(), key=lambda path: path.name):
            if not source_file.is_file() or source_file.is_symlink():
                raise ChannelError(f"candidate copy source is unsafe: {source_file}")
            shutil.copy2(source_file, staging / source_file.name)
        _verify_archived_candidate(staging)
        os.replace(staging, target)
    finally:
        if staging_parent.exists():
            shutil.rmtree(staging_parent)


def promote_candidate(
    root: Path,
    metadata_path: Path,
    source_candidate_dir: Path,
    channel_root: Path,
) -> Dict[str, Any]:
    metadata = _channel_metadata(root, metadata_path)
    source_manifest = candidate.verify_candidate(root, metadata_path, source_candidate_dir)
    if channel_root.exists() and (not channel_root.is_dir() or channel_root.is_symlink()):
        raise ChannelError(f"channel root is unsafe: {channel_root}")
    channel_root.mkdir(parents=True, exist_ok=True)
    candidates_root = channel_root / "candidates"
    if candidates_root.exists() and (not candidates_root.is_dir() or candidates_root.is_symlink()):
        raise ChannelError(f"channel candidate archive is unsafe: {candidates_root}")
    candidates_root.mkdir(parents=True, exist_ok=True)
    index_path = channel_root / INDEX_NAME
    if index_path.exists():
        index = verify_channel(root, metadata_path, channel_root)
    else:
        index = _new_index(metadata)

    candidate_id = str(source_manifest["candidate_id"])
    archived_dir = candidates_root / candidate_id
    _copy_verified_candidate(source_candidate_dir, archived_dir)
    archived_manifest = _verify_archived_candidate(archived_dir)
    if candidate._sha256_file(source_candidate_dir / candidate.MANIFEST_NAME) != candidate._sha256_file(
        archived_dir / candidate.MANIFEST_NAME
    ):
        raise ChannelError("archived candidate manifest differs from verified source")

    entries = index["candidates"]
    matching = [entry for entry in entries if entry.get("candidate_id") == candidate_id]
    expected_entry = _entry_from_manifest(channel_root, archived_dir, archived_manifest)
    if matching:
        if len(matching) != 1 or matching[0] != expected_entry:
            raise ChannelError("existing channel candidate entry differs from verified source")
    else:
        entries.append(expected_entry)
    previous = index["active_candidate_id"]
    if previous == candidate_id:
        raise ChannelError(f"candidate is already active: {candidate_id}")
    index["transitions"].append(
        {
            "action": "promote",
            "from_candidate_id": previous,
            "sequence": len(index["transitions"]) + 1,
            "to_candidate_id": candidate_id,
        }
    )
    index["active_candidate_id"] = candidate_id
    candidate._atomic_write(index_path, candidate._canonical_json(index))
    return verify_channel(root, metadata_path, channel_root)


def rollback_candidate(
    root: Path,
    metadata_path: Path,
    channel_root: Path,
    target_candidate_id: str,
) -> Dict[str, Any]:
    if candidate.SAFE_TOKEN_RE.fullmatch(target_candidate_id) is None:
        raise ChannelError("rollback target candidate_id is unsafe")
    index = verify_channel(root, metadata_path, channel_root)
    known = {entry["candidate_id"] for entry in index["candidates"]}
    if target_candidate_id not in known:
        raise ChannelError(f"rollback target is not archived: {target_candidate_id}")
    previous = index["active_candidate_id"]
    if previous == target_candidate_id:
        raise ChannelError(f"rollback target is already active: {target_candidate_id}")
    previously_active = {item["to_candidate_id"] for item in index["transitions"]}
    if target_candidate_id not in previously_active:
        raise ChannelError(f"rollback target was never active: {target_candidate_id}")
    index["transitions"].append(
        {
            "action": "rollback",
            "from_candidate_id": previous,
            "sequence": len(index["transitions"]) + 1,
            "to_candidate_id": target_candidate_id,
        }
    )
    index["active_candidate_id"] = target_candidate_id
    candidate._atomic_write(channel_root / INDEX_NAME, candidate._canonical_json(index))
    return verify_channel(root, metadata_path, channel_root)


def _build_fixture_candidate(
    fixture_root: Path,
    fixture_metadata: Path,
    build_root: Path,
    dist_root: Path,
) -> Path:
    _, presets = candidate.load_and_validate_config(fixture_root, fixture_metadata)
    candidate._create_fake_exports(build_root, presets)
    return candidate.package_candidate(fixture_root, fixture_metadata, build_root, dist_root).parent


def run_self_test(root: Path, metadata_path: Path) -> None:
    base_metadata = _channel_metadata(root, metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_channel_test.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        channel_root = base / "channel"
        first_dir = _build_fixture_candidate(
            fixture_root, fixture_metadata, base / "build-a", base / "dist-a"
        )
        first_id = first_dir.name
        promote_candidate(fixture_root, fixture_metadata, first_dir, channel_root)

        next_version = "9.8.7-alpha.2"
        next_build_number = int(base_metadata["build_number"]) + 1
        project_path = fixture_root / "project.godot"
        project_text = project_path.read_text(encoding="utf-8")
        project_path.write_text(
            project_text.replace(
                f'config/version="{base_metadata["version"]}"',
                f'config/version="{next_version}"',
                1,
            ),
            encoding="utf-8",
        )
        base_core_version = str(base_metadata["version"]).split("+", 1)[0].split("-", 1)[0]
        next_core_version = next_version.split("+", 1)[0].split("-", 1)[0]
        export_path = fixture_root / "export_presets.cfg"
        export_text = export_path.read_text(encoding="utf-8")
        version_replacements = {
            f'application/file_version="{base_core_version}.{base_metadata["build_number"]}"': f'application/file_version="{next_core_version}.{next_build_number}"',
            f'application/product_version="{base_core_version}.{base_metadata["build_number"]}"': f'application/product_version="{next_core_version}.{next_build_number}"',
            f'application/short_version="{base_core_version}"': f'application/short_version="{next_core_version}"',
            f'application/version="{base_metadata["build_number"]}"': f'application/version="{next_build_number}"',
        }
        for source, replacement in version_replacements.items():
            if export_text.count(source) != 1:
                raise ChannelError(f"self-test platform version source differs: {source}")
            export_text = export_text.replace(source, replacement, 1)
        export_path.write_text(export_text, encoding="utf-8")
        next_metadata = json.loads(fixture_metadata.read_text(encoding="utf-8"))
        next_metadata["version"] = next_version
        next_metadata["build_number"] = next_build_number
        fixture_metadata.write_bytes(candidate._canonical_json(next_metadata))
        second_dir = _build_fixture_candidate(
            fixture_root, fixture_metadata, base / "build-b", base / "dist-b"
        )
        second_id = second_dir.name
        promoted = promote_candidate(fixture_root, fixture_metadata, second_dir, channel_root)
        if promoted["active_candidate_id"] != second_id:
            raise ChannelError("self-test promotion did not activate the second candidate")
        rolled_back = rollback_candidate(
            fixture_root, fixture_metadata, channel_root, first_id
        )
        if rolled_back["active_candidate_id"] != first_id:
            raise ChannelError("self-test rollback did not restore the first candidate")

        second_entry = next(
            item for item in rolled_back["candidates"] if item["candidate_id"] == second_id
        )
        victim = channel_root / "candidates" / second_id / second_entry["packages"][0]["path"]
        original = victim.read_bytes()
        victim.write_bytes(original + b"tamper")
        try:
            verify_channel(fixture_root, fixture_metadata, channel_root)
        except candidate.ReleaseError as exc:
            if "mismatch" not in str(exc):
                raise
        else:
            raise ChannelError("self-test accepted a tampered archived package")
        finally:
            victim.write_bytes(original)

        index_path = channel_root / INDEX_NAME
        canonical_index = index_path.read_bytes()
        broken = candidate._load_json(index_path)
        broken["transitions"][-1]["from_candidate_id"] = "forged-source"
        index_path.write_bytes(candidate._canonical_json(broken))
        try:
            verify_channel(fixture_root, fixture_metadata, channel_root)
        except candidate.ReleaseError as exc:
            if "transition" not in str(exc):
                raise
        else:
            raise ChannelError("self-test accepted a forged rollback chain")
        finally:
            index_path.write_bytes(canonical_index)
        verify_channel(fixture_root, fixture_metadata, channel_root)
    print(
        "RELEASE_CHANNEL_TEST_OK "
        "candidates=2 transitions=3 promotion=atomic rollback=verified "
        "archive_tamper=blocked chain_tamper=blocked unsigned=explicit local_only=true"
    )


def _resolve_cli_path(root: Path, value: Path) -> Path:
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    subparsers = parser.add_subparsers(dest="command", required=True)
    promote_parser = subparsers.add_parser("promote", help="archive and activate a verified candidate")
    promote_parser.add_argument("--candidate-dir", type=Path, required=True)
    promote_parser.add_argument("--channel-root", type=Path, default=DEFAULT_CHANNEL_ROOT)
    rollback_parser = subparsers.add_parser("rollback", help="activate a previously verified candidate")
    rollback_parser.add_argument("--target-candidate-id", required=True)
    rollback_parser.add_argument("--channel-root", type=Path, default=DEFAULT_CHANNEL_ROOT)
    verify_parser = subparsers.add_parser("verify", help="verify the archive and activation history")
    verify_parser.add_argument("--channel-root", type=Path, default=DEFAULT_CHANNEL_ROOT)
    subparsers.add_parser("self-test", help="exercise promotion, rollback, and tamper rejection")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = _resolve_cli_path(root, args.metadata)
    try:
        if args.command == "promote":
            source = _resolve_cli_path(root, args.candidate_dir)
            channel_root = _resolve_cli_path(root, args.channel_root)
            index = promote_candidate(root, metadata_path, source, channel_root)
            print(
                f"RELEASE_CHANNEL_PROMOTE_OK active={index['active_candidate_id']} "
                f"candidates={len(index['candidates'])} transitions={len(index['transitions'])}"
            )
        elif args.command == "rollback":
            channel_root = _resolve_cli_path(root, args.channel_root)
            index = rollback_candidate(
                root, metadata_path, channel_root, args.target_candidate_id
            )
            print(
                f"RELEASE_CHANNEL_ROLLBACK_OK active={index['active_candidate_id']} "
                f"candidates={len(index['candidates'])} transitions={len(index['transitions'])}"
            )
        elif args.command == "verify":
            channel_root = _resolve_cli_path(root, args.channel_root)
            index = verify_channel(root, metadata_path, channel_root)
            print(
                f"RELEASE_CHANNEL_VERIFY_OK active={index['active_candidate_id']} "
                f"candidates={len(index['candidates'])} transitions={len(index['transitions'])}"
            )
        else:
            run_self_test(root, metadata_path)
    except candidate.ReleaseError as exc:
        print(f"RELEASE_CHANNEL_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
