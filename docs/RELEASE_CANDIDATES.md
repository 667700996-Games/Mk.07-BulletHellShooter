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
and developer tools are excluded from every export.

## Validate without export templates

Run these checks on any development or CI machine:

```sh
python3 tools/release_candidate.py check
python3 tools/release_candidate.py self-test
python3 tools/export_artifact_audit.py self-test
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
It has read-only repository
permissions, cannot publish a release, and never receives signing or store secrets.

`tools/release_candidate.py check` binds the workflow's engine version, template
requirement, exact export commands, package/verify sequence, failure-on-missing-files
behavior, and artifact action. The workflow and ordinary validation workflow are
also included in the candidate manifest's source-configuration hashes. Pipeline
drift therefore fails before packaging or makes an existing candidate unverifiable.

## Build an unsigned candidate

On a controlled build machine, install the export templates for the exact Godot
version declared in the release metadata. Bump `version` and `build_number` in the
metadata and keep `project.godot`'s version identical. Then run:

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

The packager only consumes the three expected, non-empty regular files. It writes a
versioned directory such as
`dist/PsychicVector-0.1.0-alpha.1-build.1-unsigned/`, containing one deterministic
stored ZIP per platform and `release-manifest.json`. ZIP timestamps, member order,
paths, and permissions are normalized. Each package contains a `RELEASE.json` plus
the exported binary, with SHA-256 and byte size recorded both inside the package and
in the outer manifest. The manifest also binds the release metadata, project
settings, export presets, and both build workflows by SHA-256. Extra files, unsafe
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
  --candidate-dir dist/PsychicVector-0.1.0-alpha.1-build.1-unsigned \
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

## Deliberate external gates

These packages say `unsigned=true` in both metadata layers and are not public release
artifacts. A production candidate still requires:

- review and approval of the template/action supply chain used by the build environment;
- Windows signing credentials and timestamping;
- replacement of the provisional macOS bundle identifier with an owned identity,
  Developer ID signing, hardened runtime, and
  notarization;
- final Linux distribution format and signing policy;
- protected artifact storage, store credentials, and an upload/rollout service that
  consumes the verified channel pointer;
- target-hardware installation, launch, update, and rollback certification.

Signing and distribution should wrap a manifest-verified candidate rather than
silently changing its contents. Signed deliverables need their own post-signing
checksums and provenance record because signing necessarily changes the binary bytes.
