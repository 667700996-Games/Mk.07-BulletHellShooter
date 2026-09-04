class_name BossController
extends Node2D

const POSE_IDLE := 0
const POSE_TELEGRAPH := 1
const POSE_ATTACK := 2
const POSE_OVERDRIVE := 3
const BOSS_CATALOG := {
	"arbiter": preload("res://resources/arbiter_03_boss.tres"),
	"seraph": preload("res://resources/seraph_executor_boss.tres"),
	"ion_warden": preload("res://resources/tempest_ion_warden_boss.tres"),
	"void_archon": preload("res://resources/tempest_void_archon_boss.tres"),
	"crown_harvester": preload("res://resources/forge_crown_harvester_boss.tres"),
	"aurelion_zero": preload("res://resources/forge_aurelion_zero_boss.tres")
}

signal phase_changed(phase: int, phase_name: String)
signal phase_overdrive(phase: int, phase_name: String)
signal phase_cleared(boss_id: String, phase: int, phase_name: String, clear_time: float, entered_overdrive: bool)
signal defeated(is_final: bool)

var boss_id := ""
var display_name := ""
var is_final := false
var definition: BossDefinitionData
var phases: Array[BossPhaseData] = []
var current_phase := 0
var starting_phase := 0
var hp := 1.0
var max_hp := 1.0
var target_position := Vector2(270, 220)
var age := 0.0
var phase_time := 0.0
var fire_timer := 1.0
var pattern_cursor := 0
var pattern_deck: Array[String] = []
var last_pattern_id := ""
var sequence_cursor := 0
var sequence_offset := 0
var sequence_direction := 1
var pending_pattern_id := ""
var pending_target := Vector2.ZERO
var pending_rotation := 0.0
var telegraph_timer := 0.0
var telegraph_duration := 0.0
var pattern_rotation := 0.0
var overdrive := false
var phase_intro_timer := 0.0
var phase_intro_duration := 0.0
var entering := true
var dying := false
var death_time := 0.0
var flash := 0.0
var recoil := 0.0
var radius := 58.0
var art_size := Vector2(208.0, 208.0)
var fallback_rect := Rect2(-104.0, -90.0, 208.0, 208.0)
var bank_amount := 0.018
var death_duration := 2.1
var bullet_manager: BulletManager
var player_position := Vector2(270, 820)
var boss_texture: Texture2D
var boss_animation: Texture2D
var signature_registry := BossSignatureRegistry.new()
var pose_frame := POSE_IDLE
var previous_pose_frame := POSE_IDLE
var pose_blend := 1.0
var rng := RandomNumberGenerator.new()

static func supports_boss_id(id: String) -> bool:
	return BOSS_CATALOG.has(id)

static func definition_for_id(id: String) -> BossDefinitionData:
	if not BOSS_CATALOG.has(id):
		return null
	return BOSS_CATALOG[id] as BossDefinitionData

static func supports_signature_id(id: String) -> bool:
	return BossSignatureRegistry.supports_builtin(id)

func set_signature_registry(registry: BossSignatureRegistry) -> void:
	if registry != null:
		signature_registry = registry

func setup(id: String, manager: BulletManager, start_phase: int = 0, seed_value: int = 0) -> void:
	if seed_value > 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	boss_id = id
	bullet_manager = manager
	definition = definition_for_id(id)
	if definition == null:
		_fail_setup("Unknown boss ID: %s" % id)
		return
	var definition_errors := definition.validation_errors()
	for phase_index in definition.phases.size():
		var authored_phase := definition.phases[phase_index]
		if authored_phase != null and not signature_registry.supports(authored_phase.signature_id):
			definition_errors.append("phases[%d] has an unregistered signature ID: %s" % [phase_index, authored_phase.signature_id])
	if not definition_errors.is_empty():
		_fail_setup("Invalid boss definition '%s': %s" % [id, "; ".join(definition_errors)])
		return
	position = Vector2(270, -100)
	is_final = definition.is_final
	display_name = GameText.text(definition.display_name_key)
	boss_texture = definition.key_art
	boss_animation = definition.combat_art
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	radius = definition.radius
	art_size = definition.art_size
	fallback_rect = definition.fallback_rect
	bank_amount = definition.bank_amount
	death_duration = definition.death_duration
	phases = _make_runtime_phases(definition.phases)
	starting_phase = clampi(start_phase, 0, phases.size() - 1)
	current_phase = starting_phase
	_set_animation_pose(POSE_IDLE, 1.0)
	_start_phase()
	queue_redraw()

func _fail_setup(message: String) -> void:
	push_error(message)
	definition = null
	display_name = boss_id
	is_final = false
	phases.clear()
	entering = false
	dying = false
	visible = false
	set_process(false)
	set_physics_process(false)

func _make_runtime_phases(authored_phases: Array[BossPhaseData]) -> Array[BossPhaseData]:
	var runtime_phases: Array[BossPhaseData] = []
	for authored_phase in authored_phases:
		var phase := authored_phase.duplicate(true) as BossPhaseData
		phase.name = GameText.text(phase.name_key) if not phase.name_key.is_empty() else phase.name
		phase.hp *= GameDatabase.global_balance("boss_hp_scale")
		phase.duration *= GameDatabase.global_balance("boss_phase_duration_scale")
		runtime_phases.append(phase)
	return runtime_phases

func update_boss(delta: float, target: Vector2, difficulty: float = 1.0) -> void:
	if definition == null or phases.is_empty():
		return
	player_position = target
	age += delta
	flash = maxf(0.0, flash - delta * 8.0)
	recoil = maxf(0.0, recoil - delta * 5.5)
	if dying:
		death_time += delta
		position += Vector2(sin(death_time * 21.0) * 0.9, -delta * 9.0)
		_update_animation(delta)
		queue_redraw()
		if death_time >= death_duration:
			defeated.emit(is_final)
			queue_free()
		return
	if entering:
		position = position.lerp(target_position, 1.0 - exp(-delta * 2.9))
		if position.distance_to(target_position) < 3.0:
			entering = false
			position = target_position
			phase_intro_duration = phases[current_phase].transition_time
			phase_intro_timer = phase_intro_duration
			_play_phase_cue()
			phase_changed.emit(current_phase + 1, phases[current_phase].name)
		_update_animation(delta)
		queue_redraw()
		return
	if phase_intro_timer > 0.0:
		phase_intro_timer = maxf(0.0, phase_intro_timer - delta)
		pattern_rotation += delta * (1.6 + current_phase * 0.2)
		_update_movement(delta * 0.35)
		_update_animation(delta)
		queue_redraw()
		return
	phase_time += delta
	pattern_rotation += delta * (0.62 + current_phase * 0.18)
	_update_movement(delta)
	if telegraph_timer > 0.0:
		telegraph_timer -= delta
		if telegraph_timer <= 0.0:
			_release_attack(difficulty)
			fire_timer = phases[current_phase].fire_interval / (clampf(difficulty, 0.65, 1.35) * _pressure_multiplier())
	else:
		fire_timer -= delta
		if fire_timer <= 0.0:
			_begin_attack()
	# Phase duration is a par time, not an automatic clear condition. Once the
	# player exceeds it, the pattern accelerates until that phase's HP is gone.
	if not overdrive and phase_time >= phases[current_phase].duration:
		overdrive = true
		fire_timer = minf(fire_timer, 0.24)
		phase_overdrive.emit(current_phase + 1, phases[current_phase].name)
	_update_animation(delta)
	queue_redraw()

func _update_animation(delta: float) -> void:
	var desired_pose := POSE_IDLE
	if dying:
		desired_pose = POSE_OVERDRIVE
	elif recoil > 0.08:
		desired_pose = POSE_ATTACK
	elif telegraph_timer > 0.0 or phase_intro_timer > 0.0:
		desired_pose = POSE_TELEGRAPH
	elif overdrive or hp / maxf(1.0, max_hp) < 0.38:
		desired_pose = POSE_OVERDRIVE
	_set_animation_pose(desired_pose, delta)

func _set_animation_pose(next_pose: int, delta: float) -> void:
	if next_pose != pose_frame:
		previous_pose_frame = pose_frame
		pose_frame = next_pose
		pose_blend = 0.0
	else:
		pose_blend = minf(1.0, pose_blend + delta * 8.0)

func damage(amount: float) -> bool:
	if entering or dying or phase_intro_timer > 0.0:
		return false
	hp -= amount
	flash = 1.0
	if hp <= 0.0:
		_advance_phase(true)
		return true
	return false

func barrier_damage(amount: float) -> void:
	damage(amount)

func health_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)

func total_remaining_hp() -> float:
	if dying:
		return 0.0
	var total := maxf(0.0, hp)
	for i in range(current_phase + 1, phases.size()):
		total += phases[i].hp
	return total

func total_max_hp() -> float:
	var total := 0.0
	for i in range(starting_phase, phases.size()):
		total += phases[i].hp
	return total

func _start_phase() -> void:
	var data := phases[current_phase]
	max_hp = data.hp
	hp = max_hp
	phase_time = 0.0
	fire_timer = 1.05
	pattern_cursor = 0
	pattern_deck.clear()
	last_pattern_id = ""
	sequence_cursor = 0
	sequence_offset = rng.randi_range(0, maxi(0, data.attack_sequence.size() - 1)) if not data.attack_sequence.is_empty() else 0
	sequence_direction = -1 if rng.randi() % 2 else 1
	pending_pattern_id = ""
	telegraph_timer = 0.0
	telegraph_duration = 0.0
	overdrive = false
	phase_intro_duration = data.transition_time
	phase_intro_timer = 0.0 if entering else phase_intro_duration

func _advance_phase(killed: bool) -> void:
	if dying:
		return
	var data := phases[current_phase]
	if killed:
		ScoreManager.add_boss_bonus(data.bonus)
		phase_cleared.emit(boss_id, current_phase + 1, data.name, phase_time, overdrive)
	if bullet_manager:
		bullet_manager.clear_all(true)
	AudioManager.play_sfx("phase", 0.92 + current_phase * 0.07, -2.0)
	EffectManager.shake(4)
	EffectManager.flash(data.accent, 0.56)
	EffectManager.hit_stop(0.045)
	current_phase += 1
	if current_phase >= phases.size():
		dying = true
		death_time = 0.0
		AudioManager.play_sfx("boss_die", 1.0, 1.5)
		EffectManager.shake(5)
		return
	_start_phase()
	_play_phase_cue()
	phase_changed.emit(current_phase + 1, phases[current_phase].name)

func _play_phase_cue() -> void:
	var signature := phases[current_phase].signature_id
	AudioManager.play_sfx("phase_%s" % signature, 1.0, -1.0)

func _update_movement(delta: float) -> void:
	var data := phases[current_phase]
	match data.movement_id:
		"wide":
			position.x = 270.0 + sin(age * 0.72) * 178.0
			position.y = 200.0 + sin(age * 1.17) * 42.0
		"cross":
			position.x = 270.0 + sin(age * 1.05) * 145.0
			position.y = 190.0 + cos(age * 0.63) * 75.0
		"aggressive":
			position.x = 270.0 + sin(age * 1.35) * 190.0
			position.y = 210.0 + sin(age * 1.9) * 52.0
		_:
			position.x = 270.0 + sin(age * 0.65) * 105.0
			position.y = 205.0 + sin(age * 0.84) * 25.0

func _begin_attack() -> void:
	var phase := phases[current_phase]
	# The shuffled deck keeps the boss volatile while preventing unreadable
	# streaks caused by the same attack being selected several times in a row.
	pending_pattern_id = _next_pattern_id(phase)
	pending_target = player_position
	pending_rotation = rng.randf_range(0.0, TAU) + pattern_rotation
	telegraph_duration = phase.telegraph_time * (0.68 if overdrive else 1.0)
	telegraph_timer = telegraph_duration
	AudioManager.play_sfx("telegraph", 0.94 + current_phase * 0.035, -8.0)

func _release_attack(difficulty: float) -> void:
	if pending_pattern_id.is_empty():
		return
	var id := pending_pattern_id
	pending_pattern_id = ""
	recoil = 1.0
	pattern_cursor += 1
	var pattern := GameDatabase.pattern(id)
	PatternEmitter.emit(bullet_manager, position, pending_target, pattern, pending_rotation, minf(1.30, difficulty))
	signature_registry.emit_support(phases[current_phase].signature_id, {
		"bullet_manager": bullet_manager,
		"origin": position,
		"target": pending_target,
		"primary_id": id,
		"cursor": pattern_cursor,
		"rotation": pending_rotation,
		"difficulty": difficulty,
		"accent": phases[current_phase].accent
	})
	AudioManager.play_sfx("enemy_shot", 0.72 + current_phase * 0.08, -10.0)

func _next_pattern_id(phase: BossPhaseData) -> String:
	if not phase.attack_sequence.is_empty():
		var candidate := ""
		for attempt in phase.attack_sequence.size():
			var index := posmod(sequence_offset + sequence_cursor * sequence_direction, phase.attack_sequence.size())
			candidate = phase.attack_sequence[index]
			sequence_cursor += 1
			if sequence_cursor % phase.attack_sequence.size() == 0:
				sequence_offset = rng.randi_range(0, phase.attack_sequence.size() - 1)
				sequence_direction = -1 if rng.randi() % 2 else 1
			if candidate != last_pattern_id or phase.attack_sequence.size() == 1:
				break
		last_pattern_id = candidate
		return candidate
	var pattern_ids := phase.pattern_ids
	if pattern_deck.is_empty():
		for pattern_id in pattern_ids:
			pattern_deck.append(pattern_id)
		for i in range(pattern_deck.size() - 1, 0, -1):
			var swap_index := rng.randi_range(0, i)
			var swap_value := pattern_deck[i]
			pattern_deck[i] = pattern_deck[swap_index]
			pattern_deck[swap_index] = swap_value
		if pattern_deck.size() > 1 and pattern_deck.back() == last_pattern_id:
			var first_value := pattern_deck[0]
			pattern_deck[0] = pattern_deck.back()
			pattern_deck[pattern_deck.size() - 1] = first_value
	var next_id: String = pattern_deck.pop_back()
	last_pattern_id = next_id
	return next_id

func _pressure_multiplier() -> float:
	if not overdrive:
		return 1.0
	var overtime := maxf(0.0, phase_time - phases[current_phase].duration)
	return 1.18 + clampf(overtime / 20.0, 0.0, 0.32)

func _draw() -> void:
	var color := phases[current_phase].accent if current_phase < phases.size() else Color("ff334f")
	var p := Vector2.ZERO
	if flash > 0.0:
		color = Color.WHITE
	if dying:
		for i in 8:
			var angle := float(i) / 8.0 * TAU + death_time * (1.0 if i % 2 else -1.0)
			var burst_p := p + Vector2.from_angle(angle) * (18.0 + fmod(death_time * 90.0 + i * 13.0, 75.0))
			draw_circle(burst_p, 5.0 + absf(sin(death_time * 13.0 + i)) * 10.0, Color(color, 0.58))
	# Large psychic aura and rotating machinery.
	draw_circle(p, radius + 31.0, Color(color, 0.11))
	if phase_intro_timer > 0.0:
		_draw_phase_transition(p, color)
	if telegraph_timer > 0.0:
		var charge := 1.0 - clampf(telegraph_timer / maxf(0.001, telegraph_duration), 0.0, 1.0)
		var telegraph_color := Color(color, 0.24 + charge * 0.46)
		draw_circle(p, radius + 18.0 + charge * 17.0, Color(color, 0.07 + charge * 0.10))
		draw_arc(p, radius + 26.0, -PI * 0.5, -PI * 0.5 + TAU * charge, 48, telegraph_color, 3.0)
		var pattern := GameDatabase.pattern(pending_pattern_id)
		if pattern.kind in ["aimed", "spread", "burst", "stream"]:
			var aim_end := (pending_target - position).normalized() * 260.0
			draw_line(p, aim_end, Color(color, 0.10 + charge * 0.25), 1.5)
	for i in 3:
		var ring_radius := radius + 9.0 + i * 12.0
		var start := pattern_rotation * (1.0 if i % 2 else -1.0) + i
		draw_arc(p, ring_radius, start, start + PI * 1.35, 32, Color(color, 0.42 - i*0.08), 2.0)
	if boss_animation or boss_texture:
		var alpha := 0.35 + absf(sin(death_time * 16.0)) * 0.55 if dying else 1.0
		var hover := sin(age * 2.15) * 2.4 - recoil * 4.5
		var bank := sin(age * 0.82) * bank_amount
		var phase_scale := 1.0 + sin(age * 3.0 + current_phase) * 0.012 + recoil * 0.035
		draw_set_transform(Vector2(0.0, hover), bank, Vector2.ONE * phase_scale)
		if boss_animation:
			var prior_alpha := 1.0 - pose_blend
			if prior_alpha > 0.001:
				_draw_animation_frame(previous_pose_frame, art_size, alpha * prior_alpha)
			_draw_animation_frame(pose_frame, art_size, alpha * pose_blend)
		else:
			draw_texture_rect(boss_texture, fallback_rect, false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif is_final:
		draw_circle(p + Vector2(0,-17), 10.0, color)
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-7),p+Vector2(17,26),p+Vector2(7,20),p+Vector2(0,44),p+Vector2(-7,20),p+Vector2(-17,26)]),color.darkened(0.15))
	else:
		var body := PackedVector2Array([p+Vector2(0,-radius),p+Vector2(radius*1.2,-radius*0.15),p+Vector2(radius*0.8,radius*0.75),p+Vector2(0,radius*0.52),p+Vector2(-radius*0.8,radius*0.75),p+Vector2(-radius*1.2,-radius*0.15)])
		draw_colored_polygon(body,color.darkened(0.32))
		for side in [-1.0,1.0]:
			draw_circle(p+Vector2(side*radius*0.72,0),radius*0.23,color)
			draw_line(p+Vector2(side*radius*0.55,5),p+Vector2(side*radius*1.25,radius*0.65),Color(color,0.75),6.0)
		draw_circle(p,radius*0.35,color)
	if current_phase < phases.size() and hp / maxf(1.0, max_hp) < 0.38 and not dying:
		var fracture_alpha := 0.38 + absf(sin(age * 11.0)) * 0.34
		for fracture_index in 5:
			var start := Vector2(-18.0 + fracture_index * 9.0, -26.0 + float(fracture_index % 2) * 10.0)
			draw_line(start, start + Vector2(6.0 - fracture_index * 2.0, 31.0), Color(1.0, 0.5, 0.7, fracture_alpha), 1.5)
	if boss_animation == null:
		draw_circle(p, 4.0, Color.WHITE)

func _draw_animation_frame(frame: int, art_size: Vector2, alpha: float) -> void:
	var cell_size := Vector2(floorf(boss_animation.get_width() * 0.5), floorf(boss_animation.get_height() * 0.5))
	var source := Rect2(Vector2(float(frame % 2), float(frame / 2)) * cell_size, cell_size)
	draw_texture_rect_region(boss_animation, Rect2(-art_size * 0.5, art_size), source, Color(1, 1, 1, alpha))

func _draw_phase_transition(center: Vector2, color: Color) -> void:
	var ratio := 1.0 - clampf(phase_intro_timer / maxf(0.001, phase_intro_duration), 0.0, 1.0)
	var energy := sin(ratio * PI)
	var reach := lerpf(18.0, radius + 82.0, ease(ratio, -1.4))
	draw_circle(center, radius + energy * 24.0, Color(color, energy * 0.13))
	signature_registry.draw_transition(phases[current_phase].signature_id, self, {
		"center": center,
		"color": color,
		"energy": energy,
		"reach": reach,
		"rotation": pattern_rotation,
		"radius": radius,
		"target": pending_target,
		"host_position": position
	})
