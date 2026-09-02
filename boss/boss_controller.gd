class_name BossController
extends Node2D

signal phase_changed(phase: int, phase_name: String)
signal defeated(is_final: bool)

var boss_id := ""
var display_name := ""
var is_final := false
var phases: Array[BossPhaseData] = []
var current_phase := 0
var hp := 1.0
var max_hp := 1.0
var target_position := Vector2(270, 220)
var age := 0.0
var phase_time := 0.0
var fire_timer := 1.0
var pattern_cursor := 0
var pattern_rotation := 0.0
var entering := true
var dying := false
var death_time := 0.0
var flash := 0.0
var radius := 58.0
var bullet_manager: BulletManager
var player_position := Vector2(270, 820)

func setup(id: String, manager: BulletManager) -> void:
	boss_id = id
	bullet_manager = manager
	position = Vector2(270, -100)
	is_final = id == "seraph"
	display_name = "SERAPH EXECUTOR" if is_final else "ARBITER-03"
	radius = 45.0 if is_final else 64.0
	phases = _make_final_phases() if is_final else _make_mid_phases()
	current_phase = 0
	_start_phase()
	queue_redraw()

func update_boss(delta: float, target: Vector2, difficulty: float = 1.0) -> void:
	player_position = target
	age += delta
	flash = maxf(0.0, flash - delta * 8.0)
	if dying:
		death_time += delta
		position += Vector2(sin(death_time * 21.0) * 0.9, -delta * 9.0)
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
			phase_changed.emit(1, phases[0].name)
		queue_redraw()
		return
	phase_time += delta
	pattern_rotation += delta * (0.62 + current_phase * 0.18)
	_update_movement(delta)
	fire_timer -= delta
	if fire_timer <= 0.0:
		_fire(difficulty)
		fire_timer = phases[current_phase].fire_interval / clampf(difficulty, 0.9, 1.35)
	if phase_time >= phases[current_phase].duration:
		_advance_phase(false)
	queue_redraw()

func damage(amount: float) -> bool:
	if entering or dying:
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
	for phase in phases:
		total += phase.hp
	return total

func _start_phase() -> void:
	var data := phases[current_phase]
	max_hp = data.hp
	hp = max_hp
	phase_time = 0.0
	fire_timer = 1.05
	pattern_cursor = 0

func _advance_phase(killed: bool) -> void:
	if dying:
		return
	var data := phases[current_phase]
	if killed:
		ScoreManager.add_boss_bonus(data.bonus)
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
	phase_changed.emit(current_phase + 1, phases[current_phase].name)

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

func _fire(difficulty: float) -> void:
	var phase := phases[current_phase]
	var id := phase.pattern_ids[pattern_cursor % phase.pattern_ids.size()]
	pattern_cursor += 1
	var pattern := GameDatabase.pattern(id)
	var offset := pattern_rotation
	# Stable phase offsets create learnable, repeating lanes.
	if id == "geometric":
		offset = floor(phase_time / 2.0) * PI / 16.0
	PatternEmitter.emit(bullet_manager, position, player_position, pattern, offset, minf(1.30, difficulty))
	if is_final and current_phase >= 2 and pattern_cursor % 3 == 0:
		var aimed := GameDatabase.pattern("aimed")
		aimed.speed += 18.0 + current_phase * 8.0
		PatternEmitter.emit(bullet_manager, position, player_position, aimed, 0.0, 1.0)
	AudioManager.play_sfx("enemy_shot", 0.72 + current_phase * 0.08, -10.0)

func _make_mid_phases() -> Array[BossPhaseData]:
	return [
		_phase("PERIMETER DENIAL", 1250, 25.0, ["spread", "ring"], 0.72, "hover", Color("ff9d45"), 10000),
		_phase("ROTARY JUDGEMENT", 1450, 27.0, ["rotating", "burst"], 0.58, "wide", Color("ff4b8b"), 15000),
		_phase("ARBITER OVERDRIVE", 1750, 30.0, ["layered", "stream", "radial"], 0.48, "cross", Color("bf5dff"), 22000)
	]

func _make_final_phases() -> Array[BossPhaseData]:
	return [
		_phase("VECTOR SENTENCE", 1850, 28.0, ["spread", "aimed", "burst"], 0.66, "hover", Color("ff477e"), 20000),
		_phase("HALO ENGINE", 2150, 30.0, ["rotating", "ring", "radial"], 0.52, "wide", Color("54e7ff"), 30000),
		_phase("SYNAPTIC MAELSTROM", 2450, 32.0, ["spiral", "layered", "aimed"], 0.43, "cross", Color("b45cff"), 45000),
		_phase("LATTICE OF NULL", 2750, 34.0, ["geometric", "rotating", "burst"], 0.39, "wide", Color("ff5dba"), 60000),
		_phase("LAST LIGHT PROTOCOL", 3300, 42.0, ["layered", "geometric", "stream", "ring"], 0.31, "aggressive", Color("ff334f"), 100000)
	]

func _phase(title: String, phase_hp: float, duration: float, patterns: Array, interval: float, movement: String, accent: Color, bonus: int) -> BossPhaseData:
	var data := BossPhaseData.new()
	data.name = title
	data.hp = phase_hp * GameDatabase.global_balance("boss_hp_scale")
	data.duration = duration * GameDatabase.global_balance("boss_phase_duration_scale")
	data.pattern_ids = PackedStringArray(patterns)
	data.fire_interval = interval
	data.movement_id = movement
	data.accent = accent
	data.bonus = bonus
	return data

func _draw() -> void:
	var color := phases[current_phase].accent if current_phase < phases.size() else Color("ff334f")
	if flash > 0.0:
		color = Color.WHITE
	if dying:
		for i in 8:
			var angle := float(i) / 8.0 * TAU + death_time * (1.0 if i % 2 else -1.0)
			var burst_p := position + Vector2.from_angle(angle) * (18.0 + fmod(death_time * 90.0 + i * 13.0, 75.0))
			draw_circle(burst_p, 5.0 + absf(sin(death_time * 13.0 + i)) * 10.0, Color(color, 0.58))
	# Large psychic aura and rotating machinery.
	draw_circle(position, radius + 22.0, Color(color, 0.09))
	for i in 3:
		var ring_radius := radius + 9.0 + i * 12.0
		var start := pattern_rotation * (1.0 if i % 2 else -1.0) + i
		draw_arc(position, ring_radius, start, start + PI * 1.35, 32, Color(color, 0.42 - i*0.08), 2.0)
	if is_final:
		# Human-scale silhouette held inside an oversized psychic halo.
		draw_circle(position + Vector2(0,-17), 10.0, color)
		draw_colored_polygon(PackedVector2Array([position+Vector2(0,-7),position+Vector2(17,26),position+Vector2(7,20),position+Vector2(0,44),position+Vector2(-7,20),position+Vector2(-17,26)]),color.darkened(0.15))
		draw_line(position+Vector2(-9,0),position+Vector2(-30,27),Color.WHITE,4.0)
		draw_line(position+Vector2(9,0),position+Vector2(30,27),Color.WHITE,4.0)
	else:
		var body := PackedVector2Array([position+Vector2(0,-radius),position+Vector2(radius*1.2,-radius*0.15),position+Vector2(radius*0.8,radius*0.75),position+Vector2(0,radius*0.52),position+Vector2(-radius*0.8,radius*0.75),position+Vector2(-radius*1.2,-radius*0.15)])
		draw_colored_polygon(body,color.darkened(0.32))
		for side in [-1.0,1.0]:
			draw_circle(position+Vector2(side*radius*0.72,0),radius*0.23,color)
			draw_line(position+Vector2(side*radius*0.55,5),position+Vector2(side*radius*1.25,radius*0.65),Color(color,0.75),6.0)
		draw_circle(position,radius*0.35,color)
	draw_circle(position,5.0,Color.WHITE)
