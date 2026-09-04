#!/usr/bin/env python3
"""Record and re-verify a signed delivery and its native signature evidence."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
from typing import Any, Dict, List, Mapping, Sequence

import release_candidate as candidate
import linux_delivery
import signing_provenance as provenance


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
DEFAULT_POLICY = ROOT / "release" / "signing_policy.json"
MANIFEST_NAME = "signed-delivery-manifest.json"
EVIDENCE_SCHEMA_VERSION = 2
DELIVERY_SCHEMA_VERSION = 2
EVIDENCE_KEYS = {
    "architecture",
    "bundle_identifier",
    "candidate_id",
    "detached_signature_valid",
    "detached_signature_path",
    "detached_signature_sha256",
    "detached_signature_size",
    "hardened_runtime_valid",
    "notarization_valid",
    "platform",
    "preset",
    "schema_version",
    "signature_scheme",
    "signature_valid",
    "signed_artifact_path",
    "signed_artifact_sha256",
    "signed_artifact_size",
    "signer_identity",
    "source_artifact_sha256",
    "staple_valid",
    "trusted_timestamp_valid",
    "verification_host",
    "verification_tool",
    "verified_at_utc",
}
FORMAT_SUFFIXES = {
    "exe": ".exe",
    "zip": ".zip",
    "appimage": ".AppImage",
    "deb": ".deb",
    "flatpak": ".flatpak",
    "rpm": ".rpm",
    "tar.zst": ".tar.zst",
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class DeliveryError(RuntimeError):
    pass


def _load_canonical_json(path: Path, context: str) -> Dict[str, Any]:
    try:
        raw = path.read_bytes()
        value = json.loads(raw)
    except (OSError, json.JSONDecodeError) as exc:
        raise DeliveryError(f"cannot read {context}: {exc}") from exc
    if not isinstance(value, dict):
        raise DeliveryError(f"{context} must be a JSON object")
    if raw != candidate._canonical_json(value):
        raise DeliveryError(f"{context} is not canonical JSON")
    return value


def _safe_file(root: Path, raw: str, context: str) -> Path:
    relative = PurePosixPath(raw)
    if (
        relative.is_absolute()
        or not relative.parts
        or "." in relative.parts
        or ".." in relative.parts
        or "\\" in raw
    ):
        raise DeliveryError(f"{context} path is unsafe: {raw!r}")
    resolved_root = root.resolve()
    path = root.joinpath(*relative.parts)
    try:
        path.resolve().relative_to(resolved_root)
    except ValueError as exc:
        raise DeliveryError(f"{context} escapes its root: {raw!r}") from exc
    if path.is_symlink() or not path.is_file():
        raise DeliveryError(f"{context} file is missing or unsafe: {path}")
    if path.stat().st_size <= 0:
        raise DeliveryError(f"{context} file is empty: {path}")
    return path


def _valid_label(value: Any) -> bool:
    return (
        isinstance(value, str)
        and value == value.strip()
        and 3 <= len(value) <= 256
        and all(ord(character) >= 32 and ord(character) != 127 for character in value)
    )


def _valid_timestamp(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return False
    return True


def _require_sha256(value: Any, context: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise DeliveryError(f"{context} must be a lowercase SHA-256 digest")
    return value


def _validate_evidence(
    evidence: Mapping[str, Any],
    request: Mapping[str, Any],
    package: Mapping[str, Any],
    signed_root: Path,
) -> Dict[str, Any]:
    if set(evidence) != EVIDENCE_KEYS or evidence.get("schema_version") != EVIDENCE_SCHEMA_VERSION:
        raise DeliveryError(f"native evidence fields or schema differ for {package.get('preset')}")
    preset = str(package["preset"])
    requirements = package.get("requirements")
    source_artifacts = package.get("unsigned_artifacts")
    signing_input = package.get("signing_input")
    if (
        not isinstance(requirements, dict)
        or not isinstance(source_artifacts, list)
        or len(source_artifacts) != 1
        or not isinstance(signing_input, dict)
        or set(signing_input) != {"path", "sha256", "size"}
    ):
        raise DeliveryError(f"signing request artifact contract is invalid for {preset}")
    source = signing_input
    identity_contract = {
        "architecture": package["architecture"],
        "bundle_identifier": requirements["bundle_identifier"],
        "candidate_id": request["candidate_id"],
        "platform": package["platform"],
        "preset": preset,
        "signature_scheme": requirements["signature_scheme"],
        "signer_identity": requirements["signer_identity"],
        "source_artifact_sha256": source["sha256"],
        "verification_host": requirements["verification_host"],
    }
    for key, expected in identity_contract.items():
        if evidence.get(key) != expected:
            raise DeliveryError(f"native evidence {key} differs for {preset}")
    if evidence.get("signature_valid") is not True:
        raise DeliveryError(f"native signature is not valid for {preset}")
    if not _valid_label(evidence.get("verification_tool")):
        raise DeliveryError(f"native verification tool is invalid for {preset}")
    if not _valid_timestamp(evidence.get("verified_at_utc")):
        raise DeliveryError(f"native verification timestamp is invalid for {preset}")

    boolean_contract: Dict[str, Any]
    if preset == "Windows Desktop":
        boolean_contract = {
            "trusted_timestamp_valid": True,
            "hardened_runtime_valid": None,
            "notarization_valid": None,
            "staple_valid": None,
            "detached_signature_valid": None,
        }
    elif preset == "macOS":
        boolean_contract = {
            "trusted_timestamp_valid": True,
            "hardened_runtime_valid": True,
            "notarization_valid": True,
            "staple_valid": True,
            "detached_signature_valid": None,
        }
    else:
        boolean_contract = {
            "trusted_timestamp_valid": None,
            "hardened_runtime_valid": None,
            "notarization_valid": None,
            "staple_valid": None,
            "detached_signature_valid": True,
        }
    for key, expected in boolean_contract.items():
        if evidence.get(key) is not expected:
            raise DeliveryError(f"native evidence {key} differs for {preset}")

    detached_signature: Dict[str, Any] | None = None
    if preset == "Linux":
        raw_signature_path = evidence.get("detached_signature_path")
        if not isinstance(raw_signature_path, str) or not raw_signature_path.endswith(".asc"):
            raise DeliveryError("Linux detached signature path or format is invalid")
        signature_path = _safe_file(
            signed_root, raw_signature_path, "Linux detached signature"
        )
        signature_size = signature_path.stat().st_size
        signature_hash = candidate._sha256_file(signature_path)
        if evidence.get("detached_signature_size") != signature_size:
            raise DeliveryError("Linux detached signature size differs")
        if (
            _require_sha256(
                evidence.get("detached_signature_sha256"), "Linux detached signature"
            )
            != signature_hash
        ):
            raise DeliveryError("Linux detached signature hash differs")
        detached_signature = {
            "path": raw_signature_path,
            "sha256": signature_hash,
            "size": signature_size,
        }
    elif any(
        evidence.get(key) is not None
        for key in (
            "detached_signature_path",
            "detached_signature_sha256",
            "detached_signature_size",
        )
    ):
        raise DeliveryError(f"native evidence invents a detached signature for {preset}")

    raw_signed_path = evidence.get("signed_artifact_path")
    if not isinstance(raw_signed_path, str):
        raise DeliveryError(f"signed artifact path is invalid for {preset}")
    delivery_format = requirements.get("delivery_format")
    suffix = FORMAT_SUFFIXES.get(str(delivery_format))
    if suffix is None or not raw_signed_path.endswith(suffix):
        raise DeliveryError(f"signed artifact format differs for {preset}")
    signed_path = _safe_file(signed_root, raw_signed_path, f"{preset} signed artifact")
    if detached_signature is not None and detached_signature["path"] == raw_signed_path:
        raise DeliveryError("Linux payload and detached signature paths must differ")
    actual_size = signed_path.stat().st_size
    actual_hash = candidate._sha256_file(signed_path)
    if evidence.get("signed_artifact_size") != actual_size:
        raise DeliveryError(f"signed artifact size differs for {preset}")
    if _require_sha256(evidence.get("signed_artifact_sha256"), f"{preset} signed artifact") != actual_hash:
        raise DeliveryError(f"signed artifact hash differs for {preset}")
    if preset == "Linux":
        if actual_hash != source["sha256"] or actual_size != source["size"]:
            raise DeliveryError("Linux detached-signature payload differs from its signing input")
    elif actual_hash == source["sha256"]:
        raise DeliveryError(f"signed artifact bytes did not change for {preset}")
    return {
        "architecture": package["architecture"],
        "detached_signature": detached_signature,
        "native_evidence": {
            "path": "",
            "sha256": "",
            "size": 0,
        },
        "platform": package["platform"],
        "preset": preset,
        "signature_scheme": requirements["signature_scheme"],
        "signed_artifact": {
            "path": raw_signed_path,
            "sha256": actual_hash,
            "size": actual_size,
        },
        "signer_identity": requirements["signer_identity"],
        "source_artifact_sha256": source["sha256"],
        "verified_at_utc": evidence["verified_at_utc"],
    }


def _delivery_value(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    request_path: Path,
    signed_root: Path,
    evidence_root: Path,
) -> Dict[str, Any]:
    request = provenance.verify_request(
        root, metadata_path, policy_path, candidate_root, request_path
    )
    if request.get("ready_for_signing") is not True or request.get("blockers") != []:
        raise DeliveryError("signing request is not ready; unresolved policy gates remain")
    metadata = candidate._load_json(metadata_path)
    presets = metadata.get("presets")
    if not isinstance(presets, list):
        raise DeliveryError("release metadata presets are invalid")
    slugs = {
        str(value["name"]): str(value["slug"])
        for value in presets
        if isinstance(value, dict) and "name" in value and "slug" in value
    }
    packages = request.get("packages")
    if not isinstance(packages, list) or len(packages) != len(slugs):
        raise DeliveryError("signing request packages are invalid")
    deliveries: List[Dict[str, Any]] = []
    for package in packages:
        if not isinstance(package, dict):
            raise DeliveryError("signing request package entry must be an object")
        preset = str(package.get("preset", ""))
        if preset not in slugs:
            raise DeliveryError(f"signing request contains an unknown preset: {preset!r}")
        evidence_name = f"{slugs[preset]}.json"
        evidence_path = _safe_file(evidence_root, evidence_name, f"{preset} native evidence")
        evidence = _load_canonical_json(evidence_path, f"{preset} native evidence")
        delivery = _validate_evidence(evidence, request, package, signed_root)
        delivery["native_evidence"] = {
            "path": evidence_name,
            "sha256": candidate._sha256_file(evidence_path),
            "size": evidence_path.stat().st_size,
        }
        deliveries.append(delivery)
    deliveries.sort(key=lambda item: str(item["preset"]))
    return {
        "build_number": request["build_number"],
        "candidate_id": request["candidate_id"],
        "deliveries": deliveries,
        "policy": request["policy"],
        "product_name": request["product_name"],
        "ready_for_distribution": True,
        "release_channel": request["release_channel"],
        "schema_version": DELIVERY_SCHEMA_VERSION,
        "signed_delivery": True,
        "signing_request": {
            "path": request_path.name,
            "sha256": candidate._sha256_file(request_path),
            "size": request_path.stat().st_size,
        },
        "source_tree": request["source_tree"],
        "unsigned_source_candidate": True,
        "version": request["version"],
    }


def record_delivery(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    request_path: Path,
    signed_root: Path,
    evidence_root: Path,
    manifest_path: Path,
) -> Dict[str, Any]:
    manifest = _delivery_value(
        root,
        metadata_path,
        policy_path,
        candidate_root,
        request_path,
        signed_root,
        evidence_root,
    )
    candidate._atomic_write(manifest_path, candidate._canonical_json(manifest))
    verify_delivery(
        root,
        metadata_path,
        policy_path,
        candidate_root,
        request_path,
        signed_root,
        evidence_root,
        manifest_path,
    )
    return manifest


def verify_delivery(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    request_path: Path,
    signed_root: Path,
    evidence_root: Path,
    manifest_path: Path,
) -> Dict[str, Any]:
    manifest = _load_canonical_json(manifest_path, "signed delivery manifest")
    expected = _delivery_value(
        root,
        metadata_path,
        policy_path,
        candidate_root,
        request_path,
        signed_root,
        evidence_root,
    )
    if manifest != expected:
        raise DeliveryError("signed delivery manifest differs from its files or evidence")
    return manifest


def _ready_fixture_policy(policy_path: Path) -> None:
    policy = candidate._load_json(policy_path)
    for requirement in policy["requirements"]:
        requirement["identity_status"] = "ready"
        preset = requirement["preset"]
        if preset == "Windows Desktop":
            requirement["signer_identity"] = "CN=Fixture Windows Signing"
        elif preset == "macOS":
            requirement["signer_identity"] = "Developer ID Application: Fixture Studio (TEAMID1234)"
            requirement["bundle_identifier_status"] = "owned"
        else:
            requirement["signer_identity"] = "Fixture Linux Release Key ABCDEF0123456789"
            requirement["signature_scheme"] = "openpgp-detached"
            requirement["delivery_format"] = "tar.zst"
    policy_path.write_bytes(candidate._canonical_json(policy))


def _fixture_evidence(
    signing_workspace: Path,
    request: Mapping[str, Any],
    metadata: Mapping[str, Any],
) -> tuple[Path, Path, List[Path]]:
    signed_root = signing_workspace / "signed"
    evidence_root = signing_workspace / "evidence"
    signed_root.mkdir()
    evidence_root.mkdir()
    slugs = {str(value["name"]): str(value["slug"]) for value in metadata["presets"]}
    suffixes = {"exe": ".exe", "zip": ".zip", "tar.zst": ".tar.zst"}
    signed_paths: List[Path] = []
    for package in request["packages"]:
        preset = str(package["preset"])
        requirements = package["requirements"]
        suffix = suffixes[str(requirements["delivery_format"])]
        relative = f"{slugs[preset]}/{metadata['artifact_name']}{suffix}"
        signed_path = signed_root.joinpath(*PurePosixPath(relative).parts)
        signed_path.parent.mkdir(parents=True, exist_ok=True)
        source_hash = package["signing_input"]["sha256"]
        if preset == "Linux":
            source_path = signing_workspace.joinpath(
                *PurePosixPath(str(package["signing_input"]["path"])).parts
            )
            shutil.copyfile(source_path, signed_path)
        else:
            signed_path.write_bytes(
                f"signed-fixture:{preset}:{source_hash}\n".encode("utf-8")
            )
        signed_paths.append(signed_path)
        if preset == "Windows Desktop":
            booleans = (True, None, None, None, None)
            tool = "Get-AuthenticodeSignature fixture"
        elif preset == "macOS":
            booleans = (True, True, True, True, None)
            tool = "codesign spctl stapler fixture"
        else:
            booleans = (None, None, None, None, True)
            tool = "gpgv fixture"
        signature_path: Path | None = None
        if preset == "Linux":
            signature_path = signed_path.with_name(signed_path.name + ".asc")
            signature_path.write_bytes(
                f"openpgp-signature-fixture:{candidate._sha256_file(signed_path)}\n".encode(
                    "utf-8"
                )
            )
        evidence = {
            "architecture": package["architecture"],
            "bundle_identifier": requirements["bundle_identifier"],
            "candidate_id": request["candidate_id"],
            "detached_signature_valid": booleans[4],
            "detached_signature_path": (
                signature_path.relative_to(signed_root).as_posix()
                if signature_path is not None
                else None
            ),
            "detached_signature_sha256": (
                candidate._sha256_file(signature_path) if signature_path is not None else None
            ),
            "detached_signature_size": (
                signature_path.stat().st_size if signature_path is not None else None
            ),
            "hardened_runtime_valid": booleans[1],
            "notarization_valid": booleans[2],
            "platform": package["platform"],
            "preset": preset,
            "schema_version": EVIDENCE_SCHEMA_VERSION,
            "signature_scheme": requirements["signature_scheme"],
            "signature_valid": True,
            "signed_artifact_path": relative,
            "signed_artifact_sha256": candidate._sha256_file(signed_path),
            "signed_artifact_size": signed_path.stat().st_size,
            "signer_identity": requirements["signer_identity"],
            "source_artifact_sha256": source_hash,
            "staple_valid": booleans[3],
            "trusted_timestamp_valid": booleans[0],
            "verification_host": requirements["verification_host"],
            "verification_tool": tool,
            "verified_at_utc": "2026-01-02T03:04:05Z",
        }
        evidence_path = evidence_root / f"{slugs[preset]}.json"
        evidence_path.write_bytes(candidate._canonical_json(evidence))
    return signed_root, evidence_root, signed_paths


def run_self_test(root: Path, metadata_path: Path, policy_path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="psychic_vector_signed_delivery.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        fixture_policy = fixture_root / "release" / "signing_policy.json"
        _ready_fixture_policy(fixture_policy)
        metadata, presets = candidate.load_and_validate_config(fixture_root, fixture_metadata)
        fixture_build = base / "build"
        candidate._create_fake_exports(fixture_build, presets)
        fixture_dist = base / "dist"
        candidate.package_candidate(
            fixture_root, fixture_metadata, fixture_build, fixture_dist
        )
        fixture_metadata_value = candidate._load_json(fixture_metadata)
        signing_workspace = linux_delivery.signing_root(
            fixture_dist, fixture_metadata_value
        )
        linux_delivery.prepare_payload(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            linux_delivery.default_payload_path(
                fixture_dist, fixture_metadata_value
            ),
        )
        request_path = signing_workspace / provenance.REQUEST_NAME
        request = provenance.prepare_request(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            request_path,
        )
        if request.get("ready_for_signing") is not True:
            raise DeliveryError("self-test ready policy did not clear signing blockers")
        signed_root, evidence_root, signed_paths = _fixture_evidence(
            signing_workspace, request, metadata
        )
        manifest_path = signing_workspace / MANIFEST_NAME
        record_delivery(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            request_path,
            signed_root,
            evidence_root,
            manifest_path,
        )
        mac_evidence_path = evidence_root / "macos-universal.json"
        original_mac_evidence = mac_evidence_path.read_bytes()

        def expect_evidence_failure(expected_message: str) -> None:
            try:
                verify_delivery(
                    fixture_root,
                    fixture_metadata,
                    fixture_policy,
                    fixture_dist,
                    request_path,
                    signed_root,
                    evidence_root,
                    manifest_path,
                )
            except DeliveryError as exc:
                if expected_message not in str(exc):
                    raise DeliveryError(
                        f"self-test rejected evidence for the wrong reason: {exc}"
                    ) from exc
            else:
                raise DeliveryError("self-test accepted invalid native evidence")

        mac_evidence = json.loads(original_mac_evidence)
        mac_evidence["notarization_valid"] = False
        mac_evidence_path.write_bytes(candidate._canonical_json(mac_evidence))
        expect_evidence_failure("notarization_valid differs")

        mac_evidence["notarization_valid"] = True
        mac_evidence["signed_artifact_path"] = "../escape.zip"
        mac_evidence_path.write_bytes(candidate._canonical_json(mac_evidence))
        expect_evidence_failure("path is unsafe")

        mac_evidence_path.write_bytes(json.dumps(json.loads(original_mac_evidence)).encode("utf-8"))
        expect_evidence_failure("not canonical JSON")
        mac_evidence_path.write_bytes(original_mac_evidence)

        linux_signature_path = next(signed_root.rglob("*.asc"))
        original_linux_signature = linux_signature_path.read_bytes()
        mutated_linux_signature = bytearray(original_linux_signature)
        mutated_linux_signature[0] ^= 0x01
        linux_signature_path.write_bytes(bytes(mutated_linux_signature))
        expect_evidence_failure("detached signature hash differs")
        linux_signature_path.write_bytes(original_linux_signature)

        signed_paths[0].write_bytes(signed_paths[0].read_bytes() + b"tamper")
        try:
            verify_delivery(
                fixture_root,
                fixture_metadata,
                fixture_policy,
                fixture_dist,
                request_path,
                signed_root,
                evidence_root,
                manifest_path,
            )
        except DeliveryError as exc:
            if "size differs" not in str(exc) and "hash differs" not in str(exc):
                raise DeliveryError(f"self-test rejected tampering for the wrong reason: {exc}") from exc
        else:
            raise DeliveryError("self-test accepted a modified signed artifact")
    print(
        "SIGNED_DELIVERY_TEST_OK presets=3 request=bound evidence=canonical "
        "native_controls=required detached_signature=bound traversal=blocked "
        "evidence_tamper=blocked signature_tamper=blocked artifact_tamper=blocked "
        "distribution_gate=closed"
    )


def _paths(
    candidate_root: Path, metadata: Mapping[str, Any]
) -> tuple[Path, Path, Path, Path]:
    signing_root = candidate_root / "signing" / candidate._candidate_id(metadata)
    return (
        signing_root / provenance.REQUEST_NAME,
        signing_root / "signed",
        signing_root / "evidence",
        signing_root / MANIFEST_NAME,
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("record", "verify", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--candidate-root", type=Path, default=ROOT / "dist")
    parser.add_argument("--request", type=Path)
    parser.add_argument("--signed-root", type=Path)
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = args.metadata if args.metadata.is_absolute() else root / args.metadata
    policy_path = args.policy if args.policy.is_absolute() else root / args.policy
    candidate_root = args.candidate_root if args.candidate_root.is_absolute() else root / args.candidate_root
    try:
        metadata = candidate._load_json(metadata_path)
        defaults = _paths(candidate_root, metadata)

        def absolute(path: Path) -> Path:
            return path if path.is_absolute() else root / path

        request_path = absolute(args.request or defaults[0])
        signed_root = absolute(args.signed_root or defaults[1])
        evidence_root = absolute(args.evidence_root or defaults[2])
        manifest_path = absolute(args.manifest or defaults[3])
        if args.command == "self-test":
            run_self_test(root, metadata_path, policy_path)
        elif args.command == "record":
            manifest = record_delivery(
                root,
                metadata_path,
                policy_path,
                candidate_root,
                request_path,
                signed_root,
                evidence_root,
                manifest_path,
            )
            print(
                f"SIGNED_DELIVERY_OK manifest={manifest_path} candidate={manifest['candidate_id']} "
                f"deliveries={len(manifest['deliveries'])} ready=true"
            )
        else:
            manifest = verify_delivery(
                root,
                metadata_path,
                policy_path,
                candidate_root,
                request_path,
                signed_root,
                evidence_root,
                manifest_path,
            )
            print(
                f"SIGNED_DELIVERY_VERIFY_OK candidate={manifest['candidate_id']} "
                f"deliveries={len(manifest['deliveries'])} ready=true"
            )
    except (OSError, DeliveryError, provenance.SigningError, candidate.ReleaseError) as exc:
        print(f"SIGNED_DELIVERY_FAILED {exc}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
