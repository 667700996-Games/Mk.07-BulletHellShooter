#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"

run_checked() {
	local log_file exit_code
	log_file="$(mktemp "${TMPDIR:-/tmp}/psychic_vector_validate.XXXXXX")"
	set +e
	"$@" 2>&1 | tee "${log_file}"
	exit_code="${PIPESTATUS[0]}"
	set -e
	if grep -Eq "SCRIPT ERROR:|Assertion failed:|Parse Error:" "${log_file}"; then
		exit_code=1
	fi
	rm -f "${log_file}"
	return "${exit_code}"
}

run_checked "${GODOT_BIN}" --headless --editor --path . --quit
run_checked "${GODOT_BIN}" --headless --path . --quit-after 600 -- --smoke-ui
run_checked "${GODOT_BIN}" --headless --path . --quit-after 900 -- --smoke-combat
run_checked "${GODOT_BIN}" --headless --path . --quit-after 1800 -- --smoke-stage
run_checked "${GODOT_BIN}" --headless --path . --quit-after 600 -- --benchmark-bullets
