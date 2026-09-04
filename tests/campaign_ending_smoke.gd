extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var stage_ids := StageManager.stage_ids()
	assert(stage_ids.size() >= 2, "Campaign-ending audit requires a multi-stage catalog")
	var final_stage := StageManager.stage(String(stage_ids[stage_ids.size() - 1]))
	var first_stage := StageManager.stage(String(stage_ids[0]))
	assert(final_stage != null and final_stage.ending_enabled, "Final catalog stage has no authored ending")
	assert(first_stage != null and not first_stage.ending_enabled, "A non-final stage incorrectly enables the campaign ending")
	assert(final_stage.validation_errors().is_empty(), "Final-stage ending data failed StageData validation")

	var ending_stage_count := 0
	for stage_id in stage_ids:
		ending_stage_count += int(StageManager.stage(String(stage_id)).ending_enabled)
	assert(ending_stage_count == 1, "Exactly one final catalog stage must own the current campaign ending")

	var ending_keys := PackedStringArray([
		"campaign_ending", "ending_epilogue", "ending_final_transmission",
		"ending_view_results", "ending_skip_hint", "ending_score_stamp",
		final_stage.ending_eyebrow_key, final_stage.ending_title_key,
		final_stage.ending_body_key, final_stage.ending_transmission_source_key,
		final_stage.ending_transmission_key
	])
	ending_keys.append_array(final_stage.ending_epilogue_keys)
	for text_key in ending_keys:
		assert(GameText.EN.has(text_key) and GameText.KO.has(text_key), "Ending localization is incomplete: %s" % text_key)

	var valid_result := {
		"mode": "campaign", "cleared": true, "stage_id": final_stage.stage_id,
		"total_score": 3456789, "clear_time": 203.45, "character": 0
	}
	assert(CampaignEnding.supports(valid_result, final_stage), "Valid final campaign clear was rejected")
	var rejected := valid_result.duplicate(true)
	rejected.cleared = false
	assert(not CampaignEnding.supports(rejected, final_stage), "Failed run was accepted as an ending")
	rejected = valid_result.duplicate(true)
	rejected.mode = "practice"
	assert(not CampaignEnding.supports(rejected, final_stage), "Practice run was accepted as an ending")
	rejected.mode = "replay"
	assert(not CampaignEnding.supports(rejected, final_stage), "Replay run was accepted as an ending")
	rejected = valid_result.duplicate(true)
	rejected.stage_id = first_stage.stage_id
	assert(not CampaignEnding.supports(rejected, first_stage), "Non-final catalog stage was accepted as an ending")

	var settings_backup := SaveManager.settings.duplicate(true)
	var sfx_cache_backup := AudioManager.sfx_cache
	# This content/UI test does not exercise audio playback. Suppressing one-shots
	# also avoids headless AudioStreamPlayback objects surviving process teardown.
	AudioManager.sfx_cache = {}
	SaveManager.settings.shake = 0.15
	SaveManager.settings.flash = 0.10
	for character_index in 3:
		var character_result := valid_result.duplicate(true)
		character_result.character = character_index
		var screen := CampaignEnding.new()
		screen.setup(character_result, final_stage)
		add_child(screen)
		await get_tree().process_frame
		assert(screen.context_valid and screen.reduced_effects and is_zero_approx(screen.motion_strength), "Reduced-effects ending profile is invalid")
		assert(screen.results_button != null and screen.results_button.has_focus(), "Ending action did not receive gamepad focus")
		assert(screen.reveal_labels.size() == screen.reveal_delays.size() and not screen.reveal_labels.is_empty(), "Ending reveal sequence is incomplete")
		for label in screen.reveal_labels:
			assert(is_equal_approx(label.modulate.a, 1.0), "Reduced effects left animated copy partially hidden")
		var expected_epilogue := GameText.text(final_stage.ending_epilogue_keys[character_index])
		var has_epilogue := false
		for label in screen.reveal_labels:
			if label.text == expected_epilogue:
				has_epilogue = true
				break
		assert(has_epilogue, "Character-specific epilogue was not rendered")
		screen.queue_free()
		await get_tree().process_frame

	SaveManager.settings.language = "ko"
	var korean_screen := CampaignEnding.new()
	korean_screen.setup(valid_result, final_stage)
	add_child(korean_screen)
	await get_tree().process_frame
	assert(korean_screen.results_button.text == GameText.KO.ending_view_results, "Korean ending action did not localize")
	var emitted_results: Array[Dictionary] = []
	korean_screen.results_requested.connect(func(data: Dictionary): emitted_results.append(data))
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	korean_screen._unhandled_input(cancel_event)
	assert(emitted_results.size() == 1 and bool(emitted_results[0].ending_skipped), "Ending skip did not return the original result contract")
	korean_screen.queue_free()
	await get_tree().process_frame
	SaveManager.settings = settings_backup
	print("CAMPAIGN_ENDING_SMOKE_OK final_only=ok localization=ok characters=3 focus=ok reduced_effects=ok result_contract=ok")
	AudioManager.sfx_cache = sfx_cache_backup
	AudioManager.shutdown()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
