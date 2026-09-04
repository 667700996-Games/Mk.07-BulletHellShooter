# Release platform checklist

The automated platform contract is a configuration gate, not a platform certification:

```sh
godot --headless --path . --script res://tools/platform_release_audit.gd -- --smoke-platform
```

It verifies the three supported desktop export presets (Windows x86_64, macOS universal, and Linux x86_64), their portable output paths and production-only filters, desktop texture support, platform feature tags, the 540×960 portrait/stretch/window defaults, the square project icon, and authored keyboard/controller parity for every player action. It also checks that fullscreen is a persisted window setting and that core combat bindings remain remappable.

Before any release candidate can be called certified, complete and record these checks on native target hardware:

- Install the matching Godot export templates and produce clean exports from a tagged revision.
- Sign Windows and macOS builds; notarize the macOS build. The repository preset is intentionally unsigned.
- Launch, suspend/resume, quit, and perform a full campaign clear on supported Windows, macOS, and Linux versions.
- Test controller connection, disconnection, reconnection, remapping, focus recovery, and at least Xbox-, PlayStation-, and generic-SDL-style devices.
- Exercise windowed and exclusive fullscreen transitions on common 16:9, 16:10, ultrawide, and high-DPI displays; confirm the 9:16 playfield remains intact with expected letterboxing/pillarboxing.
- Verify save/replay migration and corruption recovery from a packaged build, then run a multi-hour soak and platform performance capture.

Do not treat a passing headless audit as evidence that signing, drivers, display hardware, OS integration, or storefront requirements have passed.
