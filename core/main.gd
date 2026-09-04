extends Node

var current_view: Node
var pause_menu: PauseMenu
var smoke_mode := false
var transition_layer: CanvasLayer
var transition_rect: ColorRect
var controller_notice: Label
var controller_notice_tween: Tween
var run_mode := "campaign"
var practice_start_phase := 0
var active_difficulty := "normal"
var active_replay_id := ""
var active_stage_id := "neon_district_01"
var stage_select_practice := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_transition()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	GameManager.selected_character = SaveManager.selected_character
	active_difficulty = SaveManager.selected_difficulty
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke-stage"):
		smoke_mode = true
		call_deferred("_run_smoke_stage", StageManager.DEFAULT_STAGE_ID)
	elif args.has("--smoke-tempest"):
		smoke_mode = true
		call_deferred("_run_smoke_stage", "null_tempest_02")
	elif args.has("--smoke-ui"):
		smoke_mode = true
		call_deferred("_run_smoke_ui")
	elif args.has("--smoke-combat"):
		smoke_mode = true
		call_deferred("_run_smoke_combat")
	elif args.has("--benchmark-bullets"):
		smoke_mode = true
		call_deferred("_run_bullet_benchmark")
	elif args.has("--benchmark-render"):
		smoke_mode = true
		call_deferred("_run_render_benchmark")
	elif args.has("--capture-title"):
		call_deferred("_capture_title")
	elif args.has("--capture-select"):
		call_deferred("_capture_select")
	elif args.has("--capture-practice"):
		call_deferred("_capture_practice")
	elif args.has("--capture-stage"):
		call_deferred("_capture_stage")
	elif args.has("--capture-player-animation"):
		call_deferred("_capture_player_animation")
	elif args.has("--capture-enemy-animation"):
		call_deferred("_capture_enemy_animation")
	elif args.has("--capture-boss-animation"):
		call_deferred("_capture_boss_animation")
	elif args.has("--capture-boss"):
		call_deferred("_capture_boss")
	elif args.has("--capture-tempest-boss"):
		call_deferred("_capture_boss", "null_tempest_02", "res://tests/tempest_boss_capture.png")
	elif args.has("--capture-results"):
		call_deferred("_capture_results")
	elif args.has("--capture-localization"):
		call_deferred("_capture_localization")
	elif args.has("--capture-assists"):
		call_deferred("_capture_assists")
	elif args.has("--capture-controller-notice"):
		call_deferred("_capture_controller_notice")
	elif args.has("--capture-training"):
		call_deferred("_capture_training")
	elif args.has("--capture-records"):
		call_deferred("_capture_records")
	else:
		_show_title()
		if SaveManager.recovered_from_backup:
			call_deferred("_show_transient_notice", GameText.text("save_recovered"))

func _build_transition() -> void:
	transition_layer = CanvasLayer.new()
	transition_layer.layer = 1000
	transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(transition_layer)
	transition_rect = ColorRect.new()
	transition_rect.color = Color(0.004, 0.008, 0.028, 1.0)
	transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_layer.add_child(transition_rect)
	controller_notice = Label.new()
	controller_notice.position = Vector2(60, 118)
	controller_notice.size = Vector2(420, 44)
	controller_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controller_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controller_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controller_notice.add_theme_font_size_override("font_size", 14)
	controller_notice.add_theme_color_override("font_color", Color("d9fbff"))
	var notice_style := StyleBoxFlat.new()
	notice_style.bg_color = Color(0.015, 0.035, 0.10, 0.94)
	notice_style.border_color = Color("43e8ff")
	notice_style.set_border_width_all(2)
	notice_style.set_corner_radius_all(8)
	controller_notice.add_theme_stylebox_override("normal", notice_style)
	controller_notice.modulate.a = 0.0
	transition_layer.add_child(controller_notice)

func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	_show_transient_notice(GameText.text("controller_connected") if connected else GameText.text("controller_disconnected"))

func _show_transient_notice(message: String) -> void:
	if controller_notice_tween != null and controller_notice_tween.is_valid():
		controller_notice_tween.kill()
	controller_notice.text = message
	controller_notice.modulate.a = 1.0
	controller_notice_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	controller_notice_tween.tween_interval(2.0)
	controller_notice_tween.tween_property(controller_notice, "modulate:a", 0.0, 0.35)

func _run_smoke_stage(stage_id: String = StageManager.DEFAULT_STAGE_ID) -> void:
	_start_stage(0, false, 0, "normal", stage_id)
	await get_tree().process_frame
	if current_view is StageController:
		(current_view as StageController).player.debug_invincible = true
		(current_view as StageController).player.power = 4
	Input.action_press("primary")
	Engine.time_scale = 90.0
	# At extreme test speed, player shots can cross a boss between frames. Drain
	# one active phase per frame so this remains a timeline/transition acceptance
	# test without reintroducing time-based boss clears into production gameplay.
	for frame in 900:
		await get_tree().process_frame
		if not (current_view is StageController):
			return
		var stage := current_view as StageController
		if stage.boss != null and is_instance_valid(stage.boss) and not stage.boss.entering and not stage.boss.dying:
			stage.boss.damage(stage.boss.hp)
	assert(false, "Full stage smoke test did not reach the result transition")
	_schedule_test_shutdown()

func _run_smoke_ui() -> void:
	var settings_backup := SaveManager.settings.duplicate(true)
	var profile_difficulty_backup := SaveManager.selected_difficulty
	var profile_scores_backup := SaveManager.high_scores.duplicate(true)
	var stage_scores_backup := SaveManager.stage_high_scores.duplicate(true)
	var unlocked_stages_backup := SaveManager.unlocked_stage_ids.duplicate()
	var run_history_backup := SaveManager.run_history.duplicate(true)
	var tutorial_completed_backup := SaveManager.tutorial_completed
	var replay_backup := ReplayManager.last_replay.duplicate(true)
	var replay_entries_backup := ReplayManager._replay_entries.duplicate(true)
	_verify_save_recovery()
	_verify_replay_storage()
	SaveManager.selected_difficulty = "invalid"
	SaveManager.high_scores.story = -10
	SaveManager._sanitize_profile()
	assert(SaveManager.selected_difficulty == "normal", "Invalid saved difficulty was not migrated")
	assert(SaveManager.high_score_for("story") == 0, "Negative difficulty record was not sanitized")
	SaveManager.selected_difficulty = profile_difficulty_backup
	SaveManager.high_scores = profile_scores_backup
	SaveManager.high_score = int(profile_scores_backup.normal)
	SaveManager.settings.master = 4.0
	SaveManager.settings.bullet_contrast = -2.0
	SaveManager.settings.language = "invalid"
	SaveManager.settings.assist_preset = "invalid"
	SaveManager._sanitize_settings()
	assert(is_equal_approx(float(SaveManager.settings.master), 1.0), "Master volume setting was not clamped")
	assert(is_zero_approx(float(SaveManager.settings.bullet_contrast)), "Bullet contrast setting was not clamped")
	assert(SaveManager.settings.language == "en", "Invalid locale was not migrated")
	assert(SaveManager.settings.assist_preset == "custom", "Invalid assist preset was not migrated")
	SaveManager.settings = settings_backup
	var original_language := String(SaveManager.settings.language)
	_verify_localization_catalogs()
	_verify_stage_catalog()
	_verify_stage_hazards()
	_verify_stage_progression()
	SaveManager.settings.language = "ko"
	assert(GameText.text("start_game") == "게임 시작", "Korean text catalog did not activate")
	SaveManager.settings.language = original_language
	_show_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Title screen failed")
	(current_view as TitleScreen).credits_pressed.emit()
	await get_tree().process_frame
	assert(current_view is CreditsScreen, "Title did not open Credits & Data")
	var credits := current_view as CreditsScreen
	assert(credits.page_count() == 3 and credits.page_index == 0, "Credits & Data did not expose its three-page contract")
	credits._change_page(1)
	assert(credits.page_index == 1, "Credits & Data navigation failed")
	credits._close()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Credits & Data did not return to title")
	SaveManager.tutorial_completed = false
	(current_view as TitleScreen).start_pressed.emit()
	await get_tree().process_frame
	assert(current_view is TrainingScreen and GameManager.state == GameManager.GameState.TRAINING, "First campaign did not open interactive training")
	var training := current_view as TrainingScreen
	assert(training.skip_button.focus_mode == Control.FOCUS_NONE, "Training skip button can consume gamepad primary fire")
	training.transition_time = 0.0
	training.player.position += Vector2(180, 0)
	training._process(0.016)
	assert(training.step == 1, "Training movement calibration failed")
	training.transition_time = 0.0
	Input.action_press("primary")
	training._process(0.8)
	Input.action_release("primary")
	assert(training.step == 2, "Training primary-shot calibration failed")
	training.transition_time = 0.0
	Input.action_press("focus")
	training._process(0.8)
	Input.action_release("focus")
	assert(training.step == 3 and training.bullet_manager.count() == 36, "Training focus or barrier setup failed")
	training.transition_time = 0.0
	assert(training.player.activate_barrier(), "Training barrier could not activate")
	assert(training.step == 4 and training.bullet_manager.count() == 0 and training.deploy_button.visible, "Training barrier calibration failed")
	training._finish_training()
	await get_tree().process_frame
	assert(current_view is StageSelect and SaveManager.tutorial_completed, "Training completion did not continue to route selection")
	(current_view as StageSelect).stage_confirmed.emit(StageManager.DEFAULT_STAGE_ID)
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Route selection did not continue to vector selection")
	SaveManager.tutorial_completed = tutorial_completed_backup
	_show_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Title did not return after training validation")
	_on_joy_connection_changed(0, true)
	assert(controller_notice.text == GameText.text("controller_connected") and controller_notice.modulate.a > 0.0, "Controller hot-plug notice failed")
	var title := current_view as TitleScreen
	title._show_help()
	await get_tree().process_frame
	assert(title.help_panel != null and title.help_panel.visible, "How-to-play panel failed")
	assert(title.training_button != null and title.training_button.visible, "Combat briefing is missing the replayable training entry")
	title.training_button.pressed.emit()
	await get_tree().process_frame
	assert(current_view is TrainingScreen, "Combat briefing did not launch replayable training")
	training = current_view as TrainingScreen
	training._skip_training()
	await get_tree().process_frame
	assert(current_view is StageSelect, "Skipping replayed training did not continue to route selection")
	(current_view as StageSelect).stage_confirmed.emit(StageManager.DEFAULT_STAGE_ID)
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Replay training route selection did not continue to vector selection")
	SaveManager.tutorial_completed = tutorial_completed_backup
	_show_title()
	await get_tree().process_frame
	title = current_view as TitleScreen
	title._show_options()
	await get_tree().process_frame
	assert(title.options_panel != null and title.options_panel.visible, "Options panel failed")
	SaveManager.apply_assist_preset("standard")
	title._show_assists()
	await get_tree().process_frame
	assert(title.assist_panel != null and title.assist_panel.visible, "Accessibility assist panel failed")
	title._cycle_assist_preset()
	await get_tree().process_frame
	assert(bool(SaveManager.settings.show_hitbox) and bool(SaveManager.settings.auto_fire), "Comfort preset did not enable readability assists")
	assert(not bool(SaveManager.settings.auto_barrier), "Comfort preset must remain record eligible")
	assert(title.assist_panel != null and title.assist_panel.visible, "Assist panel did not rebuild after preset change")
	title._cycle_assist_preset()
	await get_tree().process_frame
	assert(bool(SaveManager.settings.auto_barrier), "Guardian preset did not enable automatic barrier interception")
	title._close_assists()
	SaveManager.settings = settings_backup.duplicate(true)
	SaveManager.apply_settings()
	await get_tree().process_frame
	assert(title.options_panel.visible, "Options panel did not return from accessibility assists")
	title._show_bindings()
	await get_tree().process_frame
	assert(title.bindings_panel != null and title.bindings_panel.visible, "Key bindings panel failed")
	var original_primary_key := SaveManager.keyboard_binding("primary")
	SaveManager._apply_keyboard_binding("primary", KEY_P)
	var primary_is_p := false
	for binding_event in InputMap.action_get_events("primary"):
		if binding_event is InputEventKey and (binding_event as InputEventKey).physical_keycode == KEY_P:
			primary_is_p = true
	assert(primary_is_p, "Keyboard binding did not apply")
	SaveManager._apply_keyboard_binding("primary", original_primary_key)
	title._toggle_binding_mode()
	await get_tree().process_frame
	assert(title.binding_mode == "gamepad" and title.bindings_panel != null, "Gamepad binding page failed")
	var original_primary_button := SaveManager.gamepad_binding("primary")
	var original_focus_button := SaveManager.gamepad_binding("focus")
	title._begin_rebind("primary", title.binding_buttons.primary)
	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = original_focus_button
	gamepad_event.pressed = true
	Input.parse_input_event(gamepad_event)
	await get_tree().process_frame
	assert(SaveManager.gamepad_binding("primary") == original_focus_button, "Gamepad button binding did not apply")
	assert(SaveManager.gamepad_binding("focus") == original_primary_button, "Gamepad binding collision did not swap buttons")
	SaveManager.set_gamepad_binding("primary", original_primary_button)
	title._close_bindings()
	await get_tree().process_frame
	assert(title.options_panel.visible, "Options panel did not return from key bindings")
	title._close_options()
	await get_tree().process_frame
	_show_practice_select()
	await get_tree().process_frame
	assert(current_view is StageSelect, "Boss practice did not open route selection")
	(current_view as StageSelect).stage_confirmed.emit(StageManager.DEFAULT_STAGE_ID)
	await get_tree().process_frame
	assert(current_view is CharacterSelect and (current_view as CharacterSelect).practice_mode, "Boss-practice character selection failed")
	var practice_select := current_view as CharacterSelect
	practice_select.selected_phase = 3
	practice_select.practice_confirmed.emit(1, 3)
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).practice_mode, "Boss-practice stage failed to start")
	var practice_stage := current_view as StageController
	assert(practice_stage.boss != null and practice_stage.boss.is_final and practice_stage.final_spawned, "Boss practice did not spawn the final boss")
	assert(practice_stage.practice_phase == 3 and practice_stage.boss.current_phase == 3, "Boss practice did not start at the selected phase")
	assert(practice_stage.difficulty_id == "normal" and practice_stage.player.lives == 3, "Boss practice must use normal difficulty rules")
	assert(practice_stage.boss.total_max_hp() < practice_stage.boss.phases[0].hp + practice_stage.boss.phases[1].hp + practice_stage.boss.phases[2].hp + practice_stage.boss.phases[3].hp + practice_stage.boss.phases[4].hp, "Practice boss health still includes skipped phases")
	assert(StageManager.section == "boss_practice", "Boss-practice stage section is invalid")
	_show_pause()
	await get_tree().process_frame
	_restart_stage()
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).practice_mode, "Boss-practice restart lost its run mode")
	assert((current_view as StageController).practice_phase == 3 and (current_view as StageController).boss.current_phase == 3, "Boss-practice restart lost the selected phase")
	_show_title()
	await get_tree().process_frame
	_show_character_select()
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Character selection failed")
	var campaign_select := current_view as CharacterSelect
	campaign_select.selected_difficulty = 2
	campaign_select.campaign_confirmed.emit(2, "expert")
	await get_tree().process_frame
	assert(current_view is OperationBriefing, "Campaign vector selection did not open the operation briefing")
	var operation_briefing := current_view as OperationBriefing
	assert(operation_briefing.stage_data.stage_id == active_stage_id and operation_briefing.selected_character == 2 and operation_briefing.difficulty_id == "expert", "Operation briefing lost the selected launch context")
	assert(operation_briefing.continue_button != null and operation_briefing.skip_button != null and operation_briefing.continue_button.has_focus(), "Operation briefing actions or default gamepad focus are invalid")
	operation_briefing.cancelled.emit()
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Cancelling the operation briefing did not return to vector selection")
	campaign_select = current_view as CharacterSelect
	campaign_select.campaign_confirmed.emit(2, "expert")
	await get_tree().process_frame
	operation_briefing = current_view as OperationBriefing
	operation_briefing.completed.emit(2, "expert", active_stage_id, true)
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).difficulty_id == "expert", "Expert stage failed to start")
	assert((current_view as StageController).player.lives == 2, "Expert mode starting lives are invalid")
	_show_pause()
	await get_tree().process_frame
	assert(get_tree().paused and pause_menu != null, "Pause menu failed")
	_resume()
	await get_tree().process_frame
	assert(not get_tree().paused, "Resume failed")
	var first_stage := current_view
	_show_pause()
	await get_tree().process_frame
	_restart_stage()
	await get_tree().process_frame
	assert(current_view is StageController and current_view != first_stage, "Pause restart failed")
	assert((current_view as StageController).difficulty_id == "expert" and (current_view as StageController).player.lives == 2, "Restart lost the selected difficulty")
	_show_pause()
	await get_tree().process_frame
	_quit_to_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Quit-to-title failed")
	_show_character_select()
	await get_tree().process_frame
	_start_campaign(2, "story")
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).difficulty_id == "story", "Story stage did not start after title return")
	assert((current_view as StageController).player.lives == 5, "Story mode starting lives are invalid")
	var synthetic := ScoreManager.result(12.5, false)
	synthetic["mode"] = "campaign"
	synthetic["difficulty"] = "story"
	synthetic["total_score"] = SaveManager.high_score_for("story") + 1
	smoke_mode = false
	_on_run_finished(synthetic)
	await get_tree().process_frame
	assert(current_view is ResultsScreen, "Result screen failed")
	assert((current_view as ResultsScreen).next_operation_button == null, "A failed route exposed the next-operation action")
	assert(bool(GameManager.last_result.get("new_high_score", false)), "A genuinely new record was not marked on the result screen")
	var result_replay_id := String(GameManager.last_result.get("replay_id", ""))
	assert(result_replay_id.length() == 64 and (current_view as ResultsScreen).replay_button != null, "Result screen did not retain the exact completed-run replay")
	assert(String(SaveManager.run_history.back().get("replay_id", "")) == result_replay_id, "Run history did not link the completed run to its replay")
	var tied_result := synthetic.duplicate(true)
	_on_run_finished(tied_result)
	await get_tree().process_frame
	assert(not bool(GameManager.last_result.get("new_high_score", true)), "A tied score was incorrectly marked as a new record")
	var campaign_stage_ids := StageManager.stage_ids()
	var cleared_route_result := synthetic.duplicate(true)
	cleared_route_result["cleared"] = true
	cleared_route_result["stage_id"] = String(campaign_stage_ids[0])
	cleared_route_result["replay_available"] = false
	cleared_route_result["replay_id"] = ""
	cleared_route_result["medals"] = ["no_miss", "no_barrier"]
	cleared_route_result["medal_bonus"] = 150000
	cleared_route_result["total_score"] = int(cleared_route_result.total_score) + 150000
	_on_run_finished(cleared_route_result)
	await get_tree().process_frame
	var cleared_route_screen := current_view as ResultsScreen
	assert(cleared_route_screen != null and cleared_route_screen.next_operation_button != null, "A cleared route did not expose the next operation")
	assert(cleared_route_screen.next_stage_id == String(campaign_stage_ids[1]), "The next-operation action targeted the wrong catalog route")
	assert(cleared_route_screen.medal_ids == ["no_miss", "no_barrier"] and cleared_route_screen.medal_bonus == 150000, "Result screen did not present the earned operation medals")
	assert(cleared_route_screen._medal_title_line().contains(GameText.text("medal_no_miss")), "Result screen medal title was not localized")
	cleared_route_screen.next_operation_button.pressed.emit()
	await get_tree().process_frame
	assert(current_view is CharacterSelect and active_stage_id == String(campaign_stage_ids[1]), "Next operation did not open vector selection for the unlocked route")
	assert((current_view as CharacterSelect).stage_data.stage_id == active_stage_id, "Next-operation vector selection received the wrong StageData")
	var final_route_result := cleared_route_result.duplicate(true)
	final_route_result["stage_id"] = String(campaign_stage_ids[-1])
	_on_run_finished(final_route_result)
	await get_tree().process_frame
	assert(current_view is CampaignEnding and (current_view as CampaignEnding).context_valid, "Final campaign clear did not open the authored ending")
	var ending_screen := current_view as CampaignEnding
	ending_screen._request_results(false)
	await get_tree().process_frame
	assert(current_view is ResultsScreen and (current_view as ResultsScreen).next_operation_button == null, "The final catalog route exposed a nonexistent next operation")
	var practice_route_result := cleared_route_result.duplicate(true)
	practice_route_result["mode"] = "practice"
	_on_run_finished(practice_route_result)
	await get_tree().process_frame
	assert((current_view as ResultsScreen).next_operation_button == null, "Practice results exposed campaign continuation")
	var replay_route_result := cleared_route_result.duplicate(true)
	replay_route_result["mode"] = "replay"
	_on_run_finished(replay_route_result)
	await get_tree().process_frame
	assert((current_view as ResultsScreen).next_operation_button == null, "Replay results exposed campaign continuation")
	_start_stage(2, false, 0, "story")
	await get_tree().process_frame
	assert(current_view is StageController, "Retry failed")
	var retry_stage := current_view as StageController
	retry_stage.player.locked = false
	retry_stage.player.invulnerable = 0.0
	retry_stage.player.lives = 1
	retry_stage.player.barriers = 0
	retry_stage._damage_player()
	assert(retry_stage.player.barriers == PlayerController.BARRIERS_PER_LIFE, "Bombs did not recharge after losing a life")
	retry_stage.finish_timer = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	assert(current_view is ResultsScreen, "Game-over result transition failed")
	var high_score_before := SaveManager.high_score
	GameManager.finish_run({"mode": "practice", "total_score": high_score_before + 999999}, false)
	assert(SaveManager.high_score == high_score_before, "Practice score must not modify the campaign high score")
	var high_scores_backup := SaveManager.high_scores.duplicate(true)
	var story_record := SaveManager.high_score_for("story")
	var normal_record := SaveManager.high_score_for("normal")
	SaveManager.submit_score(story_record + 12345, "story")
	assert(SaveManager.high_score_for("story") == story_record + 12345, "Story score was not saved to its own record")
	assert(SaveManager.high_score_for("normal") == normal_record, "Story score polluted the normal record")
	SaveManager.high_scores = high_scores_backup
	SaveManager.high_score = int(high_scores_backup.normal)
	var assisted_result := synthetic.duplicate(true)
	assisted_result["difficulty"] = "normal"
	assisted_result["assisted"] = true
	assisted_result["total_score"] = normal_record + 999999
	run_mode = "campaign"
	active_difficulty = "normal"
	_on_run_finished(assisted_result)
	await get_tree().process_frame
	assert(SaveManager.high_score_for("normal") == normal_record, "Assisted campaign submitted a competitive record")
	SaveManager.run_history.clear()
	_seed_archive_samples()
	var normal_summary := SaveManager.run_summary("normal")
	assert(int(normal_summary.runs) == 3 and int(normal_summary.clears) == 2, "Archive difficulty aggregation failed")
	assert(is_equal_approx(float(normal_summary.average_deaths), 1.0), "Archive loss average failed")
	assert(int(SaveManager.run_summary("normal", 0).runs) == 1, "Archive character filter failed")
	var ranked_summary := SaveManager.summarize_runs([
		SaveManager._sanitize_run_entry({"difficulty": "normal", "total_score": 100, "assisted": false}),
		SaveManager._sanitize_run_entry({"difficulty": "normal", "total_score": 999999, "assisted": true})
	], "normal")
	assert(int(ranked_summary.best_score) == 100, "Assisted score polluted the competitive archive best")
	var stage_filtered := SaveManager.summarize_runs([
		SaveManager._sanitize_run_entry({"difficulty": "normal", "stage_id": StageManager.DEFAULT_STAGE_ID}),
		SaveManager._sanitize_run_entry({"difficulty": "normal", "stage_id": "future_stage"})
	], "normal", -1, StageManager.DEFAULT_STAGE_ID)
	assert(int(stage_filtered.runs) == 1, "Archive stage filter mixed records from different stages")
	var sanitized := SaveManager._sanitize_run_entry({"difficulty": "void", "character": 99, "deaths": -4, "barriers_used": 9999})
	assert(sanitized.difficulty == "normal" and int(sanitized.character) == 2, "Malformed archive entry profile was not sanitized")
	assert(int(sanitized.deaths) == 0 and int(sanitized.barriers_used) == 999, "Malformed archive metrics were not clamped")
	assert(String(sanitized.stage_id) == StageManager.DEFAULT_STAGE_ID and String(SaveManager._sanitize_run_entry({"stage_id": "../invalid"}).stage_id) == StageManager.DEFAULT_STAGE_ID, "Malformed archive stage ID was not migrated safely")
	var export_data: Variant = JSON.parse_string(SaveManager.playtest_export_json())
	assert(export_data is Dictionary and int(export_data.run_count) == 9, "Playtest JSON export is invalid")
	assert((export_data.summaries as Dictionary).has("normal"), "Playtest export is missing difficulty summaries")
	_show_records()
	await get_tree().process_frame
	assert(current_view is RecordsScreen, "Combat archive screen failed")
	var archive := current_view as RecordsScreen
	var archive_difficulty_before := archive.difficulty_index
	archive._cycle_difficulty(1)
	assert(archive.difficulty_index == wrapi(archive_difficulty_before + 1, 0, GameManager.DIFFICULTY_ORDER.size()), "Combat archive difficulty navigation failed")
	var replay_frames: Array[int] = []
	for frame in 480:
		replay_frames.append_array([16667, 8000 if frame < 90 else -6000, 0, ReplayManager.MASK_PRIMARY])
	var replay_fixture := ReplayManager.build_replay(1, "normal", false, 24681357, replay_frames, {
		"cleared": false, "total_score": 0, "deaths": 0, "barriers_used": 0,
		"clear_time": 0.0, "boss_phase_metrics": []
	})
	assert(not replay_fixture.is_empty(), "Replay fixture could not be built")
	var replay_fixture_second := ReplayManager.build_replay(2, "normal", false, 97531, replay_frames, {
		"cleared": true, "total_score": 765432, "deaths": 1, "barriers_used": 2,
		"clear_time": 214.5, "boss_phase_metrics": [{}, {}, {}, {}, {}, {}, {}, {}]
	})
	var replay_fixture_expert := ReplayManager.build_replay(0, "expert", true, 86420, replay_frames, {
		"cleared": false, "total_score": 345678, "deaths": 2, "barriers_used": 3,
		"clear_time": 98.0, "boss_phase_metrics": [{}, {}, {}]
	})
	ReplayManager.clear_memory_library()
	assert(ReplayManager.save_replay(replay_fixture), "First replay could not enter the in-memory vault")
	assert(ReplayManager.save_replay(replay_fixture_second), "Second replay could not enter the in vault")
	assert(ReplayManager.save_replay(replay_fixture_expert), "Difficulty-filter replay could not enter the vault")
	assert(ReplayManager.list_replays("normal").size() == 2 and ReplayManager.list_replays().size() == 3, "Replay vault difficulty filter failed")
	SaveManager.selected_difficulty = "normal"
	_show_records()
	await get_tree().process_frame
	archive = current_view as RecordsScreen
	assert(archive.replay_entries.size() == 2 and not archive.replay_button.disabled, "Combat archive did not expose the filtered replay vault")
	var selected_replay_index := -1
	for replay_index in archive.replay_entries.size():
		var replay_entry: Dictionary = archive.replay_entries[replay_index]
		if int((replay_entry.replay as Dictionary).get("seed", 0)) == 24681357:
			selected_replay_index = replay_index
			break
	assert(selected_replay_index >= 0, "Selectable replay was missing from the vault")
	archive.replay_index = selected_replay_index
	archive._refresh_replay_controls()
	var selected_replay_id := String(archive.replay_entries[selected_replay_index].id)
	var linked_run := SaveManager._sanitize_run_entry({"difficulty": "normal", "replay_id": selected_replay_id})
	assert(String(linked_run.replay_id) == selected_replay_id, "Run history did not preserve its replay-vault link")
	assert(String(SaveManager._sanitize_run_entry({"replay_id": "../invalid"}).replay_id).is_empty(), "Run history accepted an invalid replay ID")
	assert(ReplayManager.set_pinned(selected_replay_id, true), "Replay pinning failed")
	archive._refresh_replay_entries(selected_replay_id)
	assert(bool(archive.replay_entries[archive.replay_index].pinned), "Pinned replay state did not refresh in the archive")
	var profile_character_before_replay := SaveManager.selected_character
	archive._watch_replay()
	assert(current_view is StageController and (current_view as StageController).replay_mode and active_replay_id == selected_replay_id, "Selected replay did not launch from the combat archive")
	var replay_stage := current_view as StageController
	replay_stage.set_process(false)
	for frame in 360:
		replay_stage._process(0.0)
	assert(replay_stage.run_seed == 24681357 and replay_stage.difficulty_id == "normal", "Replay lost its seed or difficulty")
	assert(replay_stage.stage_data.stage_id == StageManager.DEFAULT_STAGE_ID and active_stage_id == StageManager.DEFAULT_STAGE_ID, "Replay lost its bound stage")
	assert(replay_stage.hud.run_mode == "replay" and replay_stage.replay_cursor >= ReplayManager.FRAME_STRIDE, "Replay controls or HUD context did not activate")
	assert(SaveManager.selected_character == profile_character_before_replay, "Watching a replay changed the saved character selection")
	var first_replay_state := {
		"player": replay_stage.player.position,
		"play_time": replay_stage.play_time,
		"wave": replay_stage.wave_index,
		"enemies": replay_stage.enemy_manager.enemies.size(),
		"bullets": replay_stage.bullet_manager.count(),
		"score": ScoreManager.score,
		"cursor": replay_stage.replay_cursor
	}
	_start_replay_by_id(active_replay_id)
	var repeated_stage := current_view as StageController
	repeated_stage.set_process(false)
	for frame in 360:
		repeated_stage._process(0.0)
	assert(repeated_stage.player.position.distance_to(first_replay_state.player) < 0.001, "Replay player movement was not deterministic")
	assert(is_equal_approx(repeated_stage.play_time, float(first_replay_state.play_time)), "Replay route timing was not deterministic")
	assert(repeated_stage.wave_index == int(first_replay_state.wave) and repeated_stage.enemy_manager.enemies.size() == int(first_replay_state.enemies), "Replay encounter state was not deterministic")
	assert(repeated_stage.bullet_manager.count() == int(first_replay_state.bullets) and ScoreManager.score == int(first_replay_state.score), "Replay combat state was not deterministic")
	assert(repeated_stage.replay_cursor == int(first_replay_state.cursor), "Replay input cursor diverged")
	var replay_record_before := SaveManager.high_score_for("normal")
	var replay_history_before := SaveManager.run_history.size()
	GameManager.finish_run({"mode": "replay", "difficulty": "normal", "total_score": replay_record_before + 999999}, false)
	assert(SaveManager.high_score_for("normal") == replay_record_before and SaveManager.run_history.size() == replay_history_before, "Replay playback modified campaign records")
	_show_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Replay validation did not return to title")
	ReplayManager._replay_entries.assign(replay_entries_backup)
	ReplayManager.last_replay = replay_backup
	SaveManager.run_history.assign(run_history_backup)
	SaveManager.high_scores = profile_scores_backup
	SaveManager.high_score = int(profile_scores_backup.normal)
	SaveManager.stage_high_scores = stage_scores_backup
	SaveManager.unlocked_stage_ids = unlocked_stages_backup
	print("UI_FLOW_SMOKE_OK title=ok credits_data=ok training=ok help=ok options=ok assists=ok bindings=ok gamepad=ok hotplug=ok routes=ok progression=ok briefing=ok hazards=ok practice=ok select=ok stage=ok pause=ok restart=ok quit_title=ok results=ok medals=ok retry=ok game_over=ok archive=ok telemetry=ok localization=ok save_recovery=ok replay_vault=ok")
	_schedule_test_shutdown()

func _verify_save_recovery() -> void:
	var validation_dir := _validation_directory()
	var primary_path := validation_dir + "/save_recovery_primary.testcfg"
	var backup_path := validation_dir + "/save_recovery_backup.testcfg"
	var staging_path := validation_dir + "/save_recovery_pending.testcfg"
	for path in [primary_path, backup_path, staging_path]:
		SaveManager._remove_file(path)
	var version_seven := SaveManager._create_save_config()
	version_seven.set_value("meta", "version", 7)
	SaveManager._seal_config(version_seven)
	assert(SaveManager._config_is_valid(version_seven), "Version 7 signed save compatibility failed")
	var version_eight := SaveManager._create_save_config()
	version_eight.set_value("meta", "version", 8)
	SaveManager._seal_config(version_eight)
	assert(SaveManager._config_is_valid(version_eight), "Version 8 save migration compatibility failed")
	var version_nine := SaveManager._create_save_config()
	version_nine.set_value("meta", "version", 9)
	SaveManager._seal_config(version_nine)
	assert(SaveManager._config_is_valid(version_nine), "Version 9 save migration compatibility failed")
	var version_ten := SaveManager._create_save_config()
	version_ten.set_value("meta", "version", 10)
	SaveManager._seal_config(version_ten)
	assert(SaveManager._config_is_valid(version_ten), "Version 10 save migration compatibility failed")
	var unrelated_config := ConfigFile.new()
	unrelated_config.set_value("unknown", "payload", 1)
	assert(not SaveManager._config_is_valid(unrelated_config), "Unrecognized unsigned data was accepted as a legacy save")

	var first := SaveManager._create_save_config()
	first.set_value("record", "high_score_story", 111111)
	SaveManager._seal_config(first)
	assert(SaveManager._save_config_transaction(first, primary_path, backup_path, staging_path) == OK, "Initial transactional save failed")
	assert(SaveManager._path_has_valid_config(primary_path) and SaveManager._path_has_valid_config(backup_path), "Initial save did not create two valid copies")

	var second := SaveManager._create_save_config()
	second.set_value("record", "high_score_story", 222222)
	SaveManager._seal_config(second)
	assert(SaveManager._save_config_transaction(second, primary_path, backup_path, staging_path) == OK, "Replacement transactional save failed")
	var current_selection := SaveManager._load_best_config(primary_path, backup_path)
	assert(not bool(current_selection.recovered), "A valid primary save incorrectly used its backup")
	assert(int((current_selection.config as ConfigFile).get_value("record", "high_score_story", 0)) == 222222, "Transactional save did not promote staged data")

	var tampered := ConfigFile.new()
	assert(tampered.load(primary_path) == OK, "Could not load save corruption fixture")
	tampered.set_value("record", "high_score_story", 999999)
	assert(tampered.save(primary_path) == OK, "Could not write save corruption fixture")
	assert(not SaveManager._config_is_valid(tampered), "Integrity check accepted modified save data")
	var recovered := SaveManager._load_best_config(primary_path, backup_path)
	assert(bool(recovered.recovered), "Corrupt primary save did not fall back to backup")
	assert(int((recovered.config as ConfigFile).get_value("record", "high_score_story", 0)) == 111111, "Recovery did not restore the last valid generation")

	var abandoned_pending := SaveManager._create_save_config()
	abandoned_pending.set_value("record", "high_score_story", 777777)
	SaveManager._seal_config(abandoned_pending)
	assert(abandoned_pending.save(staging_path) == OK, "Could not write interrupted-save fixture")
	var interrupted_recovery := SaveManager._load_best_config(primary_path, backup_path)
	assert(int((interrupted_recovery.config as ConfigFile).get_value("record", "high_score_story", 0)) == 111111, "Abandoned staging data was incorrectly promoted")
	for path in [primary_path, backup_path, staging_path]:
		assert(SaveManager._remove_file(path) == OK, "Could not remove save recovery fixture")

func _verify_localization_catalogs() -> void:
	assert(GameText.EN.size() == GameText.KO.size(), "Localization catalogs have different key counts")
	var format_pattern := RegEx.new()
	assert(format_pattern.compile("%[-+0-9.]*[sdf%]") == OK, "Localization format-token validator failed to compile")
	for text_key in GameText.EN:
		assert(GameText.KO.has(text_key), "Korean catalog is missing key: %s" % text_key)
		var english_tokens: Array[String] = []
		var korean_tokens: Array[String] = []
		for token_match in format_pattern.search_all(String(GameText.EN[text_key])):
			english_tokens.append(token_match.get_string())
		for token_match in format_pattern.search_all(String(GameText.KO[text_key])):
			korean_tokens.append(token_match.get_string())
		assert(english_tokens == korean_tokens, "Localization format tokens differ: %s" % text_key)
	for text_key in GameText.KO:
		assert(GameText.EN.has(text_key), "English catalog is missing key: %s" % text_key)

func _verify_stage_catalog() -> void:
	var stage_ids := StageManager.stage_ids()
	assert(not stage_ids.is_empty() and stage_ids.has(StageManager.DEFAULT_STAGE_ID), "Stage catalog has no valid default stage")
	var unique_ids := {}
	for stage_id in stage_ids:
		assert(not unique_ids.has(stage_id), "Stage catalog contains a duplicate ID: %s" % stage_id)
		unique_ids[stage_id] = true
		var data := StageManager.stage(stage_id)
		assert(data != null and data.validation_errors().is_empty(), "StageData validation failed: %s" % stage_id)
		assert(data.timeline != null and data.timeline.stage_id == data.stage_id, "Stage timeline identity is invalid: %s" % stage_id)
		assert(data.timeline.wave_start_time >= data.timeline.intro_lock_time, "Stage waves begin before the intro lock ends: %s" % stage_id)
		assert(data.timeline.midboss_spawn_time > data.timeline.wave_start_time, "Stage midboss timing is invalid: %s" % stage_id)
		assert(data.timeline.boss_spawn_time > data.timeline.boss_warning_time, "Stage final-boss warning timing is invalid: %s" % stage_id)
		assert(data.timeline.boss_spawn_time > data.timeline.danger_escalation_time, "Stage danger ramp has a zero or negative range: %s" % stage_id)
		assert(AudioManager.THEMES.has(data.stage_music_id) and AudioManager.THEMES.has(data.boss_music_id), "Stage music theme is missing: %s" % stage_id)
		assert(GameDatabase.has_enemy(data.grade_1_enemy_id) and GameDatabase.has_enemy(data.grade_2_enemy_id) and GameDatabase.has_enemy(data.grade_3_enemy_id), "Stage enemy roster contains an unknown ID: %s" % stage_id)
		assert(BossController.supports_boss_id(data.midboss_id) and BossController.supports_boss_id(data.final_boss_id), "Stage boss roster contains an unknown ID: %s" % stage_id)
		var midboss_definition := BossController.definition_for_id(data.midboss_id)
		var final_boss_definition := BossController.definition_for_id(data.final_boss_id)
		assert(midboss_definition.validation_errors().is_empty() and final_boss_definition.validation_errors().is_empty(), "Stage boss definition is invalid: %s" % stage_id)
		assert(not midboss_definition.is_final and final_boss_definition.is_final, "Stage boss roles are invalid: %s" % stage_id)
		assert(midboss_definition.phases.size() + final_boss_definition.phases.size() == data.expected_boss_phase_count, "Stage boss phase count does not match its manifest: %s" % stage_id)
		var localization_keys := PackedStringArray([
			data.title_key, data.subtitle_key, data.result_key, data.pause_key,
			data.midboss_name_key, data.midboss_subtitle_key, data.midboss_defeat_title_key, data.midboss_defeat_subtitle_key,
			data.final_boss_name_key, data.final_boss_subtitle_key, data.final_boss_defeat_title_key, data.final_boss_defeat_subtitle_key
		])
		localization_keys.append_array(data.practice_phase_name_keys)
		for boss_definition in [midboss_definition, final_boss_definition]:
			localization_keys.append(boss_definition.display_name_key)
			for phase in boss_definition.phases:
				localization_keys.append(phase.name_key)
		for text_key in localization_keys:
			assert(GameText.EN.has(text_key) and GameText.KO.has(text_key), "Stage localization key is missing: %s" % text_key)
		var background_probe := data.background_scene.instantiate()
		assert(background_probe is Node2D and background_probe.has_method("configure") and background_probe.has_method("set_route_context") and background_probe.has_method("set_escalation"), "Stage background contract is incomplete: %s" % stage_id)
		background_probe.call("configure", data)
		assert(is_equal_approx(float(background_probe.get("route_duration")), data.timeline.boss_spawn_time), "Stage background did not bind its route duration: %s" % stage_id)
		background_probe.free()
	assert(StageManager.default_stage() == StageManager.stage(StageManager.DEFAULT_STAGE_ID), "Default stage lookup is inconsistent")

func _verify_stage_hazards() -> void:
	var invalid := StageHazardData.new()
	assert(not invalid.is_valid(180.0), "Hazard validation accepted an empty definition")
	var lane := StageHazardData.new()
	lane.hazard_id = "test_lane"
	lane.kind = "lightning_lane"
	lane.start_time = 1.0
	lane.end_time = 1.5
	lane.interval = 10.0
	lane.warning_time = 1.0
	lane.active_time = 1.0
	lane.orientation = "vertical"
	lane.lane_count = 1
	lane.width = 44.0
	var debris := StageHazardData.new()
	debris.hazard_id = "test_debris"
	debris.kind = "debris_field"
	debris.start_time = 2.0
	debris.end_time = 2.5
	debris.interval = 10.0
	debris.warning_time = 0.8
	debris.active_time = 1.0
	debris.burst_count = 3
	debris.width = 42.0
	debris.speed = 260.0
	var hazard_events: Array[StageHazardData] = [lane, debris]
	var first := StageHazardManager.new()
	var second := StageHazardManager.new()
	first.configure(hazard_events, 7654321)
	second.configure(hazard_events, 7654321)
	assert(not first.update_hazards(0.0, 1.0, Vector2.ZERO, true), "A telegraphed lane dealt damage before activation")
	second.update_hazards(0.0, 1.0, Vector2.ZERO, true)
	assert(first.active_lanes.size() == 1 and first.active_lanes == second.active_lanes, "Lane hazards are not deterministic")
	var lane_rect: Rect2 = first.active_lanes[0].rect
	assert(not first.update_hazards(0.4, 1.0, lane_rect.get_center(), true), "A lane warning dealt collision damage")
	assert(first.update_hazards(0.7, 1.0, lane_rect.get_center(), true), "An active lane failed to collide with the player")
	first.update_hazards(0.0, 2.0, Vector2.ZERO, false)
	second.update_hazards(0.0, 2.0, Vector2.ZERO, false)
	assert(first.active_debris.size() == 3 and first.active_debris == second.active_debris, "Debris hazards are not deterministic")
	first.clear_all()
	assert(first.active_count() == 0, "Stage hazards did not clear before a boss transition")
	first.free()
	second.free()

func _verify_stage_progression() -> void:
	var stage_ids := StageManager.stage_ids()
	assert(stage_ids.size() >= 2, "Campaign progression requires at least two stages")
	var first_stage := String(stage_ids[0])
	var second_stage := String(stage_ids[1])
	SaveManager.high_scores = {"story": 0, "normal": 0, "expert": 0}
	SaveManager.high_score = 0
	SaveManager.stage_high_scores = {}
	SaveManager.stage_high_scores[first_stage] = {"story": 0, "normal": 0, "expert": 0}
	SaveManager.stage_high_scores[second_stage] = {"story": 0, "normal": 0, "expert": 0}
	SaveManager.unlocked_stage_ids = PackedStringArray([first_stage])
	SaveManager._sanitize_progression()
	assert(SaveManager.is_stage_unlocked(first_stage) and not SaveManager.is_stage_unlocked(second_stage), "Initial route lock state is invalid")
	assert(SaveManager.register_stage_clear(first_stage) and SaveManager.is_stage_unlocked(second_stage), "Clearing a stage did not unlock the next route")
	SaveManager.submit_score(1111, "normal", first_stage)
	SaveManager.submit_score(2222, "normal", second_stage)
	assert(SaveManager.high_score_for("normal", first_stage) == 1111, "First-stage record was not isolated")
	assert(SaveManager.high_score_for("normal", second_stage) == 2222, "Second-stage record was not isolated")

func _verify_replay_storage() -> void:
	var validation_dir := _validation_directory()
	var primary_path := validation_dir + "/replay_primary.testjson"
	var backup_path := validation_dir + "/replay_backup.testjson"
	var staging_path := validation_dir + "/replay_pending.testjson"
	for path in [primary_path, backup_path, staging_path]:
		ReplayManager._remove_file(path)
	var frames: Array[int] = [16667, 0, 0, ReplayManager.MASK_PRIMARY, 16667, 12000, -5000, ReplayManager.MASK_FOCUS | ReplayManager.MASK_BARRIER]
	var first_result := {
		"cleared": true, "total_score": 123456, "deaths": 1, "barriers_used": 2,
		"clear_time": 12.345, "boss_phase_metrics": [{}, {}]
	}
	var first := ReplayManager.build_replay(0, "normal", false, 13579, frames, first_result, StageManager.DEFAULT_STAGE_ID)
	assert(not first.is_empty() and not String(first.get("checksum", "")).is_empty(), "Replay build or checksum failed")
	assert(int(first.format_version) == ReplayManager.FORMAT_VERSION and String(first.stage_id) == StageManager.DEFAULT_STAGE_ID, "Replay did not bind its stage identity")
	assert(ReplayManager.matches_expected(first_result, first), "Replay result verification rejected a matching run")
	var wrong_stage_result := first_result.duplicate(true)
	wrong_stage_result["stage_id"] = "retired_stage"
	assert(not ReplayManager.matches_expected(wrong_stage_result, first), "Replay verification accepted results from a different stage")
	var legacy_v1 := first.duplicate(true)
	legacy_v1["format_version"] = 1
	legacy_v1.erase("stage_id")
	legacy_v1["checksum"] = ReplayManager._checksum(legacy_v1)
	var migrated_v1 := ReplayManager._verify_replay(legacy_v1)
	assert(not migrated_v1.is_empty() and int(migrated_v1.format_version) == 1 and String(migrated_v1.stage_id) == StageManager.DEFAULT_STAGE_ID, "Legacy v1 replay did not migrate to the default stage")
	var legacy_entry := ReplayManager._make_entry(legacy_v1, 1, false)
	assert(not legacy_entry.is_empty() and bool(legacy_entry.compatible), "Legacy v1 replay was not exposed as a compatible vault entry")
	var changed_result := first_result.duplicate(true)
	changed_result.total_score = 123457
	assert(not ReplayManager.matches_expected(changed_result, first), "Replay result verification accepted a desynchronized run")
	assert(ReplayManager.write_replay_transaction(first, primary_path, backup_path, staging_path) == OK, "Initial transactional replay save failed")
	assert(int(ReplayManager.load_best_replay(primary_path, backup_path).seed) == 13579, "Initial replay was not readable")
	var second := ReplayManager.build_replay(2, "expert", true, 97531, frames, changed_result)
	assert(ReplayManager.write_replay_transaction(second, primary_path, backup_path, staging_path) == OK, "Replacement transactional replay save failed")
	assert(int(ReplayManager.load_best_replay(primary_path, backup_path).seed) == 97531, "Replacement replay was not promoted")
	var replay_file := FileAccess.open(primary_path, FileAccess.READ)
	assert(replay_file != null, "Could not load replay corruption fixture")
	var tampered: Variant = JSON.parse_string(replay_file.get_as_text())
	replay_file.close()
	assert(tampered is Dictionary, "Replay corruption fixture is not JSON data")
	(tampered as Dictionary).seed = 86420
	assert(ReplayManager._write_replay(primary_path, tampered) == OK, "Could not write replay corruption fixture")
	var recovered := ReplayManager.load_best_replay(primary_path, backup_path)
	assert(int(recovered.get("seed", 0)) == 13579, "Corrupt replay did not fall back to its last valid backup")
	assert(ReplayManager._write_replay(staging_path, second) == OK, "Could not write interrupted replay fixture")
	assert(int(ReplayManager.load_best_replay(primary_path, backup_path).seed) == 13579, "Abandoned replay staging data was incorrectly promoted")
	var invalid_frames := frames.duplicate()
	invalid_frames[3] = 99
	assert(ReplayManager.build_replay(0, "normal", false, 13579, invalid_frames, first_result).is_empty(), "Replay validation accepted an invalid input mask")
	for path in [primary_path, backup_path, staging_path]:
		assert(ReplayManager._remove_file(path) == OK, "Could not remove replay recovery fixture")
	_verify_replay_vault(validation_dir, frames)

func _verify_replay_vault(validation_dir: String, frames: Array[int]) -> void:
	var vault_path := validation_dir.path_join("replay_vault")
	_clear_validation_directory(vault_path)
	var saved_directory := ReplayManager._active_replay_directory
	var saved_persistence := ReplayManager.persistence_enabled
	var saved_entries := ReplayManager._replay_entries.duplicate(true)
	var saved_last := ReplayManager.last_replay.duplicate(true)
	ReplayManager._active_replay_directory = vault_path
	ReplayManager.persistence_enabled = true
	ReplayManager.clear_memory_library()
	assert(ReplayManager._ensure_replay_directory(vault_path) == OK, "Could not create isolated replay vault")

	var fixtures: Array[Dictionary] = []
	for index in 14:
		var result := {
			"cleared": index % 3 != 1,
			"total_score": 100000 + index * 7777,
			"deaths": index % 3,
			"barriers_used": index % 5,
			"clear_time": 180.0 + index,
			"boss_phase_metrics": []
		}
		for phase_index in (8 if bool(result.cleared) else 3):
			result.boss_phase_metrics.append({"phase": phase_index})
		var replay := ReplayManager.build_replay(index % 3, "normal" if index % 2 == 0 else "expert", false, 20000 + index, frames, result)
		assert(not replay.is_empty(), "Replay vault fixture could not be built")
		fixtures.append(replay)

	for index in 3:
		var entry := ReplayManager._make_entry(fixtures[index], 1001 + index, false)
		assert(ReplayManager._write_entry_transaction(entry, vault_path) == OK, "Replay vault transaction failed")
	ReplayManager._load_replay_library(vault_path)
	ReplayManager._refresh_last_replay()
	var ordered := ReplayManager.list_replays()
	assert(ordered.size() == 3, "Replay vault did not load three independent files")
	assert(int((ordered[0].replay as Dictionary).seed) == 20002 and int((ordered[2].replay as Dictionary).seed) == 20000, "Replay vault newest-first ordering failed")
	var pinned_id := String(ordered[2].id)
	assert(ReplayManager.set_pinned(pinned_id, true), "Replay vault could not pin its oldest entry")
	var count_before_duplicate := ReplayManager.replay_count()
	assert(ReplayManager.save_replay(fixtures[0]) and ReplayManager.replay_count() == count_before_duplicate, "Replay checksum deduplication failed")

	for index in range(3, fixtures.size()):
		var entry := ReplayManager._make_entry(fixtures[index], 1001 + index, false)
		assert(ReplayManager._write_entry_transaction(entry, vault_path) == OK, "Replay vault expansion transaction failed")
	ReplayManager._load_replay_library(vault_path)
	ReplayManager._enforce_library_limits(true)
	ReplayManager._refresh_last_replay()
	assert(ReplayManager.replay_count() == ReplayManager.MAX_REPLAYS, "Replay vault capacity limit failed")
	assert(not ReplayManager.replay_by_id(pinned_id).is_empty(), "Pinned replay was evicted at capacity")

	var pin_candidates: Array[String] = []
	for entry in ReplayManager.list_replays():
		if not bool(entry.pinned):
			pin_candidates.append(String(entry.id))
	assert(pin_candidates.size() >= 3, "Replay vault lacks pin-limit fixtures")
	assert(ReplayManager.set_pinned(pin_candidates[0], true) and ReplayManager.set_pinned(pin_candidates[1], true), "Replay vault failed before reaching its pin limit")
	assert(not ReplayManager.set_pinned(pin_candidates[2], true), "Replay vault exceeded the three-pin limit")

	var corrupt_id: String = pin_candidates.back()
	var corrupt_path := vault_path.path_join("%s.json" % corrupt_id)
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	assert(corrupt_file != null, "Could not create corrupt replay fixture")
	corrupt_file.store_string("{corrupt replay")
	corrupt_file.close()
	ReplayManager._load_replay_library(vault_path)
	ReplayManager._refresh_last_replay()
	assert(ReplayManager.replay_count() == ReplayManager.MAX_REPLAYS - 1, "A corrupt replay file was not isolated")
	assert(not ReplayManager.replay_by_id(pinned_id).is_empty(), "Corrupt replay isolation damaged a valid pinned entry")

	var recovery_entries := ReplayManager.list_replays()
	var pending_entry: Dictionary = recovery_entries[0]
	var pending_id := String(pending_entry.id)
	var pending_target := vault_path.path_join("%s.json" % pending_id)
	var pending_backup := vault_path.path_join("%s.backup" % pending_id)
	var pending_path := vault_path.path_join("%s.pending" % pending_id)
	assert(DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_target), ProjectSettings.globalize_path(pending_backup)) == OK, "Could not stage pending-recovery fixture")
	assert(ReplayManager._write_entry_file(pending_path, pending_entry) == OK, "Could not write valid pending replay fixture")
	ReplayManager._load_replay_library(vault_path)
	assert(not ReplayManager.replay_by_id(pending_id).is_empty() and FileAccess.file_exists(pending_target), "Valid pending replay was not promoted after interruption")
	assert(not FileAccess.file_exists(pending_path) and not FileAccess.file_exists(pending_backup), "Recovered replay transaction debris was not removed")

	recovery_entries = ReplayManager.list_replays()
	var backup_entry: Dictionary = recovery_entries[1]
	var backup_id := String(backup_entry.id)
	var backup_target := vault_path.path_join("%s.json" % backup_id)
	var backup_path := vault_path.path_join("%s.backup" % backup_id)
	var broken_pending_path := vault_path.path_join("%s.pending" % backup_id)
	assert(DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_target), ProjectSettings.globalize_path(backup_path)) == OK, "Could not stage backup-recovery fixture")
	var broken_pending := FileAccess.open(broken_pending_path, FileAccess.WRITE)
	assert(broken_pending != null, "Could not write broken pending replay fixture")
	broken_pending.store_string("invalid")
	broken_pending.close()
	ReplayManager._load_replay_library(vault_path)
	assert(not ReplayManager.replay_by_id(backup_id).is_empty() and FileAccess.file_exists(backup_target), "Replay backup was not restored after a broken promotion")

	var incompatible_replay := fixtures[13].duplicate(true)
	incompatible_replay.content_version = ReplayManager.CONTENT_VERSION + 1
	incompatible_replay.checksum = ReplayManager._checksum(incompatible_replay)
	var incompatible_id := String(incompatible_replay.checksum)
	var incompatible_entry := {
		"storage_version": ReplayManager.STORAGE_VERSION,
		"id": incompatible_id,
		"created_unix": 9999999999,
		"pinned": false,
		"replay": incompatible_replay
	}
	assert(ReplayManager._write_entry_file(vault_path.path_join("%s.json" % incompatible_id), incompatible_entry) == OK, "Could not write incompatible replay fixture")
	ReplayManager._load_replay_library(vault_path)
	var incompatible_visible := false
	for entry in ReplayManager.list_replays():
		if String(entry.id) == incompatible_id:
			incompatible_visible = true
			assert(not bool(entry.compatible), "Incompatible replay was marked playable")
	assert(incompatible_visible and ReplayManager.replay_by_id(incompatible_id).is_empty(), "Incompatible replay metadata was not retained safely")
	var retired_stage_replay := fixtures[12].duplicate(true)
	retired_stage_replay.stage_id = "retired_stage"
	retired_stage_replay.checksum = ReplayManager._checksum(retired_stage_replay)
	var retired_stage_id := String(retired_stage_replay.checksum)
	var retired_stage_entry := {
		"storage_version": ReplayManager.STORAGE_VERSION,
		"id": retired_stage_id,
		"created_unix": 9999999998,
		"pinned": false,
		"replay": retired_stage_replay
	}
	assert(ReplayManager._write_entry_file(vault_path.path_join("%s.json" % retired_stage_id), retired_stage_entry) == OK, "Could not write retired-stage replay fixture")
	ReplayManager._load_replay_library(vault_path)
	var retired_stage_visible := false
	for entry in ReplayManager.list_replays():
		if String(entry.id) == retired_stage_id:
			retired_stage_visible = true
			assert(not bool(entry.compatible), "Replay for an unavailable stage was marked playable")
	assert(retired_stage_visible and ReplayManager.replay_by_id(retired_stage_id).is_empty(), "Unavailable-stage replay metadata was not retained safely")

	_clear_validation_directory(vault_path)
	ReplayManager._active_replay_directory = saved_directory
	ReplayManager.persistence_enabled = saved_persistence
	ReplayManager._replay_entries.assign(saved_entries)
	ReplayManager.last_replay = saved_last

func _clear_validation_directory(directory_path: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
		return
	var directory := DirAccess.open(directory_path)
	assert(directory != null, "Could not open replay validation directory")
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		assert(not directory.current_is_dir(), "Unexpected directory inside replay validation fixture")
		assert(ReplayManager._remove_file(directory_path.path_join(file_name)) == OK, "Could not remove replay vault fixture")
		file_name = directory.get_next()
	directory.list_dir_end()
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(directory_path)) == OK, "Could not remove replay validation directory")

func _validation_directory() -> String:
	# Source/editor validation can use the repository-owned fixture directory. A
	# packaged build has a read-only res:// and must prove its user:// write path.
	if OS.has_feature("editor"):
		return "res://tests"
	var runtime_path := "user://validation"
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(runtime_path)) == OK, "Could not create the packaged validation directory")
	return runtime_path

func _run_smoke_combat() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.player.debug_invincible = true
	stage.player.locked = false
	assert(stage.radio_comms != null and stage.radio_comms._events.size() == stage.stage_data.radio_events.size(), "Authored route communications did not load")
	var radio_probe := stage.stage_data.radio_events[0]
	var presented_radio_ids := PackedStringArray()
	stage.radio_comms.event_started.connect(func(event_id: String): presented_radio_ids.append(event_id))
	stage.radio_comms.update_route_time(radio_probe.trigger_time, true)
	assert(not stage.radio_comms.has_fired(radio_probe.event_id), "A route transmission fired while the midboss clock was paused")
	stage.radio_comms.update_route_time(radio_probe.trigger_time, false)
	stage.radio_comms.update_route_time(radio_probe.trigger_time, false)
	assert(stage.radio_comms.has_fired(radio_probe.event_id) and presented_radio_ids.count(radio_probe.event_id) == 1, "A route transmission was missing or repeated")
	stage.radio_comms.reset_route()
	for sheet_path in [
		"res://assets/characters/kira_voss_combat_sheet.png",
		"res://assets/characters/dae_ryu_combat_sheet.png",
		"res://assets/characters/mina_zero_combat_sheet.png",
		"res://assets/enemies/neon_drone_combat_sheet.png",
		"res://assets/enemies/psychic_trooper_combat_sheet.png",
		"res://assets/enemies/assault_mech_combat_sheet.png",
		"res://assets/enemies/vector_gunship_combat_sheet.png",
		"res://assets/enemies/tempest_needle_combat_sheet.png",
		"res://assets/enemies/tempest_corona_combat_sheet.png",
		"res://assets/enemies/tempest_monolith_combat_sheet.png",
		"res://assets/bosses/arbiter_03_combat_sheet.png",
		"res://assets/bosses/seraph_executor_combat_sheet.png",
		"res://assets/bosses/ion_warden_combat_sheet.png",
		"res://assets/bosses/void_archon_combat_sheet.png"
	]:
		var sheet := load(sheet_path) as Texture2D
		assert(sheet != null and sheet.get_width() >= 1000 and sheet.get_height() >= 1000, "Combat animation sheet is missing or undersized: %s" % sheet_path)
	assert(stage.player.combat_sheet != null, "Authored player combat animation sheet did not load")
	assert(stage.enemy_manager.enemy_animation.size() == 7, "Authored enemy combat animation sheets did not load")
	var tempest_enemy_sheets := {
		"tempest_grade_3": "res://assets/enemies/tempest_needle_combat_sheet.png",
		"tempest_grade_2": "res://assets/enemies/tempest_corona_combat_sheet.png",
		"tempest_grade_1": "res://assets/enemies/tempest_monolith_combat_sheet.png"
	}
	for enemy_id in tempest_enemy_sheets:
		var tempest_sheet := stage.enemy_manager.enemy_animation.get(enemy_id) as Texture2D
		assert(tempest_sheet != null and tempest_sheet.resource_path == tempest_enemy_sheets[enemy_id], "NULL TEMPEST enemy uses the wrong combat sheet: %s" % enemy_id)
	stage.player.tilt = -1.0
	stage.player.update_player(0.02, {"x": -1.0, "y": 0.0, "primary": false, "focus": false, "barrier_pressed": false})
	assert(stage.player.pose_frame == PlayerController.POSE_BANK_LEFT, "Player left-bank animation state failed")
	stage.player.tilt = 1.0
	stage.player.update_player(0.02, {"x": 1.0, "y": 0.0, "primary": false, "focus": false, "barrier_pressed": false})
	assert(stage.player.pose_frame == PlayerController.POSE_BANK_RIGHT, "Player right-bank animation state failed")
	stage.player.update_player(0.02, {"x": 0.0, "y": 0.0, "primary": false, "focus": true, "barrier_pressed": false})
	assert(stage.player.pose_frame == PlayerController.POSE_FOCUS and stage.player.pose_blend < 1.0, "Player focus animation or cross-fade failed")
	stage.player.tilt = 0.0
	stage.player.focus_active = false
	stage.player._set_animation_pose(PlayerController.POSE_IDLE, 1.0)
	var enemy_animation_probe := EnemyUnit.new().setup(GameDatabase.enemy("grade_3"), Vector2.ZERO, Vector2.ZERO)
	enemy_animation_probe.velocity.x = -100.0
	enemy_animation_probe.update_animation(0.02)
	assert(enemy_animation_probe.animation_frame == 1 and enemy_animation_probe.animation_blend < 1.0, "Enemy left-bank animation or cross-fade failed")
	enemy_animation_probe.velocity.x = 100.0
	enemy_animation_probe.update_animation(0.02)
	assert(enemy_animation_probe.animation_frame == 2, "Enemy right-bank animation failed")
	enemy_animation_probe.fire_recoil = 1.0
	enemy_animation_probe.update_animation(0.02)
	assert(enemy_animation_probe.animation_frame == 3, "Enemy firing animation failed")
	var boss_animation_probe := BossController.new()
	stage.add_child(boss_animation_probe)
	boss_animation_probe.setup("arbiter", stage.bullet_manager, 0, 731)
	assert(boss_animation_probe.boss_animation != null, "Authored boss combat animation sheet did not load")
	boss_animation_probe.entering = false
	boss_animation_probe.phase_intro_timer = 0.0
	boss_animation_probe.telegraph_timer = 0.3
	boss_animation_probe._update_animation(0.02)
	assert(boss_animation_probe.pose_frame == BossController.POSE_TELEGRAPH and boss_animation_probe.pose_blend < 1.0, "Boss telegraph animation or cross-fade failed")
	boss_animation_probe.telegraph_timer = 0.0
	boss_animation_probe.recoil = 1.0
	boss_animation_probe._update_animation(0.02)
	assert(boss_animation_probe.pose_frame == BossController.POSE_ATTACK, "Boss attack-release animation failed")
	boss_animation_probe.recoil = 0.0
	boss_animation_probe.overdrive = true
	boss_animation_probe._update_animation(0.02)
	assert(boss_animation_probe.pose_frame == BossController.POSE_OVERDRIVE, "Boss overdrive animation failed")
	boss_animation_probe.queue_free()
	_verify_audio_system()
	_verify_enemy_grade_balance(stage)
	_verify_focus_attack_balance(stage)
	stage.play_time = 20.0
	for i in 4:
		stage.enemy_manager.spawn("grade_3", Vector2(270 + (i-2)*28, 420-i*34), Vector2(270 + (i-2)*28, 420-i*34))
	Input.action_press("primary")
	for i in 150:
		await get_tree().process_frame
	Input.action_release("primary")
	Input.action_press("focus")
	for i in 50:
		await get_tree().process_frame
	Input.action_release("focus")
	var before_barriers := stage.player.barriers
	var erase_probe := BulletData.new()
	erase_probe.speed = 0.0
	erase_probe.lifetime = 1.0
	stage.bullet_manager.spawn_bullet(stage.player.position + Vector2(32, 0), 0.0, erase_probe)
	Input.action_press("barrier")
	await get_tree().process_frame
	Input.action_release("barrier")
	var graze_bullet := BulletData.new()
	graze_bullet.speed = 0.0
	graze_bullet.lifetime = 0.5
	stage.bullet_manager.spawn_bullet(stage.player.position + Vector2(16,0), 0.0, graze_bullet)
	for i in 5:
		await get_tree().process_frame
	assert(ScoreManager.enemies_destroyed > 0, "Primary/focus combat failed to destroy enemies")
	assert(stage.player.barriers == before_barriers - 1, "Barrier resource was not consumed")
	assert(stage.bullet_manager.erase_positions.size() > 0, "Bullet erase sparks were not generated")
	assert(ScoreManager.graze > 0, "Graze did not register")
	assert(stage.replay_stream.size() >= ReplayManager.FRAME_STRIDE and stage.replay_stream.size() % ReplayManager.FRAME_STRIDE == 0, "Campaign input stream was not recorded")
	stage.assisted_run = true
	stage.hud.set_run_context("normal", false, "campaign")
	stage.player.locked = false
	stage.player.debug_invincible = false
	stage.player.invulnerable = 0.0
	stage.player.barrier_time = 0.0
	stage.player.barrier_cooldown = 0.0
	stage.player.barriers = 1
	var lives_before_assist := stage.player.lives
	var barriers_before_assist := ScoreManager.barriers_used
	stage._damage_player()
	assert(stage.player.lives == lives_before_assist, "Automatic barrier failed to prevent a life loss")
	assert(stage.player.barriers == 0 and ScoreManager.barriers_used == barriers_before_assist + 1, "Automatic barrier did not consume and register one barrier")
	print("COMBAT_SMOKE_OK grades=ok audio=ok player_animation=ok enemy_animation=ok boss_animation=ok kills=%d graze=%d barrier=ok auto_barrier=ok erase_fx=ok replay_record=ok score=%d" % [ScoreManager.enemies_destroyed, ScoreManager.graze, ScoreManager.score])
	_schedule_test_shutdown()

func _verify_audio_system() -> void:
	var required_sfx := [
		"ui_move", "ui_confirm", "shot", "focus", "enemy_shot", "telegraph",
		"hit", "enemy_die", "player_hit", "barrier", "graze", "pickup",
		"warning", "phase", "phase_perimeter", "phase_rotary", "phase_arbiter",
		"phase_sentence", "phase_halo", "phase_maelstrom", "phase_lattice",
		"phase_last_light", "boss_die"
	]
	assert(AudioManager.sfx_cache.size() >= required_sfx.size(), "The designed SFX library is incomplete")
	for id in required_sfx:
		var wav := AudioManager.sfx_cache.get(id) as AudioStreamWAV
		assert(wav != null and wav.stereo and wav.mix_rate == 44100, "Invalid SFX stream: %s" % id)
		assert(wav.data.size() >= 4 and wav.data.size() % 4 == 0, "Invalid SFX PCM payload: %s" % id)
		var peak := 0
		var stereo_difference := 0
		for offset in range(0, wav.data.size() - 3, 128):
			var left := wav.data.decode_s16(offset)
			var right := wav.data.decode_s16(offset + 2)
			peak = maxi(peak, maxi(absi(left), absi(right)))
			stereo_difference += absi(left - right)
		assert(peak > 32 and peak < 32767, "SFX is silent or clipping: %s" % id)
		assert(stereo_difference > 0, "SFX lacks stereo differentiation: %s" % id)
	assert(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("UI") >= 0, "Required audio buses are missing")
	assert(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("SFX")) >= 2, "Combat dynamics chain is incomplete")
	assert(AudioManager._sfx_priority("boss_die") > AudioManager._sfx_priority("shot"), "Critical SFX priority is invalid")
	assert(AudioManager._sfx_priority("phase_last_light") > AudioManager._sfx_priority("enemy_shot"), "Boss cue priority is invalid")
	AudioManager.play_sfx("ui_confirm", 1.0, -12.0)
	var ui_routed := false
	for player in AudioManager.sfx_players:
		if player.stream == AudioManager.sfx_cache["ui_confirm"] and player.bus == "UI":
			ui_routed = true
			break
	assert(ui_routed, "UI sound was not routed to the isolated UI bus")
	var saved_theme := AudioManager.theme
	var saved_intensity := AudioManager.music_intensity
	var saved_target_intensity := AudioManager.target_music_intensity
	var saved_theme_time := AudioManager.theme_time
	var saved_sample_clock := AudioManager.sample_clock
	var saved_pending_theme := AudioManager.pending_theme
	var saved_theme_transition := AudioManager.theme_transition
	var saved_transition_switched := AudioManager.theme_transition_switched
	var theme_signatures: Dictionary = {}
	for theme_id in AudioManager.THEMES.keys():
		AudioManager.theme = theme_id
		AudioManager.music_intensity = 0.78
		var signature := Vector2.ZERO
		for sample_index in [1301, 11003, 29011, 47017]:
			signature += AudioManager._music_frame(sample_index, AudioManager.THEMES[theme_id])
		assert(signature.length() > 0.0001 and maxf(absf(signature.x), absf(signature.y)) < 2.0, "Music theme output is invalid: %s" % theme_id)
		theme_signatures["%.5f:%.5f" % [signature.x, signature.y]] = true
	assert(theme_signatures.size() == AudioManager.THEMES.size(), "Music themes do not have distinct signatures")
	AudioManager.theme = "title"
	AudioManager.pending_theme = "stage"
	AudioManager.theme_transition = AudioManager.THEME_TRANSITION_DURATION
	AudioManager.theme_transition_switched = false
	AudioManager._process(AudioManager.THEME_TRANSITION_DURATION * 0.51)
	assert(AudioManager.theme == "stage" and AudioManager.theme_transition_switched, "Music transition did not switch themes at its fade midpoint")
	AudioManager._process(AudioManager.THEME_TRANSITION_DURATION * 0.51)
	assert(AudioManager.pending_theme.is_empty() and is_zero_approx(AudioManager.theme_transition), "Music transition did not complete cleanly")
	AudioManager._activate_theme(saved_theme if AudioManager.THEMES.has(saved_theme) else "title")
	AudioManager.pending_theme = saved_pending_theme
	AudioManager.theme_transition = saved_theme_transition
	AudioManager.theme_transition_switched = saved_transition_switched
	AudioManager.music_intensity = saved_intensity
	AudioManager.target_music_intensity = saved_target_intensity
	AudioManager.theme_time = saved_theme_time
	AudioManager.sample_clock = saved_sample_clock
	if DisplayServer.get_name() == "headless":
		assert(not AudioManager.audio_output_enabled and AudioManager.music_player == null and AudioManager.music_playback == null, "Headless mode created an audio-output playback")

func _verify_enemy_grade_balance(stage: StageController) -> void:
	var data := stage.stage_data
	var route_half := data.timeline.boss_spawn_time * 0.5
	assert(is_equal_approx(data.timeline.boss_spawn_time, 180.0), "Final boss must spawn at three minutes")
	var legacy_enemy_seed := maxi(1, (stage.run_seed ^ 0x41524249) & 0x7fffffff)
	assert(stage._derived_seed(0x41524249) == legacy_enemy_seed, "Default-stage seed stream changed and would desync legacy replays")
	stage.play_time = route_half
	stage.difficulty_id = "story"
	var story_threat := stage._difficulty()
	stage.difficulty_id = "normal"
	var normal_threat := stage._difficulty()
	stage.difficulty_id = "expert"
	var expert_threat := stage._difficulty()
	assert(story_threat < normal_threat and normal_threat < expert_threat, "Difficulty threat scaling is not ordered")
	assert(is_equal_approx(normal_threat, lerpf(0.88, 1.16, 0.5)), "Normal mode no longer preserves the original balance curve")
	stage.difficulty_id = "normal"
	stage.background.set_route_context(route_half, "midboss", 0)
	assert(is_equal_approx(stage.background.route_progress, 0.5) and stage.background.encounter_state == "midboss", "Midboss environment state is invalid")
	stage.background.set_route_context(data.timeline.boss_spawn_time, "final", 4)
	assert(is_equal_approx(stage.background.route_progress, 1.0) and stage.background.boss_phase == 4, "Final-boss environment state is invalid")
	stage.background.set_route_context(stage.play_time, "route", 0)
	var clock_before := stage.play_time
	var midboss_probe := BossController.new()
	midboss_probe.is_final = false
	stage.boss = midboss_probe
	stage._advance_stage_clock(10.0)
	assert(is_equal_approx(stage.play_time, clock_before), "Stage clock must pause during the midboss")
	midboss_probe.is_final = true
	stage._advance_stage_clock(10.0)
	assert(is_equal_approx(stage.play_time, clock_before + 10.0), "Stage clock must run outside the midboss")
	stage.boss = null
	var authored_midboss_hp := BossController.definition_for_id(data.midboss_id).phases[0].hp
	midboss_probe.setup(data.midboss_id, stage.bullet_manager)
	midboss_probe.entering = false
	assert(is_equal_approx(midboss_probe.phases[0].hp, authored_midboss_hp * GameDatabase.global_balance("boss_hp_scale")), "Boss runtime definition did not apply the HP balance scale")
	assert(is_equal_approx(BossController.definition_for_id(data.midboss_id).phases[0].hp, authored_midboss_hp), "Boss runtime setup mutated its shared authored definition")
	var boss_signatures := {}
	for phase_data in midboss_probe.phases:
		assert(not phase_data.signature_id.is_empty() and not phase_data.attack_sequence.is_empty(), "Midboss phase choreography is incomplete")
		boss_signatures[phase_data.signature_id] = true
	midboss_probe.update_boss(60.0, stage.player.position, 1.0)
	assert(midboss_probe.current_phase == 0 and not midboss_probe.dying, "Midboss must not advance or die when time expires")
	midboss_probe.free()
	var final_probe := BossController.new()
	final_probe.setup(data.final_boss_id, stage.bullet_manager)
	final_probe.entering = false
	for phase_data in final_probe.phases:
		assert(not phase_data.signature_id.is_empty() and not phase_data.attack_sequence.is_empty(), "Final-boss phase choreography is incomplete")
		boss_signatures[phase_data.signature_id] = true
	assert(boss_signatures.size() == data.expected_boss_phase_count, "Every configured boss phase must have a unique signature")
	final_probe.update_boss(60.0, stage.player.position, 1.0)
	assert(final_probe.current_phase == 0 and not final_probe.dying, "Final-boss phases must require HP depletion")
	assert(final_probe.overdrive, "A boss phase must enter overdrive after its par time")
	assert(not final_probe.pending_pattern_id.is_empty(), "Boss attack must enter a telegraph state before firing")
	var bullets_before_release := stage.bullet_manager.count()
	final_probe.update_boss(final_probe.telegraph_duration + 0.01, stage.player.position + Vector2(120.0, 0.0), 1.0)
	assert(stage.bullet_manager.count() > bullets_before_release, "Telegraphed boss attack was not released")
	var previous_pattern := ""
	for i in final_probe.phases[0].attack_sequence.size() * 2:
		var next_pattern := final_probe._next_pattern_id(final_probe.phases[0])
		assert(next_pattern != previous_pattern, "Boss pattern deck repeated the same attack consecutively")
		previous_pattern = next_pattern
	final_probe._advance_phase(false)
	assert(final_probe.current_phase == 1 and final_probe.phase_intro_timer > 0.0, "Boss phase transition did not start")
	var transition_hp := final_probe.hp
	final_probe.damage(transition_hp)
	assert(is_equal_approx(final_probe.hp, transition_hp), "Boss took damage during its phase transition")
	final_probe.update_boss(final_probe.phase_intro_duration + 0.01, stage.player.position, 1.0)
	assert(is_zero_approx(final_probe.phase_intro_timer), "Boss phase transition did not finish")
	stage.fx.phase_break(final_probe.position, final_probe.phases[1].accent, final_probe.phases[1].signature_id)
	assert(not stage.fx.phase_glyphs.is_empty(), "Boss phase-break visual was not created")
	final_probe.free()
	stage.bullet_manager.clear_all(false)
	stage.wave_index = 1
	stage.play_time = lerpf(data.timeline.wave_start_time, data.timeline.early_wave_end, 0.5)
	var early := stage._wave_composition()
	assert(early.size() == data.timeline.enemies_per_wave and early.count(data.grade_3_enemy_id) == data.timeline.early_grade_3_count, "Early wave grade composition is invalid")
	stage.play_time = lerpf(data.timeline.early_wave_end, data.timeline.late_wave_start, 0.5)
	var middle := stage._wave_composition()
	assert(middle.size() == data.timeline.enemies_per_wave and middle.count(data.grade_3_enemy_id) == data.timeline.middle_grade_3_count, "Middle wave must contain four grade-3 enemies")
	assert(middle.count(data.grade_1_enemy_id) + middle.count(data.grade_2_enemy_id) == 1, "Middle wave must contain one grade-1/2 enemy")
	stage.play_time = lerpf(data.timeline.late_wave_start, data.timeline.boss_warning_time, 0.5)
	var late := stage._wave_composition()
	assert(late.size() == data.timeline.enemies_per_wave and late.count(data.grade_3_enemy_id) == data.timeline.late_grade_3_count, "Late wave must contain three grade-3 enemies")
	assert(late.count(data.grade_1_enemy_id) == 1 and late.count(data.grade_2_enemy_id) == 1, "Late wave must contain one grade-1 and one grade-2 enemy")
	var grade_3 := GameDatabase.enemy(data.grade_3_enemy_id)
	var grade_2 := GameDatabase.enemy(data.grade_2_enemy_id)
	var grade_1 := GameDatabase.enemy(data.grade_1_enemy_id)
	assert(grade_3.radius < grade_2.radius and grade_2.radius < grade_1.radius, "Enemy grade sizes are invalid")
	assert(grade_2.hp >= 315.0 and grade_1.hp >= 720.0, "Grade-1/2 enemies do not have the required durability")
	assert(grade_3.fire_interval < grade_2.fire_interval and grade_2.fire_interval < grade_1.fire_interval, "Enemy grade fire rates are invalid")
	assert(is_equal_approx(GameDatabase.global_balance("boss_hp_scale"), 4.0), "Boss HP multiplier must be 4x base / 2x current")
	assert(GameDatabase.pattern(grade_2.pattern_id).kind == "radial", "Grade-2 pattern must be radial")
	assert(GameDatabase.pattern(grade_1.pattern_id).kind == "circle", "Grade-1 pattern must be circular")
	var burst := GameDatabase.pattern(grade_3.pattern_id)
	PatternEmitter.emit(stage.bullet_manager, Vector2.ZERO, Vector2(0.0, 100.0), burst, 0.0, 1.45)
	assert(stage.bullet_manager.count() == 3, "Grade-3 attack must fire exactly three bullets")
	assert(is_equal_approx(stage.bullet_manager.velocities[0].angle(), stage.bullet_manager.velocities[1].angle()), "Grade-3 burst must travel in one straight direction")
	assert(is_equal_approx(stage.bullet_manager.velocities[1].angle(), stage.bullet_manager.velocities[2].angle()), "Grade-3 burst must travel in one straight direction")
	assert(is_equal_approx(stage.bullet_manager.delays[1], 0.09) and is_equal_approx(stage.bullet_manager.delays[2], 0.18), "Grade-3 burst timing is invalid")
	stage.bullet_manager.clear_all(false)
	var circle := GameDatabase.pattern(grade_1.pattern_id)
	PatternEmitter.emit(stage.bullet_manager, Vector2.ZERO, Vector2(0.0, 100.0), circle, 0.0, 1.0)
	assert(circle.volley_count == 3, "Grade-1 attack must contain three circular volleys")
	assert(stage.bullet_manager.count() == circle.count * 3, "Grade-1 circular volley count is invalid")
	assert(is_equal_approx(stage.bullet_manager.delays[0], 0.0), "Grade-1 first circle must fire immediately")
	assert(is_equal_approx(stage.bullet_manager.delays[circle.count], 0.22), "Grade-1 second circle timing is invalid")
	assert(is_equal_approx(stage.bullet_manager.delays[circle.count * 2], 0.44), "Grade-1 third circle timing is invalid")
	stage.bullet_manager.clear_all(false)

func _verify_focus_attack_balance(stage: StageController) -> void:
	stage.projectile_manager.clear()
	assert(SaveManager.settings.has("auto_fire") and SaveManager.settings.has("bullet_contrast"), "Accessibility settings are missing")
	var original_auto_fire := bool(SaveManager.settings.auto_fire)
	SaveManager.settings.auto_fire = true
	stage.player.primary_timer = 0.0
	stage.player.update_player(0.1)
	assert(not stage.projectile_manager.positions.is_empty(), "Auto primary fire did not create projectiles")
	SaveManager.settings.auto_fire = original_auto_fire
	stage.projectile_manager.clear()
	stage.player.power = 4
	stage.player._fire_focus()
	assert(not stage.projectile_manager.positions.is_empty(), "Focus attack did not create projectiles")
	for scale in stage.projectile_manager.boss_damage_scales:
		assert(is_equal_approx(scale, PlayerController.FOCUS_BOSS_DAMAGE_SCALE), "Focus boss damage scale is invalid")
	var target_id := 42
	stage.projectile_manager.mark_hit_target(0, target_id)
	assert(stage.projectile_manager.has_hit_target(0, target_id), "Piercing projectile did not remember its target")
	stage.projectile_manager.clear()
	var boss_probe := BossController.new()
	boss_probe.setup("seraph", stage.bullet_manager)
	boss_probe.entering = false
	boss_probe.position = Vector2(270.0, 220.0)
	stage.boss = boss_probe
	stage.projectile_manager.spawn(boss_probe.position, Vector2.ZERO, 100.0, 4.0, Color.WHITE, true, PlayerController.FOCUS_BOSS_DAMAGE_SCALE)
	var hp_before := boss_probe.hp
	stage._update_boss(0.0, 1.0)
	var hp_after_first_hit := boss_probe.hp
	stage._update_boss(0.0, 1.0)
	assert(is_equal_approx(hp_before - hp_after_first_hit, 75.0), "Focus boss damage reduction was not applied")
	assert(is_equal_approx(boss_probe.hp, hp_after_first_hit), "Piercing focus attack damaged the same boss more than once")
	stage.boss = null
	boss_probe.free()
	stage.projectile_manager.clear()

func _run_bullet_benchmark() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.set_process(false)
	stage.bullet_manager.collision_enabled = false
	var data := BulletData.new()
	data.speed = 26.0
	data.lifetime = 20.0
	data.radius = 5.0
	for i in 4000:
		var p := Vector2(45 + (i * 47) % 450, 95 + (i * 83) % 760)
		stage.bullet_manager.spawn_bullet(p, float(i % 360) * PI / 180.0, data)
	var start_us := Time.get_ticks_usec()
	for frame in 300:
		stage.bullet_manager.update_bullets(1.0/60.0, Vector2(-500,-500), false)
	var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	var average_ms := elapsed_ms / 300.0
	assert(stage.bullet_manager.count() >= 3000, "Bullet array corrupted during benchmark")
	print("BULLET_BENCHMARK_OK bullets=%d frames=300 average_update_ms=%.3f" % [stage.bullet_manager.count(), average_ms])
	_schedule_test_shutdown()

func _run_render_benchmark() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_start_stage(0, false, 0, "normal")
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.set_process(false)
	stage.bullet_manager.collision_enabled = false
	var data := BulletData.new()
	data.speed = 9.0
	data.lifetime = 30.0
	data.radius = 5.0
	for i in 4000:
		var p := Vector2(28 + (i * 47) % 484, 72 + (i * 83) % 820)
		data.color = Color("ff4b91") if i % 3 else Color("ffb340")
		stage.bullet_manager.spawn_bullet(p, float(i % 360) * PI / 180.0, data)
	# Warm the shader and renderer before timing so display sync and first-frame
	# compilation do not get reported as bullet throughput.
	for warmup_frame in 60:
		stage.bullet_manager.update_bullets(1.0/60.0, Vector2(-500,-500), false)
		await get_tree().process_frame
	# Layer a boss-scale destruction event over maximum bullet density.
	for i in 8:
		var blast_position := Vector2(80 + i * 54, 210 + (i % 3) * 85)
		stage.fx.burst(blast_position, Color("47e8ff") if i % 2 else Color("ff4b91"), 1.45, 40)
		stage.fx.shockwave(blast_position, Color("ffc75c"), 1.2)
	for i in 160:
		stage.bullet_manager._add_erase_spark(Vector2(34 + (i * 43) % 472, 90 + (i * 79) % 790), Color("ff5caa"))
	await RenderingServer.frame_post_draw
	var start_us := Time.get_ticks_usec()
	for frame in 180:
		stage.bullet_manager.update_bullets(1.0/60.0, Vector2(-500,-500), false)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
	var average_ms := elapsed_ms / 180.0
	assert(average_ms <= 16.667, "4,000-bullet render stress exceeded the 60 FPS frame budget")
	print("BULLET_RENDER_STRESS_OK bullets=%d erase_sparks=160 explosion_particles=320 frames=180 average_frame_ms=%.3f measured_fps=%.1f" % [stage.bullet_manager.count(), average_ms, 1000.0 / maxf(0.001, average_ms)])
	_schedule_test_shutdown()

func _capture_title() -> void:
	_show_title()
	await get_tree().create_timer(0.42, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/title_capture.png")
	print("TITLE_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_select() -> void:
	_show_character_select()
	await get_tree().create_timer(0.42, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/select_capture.png")
	print("SELECT_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_stage() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().create_timer(0.42, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.locked = false
	stage.player.position = Vector2(270,820)
	stage.play_time = 150.0
	stage.background.time = 150.0
	stage.background.set_route_context(stage.play_time, "route", 0)
	var showcase := ["gunship","guard","shield","sniper","heavy_drone"]
	for i in showcase.size():
		var showcase_position := Vector2(72+i*96,190+(i%2)*135)
		var unit := stage.enemy_manager.spawn(showcase[i],showcase_position,showcase_position,i==2)
		unit.entering = false
		unit.age = 1.0
	var ring := GameDatabase.pattern("ring")
	var layered := GameDatabase.pattern("layered")
	var spread := GameDatabase.pattern("spread")
	PatternEmitter.emit(stage.bullet_manager,Vector2(120,230),stage.player.position,ring,0.17,1.0)
	PatternEmitter.emit(stage.bullet_manager,Vector2(420,235),stage.player.position,layered,0.42,1.0)
	PatternEmitter.emit(stage.bullet_manager,Vector2(270,330),stage.player.position,spread,0.0,1.0)
	stage.bullet_manager.collision_enabled = false
	stage.bullet_manager.update_bullets(1.25,Vector2(-500,-500),false)
	for i in 18:
		stage.projectile_manager.spawn(stage.player.position+Vector2((i%5-2)*7,-i*18),Vector2(0,-900),8.0,3.0,GameManager.character().primary_color)
	stage.enemy_manager.queue_redraw()
	stage.bullet_manager.queue_redraw()
	stage.projectile_manager.queue_redraw()
	stage.hud.message_time = 0.0
	stage.hud.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/stage_capture.png")
	print("STAGE_CAPTURE status=%s size=%s bullets=%d" % [error_string(error), str(image.get_size()), stage.bullet_manager.count()])
	_schedule_test_shutdown()

func _capture_player_animation() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().create_timer(0.32, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.visible = false
	stage.enemy_manager.clear_all(true)
	stage.bullet_manager.clear_all(true)
	stage.play_time = 132.0
	stage.background.time = 132.0
	stage.background.set_route_context(132.0, "route", 0)
	stage.hud.message_time = 0.0
	stage.hud.message_duration = 0.0
	stage.hud.message = ""
	stage.hud.message_sub = ""
	stage.hud.queue_redraw()
	for character_index in GameManager.CHARACTERS.size():
		for pose_index in 4:
			var preview := PlayerController.new()
			preview.z_index = 4
			stage.add_child(preview)
			preview.configure(GameManager.CHARACTERS[character_index], stage.projectile_manager)
			preview.locked = false
			preview.invulnerable = 0.0
			preview.position = Vector2(108.0 + character_index * 162.0, 270.0 + pose_index * 155.0)
			preview._set_animation_pose(pose_index, 1.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/player_animation_capture.png")
	print("PLAYER_ANIMATION_CAPTURE status=%s size=%s characters=3 poses=4" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_enemy_animation() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().create_timer(0.32, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.visible = false
	stage.enemy_manager.clear_all(true)
	stage.bullet_manager.clear_all(true)
	stage.play_time = 132.0
	stage.background.time = 132.0
	stage.background.set_route_context(132.0, "route", 0)
	stage.hud.message_time = 0.0
	stage.hud.message_duration = 0.0
	stage.hud.message = ""
	stage.hud.message_sub = ""
	stage.hud.queue_redraw()
	var archetypes := ["drone", "soldier", "mech", "gunship"]
	for archetype_index in archetypes.size():
		for pose_index in 4:
			var preview_position := Vector2(70.0 + archetype_index * 133.0, 175.0 + pose_index * 195.0)
			var unit := stage.enemy_manager.spawn(archetypes[archetype_index], preview_position, preview_position)
			unit.entering = false
			unit.age = 1.0
			unit.data.radius = 26.0
			unit.animation_frame = pose_index
			unit.previous_animation_frame = pose_index
			unit.animation_blend = 1.0
			unit.fire_recoil = 0.0
	stage.enemy_manager.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/enemy_animation_capture.png")
	print("ENEMY_ANIMATION_CAPTURE status=%s size=%s archetypes=4 poses=4" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_boss_animation() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().create_timer(0.32, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.visible = false
	stage.enemy_manager.clear_all(true)
	stage.bullet_manager.clear_all(true)
	stage.play_time = 176.0
	stage.background.time = 176.0
	stage.background.set_route_context(176.0, "final", 4)
	stage.hud.message_time = 0.0
	stage.hud.message_duration = 0.0
	stage.hud.message = ""
	stage.hud.message_sub = ""
	stage.hud.queue_redraw()
	var boss_ids := ["arbiter", "seraph"]
	for boss_index in boss_ids.size():
		for pose_index in 4:
			var phase_index: int = mini(pose_index, 2) if boss_index == 0 else int([0, 1, 2, 4][pose_index])
			var preview := BossController.new()
			stage.add_child(preview)
			preview.setup(boss_ids[boss_index], stage.bullet_manager, phase_index, 900 + boss_index * 10 + pose_index)
			preview.entering = false
			preview.position = Vector2(145.0 + boss_index * 250.0, 155.0 + pose_index * 210.0)
			preview.phase_intro_timer = 0.0
			preview.telegraph_timer = 0.0
			preview.recoil = 0.0
			preview.overdrive = pose_index == BossController.POSE_OVERDRIVE
			preview.hp = preview.max_hp * (0.25 if preview.overdrive else 1.0)
			preview.pose_frame = pose_index
			preview.previous_pose_frame = pose_index
			preview.pose_blend = 1.0
			if pose_index == BossController.POSE_TELEGRAPH:
				preview.pending_pattern_id = "aimed"
				preview.pending_target = Vector2(270, 820)
				preview.telegraph_duration = 1.0
				preview.telegraph_timer = 0.45
			elif pose_index == BossController.POSE_ATTACK:
				preview.recoil = 1.0
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/boss_animation_capture.png")
	print("BOSS_ANIMATION_CAPTURE status=%s size=%s bosses=2 poses=4" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_boss(stage_id: String = StageManager.DEFAULT_STAGE_ID, output_path: String = "res://tests/boss_capture.png") -> void:
	_start_stage(1, false, 0, "normal", stage_id)
	await get_tree().create_timer(0.42, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.locked = false
	stage.player.debug_invincible = true
	stage.player.position = Vector2(270, 830)
	stage.play_time = 500.0
	stage.background.set_route_context(180.0, "final", 3)
	stage._spawn_boss(true)
	stage.boss.entering = false
	stage.boss.position = Vector2(270, 220)
	stage.boss.current_phase = 3
	stage.boss._start_phase()
	stage.boss.phase_intro_timer = stage.boss.phase_intro_duration * 0.5
	stage.hud.message_time = 0.0
	var geometric := GameDatabase.pattern("geometric")
	var rotating := GameDatabase.pattern("rotating")
	PatternEmitter.emit(stage.bullet_manager, stage.boss.position, stage.player.position, geometric, 0.15, 1.0)
	PatternEmitter.emit(stage.bullet_manager, stage.boss.position, stage.player.position, rotating, 0.55, 1.0)
	stage.bullet_manager.collision_enabled = false
	stage.bullet_manager.update_bullets(1.55, Vector2(-500, -500), false)
	stage.hud.set_boss(stage.boss.display_name, stage.boss.total_remaining_hp(), stage.boss.total_max_hp(), 4, 5)
	stage.boss.queue_redraw()
	await get_tree().create_timer(0.48, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	print("BOSS_CAPTURE status=%s size=%s bullets=%d" % [error_string(error), str(image.get_size()), stage.bullet_manager.count()])
	_schedule_test_shutdown()

func _capture_results() -> void:
	var synthetic := {
		"mode": "campaign",
		"difficulty": "expert",
		"assisted": true,
		"replay_available": true,
		"replay_id": "capture",
		"new_high_score": false,
		"cleared": true,
		"score": 3248750,
		"enemies_destroyed": 327,
		"graze": 1864,
		"max_combo": 146,
		"deaths": 1,
		"clear_time": 244.82,
		"boss_bonus": 685000,
		"total_score": 3933750
	}
	var screen := ResultsScreen.new()
	screen.setup(synthetic)
	_replace_view(screen)
	await get_tree().create_timer(0.42, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/results_capture.png")
	print("RESULTS_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_localization() -> void:
	var original_language := String(SaveManager.settings.language)
	SaveManager.settings.language = "ko"
	_show_title()
	await get_tree().create_timer(0.2, true, false, true).timeout
	var title := current_view as TitleScreen
	title._show_options()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var options_image := get_viewport().get_texture().get_image()
	var options_error := options_image.save_png("res://tests/options_ko_capture.png")
	title._show_bindings()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var bindings_image := get_viewport().get_texture().get_image()
	var bindings_error := bindings_image.save_png("res://tests/bindings_ko_capture.png")
	title._toggle_binding_mode()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var gamepad_bindings_image := get_viewport().get_texture().get_image()
	var gamepad_bindings_error := gamepad_bindings_image.save_png("res://tests/gamepad_bindings_ko_capture.png")
	title._close_bindings()
	await get_tree().process_frame
	title._close_options()
	await get_tree().process_frame
	title._show_help()
	await get_tree().create_timer(0.2, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var help_image := get_viewport().get_texture().get_image()
	var help_error := help_image.save_png("res://tests/help_ko_capture.png")
	SaveManager.settings.language = original_language
	print("LOCALIZATION_CAPTURE options=%s bindings=%s gamepad=%s help=%s size=%s" % [error_string(options_error), error_string(bindings_error), error_string(gamepad_bindings_error), error_string(help_error), str(help_image.get_size())])
	_schedule_test_shutdown()

func _capture_assists() -> void:
	var settings_backup := SaveManager.settings.duplicate(true)
	SaveManager.apply_assist_preset("guardian")
	SaveManager.settings.language = "ko"
	_show_title()
	await get_tree().create_timer(0.2, true, false, true).timeout
	var title := current_view as TitleScreen
	title._show_options()
	await get_tree().process_frame
	title._show_assists()
	await get_tree().create_timer(0.3, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/assists_capture.png")
	SaveManager.settings = settings_backup
	SaveManager.apply_settings()
	print("ASSISTS_CAPTURE status=%s size=%s preset=guardian" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_controller_notice() -> void:
	var original_language := String(SaveManager.settings.language)
	SaveManager.settings.language = "ko"
	_show_title()
	await get_tree().create_timer(0.45, true, false, true).timeout
	_on_joy_connection_changed(0, false)
	await get_tree().create_timer(0.1, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/controller_notice_ko_capture.png")
	SaveManager.settings.language = original_language
	print("CONTROLLER_NOTICE_CAPTURE status=%s size=%s" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_training() -> void:
	var original_language := String(SaveManager.settings.language)
	SaveManager.settings.language = "ko"
	var screen := TrainingScreen.new()
	_replace_view(screen)
	await get_tree().process_frame
	screen.step = 3
	screen.transition_time = 0.0
	screen._spawn_barrier_demo()
	screen.queue_redraw()
	await get_tree().create_timer(0.42, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/training_capture.png")
	SaveManager.settings.language = original_language
	print("TRAINING_CAPTURE status=%s size=%s step=barrier" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _capture_records() -> void:
	var original_language := String(SaveManager.settings.language)
	SaveManager.settings.language = "ko"
	SaveManager.selected_difficulty = "normal"
	SaveManager.run_history.assign(_archive_samples())
	ReplayManager.clear_memory_library()
	var replay_frames: Array[int] = [16667, 4000, 0, ReplayManager.MASK_PRIMARY, 16667, -4000, 0, ReplayManager.MASK_FOCUS]
	for index in 2:
		var phase_metrics: Array[Dictionary] = []
		for phase_index in (8 if index == 0 else 4):
			phase_metrics.append({"phase": phase_index})
		var replay := ReplayManager.build_replay(index + 1, "normal", false, 55101 + index, replay_frames, {
			"cleared": index == 0, "total_score": 2847300 - index * 615400,
			"deaths": index, "barriers_used": index + 1,
			"clear_time": 218.4 + index * 31.0, "boss_phase_metrics": phase_metrics
		})
		assert(ReplayManager.save_replay(replay), "Could not seed replay-vault capture")
	var capture_entries := ReplayManager.list_replays("normal")
	assert(capture_entries.size() == 2 and ReplayManager.set_pinned(String(capture_entries[1].id), true), "Could not seed pinned replay-vault capture")
	var screen := RecordsScreen.new()
	_replace_view(screen)
	await get_tree().process_frame
	screen.replay_index = 1
	screen._refresh_replay_controls()
	await get_tree().create_timer(0.45, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/records_capture.png")
	SaveManager.settings.language = original_language
	print("RECORDS_CAPTURE status=%s size=%s runs=9 replays=2" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _seed_archive_samples() -> void:
	for entry in _archive_samples():
		SaveManager.record_run(entry, int(entry.character))

func _archive_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for i in 9:
		var cleared := i % 4 != 1
		var phase_count := 8 if cleared else 4
		var phase_metrics: Array[Dictionary] = []
		for phase_index in phase_count:
			phase_metrics.append({
				"boss_id": "seraph" if phase_index >= 3 else "arbiter",
				"phase": phase_index,
				"phase_name": "PHASE %d" % (phase_index + 1),
				"clear_time": 16.0 + phase_index * 2.5 + i,
				"overdrive": phase_index == phase_count - 1 and i % 3 == 0
			})
		var raw_entry := {
			"mode": "campaign",
			"difficulty": GameManager.DIFFICULTY_ORDER[i % GameManager.DIFFICULTY_ORDER.size()],
			"character": (i + floori(float(i) / 3.0)) % GameManager.CHARACTERS.size(),
			"cleared": cleared,
			"assisted": i == 4 or i == 8,
			"total_score": 980000 + i * 317250,
			"clear_time": 236.0 + i * 13.75,
			"route_time": 180.0 + i * 4.0,
			"deaths": i % 3,
			"barriers_used": i % 4,
			"enemies_destroyed": 118 + i * 9,
			"graze": 340 + i * 117,
			"max_combo": 32 + i * 8,
			"boss_phase_metrics": phase_metrics,
			"timestamp": 1735689600 + i * 86400
		}
		samples.append(SaveManager._sanitize_run_entry(raw_entry))
	return samples

func _capture_practice() -> void:
	active_stage_id = StageManager.DEFAULT_STAGE_ID
	_show_character_select(true)
	await get_tree().create_timer(0.4, true, false, true).timeout
	if current_view is CharacterSelect:
		(current_view as CharacterSelect).selected_phase = 3
		(current_view as CharacterSelect).queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/practice_capture.png")
	print("PRACTICE_CAPTURE status=%s size=%s phase=4" % [error_string(error), str(image.get_size())])
	_schedule_test_shutdown()

func _schedule_test_shutdown() -> void:
	Engine.time_scale = 1.0
	Input.action_release("primary")
	Input.action_release("focus")
	AudioManager.shutdown()
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
		current_view = null
	await get_tree().process_frame
	await get_tree().create_timer(0.35, true, false, true).timeout
	get_tree().quit()

func _replace_view(next_view: Node) -> void:
	if current_view != null and is_instance_valid(current_view):
		current_view.queue_free()
	current_view = next_view
	add_child(current_view)
	if transition_layer:
		transition_rect.color = Color(0.004, 0.008, 0.028, 1.0)
		transition_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(transition_rect, "color:a", 0.0, 0.34)
		tween.tween_callback(func(): transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)

func _show_title() -> void:
	get_tree().paused = false
	active_replay_id = ""
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := TitleScreen.new()
	screen.start_pressed.connect(_on_start_pressed)
	screen.practice_pressed.connect(_show_practice_select)
	screen.records_pressed.connect(_show_records)
	screen.training_pressed.connect(_show_training)
	screen.credits_pressed.connect(_show_credits)
	_replace_view(screen)

func _on_start_pressed() -> void:
	if SaveManager.tutorial_completed:
		_show_stage_select()
	else:
		_show_training()

func _show_training() -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.TRAINING)
	var screen := TrainingScreen.new()
	screen.completed.connect(_complete_training)
	screen.skipped.connect(_complete_training)
	_replace_view(screen)

func _complete_training() -> void:
	SaveManager.complete_tutorial()
	_show_stage_select()

func _show_stage_select(practice: bool = false) -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.CHARACTER_SELECT)
	stage_select_practice = practice
	var screen := StageSelect.new()
	screen.stage_confirmed.connect(_on_stage_confirmed)
	screen.cancelled.connect(_show_title)
	_replace_view(screen)

func _on_stage_confirmed(stage_id: String) -> void:
	if not SaveManager.is_stage_unlocked(stage_id):
		return
	active_stage_id = stage_id
	_show_character_select(stage_select_practice)

func _show_records() -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := RecordsScreen.new()
	screen.closed.connect(_show_title)
	screen.replay_requested.connect(_start_replay_by_id)
	_replace_view(screen)

func _show_credits() -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := CreditsScreen.new()
	screen.closed.connect(_show_title)
	_replace_view(screen)

func _show_character_select(practice: bool = false) -> void:
	GameManager.set_state(GameManager.GameState.CHARACTER_SELECT)
	var screen := CharacterSelect.new()
	screen.practice_mode = practice
	screen.stage_data = StageManager.stage(active_stage_id)
	if screen.stage_data == null:
		active_stage_id = StageManager.DEFAULT_STAGE_ID
		screen.stage_data = StageManager.default_stage()
	if practice:
		screen.practice_confirmed.connect(_start_practice)
	else:
		screen.campaign_confirmed.connect(_show_operation_briefing)
	screen.cancelled.connect(_show_stage_select.bind(practice))
	_replace_view(screen)

func _show_operation_briefing(index: int, difficulty_id: String) -> void:
	var data := StageManager.stage(active_stage_id)
	if data == null or not SaveManager.is_stage_unlocked(active_stage_id):
		_show_stage_select()
		return
	var screen := OperationBriefing.new()
	screen.setup(data, index, difficulty_id)
	screen.completed.connect(_on_operation_briefing_completed)
	screen.cancelled.connect(_show_character_select.bind(false))
	_replace_view(screen)

func _on_operation_briefing_completed(index: int, difficulty_id: String, stage_id: String, _skipped: bool) -> void:
	if stage_id != active_stage_id or not StageManager.has_stage(stage_id) or not SaveManager.is_stage_unlocked(stage_id):
		_show_stage_select()
		return
	_start_stage(index, false, 0, difficulty_id, stage_id)

func _show_practice_select() -> void:
	_show_stage_select(true)

func _start_practice(index: int, phase_index: int = 0) -> void:
	_start_stage(index, true, phase_index, "normal", active_stage_id)

func _start_campaign(index: int, difficulty_id: String) -> void:
	_start_stage(index, false, 0, difficulty_id, active_stage_id)

func _start_last_replay() -> void:
	var replay_id := ReplayManager.latest_id()
	if replay_id.is_empty():
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_unavailable"))
		return
	_start_replay_by_id(replay_id)

func _start_replay_by_id(replay_id: String) -> void:
	var data := ReplayManager.replay_by_id(replay_id)
	if data.is_empty():
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_unavailable"))
		return
	var replay_stage_id := String(data.get("stage_id", StageManager.DEFAULT_STAGE_ID))
	if not StageManager.has_stage(replay_stage_id):
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_unavailable"))
		return
	get_tree().paused = false
	run_mode = "replay"
	active_replay_id = replay_id
	active_stage_id = replay_stage_id
	practice_start_phase = 0
	active_difficulty = String(data.get("difficulty", "normal"))
	GameManager.start_replay(int(data.get("character", 0)), active_difficulty)
	var stage := StageController.new()
	stage.setup_replay(data)
	stage.run_finished.connect(_on_run_finished)
	stage.pause_requested.connect(_show_pause)
	_replace_view(stage)

func _start_stage(index: int = GameManager.selected_character, practice: bool = false, phase_index: int = 0, next_difficulty: String = "", next_stage_id: String = "") -> void:
	var requested_stage_id := next_stage_id if not next_stage_id.is_empty() else StageManager.DEFAULT_STAGE_ID
	var next_stage := StageManager.stage(requested_stage_id)
	if next_stage == null:
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_unavailable"))
		return
	get_tree().paused = false
	active_replay_id = ""
	active_stage_id = next_stage.stage_id
	run_mode = "practice" if practice else "campaign"
	practice_start_phase = clampi(phase_index, 0, maxi(0, next_stage.practice_phase_name_keys.size() - 1)) if practice else 0
	if practice:
		active_difficulty = "normal"
	elif GameManager.DIFFICULTY_ORDER.has(next_difficulty):
		active_difficulty = next_difficulty
	elif not GameManager.DIFFICULTY_ORDER.has(active_difficulty):
		active_difficulty = "normal"
	GameManager.start_run(index, active_difficulty, not practice)
	var stage := StageController.new()
	stage.setup_stage(next_stage)
	stage.practice_mode = practice
	stage.practice_phase = practice_start_phase
	stage.difficulty_id = active_difficulty
	stage.run_finished.connect(_on_run_finished)
	stage.pause_requested.connect(_show_pause)
	_replace_view(stage)

func _show_pause() -> void:
	if pause_menu != null:
		return
	get_tree().paused = true
	pause_menu = PauseMenu.new()
	var active_stage := StageManager.stage(active_stage_id)
	pause_menu.subtitle_key = active_stage.pause_key if active_stage != null else "pause_sub"
	pause_menu.resume_pressed.connect(_resume)
	pause_menu.restart_pressed.connect(_restart_stage)
	pause_menu.title_pressed.connect(_quit_to_title)
	add_child(pause_menu)

func _resume() -> void:
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false

func _restart_stage() -> void:
	_resume()
	_retry_run()

func _retry_run() -> void:
	if run_mode == "replay":
		if active_replay_id.is_empty():
			_start_last_replay()
		else:
			_start_replay_by_id(active_replay_id)
	else:
		_start_stage(GameManager.selected_character, run_mode == "practice", practice_start_phase, active_difficulty, active_stage_id)

func _quit_to_title() -> void:
	_resume()
	_show_title()

func _on_run_finished(result: Dictionary) -> void:
	if smoke_mode:
		Engine.time_scale = 1.0
		var smoke_stage := StageManager.stage(String(result.get("stage_id", active_stage_id)))
		var expected_phase_count := smoke_stage.expected_boss_phase_count if smoke_stage != null else 8
		assert((result.get("boss_phase_metrics", []) as Array).size() == expected_phase_count, "Full run must record every configured boss phase")
		assert(float(result.get("clear_time", 0.0)) >= float(result.get("route_time", 0.0)), "Session time must include the midboss gate")
		print("ACCEPTANCE_SMOKE_OK stage=%s total_score=%d clear_time=%.2f cleared=%s boss_phases=%d" % [String(result.get("stage_id", "")), int(result.get("total_score",0)), float(result.get("clear_time",0.0)), str(result.get("cleared",false)), (result.get("boss_phase_metrics", []) as Array).size()])
		_schedule_test_shutdown()
		return
	if bool(result.get("restart",false)):
		_retry_run()
		return
	if bool(result.get("replay_invalid", false)):
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_invalid"))
		return
	var result_mode := String(result.get("mode", run_mode))
	result["stage_id"] = String(result.get("stage_id", active_stage_id))
	var result_stage := StageManager.stage(String(result.stage_id))
	if result_stage != null:
		result["stage_title_key"] = String(result.get("stage_title_key", result_stage.title_key))
		result["after_action_key"] = String(result.get("after_action_key", result_stage.result_key))
	if result_mode == "campaign" and current_view is StageController:
		var replay := (current_view as StageController).build_replay_payload(result)
		result["replay_available"] = not replay.is_empty() and ReplayManager.save_replay(replay)
		result["replay_id"] = ReplayManager.latest_id() if bool(result.replay_available) else ""
	var ranked_run := result_mode == "campaign" and not bool(result.get("assisted", false))
	var previous_record := SaveManager.high_score_for(String(result.get("difficulty", active_difficulty)), String(result.stage_id))
	result["new_high_score"] = ranked_run and int(result.get("total_score", 0)) > previous_record
	result["character"] = GameManager.selected_character
	GameManager.finish_run(result, ranked_run)
	if CampaignEnding.supports(result, result_stage):
		var ending_screen := CampaignEnding.new()
		ending_screen.setup(result, result_stage)
		ending_screen.results_requested.connect(_present_results)
		_replace_view(ending_screen)
		return
	_present_results(result)

func _present_results(result: Dictionary) -> void:
	var screen := ResultsScreen.new()
	screen.setup(result)
	screen.next_operation_pressed.connect(_continue_to_next_operation)
	screen.retry_pressed.connect(_retry_run)
	screen.replay_pressed.connect(_start_replay_by_id)
	screen.title_pressed.connect(_show_title)
	_replace_view(screen)

func _continue_to_next_operation(stage_id: String) -> void:
	if not StageManager.has_stage(stage_id) or not SaveManager.is_stage_unlocked(stage_id):
		_show_stage_select()
		return
	active_stage_id = stage_id
	active_replay_id = ""
	run_mode = "campaign"
	practice_start_phase = 0
	_show_character_select(false)
