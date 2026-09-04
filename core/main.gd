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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_transition()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	GameManager.selected_character = SaveManager.selected_character
	active_difficulty = SaveManager.selected_difficulty
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke-stage"):
		smoke_mode = true
		call_deferred("_run_smoke_stage")
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
	elif args.has("--capture-boss"):
		call_deferred("_capture_boss")
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

func _run_smoke_stage() -> void:
	_start_stage(0, false, 0, "normal")
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
	var run_history_backup := SaveManager.run_history.duplicate(true)
	var tutorial_completed_backup := SaveManager.tutorial_completed
	var replay_backup := ReplayManager.last_replay.duplicate(true)
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
	for text_key in GameText.EN:
		assert(GameText.KO.has(text_key), "Korean catalog is missing key: %s" % text_key)
	SaveManager.settings.language = "ko"
	assert(GameText.text("start_game") == "게임 시작", "Korean text catalog did not activate")
	SaveManager.settings.language = original_language
	_show_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Title screen failed")
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
	assert(current_view is CharacterSelect and SaveManager.tutorial_completed, "Training completion did not continue to vector selection")
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
	assert(current_view is CharacterSelect, "Skipping replayed training did not continue to vector selection")
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
	smoke_mode = false
	_on_run_finished(synthetic)
	await get_tree().process_frame
	assert(current_view is ResultsScreen, "Result screen failed")
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
	var sanitized := SaveManager._sanitize_run_entry({"difficulty": "void", "character": 99, "deaths": -4, "barriers_used": 9999})
	assert(sanitized.difficulty == "normal" and int(sanitized.character) == 2, "Malformed archive entry profile was not sanitized")
	assert(int(sanitized.deaths) == 0 and int(sanitized.barriers_used) == 999, "Malformed archive metrics were not clamped")
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
	ReplayManager.last_replay = replay_fixture
	_show_records()
	await get_tree().process_frame
	archive = current_view as RecordsScreen
	assert(not archive.replay_button.disabled, "Combat archive did not enable the last-run replay")
	var profile_character_before_replay := SaveManager.selected_character
	archive._watch_replay()
	assert(current_view is StageController and (current_view as StageController).replay_mode, "Replay did not launch from the combat archive")
	var replay_stage := current_view as StageController
	replay_stage.set_process(false)
	for frame in 360:
		replay_stage._process(0.0)
	assert(replay_stage.run_seed == 24681357 and replay_stage.difficulty_id == "normal", "Replay lost its seed or difficulty")
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
	_start_last_replay()
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
	ReplayManager.last_replay = replay_backup
	SaveManager.run_history.assign(run_history_backup)
	print("UI_FLOW_SMOKE_OK title=ok training=ok help=ok options=ok assists=ok bindings=ok gamepad=ok hotplug=ok practice=ok select=ok stage=ok pause=ok restart=ok quit_title=ok results=ok retry=ok game_over=ok archive=ok telemetry=ok save_recovery=ok replay=ok")
	_schedule_test_shutdown()

func _verify_save_recovery() -> void:
	var primary_path := "res://tests/save_recovery_primary.testcfg"
	var backup_path := "res://tests/save_recovery_backup.testcfg"
	var staging_path := "res://tests/save_recovery_pending.testcfg"
	for path in [primary_path, backup_path, staging_path]:
		SaveManager._remove_file(path)
	var version_seven := SaveManager._create_save_config()
	version_seven.set_value("meta", "version", 7)
	SaveManager._seal_config(version_seven)
	assert(SaveManager._config_is_valid(version_seven), "Version 7 signed save compatibility failed")
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

func _verify_replay_storage() -> void:
	var primary_path := "res://tests/replay_primary.testjson"
	var backup_path := "res://tests/replay_backup.testjson"
	var staging_path := "res://tests/replay_pending.testjson"
	for path in [primary_path, backup_path, staging_path]:
		ReplayManager._remove_file(path)
	var frames: Array[int] = [16667, 0, 0, ReplayManager.MASK_PRIMARY, 16667, 12000, -5000, ReplayManager.MASK_FOCUS | ReplayManager.MASK_BARRIER]
	var first_result := {
		"cleared": true, "total_score": 123456, "deaths": 1, "barriers_used": 2,
		"clear_time": 12.345, "boss_phase_metrics": [{}, {}]
	}
	var first := ReplayManager.build_replay(0, "normal", false, 13579, frames, first_result)
	assert(not first.is_empty() and not String(first.get("checksum", "")).is_empty(), "Replay build or checksum failed")
	assert(ReplayManager.matches_expected(first_result, first), "Replay result verification rejected a matching run")
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

func _run_smoke_combat() -> void:
	_start_stage(0, false, 0, "normal")
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.player.debug_invincible = true
	stage.player.locked = false
	for sheet_path in [
		"res://assets/characters/kira_voss_combat_sheet.png",
		"res://assets/characters/dae_ryu_combat_sheet.png",
		"res://assets/characters/mina_zero_combat_sheet.png",
		"res://assets/enemies/neon_drone_combat_sheet.png",
		"res://assets/enemies/psychic_trooper_combat_sheet.png",
		"res://assets/enemies/assault_mech_combat_sheet.png",
		"res://assets/enemies/vector_gunship_combat_sheet.png"
	]:
		var sheet := load(sheet_path) as Texture2D
		assert(sheet != null and sheet.get_width() >= 1000 and sheet.get_height() >= 1000, "Combat animation sheet is missing or undersized: %s" % sheet_path)
	assert(stage.player.combat_sheet != null, "Authored player combat animation sheet did not load")
	assert(stage.enemy_manager.enemy_animation.size() == 4, "Authored enemy combat animation sheets did not load")
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
	print("COMBAT_SMOKE_OK grades=ok player_animation=ok enemy_animation=ok kills=%d graze=%d barrier=ok auto_barrier=ok erase_fx=ok replay_record=ok score=%d" % [ScoreManager.enemies_destroyed, ScoreManager.graze, ScoreManager.score])
	_schedule_test_shutdown()

func _verify_enemy_grade_balance(stage: StageController) -> void:
	assert(is_equal_approx(StageController.TIMELINE.boss_spawn_time, 180.0), "Final boss must spawn at three minutes")
	stage.play_time = 90.0
	stage.difficulty_id = "story"
	var story_threat := stage._difficulty()
	stage.difficulty_id = "normal"
	var normal_threat := stage._difficulty()
	stage.difficulty_id = "expert"
	var expert_threat := stage._difficulty()
	assert(story_threat < normal_threat and normal_threat < expert_threat, "Difficulty threat scaling is not ordered")
	assert(is_equal_approx(normal_threat, lerpf(0.88, 1.16, 0.5)), "Normal mode no longer preserves the original balance curve")
	stage.difficulty_id = "normal"
	stage.background.set_route_context(90.0, "midboss", 0)
	assert(is_equal_approx(stage.background.route_progress, 0.5) and stage.background.encounter_state == "midboss", "Midboss environment state is invalid")
	stage.background.set_route_context(180.0, "final", 4)
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
	midboss_probe.setup("arbiter", stage.bullet_manager)
	midboss_probe.entering = false
	var boss_signatures := {}
	for phase_data in midboss_probe.phases:
		assert(not phase_data.signature_id.is_empty() and not phase_data.attack_sequence.is_empty(), "Midboss phase choreography is incomplete")
		boss_signatures[phase_data.signature_id] = true
	midboss_probe.update_boss(60.0, stage.player.position, 1.0)
	assert(midboss_probe.current_phase == 0 and not midboss_probe.dying, "Midboss must not advance or die when time expires")
	midboss_probe.free()
	var final_probe := BossController.new()
	final_probe.setup("seraph", stage.bullet_manager)
	final_probe.entering = false
	for phase_data in final_probe.phases:
		assert(not phase_data.signature_id.is_empty() and not phase_data.attack_sequence.is_empty(), "Final-boss phase choreography is incomplete")
		boss_signatures[phase_data.signature_id] = true
	assert(boss_signatures.size() == 8, "Every boss phase must have a unique signature")
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
	stage.play_time = 20.0
	var early := stage._wave_composition()
	assert(early.size() == 5 and early.count("grade_3") == 5, "Early wave grade composition is invalid")
	stage.play_time = 75.0
	var middle := stage._wave_composition()
	assert(middle.size() == 5 and middle.count("grade_3") == 4, "Middle wave must contain four grade-3 enemies")
	assert(middle.count("grade_1") + middle.count("grade_2") == 1, "Middle wave must contain one grade-1/2 enemy")
	stage.play_time = 150.0
	var late := stage._wave_composition()
	assert(late.size() == 5 and late.count("grade_3") == 3, "Late wave must contain three grade-3 enemies")
	assert(late.count("grade_1") == 1 and late.count("grade_2") == 1, "Late wave must contain one grade-1 and one grade-2 enemy")
	var grade_3 := GameDatabase.enemy("grade_3")
	var grade_2 := GameDatabase.enemy("grade_2")
	var grade_1 := GameDatabase.enemy("grade_1")
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

func _capture_boss() -> void:
	_start_stage(1, false, 0, "normal")
	await get_tree().create_timer(0.42, true, false, true).timeout
	var stage := current_view as StageController
	stage.set_process(false)
	stage.player.locked = false
	stage.player.debug_invincible = true
	stage.player.position = Vector2(270, 830)
	stage.play_time = 500.0
	stage.background.time = 500.0
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
	var error := image.save_png("res://tests/boss_capture.png")
	print("BOSS_CAPTURE status=%s size=%s bullets=%d" % [error_string(error), str(image.get_size()), stage.bullet_manager.count()])
	_schedule_test_shutdown()

func _capture_results() -> void:
	var synthetic := {
		"mode": "campaign",
		"difficulty": "expert",
		"assisted": true,
		"replay_available": true,
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
	var screen := RecordsScreen.new()
	screen.setup_preview(_archive_samples(), "normal")
	_replace_view(screen)
	await get_tree().create_timer(0.45, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("res://tests/records_capture.png")
	SaveManager.settings.language = original_language
	print("RECORDS_CAPTURE status=%s size=%s runs=9" % [error_string(error), str(image.get_size())])
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
	_show_practice_select()
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
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := TitleScreen.new()
	screen.start_pressed.connect(_on_start_pressed)
	screen.practice_pressed.connect(_show_practice_select)
	screen.records_pressed.connect(_show_records)
	screen.training_pressed.connect(_show_training)
	_replace_view(screen)

func _on_start_pressed() -> void:
	if SaveManager.tutorial_completed:
		_show_character_select()
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
	_show_character_select()

func _show_records() -> void:
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.TITLE)
	var screen := RecordsScreen.new()
	screen.closed.connect(_show_title)
	screen.replay_requested.connect(_start_last_replay)
	_replace_view(screen)

func _show_character_select(practice: bool = false) -> void:
	GameManager.set_state(GameManager.GameState.CHARACTER_SELECT)
	var screen := CharacterSelect.new()
	screen.practice_mode = practice
	if practice:
		screen.practice_confirmed.connect(_start_practice)
	else:
		screen.campaign_confirmed.connect(_start_campaign)
	screen.cancelled.connect(_show_title)
	_replace_view(screen)

func _show_practice_select() -> void:
	_show_character_select(true)

func _start_practice(index: int, phase_index: int = 0) -> void:
	_start_stage(index, true, phase_index, "normal")

func _start_campaign(index: int, difficulty_id: String) -> void:
	_start_stage(index, false, 0, difficulty_id)

func _start_last_replay() -> void:
	if not ReplayManager.has_replay():
		_show_title()
		call_deferred("_show_transient_notice", GameText.text("replay_unavailable"))
		return
	var data := ReplayManager.last_replay.duplicate(true)
	get_tree().paused = false
	run_mode = "replay"
	practice_start_phase = 0
	active_difficulty = String(data.get("difficulty", "normal"))
	GameManager.start_replay(int(data.get("character", 0)), active_difficulty)
	var stage := StageController.new()
	stage.setup_replay(data)
	stage.run_finished.connect(_on_run_finished)
	stage.pause_requested.connect(_show_pause)
	_replace_view(stage)

func _start_stage(index: int = GameManager.selected_character, practice: bool = false, phase_index: int = 0, next_difficulty: String = "") -> void:
	get_tree().paused = false
	run_mode = "practice" if practice else "campaign"
	practice_start_phase = clampi(phase_index, 0, 4) if practice else 0
	if practice:
		active_difficulty = "normal"
	elif GameManager.DIFFICULTY_ORDER.has(next_difficulty):
		active_difficulty = next_difficulty
	elif not GameManager.DIFFICULTY_ORDER.has(active_difficulty):
		active_difficulty = "normal"
	GameManager.start_run(index, active_difficulty, not practice)
	var stage := StageController.new()
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
		_start_last_replay()
	else:
		_start_stage(GameManager.selected_character, run_mode == "practice", practice_start_phase, active_difficulty)

func _quit_to_title() -> void:
	_resume()
	_show_title()

func _on_run_finished(result: Dictionary) -> void:
	if smoke_mode:
		Engine.time_scale = 1.0
		assert((result.get("boss_phase_metrics", []) as Array).size() == 8, "Full run must record all eight boss phases")
		assert(float(result.get("clear_time", 0.0)) >= float(result.get("route_time", 0.0)), "Session time must include the midboss gate")
		print("ACCEPTANCE_SMOKE_OK total_score=%d clear_time=%.2f cleared=%s boss_phases=%d" % [int(result.get("total_score",0)), float(result.get("clear_time",0.0)), str(result.get("cleared",false)), (result.get("boss_phase_metrics", []) as Array).size()])
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
	if result_mode == "campaign" and current_view is StageController:
		var replay := (current_view as StageController).build_replay_payload(result)
		result["replay_available"] = not replay.is_empty() and ReplayManager.save_replay(replay)
	var ranked_run := result_mode == "campaign" and not bool(result.get("assisted", false))
	GameManager.finish_run(result, ranked_run)
	var screen := ResultsScreen.new()
	screen.setup(result)
	screen.retry_pressed.connect(_retry_run)
	screen.replay_pressed.connect(_start_last_replay)
	screen.title_pressed.connect(_show_title)
	_replace_view(screen)
