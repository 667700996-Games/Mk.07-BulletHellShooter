#!/usr/bin/env python3
"""Prepare and verify the deterministic Linux tar.zst signing input."""

from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from typing import Any, Dict, Mapping, Sequence, Tuple
import zipfile

import release_candidate as candidate


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
DEFAULT_POLICY = ROOT / "release" / "signing_policy.json"
PAYLOAD_NAME = "PsychicVector.tar.zst"
TAR_ROOT = "PsychicVector"
TAR_MTIME = 315532800
MAX_PAYLOAD_BYTES = 1024 * 1024 * 1024
MAX_TAR_BYTES = 2 * 1024 * 1024 * 1024
ZSTD_OPTIONS = (
    "-19",
    "--single-thread",
    "--no-progress",
    "--check",
    "--no-dictID",
)
VERSION_RE = re.compile(r"\bv(\d+)\.(\d+)\.(\d+)\b")
PAYLOAD_KEYS = {
    "architecture",
    "candidate_id",
    "compressor",
    "delivery_format",
    "executable",
    "license",
    "platform",
    "policy",
    "preset",
    "schema_version",
    "signature_scheme",
    "source_package",
    "source_tree",
    "unsigned_signing_input",
}
DESCRIPTOR_KEYS = {"path", "sha256", "size"}
COMPRESSOR_KEYS = {"name", "options", "version"}
POLICY_KEYS = {"path", "policy_id", "sha256"}


class LinuxDeliveryError(candidate.ReleaseError):
    """The Linux signing-input contract failed."""


def _zstd_binary(value: str | None) -> str:
    path = value or shutil.which("zstd")
    if not path:
        raise LinuxDeliveryError("zstd CLI is required to prepare or verify Linux delivery")
    return path


def _compressor(zstd: str) -> Dict[str, Any]:
    try:
        completed = subprocess.run(
            [zstd, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise LinuxDeliveryError(f"cannot inspect zstd: {exc}") from exc
    match = VERSION_RE.search(completed.stdout)
    if completed.returncode != 0 or match is None:
        raise LinuxDeliveryError("zstd version could not be determined")
    version = ".".join(match.groups())
    if tuple(int(item) for item in match.groups()) < (1, 5, 0):
        raise LinuxDeliveryError(f"zstd {version} is below the required 1.5.0 baseline")
    return {"name": "zstd", "options": list(ZSTD_OPTIONS), "version": version}


def _linux_requirement(policy_path: Path) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    policy = candidate._load_json(policy_path)
    requirements = policy.get("requirements")
    if not isinstance(requirements, list):
        raise LinuxDeliveryError("signing policy requirements are invalid")
    matches = [
        value
        for value in requirements
        if isinstance(value, dict) and value.get("preset") == "Linux"
    ]
    if len(matches) != 1:
        raise LinuxDeliveryError("signing policy must contain exactly one Linux requirement")
    requirement = matches[0]
    if (
        requirement.get("delivery_format") != "tar.zst"
        or requirement.get("signature_scheme") != "openpgp-detached"
        or requirement.get("verification_host") != "Linux"
    ):
        raise LinuxDeliveryError("Linux signing policy must use tar.zst and OpenPGP detached signing")
    policy_id = policy.get("policy_id")
    if not isinstance(policy_id, str) or candidate.SAFE_TOKEN_RE.fullmatch(policy_id) is None:
        raise LinuxDeliveryError("signing policy ID is invalid")
    return policy, requirement


def _candidate_context(
    root: Path, metadata_path: Path, policy_path: Path, candidate_root: Path
) -> Tuple[Dict[str, Any], Dict[str, Any], Path, Dict[str, Any], Dict[str, Any]]:
    metadata, _presets = candidate.load_and_validate_config(root, metadata_path)
    _policy, requirement = _linux_requirement(policy_path)
    candidate_dir = candidate_root / candidate._candidate_id(metadata)
    if not candidate_dir.is_dir() or candidate_dir.is_symlink():
        raise LinuxDeliveryError(f"candidate directory is missing or unsafe: {candidate_dir}")
    manifest = candidate.verify_candidate(root, metadata_path, candidate_dir)
    packages = manifest.get("packages")
    matches = [
        item
        for item in packages
        if isinstance(item, dict) and item.get("preset") == "Linux"
    ] if isinstance(packages, list) else []
    if len(matches) != 1:
        raise LinuxDeliveryError("candidate must contain exactly one Linux package")
    package = matches[0]
    contents = package.get("contents")
    if not isinstance(contents, list) or len(contents) != 1:
        raise LinuxDeliveryError("Linux candidate must contain exactly one executable")
    executable = contents[0]
    if (
        executable.get("path") != "PsychicVector.x86_64"
        or package.get("architecture") != "x86_64"
        or package.get("platform") != "Linux/X11"
    ):
        raise LinuxDeliveryError("Linux executable identity differs from the delivery contract")
    return metadata, manifest, candidate_dir, package, requirement


def _descriptor(path: str, sha256: str, size: int) -> Dict[str, Any]:
    return {"path": path, "sha256": sha256, "size": size}


def _payload_contract(
    root: Path,
    policy_path: Path,
    manifest: Mapping[str, Any],
    package: Mapping[str, Any],
    compressor: Mapping[str, Any],
) -> Dict[str, Any]:
    executable = package["contents"][0]
    license_path = root / "LICENSE"
    if not license_path.is_file() or license_path.is_symlink():
        raise LinuxDeliveryError("project LICENSE is missing or unsafe")
    policy = candidate._load_json(policy_path)
    return {
        "architecture": "x86_64",
        "candidate_id": manifest["candidate_id"],
        "compressor": dict(compressor),
        "delivery_format": "tar.zst",
        "executable": _descriptor(
            f"{TAR_ROOT}/{executable['path']}",
            str(executable["sha256"]),
            int(executable["size"]),
        ),
        "license": _descriptor(
            f"{TAR_ROOT}/LICENSE.txt",
            candidate._sha256_file(license_path),
            license_path.stat().st_size,
        ),
        "platform": "Linux/X11",
        "policy": {
            "path": policy_path.relative_to(root).as_posix(),
            "policy_id": policy["policy_id"],
            "sha256": candidate._sha256_file(policy_path),
        },
        "preset": "Linux",
        "schema_version": 1,
        "signature_scheme": "openpgp-detached",
        "source_package": _descriptor(
            str(package["path"]), str(package["sha256"]), int(package["size"])
        ),
        "source_tree": manifest["source_tree"],
        "unsigned_signing_input": True,
    }


def _tar_info(name: str, size: int, executable: bool = False) -> tarfile.TarInfo:
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = 0o755 if executable else 0o644
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = TAR_MTIME
    info.type = tarfile.REGTYPE
    return info


def _outer_members(
    package_path: Path, metadata: Mapping[str, Any], package: Mapping[str, Any]
) -> Tuple[str, str]:
    root_name = str(metadata["artifact_name"])
    executable_name = str(package["contents"][0]["path"])
    return f"{root_name}/RELEASE.json", f"{root_name}/{executable_name}"


def _run_zstd(command: Sequence[str], context: str) -> None:
    try:
        completed = subprocess.run(
            list(command),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=600,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise LinuxDeliveryError(f"{context} failed: {exc}") from exc
    if completed.returncode != 0:
        raise LinuxDeliveryError(
            f"{context} failed with {completed.returncode}: {completed.stdout[-2000:].strip()}"
        )


def prepare_payload(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    output_path: Path,
    zstd_value: str | None = None,
) -> Dict[str, Any]:
    metadata, manifest, candidate_dir, package, _requirement = _candidate_context(
        root, metadata_path, policy_path, candidate_root
    )
    zstd = _zstd_binary(zstd_value)
    compressor = _compressor(zstd)
    contract = _payload_contract(root, policy_path, manifest, package, compressor)
    package_path = candidate_dir / str(package["path"])
    if output_path.is_symlink() or (output_path.exists() and not output_path.is_file()):
        raise LinuxDeliveryError(f"Linux payload output is unsafe: {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=f".{output_path.name}.", dir=output_path.parent
    ) as temporary:
        temporary_root = Path(temporary)
        tar_path = temporary_root / "payload.tar"
        compressed_path = temporary_root / PAYLOAD_NAME
        release_bytes = candidate._canonical_json(contract)
        license_bytes = (root / "LICENSE").read_bytes()
        metadata_member, executable_member = _outer_members(package_path, metadata, package)
        with zipfile.ZipFile(package_path, "r") as outer:
            infos = outer.infolist()
            if (
                [info.filename for info in infos] != [metadata_member, executable_member]
                or any(info.is_dir() for info in infos)
            ):
                raise LinuxDeliveryError("Linux candidate package members differ")
            executable_info = outer.getinfo(executable_member)
            if (
                executable_info.file_size != int(package["contents"][0]["size"])
                or executable_info.file_size <= 0
            ):
                raise LinuxDeliveryError("Linux executable size differs before packaging")
            with tarfile.open(tar_path, "w", format=tarfile.USTAR_FORMAT) as archive:
                archive.addfile(
                    _tar_info(f"{TAR_ROOT}/LICENSE.txt", len(license_bytes)),
                    io.BytesIO(license_bytes),
                )
                with outer.open(executable_info, "r") as executable_source:
                    archive.addfile(
                        _tar_info(
                            f"{TAR_ROOT}/PsychicVector.x86_64",
                            executable_info.file_size,
                            True,
                        ),
                        executable_source,
                    )
                archive.addfile(
                    _tar_info(f"{TAR_ROOT}/RELEASE.json", len(release_bytes)),
                    io.BytesIO(release_bytes),
                )
        _run_zstd(
            [
                zstd,
                *ZSTD_OPTIONS,
                "-q",
                "-f",
                "-o",
                str(compressed_path),
                "--",
                str(tar_path),
            ],
            "Linux payload compression",
        )
        if compressed_path.stat().st_size <= 0 or compressed_path.stat().st_size > MAX_PAYLOAD_BYTES:
            raise LinuxDeliveryError("compressed Linux payload size is outside the safety budget")
        os.replace(compressed_path, output_path)
    verified = verify_payload(
        root, metadata_path, policy_path, candidate_root, output_path, zstd
    )
    return verified


def _validate_embedded_compressor(value: Any) -> Dict[str, Any]:
    if not isinstance(value, dict) or set(value) != COMPRESSOR_KEYS:
        raise LinuxDeliveryError("embedded compressor fields differ")
    if value.get("name") != "zstd" or value.get("options") != list(ZSTD_OPTIONS):
        raise LinuxDeliveryError("embedded compressor contract differs")
    version = value.get("version")
    match = VERSION_RE.fullmatch(f"v{version}") if isinstance(version, str) else None
    if match is None or tuple(int(item) for item in match.groups()) < (1, 5, 0):
        raise LinuxDeliveryError("embedded compressor version is invalid")
    return dict(value)


def _hash_stream(handle: Any) -> Tuple[str, int]:
    import hashlib

    digest = hashlib.sha256()
    size = 0
    while True:
        chunk = handle.read(1024 * 1024)
        if not chunk:
            return digest.hexdigest(), size
        digest.update(chunk)
        size += len(chunk)


def verify_payload(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    payload_path: Path,
    zstd_value: str | None = None,
) -> Dict[str, Any]:
    metadata, manifest, _candidate_dir, package, _requirement = _candidate_context(
        root, metadata_path, policy_path, candidate_root
    )
    if (
        payload_path.is_symlink()
        or not payload_path.is_file()
        or payload_path.stat().st_size <= 0
        or payload_path.stat().st_size > MAX_PAYLOAD_BYTES
    ):
        raise LinuxDeliveryError(f"Linux payload is missing, empty, oversized, or unsafe: {payload_path}")
    zstd = _zstd_binary(zstd_value)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_linux_verify.") as temporary:
        tar_path = Path(temporary) / "payload.tar"
        _run_zstd(
            [zstd, "-d", "-q", "-f", "-o", str(tar_path), "--", str(payload_path)],
            "Linux payload decompression",
        )
        if tar_path.stat().st_size <= 0 or tar_path.stat().st_size > MAX_TAR_BYTES:
            raise LinuxDeliveryError("decompressed Linux payload exceeds the safety budget")
        with tarfile.open(tar_path, "r:") as archive:
            members = archive.getmembers()
            expected_names = [
                f"{TAR_ROOT}/LICENSE.txt",
                f"{TAR_ROOT}/PsychicVector.x86_64",
                f"{TAR_ROOT}/RELEASE.json",
            ]
            if [member.name for member in members] != expected_names:
                raise LinuxDeliveryError("Linux tar member set or order differs")
            for member in members:
                expected_mode = 0o755 if member.name.endswith(".x86_64") else 0o644
                if (
                    not member.isfile()
                    or stat.S_IMODE(member.mode) != expected_mode
                    or member.uid != 0
                    or member.gid != 0
                    or member.uname != ""
                    or member.gname != ""
                    or member.mtime != TAR_MTIME
                ):
                    raise LinuxDeliveryError(f"Linux tar metadata differs: {member.name}")
            release_handle = archive.extractfile(f"{TAR_ROOT}/RELEASE.json")
            license_handle = archive.extractfile(f"{TAR_ROOT}/LICENSE.txt")
            executable_handle = archive.extractfile(f"{TAR_ROOT}/PsychicVector.x86_64")
            if release_handle is None or license_handle is None or executable_handle is None:
                raise LinuxDeliveryError("Linux tar member could not be read")
            release_raw = release_handle.read()
            try:
                embedded = json.loads(release_raw)
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise LinuxDeliveryError(f"embedded Linux release metadata is invalid: {exc}") from exc
            if (
                not isinstance(embedded, dict)
                or set(embedded) != PAYLOAD_KEYS
                or release_raw != candidate._canonical_json(embedded)
            ):
                raise LinuxDeliveryError("embedded Linux release metadata is not canonical")
            compressor = _validate_embedded_compressor(embedded.get("compressor"))
            expected = _payload_contract(
                root, policy_path, manifest, package, compressor
            )
            if embedded != expected:
                raise LinuxDeliveryError("embedded Linux release contract differs")
            license_hash, license_size = _hash_stream(license_handle)
            executable_hash, executable_size = _hash_stream(executable_handle)
            if (
                license_hash != embedded["license"]["sha256"]
                or license_size != embedded["license"]["size"]
            ):
                raise LinuxDeliveryError("Linux payload license differs")
            if (
                executable_hash != embedded["executable"]["sha256"]
                or executable_size != embedded["executable"]["size"]
            ):
                raise LinuxDeliveryError("Linux payload executable differs")
    return _descriptor(
        f"prepared/linux-x86_64/{PAYLOAD_NAME}",
        candidate._sha256_file(payload_path),
        payload_path.stat().st_size,
    )


def signing_root(candidate_root: Path, metadata: Mapping[str, Any]) -> Path:
    return candidate_root / "signing" / candidate._candidate_id(metadata)


def default_payload_path(candidate_root: Path, metadata: Mapping[str, Any]) -> Path:
    return signing_root(candidate_root, metadata) / "prepared" / "linux-x86_64" / PAYLOAD_NAME


def run_self_test(
    root: Path, metadata_path: Path, policy_path: Path, zstd_value: str | None
) -> None:
    metadata, presets = candidate.load_and_validate_config(root, metadata_path)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_linux_delivery.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        fixture_build = base / "build"
        candidate._create_fake_exports(fixture_build, presets)
        fixture_dist = base / "dist"
        candidate.package_candidate(
            fixture_root, fixture_metadata, fixture_build, fixture_dist
        )
        fixture_policy = fixture_root / "release" / "signing_policy.json"
        first = base / "first" / PAYLOAD_NAME
        second = base / "second" / PAYLOAD_NAME
        prepare_payload(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            first,
            zstd_value,
        )
        prepare_payload(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            second,
            zstd_value,
        )
        if first.read_bytes() != second.read_bytes():
            raise LinuxDeliveryError("Linux signing input is not byte-deterministic")
        original = first.read_bytes()
        mutated = bytearray(original)
        mutated[len(mutated) // 2] ^= 0x01
        first.write_bytes(bytes(mutated))
        try:
            verify_payload(
                fixture_root,
                fixture_metadata,
                fixture_policy,
                fixture_dist,
                first,
                zstd_value,
            )
        except LinuxDeliveryError:
            pass
        else:
            raise LinuxDeliveryError("self-test accepted a modified Linux payload")
        first.write_bytes(original)
        verify_payload(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            first,
            zstd_value,
        )
    print(
        "LINUX_DELIVERY_TEST_OK format=tar.zst compression=deterministic "
        "executable=source-bound license=included metadata=normalized tamper=blocked "
        "signing_input=verified"
    )


def _resolve(root: Path, value: Path) -> Path:
    return value.resolve() if value.is_absolute() else (root / value).resolve()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--candidate-root", type=Path, default=Path("dist"))
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--zstd")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = _resolve(root, args.metadata)
    policy_path = _resolve(root, args.policy)
    candidate_root = _resolve(root, args.candidate_root)
    metadata = candidate._load_json(metadata_path)
    payload_path = (
        _resolve(root, args.payload)
        if args.payload is not None
        else default_payload_path(candidate_root, metadata)
    )
    try:
        if args.command == "self-test":
            run_self_test(root, metadata_path, policy_path, args.zstd)
        elif args.command == "prepare":
            value = prepare_payload(
                root,
                metadata_path,
                policy_path,
                candidate_root,
                payload_path,
                args.zstd,
            )
            print(
                f"LINUX_DELIVERY_OK candidate={candidate._candidate_id(metadata)} "
                f"path={payload_path} size={value['size']} sha256={value['sha256']}"
            )
        else:
            value = verify_payload(
                root,
                metadata_path,
                policy_path,
                candidate_root,
                payload_path,
                args.zstd,
            )
            print(
                f"LINUX_DELIVERY_VERIFY_OK candidate={candidate._candidate_id(metadata)} "
                f"size={value['size']} sha256={value['sha256']}"
            )
    except (
        OSError,
        ValueError,
        zipfile.BadZipFile,
        tarfile.TarError,
        LinuxDeliveryError,
        candidate.ReleaseError,
    ) as exc:
        print(f"LINUX_DELIVERY_FAILED {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
