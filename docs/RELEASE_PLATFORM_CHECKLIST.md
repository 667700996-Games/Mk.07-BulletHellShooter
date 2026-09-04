# Release platform checklist

The automated platform contract is a configuration gate, not a platform certification:

```sh
godot --headless --path . --script res://tools/platform_release_audit.gd -- --smoke-platform
```

It verifies the three supported desktop export presets (Windows x86_64, macOS universal, and Linux x86_64), their portable output paths and production-only filters, desktop texture support, platform feature tags, the 540×960 portrait/stretch/window defaults, the square project icon, and authored keyboard/controller parity for every player action. It also checks that fullscreen is a persisted window setting and that core combat bindings remain remappable.

The manual candidate workflow additionally launches the exact archived package on
native Windows, macOS, and Linux runners. Each run emits a candidate/package/tool-
bound receipt after package boot, a 9-run three-stage lifecycle soak, and a 300-frame
4,000-bullet benchmark below 16.667ms; `native_smoke_evidence.py` produces a complete matrix
receipt only when all three come from the same GitHub run and commit. Preserve that
artifact with the candidate. It covers a package-only headless launch, not the wider
hardware certification below.

The Linux public-delivery contract is no longer open-ended: package the standalone
binary as `tar.zst`, sign that payload with the authorized OpenPGP release key, and
retain the detached armored `.asc` signature. The signed-delivery receipt binds
both files independently; choosing the actual release-key identity and conducting
the key ceremony remain external security responsibilities.

Before any release candidate can be called certified, complete and record these checks on native target hardware:

- Install the matching Godot export templates and produce clean exports from a tagged revision.
- Sign Windows and macOS builds; notarize the macOS build. The repository preset is intentionally unsigned.
- Launch, suspend/resume, quit, and perform a full campaign clear on supported Windows, macOS, and Linux versions.
- Test controller connection, disconnection, reconnection, remapping, focus recovery, and at least Xbox-, PlayStation-, and generic-SDL-style devices.
- Exercise windowed and exclusive fullscreen transitions on common 16:9, 16:10, ultrawide, and high-DPI displays; confirm the 9:16 playfield remains intact with expected letterboxing/pillarboxing.
- Verify save/replay migration and corruption recovery from a packaged build, then run a multi-hour soak and platform performance capture.
- Retain the complete native-smoke matrix, raw platform logs, hardware/driver inventory, tester, date, and candidate ID with the certification record.

Do not treat a passing headless audit as evidence that signing, drivers, display hardware, OS integration, or storefront requirements have passed.

## Steam graphical handoff

The upload-ready graphical set is generated separately from the runtime candidate:

```sh
godot --path . -- --capture-store-sources
godot --headless --path . --script res://tools/store_asset_builder.gd
python3 tools/store_asset_audit.py
```

`docs/STORE_ASSETS.md` lists every current official size, content restriction, and
manual portal step. The audit proves local dimensions, source/output hashes,
English gameplay-capture count, transparent logo format, export exclusion, and
candidate binding. It does not prove Steamworks upload, live-template preview,
content-rating flags, alt text, App-ID ownership, or Valve approval; retain screenshots
of those portal checks with the platform certification record.
