class_name TrainingScreen
extends Control

signal completed
signal skipped

const ACTION_STEPS := 4
const MOVE_TARGET := 150.0
const HOLD_TARGET := 0.75

var player: PlayerController
var projectile_manager: PlayerProjectileManager
var bullet_manager: BulletManager
var fx: CombatFX
var skip_button: Button
var deploy_button: Button
var step := 0
var movement_distance := 0.0
var hold_time := 0.0
var transition_time := 0.35
var time := 0.0
var last_player_position := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	projectile_manager = PlayerProjectileManager.new()
	projectile_manager.z_index = 2
	add_child(projectile_manager)
	bullet_manager = BulletManager.new()
	bullet_manager.z_index = 3
	bullet_manager.collision_enabled = false
	add_child(bullet_manager)
	player = PlayerController.new()
	player.z_index = 4
	add_child(player)
	player.configure(GameManager.character(), projectile_manager)
	player.position = Vector2(270, 685)
	player.locked = false
	player.invulnerable = 9999.0
	player.power = 2
	player.barriers = PlayerController.BARRIERS_PER_LIFE
	player.barrier_activated.connect(_on_barrier)
	last_player_position = player.position
	fx = CombatFX.new()
	fx.z_index = 5
	add_child(fx)

	skip_button = _button(GameText.text("training_skip"), Vector2(190, 900), Vector2(160, 42), Color("64799c"))
	deploy_button = _button(GameText.text("training_deploy"), Vector2(135, 832), Vector2(270, 54), GameManager.character().primary_color)
	deploy_button.visible = false
	skip_button.pressed.connect(_skip_training)
	deploy_button.pressed.connect(_finish_training)
	# Gamepad A is both primary fire and UI accept. Keeping focus off the skip
	# button prevents the shot lesson from accidentally leaving training.
	skip_button.focus_mode = Control.FOCUS_NONE
	AudioManager.play_music("stage")

func _button(label: String, at: Vector2, button_size: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = label
	button.position = at
	button.custom_minimum_size = button_size
	button.size = button_size
	ArcadeUI.style_button(button, accent)
	button.custom_minimum_size = button_size
	button.size = button_size
	button.add_theme_font_size_override("font_size", 13 if button_size.x < 200.0 else 17)
	button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.0, -5.0))
	add_child(button)
	return button

func _process(delta: float) -> void:
	time += delta
	transition_time = maxf(0.0, transition_time - delta)
	player.update_player(delta)
	projectile_manager.update_projectiles(delta)
	bullet_manager.update_bullets(delta, player.position, false)
	var traveled := player.position.distance_to(last_player_position)
	last_player_position = player.position
	if transition_time <= 0.0:
		match step:
			0:
				movement_distance += traveled
				if movement_distance >= MOVE_TARGET:
					_advance_step()
			1:
				if Input.is_action_pressed("primary"):
					hold_time += delta
				if hold_time >= HOLD_TARGET:
					_advance_step()
			2:
				if Input.is_action_pressed("focus"):
					hold_time += delta
				if hold_time >= HOLD_TARGET:
					_advance_step()
	queue_redraw()

func _advance_step() -> void:
	if step >= ACTION_STEPS:
		return
	step += 1
	hold_time = 0.0
	transition_time = 0.35
	fx.shockwave(player.position, GameManager.character().primary_color, 0.65)
	AudioManager.play_sfx("ui_confirm", 1.0 + step * 0.035, -2.0)
	if step == 3:
		player.barriers = PlayerController.BARRIERS_PER_LIFE
		_spawn_barrier_demo()
	elif step == ACTION_STEPS:
		bullet_manager.clear_all(true)
		deploy_button.visible = true
		deploy_button.grab_focus.call_deferred()
	queue_redraw()

func _spawn_barrier_demo() -> void:
	bullet_manager.clear_all(false)
	var data := BulletData.new()
	data.speed = 18.0
	data.radius = 6.5
	data.lifetime = 20.0
	for i in 36:
		var angle := TAU * float(i) / 36.0
		var radius := 105.0 + float(i % 3) * 34.0
		var origin := player.position + Vector2.from_angle(angle) * radius
		data.color = Color("ff4f9d") if i % 2 == 0 else Color("8a62ff")
		bullet_manager.spawn_bullet(origin, origin.angle_to_point(player.position), data)

func _on_barrier(center: Vector2) -> void:
	var erased := bullet_manager.clear_radius(center, 260.0)
	fx.shockwave(center, GameManager.character().accent, 1.6)
	fx.burst(center, GameManager.character().primary_color, 0.85, 24)
	if step == 3 and erased > 0:
		_advance_step()

func _finish_training() -> void:
	if step < ACTION_STEPS:
		return
	AudioManager.play_sfx("ui_confirm", 1.12, 0.0)
	AudioManager.play_music("title")
	completed.emit()

func _skip_training() -> void:
	AudioManager.play_sfx("ui_confirm", 0.82, -3.0)
	AudioManager.play_music("title")
	skipped.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		_skip_training()
		get_viewport().set_input_as_handled()
	elif step >= ACTION_STEPS and (event.is_action_pressed("primary") or event.is_action_pressed("ui_accept")):
		_finish_training()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var primary: Color = GameManager.character().primary_color
	var accent: Color = GameManager.character().accent
	draw_rect(Rect2(0, 0, 540, 960), Color("03091d"))
	for row in 17:
		var y := 145.0 + row * 38.0
		draw_line(Vector2(20, y), Vector2(520, y), Color(0.12, 0.36, 0.62, 0.10), 1.0)
	for column in 14:
		var x := 20.0 + column * 38.5
		draw_line(Vector2(x, 145), Vector2(x - 100, 790), Color(0.12, 0.36, 0.62, 0.08), 1.0)
	draw_rect(Rect2(20, 145, 500, 650), Color(0.015, 0.035, 0.085, 0.58), false, 2.0)
	draw_line(Vector2(20, 145), Vector2(520, 145), primary, 2.0)
	draw_string(font, Vector2(0, 76), GameText.text("training_title"), HORIZONTAL_ALIGNMENT_CENTER, 540, 28, Color("e9fbff"))
	draw_string(font, Vector2(0, 108), GameText.text("training_sub"), HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color(0.48, 0.67, 0.88))
	for index in ACTION_STEPS:
		var dot_color := Color("76f5ff") if index < step else (Color("ffe579") if index == step else Color(0.25, 0.35, 0.52))
		draw_circle(Vector2(225 + index * 30, 132), 5.5 if index == step and step < ACTION_STEPS else 4.0, dot_color)

	var heading := _step_title()
	var body := _step_body()
	draw_string(font, Vector2(0, 218), heading, HORIZONTAL_ALIGNMENT_CENTER, 540, 23, Color("ffe579") if step < ACTION_STEPS else Color("75ffb2"))
	_draw_centered_lines(font, body, 254, 14, Color(0.72, 0.84, 0.97))
	var progress := _step_progress()
	draw_rect(Rect2(90, 318, 360, 8), Color(0.08, 0.15, 0.27, 0.95))
	draw_rect(Rect2(90, 318, 360.0 * progress, 8), primary)
	draw_string(font, Vector2(0, 350), GameText.text("training_progress") % int(round(progress * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color(0.48, 0.68, 0.90))

	var target := Vector2(270, 445)
	for ring in 3:
		var radius := 34.0 + ring * 18.0 + sin(time * 2.0 + ring) * 3.0
		draw_arc(target, radius, time * (0.18 + ring * 0.04), TAU + time * (0.18 + ring * 0.04), 48, Color(accent, 0.34 - ring * 0.07), 2.0)
	var diamond := PackedVector2Array([target + Vector2(0, -22), target + Vector2(22, 0), target + Vector2(0, 22), target + Vector2(-22, 0), target + Vector2(0, -22)])
	draw_polyline(diamond, Color(primary, 0.82), 2.0)
	draw_string(font, Vector2(0, 536), GameText.text("training_target"), HORIZONTAL_ALIGNMENT_CENTER, 540, 10, Color(0.42, 0.62, 0.82))
	draw_string(font, Vector2(0, 768), _step_hint(), HORIZONTAL_ALIGNMENT_CENTER, 540, 12, Color("a9caff"))

func _draw_centered_lines(font: Font, value: String, start_y: float, font_size: int, color: Color) -> void:
	var lines := value.split("\n")
	for index in lines.size():
		draw_string(font, Vector2(0, start_y + index * (font_size + 7)), lines[index], HORIZONTAL_ALIGNMENT_CENTER, 540, font_size, color)

func _step_title() -> String:
	var keys := ["training_move", "training_primary", "training_focus", "training_barrier", "training_complete"]
	return GameText.text(keys[clampi(step, 0, ACTION_STEPS)])

func _step_body() -> String:
	match step:
		0:
			return GameText.text("training_move_desc") % [
				SaveManager.keyboard_binding_label("move_up"), SaveManager.keyboard_binding_label("move_left"),
				SaveManager.keyboard_binding_label("move_down"), SaveManager.keyboard_binding_label("move_right")
			]
		1:
			return GameText.text("training_primary_desc") % [SaveManager.keyboard_binding_label("primary"), SaveManager.gamepad_binding_label("primary")]
		2:
			return GameText.text("training_focus_desc") % [SaveManager.keyboard_binding_label("focus"), SaveManager.gamepad_binding_label("focus")]
		3:
			return GameText.text("training_barrier_desc") % [SaveManager.keyboard_binding_label("barrier"), SaveManager.gamepad_binding_label("barrier")]
		_:
			return GameText.text("training_complete_desc")

func _step_hint() -> String:
	if step >= ACTION_STEPS:
		return GameText.text("training_complete_hint")
	return GameText.text("training_hold")

func _step_progress() -> float:
	match step:
		0:
			return clampf(movement_distance / MOVE_TARGET, 0.0, 1.0)
		1, 2:
			return clampf(hold_time / HOLD_TARGET, 0.0, 1.0)
		3:
			return 0.0
		_:
			return 1.0
