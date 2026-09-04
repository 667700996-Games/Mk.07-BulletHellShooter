class_name GameHUD
extends Control

var lives := 3
var barriers := 3
var power := 0
var combo := 0
var multiplier := 1.0
var graze := 0
var boss_name := ""
var boss_hp := 0.0
var boss_max_hp := 1.0
var boss_phase := 0
var boss_phases := 0
var stage_time := 0.0
var message := ""
var message_sub := ""
var message_time := 0.0
var message_duration := 0.0
var message_portrait: Texture2D
var message_portrait_final := false
var warning_strength := 0.0
var player_color := Color("39e7ff")
var difficulty_id := "normal"
var ranked_run := true
var run_mode := "campaign"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ScoreManager.score_changed.connect(_on_stat_change)
	ScoreManager.combo_changed.connect(_on_combo_change)
	ScoreManager.graze_changed.connect(_on_graze_change)

func set_player_color(color: Color) -> void:
	player_color = color

func set_run_context(next_difficulty: String, ranked: bool, next_mode: String = "campaign") -> void:
	difficulty_id = next_difficulty
	ranked_run = ranked
	run_mode = next_mode
	queue_redraw()

func set_status(next_lives: int, next_barriers: int, next_power: int) -> void:
	lives = next_lives
	barriers = next_barriers
	power = next_power
	queue_redraw()

func set_boss(name: String, hp: float, max_hp: float, phase: int, phases: int) -> void:
	boss_name = name
	boss_hp = hp
	boss_max_hp = maxf(1.0, max_hp)
	boss_phase = phase
	boss_phases = phases
	queue_redraw()

func clear_boss() -> void:
	boss_name = ""
	queue_redraw()

func announce(title: String, subtitle: String = "", duration: float = 2.0) -> void:
	message = title
	message_sub = subtitle
	message_time = duration
	message_duration = duration
	message_portrait = null
	message_portrait_final = false
	if title == "ARBITER-03":
		message_portrait = load("res://assets/bosses/arbiter_03_keyart.png") as Texture2D
	elif title == "SERAPH EXECUTOR":
		message_portrait = load("res://assets/bosses/seraph_executor_keyart.png") as Texture2D
		message_portrait_final = true
	queue_redraw()

func warning(duration: float = 3.0) -> void:
	warning_strength = duration
	announce(GameText.text("warning"), GameText.text("psychic_signal"), duration)

func _process(delta: float) -> void:
	stage_time += delta
	message_time = maxf(0.0, message_time - delta)
	warning_strength = maxf(0.0, warning_strength - delta)
	if message_time > 0.0 or warning_strength > 0.0:
		queue_redraw()

func _on_stat_change(_value: int = 0) -> void:
	queue_redraw()

func _on_combo_change(value: int, next_multiplier: float) -> void:
	combo = value
	multiplier = next_multiplier
	queue_redraw()

func _on_graze_change(value: int) -> void:
	graze = value
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 540, 60), Color(0.015, 0.025, 0.075, 0.88))
	draw_line(Vector2(0, 59), Vector2(540, 59), Color(player_color, 0.42), 2.0)
	draw_string(font, Vector2(18, 22), GameText.text("score"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.72, 0.9))
	draw_string(font, Vector2(18, 45), "%012d" % ScoreManager.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)
	var unranked_label := GameText.text("replay_mode") if run_mode == "replay" else (GameText.text("boss_practice") if run_mode == "practice" else GameText.text("assist_active"))
	var record_label := "%s %s" % [GameText.text("difficulty_%s" % difficulty_id), GameText.text("high_score")] if ranked_run else unranked_label
	var record_score := maxi(SaveManager.high_score_for(difficulty_id), ScoreManager.score) if ranked_run else ScoreManager.score
	draw_string(font, Vector2(332, 22), record_label, HORIZONTAL_ALIGNMENT_RIGHT, 190, 12, Color(0.55, 0.72, 0.9))
	draw_string(font, Vector2(332, 45), "%012d" % record_score, HORIZONTAL_ALIGNMENT_RIGHT, 190, 18, Color("ffd470"))
	# Lives and resources.
	draw_rect(Rect2(12, 902, 230, 44), Color(0.015, 0.025, 0.07, 0.82))
	draw_string(font, Vector2(22, 921), GameText.text("vector"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.52, 0.72, 0.9))
	for i in lives:
		var p := Vector2(28 + i * 21, 936)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0,-7), p + Vector2(7,6), p + Vector2(0,3), p + Vector2(-7,6)]), player_color)
	draw_string(font, Vector2(122, 921), "%s %d/4" % [GameText.text("power"), power], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.52, 0.72, 0.9))
	for i in 4:
		draw_rect(Rect2(122 + i * 22, 930, 17, 6), player_color if i < power else Color(0.18,0.23,0.34,0.8))
	# Barrier cells.
	draw_rect(Rect2(250, 902, 278, 44), Color(0.015, 0.025, 0.07, 0.82))
	draw_string(font, Vector2(266, 922), GameText.text("barrier"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.52, 0.72, 0.9))
	for i in 3:
		var center := Vector2(430 + i * 27, 924)
		draw_arc(center, 8.0, 0, TAU, 20, Color("b56bff") if i < barriers else Color(0.18,0.23,0.34,0.8), 3.0)
	# Combo rail.
	if combo > 0:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.04
		draw_rect(Rect2(405, 405, 127, 84), Color(0.02, 0.025, 0.08, 0.78))
		draw_line(Vector2(405,405), Vector2(405,489), Color(player_color, 0.8), 3.0)
		draw_string(font, Vector2(517, 428), "%d %s" % [combo, GameText.text("chain")], HORIZONTAL_ALIGNMENT_RIGHT, 102, 15, Color.WHITE)
		draw_string(font, Vector2(517, 461), "x%.1f" % multiplier, HORIZONTAL_ALIGNMENT_RIGHT, 102, int(27 * pulse), player_color)
		draw_string(font, Vector2(517, 481), "%s %04d" % [GameText.text("graze"), graze], HORIZONTAL_ALIGNMENT_RIGHT, 102, 11, Color(0.66,0.78,0.95))
	# Boss health segmented by phase.
	if not boss_name.is_empty():
		draw_rect(Rect2(98, 71, 344, 39), Color(0.01, 0.015, 0.05, 0.9))
		draw_string(font, Vector2(108, 86), boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		draw_string(font, Vector2(431, 86), "%s %d/%d" % [GameText.text("phase"), boss_phase, boss_phases], HORIZONTAL_ALIGNMENT_RIGHT, 100, 11, Color(0.7,0.76,0.9))
		var ratio := clampf(boss_hp / boss_max_hp, 0.0, 1.0)
		draw_rect(Rect2(108, 94, 324, 8), Color("221332"))
		draw_rect(Rect2(108, 94, 324 * ratio, 8), Color("ff477e").lerp(player_color, ratio * 0.35))
		for i in range(1, boss_phases):
			var x := 108.0 + 324.0 * float(i) / float(boss_phases)
			draw_line(Vector2(x, 93), Vector2(x, 104), Color.WHITE, 1.0)
	# Stage messages.
	if message_time > 0.0:
		var entrance := clampf((message_duration - message_time) / 0.32, 0.0, 1.0)
		var exit_fade := clampf(minf(message_time, 0.42) / 0.42, 0.0, 1.0)
		var fade := entrance * exit_fade
		if message_portrait:
			draw_rect(Rect2(0, 125, 540, 430), Color(0.005, 0.008, 0.03, fade * 0.82))
			var slash := PackedVector2Array([Vector2(0,170),Vector2(190,125),Vector2(150,555),Vector2(0,555)])
			draw_colored_polygon(slash, Color(player_color, fade * 0.13))
			var portrait_rect := Rect2(4 - (1.0-entrance)*70.0, 165, 192, 288) if message_portrait_final else Rect2(-8 - (1.0-entrance)*70.0, 190, 220, 220)
			draw_texture_rect(message_portrait, portrait_rect, false, Color(1,1,1,fade))
			draw_line(Vector2(184,190),Vector2(540,190),Color("ff3c62",fade),3.0)
			draw_string(font, Vector2(198, 280), message, HORIZONTAL_ALIGNMENT_LEFT, 330, 29, Color.WHITE)
			draw_string(font, Vector2(198, 313), message_sub, HORIZONTAL_ALIGNMENT_LEFT, 330, 12, Color(0.68,0.82,1.0,fade))
			draw_string(font, Vector2(198, 351), GameText.text("signature_confirmed"), HORIZONTAL_ALIGNMENT_LEFT, 330, 10, Color("ff668f",fade))
			draw_line(Vector2(198,370),Vector2(510,370),Color(player_color,fade*0.65),1.0)
		else:
			var y := 326.0
			draw_rect(Rect2(0, y - 44, 540, 98), Color(0.01, 0.015, 0.06, fade * 0.62))
			draw_line(Vector2(0,y-43), Vector2(540,y-43), Color(player_color, fade * 0.65), 2.0)
			draw_line(Vector2(0,y+53), Vector2(540,y+53), Color(player_color, fade * 0.65), 2.0)
			var title_color := Color("ff3c62") if warning_strength > 0.0 else Color.WHITE
			draw_string(font, Vector2(0, y + 4), message, HORIZONTAL_ALIGNMENT_CENTER, 540, 34, Color(title_color, fade))
			draw_string(font, Vector2(0, y + 31), message_sub, HORIZONTAL_ALIGNMENT_CENTER, 540, 13, Color(0.65,0.8,1.0,fade))
	if warning_strength > 0.0:
		var warning_alpha := (0.08 + absf(sin(Time.get_ticks_msec() * 0.016)) * 0.10) * clampf(warning_strength, 0.0, 1.0)
		draw_rect(Rect2(0, 0, 540, 960), Color(1.0,0.05,0.12,warning_alpha), false, 8.0)
