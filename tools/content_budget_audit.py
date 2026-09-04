#!/usr/bin/env python3
"""Enforce machine-readable source-art and runtime-source production budgets."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import struct
import sys
from typing import Any, Iterable
import zlib


ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = ROOT / "resources" / "content_budgets.json"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
REFERENCE_SUFFIXES = {".gd", ".tscn", ".tres"}
REFERENCE_ROOTS = (
    "autoload", "audio", "boss", "bullet", "core", "effects", "enemy",
    "pattern", "player", "release", "resources", "scenes", "stage", "ui",
)
RUNTIME_PAYLOAD_ROOTS = REFERENCE_ROOTS + ("shaders",)
IGNORED_GENERATED_SUFFIXES = {".import", ".uid"}
ASSET_REFERENCE_RE = re.compile(r"res://assets/[a-z0-9_./-]+\.png")
EXPECTED_GLOBAL = {
    "min_files": 33,
    "max_files": 64,
    "max_source_bytes": 100663296,
    "max_decoded_rgba_bytes": 301989888,
    "min_width": 512,
    "min_height": 512,
    "max_width": 2048,
    "max_height": 2048,
    "max_pixels_per_texture": 3145728,
    "max_source_bytes_per_texture": 6291456,
}
EXPECTED_TEXTURE_CATEGORIES = {
    "backgrounds": ("assets/backgrounds", 1, 6, 12582912, 50331648),
    "bosses": ("assets/bosses", 12, 24, 50331648, 134217728),
    "characters": ("assets/characters", 6, 12, 25165824, 67108864),
    "enemies": ("assets/enemies", 14, 32, 50331648, 167772160),
}
SCRIPT_ROOTS = [
    "autoload", "audio", "boss", "bullet", "core", "effects", "enemy",
    "pattern", "player", "resources", "stage", "ui",
]
EXPECTED_SOURCE_CATEGORIES = {
    "scripts": (SCRIPT_ROOTS, [".gd"], 51, 128, 2097152, 262144),
    "scenes": (["scenes"], [".tscn"], 4, 32, 262144, 131072),
    "data": (["resources", "release"], [".json", ".tres"], 34, 128, 524288, 131072),
    "shaders": (["shaders"], [".gdshader"], 5, 16, 131072, 32768),
}
EXPECTED_RULES = {
    "texture_name_pattern": r"^[a-z0-9]+(?:_[a-z0-9]+)*\.png$",
    "runtime_source_name_pattern": r"^[a-z0-9]+(?:_[a-z0-9]+)*\.(?:gd|tscn|tres|json|gdshader)$",
    "combat_sheet_suffix": "_combat_sheet.png",
    "combat_sheet_alpha_required": True,
    "runtime_texture_reference_required": True,
    "png_bit_depth": 8,
    "png_interlace": 0,
}


class BudgetError(RuntimeError):
    pass


def _load_policy() -> dict[str, Any]:
    try:
        policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BudgetError(f"content budget policy is unreadable: {exc}") from exc
    if not isinstance(policy, dict):
        raise BudgetError("content budget policy root must be an object")
    return policy


def _objects_by_id(value: Any, context: str) -> dict[str, dict[str, Any]]:
    if not isinstance(value, list):
        raise BudgetError(f"{context} must be an array")
    result: dict[str, dict[str, Any]] = {}
    for item in value:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str):
            raise BudgetError(f"every {context} entry must be an object with an id")
        item_id = item["id"]
        if item_id in result:
            raise BudgetError(f"duplicate {context} id: {item_id}")
        result[item_id] = item
    return result


def _audit_policy(policy: dict[str, Any]) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    if set(policy) != {
        "global_texture_budget", "product", "rules", "runtime_source_categories",
        "schema_version", "scope", "texture_categories",
    }:
        raise BudgetError("content budget policy fields differ from schema 1")
    if policy.get("schema_version") != 1 or policy.get("product") != "PSYCHIC VECTOR":
        raise BudgetError("content budget schema or product identity changed")
    if policy.get("scope") != "source_control_runtime_payload":
        raise BudgetError("content budget scope must remain source_control_runtime_payload")
    if policy.get("global_texture_budget") != EXPECTED_GLOBAL:
        raise BudgetError("global texture budget changed without updating its audited contract")
    if policy.get("rules") != EXPECTED_RULES:
        raise BudgetError("content budget rules changed without updating their audited contract")

    texture_categories = _objects_by_id(policy.get("texture_categories"), "texture_categories")
    if list(texture_categories) != list(EXPECTED_TEXTURE_CATEGORIES):
        raise BudgetError("texture category catalog or deterministic order changed")
    for category_id, expected in EXPECTED_TEXTURE_CATEGORIES.items():
        root, minimum, maximum, source_bytes, decoded_bytes = expected
        contract = {
            "id": category_id,
            "root": root,
            "min_files": minimum,
            "max_files": maximum,
            "max_source_bytes": source_bytes,
            "max_decoded_rgba_bytes": decoded_bytes,
        }
        if texture_categories[category_id] != contract:
            raise BudgetError(f"texture category contract changed: {category_id}")

    source_categories = _objects_by_id(
        policy.get("runtime_source_categories"), "runtime_source_categories"
    )
    if list(source_categories) != list(EXPECTED_SOURCE_CATEGORIES):
        raise BudgetError("runtime source category catalog or deterministic order changed")
    for category_id, expected in EXPECTED_SOURCE_CATEGORIES.items():
        roots, extensions, minimum, maximum, total_bytes, file_bytes = expected
        contract = {
            "id": category_id,
            "roots": roots,
            "extensions": extensions,
            "min_files": minimum,
            "max_files": maximum,
            "max_total_bytes": total_bytes,
            "max_file_bytes": file_bytes,
        }
        if source_categories[category_id] != contract:
            raise BudgetError(f"runtime source category contract changed: {category_id}")
    return texture_categories, source_categories


def _regular_files(root: Path, suffixes: set[str]) -> list[Path]:
    if not root.is_dir() or root.is_symlink():
        raise BudgetError(f"budget root is missing or unsafe: {root.relative_to(ROOT)}")
    files: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise BudgetError(f"runtime payload may not contain symlinks: {path.relative_to(ROOT)}")
        if path.is_file() and path.suffix in suffixes:
            files.append(path)
    return files


def _png_info(path: Path) -> tuple[int, int, int, int, int]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise BudgetError(f"texture is not a PNG file: {path.relative_to(ROOT)}")
    cursor = len(PNG_SIGNATURE)
    ihdr: bytes | None = None
    saw_idat = False
    saw_iend = False
    chunk_index = 0
    while cursor < len(data):
        if cursor + 12 > len(data):
            raise BudgetError(f"truncated PNG chunk: {path.relative_to(ROOT)}")
        length = struct.unpack(">I", data[cursor:cursor + 4])[0]
        chunk_type = data[cursor + 4:cursor + 8]
        payload_start = cursor + 8
        payload_end = payload_start + length
        crc_end = payload_end + 4
        if crc_end > len(data):
            raise BudgetError(f"truncated PNG payload: {path.relative_to(ROOT)}")
        stored_crc = struct.unpack(">I", data[payload_end:crc_end])[0]
        actual_crc = zlib.crc32(chunk_type + data[payload_start:payload_end]) & 0xFFFFFFFF
        if stored_crc != actual_crc:
            raise BudgetError(f"PNG CRC mismatch: {path.relative_to(ROOT)}")
        if chunk_index == 0 and chunk_type != b"IHDR":
            raise BudgetError(f"PNG IHDR is not first: {path.relative_to(ROOT)}")
        if chunk_type == b"IHDR":
            if ihdr is not None or length != 13:
                raise BudgetError(f"PNG IHDR is invalid: {path.relative_to(ROOT)}")
            ihdr = data[payload_start:payload_end]
        elif chunk_type == b"IDAT":
            saw_idat = True
        elif chunk_type == b"IEND":
            if length != 0 or crc_end != len(data):
                raise BudgetError(f"PNG IEND/trailing bytes are invalid: {path.relative_to(ROOT)}")
            saw_iend = True
        cursor = crc_end
        chunk_index += 1
    if ihdr is None or not saw_idat or not saw_iend:
        raise BudgetError(f"PNG is missing required chunks: {path.relative_to(ROOT)}")
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", ihdr
    )
    if width < 1 or height < 1 or compression != 0 or filtering != 0:
        raise BudgetError(f"PNG header is unsupported: {path.relative_to(ROOT)}")
    if color_type not in (2, 6):
        raise BudgetError(f"PNG must use RGB or RGBA color: {path.relative_to(ROOT)}")
    return width, height, bit_depth, color_type, interlace


def _audit_textures(
    categories: dict[str, dict[str, Any]], rules: dict[str, Any]
) -> tuple[list[Path], int, int]:
    global_budget = EXPECTED_GLOBAL
    name_pattern = re.compile(rules["texture_name_pattern"])
    all_textures: list[Path] = []
    hashes: dict[str, Path] = {}
    global_source_bytes = 0
    global_decoded_bytes = 0
    for category_id, contract in categories.items():
        category_root = ROOT / contract["root"]
        for path in sorted(category_root.rglob("*")):
            if path.is_symlink():
                raise BudgetError(f"asset category may not contain symlinks: {path.relative_to(ROOT)}")
            if path.is_file() and path.suffix not in (".png", ".import"):
                raise BudgetError(f"unbudgeted asset type: {path.relative_to(ROOT)}")
        textures = _regular_files(category_root, {".png"})
        count = len(textures)
        if not contract["min_files"] <= count <= contract["max_files"]:
            raise BudgetError(
                f"{category_id} texture count {count} is outside "
                f"{contract['min_files']}..{contract['max_files']}"
            )
        source_bytes = 0
        decoded_bytes = 0
        for path in textures:
            relative = path.relative_to(ROOT)
            if not name_pattern.fullmatch(path.name):
                raise BudgetError(f"texture name violates snake_case: {relative}")
            file_bytes = path.stat().st_size
            if file_bytes <= 0 or file_bytes > global_budget["max_source_bytes_per_texture"]:
                raise BudgetError(f"texture source-byte budget exceeded: {relative} ({file_bytes})")
            width, height, bit_depth, color_type, interlace = _png_info(path)
            if bit_depth != rules["png_bit_depth"] or interlace != rules["png_interlace"]:
                raise BudgetError(f"texture PNG encoding contract differs: {relative}")
            if not global_budget["min_width"] <= width <= global_budget["max_width"]:
                raise BudgetError(f"texture width budget exceeded: {relative} ({width})")
            if not global_budget["min_height"] <= height <= global_budget["max_height"]:
                raise BudgetError(f"texture height budget exceeded: {relative} ({height})")
            pixels = width * height
            if pixels > global_budget["max_pixels_per_texture"]:
                raise BudgetError(f"texture pixel budget exceeded: {relative} ({pixels})")
            if path.name.endswith(rules["combat_sheet_suffix"]) and color_type != 6:
                raise BudgetError(f"combat sheet must preserve an alpha channel: {relative}")
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest in hashes:
                raise BudgetError(
                    f"duplicate texture payloads: {hashes[digest].relative_to(ROOT)} and {relative}"
                )
            hashes[digest] = path
            source_bytes += file_bytes
            decoded_bytes += pixels * 4
        if source_bytes > contract["max_source_bytes"]:
            raise BudgetError(f"{category_id} source-byte budget exceeded: {source_bytes}")
        if decoded_bytes > contract["max_decoded_rgba_bytes"]:
            raise BudgetError(f"{category_id} decoded RGBA budget exceeded: {decoded_bytes}")
        all_textures.extend(textures)
        global_source_bytes += source_bytes
        global_decoded_bytes += decoded_bytes
    if not global_budget["min_files"] <= len(all_textures) <= global_budget["max_files"]:
        raise BudgetError(f"global texture count is outside budget: {len(all_textures)}")
    if global_source_bytes > global_budget["max_source_bytes"]:
        raise BudgetError(f"global texture source-byte budget exceeded: {global_source_bytes}")
    if global_decoded_bytes > global_budget["max_decoded_rgba_bytes"]:
        raise BudgetError(f"global decoded RGBA budget exceeded: {global_decoded_bytes}")
    return all_textures, global_source_bytes, global_decoded_bytes


def _audit_texture_references(textures: Iterable[Path]) -> int:
    references: set[str] = set()
    for root_name in REFERENCE_ROOTS:
        root = ROOT / root_name
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in REFERENCE_SUFFIXES:
                references.update(ASSET_REFERENCE_RE.findall(path.read_text(encoding="utf-8")))
    asset_paths = {f"res://{path.relative_to(ROOT).as_posix()}" for path in textures}
    missing = sorted(references - asset_paths)
    orphaned = sorted(asset_paths - references)
    if missing:
        raise BudgetError(f"runtime texture references are missing: {missing}")
    if orphaned:
        raise BudgetError(f"source textures are not referenced by runtime content: {orphaned}")
    return len(references)


def _audit_runtime_sources(
    categories: dict[str, dict[str, Any]], rules: dict[str, Any]
) -> dict[str, tuple[int, int]]:
    name_pattern = re.compile(rules["runtime_source_name_pattern"])
    seen: set[Path] = set()
    results: dict[str, tuple[int, int]] = {}
    for category_id, contract in categories.items():
        suffixes = set(contract["extensions"])
        files: list[Path] = []
        for root_name in contract["roots"]:
            files.extend(_regular_files(ROOT / root_name, suffixes))
        files = sorted(set(files))
        overlap = seen.intersection(files)
        if overlap:
            raise BudgetError(f"runtime source categories overlap at {sorted(overlap)[0]}")
        seen.update(files)
        count = len(files)
        if not contract["min_files"] <= count <= contract["max_files"]:
            raise BudgetError(
                f"{category_id} file count {count} is outside "
                f"{contract['min_files']}..{contract['max_files']}"
            )
        total_bytes = 0
        for path in files:
            relative = path.relative_to(ROOT)
            if not name_pattern.fullmatch(path.name):
                raise BudgetError(f"runtime source name violates snake_case: {relative}")
            file_bytes = path.stat().st_size
            if file_bytes <= 0 or file_bytes > contract["max_file_bytes"]:
                raise BudgetError(f"{category_id} per-file budget exceeded: {relative} ({file_bytes})")
            total_bytes += file_bytes
        if total_bytes > contract["max_total_bytes"]:
            raise BudgetError(f"{category_id} total-byte budget exceeded: {total_bytes}")
        results[category_id] = (count, total_bytes)
    for root_name in RUNTIME_PAYLOAD_ROOTS:
        payload_root = ROOT / root_name
        if not payload_root.is_dir() or payload_root.is_symlink():
            raise BudgetError(f"runtime payload root is missing or unsafe: {root_name}")
        for path in sorted(payload_root.rglob("*")):
            if path.is_symlink():
                raise BudgetError(f"runtime payload may not contain symlinks: {path.relative_to(ROOT)}")
            if not path.is_file() or path.suffix in IGNORED_GENERATED_SUFFIXES:
                continue
            if path not in seen:
                raise BudgetError(f"runtime payload file bypasses all budget categories: {path.relative_to(ROOT)}")
    return results


def main() -> int:
    try:
        policy = _load_policy()
        texture_categories, source_categories = _audit_policy(policy)
        textures, source_bytes, decoded_bytes = _audit_textures(
            texture_categories, policy["rules"]
        )
        referenced = _audit_texture_references(textures)
        source_results = _audit_runtime_sources(source_categories, policy["rules"])
    except (BudgetError, OSError, UnicodeDecodeError) as exc:
        print(f"CONTENT_BUDGET_AUDIT_FAILED {exc}", file=sys.stderr)
        return 1
    source_mib = source_bytes / (1024 * 1024)
    decoded_mib = decoded_bytes / (1024 * 1024)
    source_headroom = 100.0 * (1.0 - source_bytes / EXPECTED_GLOBAL["max_source_bytes"])
    print(
        "CONTENT_BUDGET_AUDIT_OK "
        f"textures={len(textures)} referenced={referenced} "
        f"source_mib={source_mib:.1f} decoded_rgba_mib={decoded_mib:.1f} "
        f"source_headroom={source_headroom:.1f}% "
        + " ".join(
            f"{category_id}={count}/{byte_count}B"
            for category_id, (count, byte_count) in source_results.items()
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
