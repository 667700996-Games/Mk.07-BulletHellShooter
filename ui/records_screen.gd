class_name RecordsScreen
extends Control

signal closed
signal replay_requested(replay_id: String)

var difficulty_index := 1
var stage_index := 0
var stage_ids := PackedStringArray()
var time := 0.0
var export_status := ""
var export_status_time := 0.0
var export_status_success := false
var left_button: Button
var right_button: Button
var stage_left_button: Button
var stage_right_button: Button
var replay_button: Button
var replay_previous_button: Button
var replay_next_button: Button
var replay_pin_button: Button
var export_button: Button
var diagnostics_export_button: Button
var back_button: Button
var replay_index := 0
var replay_entries: Array[Dictionary] = []
var use_preview_data := false
var preview_difficulty := "normal"
var preview_stage_id := ""
var preview_history: Array[Dictionary] = []

func setup_preview(entries: Array[Dictionary], difficulty_id: String = "normal", stage_id: String = "") -> void:
	use_preview_data = true
	preview_history = entries.duplicate(true)
	preview_difficulty = difficulty_id if GameManager.DIFFICULTY_ORDER.has(difficulty_id) else "normal"
	preview_stage_id = stage_id
	if preview_stage_id.is_empty() and not preview_history.is_empty():
		preview_stage_id = String(preview_history[0].get("stage_id", StageManager.DEFAULT_STAGE_ID))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var initial_difficulty := preview_difficulty if use_preview_data else SaveManager.selected_difficulty
	difficulty_index = maxi(0, GameManager.DIFFICULTY_ORDER.find(initial_difficulty))
	stage_ids = StageManager.stage_ids()
	var initial_stage_id := preview_stage_id
	if initial_stage_id.is_empty() and StageManager.has_stage(StageManager.active_stage):
		initial_stage_id = StageManager.active_stage
	if initial_stage_id.is_empty() or not stage_ids.has(initial_stage_id):
		initial_stage_id = StageManager.DEFAULT_STAGE_ID
	stage_index = maxi(0, stage_ids.find(initial_stage_id))
	stage_left_button = _button("◀", Vector2(48, 113), Vector2(64, 36), Color("a45cff"))
	stage_right_button = _button("▶", Vector2(428, 113), Vector2(64, 36), Color("a45cff"))
	left_button = _button("◀", Vector2(48, 162), Vector2(64, 36), Color("43e8ff"))
	right_button = _button("▶", Vector2(428, 162), Vector2(64, 36), Color("43e8ff"))
	replay_previous_button = _button("◀", Vector2(34, 810), Vector2(52, 40), Color("ff4f9f"))
	replay_button = _button(GameText.text("watch_replay"), Vector2(94, 810), Vector2(292, 40), Color("ff4f9f"))
	replay_next_button = _button("▶", Vector2(394, 810), Vector2(52, 40), Color("ff4f9f"))
	replay_pin_button = _button("☆", Vector2(454, 810), Vector2(52, 40), Color("ffe36d"))
	export_button = _button(GameText.text("export_data"), Vector2(28, 858), Vector2(238, 40), Color("43e8ff"))
	diagnostics_export_button = _button(GameText.text("export_diagnostics"), Vector2(274, 858), Vector2(238, 40), Color("ffe36d"))
	back_button = _button(GameText.text("archive_back"), Vector2(135, 906), Vector2(270, 40), Color("a45cff"))
	stage_left_button.pressed.connect(_cycle_stage.bind(-1))
	stage_right_button.pressed.connect(_cycle_stage.bind(1))
	left_button.pressed.connect(_cycle_difficulty.bind(-1))
	right_button.pressed.connect(_cycle_difficulty.bind(1))
	replay_previous_button.pressed.connect(_cycle_replay.bind(-1))
	replay_button.pressed.connect(_watch_replay)
	replay_next_button.pressed.connect(_cycle_replay.bind(1))
	replay_pin_button.pressed.connect(_toggle_replay_pin)
	export_button.pressed.connect(_export_data)
	diagnostics_export_button.pressed.connect(_export_diagnostics)
	back_button.pressed.connect(_close)
	stage_left_button.focus_neighbor_right = stage_right_button.get_path()
	stage_right_button.focus_neighbor_left = stage_left_button.get_path()
	stage_left_button.focus_neighbor_bottom = left_button.get_path()
	stage_right_button.focus_neighbor_bottom = right_button.get_path()
	left_button.focus_neighbor_right = right_button.get_path()
	right_button.focus_neighbor_left = left_button.get_path()
	left_button.focus_neighbor_top = stage_left_button.get_path()
	right_button.focus_neighbor_top = stage_right_button.get_path()
	replay_previous_button.focus_neighbor_right = replay_button.get_path()
	replay_button.focus_neighbor_left = replay_previous_button.get_path()
	replay_button.focus_neighbor_right = replay_next_button.get_path()
	replay_next_button.focus_neighbor_left = replay_button.get_path()
	replay_next_button.focus_neighbor_right = replay_pin_button.get_path()
	replay_pin_button.focus_neighbor_left = replay_next_button.get_path()
	replay_previous_button.focus_neighbor_bottom = export_button.get_path()
	replay_button.focus_neighbor_bottom = export_button.get_path()
	replay_next_button.focus_neighbor_bottom = diagnostics_export_button.get_path()
	replay_pin_button.focus_neighbor_bottom = diagnostics_export_button.get_path()
	export_button.focus_neighbor_left = diagnostics_export_button.get_path()
	export_button.focus_neighbor_right = diagnostics_export_button.get_path()
	export_button.focus_neighbor_top = replay_button.get_path()
	export_button.focus_neighbor_bottom = back_button.get_path()
	diagnostics_export_button.focus_neighbor_left = export_button.get_path()
	diagnostics_export_button.focus_neighbor_right = export_button.get_path()
	diagnostics_export_button.focus_neighbor_top = replay_button.get_path()
	diagnostics_export_button.focus_neighbor_bottom = back_button.get_path()
	back_button.focus_neighbor_top = diagnostics_export_button.get_path()
	_refresh_replay_entries()
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
	_refresh_replay_entries()
	AudioManager.play_sfx("ui_move", 1.08, -3.0)
	queue_redraw()

func _cycle_stage(direction: int) -> void:
	if stage_ids.size() <= 1:
		return
	stage_index = wrapi(stage_index + direction, 0, stage_ids.size())
	replay_index = 0
	_refresh_replay_entries()
	AudioManager.play_sfx("ui_move", 0.92, -3.0)
	queue_redraw()

func _refresh_replay_entries(preferred_id: String = "") -> void:
	replay_entries.clear()
	if not use_preview_data:
		var difficulty_id: String = GameManager.DIFFICULTY_ORDER[difficulty_index]
		replay_entries.assign(ReplayManager.list_replays(difficulty_id, _selected_stage_id()))
	if not preferred_id.is_empty():
		for i in replay_entries.size():
			if String(replay_entries[i].get("id", "")) == preferred_id:
				replay_index = i
				break
	replay_index = clampi(replay_index, 0, maxi(0, replay_entries.size() - 1))
	_refresh_replay_controls()

func _refresh_replay_controls() -> void:
	if replay_button == null:
		return
	var has_entries := not replay_entries.is_empty()
	var compatible := has_entries and bool(replay_entries[replay_index].get("compatible", true))
	replay_button.disabled = not compatible
	replay_previous_button.disabled = replay_entries.size() <= 1
	replay_next_button.disabled = replay_entries.size() <= 1
	replay_pin_button.disabled = not has_entries
	if has_entries:
		replay_button.text = GameText.text("watch_selected_replay") % [replay_index + 1, replay_entries.size()]
		replay_pin_button.text = "★" if bool(replay_entries[replay_index].get("pinned", false)) else "☆"
	else:
		replay_button.text = GameText.text("replay_empty")
		replay_pin_button.text = "☆"
	queue_redraw()

func _cycle_replay(direction: int) -> void:
	if replay_entries.size() <= 1:
		return
	replay_index = wrapi(replay_index + direction, 0, replay_entries.size())
	_refresh_replay_controls()
	AudioManager.play_sfx("ui_move", 1.12, -3.0)

func _toggle_replay_pin() -> void:
	if replay_entries.is_empty():
		return
	var entry := replay_entries[replay_index]
	var replay_id := String(entry.get("id", ""))
	if replay_id.is_empty():
		return
	var pinned := not bool(entry.get("pinned", false))
	if ReplayManager.set_pinned(replay_id, pinned):
		AudioManager.play_sfx("ui_confirm", 1.1 if pinned else 0.9, -2.0)
		_refresh_replay_entries(replay_id)
	else:
		AudioManager.play_sfx("warning", 1.0, -4.0)

func _export_data() -> void:
	var success := SaveManager.export_playtest_data()
	export_status = GameText.text("export_success") if success else GameText.text("export_failed")
	export_status_success = success
	export_status_time = 4.0
	AudioManager.play_sfx("ui_confirm" if success else "warning", 1.0, -2.0)
	queue_redraw()


func _export_diagnostics() -> void:
	var success := SessionDiagnostics.export_diagnostics()
	export_status = GameText.text("diagnostics_export_success") if success else GameText.text("export_failed")
	export_status_success = success
	export_status_time = 4.0
	AudioManager.play_sfx("ui_confirm" if success else "warning", 1.0, -2.0)
	queue_redraw()

func _watch_replay() -> void:
	if replay_button.disabled or replay_entries.is_empty():
		return
	var replay_id := String(replay_entries[replay_index].get("id", ""))
	if replay_id.is_empty():
		return
	AudioManager.play_sfx("ui_confirm", 1.0, -2.0)
	replay_requested.emit(replay_id)

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
	elif event.is_action_pressed("move_up"):
		_cycle_stage(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_cycle_stage(1)
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
	draw_string(font, Vector2(0, 61), GameText.text("combat_archive"), HORIZONTAL_ALIGNMENT_CENTER, 540, 27, Color("75f3ff"))
	draw_string(font, Vector2(0, 89), GameText.text("archive_sub"), HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color(0.48, 0.65, 0.86))
	_draw_filter_header(font, difficulty_id)

	_draw_summary_panel(font, summary)
	draw_string(font, Vector2(36, 489), "%s // %s" % [GameText.text("combat_archive"), GameText.text("vector_breakdown")], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.50, 0.70, 0.91))
	for character_index in GameManager.CHARACTERS.size():
		_draw_character_card(font, character_index, _summary(difficulty_id, character_index))
	_draw_recent_runs(font, difficulty_id, _selected_stage_id())
	if not export_status.is_empty():
		draw_string(font, Vector2(0, 802), export_status, HORIZONTAL_ALIGNMENT_CENTER, 540, 11, Color("7dffb2") if export_status_success else Color("ff7192"))
	elif SessionDiagnostics.prior_session_unclean:
		draw_string(font, Vector2(18, 802), GameText.text("diagnostics_unclean_notice"), HORIZONTAL_ALIGNMENT_CENTER, 504, 10, Color("ffe36d"))
	elif SessionDiagnostics.journal_reset_after_corruption:
		draw_string(font, Vector2(18, 802), GameText.text("diagnostics_reset_notice"), HORIZONTAL_ALIGNMENT_CENTER, 504, 10, Color("ff9fca"))
	else:
		_draw_replay_summary(font)

func _draw_filter_header(font: Font, difficulty_id: String) -> void:
	var data := StageManager.stage(_selected_stage_id())
	var stage_title := _selected_stage_id()
	if data != null:
		stage_title = GameText.text(data.title_key)
	var unlocked := SaveManager.is_stage_unlocked(_selected_stage_id())
	var stage_color := Color.WHITE if unlocked else Color(0.53, 0.58, 0.70)
	var lock_suffix := "" if unlocked else "  //  %s" % GameText.text("locked")
	draw_rect(Rect2(38, 108, 464, 44), Color(0.035, 0.035, 0.13, 0.94))
	draw_line(Vector2(38, 108), Vector2(502, 108), Color("a45cff"), 2.0)
	draw_string(font, Vector2(118, 137), "%s %02d  //  %s%s" % [GameText.text("stage_label"), stage_index + 1, stage_title, lock_suffix], HORIZONTAL_ALIGNMENT_CENTER, 304, 14, stage_color)
	draw_rect(Rect2(38, 157, 464, 44), Color(0.02, 0.07, 0.16, 0.92))
	draw_line(Vector2(38, 157), Vector2(502, 157), Color("43e8ff"), 2.0)
	draw_string(font, Vector2(118, 187), GameText.text("difficulty_%s" % difficulty_id), HORIZONTAL_ALIGNMENT_CENTER, 304, 17, Color.WHITE)

func _draw_replay_summary(font: Font) -> void:
	if replay_entries.is_empty():
		draw_string(font, Vector2(0, 802), GameText.text("replay_empty"), HORIZONTAL_ALIGNMENT_CENTER, 540, 10, Color(0.48, 0.61, 0.78))
		return
	var entry := replay_entries[replay_index]
	var replay: Dictionary = entry.get("replay", entry)
	var expected: Dictionary = replay.get("expected", {})
	var character_index := clampi(int(replay.get("character", 0)), 0, GameManager.CHARACTERS.size() - 1)
	var difficulty_id := String(replay.get("difficulty", "normal"))
	var state := GameText.text("cleared_short") if bool(expected.get("cleared", false)) else GameText.text("failed_short")
	if bool(replay.get("assisted", false)):
		state += " / " + GameText.text("assisted_short")
	if bool(entry.get("pinned", false)):
		state += " / " + GameText.text("replay_pinned")
	if not bool(entry.get("compatible", true)):
		state = GameText.text("replay_incompatible")
	var line := "%s // %s // %s // %09d" % [
		String(GameManager.CHARACTERS[character_index].name),
		GameText.text("difficulty_%s" % difficulty_id), state,
		int(expected.get("total_score", 0))
	]
	draw_string(font, Vector2(22, 802), "%s  %s" % [GameText.text("replay_vault"), line], HORIZONTAL_ALIGNMENT_CENTER, 496, 10, Color("ffb2d7"))

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

func _draw_recent_runs(font: Font, difficulty_id: String, stage_id: String = "") -> void:
	draw_string(font, Vector2(36, 674), GameText.text("recent_runs"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a8f8ff"))
	var recent: Array[Dictionary] = []
	var history := _history()
	for index in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[index]
		if String(entry.get("difficulty", "normal")) == difficulty_id:
			if not stage_id.is_empty() and String(entry.get("stage_id", StageManager.DEFAULT_STAGE_ID)) != stage_id:
				continue
			recent.append(entry)
			if recent.size() == 3:
				break
	if recent.is_empty():
		draw_string(font, Vector2(36, 718), GameText.text("no_run_data"), HORIZONTAL_ALIGNMENT_CENTER, 468, 13, Color(0.48, 0.61, 0.78))
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
		draw_rect(Rect2(34, 690 + i * 32, 472, 27), Color(0.025, 0.06, 0.13, 0.78))
		draw_string(font, Vector2(46, 709 + i * 32), line, HORIZONTAL_ALIGNMENT_LEFT, 448, 11, Color(0.74, 0.86, 0.98))

func _history() -> Array:
	return preview_history if use_preview_data else SaveManager.run_history

func _summary(difficulty_id: String, character_index: int = -1) -> Dictionary:
	var summary: Dictionary
	if use_preview_data:
		summary = SaveManager.summarize_runs(_history(), difficulty_id, character_index, _selected_stage_id())
	else:
		summary = SaveManager.run_summary(difficulty_id, character_index, _selected_stage_id())
		summary = summary.duplicate(true)
		summary["best_score"] = SaveManager.high_score_for(difficulty_id, _selected_stage_id())
	return summary

func _selected_stage_id() -> String:
	if stage_index >= 0 and stage_index < stage_ids.size():
		return String(stage_ids[stage_index])
	return StageManager.DEFAULT_STAGE_ID


func _format_time(value: float) -> String:
	if value <= 0.0:
		return "--:--"
	return "%02d:%02d" % [int(value) / 60, int(value) % 60]
