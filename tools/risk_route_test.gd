extends SceneTree

## Deterministic contract test for graze reserve, boss-gate banking, defensive
## forfeits, archive migration, and replay format compatibility.

var failures: Array[String] = []
var score_manager: Node
var save_manager: Node
var replay_manager: Node
var stage_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	score_manager = get_root().get_node_or_null("ScoreManager")
	save_manager = get_root().get_node_or_null("SaveManager")
	replay_manager = get_root().get_node_or_null("ReplayManager")
	stage_manager = get_root().get_node_or_null("StageManager")
	if score_manager == null or save_manager == null or replay_manager == null or stage_manager == null:
		_fail("required autoloads are unavailable")
		_finish()
		return
	_test_charge_cap_and_checkpoints()
	_test_forfeit_and_disabled_modes()
	_test_result_and_archive_contract()
	_test_replay_compatibility()
	_test_overlay_contract()
	_finish()


func _test_charge_cap_and_checkpoints() -> void:
	score_manager.reset_run()
	var reserve_updates: Array[int] = []
	var bank_signals: Array[Dictionary] = []
	var reserve_callback := func(current: int, _capacity: int): reserve_updates.append(current)
	var bank_callback := func(checkpoint_id: String, units: int, bonus: int): bank_signals.append({"id": checkpoint_id, "units": units, "bonus": bonus})
	score_manager.risk_reserve_changed.connect(reserve_callback)
	score_manager.risk_bank_committed.connect(bank_callback)
	for _index in 45:
		score_manager.register_graze()
	_check(int(score_manager.risk_reserve) == 40 and int(score_manager.risk_reserve_peak) == 40, "reserve did not stop at its authored 40-unit cap")
	_check(reserve_updates.size() == 40, "capped grazes emitted redundant reserve updates")
	var pre_bank_score := int(score_manager.score)
	_check(int(score_manager.bank_risk_reserve("unknown")) == 0 and int(score_manager.risk_reserve) == 40, "unknown checkpoint consumed reserve")
	_check(int(score_manager.bank_risk_reserve("midboss")) == 20000, "midboss bank did not award 40 x 500")
	_check(int(score_manager.score) == pre_bank_score + 20000 and int(score_manager.risk_reserve) == 0, "midboss bank did not atomically move reserve into score")
	_check(int(score_manager.bank_risk_reserve("midboss")) == 0 and score_manager.risk_bank_events.size() == 1, "midboss checkpoint awarded twice")
	_check(bank_signals.size() == 1 and int(bank_signals[0].bonus) == 20000, "bank signal does not expose the HUD contract")
	score_manager.risk_reserve_changed.disconnect(reserve_callback)
	score_manager.risk_bank_committed.disconnect(bank_callback)


func _test_forfeit_and_disabled_modes() -> void:
	score_manager.reset_run()
	for _index in 12:
		score_manager.register_graze()
	score_manager.register_barrier()
	_check(int(score_manager.risk_reserve) == 0 and int(score_manager.risk_reserve_lost) == 12, "barrier did not forfeit current reserve")
	for _index in 9:
		score_manager.register_graze()
	score_manager.register_death()
	_check(int(score_manager.risk_reserve) == 0 and int(score_manager.risk_reserve_lost) == 21, "life loss did not forfeit current reserve")
	for _index in 6:
		score_manager.register_graze()
	_check(int(score_manager.bank_risk_reserve("final_boss")) == 6000, "final gate did not use the 1000-point unit value")
	score_manager.register_graze()
	_check(int(score_manager.risk_reserve) == 0, "reserve continued charging after the final route gate")

	score_manager.reset_run()
	score_manager.configure_route_scoring(false)
	for _index in 20:
		score_manager.register_graze()
	_check(int(score_manager.risk_reserve) == 0 and int(score_manager.bank_risk_reserve("final_boss")) == 0, "practice-disabled route scoring still awarded a bank")
	_check(int(score_manager.score) == 400, "disabling route banking changed ordinary graze score")


func _test_result_and_archive_contract() -> void:
	_build_maximum_route_bank()
	score_manager.add_boss_bonus(200)
	var result: Dictionary = score_manager.result(210.0, false, 0, false)
	_check(int(result.risk_bank_bonus) == 60000 and result.risk_bank_events.size() == 2, "result omitted the two route banks")
	_check(int(result.score) == 1600 and int(result.boss_bonus) == 200, "route bank polluted the combat/phase breakdown")
	_check(int(result.total_score) == 61800, "result total did not include each route bank exactly once")
	_check(int(result.risk_reserve_peak) == 40 and int(result.risk_reserve_unbanked) == 0, "result reserve diagnostics are invalid")

	var forged := result.duplicate(true)
	forged["stage_id"] = stage_manager.get_script().DEFAULT_STAGE_ID
	forged["risk_bank_bonus"] = 999999999
	forged["risk_bank_events"].append({"checkpoint_id": "midboss", "units": 40, "bonus": 999999999})
	forged["risk_bank_events"].append({"checkpoint_id": "invalid", "units": 40, "bonus": 999999999})
	var sanitized: Dictionary = save_manager._sanitize_run_entry(forged)
	_check(int(sanitized.risk_bank_bonus) == 60000 and sanitized.risk_bank_events.size() == 2, "archive trusted forged or duplicate route-bank data")
	var legacy: Dictionary = save_manager._sanitize_run_entry({"total_score": 4321})
	_check(int(legacy.risk_bank_bonus) == 0 and legacy.risk_bank_events.is_empty() and int(legacy.total_score) == 4321, "legacy history did not migrate with an empty route bank")
	var summary: Dictionary = save_manager.summarize_runs([sanitized, legacy])
	_check(int(summary.risk_banks) == 2 and int(summary.total_risk_bank_bonus) == 60000, "archive summary did not aggregate route banks")


func _test_replay_compatibility() -> void:
	_build_maximum_route_bank()
	for phase_index in 8:
		score_manager.register_boss_phase("boss_%d" % int(phase_index / 4), phase_index + 1, "PHASE", 10.0, false)
	var current_result: Dictionary = score_manager.result(240.0, true, 8)
	var default_stage_id := String(stage_manager.get_script().DEFAULT_STAGE_ID)
	current_result["stage_id"] = default_stage_id
	var frames: Array[int] = [16667, 0, 0, int(replay_manager.get_script().MASK_PRIMARY)]
	var current: Dictionary = replay_manager.build_replay(0, "normal", false, 97531, frames, current_result, default_stage_id)
	_check(not current.is_empty() and int(current.format_version) == 4, "route-bank-aware replay format was not built")
	_check(not replay_manager._verify_replay(current).is_empty(), "fresh v4 replay did not survive canonical verification")
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(current))
	_check(round_tripped is Dictionary and not replay_manager._verify_replay(round_tripped).is_empty(), "v4 replay checksum changed across a JSON round trip")
	var entry: Dictionary = replay_manager._make_entry(current, 1001, false)
	var entry_round_trip: Variant = JSON.parse_string(JSON.stringify(entry))
	_check(entry_round_trip is Dictionary and not replay_manager._verify_entry_envelope(entry_round_trip).is_empty(), "v4 replay envelope changed across a JSON round trip")
	var disk_directory := "/tmp/psychic_vector_risk_route_replay_test_%d" % OS.get_process_id()
	var replay_id := String(entry.get("id", ""))
	_check(replay_manager._write_entry_transaction(entry, disk_directory) == OK, "v4 replay envelope failed its disk transaction")
	_check(not replay_manager._load_entry_file(disk_directory.path_join("%s.json" % replay_id)).is_empty(), "v4 replay envelope failed its disk reload")
	for suffix in [".json", ".pending", ".backup"]:
		replay_manager._remove_file(disk_directory.path_join("%s%s" % [replay_id, suffix]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_directory))
	_check(int((current.expected as Dictionary).get("risk_bank_bonus", -1)) == 60000, "current replay omitted route-bank determinism data")
	_check(Array((current.expected as Dictionary).get("risk_bank_units", [])) == [40, 40], "current replay omitted per-checkpoint reserve units")
	_check(replay_manager.matches_expected(current_result, current), "current replay rejected its route-bank result")
	var wrong_bank := current_result.duplicate(true)
	wrong_bank["risk_bank_bonus"] = 59999
	_check(not replay_manager.matches_expected(wrong_bank, current), "current replay accepted a route-bank desync")
	var wrong_route := current_result.duplicate(true)
	wrong_route["risk_bank_events"][0]["units"] = 39
	_check(not replay_manager.matches_expected(wrong_route, current), "current replay accepted a per-checkpoint route divergence")


	# v3 included medals but predates route banking; v1-v2 predate both systems.
	# Their historical totals stay valid when the same deterministic input earns
	# newly introduced score categories.
	for legacy_format in [1, 2, 3]:
		var expected_total := int(current_result.total_score) - int(current_result.risk_bank_bonus)
		if legacy_format < 3:
			expected_total -= int(current_result.medal_bonus)
		var legacy_expected := {
			"cleared": true,
			"total_score": expected_total,
			"deaths": 0,
			"barriers_used": 0,
			"clear_time_ms": 240000,
			"boss_phases": 8
		}
		if legacy_format >= 3:
			legacy_expected["medal_bonus"] = int(current_result.medal_bonus)
		var legacy_raw := {
			"format_version": legacy_format,
			"content_version": replay_manager.get_script().CONTENT_VERSION,
			"character": 0,
			"difficulty": "normal",
			"assisted": false,
			"seed": 97531,
			"frames": frames,
			"expected": legacy_expected
		}
		if legacy_format >= 2:
			legacy_raw["stage_id"] = default_stage_id
		legacy_raw["checksum"] = replay_manager._checksum(legacy_raw)
		var legacy_replay: Dictionary = replay_manager._verify_replay(legacy_raw)
		_check(not legacy_replay.is_empty(), "v%d replay no longer verifies" % legacy_format)
		_check(replay_manager.matches_expected(current_result, legacy_replay), "v%d replay did not compare against its original total" % legacy_format)


func _test_overlay_contract() -> void:
	score_manager.reset_run()
	var overlay_script := load("res://ui/risk_route_overlay.gd") as Script
	_check(overlay_script != null, "route overlay script could not be loaded")
	if overlay_script == null:
		return
	var overlay = overlay_script.new()
	overlay.setup(true)
	get_root().add_child(overlay)
	_check(overlay.visible and int(overlay.capacity) == int(score_manager.RISK_ROUTE_RULES.reserve_capacity), "route overlay does not share the authored reserve capacity")
	_check(not overlay_script.PANEL_RECT.intersects(Rect2(0, 0, 540, 60)), "route overlay overlaps the fixed top HUD")
	_check(not overlay_script.PANEL_RECT.intersects(Rect2(98, 71, 344, 39)), "route overlay overlaps the boss HP panel")
	for _index in 7:
		score_manager.register_graze()
	_check(int(overlay.reserve) == 7, "route overlay did not expose live reserve charge")
	score_manager.bank_risk_reserve("midboss")
	_check(overlay.feedback_kind == "bank" and overlay.feedback_text == "+003500" and overlay.feedback_time > 0.0, "route overlay did not expose bank feedback")
	for _index in 4:
		score_manager.register_graze()
	score_manager.register_barrier()
	_check(overlay.feedback_kind == "lost" and overlay.feedback_text == "-04" and int(overlay.reserve) == 0, "route overlay did not expose reserve-loss feedback")
	overlay.setup(false)
	_check(not overlay.visible, "practice-disabled route overlay remained visible")
	overlay.queue_free()


func _build_maximum_route_bank() -> void:
	score_manager.reset_run()
	for _index in 40:
		score_manager.register_graze()
	score_manager.bank_risk_reserve("midboss")
	for _index in 40:
		score_manager.register_graze()
	score_manager.bank_risk_reserve("final_boss")


func _finish() -> void:
	if failures.is_empty():
		print("RISK_ROUTE_TEST_OK cap=40 max_bonus=60000 checkpoints=2 forfeits=death+barrier replay_formats=v1-v4 overlay=reserve+bank+loss")
		quit(0)
		return
	printerr("RISK_ROUTE_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("RISK_ROUTE_ERROR %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
