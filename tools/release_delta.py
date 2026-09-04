#!/usr/bin/env python3
"""Create, verify, and apply deterministic chunk deltas between release candidates."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tempfile
from typing import Any, Dict, Iterator, List, Mapping, Sequence, Tuple
import zipfile

import release_candidate as candidate
import release_channel as channel


ROOT = Path(__file__).resolve().parents[1]
FORMAT = "psychic-vector-candidate-chunk-delta-v1"
MANIFEST_NAME = "DELTA.json"
DEFAULT_CHUNK_SIZE = 1024 * 1024
MIN_CHUNK_SIZE = 4096
MAX_CHUNK_SIZE = 16 * 1024 * 1024
MAX_MANIFEST_SIZE = 32 * 1024 * 1024
ANCHOR_SIZE = 32
ROOT_KEYS = {
    "chunk_size",
    "files",
    "format",
    "schema_version",
    "source",
    "stats",
    "target",
    "unsigned",
}
SNAPSHOT_KEYS = {
    "build_number",
    "candidate_id",
    "files",
    "manifest_sha256",
    "product_name",
    "release_channel",
    "version",
}
SNAPSHOT_FILE_KEYS = {"path", "sha256", "size"}
FILE_KEYS = {"chunks", "path", "sha256", "size"}
SOURCE_CHUNK_KEYS = {"kind", "offset", "path", "sha256", "size"}
BLOB_CHUNK_KEYS = {"kind", "path", "sha256", "size"}
STATS_KEYS = {"literal_bytes", "reused_bytes", "target_bytes", "unique_blob_bytes"}


class DeltaError(candidate.ReleaseError):
    """A delta bundle or reconstruction contract failed."""


def _exact_keys(value: Mapping[str, Any], expected: set[str], context: str) -> None:
    actual = set(value)
    if actual != expected:
        raise DeltaError(
            f"{context} fields differ; extra={sorted(actual - expected)}, "
            f"missing={sorted(expected - actual)}"
        )


def _positive_int(value: Any, context: str, allow_zero: bool = False) -> int:
    minimum = 0 if allow_zero else 1
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        qualifier = "non-negative" if allow_zero else "positive"
        raise DeltaError(f"{context} must be a {qualifier} integer")
    return value


def _sha256(value: Any, context: str) -> str:
    try:
        return channel._require_sha256(value, context)
    except channel.ChannelError as exc:
        raise DeltaError(str(exc)) from exc


def _safe_flat_name(value: Any, context: str) -> str:
    if not isinstance(value, str) or not value or PurePosixPath(value).name != value:
        raise DeltaError(f"{context} must be a safe flat filename")
    if "\\" in value or value in (".", ".."):
        raise DeltaError(f"{context} is unsafe")
    return value


def _candidate_files(candidate_dir: Path) -> List[Path]:
    manifest = channel._verify_archived_candidate(candidate_dir)
    expected = {candidate.MANIFEST_NAME, *(str(item["path"]) for item in manifest["packages"])}
    paths: List[Path] = []
    for name in sorted(expected):
        path = candidate_dir / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size <= 0:
            raise DeltaError(f"candidate file is missing, empty, or unsafe: {path}")
        paths.append(path)
    return paths


def _snapshot(candidate_dir: Path) -> Dict[str, Any]:
    manifest = channel._verify_archived_candidate(candidate_dir)
    files = [
        {"path": path.name, "sha256": candidate._sha256_file(path), "size": path.stat().st_size}
        for path in _candidate_files(candidate_dir)
    ]
    manifest_entry = next(item for item in files if item["path"] == candidate.MANIFEST_NAME)
    return {
        "build_number": manifest["build_number"],
        "candidate_id": manifest["candidate_id"],
        "files": files,
        "manifest_sha256": manifest_entry["sha256"],
        "product_name": manifest["product_name"],
        "release_channel": manifest["release_channel"],
        "version": manifest["version"],
    }


def _chunks(path: Path, chunk_size: int) -> Iterator[Tuple[int, bytes, str]]:
    offset = 0
    with path.open("rb") as handle:
        while True:
            data = handle.read(chunk_size)
            if not data:
                return
            yield offset, data, candidate._sha256_bytes(data)
            offset += len(data)


def _file_role(name: str) -> str:
    if name == candidate.MANIFEST_NAME:
        return name
    marker = "-unsigned-"
    if marker not in name:
        return name
    return name.split(marker, 1)[1]


def _source_chunk_index(
    source_dir: Path, snapshot: Mapping[str, Any], chunk_size: int
) -> Dict[str, List[Tuple[bytes, str, int, int, str]]]:
    index: Dict[str, List[Tuple[bytes, str, int, int, str]]] = {}
    for file_entry in snapshot["files"]:
        path = source_dir / str(file_entry["path"])
        role = _file_role(path.name)
        if role in index:
            raise DeltaError(f"source candidate file role is duplicated: {role}")
        locations: List[Tuple[bytes, str, int, int, str]] = []
        for offset, data, digest in _chunks(path, chunk_size):
            if len(data) < ANCHOR_SIZE:
                continue
            locations.append(
                (data[:ANCHOR_SIZE], path.name, offset, len(data), digest)
            )
        index[role] = locations
    return index


def _target_source_matches(
    target_data: bytes,
    source_chunks: Sequence[Tuple[bytes, str, int, int, str]],
    chunk_size: int,
) -> List[Tuple[int, int, str, int, str]]:
    if not source_chunks or len(target_data) < ANCHOR_SIZE:
        return []
    selected: List[Tuple[int, int, str, int, str]] = []
    consumed_until = 0
    current_shift = 0
    consecutive_misses = 0
    for anchor, source_name, source_offset, size, digest in source_chunks:
        predicted = source_offset + current_shift
        search_radius = min(
            MAX_CHUNK_SIZE * 4,
            chunk_size * (4 + min(consecutive_misses, 12)),
        )
        search_start = max(consumed_until, predicted - search_radius)
        search_end = min(
            len(target_data),
            predicted + search_radius + size,
        )
        target_offset = target_data.find(anchor, search_start, search_end)
        matched = False
        while target_offset >= 0:
            if (
                target_offset + size <= len(target_data)
                and candidate._sha256_bytes(
                    target_data[target_offset : target_offset + size]
                )
                == digest
            ):
                selected.append(
                    (target_offset, size, source_name, source_offset, digest)
                )
                consumed_until = target_offset + size
                current_shift = target_offset - source_offset
                consecutive_misses = 0
                matched = True
                break
            target_offset = target_data.find(
                anchor, target_offset + 1, search_end
            )
        if not matched:
            consecutive_misses += 1
    return selected


def _literal_chunks(
    target_path: Path,
    target_data: bytes,
    start: int,
    end: int,
    chunk_size: int,
    blob_locations: Dict[str, Tuple[Path, int, int]],
) -> Tuple[List[Dict[str, Any]], int]:
    chunks: List[Dict[str, Any]] = []
    literal_bytes = 0
    offset = start
    while offset < end:
        size = min(chunk_size, end - offset)
        data = target_data[offset : offset + size]
        digest = candidate._sha256_bytes(data)
        existing = blob_locations.get(digest)
        location = (target_path, offset, size)
        if existing is not None and existing[2] != size:
            raise DeltaError("SHA-256 blob collision has inconsistent sizes")
        blob_locations.setdefault(digest, location)
        chunks.append(
            {
                "kind": "blob",
                "path": f"blobs/{digest}",
                "sha256": digest,
                "size": size,
            }
        )
        literal_bytes += size
        offset += size
    return chunks, literal_bytes


def _delta_value(
    source_dir: Path, target_dir: Path, chunk_size: int
) -> Tuple[Dict[str, Any], Dict[str, Tuple[Path, int, int]]]:
    if chunk_size < MIN_CHUNK_SIZE or chunk_size > MAX_CHUNK_SIZE or chunk_size & (chunk_size - 1):
        raise DeltaError(
            f"chunk size must be a power of two between {MIN_CHUNK_SIZE} and {MAX_CHUNK_SIZE}"
        )
    source = _snapshot(source_dir)
    target = _snapshot(target_dir)
    if source["candidate_id"] == target["candidate_id"]:
        raise DeltaError("source and target candidate IDs must differ")
    for key in ("product_name", "release_channel"):
        if source[key] != target[key]:
            raise DeltaError(f"source and target {key} differ")
    if int(target["build_number"]) <= int(source["build_number"]):
        raise DeltaError("target build number must be greater than source build number")

    source_chunks = _source_chunk_index(source_dir, source, chunk_size)
    blob_locations: Dict[str, Tuple[Path, int, int]] = {}
    file_recipes: List[Dict[str, Any]] = []
    reused_bytes = 0
    literal_bytes = 0
    for target_entry in target["files"]:
        target_path = target_dir / str(target_entry["path"])
        target_data = target_path.read_bytes()
        recipe_chunks: List[Dict[str, Any]] = []
        target_offset = 0
        role = _file_role(target_path.name)
        for match_offset, size, source_name, source_offset, digest in _target_source_matches(
            target_data, source_chunks.get(role, []), chunk_size
        ):
            literal_chunks, literal_count = _literal_chunks(
                target_path,
                target_data,
                target_offset,
                match_offset,
                chunk_size,
                blob_locations,
            )
            recipe_chunks.extend(literal_chunks)
            literal_bytes += literal_count
            recipe_chunks.append(
                {
                    "kind": "source",
                    "offset": source_offset,
                    "path": source_name,
                    "sha256": digest,
                    "size": size,
                }
            )
            reused_bytes += size
            target_offset = match_offset + size
        literal_chunks, literal_count = _literal_chunks(
            target_path,
            target_data,
            target_offset,
            len(target_data),
            chunk_size,
            blob_locations,
        )
        recipe_chunks.extend(literal_chunks)
        literal_bytes += literal_count
        file_recipes.append(
            {
                "chunks": recipe_chunks,
                "path": target_entry["path"],
                "sha256": target_entry["sha256"],
                "size": target_entry["size"],
            }
        )
    target_bytes = sum(int(item["size"]) for item in target["files"])
    unique_blob_bytes = sum(location[2] for location in blob_locations.values())
    value = {
        "chunk_size": chunk_size,
        "files": file_recipes,
        "format": FORMAT,
        "schema_version": 1,
        "source": source,
        "stats": {
            "literal_bytes": literal_bytes,
            "reused_bytes": reused_bytes,
            "target_bytes": target_bytes,
            "unique_blob_bytes": unique_blob_bytes,
        },
        "target": target,
        "unsigned": True,
    }
    return value, blob_locations


def _read_at(path: Path, offset: int, size: int) -> bytes:
    with path.open("rb") as handle:
        handle.seek(offset)
        data = handle.read(size)
    if len(data) != size:
        raise DeltaError(f"short read from {path.name} at {offset}")
    return data


def create_delta(
    source_dir: Path, target_dir: Path, output_path: Path, chunk_size: int = DEFAULT_CHUNK_SIZE
) -> Dict[str, Any]:
    value, blobs = _delta_value(source_dir, target_dir, chunk_size)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.is_symlink() or (output_path.exists() and not output_path.is_file()):
        raise DeltaError(f"delta output path is unsafe: {output_path}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output_path.name}.", dir=output_path.parent)
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary_path, "w", allowZip64=True) as archive:
            archive.writestr(candidate._archive_info(MANIFEST_NAME), candidate._canonical_json(value))
            for digest, (path, offset, size) in sorted(blobs.items()):
                data = _read_at(path, offset, size)
                if candidate._sha256_bytes(data) != digest:
                    raise DeltaError(f"target changed while creating blob {digest}")
                archive.writestr(candidate._archive_info(f"blobs/{digest}"), data)
        os.replace(temporary_path, output_path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()
    verify_delta(source_dir, output_path)
    return value


def _validate_snapshot(value: Any, context: str) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise DeltaError(f"{context} snapshot must be an object")
    _exact_keys(value, SNAPSHOT_KEYS, f"{context} snapshot")
    candidate_id = value.get("candidate_id")
    if not isinstance(candidate_id, str) or candidate.SAFE_TOKEN_RE.fullmatch(candidate_id) is None:
        raise DeltaError(f"{context} candidate ID is unsafe")
    version = value.get("version")
    if not isinstance(version, str) or candidate.SEMVER_RE.fullmatch(version) is None:
        raise DeltaError(f"{context} version is invalid")
    _positive_int(value.get("build_number"), f"{context} build number")
    for key in ("product_name", "release_channel"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise DeltaError(f"{context} {key} is invalid")
    files = value.get("files")
    if not isinstance(files, list) or not files:
        raise DeltaError(f"{context} files are invalid")
    seen: set[str] = set()
    normalized: List[Dict[str, Any]] = []
    for entry in files:
        if not isinstance(entry, dict):
            raise DeltaError(f"{context} file entry must be an object")
        _exact_keys(entry, SNAPSHOT_FILE_KEYS, f"{context} file")
        name = _safe_flat_name(entry.get("path"), f"{context} file path")
        if name in seen:
            raise DeltaError(f"{context} file path is duplicated: {name}")
        seen.add(name)
        normalized.append(
            {
                "path": name,
                "sha256": _sha256(entry.get("sha256"), f"{context} file {name}"),
                "size": _positive_int(entry.get("size"), f"{context} file {name} size"),
            }
        )
    if [item["path"] for item in normalized] != sorted(seen):
        raise DeltaError(f"{context} files are not in deterministic order")
    if candidate.MANIFEST_NAME not in seen:
        raise DeltaError(f"{context} release manifest is missing")
    manifest_hash = _sha256(value.get("manifest_sha256"), f"{context} manifest")
    manifest_entry = next(item for item in normalized if item["path"] == candidate.MANIFEST_NAME)
    if manifest_entry["sha256"] != manifest_hash:
        raise DeltaError(f"{context} manifest hash differs from its file snapshot")
    return dict(value)


def _zip_manifest(archive: zipfile.ZipFile) -> Dict[str, Any]:
    infos = archive.infolist()
    names = [info.filename for info in infos]
    if len(names) != len(set(names)):
        raise DeltaError("delta archive contains duplicate members")
    if MANIFEST_NAME not in names:
        raise DeltaError("delta manifest is missing")
    for info in infos:
        path = PurePosixPath(info.filename)
        if path.is_absolute() or ".." in path.parts or "\\" in info.filename or info.is_dir():
            raise DeltaError(f"delta archive member is unsafe: {info.filename}")
        if info.compress_type != zipfile.ZIP_STORED:
            raise DeltaError(f"delta archive member must be stored: {info.filename}")
        mode = info.external_attr >> 16
        if stat.S_IFMT(mode) != stat.S_IFREG or stat.S_IMODE(mode) != 0o644:
            raise DeltaError(f"delta archive member permissions differ: {info.filename}")
    manifest_info = archive.getinfo(MANIFEST_NAME)
    if manifest_info.file_size <= 0 or manifest_info.file_size > MAX_MANIFEST_SIZE:
        raise DeltaError("delta manifest size is invalid")
    try:
        raw = archive.read(manifest_info)
        value = json.loads(raw)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        raise DeltaError(f"cannot read delta manifest: {exc}") from exc
    if not isinstance(value, dict) or raw != candidate._canonical_json(value):
        raise DeltaError("delta manifest must be a canonical JSON object")
    return value


def _piece_bytes(
    archive: zipfile.ZipFile,
    source_dir: Path,
    source_files: Mapping[str, Mapping[str, Any]],
    chunk: Mapping[str, Any],
) -> bytes:
    size = int(chunk["size"])
    digest = str(chunk["sha256"])
    if chunk["kind"] == "source":
        source_name = str(chunk["path"])
        source_entry = source_files[source_name]
        offset = int(chunk["offset"])
        if offset + size > int(source_entry["size"]):
            raise DeltaError(f"source chunk exceeds {source_name}")
        data = _read_at(source_dir / source_name, offset, size)
    else:
        try:
            data = archive.read(str(chunk["path"]))
        except (KeyError, OSError, zipfile.BadZipFile) as exc:
            raise DeltaError(f"cannot read literal blob {chunk['path']}: {exc}") from exc
        if len(data) != size:
            raise DeltaError(f"literal blob size differs: {chunk['path']}")
    if candidate._sha256_bytes(data) != digest:
        raise DeltaError(f"delta chunk hash mismatch: {chunk['path']}")
    return data


def _validated_delta(
    source_dir: Path, delta_path: Path
) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    if delta_path.is_symlink() or not delta_path.is_file() or delta_path.stat().st_size <= 0:
        raise DeltaError(f"delta bundle is missing, empty, or unsafe: {delta_path}")
    try:
        archive = zipfile.ZipFile(delta_path, "r")
    except (OSError, zipfile.BadZipFile) as exc:
        raise DeltaError(f"cannot open delta bundle: {exc}") from exc
    with archive:
        value = _zip_manifest(archive)
        _exact_keys(value, ROOT_KEYS, "delta manifest")
        if value.get("schema_version") != 1 or value.get("format") != FORMAT:
            raise DeltaError("delta schema or format differs")
        if value.get("unsigned") is not True:
            raise DeltaError("delta bundle must remain explicitly unsigned")
        chunk_size = _positive_int(value.get("chunk_size"), "delta chunk size")
        if (
            chunk_size < MIN_CHUNK_SIZE
            or chunk_size > MAX_CHUNK_SIZE
            or chunk_size & (chunk_size - 1)
        ):
            raise DeltaError("delta chunk size is outside the supported power-of-two range")
        source = _validate_snapshot(value.get("source"), "source")
        target = _validate_snapshot(value.get("target"), "target")
        actual_source = _snapshot(source_dir)
        if source != actual_source:
            raise DeltaError("source candidate differs from the delta snapshot")
        if source["candidate_id"] == target["candidate_id"]:
            raise DeltaError("source and target candidate IDs must differ")
        for key in ("product_name", "release_channel"):
            if source[key] != target[key]:
                raise DeltaError(f"source and target {key} differ")
        if int(target["build_number"]) <= int(source["build_number"]):
            raise DeltaError("target build number must be greater than source build number")

        source_files = {str(item["path"]): item for item in source["files"]}
        target_files = {str(item["path"]): item for item in target["files"]}
        recipes = value.get("files")
        if not isinstance(recipes, list) or not recipes:
            raise DeltaError("delta file recipes are invalid")
        recipe_names: List[str] = []
        referenced_blobs: set[str] = set()
        reused_bytes = 0
        literal_bytes = 0
        normalized_recipes: List[Dict[str, Any]] = []
        for recipe in recipes:
            if not isinstance(recipe, dict):
                raise DeltaError("delta file recipe must be an object")
            _exact_keys(recipe, FILE_KEYS, "delta file recipe")
            name = _safe_flat_name(recipe.get("path"), "delta target path")
            if name in recipe_names or name not in target_files:
                raise DeltaError(f"delta target path is duplicate or unknown: {name}")
            recipe_names.append(name)
            target_entry = target_files[name]
            for key in ("sha256", "size"):
                if recipe.get(key) != target_entry[key]:
                    raise DeltaError(f"delta target {name} {key} differs from its snapshot")
            chunks = recipe.get("chunks")
            if not isinstance(chunks, list) or not chunks:
                raise DeltaError(f"delta target {name} has no chunks")
            total_size = 0
            normalized_chunks: List[Dict[str, Any]] = []
            for chunk in chunks:
                if not isinstance(chunk, dict) or chunk.get("kind") not in ("source", "blob"):
                    raise DeltaError(f"delta target {name} has an invalid chunk")
                kind = str(chunk["kind"])
                _exact_keys(
                    chunk,
                    SOURCE_CHUNK_KEYS if kind == "source" else BLOB_CHUNK_KEYS,
                    f"delta {kind} chunk",
                )
                size = _positive_int(chunk.get("size"), f"delta {kind} chunk size")
                if size > chunk_size:
                    raise DeltaError(f"delta {kind} chunk exceeds chunk_size")
                digest = _sha256(chunk.get("sha256"), f"delta {kind} chunk")
                if kind == "source":
                    source_name = _safe_flat_name(chunk.get("path"), "delta source chunk path")
                    if source_name not in source_files:
                        raise DeltaError(f"delta source chunk file is unknown: {source_name}")
                    offset = _positive_int(chunk.get("offset"), "delta source offset", allow_zero=True)
                    if offset % chunk_size != 0:
                        raise DeltaError("delta source chunk offset is not aligned")
                    if offset + size > int(source_files[source_name]["size"]):
                        raise DeltaError(f"delta source chunk exceeds {source_name}")
                    reused_bytes += size
                else:
                    blob_path = chunk.get("path")
                    if blob_path != f"blobs/{digest}":
                        raise DeltaError("delta literal blob path differs from its digest")
                    referenced_blobs.add(str(blob_path))
                    literal_bytes += size
                total_size += size
                normalized_chunks.append(dict(chunk))
            if total_size != int(target_entry["size"]):
                raise DeltaError(f"delta target {name} reconstructed size differs")
            normalized_recipes.append(dict(recipe))
        if recipe_names != sorted(target_files) or set(recipe_names) != set(target_files):
            raise DeltaError("delta recipes do not exactly cover target files in sorted order")

        archive_names = {info.filename for info in archive.infolist()}
        if archive_names != {MANIFEST_NAME, *referenced_blobs}:
            raise DeltaError("delta archive members differ from referenced literal blobs")
        blob_sizes: Dict[str, int] = {}
        for recipe in normalized_recipes:
            for chunk in recipe["chunks"]:
                if chunk["kind"] != "blob":
                    continue
                path = str(chunk["path"])
                size = int(chunk["size"])
                previous = blob_sizes.setdefault(path, size)
                if previous != size or archive.getinfo(path).file_size != size:
                    raise DeltaError(f"delta literal blob size contract differs: {path}")

        stats_value = value.get("stats")
        if not isinstance(stats_value, dict):
            raise DeltaError("delta stats must be an object")
        _exact_keys(stats_value, STATS_KEYS, "delta stats")
        expected_stats = {
            "literal_bytes": literal_bytes,
            "reused_bytes": reused_bytes,
            "target_bytes": sum(int(item["size"]) for item in target["files"]),
            "unique_blob_bytes": sum(blob_sizes.values()),
        }
        if stats_value != expected_stats or reused_bytes + literal_bytes != expected_stats["target_bytes"]:
            raise DeltaError("delta byte statistics differ from its recipes")

        reconstructed_manifest: bytes | None = None
        for recipe in normalized_recipes:
            digest = hashlib.sha256()
            manifest_bytes = bytearray() if recipe["path"] == candidate.MANIFEST_NAME else None
            for chunk in recipe["chunks"]:
                data = _piece_bytes(archive, source_dir, source_files, chunk)
                digest.update(data)
                if manifest_bytes is not None:
                    manifest_bytes.extend(data)
            if digest.hexdigest() != recipe["sha256"]:
                raise DeltaError(f"reconstructed target hash differs: {recipe['path']}")
            if manifest_bytes is not None:
                reconstructed_manifest = bytes(manifest_bytes)
        if reconstructed_manifest is None or len(reconstructed_manifest) > MAX_MANIFEST_SIZE:
            raise DeltaError("reconstructed release manifest is missing or oversized")
        try:
            release_manifest = json.loads(reconstructed_manifest)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise DeltaError(f"reconstructed release manifest is invalid: {exc}") from exc
        if not isinstance(release_manifest, dict) or reconstructed_manifest != candidate._canonical_json(release_manifest):
            raise DeltaError("reconstructed release manifest is not canonical JSON")
        identity = {
            "build_number": release_manifest.get("build_number"),
            "candidate_id": release_manifest.get("candidate_id"),
            "product_name": release_manifest.get("product_name"),
            "release_channel": release_manifest.get("release_channel"),
            "version": release_manifest.get("version"),
        }
        for key, expected in identity.items():
            if target.get(key) != expected:
                raise DeltaError(f"reconstructed release manifest {key} differs from target")
        return value, normalized_recipes


def verify_delta(source_dir: Path, delta_path: Path) -> Dict[str, Any]:
    value, _ = _validated_delta(source_dir, delta_path)
    return value


def apply_delta(source_dir: Path, delta_path: Path, output_dir: Path) -> Dict[str, Any]:
    value, recipes = _validated_delta(source_dir, delta_path)
    if output_dir.exists() or output_dir.is_symlink():
        raise DeltaError(f"delta output candidate already exists or is unsafe: {output_dir}")
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    staging_parent = Path(tempfile.mkdtemp(prefix=f".{output_dir.name}.", dir=output_dir.parent))
    staging = staging_parent / output_dir.name
    try:
        staging.mkdir()
        source_files = {str(item["path"]): item for item in value["source"]["files"]}
        with zipfile.ZipFile(delta_path, "r") as archive:
            for recipe in recipes:
                output = staging / str(recipe["path"])
                digest = hashlib.sha256()
                with output.open("wb") as handle:
                    for chunk in recipe["chunks"]:
                        data = _piece_bytes(archive, source_dir, source_files, chunk)
                        handle.write(data)
                        digest.update(data)
                    handle.flush()
                    os.fsync(handle.fileno())
                if output.stat().st_size != recipe["size"] or digest.hexdigest() != recipe["sha256"]:
                    raise DeltaError(f"applied target differs: {recipe['path']}")
        manifest = channel._verify_archived_candidate(staging)
        if manifest["candidate_id"] != value["target"]["candidate_id"]:
            raise DeltaError("applied candidate identity differs from delta target")
        os.replace(staging, output_dir)
    finally:
        if staging_parent.exists():
            shutil.rmtree(staging_parent)
    channel._verify_archived_candidate(output_dir)
    return value


def _advance_fixture_contract(
    fixture_root: Path, fixture_metadata: Path, base_metadata: Mapping[str, Any]
) -> None:
    next_version = "9.8.7-alpha.2"
    next_build = int(base_metadata["build_number"]) + 1
    project_path = fixture_root / "project.godot"
    project_path.write_text(
        project_path.read_text(encoding="utf-8").replace(
            f'config/version="{base_metadata["version"]}"',
            f'config/version="{next_version}"',
            1,
        ),
        encoding="utf-8",
    )
    old_core = str(base_metadata["version"]).split("+", 1)[0].split("-", 1)[0]
    next_core = next_version.split("+", 1)[0].split("-", 1)[0]
    export_path = fixture_root / "export_presets.cfg"
    export_text = export_path.read_text(encoding="utf-8")
    replacements = {
        f'application/file_version="{old_core}.{base_metadata["build_number"]}"': f'application/file_version="{next_core}.{next_build}"',
        f'application/product_version="{old_core}.{base_metadata["build_number"]}"': f'application/product_version="{next_core}.{next_build}"',
        f'application/short_version="{old_core}"': f'application/short_version="{next_core}"',
        f'application/version="{base_metadata["build_number"]}"': f'application/version="{next_build}"',
    }
    for source, replacement in replacements.items():
        if export_text.count(source) != 1:
            raise DeltaError(f"fixture version source differs: {source}")
        export_text = export_text.replace(source, replacement, 1)
    export_path.write_text(export_text, encoding="utf-8")
    metadata = json.loads(fixture_metadata.read_text(encoding="utf-8"))
    metadata["version"] = next_version
    metadata["build_number"] = next_build
    fixture_metadata.write_bytes(candidate._canonical_json(metadata))


def _fixture_candidate(
    fixture_root: Path,
    fixture_metadata: Path,
    build_root: Path,
    dist_root: Path,
    insertion: bytes = b"",
) -> Path:
    _, presets = candidate.load_and_validate_config(fixture_root, fixture_metadata)
    candidate._create_fake_exports(build_root, presets)
    for index, preset in enumerate(presets):
        path = candidate._artifact_path(build_root, preset)
        payload = b"".join(
            hashlib.sha256(f"fixture-{index}-{block}".encode("ascii")).digest()
            for block in range(16384)
        )
        with path.open("ab") as handle:
            handle.write(insertion)
            handle.write(payload)
    return candidate.package_candidate(fixture_root, fixture_metadata, build_root, dist_root).parent


def _rewrite_first_blob(delta_path: Path) -> None:
    replacement = delta_path.with_suffix(".tampered")
    with zipfile.ZipFile(delta_path, "r") as source, zipfile.ZipFile(replacement, "w", allowZip64=True) as target:
        changed = False
        for info in source.infolist():
            data = source.read(info)
            if info.filename.startswith("blobs/") and not changed:
                data = bytes([data[0] ^ 1]) + data[1:]
                changed = True
            target.writestr(candidate._archive_info(info.filename), data)
    if not changed:
        replacement.unlink()
        raise DeltaError("self-test delta did not contain a literal blob")
    os.replace(replacement, delta_path)


def run_self_test(root: Path, metadata_path: Path) -> None:
    base_metadata, _ = candidate.load_and_validate_config(root, metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_delta_test.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        first = _fixture_candidate(
            fixture_root, fixture_metadata, base / "build-a", base / "dist-a"
        )
        _advance_fixture_contract(fixture_root, fixture_metadata, base_metadata)
        second = _fixture_candidate(
            fixture_root,
            fixture_metadata,
            base / "build-b",
            base / "dist-b",
            b"shifted-metadata",
        )
        delta_a = base / "a.pvdelta"
        delta_b = base / "b.pvdelta"
        first_value = create_delta(first, second, delta_a, 4096)
        create_delta(first, second, delta_b, 4096)
        if delta_a.read_bytes() != delta_b.read_bytes():
            raise DeltaError("self-test delta creation is not byte-deterministic")
        if int(first_value["stats"]["reused_bytes"]) <= int(
            first_value["stats"]["target_bytes"]
        ) // 2:
            raise DeltaError("self-test delta did not resynchronize after shifted bytes")
        applied = base / second.name
        apply_delta(first, delta_a, applied)
        for expected in _candidate_files(second):
            actual = applied / expected.name
            if candidate._sha256_file(actual) != candidate._sha256_file(expected):
                raise DeltaError(f"self-test applied candidate differs: {expected.name}")

        original_delta = delta_a.read_bytes()
        _rewrite_first_blob(delta_a)
        try:
            verify_delta(first, delta_a)
        except DeltaError as exc:
            if "hash mismatch" not in str(exc):
                raise DeltaError(f"self-test rejected blob tamper for the wrong reason: {exc}") from exc
        else:
            raise DeltaError("self-test accepted a tampered literal blob")
        delta_a.write_bytes(original_delta)

        victim = _candidate_files(first)[0]
        original_source = victim.read_bytes()
        victim.write_bytes(original_source + b"tamper")
        try:
            verify_delta(first, delta_a)
        except candidate.ReleaseError:
            pass
        else:
            raise DeltaError("self-test accepted a modified source candidate")
        victim.write_bytes(original_source)
        verify_delta(first, delta_a)
    print(
        "RELEASE_DELTA_TEST_OK deterministic=ok source=bound target=reconstructed "
        "chunks=reused resync=shift-tolerant blob_tamper=blocked source_tamper=blocked "
        "apply=verified unsigned=explicit"
    )


def _resolve(root: Path, value: Path) -> Path:
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def _default_delta_path(root: Path, source_dir: Path, target_dir: Path) -> Path:
    return root / "dist" / "deltas" / f"{source_dir.name}--to--{target_dir.name}.pvdelta"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=ROOT / "release" / "release_metadata.json")
    subparsers = parser.add_subparsers(dest="command", required=True)
    create_parser = subparsers.add_parser("create")
    create_parser.add_argument("--source-candidate", type=Path, required=True)
    create_parser.add_argument("--target-candidate", type=Path, required=True)
    create_parser.add_argument("--delta", type=Path)
    create_parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--source-candidate", type=Path, required=True)
    verify_parser.add_argument("--delta", type=Path, required=True)
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--source-candidate", type=Path, required=True)
    apply_parser.add_argument("--delta", type=Path, required=True)
    apply_parser.add_argument("--output-dir", type=Path, required=True)
    subparsers.add_parser("self-test")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = _resolve(root, args.metadata)
    try:
        if args.command == "self-test":
            run_self_test(root, metadata_path)
        elif args.command == "create":
            source_dir = _resolve(root, args.source_candidate)
            target_dir = _resolve(root, args.target_candidate)
            delta_path = (
                _resolve(root, args.delta)
                if args.delta
                else _default_delta_path(root, source_dir, target_dir)
            )
            value = create_delta(source_dir, target_dir, delta_path, args.chunk_size)
            stats_value = value["stats"]
            print(
                f"RELEASE_DELTA_OK path={delta_path} source={value['source']['candidate_id']} "
                f"target={value['target']['candidate_id']} reused={stats_value['reused_bytes']} "
                f"literal={stats_value['literal_bytes']} transfer={stats_value['unique_blob_bytes']}"
            )
        elif args.command == "verify":
            value = verify_delta(
                _resolve(root, args.source_candidate), _resolve(root, args.delta)
            )
            print(
                f"RELEASE_DELTA_VERIFY_OK source={value['source']['candidate_id']} "
                f"target={value['target']['candidate_id']} transfer={value['stats']['unique_blob_bytes']}"
            )
        else:
            value = apply_delta(
                _resolve(root, args.source_candidate),
                _resolve(root, args.delta),
                _resolve(root, args.output_dir),
            )
            print(
                f"RELEASE_DELTA_APPLY_OK source={value['source']['candidate_id']} "
                f"target={value['target']['candidate_id']} output={args.output_dir}"
            )
    except (OSError, ValueError, zipfile.BadZipFile, candidate.ReleaseError) as exc:
        print(f"RELEASE_DELTA_FAILED {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
