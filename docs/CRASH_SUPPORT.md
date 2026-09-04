# Offline crash support

Release builds keep up to five rotating Godot runtime logs at
`user://logs/psychic_vector.log`. GDScript call-stack tracking is enabled for
release exports, stdout is flushed when the game writes its sparse session
markers, and every successfully opened session writes its release-candidate ID
to the log. The session journal and its manual diagnostic JSON remain separate:
they infer a missing clean-exit marker but are not native crash dumps.

Nothing is uploaded automatically. Runtime logs can contain engine error
backtraces, local file paths, and basic system or driver context. OS-native crash
reports can contain substantially more sensitive process and machine context.
Review every file before it leaves the local support environment.

## Locate the local files

The default desktop paths for this project name are:

- Windows: `%APPDATA%\Godot\app_userdata\PSYCHIC VECTOR\logs\psychic_vector.log`
- macOS: `~/Library/Application Support/Godot/app_userdata/PSYCHIC VECTOR/logs/psychic_vector.log`
- Linux: `$XDG_DATA_HOME/godot/app_userdata/PSYCHIC VECTOR/logs/psychic_vector.log`, or `~/.local/share/godot/app_userdata/PSYCHIC VECTOR/logs/psychic_vector.log` when `XDG_DATA_HOME` is unset

The adjacent rotated files should be preserved when the most recent log does not
contain the failure. The optional manual diagnostic file is
`user://psychic_vector_diagnostics.json`, created only through Combat Archive >
Export Diagnostics.

A native `.dmp`, `.ips`, `.crash`, `.core`, or textual report must come from the
target OS or an authorized debugger. The game does not create or upload one by
itself. Preserve the matching unsigned/signed candidate, the exact source
revision, and any available symbol files with the report.

## Create a candidate-bound support case

The exact candidate must already pass `release_candidate.py verify`. Use a stable,
non-player case identifier and select the platform package that was executed:

```sh
python3 tools/crash_support_bundle.py collect \
  --case-id CASE-0001 \
  --preset "macOS" \
  --runtime-log /private/support/psychic_vector.log \
  --diagnostics /private/support/psychic_vector_diagnostics.json
```

To add an OS-native report, explicitly acknowledge that it may contain sensitive
data:

```sh
python3 tools/crash_support_bundle.py collect \
  --case-id CASE-0002 \
  --preset "Windows Desktop" \
  --runtime-log C:/private/support/psychic_vector.log \
  --native-report C:/private/support/crash.dmp \
  --include-sensitive-native-report
```

The tool writes under `dist/crash-support/<candidate-id>/<case-id>/`, never
overwrites an existing case, and records the exact candidate manifest, platform
package, source-tree fingerprint, tool hash, and every artifact hash. Original
filenames and input paths are not retained. UTF-8 logs and text crash reports are
normalized and common home-directory, email, username, and hostname fields are
redacted. Binary reports cannot be sanitized and are copied only after the
explicit acknowledgement. Redaction is a risk reduction, not a guarantee; every
bundle remains marked for manual review.

Verify the case before analysis, transfer, or archival:

```sh
python3 tools/crash_support_bundle.py verify \
  --bundle dist/crash-support/<candidate-id>/CASE-0001
```

Any changed candidate, manifest, package, tool, source fingerprint, support
manifest, or artifact fails verification. The bundle is not encrypted, signed, or
transmitted by this tool; access control and any approved transfer channel remain
external support responsibilities.

## Symbolication boundary

The exact candidate and local GDScript call stacks make script failures
correlatable. Useful native engine symbolication additionally requires binaries
and debug symbols produced from the matching custom Godot export-template build.
Official stripped export templates do not provide that symbol set. Until a
controlled symbol-bearing template pipeline and native crash exercise are
completed on all supported platforms, a collected support case is evidence-ready
input—not proof that native symbolication or crash certification has passed.
