class_name StageController
extends Node2D

signal run_finished(result: Dictionary)
signal pause_requested

const WAVE_START_TIME := 5.0
const EARLY_WAVE_END := 60.0
const MIDBOSS_SPAWN_TIME := 90.0
const LATE_WAVE_START := 135.0
const BOSS_WARNING_TIME := 174.0
const BOSS_SPAWN_TIME := 180.0
const DANGER_ESCALATION_TIME := 120.0
const ENEMIES_PER_WAVE := 5

var background: UrbanBackground
var bullet_manager: BulletManager
var projectile_manager: PlayerProjectileManager
var enemy_manager: EnemyManager
var player: PlayerController
var item_manager: ItemManager
var fx: CombatFX
var hud: GameHUD
var hud_layer: CanvasLayer
var overlay: ColorRect
var post_material: ShaderMaterial
var boss: BossController

var play_time := 0.0
var wave_timer := 0.0
var wave_index := 0
var intro_time := 4.2
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
	rng.seed = 0x4E454F4E
	_build_scene()
	_connect_signals()
	AudioManager.play_music("stage")
	StageManager.begin("neon_district_01")
	hud.announce("NEON DISTRICT", "SECTOR 07 // CONTROL SPINE APPROACH", 3.8)
	get_viewport().set_embedding_subwindows(false)

func _build_scene() -> void:
	background = UrbanBackground.new()
	background.z_index = -100
	add_child(background)
	enemy_manager = EnemyManager.new()
	enemy_manager.z_index = 0
	add_child(enemy_manager)
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
	enemy_manager.configure(bullet_manager)
	player.configure(GameManager.character(), projectile_manager)
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	var post_rect := ColorRect.new()
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	post_material = ShaderMaterial.new()
	post_material.shader = load("res://shaders/urban_post.gdshader") as Shader
	post_rect.material = post_material
	post_layer.add_child(post_rect)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 20
	add_child(hud_layer)
	hud = GameHUD.new()
	hud.set_player_color(GameManager.character().primary_color)
	hud_layer.add_child(hud)
	overlay = ColorRect.new()
	overlay.color = Color(1,1,1,0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(overlay)
	hud.move_to_front()

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

func _process(delta: float) -> void:
	_update_presentation(delta)
	if frozen_time > 0.0:
		frozen_time -= delta
		return
	if ending:
		finish_timer -= delta
		if finish_timer <= 0.0:
			_complete_run(run_cleared)
		return
	play_time += delta
	StageManager.update_time(play_time)
	ScoreManager.tick(delta)
	hit_sfx_timer = maxf(0.0, hit_sfx_timer - delta)
	player.locked = play_time < intro_time
	player.update_player(delta)
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
	if GameManager.debug_enabled:
		_update_debug_inputs()

func _update_timeline(delta: float) -> void:
	if play_time < WAVE_START_TIME:
		return
	if not midboss_spawned and play_time >= MIDBOSS_SPAWN_TIME:
		_spawn_boss(false)
		return
	if boss != null:
		return
	if not final_warning and play_time >= BOSS_WARNING_TIME:
		final_warning = true
		enemy_manager.clear_all(true)
		bullet_manager.clear_all(true)
		hud.warning(5.8)
		AudioManager.play_sfx("warning", 1.0, 2.5)
		return
	if final_warning and not final_spawned and play_time >= BOSS_SPAWN_TIME:
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
	for i in ENEMIES_PER_WAVE:
		var id := ids[i]
		var formation := wave_index % 4
		var target_x := 64.0 + fmod(float(i * 83 + wave_index * 41), 412.0)
		var target_y := 130.0 + float((i * 53 + wave_index * 17) % 270)
		var origin := Vector2(target_x, -55.0 - i * 18.0)
		match formation:
			1:
				origin = Vector2(-55.0 if i % 2 == 0 else 595.0, 120.0 + i * 36.0)
			2:
				target_x = 270.0 + (float(i) - float(ENEMIES_PER_WAVE-1)*0.5) * 42.0
				origin = Vector2(target_x, -65.0 - absf(float(i)-float(ENEMIES_PER_WAVE)*0.5)*20.0)
			3:
				origin = Vector2(60.0 + i * (420.0 / maxf(1.0,ENEMIES_PER_WAVE-1)), -70.0 - i%2*70.0)
		enemy_manager.spawn(id, origin, Vector2(target_x, target_y))
	if wave_index % 5 == 0:
		hud.announce("HOSTILE SURGE", "CHAIN WINDOW EXTENDED", 1.1)

func _wave_composition() -> Array[String]:
	var ids: Array[String] = ["grade_3", "grade_3", "grade_3"]
	if play_time < EARLY_WAVE_END:
		ids.append_array(["grade_3", "grade_3"])
	elif play_time < LATE_WAVE_START:
		ids.append("grade_3")
		ids.append("grade_2" if wave_index % 2 == 0 else "grade_1")
	else:
		ids.append_array(["grade_2", "grade_1"])
	# Rotate the fixed composition so stronger enemies do not always occupy the
	# same formation slot, while preserving the required grade counts.
	for i in wave_index % ENEMIES_PER_WAVE:
		ids.push_back(ids.pop_front())
	return ids

func _wave_interval() -> float:
	if play_time < EARLY_WAVE_END: return 6.4
	if play_time < LATE_WAVE_START: return 5.8
	return 5.2

func _spawn_boss(final: bool) -> void:
	enemy_manager.clear_all(true)
	bullet_manager.clear_all(true)
	boss = BossController.new()
	boss.z_index = 1
	add_child(boss)
	boss.setup("seraph" if final else "arbiter", bullet_manager)
	boss.phase_changed.connect(_on_boss_phase)
	boss.defeated.connect(_on_boss_defeated)
	if final:
		final_spawned = true
		AudioManager.play_music("boss")
		hud.announce("SERAPH EXECUTOR", "PSYCHIC WEAPON // THREAT OMEGA", 3.4)
	else:
		midboss_spawned = true
		hud.announce("ARBITER-03", "AERIAL VERDICT PLATFORM", 2.8)
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
	hud.set_boss(boss.display_name, boss.total_remaining_hp(), boss.total_max_hp(), mini(boss.current_phase + 1, boss.phases.size()), boss.phases.size())
	for shot_index in range(projectile_manager.positions.size() - 1, -1, -1):
		if shot_index >= projectile_manager.positions.size() or boss == null or boss.dying:
			continue
		var distance := boss.radius + projectile_manager.radii[shot_index]
		if projectile_manager.positions[shot_index].distance_squared_to(boss.position) <= distance * distance:
			boss.damage(projectile_manager.damages[shot_index])
			fx.muzzle(projectile_manager.positions[shot_index], GameManager.character().accent)
			if projectile_manager.piercing[shot_index] == 0:
				projectile_manager.remove_at(shot_index)
			_on_attack_hits(1)
	if boss != null and not boss.entering and not boss.dying and boss.position.distance_squared_to(player.position) < pow(boss.radius + 6.0, 2.0):
		_damage_player()

func _on_boss_phase(phase: int, phase_name: String) -> void:
	hud.announce("PHASE %02d" % phase, phase_name, 1.5)
	fx.shockwave(boss.position, boss.phases[boss.current_phase].accent, 1.2)

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
		hud.announce("CONTROL SPINE SEVERED", "CITY LOCKDOWN COLLAPSING", 4.0)
		AudioManager.play_music("result")
	else:
		midboss_complete = true
		wave_timer = 1.8
		hud.announce("ARBITER DOWN", "ADVANCE TO CENTRAL SPINE", 2.4)

func _on_barrier(center: Vector2) -> void:
	var erased := bullet_manager.clear_radius(center, 260.0)
	enemy_manager.damage_radius(center, 260.0, 420.0)
	if boss != null:
		boss.barrier_damage(340.0)
	ScoreManager.add_score(erased * 8)
	fx.shockwave(center, GameManager.character().accent, 2.0)
	fx.burst(center, GameManager.character().primary_color, 1.3, 36)

func _damage_player() -> void:
	if player.take_hit():
		bullet_manager.clear_radius(player.position, 230.0)
		fx.burst(player.position, Color("ff335f"), 1.35, 36)
		hud.announce("VECTOR DISRUPTED", "LIFE SIGNAL %d" % player.lives, 1.3)
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
	fx.floater(position, "POWER UP" if changed else "+500", Color("8ff4ff"), 0.9)
	if not changed:
		ScoreManager.add_score(500)

func _on_attack_hits(hits: int) -> void:
	if hit_sfx_timer <= 0.0:
		AudioManager.play_sfx("hit", 0.92 + rng.randf() * 0.14, -19.0)
		hit_sfx_timer = 0.045
	if hits >= 5:
		EffectManager.shake(1)

func _difficulty() -> float:
	var stage_progress := clampf(play_time / BOSS_SPAWN_TIME, 0.0, 1.0)
	return lerpf(0.88, 1.16, stage_progress)

func _update_presentation(delta: float) -> void:
	flash_alpha = maxf(0.0, flash_alpha - delta * 2.8)
	overlay.color = Color(flash_color, flash_alpha)
	if post_material:
		post_material.set_shader_parameter("chromatic_amount", 0.00055 + flash_alpha * 0.006)
		var danger := clampf((play_time - DANGER_ESCALATION_TIME) / (BOSS_SPAWN_TIME - DANGER_ESCALATION_TIME), 0.0, 0.72)
		if boss != null and is_instance_valid(boss) and boss.is_final:
			danger = maxf(danger, float(boss.current_phase) / 4.0)
		post_material.set_shader_parameter("danger_amount", danger)
	if shake_time > 0.0:
		shake_time -= delta
		var amount := shake_strength * clampf(shake_time * 10.0, 0.0, 1.0)
		position = Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))
	else:
		position = position.lerp(Vector2.ZERO, 1.0 - exp(-delta * 22.0))
	if background:
		background.set_escalation(clampf((play_time - DANGER_ESCALATION_TIME) / (BOSS_SPAWN_TIME - DANGER_ESCALATION_TIME), 0.0, 1.0))

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
		play_time = BOSS_SPAWN_TIME
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
		run_finished.emit(ScoreManager.result(play_time, cleared))
