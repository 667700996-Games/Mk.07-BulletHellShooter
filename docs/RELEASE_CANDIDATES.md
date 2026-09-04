# Unsigned release candidates

This repository has a deterministic packaging and verification layer for the three
desktop export presets. It deliberately stops before code signing, notarization,
store upload, or publication.

`release/release_metadata.json` is the release contract. Its product version must
match `application/config/version` in `project.godot`; its Godot version must match
the pinned validation workflow; and every declared preset must match
`export_presets.cfg` exactly. Windows and Linux embed their PCK so each export is a
single executable. Tests and developer tools are excluded from every export.

## Validate without export templates

Run these checks on any development or CI machine:

```sh
python3 tools/release_candidate.py check
python3 tools/release_candidate.py self-test
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
then uploads the `dist/` candidate for 14 days. It has read-only repository
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

Keep a previously verified candidate directory intact to provide an artifact-level
rollback point; never mix packages from different candidate directories. An
artifact host should rerun `verify` immediately before upload or restoration.

## Deliberate external gates

These packages say `unsigned=true` in both metadata layers and are not public release
artifacts. A production candidate still requires:

- review and approval of the template/action supply chain used by the build environment;
- Windows signing credentials and timestamping;
- an owned macOS bundle identifier, Developer ID signing, hardened runtime, and
  notarization;
- final Linux distribution format and signing policy;
- protected artifact storage, store credentials, and an upload/rollout service;
- target-hardware installation, launch, update, and rollback certification.

Signing and distribution should wrap a manifest-verified candidate rather than
silently changing its contents. Signed deliverables need their own post-signing
checksums and provenance record because signing necessarily changes the binary bytes.
