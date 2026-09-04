class_name PlayerController
extends Node2D

signal barrier_activated(position: Vector2)

const BARRIERS_PER_LIFE := 3
const FOCUS_BOSS_DAMAGE_SCALE := 0.75
const POSE_IDLE := 0
const POSE_BANK_LEFT := 1
const POSE_BANK_RIGHT := 2
const POSE_FOCUS := 3

var character: Dictionary
var projectile_manager: PlayerProjectileManager
var lives := 3
var barriers := BARRIERS_PER_LIFE
var power := 0
var invulnerable := 1.8
var barrier_time := 0.0
var barrier_cooldown := 0.0
var primary_timer := 0.0
var focus_timer := 0.0
var focus_active := false
var locked := true
var debug_invincible := false
var tilt := 0.0
var firing_glow := 0.0
var animation_time := 0.0
var character_texture: Texture2D
var combat_sheet: Texture2D
var pose_frame := POSE_IDLE
var previous_pose_frame := POSE_IDLE
var pose_blend := 1.0

func configure(data: Dictionary, shots: PlayerProjectileManager) -> void:
	character = data
	projectile_manager = shots
	var texture_paths := {
		"A": "res://assets/characters/kira_voss_keyart.png",
		"B": "res://assets/characters/dae_ryu_keyart.png",
		"C": "res://assets/characters/mina_zero_keyart.png"
	}
	var sheet_paths := {
		"A": "res://assets/characters/kira_voss_combat_sheet.png",
		"B": "res://assets/characters/dae_ryu_combat_sheet.png",
		"C": "res://assets/characters/mina_zero_combat_sheet.png"
	}
	var character_code := String(character.code)
	character_texture = load(texture_paths.get(character_code, texture_paths.A)) as Texture2D
	combat_sheet = load(sheet_paths.get(character_code, sheet_paths.A)) as Texture2D
	pose_frame = POSE_IDLE
	previous_pose_frame = POSE_IDLE
	pose_blend = 1.0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	position = Vector2(270, 842)
	queue_redraw()

func update_player(delta: float, control_state: Dictionary = {}) -> void:
	animation_time += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	barrier_time = maxf(0.0, barrier_time - delta)
	barrier_cooldown = maxf(0.0, barrier_cooldown - delta)
	primary_timer -= delta
	focus_timer -= delta
	firing_glow = maxf(0.0, firing_glow - delta * 6.0)
	if locked:
		_set_animation_pose(POSE_IDLE, delta)
		position.y = lerpf(position.y, 805.0, 1.0 - exp(-delta * 3.2))
		queue_redraw()
		return
	var has_control_override := not control_state.is_empty()
	focus_active = bool(control_state.get("focus", false)) if has_control_override else Input.is_action_pressed("focus")
	var input_vector := Vector2(float(control_state.get("x", 0.0)), float(control_state.get("y", 0.0))) if has_control_override else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed := float(character.focus_speed if focus_active else character.speed)
	position += input_vector * speed * delta
	position.x = clampf(position.x, GameManager.PLAY_BOUNDS.position.x, GameManager.PLAY_BOUNDS.end.x)
	position.y = clampf(position.y, GameManager.PLAY_BOUNDS.position.y + 80.0, GameManager.PLAY_BOUNDS.end.y)
	tilt = lerpf(tilt, input_vector.x, 1.0 - exp(-delta * 12.0))
	var target_pose := POSE_FOCUS if focus_active or barrier_time > 0.0 else (POSE_BANK_LEFT if tilt < -0.22 else (POSE_BANK_RIGHT if tilt > 0.22 else POSE_IDLE))
	_set_animation_pose(target_pose, delta)
	var barrier_pressed := bool(control_state.get("barrier_pressed", false)) if has_control_override else Input.is_action_just_pressed("barrier")
	if barrier_pressed:
		activate_barrier()
	if focus_active:
		if focus_timer <= 0.0:
			_fire_focus()
	else:
		var primary_held := bool(control_state.get("primary", false)) if has_control_override else (Input.is_action_pressed("primary") or bool(SaveManager.settings.get("auto_fire", false)))
		if primary_held and primary_timer <= 0.0:
			_fire_primary()
	queue_redraw()

func _set_animation_pose(next_pose: int, delta: float) -> void:
	if next_pose != pose_frame:
		previous_pose_frame = pose_frame
		pose_frame = next_pose
		pose_blend = 0.0
	pose_blend = minf(1.0, pose_blend + delta * 9.0)

func activate_barrier() -> bool:
	if barriers <= 0 or barrier_cooldown > 0.0 or locked:
		return false
	barriers -= 1
	barrier_time = 1.35
	barrier_cooldown = 1.65
	invulnerable = maxf(invulnerable, 1.5)
	barrier_activated.emit(position)
	AudioManager.play_sfx("barrier", 1.0, 1.0)
	EffectManager.shake(4)
	EffectManager.flash(character.accent, 0.6)
	queue_redraw()
	return true

func take_hit() -> bool:
	if not is_vulnerable():
		return false
	lives -= 1
	power = maxi(0, power - 1)
	barriers = BARRIERS_PER_LIFE
	barrier_time = 0.0
	barrier_cooldown = 0.0
	invulnerable = 2.6
	position = Vector2(270, 845)
	ScoreManager.register_death()
	AudioManager.play_sfx("player_hit", 1.0, 1.5)
	EffectManager.shake(4)
	EffectManager.flash(Color("ff3d6e"), 0.82)
	queue_redraw()
	return true

func is_vulnerable() -> bool:
	return invulnerable <= 0.0 and barrier_time <= 0.0 and not debug_invincible and not locked

func add_power() -> bool:
	var changed := power < 4
	power = mini(4, power + 1)
	AudioManager.play_sfx("pickup", 0.9 + power * 0.08, -1.0)
	queue_redraw()
	return changed

func _fire_primary() -> void:
	var code: String = character.code
	var color: Color = character.primary_color
	var count := 3
	var spread := 0.10
	var damage := 7.0 * float(character.power)
	var interval := 0.075
	match code:
		"B":
			count = 2 + int(power >= 3)
			spread = 0.035
			damage = 12.5 * float(character.power)
			interval = 0.092
		"C":
			count = 5 + int(power >= 2) * 2
			spread = 0.27
			damage = 4.4 * float(character.power)
			interval = 0.062
		_:
			count = 3 + int(power >= 2) * 2
			spread = 0.105
			damage = 6.8
	for i in count:
		var offset := float(i) - float(count - 1) * 0.5
		var angle := -PI * 0.5 + offset * spread
		var origin := position + Vector2(offset * 7.0, -22.0)
		projectile_manager.spawn(origin, Vector2.from_angle(angle) * 940.0, damage * (1.0 + power * 0.14), 3.1 + power * 0.22, color)
	primary_timer = interval
	firing_glow = 1.0
	AudioManager.play_sfx("shot", 0.92 + power * 0.035, -17.0)

func _fire_focus() -> void:
	var code: String = character.code
	var color: Color = character.accent
	var count := 2
	var damage := 10.0
	var radius := 4.2
	var interval := 0.085
	match code:
		"B":
			count = 2
			damage = 18.5
			radius = 6.0
			interval = 0.095
		"C":
			count = 3
			damage = 7.0
			radius = 3.8
			interval = 0.074
		_:
			count = 2 + int(power >= 4)
			damage = 11.0
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * (8.0 if code != "B" else 5.0)
		projectile_manager.spawn(position + Vector2(offset, -25), Vector2(0, -1120), damage * float(character.power) * (1.0 + power * 0.17), radius + power * 0.25, color, code == "B", FOCUS_BOSS_DAMAGE_SCALE)
	focus_timer = interval
	firing_glow = 1.0
	AudioManager.play_sfx("focus", 0.9 + power * 0.04, -18.0)

func _draw() -> void:
	if character.is_empty():
		return
	var primary: Color = character.primary_color
	var accent: Color = character.accent
	var alpha := 1.0
	if invulnerable > 0.0 and fmod(invulnerable, 0.16) < 0.08:
		alpha = 0.28
	# Flight trails.
	draw_line(Vector2(-9, 13), Vector2(-9 - tilt * 5.0, 37 + firing_glow * 8.0), Color(primary, 0.18 * alpha), 8.0)
	draw_line(Vector2(9, 13), Vector2(9 - tilt * 5.0, 37 + firing_glow * 8.0), Color(accent, 0.18 * alpha), 8.0)
	draw_line(Vector2(-9, 12), Vector2(-9 - tilt * 3.0, 29 + firing_glow * 7.0), Color(primary, 0.78 * alpha), 2.5)
	draw_line(Vector2(9, 12), Vector2(9 - tilt * 3.0, 29 + firing_glow * 7.0), Color(accent, 0.78 * alpha), 2.5)
	# Psychic aura.
	draw_circle(Vector2.ZERO, 29.0, Color(primary, 0.07 * alpha))
	draw_arc(Vector2.ZERO, 24.0, -0.4 + tilt * 0.2, PI + 0.5 + tilt * 0.2, 28, Color(accent, 0.35 * alpha), 2.0)
	# Authored state frames cross-fade while the collision core stays fixed.
	if combat_sheet:
		var hover := sin(animation_time * 3.4) * 1.15 - firing_glow * 1.2
		var squash := Vector2(1.0 - absf(tilt) * 0.025, 1.0 + firing_glow * 0.025)
		draw_set_transform(Vector2(0.0, hover), tilt * 0.075, squash)
		if pose_blend < 1.0:
			_draw_combat_pose(previous_pose_frame, alpha * (1.0 - pose_blend))
		_draw_combat_pose(pose_frame, alpha * pose_blend)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif character_texture:
		draw_texture_rect(character_texture, Rect2(-27, -42, 54, 81), false, Color(1, 1, 1, alpha))
	else:
		draw_circle(Vector2(0, -13), 6.8, Color(primary, alpha))
	draw_circle(Vector2(0, 1), 3.2, Color.WHITE)
	# Focus exposes the true 6.4 px collision core.
	if focus_active or bool(SaveManager.settings.get("show_hitbox", false)):
		var pulse := 0.7 + sin(Time.get_ticks_msec() * 0.018) * 0.22
		draw_circle(Vector2.ZERO, 8.0, Color(accent, 0.18 * pulse))
		draw_arc(Vector2.ZERO, 6.4, 0, TAU, 24, Color.WHITE, 1.6)
		draw_circle(Vector2.ZERO, 2.6, Color("ff355f"))
	if barrier_time > 0.0:
		var ratio := barrier_time / 1.35
		var radius := 62.0 + (1.0 - ratio) * 58.0
		draw_circle(Vector2.ZERO, radius, Color(accent, 0.07 + ratio * 0.08))
		draw_arc(Vector2.ZERO, radius, -barrier_time * 4.0, TAU - barrier_time * 4.0, 64, Color(accent, 0.78 * ratio), 4.0)
		draw_arc(Vector2.ZERO, radius * 0.78, barrier_time * 5.0, TAU + barrier_time * 5.0, 64, Color.WHITE, 0.34 * ratio + 1.0)

func _draw_combat_pose(frame: int, alpha: float) -> void:
	if combat_sheet == null or alpha <= 0.001:
		return
	var frame_width := float(combat_sheet.get_width()) * 0.5
	var frame_height := float(combat_sheet.get_height()) * 0.5
	var source := Rect2(float(frame % 2) * frame_width, float(frame / 2) * frame_height, frame_width, frame_height)
	var target_height := 88.0
	var target_width := target_height * frame_width / frame_height
	draw_texture_rect_region(combat_sheet, Rect2(-target_width * 0.5, -44.0, target_width, target_height), source, Color(1, 1, 1, alpha))
