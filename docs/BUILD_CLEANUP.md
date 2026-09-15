# Build storage and cleanup

## Commands

```sh
python3 tools/build_desktop.py              # all three exports; keep two development successes
python3 tools/build_desktop.py --release    # verified immutable dist/<candidate-id>; no automatic expiry
bash tools/validate.sh                     # owned temporary logs and fixtures
python3 tools/build_workspace.py recover   # also runs automatically at job startup/end
python3 tools/build_workspace_test.py
```

The pinned engine and matching export templates are Godot 4.7.2. Targets are
Windows x86_64, macOS universal and Linux x86_64. A complete build audits all three
containers, packages and verifies their hashes, and boots the current host's native
package before publishing. The CI native matrix adds Windows/macOS/Linux runtime
certification. Only one Godot import/export/validation job uses this checkout's
shared import cache at a time. Close an independently launched editor before
building; editors outside these tools do not participate in the lock.

## Ownership and publication

`build/.work/owner.json` identifies the project. Each random job directory has an
owner record, process lease and registered children. Temporary exports, extraction,
Python fixtures, compression inputs and staging files all live inside that job.
`managed_tempfile` rejects cross-filesystem atomic outputs instead of silently
copying or deleting the destination. Library callers must open a workspace session.
CLI tools install SIGINT/SIGTERM/SIGHUP handlers (and SIGBREAK where supported).
On interruption they stop/reap their subprocess before cleanup; POSIX children
inherit the lease. After SIGKILL or power loss, the next run reclaims only unlocked
jobs whose owner and registered child processes are dead. PID reuse is conservative.
Windows uses byte-range locks and process handles; an interrupted child-registration
window is preserved with an explicit warning for manual inspection.

Collectors serialize under a guard; publication and engine access have separate
locks. Unsafe links/junctions, corrupt ownership and cleanup failures produce
`BUILD_CLEANUP_WARNING remaining=<path>`. Other project roots, Git and shared
system caches are never scanned for deletion. Finished logs are written under the
guard and then pruned, so another running command's log is not removed.

A release candidate is assembled and verified as a whole before an atomic directory
rename. Repeating the exact same candidate is harmless; different bytes for an
existing ID fail and preserve the original. Channel promotion and rollback preserve
all archives and atomically update the index. Delta and Linux delivery staging are
verified before replacement. Engine exports never overwrite the historical files
in `build/windows`, `build/macos` or `build/linux`.

## Retention

| Class | Location / policy |
| --- | --- |
| Source, original art, settings, plugins, credentials | Never clean automatically |
| Godot imported assets | `.godot/`, reusable cache; preserved, not cleared every build |
| Engine/templates/dependency caches outside the project | Preserved; no global cache eviction |
| Temporary work | `build/.work/jobs/`, deleted when unused and owned |
| Successful development package sets | `build/development/<job-id>/`, explicit `.development.json`; latest 2 unpinned successes |
| Raw build/validation command logs | `build/.work/logs/`, latest 10 completed commands, final 1 MiB each; console is streamed in full |
| Release and rollback archives / patch baselines | `dist/`, immutable or explicit release management; no count-based deletion |
| Signing, native evidence, crash support, symbols and mapping files | Preserve with the bound candidate; never apply development/log eviction |
| Store derivatives and capture inputs | `dist/store/steam/`, fixed deterministic delivery set; preserve pending storefront review |
| Disk investigation receipts | `build/disk-audit/`, preserve; excluded from the source fingerprint |

The native certification evidence tool's existing 4 MiB log budget is intentionally
unchanged: these logs are hashed into receipts, and truncating or rotating historical
evidence would invalidate release verification. The 1 MiB rule applies to new raw
build/validation logs, not release evidence or the game's five rotating user logs.

For a development debugging exception, put a `KEEP.json` inside the successful run:

```json
{"purpose":"investigate startup failure", "location":"build/development/<id>", "delete_after":"issue 123 is resolved"}
```

Pinned runs are excluded from the two-run policy. Do not pin live temporary jobs:
copy only the minimum diagnostic data into a documented evidence location. Do not
retain extracted apps or make repeated dated package copies without recording why.
Unknown historical output is never silently enrolled in automatic retention.
Unexpected export sidecars are moved to `build/preserved-extra/<job-id>/` with a
`KEEP.json` and a warning, without expiry. Custom templates must archive symbols
with their candidate; the pinned official templates produce the declared exports.

## Investigation record

The initial investigation found original assets around 69 MiB versus a project
around 17.70 GiB. Eighteen root candidate copies exactly matched all corresponding
files in `dist/channel-alpha/candidates/`. Sixteen redundant root copies were
removed, keeping the two latest root copies and every channel candidate/history,
hosted artifact, signing input, delta, support record and native receipt. No original
art, configuration or shared cache was removed. All four channels were verified
before cleanup. Per-file hashes, exact deletion paths/reasons, directory measurements,
free-space observations and subsequent verification are in `build/disk-audit/`.
This directory is outside the source fingerprint so recording results cannot
invalidate the package just built. No public release or signing completion is
inferred from an unsigned alpha archive.
