#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"

"${GODOT_BIN}" --headless --editor --path . --quit
"${GODOT_BIN}" --headless --path . --quit-after 600 -- --smoke-ui
"${GODOT_BIN}" --headless --path . --quit-after 900 -- --smoke-combat
"${GODOT_BIN}" --headless --path . --quit-after 1800 -- --smoke-stage
"${GODOT_BIN}" --headless --path . --quit-after 600 -- --benchmark-bullets
