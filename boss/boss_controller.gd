class_name BossController
extends Node2D

const POSE_IDLE := 0
const POSE_TELEGRAPH := 1
const POSE_ATTACK := 2
const POSE_OVERDRIVE := 3

signal phase_changed(phase: int, phase_name: String)
signal phase_overdrive(phase: int, phase_name: String)
signal phase_cleared(boss_id: String, phase: int, phase_name: String, clear_time: float, entered_overdrive: bool)
signal defeated(is_final: bool)

var boss_id := ""
var display_name := ""
var is_final := false
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
var bullet_manager: BulletManager
var player_position := Vector2(270, 820)
var boss_texture: Texture2D
var boss_animation: Texture2D
var pose_frame := POSE_IDLE
var previous_pose_frame := POSE_IDLE
var pose_blend := 1.0
var rng := RandomNumberGenerator.new()

func setup(id: String, manager: BulletManager, start_phase: int = 0, seed_value: int = 0) -> void:
	if seed_value > 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	boss_id = id
	bullet_manager = manager
	position = Vector2(270, -100)
	is_final = id == "seraph"
	display_name = "SERAPH EXECUTOR" if is_final else "ARBITER-03"
	boss_texture = load("res://assets/bosses/seraph_executor_keyart.png" if is_final else "res://assets/bosses/arbiter_03_keyart.png") as Texture2D
	boss_animation = load("res://assets/bosses/seraph_executor_combat_sheet.png" if is_final else "res://assets/bosses/arbiter_03_combat_sheet.png") as Texture2D
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	radius = 45.0 if is_final else 64.0
	phases = _make_final_phases() if is_final else _make_mid_phases()
	starting_phase = clampi(start_phase, 0, phases.size() - 1)
	current_phase = starting_phase
	_set_animation_pose(POSE_IDLE, 1.0)
	_start_phase()
	queue_redraw()

func update_boss(delta: float, target: Vector2, difficulty: float = 1.0) -> void:
	player_position = target
	age += delta
	flash = maxf(0.0, flash - delta * 8.0)
	recoil = maxf(0.0, recoil - delta * 5.5)
	if dying:
		death_time += delta
		position += Vector2(sin(death_time * 21.0) * 0.9, -delta * 9.0)
		_update_animation(delta)
		queue_redraw()
		if death_time >= (3.1 if is_final else 2.1):
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
	_emit_signature_support(phases[current_phase].signature_id, id, difficulty)
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

func _emit_signature_support(signature: String, primary_id: String, difficulty: float) -> void:
	match signature:
		"perimeter":
			if primary_id == "ring" and pattern_cursor % 2 == 0:
				var echo := GameDatabase.pattern("ring")
				echo.count = 8
				echo.speed *= 0.72
				PatternEmitter.emit(bullet_manager, position, pending_target, echo, pending_rotation + PI / 8.0, minf(1.0, difficulty))
		"rotary":
			if primary_id == "rotating":
				var counter := GameDatabase.pattern("rotating")
				counter.count = 4
				counter.modifier_strength *= -1.0
				PatternEmitter.emit(bullet_manager, position, pending_target, counter, -pending_rotation, minf(1.0, difficulty))
		"arbiter":
			if pattern_cursor % 4 == 0:
				PatternEmitter.emit_aimed_fan(bullet_manager, position, pending_target, 3, 0.24, 168.0, phases[current_phase].accent)
		"sentence":
			if primary_id == "aimed":
				PatternEmitter.emit_aimed_fan(bullet_manager, position, pending_target, 2, 0.16, 188.0, phases[current_phase].accent)
		"halo":
			if primary_id == "ring":
				var inner_halo := GameDatabase.pattern("ring")
				inner_halo.count = 9
				inner_halo.speed *= 1.28
				inner_halo.modifier = "accelerate"
				inner_halo.modifier_strength = 12.0
				PatternEmitter.emit(bullet_manager, position, pending_target, inner_halo, pending_rotation + PI / 9.0, minf(1.0, difficulty))
		"maelstrom":
			if pattern_cursor % 3 == 0:
				var seeker := GameDatabase.pattern("aimed")
				seeker.speed += 34.0
				PatternEmitter.emit(bullet_manager, position, pending_target, seeker, 0.0, 1.0)
		"lattice":
			if primary_id == "geometric":
				var cross_lattice := GameDatabase.pattern("geometric")
				cross_lattice.count = 10
				cross_lattice.speed *= 0.84
				PatternEmitter.emit(bullet_manager, position, pending_target, cross_lattice, pending_rotation + PI / 10.0, minf(1.0, difficulty))
		"last_light":
			if pattern_cursor % 4 == 0:
				PatternEmitter.emit_aimed_fan(bullet_manager, position, pending_target, 3, 0.30, 218.0, phases[current_phase].accent)

func _pressure_multiplier() -> float:
	if not overdrive:
		return 1.0
	var overtime := maxf(0.0, phase_time - phases[current_phase].duration)
	return 1.18 + clampf(overtime / 20.0, 0.0, 0.32)

func _make_mid_phases() -> Array[BossPhaseData]:
	return [
		_phase(GameText.text("boss_phase_perimeter"), 1250, 12.0, ["spread", "ring"], ["spread", "ring", "spread", "ring"], 0.72, 0.44, 0.76, "hover", "perimeter", Color("ff9d45"), 10000),
		_phase(GameText.text("boss_phase_rotary"), 1450, 14.0, ["rotating", "burst"], ["rotating", "burst", "rotating", "burst"], 0.58, 0.38, 0.88, "wide", "rotary", Color("ff4b8b"), 15000),
		_phase(GameText.text("boss_phase_arbiter"), 1750, 16.0, ["layered", "stream", "radial"], ["layered", "stream", "radial", "stream"], 0.48, 0.34, 1.02, "cross", "arbiter", Color("bf5dff"), 22000)
	]

func _make_final_phases() -> Array[BossPhaseData]:
	return [
		_phase(GameText.text("boss_phase_sentence"), 1850, 28.0, ["spread", "aimed", "burst"], ["aimed", "spread", "burst", "aimed", "spread"], 0.66, 0.46, 0.82, "hover", "sentence", Color("ff477e"), 20000),
		_phase(GameText.text("boss_phase_halo"), 2150, 30.0, ["rotating", "ring", "radial"], ["ring", "rotating", "ring", "radial", "rotating"], 0.52, 0.40, 0.94, "wide", "halo", Color("54e7ff"), 30000),
		_phase(GameText.text("boss_phase_maelstrom"), 2450, 32.0, ["spiral", "layered", "aimed"], ["spiral", "layered", "aimed", "spiral", "layered"], 0.43, 0.36, 1.04, "cross", "maelstrom", Color("b45cff"), 45000),
		_phase(GameText.text("boss_phase_lattice"), 2750, 34.0, ["geometric", "rotating", "burst"], ["geometric", "burst", "rotating", "geometric", "burst"], 0.39, 0.34, 1.14, "wide", "lattice", Color("ff5dba"), 60000),
		_phase(GameText.text("boss_phase_last_light"), 3300, 42.0, ["layered", "geometric", "stream", "ring"], ["stream", "layered", "ring", "geometric", "stream", "ring"], 0.31, 0.30, 1.28, "aggressive", "last_light", Color("ff334f"), 100000)
	]

func _phase(title: String, phase_hp: float, duration: float, patterns: Array, sequence: Array, interval: float, telegraph: float, transition: float, movement: String, signature: String, accent: Color, bonus: int) -> BossPhaseData:
	var data := BossPhaseData.new()
	data.name = title
	data.hp = phase_hp * GameDatabase.global_balance("boss_hp_scale")
	data.duration = duration * GameDatabase.global_balance("boss_phase_duration_scale")
	data.pattern_ids = PackedStringArray(patterns)
	data.attack_sequence = PackedStringArray(sequence)
	data.fire_interval = interval
	data.telegraph_time = telegraph
	data.transition_time = transition
	data.movement_id = movement
	data.signature_id = signature
	data.accent = accent
	data.bonus = bonus
	return data

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
		var art_size := Vector2(194.0, 180.0) if is_final else Vector2(312.0, 208.0)
		var hover := sin(age * 2.15) * 2.4 - recoil * 4.5
		var bank := sin(age * 0.82) * (0.026 if is_final else 0.018)
		var phase_scale := 1.0 + sin(age * 3.0 + current_phase) * 0.012 + recoil * 0.035
		draw_set_transform(Vector2(0.0, hover), bank, Vector2.ONE * phase_scale)
		if boss_animation:
			var prior_alpha := 1.0 - pose_blend
			if prior_alpha > 0.001:
				_draw_animation_frame(previous_pose_frame, art_size, alpha * prior_alpha)
			_draw_animation_frame(pose_frame, art_size, alpha * pose_blend)
		else:
			var fallback_rect := Rect2(-54, -74, 108, 162) if is_final else Rect2(-104, -90, 208, 208)
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
	var signature := phases[current_phase].signature_id
	draw_circle(center, radius + energy * 24.0, Color(color, energy * 0.13))
	match signature:
		"perimeter":
			for i in 4:
				var angle := TAU * float(i) / 4.0 + pattern_rotation
				draw_line(center + Vector2.from_angle(angle) * radius, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.82), 3.0)
		"rotary":
			for i in 8:
				var angle := TAU * float(i) / 8.0 + pattern_rotation * 1.8
				draw_line(center + Vector2.from_angle(angle) * 16.0, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.68), 2.0 + float(i % 2))
		"arbiter":
			for i in 3:
				var angle := TAU * float(i) / 3.0 - pattern_rotation
				var point := center + Vector2.from_angle(angle) * reach
				draw_circle(point, 7.0 + energy * 5.0, Color(color, energy * 0.72))
				draw_line(center, point, Color(color, energy * 0.34), 2.0)
		"sentence":
			var aim := (pending_target - position).normalized()
			if aim == Vector2.ZERO:
				aim = Vector2.DOWN
			draw_line(center - aim * reach * 0.25, center + aim * reach, Color(color, energy * 0.72), 4.0)
			draw_line(center - aim.rotated(PI * 0.5) * 38.0, center + aim.rotated(PI * 0.5) * 38.0, Color.WHITE, energy * 2.0)
		"halo":
			for i in 3:
				draw_arc(center, reach * (0.48 + i * 0.22), pattern_rotation * (1.0 if i % 2 else -1.0), pattern_rotation * (1.0 if i % 2 else -1.0) + PI * 1.55, 48, Color(color, energy * (0.72 - i * 0.12)), 3.0)
		"maelstrom":
			for i in 18:
				var t := float(i) / 17.0
				var angle := pattern_rotation * 2.0 + t * TAU * 2.4
				var point := center + Vector2.from_angle(angle) * reach * t
				draw_circle(point, 2.0 + energy * 3.0, Color(color, energy * (1.0 - t * 0.45)))
		"lattice":
			draw_set_transform(center, pattern_rotation * 0.7, Vector2.ONE)
			for i in 3:
				var half_size := reach * (0.35 + i * 0.2)
				draw_rect(Rect2(-Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), Color(color, energy * (0.72 - i * 0.16)), false, 2.5)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"last_light":
			for i in 12:
				var angle := TAU * float(i) / 12.0 + pattern_rotation
				var inner := radius * (0.45 if i % 2 else 0.7)
				draw_line(center + Vector2.from_angle(angle) * inner, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.78), 2.0 + float(i % 2) * 2.0)
