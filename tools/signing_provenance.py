#!/usr/bin/env python3
"""Create and verify a canonical, source-bound desktop signing request."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Dict, List, Mapping, Sequence, Tuple

import release_candidate as candidate
import linux_delivery


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "release" / "release_metadata.json"
DEFAULT_POLICY = ROOT / "release" / "signing_policy.json"
REQUEST_NAME = "signing-request.json"
REQUEST_SCHEMA_VERSION = 2
POLICY_KEYS = {"policy_id", "product_name", "requirements", "schema_version", "stable_gate"}
REQUIREMENT_KEYS = {
    "bundle_identifier",
    "bundle_identifier_status",
    "delivery_format",
    "identity_status",
    "preset",
    "signature_scheme",
    "signer_identity",
    "verification_host",
}
STABLE_GATE_KEYS = {
    "hardened_runtime_required",
    "identity_required",
    "linux_signature_policy_required",
    "macos_notarization_required",
    "macos_staple_required",
    "native_signature_evidence_required",
    "signed_delivery_manifest_required",
    "trusted_timestamp_required",
}
HOST_CONTRACT = {
    "Windows Desktop": "Windows",
    "macOS": "macOS",
    "Linux": "Linux",
}
FORMAT_CONTRACT = {
    "Windows Desktop": {"exe"},
    "macOS": {"zip"},
    "Linux": {"appimage", "deb", "flatpak", "rpm", "tar.zst"},
}
SCHEME_CONTRACT = {
    "Windows Desktop": {"authenticode-sha256"},
    "macOS": {"developer-id-application"},
    "Linux": {"minisign", "openpgp-detached", "sigstore"},
}
class SigningError(RuntimeError):
    pass


def _valid_identity(value: Any) -> bool:
    return (
        isinstance(value, str)
        and value == value.strip()
        and 3 <= len(value) <= 256
        and all(ord(character) >= 32 and ord(character) != 127 for character in value)
    )


def _load_json(path: Path, context: str) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SigningError(f"cannot read {context}: {exc}") from exc
    if not isinstance(value, dict):
        raise SigningError(f"{context} must be a JSON object")
    return value


def _policy(
    policy_path: Path, metadata: Mapping[str, Any]
) -> Tuple[Dict[str, Any], Dict[str, Dict[str, Any]], List[str]]:
    policy = _load_json(policy_path, "signing policy")
    if set(policy) != POLICY_KEYS or policy.get("schema_version") != 1:
        raise SigningError("signing policy root fields or schema differ")
    if policy.get("product_name") != metadata.get("product_name"):
        raise SigningError("signing policy product_name differs from release metadata")
    policy_id = policy.get("policy_id")
    if not isinstance(policy_id, str) or candidate.SAFE_TOKEN_RE.fullmatch(policy_id) is None:
        raise SigningError("signing policy_id is unsafe")
    stable_gate = policy.get("stable_gate")
    if not isinstance(stable_gate, dict) or set(stable_gate) != STABLE_GATE_KEYS:
        raise SigningError("signing stable_gate fields differ")
    if any(stable_gate.get(key) is not True for key in STABLE_GATE_KEYS):
        raise SigningError("every stable signing gate must remain required")
    requirements = policy.get("requirements")
    if not isinstance(requirements, list) or len(requirements) != len(HOST_CONTRACT):
        raise SigningError("signing policy must contain exactly three desktop requirements")
    by_preset: Dict[str, Dict[str, Any]] = {}
    blockers: List[str] = []
    for value in requirements:
        if not isinstance(value, dict) or set(value) != REQUIREMENT_KEYS:
            raise SigningError("signing requirement fields differ")
        preset = value.get("preset")
        if preset not in HOST_CONTRACT or preset in by_preset:
            raise SigningError(f"signing requirement preset is duplicate or unsupported: {preset!r}")
        if value.get("verification_host") != HOST_CONTRACT[preset]:
            raise SigningError(f"signing verification host differs for {preset}")
        identity_status = value.get("identity_status")
        if identity_status not in ("ready", "pending", "policy_pending"):
            raise SigningError(f"signing identity_status is invalid for {preset}")
        signer = value.get("signer_identity")
        if signer is not None and not _valid_identity(signer):
            raise SigningError(f"signer identity is malformed for {preset}")
        if identity_status == "ready" and signer is None:
            raise SigningError(f"ready signing identity is empty for {preset}")
        scheme = value.get("signature_scheme")
        delivery_format = value.get("delivery_format")
        if scheme is not None and scheme not in SCHEME_CONTRACT[preset]:
            raise SigningError(f"signature scheme is unsupported for {preset}: {scheme!r}")
        if delivery_format is not None and delivery_format not in FORMAT_CONTRACT[preset]:
            raise SigningError(f"delivery format is unsupported for {preset}: {delivery_format!r}")
        bundle_status = value.get("bundle_identifier_status")
        bundle_id = value.get("bundle_identifier")
        if preset == "macOS":
            if bundle_id != metadata.get("macos_bundle_identifier"):
                raise SigningError("macOS signing bundle identifier differs from release metadata")
            if bundle_status not in ("owned", "provisional"):
                raise SigningError("macOS bundle identifier status is invalid")
        elif bundle_id is not None or bundle_status != "not_applicable":
            raise SigningError(f"non-macOS signing requirement declares a bundle identifier: {preset}")
        if scheme is None:
            blockers.append(f"{preset}:signature_scheme")
        if delivery_format is None:
            blockers.append(f"{preset}:delivery_format")
        if signer is None or identity_status != "ready":
            blockers.append(f"{preset}:signer_identity")
        if preset == "macOS" and bundle_status != "owned":
            blockers.append("macOS:owned_bundle_identifier")
        by_preset[str(preset)] = dict(value)
    if set(by_preset) != set(HOST_CONTRACT):
        raise SigningError("signing policy preset set is incomplete")
    blockers.sort()
    return policy, by_preset, blockers


def _candidate_dir(candidate_root: Path, metadata: Mapping[str, Any]) -> Path:
    path = candidate_root / candidate._candidate_id(metadata)
    if not path.is_dir() or path.is_symlink():
        raise SigningError(f"unsigned candidate is missing or unsafe: {path}")
    return path


def _request_value(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
) -> Dict[str, Any]:
    metadata, presets = candidate.load_and_validate_config(root, metadata_path)
    policy, requirements, blockers = _policy(policy_path, metadata)
    unsigned_dir = _candidate_dir(candidate_root, metadata)
    manifest = candidate.verify_candidate(root, metadata_path, unsigned_dir)
    manifest_path = unsigned_dir / candidate.MANIFEST_NAME
    packages: List[Dict[str, Any]] = []
    manifest_packages = manifest.get("packages")
    if not isinstance(manifest_packages, list):
        raise SigningError("unsigned candidate packages are invalid")
    by_name = {
        str(value.get("preset")): value
        for value in manifest_packages
        if isinstance(value, dict)
    }
    for preset in sorted(presets, key=lambda item: str(item["name"])):
        name = str(preset["name"])
        package = by_name.get(name)
        if not isinstance(package, dict):
            raise SigningError(f"unsigned candidate package is missing: {name}")
        contents = package.get("contents")
        if not isinstance(contents, list) or not contents:
            raise SigningError(f"unsigned candidate content contract is missing: {name}")
        signing_input = dict(contents[0])
        if name == "Linux":
            payload_path = linux_delivery.default_payload_path(candidate_root, metadata)
            try:
                signing_input = linux_delivery.verify_payload(
                    root,
                    metadata_path,
                    policy_path,
                    candidate_root,
                    payload_path,
                )
            except linux_delivery.LinuxDeliveryError as exc:
                raise SigningError(f"Linux signing input is not ready: {exc}") from exc
        packages.append(
            {
                "architecture": preset["architecture"],
                "platform": preset["platform"],
                "preset": name,
                "requirements": requirements[name],
                "signing_input": signing_input,
                "unsigned_artifacts": contents,
                "unsigned_package": {
                    "path": package["path"],
                    "sha256": package["sha256"],
                    "size": package["size"],
                },
            }
        )
    ready = not blockers
    if metadata.get("release_channel") == "stable" and not ready:
        raise SigningError("stable release cannot create a signing request with unresolved gates")
    return {
        "blockers": blockers,
        "build_number": metadata["build_number"],
        "candidate_id": manifest["candidate_id"],
        "candidate_manifest": {
            "path": candidate.MANIFEST_NAME,
            "sha256": candidate._sha256_file(manifest_path),
            "size": manifest_path.stat().st_size,
        },
        "packages": packages,
        "policy": {
            "path": policy_path.relative_to(root).as_posix(),
            "policy_id": policy["policy_id"],
            "sha256": candidate._sha256_file(policy_path),
        },
        "product_name": metadata["product_name"],
        "ready_for_signing": ready,
        "release_channel": metadata["release_channel"],
        "schema_version": REQUEST_SCHEMA_VERSION,
        "source_tree": manifest.get("source_tree"),
        "unsigned": True,
        "version": metadata["version"],
    }


def prepare_request(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    output_path: Path,
) -> Dict[str, Any]:
    request = _request_value(root, metadata_path, policy_path, candidate_root)
    candidate._atomic_write(output_path, candidate._canonical_json(request))
    verify_request(root, metadata_path, policy_path, candidate_root, output_path)
    return request


def verify_request(
    root: Path,
    metadata_path: Path,
    policy_path: Path,
    candidate_root: Path,
    request_path: Path,
) -> Dict[str, Any]:
    request = _load_json(request_path, "signing request")
    if request_path.read_bytes() != candidate._canonical_json(request):
        raise SigningError("signing request is not canonical JSON")
    expected = _request_value(root, metadata_path, policy_path, candidate_root)
    if request != expected:
        raise SigningError("signing request differs from the current candidate or policy")
    return request


def run_self_test(root: Path, metadata_path: Path, policy_path: Path) -> None:
    metadata, presets = candidate.load_and_validate_config(root, metadata_path)
    _policy(policy_path, metadata)
    with tempfile.TemporaryDirectory(prefix="psychic_vector_signing_provenance.") as temporary:
        base = Path(temporary)
        fixture_root = base / "source"
        fixture_metadata = candidate._copy_contract_fixture(root, metadata_path, fixture_root)
        fixture_policy = fixture_root / "release" / "signing_policy.json"
        fixture_build = base / "build"
        candidate._create_fake_exports(fixture_build, presets)
        fixture_dist = base / "dist"
        candidate.package_candidate(
            fixture_root, fixture_metadata, fixture_build, fixture_dist
        )
        fixture_metadata_value = candidate._load_json(fixture_metadata)
        linux_delivery.prepare_payload(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            linux_delivery.default_payload_path(fixture_dist, fixture_metadata_value),
        )
        request_path = (
            linux_delivery.signing_root(fixture_dist, fixture_metadata_value)
            / REQUEST_NAME
        )
        request = prepare_request(
            fixture_root,
            fixture_metadata,
            fixture_policy,
            fixture_dist,
            request_path,
        )
        if request.get("ready_for_signing") is not False or not request.get("blockers"):
            raise SigningError("self-test pending policy did not preserve explicit blockers")
        tampered = dict(request)
        tampered_manifest = dict(tampered["candidate_manifest"])
        tampered_manifest["sha256"] = "0" * 64
        tampered["candidate_manifest"] = tampered_manifest
        request_path.write_bytes(candidate._canonical_json(tampered))
        try:
            verify_request(
                fixture_root,
                fixture_metadata,
                fixture_policy,
                fixture_dist,
                request_path,
            )
        except SigningError as exc:
            if "differs" not in str(exc):
                raise SigningError(f"self-test rejected tampering for the wrong reason: {exc}") from exc
        else:
            raise SigningError("self-test accepted a tampered signing request")
    print(
        "SIGNING_PROVENANCE_TEST_OK candidate=bound policy=bound source_tree=bound "
        "pending_gates=explicit tamper=blocked"
    )


def _default_request_path(candidate_root: Path, metadata: Mapping[str, Any]) -> Path:
    return candidate_root / "signing" / candidate._candidate_id(metadata) / REQUEST_NAME


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify", "self-test"))
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY)
    parser.add_argument("--candidate-root", type=Path, default=ROOT / "dist")
    parser.add_argument("--request", type=Path)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    metadata_path = args.metadata if args.metadata.is_absolute() else root / args.metadata
    policy_path = args.policy if args.policy.is_absolute() else root / args.policy
    candidate_root = args.candidate_root if args.candidate_root.is_absolute() else root / args.candidate_root
    metadata = candidate._load_json(metadata_path)
    request_path = args.request or _default_request_path(candidate_root, metadata)
    if not request_path.is_absolute():
        request_path = root / request_path
    try:
        if args.command == "self-test":
            run_self_test(root, metadata_path, policy_path)
        elif args.command == "prepare":
            request = prepare_request(
                root, metadata_path, policy_path, candidate_root, request_path
            )
            print(
                f"SIGNING_REQUEST_OK path={request_path} candidate={request['candidate_id']} "
                f"ready={str(request['ready_for_signing']).lower()} blockers={len(request['blockers'])}"
            )
        else:
            request = verify_request(
                root, metadata_path, policy_path, candidate_root, request_path
            )
            print(
                f"SIGNING_REQUEST_VERIFY_OK candidate={request['candidate_id']} "
                f"ready={str(request['ready_for_signing']).lower()} blockers={len(request['blockers'])}"
            )
    except (OSError, SigningError, candidate.ReleaseError) as exc:
        print(f"SIGNING_PROVENANCE_FAILED {exc}", file=os.sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
