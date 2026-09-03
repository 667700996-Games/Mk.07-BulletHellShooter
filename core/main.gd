extends Node

var current_view: Node
var pause_menu: PauseMenu
var smoke_mode := false
var transition_layer: CanvasLayer
var transition_rect: ColorRect
var run_mode := "campaign"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_transition()
	GameManager.selected_character = SaveManager.selected_character
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
	elif args.has("--capture-stage"):
		call_deferred("_capture_stage")
	elif args.has("--capture-boss"):
		call_deferred("_capture_boss")
	elif args.has("--capture-results"):
		call_deferred("_capture_results")
	elif args.has("--capture-localization"):
		call_deferred("_capture_localization")
	else:
		_show_title()

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

func _run_smoke_stage() -> void:
	_start_stage(0)
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
	SaveManager.settings.master = 4.0
	SaveManager.settings.bullet_contrast = -2.0
	SaveManager.settings.language = "invalid"
	SaveManager._sanitize_settings()
	assert(is_equal_approx(float(SaveManager.settings.master), 1.0), "Master volume setting was not clamped")
	assert(is_zero_approx(float(SaveManager.settings.bullet_contrast)), "Bullet contrast setting was not clamped")
	assert(SaveManager.settings.language == "en", "Invalid locale was not migrated")
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
	var title := current_view as TitleScreen
	title._show_help()
	await get_tree().process_frame
	assert(title.help_panel != null and title.help_panel.visible, "How-to-play panel failed")
	title._close_help()
	await get_tree().process_frame
	title._show_options()
	await get_tree().process_frame
	assert(title.options_panel != null and title.options_panel.visible, "Options panel failed")
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
	title._close_bindings()
	await get_tree().process_frame
	assert(title.options_panel.visible, "Options panel did not return from key bindings")
	title._close_options()
	await get_tree().process_frame
	_show_practice_select()
	await get_tree().process_frame
	assert(current_view is CharacterSelect and (current_view as CharacterSelect).practice_mode, "Boss-practice character selection failed")
	_start_practice(1)
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).practice_mode, "Boss-practice stage failed to start")
	var practice_stage := current_view as StageController
	assert(practice_stage.boss != null and practice_stage.boss.is_final and practice_stage.final_spawned, "Boss practice did not spawn the final boss")
	_show_pause()
	await get_tree().process_frame
	_restart_stage()
	await get_tree().process_frame
	assert(current_view is StageController and (current_view as StageController).practice_mode, "Boss-practice restart lost its run mode")
	_show_title()
	await get_tree().process_frame
	_show_character_select()
	await get_tree().process_frame
	assert(current_view is CharacterSelect, "Character selection failed")
	_start_stage(2)
	await get_tree().process_frame
	assert(current_view is StageController, "Stage failed to start")
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
	_show_pause()
	await get_tree().process_frame
	_quit_to_title()
	await get_tree().process_frame
	assert(current_view is TitleScreen, "Quit-to-title failed")
	_show_character_select()
	await get_tree().process_frame
	_start_stage(2)
	await get_tree().process_frame
	assert(current_view is StageController, "Stage did not restart after title return")
	var synthetic := ScoreManager.result(12.5, false)
	smoke_mode = false
	_on_run_finished(synthetic)
	await get_tree().process_frame
	assert(current_view is ResultsScreen, "Result screen failed")
	_start_stage(2)
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
	print("UI_FLOW_SMOKE_OK title=ok help=ok options=ok bindings=ok practice=ok select=ok stage=ok pause=ok restart=ok quit_title=ok results=ok retry=ok game_over=ok")
	_schedule_test_shutdown()

func _run_smoke_combat() -> void:
	_start_stage(0)
	await get_tree().process_frame
	var stage := current_view as StageController
	stage.player.debug_invincible = true
	stage.player.locked = false
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
	print("COMBAT_SMOKE_OK grades=ok kills=%d graze=%d barrier=ok erase_fx=ok score=%d" % [ScoreManager.enemies_destroyed, ScoreManager.graze, ScoreManager.score])
	_schedule_test_shutdown()

func _verify_enemy_grade_balance(stage: StageController) -> void:
	assert(is_equal_approx(StageController.TIMELINE.boss_spawn_time, 180.0), "Final boss must spawn at three minutes")
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
	_start_stage(0)
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
	_start_stage(0)
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
	_start_stage(0)
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

func _capture_boss() -> void:
	_start_stage(1)
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
		"cleared": true,
		"score": 3248750,
		"enemies_destroyed": 327,
		"graze": 1864,
		"max_combo": 146,
		"deaths": 1,
		"clear_time": 604.82,
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
	print("LOCALIZATION_CAPTURE options=%s bindings=%s help=%s size=%s" % [error_string(options_error), error_string(bindings_error), error_string(help_error), str(help_image.get_size())])
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
	screen.start_pressed.connect(_show_character_select)
	screen.practice_pressed.connect(_show_practice_select)
	_replace_view(screen)

func _show_character_select(practice: bool = false) -> void:
	GameManager.set_state(GameManager.GameState.CHARACTER_SELECT)
	var screen := CharacterSelect.new()
	screen.practice_mode = practice
	if practice:
		screen.character_confirmed.connect(_start_practice)
	else:
		screen.character_confirmed.connect(_start_stage)
	screen.cancelled.connect(_show_title)
	_replace_view(screen)

func _show_practice_select() -> void:
	_show_character_select(true)

func _start_practice(index: int) -> void:
	_start_stage(index, true)

func _start_stage(index: int = GameManager.selected_character, practice: bool = false) -> void:
	get_tree().paused = false
	run_mode = "practice" if practice else "campaign"
	GameManager.start_run(index)
	var stage := StageController.new()
	stage.practice_mode = practice
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
	_start_stage(GameManager.selected_character, run_mode == "practice")

func _quit_to_title() -> void:
	_resume()
	_show_title()

func _on_run_finished(result: Dictionary) -> void:
	if smoke_mode:
		Engine.time_scale = 1.0
		assert((result.get("boss_phase_metrics", []) as Array).size() == 8, "Full run must record all eight boss phases")
		print("ACCEPTANCE_SMOKE_OK total_score=%d clear_time=%.2f cleared=%s boss_phases=%d" % [int(result.get("total_score",0)), float(result.get("clear_time",0.0)), str(result.get("cleared",false)), (result.get("boss_phase_metrics", []) as Array).size()])
		_schedule_test_shutdown()
		return
	if bool(result.get("restart",false)):
		_start_stage(GameManager.selected_character)
		return
	GameManager.finish_run(result, run_mode == "campaign")
	var screen := ResultsScreen.new()
	screen.setup(result)
	screen.retry_pressed.connect(func(): _start_stage(GameManager.selected_character, run_mode == "practice"))
	screen.title_pressed.connect(_show_title)
	_replace_view(screen)
