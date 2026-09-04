extends SceneTree

## Focused regression test for the data-driven end-of-run medal layer.
## It exercises scoring, mutually independent goals, deduplication, save
## sanitization, localization, and pre-medal replay compatibility.

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
		failures.append("required autoloads are unavailable")
		_finish()
		return
	_test_medal_scoring()
	_test_independent_conditions()
	_test_archive_sanitization()
	_test_replay_compatibility()
	_test_localization_contract()
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("PERFORMANCE_MEDAL_TEST_OK medals=%d max_bonus=%d replay_formats=legacy+current locales=2" % [
			score_manager.get_script().MEDAL_DEFINITIONS.size(),
			score_manager.medal_bonus_for_ids(["no_miss", "no_barrier", "phase_perfect"])
		])
		quit(0)
		return
	printerr("PERFORMANCE_MEDAL_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("PERFORMANCE_MEDAL_ERROR %s" % failure)
	quit(1)


func _test_medal_scoring() -> void:
	score_manager.reset_run()
	score_manager.add_score(800)
	score_manager.add_boss_bonus(200)
	_register_phase_fixture(8)
	var result: Dictionary = score_manager.result(240.0, true, 8)
	var expected_ids := ["no_miss", "no_barrier", "phase_perfect"]
	_check(Array(result.medals) == expected_ids, "perfect clear did not earn each medal exactly once")
	_check(int(result.medal_bonus) == 275000, "perfect clear medal bonus is not the authored 275000")
	_check(int(result.score) == 800 and int(result.boss_bonus) == 200, "medals changed the combat/phase score breakdown")
	_check(int(result.total_score) == 276000, "medal bonus was not added exactly once to total score")
	var repeated: Dictionary = score_manager.result(240.0, true, 8)
	_check(int(repeated.total_score) == int(result.total_score), "re-reading a result accumulated the medal bonus")
	_check(score_manager.normalize_medal_ids(["no_miss", "no_miss", "invalid"]) == ["no_miss"], "medal ID normalization did not deduplicate or reject unknown IDs")


func _test_independent_conditions() -> void:
	score_manager.reset_run()
	score_manager.register_death()
	_register_phase_fixture(8)
	var death_result: Dictionary = score_manager.result(250.0, true, 8)
	_check(not death_result.medals.has("no_miss"), "a life loss still earned the no-miss medal")
	_check(death_result.medals.has("no_barrier") and death_result.medals.has("phase_perfect"), "a life loss removed unrelated medals")

	score_manager.reset_run()
	score_manager.register_barrier()
	_register_phase_fixture(8)
	var barrier_result: Dictionary = score_manager.result(250.0, true, 8)
	_check(not barrier_result.medals.has("no_barrier"), "a barrier activation still earned the no-barrier medal")
	_check(barrier_result.medals.has("no_miss") and barrier_result.medals.has("phase_perfect"), "a barrier activation removed unrelated medals")

	score_manager.reset_run()
	_register_phase_fixture(8, 5)
	var late_phase_result: Dictionary = score_manager.result(250.0, true, 8)
	_check(not late_phase_result.medals.has("phase_perfect"), "an Overdrive phase still earned phase-perfect")
	_check(late_phase_result.medals.has("no_miss") and late_phase_result.medals.has("no_barrier"), "an Overdrive phase removed unrelated medals")

	score_manager.reset_run()
	_register_phase_fixture(7)
	var incomplete_result: Dictionary = score_manager.result(250.0, true, 8)
	_check(not incomplete_result.medals.has("phase_perfect"), "an incomplete boss route earned phase-perfect")

	score_manager.reset_run()
	_register_phase_fixture(8)
	var failed_result: Dictionary = score_manager.result(250.0, false, 8)
	_check(failed_result.medals.is_empty() and int(failed_result.medal_bonus) == 0, "a failed route earned operation medals")
	var practice_result: Dictionary = score_manager.result(250.0, true, 8, false)
	_check(practice_result.medals.is_empty() and int(practice_result.medal_bonus) == 0, "medals were awarded when explicitly disabled for practice")


func _test_archive_sanitization() -> void:
	var sanitized: Dictionary = save_manager._sanitize_run_entry({
		"stage_id": stage_manager.get_script().DEFAULT_STAGE_ID,
		"difficulty": "normal",
		"total_score": 999999,
		"medals": ["no_miss", "no_miss", "../spoof", "no_barrier"],
		"medal_bonus": 999999999
	})
	_check(Array(sanitized.medals) == ["no_miss", "no_barrier"], "archive sanitizer did not normalize medal IDs")
	_check(int(sanitized.medal_bonus) == 150000, "archive sanitizer trusted a forged medal bonus")
	var legacy: Dictionary = save_manager._sanitize_run_entry({"total_score": 4321})
	_check(legacy.medals.is_empty() and int(legacy.medal_bonus) == 0 and int(legacy.total_score) == 4321, "legacy run history did not migrate losslessly")
	var summary: Dictionary = save_manager.summarize_runs([sanitized, legacy])
	_check(int(summary.medals_earned) == 2 and int(summary.total_medal_bonus) == 150000, "archive summary did not aggregate medal performance")
	_check(int((summary.medal_counts as Dictionary).get("no_miss", 0)) == 1, "archive summary double-counted a medal")


func _test_replay_compatibility() -> void:
	var frames: Array[int] = [16667, 0, 0, int(replay_manager.get_script().MASK_PRIMARY)]
	score_manager.reset_run()
	score_manager.add_score(1000)
	_register_phase_fixture(8)
	var current_result: Dictionary = score_manager.result(240.0, true, 8)
	var default_stage_id := String(stage_manager.get_script().DEFAULT_STAGE_ID)
	current_result["stage_id"] = default_stage_id
	var current: Dictionary = replay_manager.build_replay(0, "normal", false, 24680, frames, current_result, default_stage_id)
	_check(not current.is_empty() and int(current.format_version) == int(replay_manager.get_script().FORMAT_VERSION), "current medal-aware replay could not be built")
	_check(int((current.expected as Dictionary).get("medal_bonus", -1)) == int(current_result.medal_bonus), "current replay omitted its medal bonus")
	_check(replay_manager.matches_expected(current_result, current), "current replay rejected its deterministic medal result")
	var wrong_bonus := current_result.duplicate(true)
	wrong_bonus["medal_bonus"] = int(current_result.medal_bonus) - 1
	_check(not replay_manager.matches_expected(wrong_bonus, current), "current replay accepted a medal-bonus desync")

	var legacy_raw := {
		"format_version": 2,
		"content_version": replay_manager.get_script().CONTENT_VERSION,
		"stage_id": default_stage_id,
		"character": 0,
		"difficulty": "normal",
		"assisted": false,
		"seed": 24680,
		"frames": frames,
		"expected": {
			"cleared": true,
			"total_score": int(current_result.total_score) - int(current_result.medal_bonus),
			"deaths": 0,
			"barriers_used": 0,
			"clear_time_ms": 240000,
			"boss_phases": 8
		}
	}
	legacy_raw["checksum"] = replay_manager._checksum(legacy_raw)
	var legacy_replay: Dictionary = replay_manager._verify_replay(legacy_raw)
	_check(not legacy_replay.is_empty(), "pre-medal replay format no longer verifies")
	_check(replay_manager.matches_expected(current_result, legacy_replay), "pre-medal replay did not compare against its original combat total")


func _test_localization_contract() -> void:
	var text_script := load("res://resources/game_text.gd") as Script
	for definition in score_manager.medal_definitions():
		for field in ["title_key", "description_key"]:
			var key := String(definition.get(field, ""))
			_check(text_script.EN.has(key) and text_script.KO.has(key), "medal localization key is missing: %s" % key)
	_check(text_script.EN.has("performance_medals") and text_script.KO.has("performance_medals"), "medal section localization is missing")
	_check(text_script.EN.has("medal_bonus") and text_script.KO.has("medal_bonus"), "medal bonus localization is missing")


func _register_phase_fixture(count: int, overdrive_phase: int = -1) -> void:
	for index in count:
		score_manager.register_boss_phase(
			"boss_%d" % int(index / 4),
			index + 1,
			"PHASE %d" % (index + 1),
			10.0,
			index == overdrive_phase
		)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
