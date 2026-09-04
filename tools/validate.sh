#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"

run_checked() {
	local log_file engine_log exit_code
	local -a command
	log_file="$(mktemp "${TMPDIR:-/tmp}/psychic_vector_validate.XXXXXX")"
	engine_log=""
	command=("$@")
	if [[ "${command[0]}" == "${GODOT_BIN}" ]]; then
		engine_log="$(mktemp "${TMPDIR:-/tmp}/psychic_vector_engine.XXXXXX")"
		command=("${command[0]}" --log-file "${engine_log}" "${command[@]:1}")
	fi
	set +e
	"${command[@]}" 2>&1 | tee "${log_file}"
	exit_code="${PIPESTATUS[0]}"
	set -e
	if grep -Eq "SCRIPT ERROR:|Assertion failed:|Parse Error:" "${log_file}"; then
		exit_code=1
	fi
	rm -f "${log_file}"
	if [[ -n "${engine_log}" ]]; then
		rm -f "${engine_log}"
	fi
	return "${exit_code}"
}

run_checked "${GODOT_BIN}" --headless --editor --path . --quit
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/release_candidate.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/export_artifact_audit.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/native_candidate_smoke.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/native_smoke_evidence.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/crash_support_bundle.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/linux_delivery.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/signing_provenance.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/signed_delivery.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/release_channel.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/release_delta.py self-test
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/playtest_gate_test.py
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/data_policy_audit.py
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/content_budget_audit.py
PYTHONPYCACHEPREFIX="${TMPDIR:-/tmp}/psychic_vector_pycache" python3 tools/store_asset_audit.py source
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/platform_release_audit.gd -- --smoke-platform
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/content_audit.gd -- --smoke-content
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/session_diagnostics_test.gd -- --smoke-session-diagnostics
run_checked "${GODOT_BIN}" --headless --path . --quit-after 120 res://tests/boss_signature_registry_smoke.tscn -- --smoke-boss-signatures
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/performance_medal_test.gd -- --smoke-medals
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/risk_route_test.gd -- --smoke-risk-route
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/briefing_medal_test.gd -- --smoke-briefing-medals
run_checked "${GODOT_BIN}" --headless --path . --script res://tools/ui_layout_audit.gd -- --smoke-layout
run_checked "${GODOT_BIN}" --headless --path . --quit-after 120 res://tests/radio_comms_smoke.tscn -- --smoke-radio
run_checked "${GODOT_BIN}" --headless --path . --quit-after 120 res://tests/campaign_ending_smoke.tscn -- --smoke-ending
run_checked "${GODOT_BIN}" --headless --path . --quit-after 600 -- --smoke-ui
run_checked "${GODOT_BIN}" --headless --path . --quit-after 900 -- --smoke-combat
run_checked "${GODOT_BIN}" --headless --path . --quit-after 1800 -- --smoke-stage
run_checked "${GODOT_BIN}" --headless --path . --quit-after 1800 -- --smoke-tempest
run_checked "${GODOT_BIN}" --headless --path . --quit-after 1800 -- --smoke-forge
run_checked "${GODOT_BIN}" --headless --path . --quit-after 12000 -- --smoke-soak
run_checked "${GODOT_BIN}" --headless --path . --quit-after 600 -- --benchmark-bullets
