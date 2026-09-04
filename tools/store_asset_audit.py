#!/usr/bin/env python3
"""Fail-closed audit for the deterministic Steam graphical-asset delivery set."""

from __future__ import annotations

import hashlib
import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DELIVERY = ROOT / "dist" / "store" / "steam"
MANIFEST = DELIVERY / "manifest.json"
SPEC_URL = "https://partner.steamgames.com/doc/store/assets"
RULES_URL = "https://partner.steamgames.com/doc/store/assets/rules"

EXPECTED = {
    "community/app_icon.jpg": (184, 184, "jpg", "app_icon", True),
    "community/shortcut_icon.png": (256, 256, "png", "shortcut_icon", True),
    "library/library_capsule.png": (600, 900, "png", "library_capsule", True),
    "library/library_header.png": (920, 430, "png", "library_header", True),
    "library/library_hero.png": (3840, 1240, "png", "library_hero", False),
    "logo/library_logo.png": (1280, 400, "png", "library_logo", True),
    "store/header_capsule.png": (920, 430, "png", "store_header", True),
    "store/main_capsule.png": (1232, 706, "png", "store_main", True),
    "store/page_background.png": (1438, 810, "png", "store_page_background", False),
    "store/small_capsule.png": (462, 174, "png", "store_small", True),
    "store/vertical_capsule.png": (748, 896, "png", "store_vertical", True),
}
SOURCE_MASTERS = {
    "assets/store/psychic_vector_store_landscape_v1.png": (
        1536,
        1024,
        "048d8e9713690436769c6ece6571e8be2cb6da3d81a0c3f264cea5992267ebf7",
    ),
    "assets/store/psychic_vector_store_portrait_v1.png": (
        1024,
        1536,
        "cdbcf10cf210b1ed968d9ccc062882f310e8b2bea5421798b97b6467cf5bcef4",
    ),
}


class AuditError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _png_info(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()[:33]
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise AuditError(f"{path}: invalid PNG signature or IHDR")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type in (4, 6)


def _jpeg_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        if handle.read(2) != b"\xff\xd8":
            raise AuditError(f"{path}: invalid JPEG signature")
        while True:
            prefix = handle.read(1)
            if not prefix:
                break
            if prefix != b"\xff":
                continue
            marker = handle.read(1)
            while marker == b"\xff":
                marker = handle.read(1)
            if marker in (b"\xd8", b"\xd9"):
                continue
            length_data = handle.read(2)
            if len(length_data) != 2:
                break
            length = struct.unpack(">H", length_data)[0]
            if marker and marker[0] in range(0xC0, 0xC4):
                payload = handle.read(5)
                if len(payload) != 5:
                    break
                height, width = struct.unpack(">HH", payload[1:5])
                return width, height
            handle.seek(length - 2, 1)
    raise AuditError(f"{path}: JPEG dimensions not found")


def _image_info(path: Path, image_format: str) -> tuple[int, int, bool]:
    if image_format == "png":
        return _png_info(path)
    width, height = _jpeg_size(path)
    return width, height, False


def _validate_source(source: dict) -> None:
    relative = source.get("path")
    expected_hash = source.get("sha256")
    if not isinstance(relative, str) or not relative or not isinstance(expected_hash, str):
        raise AuditError("manifest source_art entry is malformed")
    path = ROOT / relative
    if not path.is_file():
        raise AuditError(f"source art missing: {relative}")
    if _sha256(path) != expected_hash:
        raise AuditError(f"source art hash mismatch: {relative}")


def audit_sources() -> None:
    for relative, (width, height, expected_hash) in SOURCE_MASTERS.items():
        path = ROOT / relative
        if not path.is_file():
            raise AuditError(f"store source master is missing: {relative}")
        actual_width, actual_height, _ = _png_info(path)
        if (actual_width, actual_height) != (width, height):
            raise AuditError(f"store source dimensions drifted: {relative}")
        if _sha256(path) != expected_hash:
            raise AuditError(f"store source identity drifted: {relative}")
    builder = (ROOT / "tools" / "store_asset_builder.gd").read_text(encoding="utf-8")
    capture = (ROOT / "core" / "main.gd").read_text(encoding="utf-8")
    export_presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    documentation = (ROOT / "docs" / "STORE_ASSETS.md").read_text(encoding="utf-8")
    required_builder_fragments = [
        SPEC_URL,
        RULES_URL,
        "steam-graphical-assets-v1",
        "Vector2i(920, 430)",
        "Vector2i(462, 174)",
        "Vector2i(1232, 706)",
        "Vector2i(748, 896)",
        "Vector2i(600, 900)",
        "Vector2i(3840, 1240)",
        "Vector2i(1920, 1080)",
    ]
    for fragment in required_builder_fragments:
        if fragment not in builder:
            raise AuditError(f"store builder contract fragment is missing: {fragment}")
    if "--capture-store-sources" not in capture or capture.count("_boss.png\"") < 3:
        raise AuditError("six-scene English store capture route is incomplete")
    if export_presets.count("assets/store/*") != 3:
        raise AuditError("store source material must be excluded by every export preset")
    for url in (SPEC_URL, RULES_URL):
        if url not in documentation:
            raise AuditError(f"store documentation reference is missing: {url}")
    print("STORE_ASSET_SOURCE_AUDIT_OK masters=2 captures=6 profile=steam-graphical-assets-v1")


def audit() -> None:
    if not MANIFEST.is_file():
        raise AuditError("store asset manifest is missing; run the capture and builder commands")
    document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if document.get("schema_version") != 1 or document.get("platform") != "Steam":
        raise AuditError("manifest identity is invalid")
    if document.get("product") != "PSYCHIC VECTOR":
        raise AuditError("manifest product title is invalid")
    release_metadata = json.loads((ROOT / "release" / "release_metadata.json").read_text(encoding="utf-8"))
    expected_candidate = (
        f"{release_metadata['artifact_name']}-{release_metadata['version']}"
        f"-build.{release_metadata['build_number']}-"
        f"{'unsigned' if release_metadata['unsigned'] else 'signed'}"
    )
    if document.get("candidate_id") != expected_candidate:
        raise AuditError("manifest release-candidate identity is stale")
    if document.get("generation_profile") != "steam-graphical-assets-v1":
        raise AuditError("manifest generation profile is invalid")
    if document.get("generator") != "tools/store_asset_builder.gd":
        raise AuditError("manifest generator is invalid")
    if document.get("official_spec_url") != SPEC_URL or document.get("official_rules_url") != RULES_URL:
        raise AuditError("manifest official documentation references drifted")
    rules = document.get("content_rules")
    if not isinstance(rules, dict) or set(rules) != {"capsules", "library_hero", "library_logo", "screenshots"}:
        raise AuditError("content-rule declaration is incomplete")
    sources = document.get("source_art")
    if not isinstance(sources, list) or len(sources) != 9:
        raise AuditError("manifest must bind three key-art sources and six gameplay captures")
    for source in sources:
        _validate_source(source)

    records = document.get("outputs")
    if not isinstance(records, list):
        raise AuditError("manifest outputs must be an array")
    by_path = {record.get("path"): record for record in records if isinstance(record, dict)}
    if len(by_path) != len(records):
        raise AuditError("manifest output paths must be unique strings")
    screenshot_paths = sorted(path for path in by_path if isinstance(path, str) and path.startswith("screenshots/"))
    if len(screenshot_paths) < 5:
        raise AuditError("Steam delivery requires at least five gameplay screenshots")
    expected_paths = set(EXPECTED) | set(screenshot_paths)
    if set(by_path) != expected_paths:
        missing = sorted(expected_paths - set(by_path))
        extra = sorted(set(by_path) - expected_paths)
        raise AuditError(f"output set mismatch: missing={missing} extra={extra}")

    for relative, record in sorted(by_path.items()):
        if relative in EXPECTED:
            width, height, image_format, role, logo_present = EXPECTED[relative]
            expected_locale = "neutral"
        else:
            width, height, image_format, role, logo_present = (1920, 1080, "png", "gameplay_screenshot", False)
            expected_locale = "en"
        if (
            record.get("width") != width
            or record.get("height") != height
            or record.get("format") != image_format
            or record.get("role") != role
            or record.get("logo_present") is not logo_present
            or record.get("locale") != expected_locale
        ):
            raise AuditError(f"manifest contract mismatch: {relative}")
        path = DELIVERY / relative
        if not path.is_file() or path.is_symlink():
            raise AuditError(f"output missing or unsafe: {relative}")
        if path.stat().st_size != record.get("size") or _sha256(path) != record.get("sha256"):
            raise AuditError(f"output byte identity mismatch: {relative}")
        actual_width, actual_height, has_alpha = _image_info(path, image_format)
        if (actual_width, actual_height) != (width, height):
            raise AuditError(f"output dimensions mismatch: {relative}")
        if role == "library_logo" and not has_alpha:
            raise AuditError("library logo must retain a transparent alpha channel")

    print(
        "STORE_ASSET_AUDIT_OK "
        f"platform=Steam outputs={len(records)} screenshots={len(screenshot_paths)} "
        "capsules=4 library=4 icons=2"
    )


def main() -> int:
    try:
        if len(sys.argv) == 2 and sys.argv[1] == "source":
            audit_sources()
        elif len(sys.argv) == 1:
            audit()
        else:
            raise AuditError("usage: store_asset_audit.py [source]")
    except (AuditError, json.JSONDecodeError, OSError, ValueError) as exc:
        print(f"STORE_ASSET_AUDIT_FAILED {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
