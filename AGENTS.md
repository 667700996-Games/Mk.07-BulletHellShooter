# Project work rules

## Build cleanup is required

- This is a Godot 4.7.2 desktop project: Windows x86_64, macOS universal, Linux x86_64. Read `release/release_metadata.json`, `export_presets.cfg`, workflows and [the cleanup policy](docs/BUILD_CLEANUP.md) before changing build tooling. Do not infer mobile targets from its portrait canvas.
- Use `python3 tools/build_desktop.py` for development exports, `--release` for immutable release candidates, and `bash tools/validate.sh` for validation. Do not export over a previous successful artifact in `build/`.
- Every new build/packaging tool must use `build_workspace.cli/session`, `managed_tempfile`, and `build_workspace.run`. Work goes exclusively in an owned `build/.work/jobs/<id>/tmp` directory. Use the engine lock for Godot imports/exports and the publication lock for shared output mutation. Never launch detached workers without an independent lease.
- Clean on success, failure, cancellation and ordinary termination. Recover abandoned owned jobs at startup with locks and process checks. Unknown owners, active jobs, symlinks/junctions and cleanup errors must be preserved and reported with their paths. Do not recursively remove an arbitrary user-supplied output/cache path.
- Verify a complete staged package before publication. Publish atomically; an existing release candidate ID is immutable. Never delete a good release to make room for an unverified replacement.
- Retain two owned successful development package sets and ten bounded raw command logs (at most 1 MiB each). Apply no automatic count limit to release/channel archives, patches, rollback inputs, signing files, native evidence, support records or symbols.
- Do not accumulate date/number copies or extracted applications without a specific need. A debug retention exception requires a `KEEP.json` recording purpose, location and deletion date/event; remove it when resolved. Unknown historical outputs require review, not adoption into automatic deletion.
- Preserve sources/assets/configuration, credentials/keys/plugins, user saves and the Git repository. Shared Godot/template/dependency caches are not per-build garbage. Do not clean anything outside the project without explicit authorization.
- Verify cleanup changes with `python3 tools/build_workspace_test.py`, relevant existing tool self-tests and one representative real build when available. Record untested host/platform paths honestly.
