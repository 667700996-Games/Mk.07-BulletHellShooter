class_name StageController
extends Node2D

signal run_finished(result: Dictionary)
signal pause_requested

var stage_data: StageData
var timeline: StageTimelineData
var practice_mode := false
var practice_phase := 0
var replay_mode := false
var replay_data: Dictionary = {}
var difficulty_id := "normal"
var assisted_run := false
var run_seed := 0
var replay_stream: Array[int] = []
var replay_cursor := 0
var recording_truncated := false
var background
var bullet_manager: BulletManager
var projectile_manager: PlayerProjectileManager
var enemy_manager: EnemyManager
var hazard_manager: StageHazardManager
var player: PlayerController
var item_manager: ItemManager
var fx: CombatFX
var hud: GameHUD
var radio_comms: RadioCommsOverlay
var risk_route_overlay: RiskRouteOverlay
var hud_layer: CanvasLayer
var overlay: ColorRect
var post_material: ShaderMaterial
var boss: BossController

var play_time := 0.0
var session_time := 0.0
var wave_timer := 0.0
var wave_index := 0
var intro_time := 0.0
var midboss_spawned := false
var midboss_complete := false
var final_warning := false
var final_spawned := false
var ending := false
var run_cleared := false
var finish_timer := 0.0
var frozen_time := 0.0
var shake_time := 0.0
var shake_strength := 0.0
var flash_alpha := 0.0
var flash_color := Color.WHITE
var hit_sfx_timer := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if stage_data == null:
		setup_stage(StageManager.default_stage())
	if run_seed <= 0:
		run_seed = int(Time.get_ticks_usec() % 2147483000) + 1
	rng.seed = run_seed ^ stage_data.deterministic_seed_salt
	assisted_run = bool(replay_data.get("assisted", false)) if replay_mode else bool(SaveManager.settings.get("auto_barrier", false))
	ScoreManager.configure_route_scoring(not practice_mode)
	_build_scene()
	_connect_signals()
	AudioManager.play_music(stage_data.stage_music_id)
	if practice_mode:
		intro_time = 0.0
		midboss_spawned = true
		midboss_complete = true
		final_warning = true
		StageManager.begin_stage(stage_data)
		StageManager.set_section("boss_practice")
		_spawn_boss(true)
	else:
		StageManager.begin_stage(stage_data)
		hud.announce(GameText.text("replay_mode") if replay_mode else GameText.text(stage_data.title_key), GameText.text("replay_sub") if replay_mode else GameText.text(stage_data.subtitle_key), 3.8)
	get_viewport().set_embedding_subwindows(false)

func setup_stage(data: StageData) -> void:
	stage_data = data if data != null and data.is_valid() else StageManager.default_stage()
	timeline = stage_data.timeline
	intro_time = timeline.intro_lock_time

func setup_replay(data: Dictionary) -> void:
	replay_mode = true
	replay_data = data.duplicate(true)
	difficulty_id = String(replay_data.get("difficulty", "normal"))
	run_seed = int(replay_data.get("seed", 0))
	replay_stream.assign(replay_data.get("frames", []))
	replay_cursor = 0
	var replay_stage := StageManager.stage(String(replay_data.get("stage_id", StageManager.DEFAULT_STAGE_ID)))
	if replay_stage == null:
		replay_stream.clear()
		return
	setup_stage(replay_stage)

func _build_scene() -> void:
	background = stage_data.background_scene.instantiate() if stage_data.background_scene != null else UrbanBackground.new()
	if background.has_method("configure"):
		background.call("configure", stage_data)
	background.z_index = -100
	add_child(background)
	enemy_manager = EnemyManager.new()
	enemy_manager.z_index = 0
	add_child(enemy_manager)
	hazard_manager = StageHazardManager.new()
	hazard_manager.z_index = 1
	add_child(hazard_manager)
	player = PlayerController.new()
	player.z_index = 4
	add_child(player)
	bullet_manager = BulletManager.new()
	bullet_manager.z_index = 3
	add_child(bullet_manager)
	projectile_manager = PlayerProjectileManager.new()
	projectile_manager.z_index = 2
	add_child(projectile_manager)
	item_manager = ItemManager.new()
	item_manager.z_index = 2
	add_child(item_manager)
	fx = CombatFX.new()
	fx.z_index = 6
	add_child(fx)
	enemy_manager.configure(bullet_manager, _derived_seed(0x41524249))
	hazard_manager.configure(stage_data.hazard_events, _derived_seed(0x48415A44))
	player.configure(GameManager.character(), projectile_manager)
	var difficulty_data := GameManager.difficulty(difficulty_id)
	player.lives = int(difficulty_data.get("starting_lives", 3))
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	var post_rect := ColorRect.new()
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_material = ShaderMaterial.new()
	post_material.shader = stage_data.post_shader
	post_rect.material = post_material
	post_layer.add_child(post_rect)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)
	hud = GameHUD.new()
	hud.set_player_color(GameManager.character().primary_color)
	hud.set_run_context(difficulty_id, not practice_mode and not replay_mode and not assisted_run, "replay" if replay_mode else ("practice" if practice_mode else "campaign"), stage_data.stage_id)
	hud_layer.add_child(hud)
	overlay = ColorRect.new()
	overlay.color = Color(1,1,1,0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(overlay)
	radio_comms = RadioCommsOverlay.new()
	radio_comms.setup(stage_data.radio_events)
	hud_layer.add_child(radio_comms)
	risk_route_overlay = RiskRouteOverlay.new()
	risk_route_overlay.setup(not practice_mode)
	hud_layer.add_child(risk_route_overlay)
	radio_comms.move_to_front()
	hud.move_to_front()
	risk_route_overlay.move_to_front()

func _connect_signals() -> void:
	bullet_manager.graze_registered.connect(_on_graze)
	enemy_manager.enemy_destroyed.connect(_on_enemy_destroyed)
	enemy_manager.power_item_requested.connect(item_manager.spawn_power)
	enemy_manager.contact_hit.connect(_damage_player)
	item_manager.power_collected.connect(_on_power_collected)
	player.barrier_activated.connect(_on_barrier)
	EffectManager.shake_requested.connect(_on_shake)
	EffectManager.flash_requested.connect(_on_flash)
	EffectManager.freeze_requested.connect(_on_freeze)
	hazard_manager.hazard_warning.connect(_on_hazard_warning)

func _process(delta: float) -> void:
	var controls: Dictionary
	if replay_mode:
		controls = _next_replay_controls()
		if controls.is_empty():
			_abort_replay()
			return
		delta = float(controls.delta)
	else:
		controls = _capture_live_controls()
		if not practice_mode:
			delta = _record_replay_frame(delta, controls)
	_update_presentation(delta)
	# Session time measures active play, including the untimed midboss gate and
	# hit-stop, while pausing naturally with the scene tree.
	if not ending:
		session_time += delta
	if frozen_time > 0.0:
		frozen_time -= delta
		return
	if ending:
		finish_timer -= delta
		if finish_timer <= 0.0:
			_complete_run(run_cleared)
		return
	_advance_stage_clock(delta)
	if not practice_mode and radio_comms != null:
		var route_paused := boss != null and is_instance_valid(boss) and not boss.is_final
		radio_comms.update_route_time(play_time, route_paused)
	ScoreManager.tick(delta)
	hit_sfx_timer = maxf(0.0, hit_sfx_timer - delta)
	player.locked = play_time < intro_time
	player.update_player(delta, controls)
	if hazard_manager.update_hazards(delta, play_time, player.position, player.is_vulnerable()):
		_damage_player()
	projectile_manager.update_projectiles(delta)
	item_manager.update_items(delta, player.position)
	var difficulty := _difficulty()
	enemy_manager.update_enemies(delta, play_time, player.position, difficulty)
	var got_hit := bullet_manager.update_bullets(delta, player.position, player.is_vulnerable())
	if got_hit:
		_damage_player()
	var hits := enemy_manager.collide_projectiles(projectile_manager)
	if hits > 0:
		_on_attack_hits(hits)
	_update_boss(delta, difficulty)
	_update_timeline(delta)
	hud.set_status(player.lives, player.barriers, player.power)
	if GameManager.debug_enabled and not replay_mode:
		_update_debug_inputs()

func _capture_live_controls() -> Dictionary:
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return {
		"x": movement.x,
		"y": movement.y,
		"primary": Input.is_action_pressed("primary") or bool(SaveManager.settings.get("auto_fire", false)),
		"focus": Input.is_action_pressed("focus"),
		"barrier_pressed": Input.is_action_just_pressed("barrier")
	}

func _record_replay_frame(delta: float, controls: Dictionary) -> float:
	var delta_us := clampi(roundi(delta * 1000000.0), ReplayManager.MIN_DELTA_US, ReplayManager.MAX_DELTA_US)
	var recorded_delta := float(delta_us) / 1000000.0
	if replay_stream.size() / ReplayManager.FRAME_STRIDE >= ReplayManager.MAX_FRAMES:
		recording_truncated = true
		return recorded_delta
	var mask := 0
	if bool(controls.primary):
		mask |= ReplayManager.MASK_PRIMARY
	if bool(controls.focus):
		mask |= ReplayManager.MASK_FOCUS
	if bool(controls.barrier_pressed):
		mask |= ReplayManager.MASK_BARRIER
	replay_stream.append(delta_us)
	replay_stream.append(clampi(roundi(float(controls.x) * ReplayManager.AXIS_SCALE), -ReplayManager.AXIS_SCALE, ReplayManager.AXIS_SCALE))
	replay_stream.append(clampi(roundi(float(controls.y) * ReplayManager.AXIS_SCALE), -ReplayManager.AXIS_SCALE, ReplayManager.AXIS_SCALE))
	replay_stream.append(mask)
	return recorded_delta

func _next_replay_controls() -> Dictionary:
	if replay_cursor + ReplayManager.FRAME_STRIDE > replay_stream.size():
		return {}
	var delta := float(replay_stream[replay_cursor]) / 1000000.0
	var axis_x := float(replay_stream[replay_cursor + 1]) / float(ReplayManager.AXIS_SCALE)
	var axis_y := float(replay_stream[replay_cursor + 2]) / float(ReplayManager.AXIS_SCALE)
	var mask := replay_stream[replay_cursor + 3]
	replay_cursor += ReplayManager.FRAME_STRIDE
	return {
		"delta": delta,
		"x": axis_x,
		"y": axis_y,
		"primary": (mask & ReplayManager.MASK_PRIMARY) != 0,
		"focus": (mask & ReplayManager.MASK_FOCUS) != 0,
		"barrier_pressed": (mask & ReplayManager.MASK_BARRIER) != 0
	}

func build_replay_payload(result: Dictionary) -> Dictionary:
	if practice_mode or replay_mode or recording_truncated or replay_stream.is_empty():
		return {}
	return ReplayManager.build_replay(GameManager.selected_character, difficulty_id, assisted_run, run_seed, replay_stream, result, stage_data.stage_id)

func _abort_replay() -> void:
	set_process(false)
	StageManager.finish(false)
	run_finished.emit({"mode": "replay", "replay_invalid": true, "stage_id": stage_data.stage_id})

func _advance_stage_clock(delta: float) -> void:
	# The route clock represents wave progression. A midboss encounter is an
	# untimed gate: combat continues, but the three-minute route waits here.
	if boss != null and is_instance_valid(boss) and not boss.is_final:
		return
	play_time += delta
	if practice_mode:
		StageManager.update_elapsed(play_time)
	else:
		StageManager.update_time(play_time, midboss_complete)

func _update_timeline(delta: float) -> void:
	if play_time < timeline.wave_start_time:
		return
	if not midboss_spawned and play_time >= timeline.midboss_spawn_time:
		_spawn_boss(false)
		return
	if boss != null:
		return
	if not final_warning and play_time >= timeline.boss_warning_time:
		final_warning = true
		enemy_manager.clear_all(true)
		bullet_manager.clear_all(true)
		hazard_manager.clear_all()
		hud.warning(5.8)
		AudioManager.play_sfx("warning", 1.0, 2.5)
		return
	if final_warning and not final_spawned and play_time >= timeline.boss_spawn_time:
		_spawn_boss(true)
		return
	if final_spawned:
		return
	wave_timer -= delta
	if wave_timer <= 0.0:
		_spawn_wave()
		wave_timer = _wave_interval()

func _spawn_wave() -> void:
	wave_index += 1
	var ids := _wave_composition()
	for i in timeline.enemies_per_wave:
		var id := ids[i]
		var formation := wave_index % 4
		var target_x := 64.0 + fmod(float(i * 83 + wave_index * 41), 412.0)
		var target_y := 130.0 + float((i * 53 + wave_index * 17) % 270)
		var origin := Vector2(target_x, -55.0 - i * 18.0)
		match formation:
			1:
				origin = Vector2(-55.0 if i % 2 == 0 else 595.0, 120.0 + i * 36.0)
			2:
				target_x = 270.0 + (float(i) - float(timeline.enemies_per_wave-1)*0.5) * 42.0
				origin = Vector2(target_x, -65.0 - absf(float(i)-float(timeline.enemies_per_wave)*0.5)*20.0)
			3:
				origin = Vector2(60.0 + i * (420.0 / maxf(1.0,timeline.enemies_per_wave-1)), -70.0 - i%2*70.0)
		enemy_manager.spawn(id, origin, Vector2(target_x, target_y))
	if wave_index % 5 == 0:
		hud.announce(GameText.text("hostile_surge"), GameText.text("chain_window"), 1.1)

func _wave_composition() -> Array[String]:
	var grade_3_count := timeline.late_grade_3_count
	if play_time < timeline.early_wave_end:
		grade_3_count = timeline.early_grade_3_count
	elif play_time < timeline.late_wave_start:
		grade_3_count = timeline.middle_grade_3_count
	var ids: Array[String] = []
	for i in mini(grade_3_count, timeline.enemies_per_wave):
		ids.append(stage_data.grade_3_enemy_id)
	while ids.size() < timeline.enemies_per_wave:
		if play_time < timeline.early_wave_end:
			ids.append(stage_data.grade_3_enemy_id)
		elif play_time < timeline.late_wave_start:
			ids.append(stage_data.grade_2_enemy_id if wave_index % 2 == 0 else stage_data.grade_1_enemy_id)
		else:
			ids.append(stage_data.grade_2_enemy_id if ids.size() % 2 else stage_data.grade_1_enemy_id)
	# Rotate the fixed composition so stronger enemies do not always occupy the
	# same formation slot, while preserving the required grade counts.
	for i in wave_index % timeline.enemies_per_wave:
		ids.push_back(ids.pop_front())
	return ids

func _wave_interval() -> float:
	if play_time < timeline.early_wave_end: return timeline.early_wave_interval
	if play_time < timeline.late_wave_start: return timeline.middle_wave_interval
	return timeline.late_wave_interval

func _spawn_boss(final: bool) -> void:
	if not practice_mode:
		ScoreManager.bank_risk_reserve("final_boss" if final else "midboss")
	enemy_manager.clear_all(true)
	bullet_manager.clear_all(true)
	hazard_manager.clear_all()
	boss = BossController.new()
	boss.z_index = 1
	add_child(boss)
	var starting_phase := practice_phase if practice_mode and final else 0
	var encounter_id := stage_data.final_boss_id if final else stage_data.midboss_id
	boss.setup(encounter_id, bullet_manager, starting_phase, _derived_seed(0x53455241 if final else 0x41524249))
	boss.phase_changed.connect(_on_boss_phase)
	boss.phase_overdrive.connect(_on_boss_overdrive)
	boss.phase_cleared.connect(_on_boss_phase_cleared)
	boss.defeated.connect(_on_boss_defeated)
	if final:
		final_spawned = true
		AudioManager.play_music(stage_data.boss_music_id)
		hud.announce(GameText.text(stage_data.final_boss_name_key), GameText.text(stage_data.final_boss_subtitle_key), 3.4, boss.definition.key_art, true)
	else:
		midboss_spawned = true
		hud.announce(GameText.text(stage_data.midboss_name_key), GameText.text(stage_data.midboss_subtitle_key), 2.8, boss.definition.key_art)
	AudioManager.play_sfx("warning", 0.82 if final else 1.15, 1.0)
	EffectManager.shake(3)

func _update_boss(delta: float, difficulty: float) -> void:
	if boss == null or not is_instance_valid(boss):
		boss = null
		hud.clear_boss()
		return
	boss.update_boss(delta, player.position, difficulty)
	if boss == null or not is_instance_valid(boss):
		hud.clear_boss()
		return
	var boss_name_key := stage_data.final_boss_name_key if boss.is_final else stage_data.midboss_name_key
	hud.set_boss(GameText.text(boss_name_key), boss.total_remaining_hp(), boss.total_max_hp(), mini(boss.current_phase + 1, boss.phases.size()), boss.phases.size())
	for shot_index in range(projectile_manager.positions.size() - 1, -1, -1):
		if shot_index >= projectile_manager.positions.size() or boss == null or boss.dying:
			continue
		var boss_id := boss.get_instance_id()
		if projectile_manager.piercing[shot_index] != 0 and projectile_manager.has_hit_target(shot_index, boss_id):
			continue
		var distance := boss.radius + projectile_manager.radii[shot_index]
		if projectile_manager.positions[shot_index].distance_squared_to(boss.position) <= distance * distance:
			boss.damage(projectile_manager.damages[shot_index] * projectile_manager.boss_damage_scales[shot_index])
			fx.muzzle(projectile_manager.positions[shot_index], GameManager.character().accent)
			if projectile_manager.piercing[shot_index] == 0:
				projectile_manager.remove_at(shot_index)
			else:
				projectile_manager.mark_hit_target(shot_index, boss_id)
			_on_attack_hits(1)
	if boss != null and not boss.entering and not boss.dying and boss.position.distance_squared_to(player.position) < pow(boss.radius + 6.0, 2.0):
		_damage_player()

func _on_boss_phase(phase: int, phase_name: String) -> void:
	hud.announce("%s %02d" % [GameText.text("phase"), phase], phase_name, 1.5)
	fx.shockwave(boss.position, boss.phases[boss.current_phase].accent, 1.2)

func _on_boss_overdrive(phase: int, phase_name: String) -> void:
	hud.announce("%s %02d %s" % [GameText.text("phase"), phase, GameText.text("overdrive")], phase_name, 1.5)
	AudioManager.play_sfx("warning", 1.22, 0.5)
	EffectManager.flash(boss.phases[boss.current_phase].accent, 0.42)
	EffectManager.shake(3)

func _on_boss_phase_cleared(id: String, phase: int, phase_name: String, clear_time: float, entered_overdrive: bool) -> void:
	ScoreManager.register_boss_phase(id, phase, phase_name, clear_time, entered_overdrive)
	if boss != null and is_instance_valid(boss) and phase - 1 < boss.phases.size():
		var phase_data := boss.phases[phase - 1]
		fx.phase_break(boss.position, phase_data.accent, phase_data.signature_id)

func _on_boss_defeated(was_final: bool) -> void:
	var death_position := boss.position if boss != null else Vector2(270,210)
	for i in 12:
		fx.burst(death_position + Vector2.from_angle(float(i)/12.0*TAU)*float(i*6), Color("ffcf62") if i%2 else Color("ff3f87"), 1.2 + i*0.06, 12)
	bullet_manager.clear_all(true)
	hud.clear_boss()
	boss = null
	if was_final:
		ending = true
		run_cleared = true
		finish_timer = 4.4
		hud.announce(GameText.text(stage_data.final_boss_defeat_title_key), GameText.text(stage_data.final_boss_defeat_subtitle_key), 4.0)
		AudioManager.play_music("result")
	else:
		midboss_complete = true
		wave_timer = 1.8
		hud.announce(GameText.text(stage_data.midboss_defeat_title_key), GameText.text(stage_data.midboss_defeat_subtitle_key), 2.4)

func _on_barrier(center: Vector2) -> void:
	ScoreManager.register_barrier()
	var erased := bullet_manager.clear_radius(center, 260.0)
	enemy_manager.damage_radius(center, 260.0, 420.0)
	if boss != null:
		boss.barrier_damage(340.0)
	ScoreManager.add_score(erased * 8)
	fx.shockwave(center, GameManager.character().accent, 2.0)
	fx.burst(center, GameManager.character().primary_color, 1.3, 36)

func _damage_player() -> void:
	if assisted_run and player.is_vulnerable() and player.activate_barrier():
		hud.announce(GameText.text("auto_barrier_trigger"), GameText.text("auto_barrier_sub"), 1.1)
		return
	if player.take_hit():
		bullet_manager.clear_radius(player.position, 230.0)
		fx.burst(player.position, Color("ff335f"), 1.35, 36)
		hud.announce(GameText.text("vector_disrupted"), GameText.text("life_signal") % player.lives, 1.3)
		if player.lives <= 0:
			ending = true
			run_cleared = false
			finish_timer = 2.2

func _on_graze(position: Vector2) -> void:
	ScoreManager.register_graze()
	fx.graze(position)
	if ScoreManager.graze % 3 == 0:
		AudioManager.play_sfx("graze", 0.92 + float(ScoreManager.graze % 8) * 0.025, -12.0)

func _on_enemy_destroyed(position: Vector2, value: int, color: Color, size_class: int) -> void:
	fx.burst(position, color, 0.7 + size_class * 0.32, 10 + size_class * 8)
	fx.floater(position + Vector2(-8,-14), "+%d" % value, color, 0.8 + size_class * 0.12)
	AudioManager.play_sfx("enemy_die", 1.12 - size_class * 0.12, -7.0 + size_class * 2.0)
	EffectManager.shake(2 + mini(size_class, 1))
	if size_class >= 2:
		EffectManager.hit_stop(0.026)

func _on_power_collected(position: Vector2) -> void:
	var changed := player.add_power()
	fx.burst(position, Color("52e9ff"), 0.55, 9)
	fx.floater(position, GameText.text("power_up") if changed else "+500", Color("8ff4ff"), 0.9)
	if not changed:
		ScoreManager.add_score(500)

func _on_attack_hits(hits: int) -> void:
	if hit_sfx_timer <= 0.0:
		AudioManager.play_sfx("hit", 0.92 + rng.randf() * 0.14, -19.0)
		hit_sfx_timer = 0.045
	if hits >= 5:
		EffectManager.shake(1)

func _on_hazard_warning(_hazard_id: String, _kind: String) -> void:
	hud.announce(GameText.text("environment_hazard"), GameText.text("evasive_action"), 1.05)
	AudioManager.play_sfx("warning", 1.18, -7.0)

func _difficulty() -> float:
	if practice_mode:
		return 1.0
	var stage_progress := clampf(play_time / timeline.boss_spawn_time, 0.0, 1.0)
	return lerpf(0.88, 1.16, stage_progress) * float(GameManager.difficulty(difficulty_id).get("threat_scale", 1.0))

func _derived_seed(salt: int) -> int:
	# Preserve the shipped Neon District seed stream so legacy v1 replays stay
	# deterministic. Additional stages fold in their own salt to avoid sharing decks.
	var stage_salt := 0 if stage_data.stage_id == StageManager.DEFAULT_STAGE_ID else stage_data.deterministic_seed_salt
	return maxi(1, (run_seed ^ stage_salt ^ salt) & 0x7fffffff)

func _update_presentation(delta: float) -> void:
	flash_alpha = maxf(0.0, flash_alpha - delta * 2.8)
	overlay.color = Color(flash_color, flash_alpha)
	if post_material:
		post_material.set_shader_parameter("chromatic_amount", 0.00055 + flash_alpha * 0.006)
		var danger := clampf(
			(play_time - timeline.danger_escalation_time)
			/ (timeline.boss_spawn_time - timeline.danger_escalation_time),
			0.0,
			0.72
		)
		if boss != null and is_instance_valid(boss) and boss.is_final:
			danger = maxf(danger, float(boss.current_phase) / 4.0)
		post_material.set_shader_parameter("danger_amount", danger)
	if shake_time > 0.0:
		shake_time -= delta
		var amount := shake_strength * clampf(shake_time * 10.0, 0.0, 1.0)
		position = Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
	else:
		position = position.lerp(Vector2.ZERO, 1.0 - exp(-delta * 22.0))
	if background and background.has_method("set_route_context") and background.has_method("set_escalation"):
		var encounter := "route"
		var encounter_phase := 0
		if boss != null and is_instance_valid(boss):
			encounter = "final" if boss.is_final else "midboss"
			encounter_phase = boss.current_phase
		var environment_route_time := timeline.boss_spawn_time if practice_mode else play_time
		background.call("set_route_context", environment_route_time, encounter, encounter_phase)
		var music_pressure := lerpf(0.30, 0.68, clampf(play_time / timeline.boss_spawn_time, 0.0, 1.0))
		if encounter == "midboss":
			music_pressure = 0.70 + float(encounter_phase) * 0.07
		elif encounter == "final":
			music_pressure = 0.76 + float(encounter_phase) * 0.055
		AudioManager.set_music_intensity(music_pressure)
		background.call("set_escalation", clampf(
			(play_time - timeline.danger_escalation_time)
			/ (timeline.boss_spawn_time - timeline.danger_escalation_time),
			0.0,
			1.0
		))

func _on_shake(level: int) -> void:
	shake_time = 0.07 + level * 0.045
	shake_strength = [0.0, 1.2, 2.4, 4.0, 6.5, 10.0][level] * float(SaveManager.settings.get("shake", 0.85))

func _on_flash(color: Color, strength: float) -> void:
	flash_color = color
	flash_alpha = maxf(flash_alpha, strength * 0.34 * float(SaveManager.settings.get("flash", 0.85)))

func _on_freeze(duration: float) -> void:
	frozen_time = maxf(frozen_time, duration)

func _update_debug_inputs() -> void:
	if Input.is_action_just_pressed("debug_invincible"):
		player.debug_invincible = not player.debug_invincible
		hud.announce("DEBUG INVINCIBLE", "ON" if player.debug_invincible else "OFF", 0.8)
	if Input.is_action_just_pressed("debug_power"):
		player.power = 4
		player.barriers = 3
	if Input.is_action_just_pressed("debug_boss") and not final_spawned:
		play_time = timeline.boss_spawn_time
		midboss_spawned = true
		final_warning = true
		if boss != null:
			boss.queue_free()
			boss = null
	if Input.is_action_just_pressed("debug_clear"):
		bullet_manager.clear_all(true)
	if Input.is_action_just_pressed("debug_restart"):
		_complete_run(false, true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not ending:
		pause_requested.emit()
		get_viewport().set_input_as_handled()

func _complete_run(cleared: bool, restart: bool = false) -> void:
	set_process(false)
	StageManager.finish(cleared)
	if restart:
		run_finished.emit({"restart": true})
	else:
		# Practice runs deliberately do not award operation medals. Replays do:
		# using the same phase-count contract keeps campaign playback deterministic.
		var result := ScoreManager.result(
			session_time,
			cleared,
			stage_data.expected_boss_phase_count,
			not practice_mode
		)
		result["route_time"] = play_time
		result["stage_id"] = stage_data.stage_id
		result["stage_title_key"] = stage_data.title_key
		result["after_action_key"] = stage_data.result_key
		result["mode"] = "replay" if replay_mode else ("practice" if practice_mode else "campaign")
		result["difficulty"] = "normal" if practice_mode else difficulty_id
		result["assisted"] = assisted_run
		if replay_mode:
			result["replay_verified"] = ReplayManager.matches_expected(result, replay_data)
		if practice_mode:
			result["practice_phase"] = practice_phase + 1
		run_finished.emit(result)
