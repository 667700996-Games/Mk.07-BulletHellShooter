class_name DifficultySelect
extends Control

signal difficulty_confirmed(difficulty_id: String)
signal cancelled

const VIEW_SIZE := Vector2(540.0, 960.0)
const CARD_RECTS := [
	Rect2(40.0, 230.0, 460.0, 142.0),
	Rect2(40.0, 392.0, 460.0, 142.0),
	Rect2(40.0, 554.0, 460.0, 142.0)
]
const CARD_COLORS := [Color("66e6ff"), Color("ffe579"), Color("ff668f")]

var stage_data: StageData
var practice_mode := false
var difficulty_id := ""
var selected_index := 1
var time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if stage_data == null:
		stage_data = StageManager.default_stage()
	if not GameManager.DIFFICULTY_ORDER.has(difficulty_id):
		difficulty_id = SaveManager.selected_difficulty if GameManager.DIFFICULTY_ORDER.has(SaveManager.selected_difficulty) else "normal"
	selected_index = GameManager.DIFFICULTY_ORDER.find(difficulty_id)
	AudioManager.play_music("title")
	queue_redraw()


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
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_change_selection(1)
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	for index in CARD_RECTS.size():
		if CARD_RECTS[index].has_point(event.position):
			_select_index(index)
			if event.double_click:
				_confirm_selection()
			accept_event()
			return


func _change_selection(direction: int) -> void:
	_select_index(wrapi(selected_index + direction, 0, GameManager.DIFFICULTY_ORDER.size()))


func _select_index(index: int) -> void:
	selected_index = clampi(index, 0, GameManager.DIFFICULTY_ORDER.size() - 1)
	difficulty_id = String(GameManager.DIFFICULTY_ORDER[selected_index])
	AudioManager.play_sfx("ui_move", 0.88 + selected_index * 0.07, -2.0)
	queue_redraw()


func _confirm_selection() -> void:
	difficulty_id = String(GameManager.DIFFICULTY_ORDER[selected_index])
	AudioManager.play_sfx("ui_confirm", 1.0, 0.0)
	difficulty_confirmed.emit(difficulty_id)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("05091e"))
	_draw_backdrop()
	draw_string(font, Vector2(0, 70), GameText.text("select_difficulty"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 29, Color("ffe579"))
	var context_name := GameText.text(stage_data.final_boss_name_key) if practice_mode else GameText.text(stage_data.title_key)
	var context_key := "difficulty_practice_sub" if practice_mode else "difficulty_campaign_sub"
	draw_string(font, Vector2(0, 103), GameText.text(context_key) % context_name, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 12, Color(0.55, 0.72, 0.91))
	draw_line(Vector2(34, 132), Vector2(506, 132), Color(0.95, 0.79, 0.32, 0.5), 1.0)

	for index in GameManager.DIFFICULTY_ORDER.size():
		_draw_difficulty_card(font, index)

	var selected_id := String(GameManager.DIFFICULTY_ORDER[selected_index])
	draw_string(font, Vector2(0, 750), GameText.text("difficulty_selected") % GameText.text("difficulty_%s" % selected_id), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 16, CARD_COLORS[selected_index])
	draw_string(font, Vector2(0, 782), GameText.text("difficulty_%s_desc" % selected_id), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 13, Color.WHITE)
	draw_string(font, Vector2(0, 868), GameText.text("difficulty_select_controls"), HORIZONTAL_ALIGNMENT_CENTER, 270, 12, Color(0.61, 0.77, 0.94))
	draw_string(font, Vector2(270, 868), "%s / A   %s" % [SaveManager.keyboard_binding_label("primary"), GameText.text("confirm")], HORIZONTAL_ALIGNMENT_CENTER, 270, 12, Color("91f7ff"))
	draw_string(font, Vector2(0, 916), "ESC / B   %s" % GameText.text("back"), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 11, Color(0.52, 0.64, 0.82))


func _draw_backdrop() -> void:
	for line_index in 14:
		var y := fmod(line_index * 84.0 + time * 21.0, 1040.0) - 70.0
		draw_line(Vector2(-80.0, y), Vector2(620.0, y - 150.0), Color(0.22, 0.48, 0.86, 0.07), 1.0)
	for ring in 5:
		var radius := 120.0 + ring * 58.0 + sin(time * 0.75 + ring) * 3.0
		draw_arc(Vector2(270.0, 470.0), radius, -0.4 - time * 0.015, 2.7 - time * 0.015, 72, Color(0.85, 0.45, 1.0, 0.04), 1.0)


func _draw_difficulty_card(font: Font, index: int) -> void:
	var difficulty_id := String(GameManager.DIFFICULTY_ORDER[index])
	var rect: Rect2 = CARD_RECTS[index]
	var color: Color = CARD_COLORS[index]
	var active := index == selected_index
	var pulse := 0.88 + sin(time * 3.2) * 0.12 if active else 0.28
	draw_style_box(_card_box(color, active, pulse), rect)
	draw_string(font, rect.position + Vector2(22, 29), "%02d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, 42, 12, Color(color, 0.8))
	draw_string(font, rect.position + Vector2(72, 42), GameText.text("difficulty_%s" % difficulty_id), HORIZONTAL_ALIGNMENT_LEFT, 340, 24, color if active else Color(color, 0.75))
	draw_string(font, rect.position + Vector2(72, 76), GameText.text("difficulty_%s_desc" % difficulty_id), HORIZONTAL_ALIGNMENT_LEFT, 350, 14, Color.WHITE if active else Color(0.62, 0.7, 0.82))
	var marker := "◆" if active else "◇"
	draw_string(font, rect.position + Vector2(414, 83), marker, HORIZONTAL_ALIGNMENT_CENTER, 24, 18, color)


func _card_box(color: Color, active: bool, pulse: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color, 0.16 if active else 0.045)
	box.border_color = Color(color, pulse)
	box.set_border_width_all(3 if active else 1)
	box.corner_radius_top_left = 12
	box.corner_radius_top_right = 12
	box.corner_radius_bottom_left = 12
	box.corner_radius_bottom_right = 12
	return box
