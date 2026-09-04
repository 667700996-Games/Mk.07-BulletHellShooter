#!/usr/bin/env python3
"""Validate the native container and architecture contracts of desktop exports."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import stat
import struct
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Dict, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
MIN_ARTIFACT_BYTES = 1024 * 1024
MAX_MACOS_UNCOMPRESSED_BYTES = 768 * 1024 * 1024
PE_MACHINE_AMD64 = 0x8664
PE_OPTIONAL_MAGIC_64 = 0x020B
PE_SUBSYSTEM_WINDOWS_GUI = 2
ELF_MACHINE_X86_64 = 62
MACH_CPU_X86_64 = 0x01000007
MACH_CPU_ARM64 = 0x0100000C


class ArtifactError(RuntimeError):
    pass


def _load_metadata(path: Path) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactError(f"cannot load release metadata: {exc}") from exc
    if not isinstance(value, dict):
        raise ArtifactError("release metadata must be a JSON object")
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _artifact_paths(metadata: Mapping[str, Any], build_root: Path) -> Dict[str, Path]:
    presets = metadata.get("presets")
    if not isinstance(presets, list):
        raise ArtifactError("release metadata presets must be an array")
    paths: Dict[str, Path] = {}
    for preset in presets:
        if not isinstance(preset, dict):
            raise ArtifactError("release metadata preset must be an object")
        name = preset.get("name")
        raw_path = preset.get("export_path")
        if not isinstance(name, str) or not isinstance(raw_path, str):
            raise ArtifactError("release preset name/export_path must be strings")
        relative = PurePosixPath(raw_path)
        if relative.is_absolute() or not relative.parts or relative.parts[0] != "build" or ".." in relative.parts:
            raise ArtifactError(f"unsafe export path in release metadata: {raw_path!r}")
        paths[name] = build_root.joinpath(*relative.parts[1:])
    expected = {"Windows Desktop", "macOS", "Linux"}
    if set(paths) != expected:
        raise ArtifactError(f"desktop export set differs: {sorted(paths)}")
    return paths


def _require_regular_artifact(path: Path, label: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise ArtifactError(f"{label} artifact is missing or unsafe: {path}")
    if path.stat().st_size < MIN_ARTIFACT_BYTES:
        raise ArtifactError(f"{label} artifact is implausibly small: {path.stat().st_size} bytes")


def _audit_windows(path: Path) -> None:
    _require_regular_artifact(path, "Windows")
    with path.open("rb") as source:
        dos = source.read(64)
        if len(dos) != 64 or dos[:2] != b"MZ":
            raise ArtifactError("Windows artifact does not have an MZ header")
        pe_offset = struct.unpack_from("<I", dos, 0x3C)[0]
        if pe_offset < 64 or pe_offset > 16 * 1024 * 1024:
            raise ArtifactError(f"Windows PE header offset is invalid: {pe_offset}")
        source.seek(pe_offset)
        header = source.read(24 + 96)
    if len(header) < 24 + 70 or header[:4] != b"PE\0\0":
        raise ArtifactError("Windows artifact does not have a complete PE header")
    machine = struct.unpack_from("<H", header, 4)[0]
    optional_size = struct.unpack_from("<H", header, 20)[0]
    optional_magic = struct.unpack_from("<H", header, 24)[0]
    subsystem = struct.unpack_from("<H", header, 24 + 68)[0]
    if machine != PE_MACHINE_AMD64 or optional_magic != PE_OPTIONAL_MAGIC_64:
        raise ArtifactError(
            f"Windows artifact is not PE32+ x86_64: machine=0x{machine:04x} magic=0x{optional_magic:04x}"
        )
    if optional_size < 70 or subsystem != PE_SUBSYSTEM_WINDOWS_GUI:
        raise ArtifactError(
            f"Windows artifact has the wrong optional-header/subsystem contract: size={optional_size} subsystem={subsystem}"
        )


def _audit_linux(path: Path) -> None:
    _require_regular_artifact(path, "Linux")
    with path.open("rb") as source:
        header = source.read(64)
    if len(header) < 64 or header[:4] != b"\x7fELF":
        raise ArtifactError("Linux artifact does not have an ELF header")
    if header[4] != 2 or header[5] != 1:
        raise ArtifactError("Linux artifact must be a little-endian ELF64 executable")
    elf_type, machine = struct.unpack_from("<HH", header, 16)
    if elf_type not in (2, 3) or machine != ELF_MACHINE_X86_64:
        raise ArtifactError(f"Linux artifact architecture/type is invalid: type={elf_type} machine={machine}")
    if not path.stat().st_mode & stat.S_IXUSR:
        raise ArtifactError("Linux artifact is not executable by its owner")


def _mach_architectures(header: bytes) -> set[int]:
    if len(header) < 8:
        raise ArtifactError("macOS executable header is truncated")
    magic = header[:4]
    if magic == b"\xca\xfe\xba\xbe":
        item_size = 20
    elif magic == b"\xca\xfe\xba\xbf":
        item_size = 24
    else:
        raise ArtifactError("macOS executable is not a big-endian universal Mach-O")
    count = struct.unpack_from(">I", header, 4)[0]
    if count < 1 or count > 16 or len(header) < 8 + count * item_size:
        raise ArtifactError(f"macOS universal architecture table is invalid: count={count}")
    return {
        struct.unpack_from(">I", header, 8 + index * item_size)[0]
        for index in range(count)
    }


def _safe_zip_members(archive: zipfile.ZipFile) -> Dict[str, zipfile.ZipInfo]:
    members: Dict[str, zipfile.ZipInfo] = {}
    total_size = 0
    for info in archive.infolist():
        member = PurePosixPath(info.filename)
        mode = (info.external_attr >> 16) & 0xFFFF
        if (
            member.is_absolute()
            or ".." in member.parts
            or "\\" in info.filename
            or info.is_dir()
            or stat.S_IFMT(mode) == stat.S_IFLNK
        ):
            raise ArtifactError(f"macOS archive contains an unsafe member: {info.filename}")
        if info.filename in members:
            raise ArtifactError(f"macOS archive contains a duplicate member: {info.filename}")
        total_size += info.file_size
        if total_size > MAX_MACOS_UNCOMPRESSED_BYTES:
            raise ArtifactError("macOS archive exceeds the uncompressed safety budget")
        members[info.filename] = info
    return members


def _audit_macos(path: Path, metadata: Mapping[str, Any]) -> None:
    _require_regular_artifact(path, "macOS")
    product_name = metadata.get("product_name")
    version = metadata.get("version")
    build_number = metadata.get("build_number")
    bundle_identifier = metadata.get("macos_bundle_identifier")
    if not isinstance(product_name, str) or not isinstance(version, str) or not isinstance(build_number, int):
        raise ArtifactError("release metadata lacks macOS identity/version fields")
    app_root = f"{product_name}.app/Contents"
    executable_name = product_name
    expected_members = {
        f"{app_root}/MacOS/{executable_name}",
        f"{app_root}/Resources/icon.icns",
        f"{app_root}/Resources/PrivacyInfo.xcprivacy",
        f"{app_root}/Resources/{product_name}.pck",
        f"{app_root}/Info.plist",
        f"{app_root}/PkgInfo",
    }
    try:
        with zipfile.ZipFile(path, "r") as archive:
            members = _safe_zip_members(archive)
            if set(members) != expected_members:
                extra = sorted(set(members) - expected_members)
                missing = sorted(expected_members - set(members))
                raise ArtifactError(f"macOS bundle member allowlist differs; extra={extra}, missing={missing}")
            plist = plistlib.loads(archive.read(f"{app_root}/Info.plist"))
            core_version = version.split("+", 1)[0].split("-", 1)[0]
            plist_contract = {
                "CFBundleDisplayName": product_name,
                "CFBundleExecutable": executable_name,
                "CFBundleIdentifier": bundle_identifier,
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": core_version,
                "CFBundleVersion": str(build_number),
            }
            for key, expected in plist_contract.items():
                if plist.get(key) != expected:
                    raise ArtifactError(f"macOS Info.plist {key} {plist.get(key)!r} != {expected!r}")
            privacy = plistlib.loads(archive.read(f"{app_root}/Resources/PrivacyInfo.xcprivacy"))
            if not isinstance(privacy, dict) or privacy.get("NSPrivacyTracking") is not False:
                raise ArtifactError("macOS privacy manifest must explicitly disable tracking")
            if archive.read(f"{app_root}/PkgInfo").strip() != b"APPL????":
                raise ArtifactError("macOS PkgInfo is invalid")
            if archive.read(f"{app_root}/Resources/icon.icns")[:4] != b"icns":
                raise ArtifactError("macOS icon is not an ICNS container")
            pck_info = members[f"{app_root}/Resources/{product_name}.pck"]
            if pck_info.file_size < MIN_ARTIFACT_BYTES:
                raise ArtifactError("macOS PCK is implausibly small")
            executable_info = members[f"{app_root}/MacOS/{executable_name}"]
            executable_mode = (executable_info.external_attr >> 16) & 0xFFFF
            if not executable_mode & stat.S_IXUSR:
                raise ArtifactError("macOS executable does not retain its owner execute bit")
            with archive.open(executable_info, "r") as executable:
                architectures = _mach_architectures(executable.read(512))
            expected_architectures = {MACH_CPU_X86_64, MACH_CPU_ARM64}
            if architectures != expected_architectures:
                formatted = sorted(f"0x{value:08x}" for value in architectures)
                raise ArtifactError(f"macOS universal architectures differ: {formatted}")
    except (OSError, zipfile.BadZipFile, KeyError, plistlib.InvalidFileException) as exc:
        raise ArtifactError(f"cannot inspect macOS archive: {exc}") from exc


def audit_exports(metadata_path: Path, build_root: Path) -> Dict[str, Path]:
    metadata = _load_metadata(metadata_path)
    paths = _artifact_paths(metadata, build_root)
    _audit_windows(paths["Windows Desktop"])
    _audit_macos(paths["macOS"], metadata)
    _audit_linux(paths["Linux"])
    print(
        "EXPORT_ARTIFACT_AUDIT_OK "
        f"windows={paths['Windows Desktop'].stat().st_size}B:{_sha256(paths['Windows Desktop'])[:12]} "
        f"macos={paths['macOS'].stat().st_size}B:{_sha256(paths['macOS'])[:12]} "
        f"linux={paths['Linux'].stat().st_size}B:{_sha256(paths['Linux'])[:12]} "
        "architectures=pe-x86_64+mach-x86_64-arm64+elf-x86_64 privacy=notracking"
    )
    return paths


def _zip_info(name: str, executable: bool = False) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (0o100755 if executable else 0o100644) << 16
    return info


def _write_self_test_exports(build_root: Path, metadata: Mapping[str, Any]) -> None:
    paths = _artifact_paths(metadata, build_root)
    for path in paths.values():
        path.parent.mkdir(parents=True, exist_ok=True)

    pe = bytearray(MIN_ARTIFACT_BYTES)
    pe[:2] = b"MZ"
    struct.pack_into("<I", pe, 0x3C, 0x80)
    pe[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", pe, 0x84, PE_MACHINE_AMD64)
    struct.pack_into("<H", pe, 0x80 + 20, 0xF0)
    struct.pack_into("<H", pe, 0x80 + 24, PE_OPTIONAL_MAGIC_64)
    struct.pack_into("<H", pe, 0x80 + 24 + 68, PE_SUBSYSTEM_WINDOWS_GUI)
    paths["Windows Desktop"].write_bytes(pe)

    elf = bytearray(MIN_ARTIFACT_BYTES)
    elf[:6] = b"\x7fELF\x02\x01"
    struct.pack_into("<HH", elf, 16, 3, ELF_MACHINE_X86_64)
    paths["Linux"].write_bytes(elf)
    paths["Linux"].chmod(0o755)

    product_name = str(metadata["product_name"])
    app_root = f"{product_name}.app/Contents"
    core_version = str(metadata["version"]).split("+", 1)[0].split("-", 1)[0]
    info_plist = plistlib.dumps(
        {
            "CFBundleDisplayName": product_name,
            "CFBundleExecutable": product_name,
            "CFBundleIdentifier": metadata["macos_bundle_identifier"],
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": core_version,
            "CFBundleVersion": str(metadata["build_number"]),
        }
    )
    privacy_plist = plistlib.dumps({"NSPrivacyTracking": False})
    fat_header = bytearray(48)
    fat_header[:4] = b"\xca\xfe\xba\xbe"
    struct.pack_into(">I", fat_header, 4, 2)
    struct.pack_into(">I", fat_header, 8, MACH_CPU_X86_64)
    struct.pack_into(">I", fat_header, 28, MACH_CPU_ARM64)
    mac_executable = bytes(fat_header) + bytes(MIN_ARTIFACT_BYTES)
    with zipfile.ZipFile(paths["macOS"], "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(_zip_info(f"{app_root}/MacOS/{product_name}", True), mac_executable)
        archive.writestr(_zip_info(f"{app_root}/Resources/icon.icns"), b"icns" + bytes(MIN_ARTIFACT_BYTES))
        archive.writestr(_zip_info(f"{app_root}/Resources/PrivacyInfo.xcprivacy"), privacy_plist)
        archive.writestr(_zip_info(f"{app_root}/Resources/{product_name}.pck"), bytes(MIN_ARTIFACT_BYTES))
        archive.writestr(_zip_info(f"{app_root}/Info.plist"), info_plist)
        archive.writestr(_zip_info(f"{app_root}/PkgInfo"), b"APPL????\n")


def run_self_test(metadata_path: Path) -> None:
    metadata = _load_metadata(metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_artifact_audit.") as temporary:
        build_root = Path(temporary) / "build"
        _write_self_test_exports(build_root, metadata)
        paths = audit_exports(metadata_path, build_root)
        windows = paths["Windows Desktop"]
        fixture = bytearray(windows.read_bytes())
        struct.pack_into("<H", fixture, 0x84, 0x014C)
        windows.write_bytes(fixture)
        try:
            audit_exports(metadata_path, build_root)
        except ArtifactError as exc:
            if "PE32+ x86_64" not in str(exc):
                raise ArtifactError(f"self-test rejected tampering for the wrong reason: {exc}") from exc
        else:
            raise ArtifactError("self-test accepted a non-x86_64 Windows artifact")
    print("EXPORT_ARTIFACT_AUDIT_TEST_OK containers=pe+zip+elf architectures=3 tamper=blocked")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("audit", "self-test"))
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--build-root", type=Path, default=ROOT / "build")
    args = parser.parse_args(argv)
    metadata_path = args.metadata if args.metadata.is_absolute() else ROOT / args.metadata
    build_root = args.build_root if args.build_root.is_absolute() else ROOT / args.build_root
    try:
        if args.command == "audit":
            audit_exports(metadata_path, build_root)
        else:
            run_self_test(metadata_path)
    except ArtifactError as exc:
        print(f"EXPORT_ARTIFACT_AUDIT_FAILED {exc}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
