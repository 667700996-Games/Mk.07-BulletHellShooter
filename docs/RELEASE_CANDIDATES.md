# Unsigned release candidates

This repository has a deterministic packaging and verification layer for the three
desktop export presets. It deliberately stops before code signing, notarization,
store upload, or publication.

`release/release_metadata.json` is the release contract. Its product version must
match `application/config/version` in `project.godot`; its Godot version must match
the pinned validation workflow; and every declared preset must match
`export_presets.cfg` exactly. Windows and Linux embed their PCK so each export is a
single executable. The prerelease SemVer is mapped to numeric Windows and macOS
resource versions, and the provisional macOS bundle identifier is explicit. Tests
and developer tools, generated build/distribution/playtest data, repository
workflows/docs, and credential-free signing policy are excluded from every export;
the runtime release identity JSON remains included for diagnostics.

## Validate without export templates

Run these checks on any development or CI machine:

```sh
python3 tools/release_candidate.py check
python3 tools/release_candidate.py self-test
python3 tools/export_artifact_audit.py self-test
python3 tools/native_candidate_smoke.py self-test
python3 tools/native_smoke_evidence.py self-test
python3 tools/crash_support_bundle.py self-test
python3 tools/linux_delivery.py self-test
python3 tools/signing_provenance.py self-test
python3 tools/signed_delivery.py self-test
python3 tools/release_delta.py self-test
```

The self-test creates disposable fixture exports outside the repository. It proves
that two packaging runs are byte-identical and that a one-byte package mutation is
rejected. `tools/validate.sh` runs this test before the gameplay suite, while the CI
workflow intentionally keeps `include-templates: false`.

## Template-provisioned CI candidate

The manual `Unsigned release candidate` GitHub Actions workflow is the reproducible
build entry point when local export templates are unavailable. It installs the exact
Godot version and matching templates, runs the complete validation suite, exports all
three configured desktop targets, packages them, reruns strict verification, and only
then uploads the `dist/` candidate for 14 days. Before packaging, it verifies PE/ELF
headers, CPU architectures, the macOS ZIP allowlist and plist/privacy metadata, and
launches the exported Linux release binary through its package-only runtime smoke.
After upload, a fail-independent Windows/macOS/Linux runner matrix downloads the
same candidate, re-verifies every manifest and byte, performs traversal-safe
temporary extraction, and requires the package-only runtime marker from the native
executable before running the exported three-stage nine-run lifecycle soak and
3,993-bullet frame-budget benchmark. Each runner preserves a bounded execution log and canonical receipt
binding its OS, package, candidate/source fingerprint, verifier version, completion
time, and GitHub run/commit identity. A final job accepts the matrix only when all
three receipts and logs share one GitHub Actions run, commit, and release-workflow
provenance and still match the exact candidate;
missing, mixed-run, extra, or modified evidence fails closed. It has read-only repository
permissions, cannot publish a release, and never receives signing or store secrets.

For a local native pass that should leave an auditable receipt, provide both outputs:

```sh
python3 tools/native_candidate_smoke.py smoke --candidate-root dist --preset "macOS" \
  --profile certification \
  --receipt native-evidence/receipts/macos-universal.json \
  --log-output native-evidence/logs/macos-universal.log
```

`native_smoke_evidence.py record` requires all three receipts to contain the boot,
9-run soak, and 300-frame benchmark results within the 16.667ms budget. A complete
matrix is CI-only: it deliberately refuses local-only evidence, incomplete platform
sets, mixed runs/commits, or a different workflow. Individual local receipts prove
only that their bound commands and archived logs passed; they are not a substitute
for the hosted matrix, signed CI attestations, physical-device testing, or
full-campaign certification.

`tools/release_candidate.py check` binds the workflow's engine version, template
requirement, exact export commands, package/verify sequence, failure-on-missing-files
behavior, and artifact action. The workflow and ordinary validation workflow are
also included in the candidate manifest's source-configuration hashes. Pipeline
drift therefore fails before packaging or makes an existing candidate unverifiable.

## Offline crash-support evidence

Release builds keep five rotating local engine logs and write a non-player candidate
marker after the session journal opens. When a failure is reported, the offline
support tool can bind an explicitly supplied runtime log, optional manual diagnostic
JSON, and optional OS-native report to the exact verified candidate and platform
package:

```sh
python3 tools/crash_support_bundle.py collect \
  --case-id CASE-0001 --preset "macOS" \
  --runtime-log /private/support/psychic_vector.log
python3 tools/crash_support_bundle.py verify \
  --bundle dist/crash-support/<candidate-id>/CASE-0001
```

The support tool itself is included in the candidate's source-configuration hashes.
It has no network path, does not overwrite cases, strips original filenames, redacts
common identity-bearing text patterns, and requires an explicit sensitive-data
acknowledgement for native reports. Binary dumps are not sanitized. This is a
collection-integrity contract, not native symbolication or an approved transfer
channel; see `docs/CRASH_SUPPORT.md`.

## Build an unsigned candidate

On a controlled build machine, install the export templates for the exact Godot
version declared in the release metadata. Bump `version` and `build_number` in the
metadata and keep `project.godot`'s version identical. The audited project contract
keeps `editor/export/convert_text_resources_to_binary=false`: Godot 4.7.2's binary
export conversion drops packed string arrays from nested boss-phase resources, while
preserving the text resources keeps their authored attack decks intact. Then run:

```sh
python3 tools/release_candidate.py check
godot --headless --path . --export-release "Windows Desktop" build/windows/PsychicVector.exe
godot --headless --path . --export-release "macOS" build/macos/PsychicVector.zip
godot --headless --path . --export-release "Linux" build/linux/PsychicVector.x86_64
python3 tools/export_artifact_audit.py audit
build/linux/PsychicVector.x86_64 --headless --log-file /tmp/psychic-vector-export-smoke.log --quit-after 300 -- --smoke-export
python3 tools/release_candidate.py package
python3 tools/release_candidate.py verify
```

The packager only consumes the three expected, non-empty regular files. Packaged boot
revalidates every boss definition and the native runner rejects any unexpected Godot
or script error in its raw log; only the exact macOS system-CA lookup warning emitted
by the restricted test host is tolerated. Generated `native-evidence/` files are
excluded from the source fingerprint and all runtime exports, allowing the matrix job
to download receipts and then reverify the unchanged source-bound candidate. It writes a
versioned directory such as
`dist/PsychicVector-0.1.0-alpha.1-build.15-unsigned/`, containing one deterministic
stored ZIP per platform and `release-manifest.json`. ZIP timestamps, member order,
paths, and permissions are normalized. Each package contains a `RELEASE.json` plus
the exported binary, with SHA-256 and byte size recorded both inside the package and
in the outer manifest. Manifest schema 2 also binds a framed SHA-256 fingerprint of
every source file (excluding generated/ignored output) plus the release metadata,
project settings, export presets, validation/signing tools, and both build workflows.
Extra files, unsafe
paths, wrong platforms or architectures, modified configuration, corrupt package
bytes, and unexpected ZIP members make verification fail.

## Offline promotion and rollback contract

Keep candidates intact and use the local channel tool to archive them. Promotion
first runs the source-bound candidate verification, copies the complete candidate
into an immutable channel archive, verifies the copy again, and atomically replaces
only `release-channel.json`. The index records a contiguous promotion/rollback
history and the active candidate; it never edits, mixes, or deletes package bytes.

```sh
python3 tools/release_channel.py promote \
  --candidate-dir dist/PsychicVector-0.1.0-alpha.1-build.15-unsigned \
  --channel-root dist/channel-alpha
python3 tools/release_channel.py verify --channel-root dist/channel-alpha
python3 tools/release_channel.py rollback \
  --channel-root dist/channel-alpha \
  --target-candidate-id PsychicVector-0.1.0-alpha.1-build.1-unsigned
```

An archived candidate remains verifiable after the repository advances to a newer
version: the channel binds the original canonical manifest and every package hash,
then reopens each archive and checks its embedded release metadata and exported-file
hashes. Rollback is allowed only to a candidate that was previously active. Index
or package tampering, unsafe paths, invented history, cross-product packages, and
mixed release channels fail verification. `release_channel.py self-test` proves a
two-candidate promotion followed by rollback and exercises both tamper paths.

This is an offline control-plane contract, not a public updater. A future protected
artifact host can consume the verified active pointer and map it to staged rollout
cohorts. It must preserve the candidate archive, perform an equivalent atomic pointer
change, rerun verification before upload or restoration, and record signed-package
provenance separately.

## Deterministic candidate deltas

Generate a forward-only delta from two immutable candidates and independently verify
or apply it with:

```sh
python3 tools/release_delta.py create \
  --source-candidate dist/channel-alpha/candidates/PsychicVector-0.1.0-alpha.1-build.14-unsigned \
  --target-candidate dist/channel-alpha/candidates/PsychicVector-0.1.0-alpha.1-build.15-unsigned
python3 tools/release_delta.py verify \
  --source-candidate dist/channel-alpha/candidates/PsychicVector-0.1.0-alpha.1-build.14-unsigned \
  --delta dist/deltas/PsychicVector-0.1.0-alpha.1-build.14-unsigned--to--PsychicVector-0.1.0-alpha.1-build.15-unsigned.pvdelta
python3 tools/release_delta.py apply \
  --source-candidate dist/channel-alpha/candidates/PsychicVector-0.1.0-alpha.1-build.14-unsigned \
  --delta dist/deltas/PsychicVector-0.1.0-alpha.1-build.14-unsigned--to--PsychicVector-0.1.0-alpha.1-build.15-unsigned.pvdelta \
  --output-dir /controlled/staging/PsychicVector-0.1.0-alpha.1-build.15-unsigned
```

The deterministic, stored ZIP bundle binds the complete source candidate snapshot,
target snapshot, ordered reconstruction recipes, and every source or literal chunk
by SHA-256. File-role-aware content anchors resynchronize matching 1 MiB source
chunks after shifted ZIP headers or embedded metadata, while new ranges are split
into bounded literal chunks and deduplicated by digest. The verifier rejects
path/member/schema/statistics drift and accepts an
applied result only after the ordinary archived-candidate verifier validates every
reconstructed package and embedded `RELEASE.json`. It never edits the installed game
or the source candidate, never deletes archives, and refuses reverse or same-build
patches. The bundle remains explicitly unsigned: a production service must sign or
otherwise authenticate it, stage rollout cohorts, and apply it from a controlled
temporary directory before an atomic install switch.

## Deliberate external gates

These packages say `unsigned=true` in both metadata layers and are not public release
artifacts. A production candidate still requires:

- review and approval of the template/action supply chain used by the build environment;
- Windows signing credentials and timestamping;
- replacement of the provisional macOS bundle identifier with an owned identity,
  Developer ID signing, hardened runtime, and
  notarization;
- the authorized Linux OpenPGP release-key identity and operational key ceremony
  for the fixed `tar.zst` plus detached armored-signature policy;
- protected artifact storage, store credentials, and an upload/rollout service that
  consumes the verified channel pointer;
- authentication and platform installation integration for candidate delta bundles;
- target-hardware installation, launch, update, and rollback certification.

Signing and distribution should wrap a manifest-verified candidate rather than
silently changing its contents. Signed deliverables need their own post-signing
checksums and provenance record because signing necessarily changes the binary bytes.

## Signing provenance request

`release/signing_policy.json` records the required signing mechanism, native
verification host, delivery format, and identity state for every target without
containing credentials. Generate a canonical request from a verified candidate:

```sh
python3 tools/linux_delivery.py prepare
python3 tools/linux_delivery.py verify
python3 tools/signing_provenance.py prepare
python3 tools/signing_provenance.py verify
```

The Linux preparation step builds a byte-deterministic `tar.zst` with the exact
candidate executable, project LICENSE, and canonical candidate/policy/compressor
metadata. The signing request refuses to proceed without re-verifying that payload
and records it as the Linux signing input. Windows and macOS continue to use their
exported executable/archive as their signing inputs.

The request is written under `dist/signing/<candidate-id>/` and binds the candidate
manifest, all unsigned package/artifact hashes, the complete source-tree
fingerprint, and the signing policy hash. Current unresolved signer identities and
the provisional macOS bundle identifier remain explicit blockers; the Linux delivery
contract is fixed to `tar.zst` with an OpenPGP detached armored signature. A
stable-channel request is rejected while any blocker
remains. The request contains no key material and is not evidence that signing or
notarization has occurred.

## Signed-delivery receipt

After authorized native signing, place the resulting files under
`dist/signing/<candidate-id>/signed/` and one canonical native-verification evidence
JSON file per preset under `dist/signing/<candidate-id>/evidence/`. Then run:

```sh
python3 tools/signed_delivery.py record
python3 tools/signed_delivery.py verify
```

The receipt is created only when the signing request has no policy blockers. It binds
the exact unsigned candidate and source fingerprint to every changed signed artifact,
signer identity, native verification host/tool/time, evidence-file hash, and required
Windows timestamp, macOS hardened-runtime/notarization/staple, or Linux detached-
signature result. For Linux, both the `tar.zst` payload and its `.asc` signature
path, size, and SHA-256 are mandatory receipt fields. Path traversal, symlinks,
missing controls, noncanonical evidence, or any later payload/signature mutation
fails verification. The evidence JSON is a transport
record, not independent cryptographic proof: it must be produced on the named native
platform by a trusted verifier and retained with its logs. The repository contains no
signing keys, cannot manufacture that native evidence, and keeps the current delivery
gate closed while signer identities and the owned macOS bundle identity remain
pending.

OpenPGP detached signing must not rewrite the prepared Linux payload: copy the
verified `prepared/linux-x86_64/PsychicVector.tar.zst` byte-for-byte into the
`signed/linux-x86_64/` directory and create only its armored `.asc` sibling.
The delivery verifier rejects a Linux payload whose hash or size differs from the
request, even if the supplied evidence claims that its signature is valid.
