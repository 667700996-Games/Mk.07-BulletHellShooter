class_name RecordsScreen
extends Control

signal closed

var difficulty_index := 1
var time := 0.0
var export_status := ""
var export_status_time := 0.0
var left_button: Button
var right_button: Button
var export_button: Button
var back_button: Button
var use_preview_data := false
var preview_difficulty := "normal"
var preview_history: Array[Dictionary] = []

func setup_preview(entries: Array[Dictionary], difficulty_id: String = "normal") -> void:
	use_preview_data = true
	preview_history = entries.duplicate(true)
	preview_difficulty = difficulty_id if GameManager.DIFFICULTY_ORDER.has(difficulty_id) else "normal"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var initial_difficulty := preview_difficulty if use_preview_data else SaveManager.selected_difficulty
	difficulty_index = maxi(0, GameManager.DIFFICULTY_ORDER.find(initial_difficulty))
	left_button = _button("◀", Vector2(48, 146), Vector2(64, 44), Color("43e8ff"))
	right_button = _button("▶", Vector2(428, 146), Vector2(64, 44), Color("43e8ff"))
	export_button = _button(GameText.text("export_data"), Vector2(135, 826), Vector2(270, 52), Color("43e8ff"))
	back_button = _button(GameText.text("archive_back"), Vector2(135, 890), Vector2(270, 52), Color("a45cff"))
	left_button.pressed.connect(_cycle_difficulty.bind(-1))
	right_button.pressed.connect(_cycle_difficulty.bind(1))
	export_button.pressed.connect(_export_data)
	back_button.pressed.connect(_close)
	left_button.focus_neighbor_right = right_button.get_path()
	right_button.focus_neighbor_left = left_button.get_path()
	back_button.grab_focus.call_deferred()
	AudioManager.play_music("title")

func _button(label: String, at: Vector2, button_size: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = label
	button.position = at
	button.custom_minimum_size = button_size
	button.size = button_size
	ArcadeUI.style_button(button, accent)
	button.custom_minimum_size = button_size
	button.size = button_size
	button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.0, -5.0))
	add_child(button)
	return button

func _cycle_difficulty(direction: int) -> void:
	difficulty_index = wrapi(difficulty_index + direction, 0, GameManager.DIFFICULTY_ORDER.size())
	AudioManager.play_sfx("ui_move", 1.08, -3.0)
	queue_redraw()

func _export_data() -> void:
	var success := SaveManager.export_playtest_data()
	export_status = GameText.text("export_success") if success else GameText.text("export_failed")
	export_status_time = 4.0
	AudioManager.play_sfx("ui_confirm" if success else "warning", 1.0, -2.0)
	queue_redraw()

func _close() -> void:
	AudioManager.play_sfx("ui_confirm", 0.9, -3.0)
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		_cycle_difficulty(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_cycle_difficulty(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game"):
		_close()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	time += delta
	if export_status_time > 0.0:
		export_status_time = maxf(0.0, export_status_time - delta)
		if export_status_time <= 0.0:
			export_status = ""
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var difficulty_id: String = GameManager.DIFFICULTY_ORDER[difficulty_index]
	var summary := _summary(difficulty_id)
	draw_rect(Rect2(0, 0, 540, 960), Color("04091c"))
	for band in 16:
		var shade := Color("071536").lerp(Color("160a2e"), float(band) / 15.0)
		shade.a = 0.22
		draw_rect(Rect2(0, band * 60, 540, 62), shade)
	for ring in 7:
		var radius := 120.0 + ring * 52.0 + sin(time * 0.55 + ring) * 4.0
		draw_arc(Vector2(270, 300), radius, -0.45 + time * 0.025, 2.65 + time * 0.025, 64, Color(0.20, 0.72, 1.0, 0.055), 1.0)
	draw_string(font, Vector2(0, 78), GameText.text("combat_archive"), HORIZONTAL_ALIGNMENT_CENTER, 540, 30, Color("75f3ff"))
	draw_string(font, Vector2(0, 108), GameText.text("archive_sub"), HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color(0.48, 0.65, 0.86))
	draw_rect(Rect2(38, 137, 464, 62), Color(0.02, 0.07, 0.16, 0.92))
	draw_line(Vector2(38, 137), Vector2(502, 137), Color("43e8ff"), 2.0)
	draw_string(font, Vector2(118, 177), GameText.text("difficulty_%s" % difficulty_id), HORIZONTAL_ALIGNMENT_CENTER, 304, 22, Color.WHITE)

	_draw_summary_panel(font, summary)
	draw_string(font, Vector2(36, 489), "%s // %s" % [GameText.text("combat_archive"), GameText.text("vector_breakdown")], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.50, 0.70, 0.91))
	for character_index in GameManager.CHARACTERS.size():
		_draw_character_card(font, character_index, _summary(difficulty_id, character_index))
	_draw_recent_runs(font, difficulty_id)
	if not export_status.is_empty():
		draw_string(font, Vector2(0, 816), export_status, HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color("7dffb2") if export_status == GameText.text("export_success") else Color("ff7192"))

func _draw_summary_panel(font: Font, summary: Dictionary) -> void:
	draw_rect(Rect2(34, 218, 472, 244), Color(0.015, 0.035, 0.095, 0.92))
	draw_line(Vector2(34, 218), Vector2(506, 218), Color("a45cff"), 2.0)
	_draw_stat(font, GameText.text("archive_runs"), "%02d" % int(summary.runs), Vector2(58, 245))
	_draw_stat(font, GameText.text("archive_clears"), "%02d" % int(summary.clears), Vector2(286, 245))
	_draw_stat(font, GameText.text("clear_rate"), "%05.1f%%" % (float(summary.clear_rate) * 100.0), Vector2(58, 306))
	_draw_stat(font, GameText.text("average_losses"), "%.2f" % float(summary.average_deaths), Vector2(286, 306))
	_draw_stat(font, GameText.text("average_barriers"), "%.2f" % float(summary.average_barriers), Vector2(58, 367))
	_draw_stat(font, GameText.text("overdrive_rate"), "%05.1f%%" % (float(summary.overdrive_rate) * 100.0), Vector2(286, 367))
	draw_line(Vector2(52, 421), Vector2(488, 421), Color(0.17, 0.34, 0.56, 0.55), 1.0)
	draw_string(font, Vector2(58, 447), "%s  %s" % [GameText.text("best_clear"), _format_time(float(summary.best_clear_time))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("d4e8ff"))
	draw_string(font, Vector2(280, 447), "%s  %09d" % [GameText.text("best_score"), int(summary.best_score)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffe879"))

func _draw_stat(font: Font, label: String, value: String, at: Vector2) -> void:
	draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.48, 0.67, 0.89))
	draw_string(font, at + Vector2(0, 28), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color.WHITE)

func _draw_character_card(font: Font, character_index: int, summary: Dictionary) -> void:
	var character: Dictionary = GameManager.CHARACTERS[character_index]
	var accent: Color = character.primary_color
	var x := 32.0 + character_index * 159.0
	draw_rect(Rect2(x, 505, 145, 145), Color(accent, 0.075))
	draw_line(Vector2(x, 505), Vector2(x + 145, 505), accent, 2.0)
	draw_string(font, Vector2(x + 9, 533), String(character.name), HORIZONTAL_ALIGNMENT_LEFT, 127, 13, accent)
	draw_string(font, Vector2(x + 9, 565), "%s  %02d" % [GameText.text("archive_runs"), int(summary.runs)], HORIZONTAL_ALIGNMENT_LEFT, 127, 11, Color(0.72, 0.84, 0.97))
	draw_string(font, Vector2(x + 9, 593), "%s  %4.1f%%" % [GameText.text("clear_rate"), float(summary.clear_rate) * 100.0], HORIZONTAL_ALIGNMENT_LEFT, 127, 11, Color.WHITE)
	draw_string(font, Vector2(x + 9, 621), "%s  %.2f" % [GameText.text("average_losses"), float(summary.average_deaths)], HORIZONTAL_ALIGNMENT_LEFT, 127, 11, Color(0.72, 0.84, 0.97))

func _draw_recent_runs(font: Font, difficulty_id: String) -> void:
	draw_string(font, Vector2(36, 687), GameText.text("recent_runs"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a8f8ff"))
	var recent: Array[Dictionary] = []
	var history := _history()
	for index in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[index]
		if String(entry.get("difficulty", "normal")) == difficulty_id:
			recent.append(entry)
			if recent.size() == 3:
				break
	if recent.is_empty():
		draw_string(font, Vector2(36, 735), GameText.text("no_run_data"), HORIZONTAL_ALIGNMENT_CENTER, 468, 13, Color(0.48, 0.61, 0.78))
		return
	for i in recent.size():
		var entry: Dictionary = recent[i]
		var character_index := clampi(int(entry.get("character", 0)), 0, GameManager.CHARACTERS.size() - 1)
		var state := GameText.text("cleared_short") if bool(entry.get("cleared", false)) else GameText.text("failed_short")
		if bool(entry.get("assisted", false)):
			state += " / " + GameText.text("assisted_short")
		var line := "%s  //  %s  //  %s  //  %09d" % [
			String(GameManager.CHARACTERS[character_index].name), state,
			_format_time(float(entry.get("clear_time", 0.0))), int(entry.get("total_score", 0))
		]
		draw_rect(Rect2(34, 703 + i * 36, 472, 30), Color(0.025, 0.06, 0.13, 0.78))
		draw_string(font, Vector2(46, 724 + i * 36), line, HORIZONTAL_ALIGNMENT_LEFT, 448, 11, Color(0.74, 0.86, 0.98))

func _history() -> Array:
	return preview_history if use_preview_data else SaveManager.run_history

func _summary(difficulty_id: String, character_index: int = -1) -> Dictionary:
	return SaveManager.summarize_runs(_history(), difficulty_id, character_index)

func _format_time(value: float) -> String:
	if value <= 0.0:
		return "--:--"
	return "%02d:%02d" % [int(value) / 60, int(value) % 60]
