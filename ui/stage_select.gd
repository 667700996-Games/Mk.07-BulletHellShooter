class_name StageSelect
extends Control

signal stage_confirmed(stage_id: String)
signal cancelled

const VIEW_SIZE := Vector2(540.0, 960.0)
const LIST_RECT := Rect2(26.0, 166.0, 488.0, 382.0)
const CARD_HEIGHT := 94.0
const ACCENT := Color("43e8ff")
const LOCKED_COLOR := Color("5a6883")

var stage_ids := PackedStringArray()
var stage_buttons: Array[Button] = []
var selected_index := -1
var difficulty_id := "normal"
var time := 0.0
var locked_feedback_time := 0.0
var stage_list: ScrollContainer
var card_column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	difficulty_id = String(SaveManager.selected_difficulty)
	if not GameManager.DIFFICULTY_ORDER.has(difficulty_id):
		difficulty_id = "normal"
	stage_ids = StageManager.stage_ids()
	_build_stage_list()
	_select_first_unlocked()
	AudioManager.play_music("title")


func _build_stage_list() -> void:
	stage_list = ScrollContainer.new()
	stage_list.position = LIST_RECT.position
	stage_list.size = LIST_RECT.size
	stage_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage_list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stage_list.follow_focus = true
	stage_list.clip_contents = true
	stage_list.add_theme_stylebox_override("panel", _box(Color(0.01, 0.025, 0.075, 0.72), Color(0.13, 0.31, 0.5, 0.45), 1, 10))
	add_child(stage_list)

	card_column = VBoxContainer.new()
	card_column.custom_minimum_size = Vector2(LIST_RECT.size.x - 18.0, 0.0)
	card_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_column.add_theme_constant_override("separation", 10)
	stage_list.add_child(card_column)

	for index in stage_ids.size():
		var stage_id := String(stage_ids[index])
		var data := StageManager.stage(stage_id)
		if data == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(LIST_RECT.size.x - 20.0, CARD_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(_select_index.bind(index))
		button.gui_input.connect(_on_stage_card_gui_input.bind(index))
		card_column.add_child(button)
		stage_buttons.append(button)
	_refresh_stage_cards()


func _select_first_unlocked() -> void:
	for index in stage_ids.size():
		if SaveManager.is_stage_unlocked(String(stage_ids[index])):
			_select_index(index, false)
			return
	if not stage_ids.is_empty():
		_select_index(0, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
		_change_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
		_change_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary") or event.is_action_pressed("ui_accept"):
		_confirm_selection()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		AudioManager.play_sfx("ui_move", 0.76, -3.0)
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_change_selection(-1)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_change_selection(1)
		accept_event()


func _on_stage_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		_select_index(index, false)
		_confirm_selection()
		accept_event()


func _change_selection(direction: int) -> void:
	if stage_ids.is_empty():
		return
	var next_index := 0 if selected_index < 0 else wrapi(selected_index + direction, 0, stage_ids.size())
	_select_index(next_index)


func _select_index(index: int, play_sound: bool = true) -> void:
	if index < 0 or index >= stage_ids.size():
		return
	selected_index = index
	if play_sound:
		AudioManager.play_sfx("ui_move", 0.94 + float(index % 5) * 0.035, -3.0)
	_refresh_stage_cards()
	queue_redraw()
	if index < stage_buttons.size() and stage_list != null:
		stage_list.ensure_control_visible.call_deferred(stage_buttons[index])


func _confirm_selection() -> void:
	if selected_index < 0 or selected_index >= stage_ids.size():
		return
	var stage_id := String(stage_ids[selected_index])
	if not SaveManager.is_stage_unlocked(stage_id):
		locked_feedback_time = 0.55
		AudioManager.play_sfx("warning", 0.88, -3.0)
		queue_redraw()
		return
	AudioManager.play_sfx("ui_confirm", 1.0, 0.0)
	stage_confirmed.emit(stage_id)


func _refresh_stage_cards() -> void:
	for index in stage_buttons.size():
		var button := stage_buttons[index]
		var stage_id := String(stage_ids[index])
		var data := StageManager.stage(stage_id)
		if data == null:
			continue
		var unlocked := SaveManager.is_stage_unlocked(stage_id)
		var active := index == selected_index
		var accent := ACCENT if unlocked else LOCKED_COLOR
		var marker := "◆" if active else "◇"
		var state := "" if unlocked else "  [ %s ]" % GameText.text("locked")
		button.text = "%s  %s %02d  //  %s%s\n       %s" % [
			marker, GameText.text("stage_label"), index + 1,
			GameText.text(data.title_key), state, GameText.text(data.subtitle_key)
		]
		button.add_theme_color_override("font_color", Color(0.82, 0.91, 1.0) if unlocked else Color(0.43, 0.49, 0.61))
		button.add_theme_color_override("font_hover_color", Color.WHITE if unlocked else Color(0.62, 0.67, 0.76))
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _card_box(accent, active, unlocked, false))
		button.add_theme_stylebox_override("hover", _card_box(accent, true, unlocked, true))
		button.add_theme_stylebox_override("pressed", _card_box(accent, true, unlocked, true))


func _process(delta: float) -> void:
	time += delta
	locked_feedback_time = maxf(0.0, locked_feedback_time - delta)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("04091c"))
	_draw_backdrop()
	draw_string(font, Vector2(0, 68), GameText.text("select_operation_route"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 29, Color("8cf6ff"))
	draw_string(font, Vector2(0, 100), GameText.text("campaign_network"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 11, Color(0.48, 0.66, 0.86))
	_draw_catalog_progress(font)
	_draw_selected_stage(font)
	_draw_control_hints(font)


func _draw_backdrop() -> void:
	for band in 16:
		var shade := Color("071536").lerp(Color("18092c"), float(band) / 15.0)
		shade.a = 0.24
		draw_rect(Rect2(0.0, band * 60.0, VIEW_SIZE.x, 62.0), shade)
	for line_index in 13:
		var y := fmod(line_index * 91.0 + time * 24.0, 1050.0) - 80.0
		draw_line(Vector2(-60.0, y), Vector2(600.0, y - 190.0), Color(0.12, 0.58, 0.88, 0.075), 1.0)
	for ring in 5:
		var radius := 155.0 + ring * 58.0 + sin(time * 0.6 + ring) * 3.0
		draw_arc(Vector2(270.0, 405.0), radius, -0.55 + time * 0.018, 2.6 + time * 0.018, 72, Color(0.25, 0.78, 1.0, 0.045), 1.0)
	draw_line(Vector2(26.0, 127.0), Vector2(514.0, 127.0), Color(ACCENT, 0.45), 1.0)


func _draw_catalog_progress(font: Font) -> void:
	if stage_ids.is_empty():
		draw_string(font, Vector2(0, 145), GameText.text("no_routes_available"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 12, Color("ff7192"))
		return
	var unlocked_count := 0
	for stage_id in stage_ids:
		unlocked_count += int(SaveManager.is_stage_unlocked(String(stage_id)))
	var progress := "%s  %02d / %02d" % [GameText.text("routes_online"), unlocked_count, stage_ids.size()]
	draw_string(font, Vector2(30, 147), progress, HORIZONTAL_ALIGNMENT_LEFT, 480, 11, Color(0.53, 0.73, 0.92))


func _draw_selected_stage(font: Font) -> void:
	var panel_rect := Rect2(28.0, 568.0, 484.0, 268.0)
	draw_style_box(_box(Color(0.012, 0.026, 0.075, 0.95), Color(ACCENT, 0.62), 2, 14), panel_rect)
	if selected_index < 0 or selected_index >= stage_ids.size():
		draw_string(font, Vector2(0, 700), GameText.text("catalog_offline"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 18, Color("ff7192"))
		return
	var stage_id := String(stage_ids[selected_index])
	var data := StageManager.stage(stage_id)
	if data == null:
		return
	var unlocked := SaveManager.is_stage_unlocked(stage_id)
	var route_time := data.timeline.boss_spawn_time if data.timeline != null else 0.0
	var summary: Dictionary = SaveManager.run_summary(difficulty_id, -1, stage_id)
	var best_score := SaveManager.high_score_for(difficulty_id, stage_id)
	var headline_color := ACCENT if unlocked else LOCKED_COLOR
	draw_line(Vector2(28.0, 568.0), Vector2(512.0, 568.0), headline_color, 3.0)
	draw_string(font, Vector2(48, 606), "%s %02d" % [GameText.text("stage_label"), selected_index + 1], HORIZONTAL_ALIGNMENT_LEFT, 150, 13, headline_color)
	draw_string(font, Vector2(48, 641), GameText.text(data.title_key), HORIZONTAL_ALIGNMENT_LEFT, 444, 24, Color.WHITE if unlocked else Color(0.5, 0.56, 0.67))
	draw_string(font, Vector2(48, 666), GameText.text(data.subtitle_key), HORIZONTAL_ALIGNMENT_LEFT, 444, 11, Color(0.54, 0.72, 0.91) if unlocked else LOCKED_COLOR)

	var difficulty_label := GameText.text("difficulty_%s" % difficulty_id)
	draw_string(font, Vector2(48, 701), GameText.text("route_time"), HORIZONTAL_ALIGNMENT_LEFT, 132, 10, Color(0.47, 0.65, 0.84))
	draw_string(font, Vector2(196, 701), GameText.text("difficulty_label"), HORIZONTAL_ALIGNMENT_LEFT, 132, 10, Color(0.47, 0.65, 0.84))
	draw_string(font, Vector2(348, 701), GameText.text("best_score"), HORIZONTAL_ALIGNMENT_LEFT, 132, 10, Color(0.47, 0.65, 0.84))
	draw_string(font, Vector2(48, 727), _format_time(route_time), HORIZONTAL_ALIGNMENT_LEFT, 132, 18, Color.WHITE)
	draw_string(font, Vector2(196, 727), difficulty_label, HORIZONTAL_ALIGNMENT_LEFT, 132, 18, Color("ffe879"))
	draw_string(font, Vector2(348, 727), "%09d" % best_score, HORIZONTAL_ALIGNMENT_LEFT, 132, 18, Color("ffe879"))

	draw_line(Vector2(48, 750), Vector2(492, 750), Color(0.18, 0.35, 0.56, 0.62), 1.0)
	draw_string(font, Vector2(48, 778), "%s  %02d" % [GameText.text("archive_runs"), int(summary.get("runs", 0))], HORIZONTAL_ALIGNMENT_LEFT, 135, 12, Color(0.76, 0.87, 0.98))
	draw_string(font, Vector2(188, 778), "%s  %02d" % [GameText.text("archive_clears"), int(summary.get("clears", 0))], HORIZONTAL_ALIGNMENT_LEFT, 135, 12, Color(0.76, 0.87, 0.98))
	draw_string(font, Vector2(332, 778), "%s  %5.1f%%" % [GameText.text("clear_rate"), float(summary.get("clear_rate", 0.0)) * 100.0], HORIZONTAL_ALIGNMENT_LEFT, 160, 12, Color(0.76, 0.87, 0.98))
	var status_text := GameText.text("route_ready") if unlocked else GameText.text("route_unlock_previous")
	var status_color := Color("7dffb2") if unlocked else Color("ff9dbb")
	if not unlocked and locked_feedback_time > 0.0:
		status_text = GameText.text("route_access_denied")
		status_color = Color("ff5d91")
	draw_string(font, Vector2(48, 814), status_text, HORIZONTAL_ALIGNMENT_CENTER, 444, 11, status_color)


func _draw_control_hints(font: Font) -> void:
	var confirm_key := SaveManager.keyboard_binding_label("primary")
	draw_string(font, Vector2(0, 875), "◀ / ▶   ▲ / ▼   %s" % GameText.text("select_route"), HORIZONTAL_ALIGNMENT_CENTER, 270, 12, Color(0.61, 0.77, 0.94))
	draw_string(font, Vector2(270, 875), "%s / A   %s" % [confirm_key, GameText.text("deploy")], HORIZONTAL_ALIGNMENT_CENTER, 270, 12, Color("91f7ff"))
	draw_string(font, Vector2(0, 916), "ESC / B   %s" % GameText.text("back"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 11, Color(0.52, 0.64, 0.82))


func _format_time(value: float) -> String:
	if value <= 0.0:
		return "--:--"
	var total_seconds := int(ceil(value))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]




func _card_box(accent: Color, active: bool, unlocked: bool, hovered: bool) -> StyleBoxFlat:
	var alpha := 0.18 if active else 0.075
	if hovered:
		alpha += 0.055
	if not unlocked:
		alpha *= 0.52
	return _box(Color(accent, alpha), Color(accent, 0.95 if active else 0.4), 2 if active else 1, 8)


func _box(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box
