class_name OperationBriefing
extends Control

## Data-driven campaign bridge shown after vector selection and before combat.
##
## Integration contract:
##   screen.setup(stage_data, character_index, difficulty_id)
##   screen.completed.connect(_on_operation_briefing_completed)
##   screen.cancelled.connect(_show_character_select.bind(false))
##
## `completed` returns the exact launch context supplied to setup. The final
## boolean records whether the player used Skip, allowing analytics to measure
## briefing engagement without changing campaign behavior.

signal completed(character_index: int, difficulty_id: String, stage_id: String, skipped: bool)
signal cancelled

const VIEW_SIZE := Vector2(540, 960)
const SITUATION_PANEL_RECT := Rect2(32, 178, 476, 122)
const OBJECTIVE_PANEL_RECT := Rect2(32, 311, 476, 111)
const MEDAL_PANEL_RECT := Rect2(32, 433, 476, 138)
const TRANSMISSION_PANEL_RECT := Rect2(32, 582, 476, 134)
const MEDAL_ACCENT := Color("ffbf5a")
const PORTRAIT_PATHS := [
	"res://assets/characters/kira_voss_keyart.png",
	"res://assets/characters/dae_ryu_keyart.png",
	"res://assets/characters/mina_zero_keyart.png"
]

var stage_data: StageData
var selected_character := 0
var difficulty_id := "normal"
var character_art: Texture2D
var continue_button: Button
var skip_button: Button
var medal_goal_rows: Array[Dictionary] = []
var medal_goal_labels: Array[Label] = []
var motion_time := 0.0
var motion_strength := 0.0
var flash_strength := 0.0
var _closing := false


func setup(data: StageData, character_index: int, selected_difficulty_id: String) -> void:
	stage_data = data
	selected_character = clampi(character_index, 0, PORTRAIT_PATHS.size() - 1)
	difficulty_id = selected_difficulty_id if GameManager.DIFFICULTY_ORDER.has(selected_difficulty_id) else "normal"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	if stage_data == null:
		stage_data = StageManager.default_stage()
	character_art = load(PORTRAIT_PATHS[selected_character]) as Texture2D
	_refresh_effect_profile()
	_build_copy()
	_build_actions()
	queue_redraw()


func _refresh_effect_profile() -> void:
	motion_strength = clampf(float(SaveManager.settings.get("shake", 0.85)), 0.0, 1.0)
	flash_strength = clampf(float(SaveManager.settings.get("flash", 0.85)), 0.0, 1.0)


func _build_copy() -> void:
	_add_label(GameText.text(stage_data.briefing_eyebrow_key), Rect2(34, 40, 472, 22), 11, Color(stage_data.briefing_accent, 0.86))
	_add_label(GameText.text("operation_briefing"), Rect2(34, 68, 472, 42), 29, Color.WHITE)
	_add_label(GameText.text(stage_data.title_key), Rect2(34, 111, 472, 24), 15, Color(stage_data.briefing_accent, 0.96))
	_add_label(
		GameText.text("briefing_difficulty") % GameText.text("difficulty_%s" % difficulty_id),
		Rect2(34, 139, 472, 20), 10, Color(0.54, 0.68, 0.86)
	)

	_add_label(GameText.text("briefing_situation"), Rect2(48, 189, 444, 20), 11, Color(stage_data.briefing_accent, 0.92))
	_add_label(GameText.text(stage_data.briefing_situation_key), Rect2(48, 215, 444, 73), 13, Color(0.82, 0.89, 0.98), true)

	_add_label(GameText.text("briefing_objective"), Rect2(48, 322, 444, 20), 11, Color("ffe579"))
	_add_label(GameText.text(stage_data.briefing_objective_key), Rect2(48, 348, 444, 62), 13, Color(0.91, 0.94, 1.0), true)

	_build_medal_goals()

	_add_label(GameText.text("briefing_transmission"), Rect2(48, 593, 444, 20), 11, Color(stage_data.briefing_accent, 0.94))
	_add_label(GameText.text(stage_data.briefing_transmission_source_key), Rect2(70, 618, 400, 18), 10, Color("a9caff"))
	_add_label(GameText.text(stage_data.briefing_transmission_key), Rect2(70, 642, 400, 62), 12, Color(0.82, 0.90, 1.0), true)
	_add_label(GameText.text("risk_route_hint"), Rect2(28, 875, 484, 30), 9, Color("ffe579"), true, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(GameText.text("briefing_cancel_hint"), Rect2(0, 918, VIEW_SIZE.x, 20), 10, Color(0.48, 0.61, 0.79), false, HORIZONTAL_ALIGNMENT_CENTER)


func _build_medal_goals() -> void:
	medal_goal_rows = PerformanceMedalPresenter.briefing_rows()
	medal_goal_labels.clear()
	var heading := _add_label(GameText.text("performance_medals"), Rect2(48, 444, 444, 18), 11, Color(MEDAL_ACCENT, 0.96))
	medal_goal_labels.append(heading)
	for index in medal_goal_rows.size():
		var row: Dictionary = medal_goal_rows[index]
		var row_y := 467.0 + float(index) * 33.0
		var title := _add_label(String(row.title), Rect2(54, row_y, 350, 15), 10, Color(1.0, 0.89, 0.57))
		var condition := _add_label(String(row.description), Rect2(62, row_y + 15.0, 424, 15), 9, Color(0.72, 0.80, 0.91))
		var bonus := _add_label(String(row.bonus_text), Rect2(414, row_y, 72, 15), 10, Color.WHITE, false, HORIZONTAL_ALIGNMENT_RIGHT)
		medal_goal_labels.append_array([title, condition, bonus])


func _build_actions() -> void:
	continue_button = _action_button(GameText.text("briefing_continue"), Vector2(135, 745), stage_data.briefing_accent)
	skip_button = _action_button(GameText.text("briefing_skip"), Vector2(135, 811), Color("64799c"))
	continue_button.pressed.connect(_finish.bind(false))
	skip_button.pressed.connect(_finish.bind(true))
	continue_button.focus_neighbor_bottom = continue_button.get_path_to(skip_button)
	continue_button.focus_next = continue_button.get_path_to(skip_button)
	skip_button.focus_neighbor_top = skip_button.get_path_to(continue_button)
	skip_button.focus_previous = skip_button.get_path_to(continue_button)
	continue_button.grab_focus.call_deferred()


func _add_label(
	value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	wrap := false,
	alignment := HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = value
	# Apply typography before assigning the final rect. Otherwise Label computes
	# its minimum size with the default font and can silently expand past a
	# compact panel when Korean copy is selected.
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _action_button(label: String, position_value: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = label
	button.position = position_value
	button.size = Vector2(270, 52)
	ArcadeUI.style_button(button, accent)
	button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.0, -5.0))
	add_child(button)
	return button


func _process(delta: float) -> void:
	if motion_strength <= 0.001:
		return
	motion_time += delta * lerpf(0.15, 1.0, motion_strength)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _closing:
		return
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		_closing = true
		AudioManager.play_sfx("ui_move", 0.75, -3.0)
		cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary"):
		var focused := get_viewport().gui_get_focus_owner()
		_finish(focused == skip_button)
		get_viewport().set_input_as_handled()


func _finish(skipped: bool) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_sfx("ui_confirm", 1.06 if not skipped else 0.9, -1.0)
	completed.emit(selected_character, difficulty_id, stage_data.stage_id, skipped)


func _draw() -> void:
	var accent := stage_data.briefing_accent if stage_data != null else Color("43e8ff")
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("030716"))
	if character_art != null:
		draw_texture_rect(character_art, Rect2(286, 38, 286, 429), false, Color(0.52, 0.62, 0.84, 0.075 + flash_strength * 0.035))

	var grid_alpha := 0.025 + flash_strength * 0.025
	for row in 16:
		var base_y := 12.0 + row * 64.0
		var drift := fmod(motion_time * 11.0, 64.0) if motion_strength > 0.12 else 0.0
		draw_line(Vector2(0, base_y + drift), Vector2(VIEW_SIZE.x, base_y + drift), Color(accent, grid_alpha), 1.0)
	for column in 10:
		var x := 18.0 + column * 58.0
		draw_line(Vector2(x, 0), Vector2(x - 138.0, VIEW_SIZE.y), Color(accent, grid_alpha * 0.7), 1.0)

	draw_rect(Rect2(24, 28, 492, 139), Color(0.015, 0.035, 0.09, 0.82))
	draw_line(Vector2(24, 167), Vector2(516, 167), Color(accent, 0.9), 2.0)
	_draw_briefing_panel(SITUATION_PANEL_RECT, accent)
	_draw_briefing_panel(OBJECTIVE_PANEL_RECT, Color("ffe579"))
	_draw_briefing_panel(MEDAL_PANEL_RECT, MEDAL_ACCENT)
	_draw_briefing_panel(TRANSMISSION_PANEL_RECT, accent)

	var signal_origin := Vector2(48, 627)
	for index in 7:
		var phase: float = motion_time * 2.2 + float(index) * 0.92
		var height: float = 4.0 + absf(sin(phase)) * (4.0 + flash_strength * 7.0)
		draw_line(signal_origin + Vector2(index * 3.0, -height), signal_origin + Vector2(index * 3.0, height), Color(accent, 0.32 + flash_strength * 0.28), 1.0)

	var sweep_y := SITUATION_PANEL_RECT.position.y + fmod(motion_time * 47.0, TRANSMISSION_PANEL_RECT.end.y - SITUATION_PANEL_RECT.position.y)
	if motion_strength > 0.35 and flash_strength > 0.15:
		draw_line(Vector2(32, sweep_y), Vector2(508, sweep_y), Color(accent, flash_strength * 0.07), 1.0)


func _draw_briefing_panel(rect: Rect2, accent: Color) -> void:
	draw_rect(rect, Color(0.012, 0.026, 0.068, 0.94))
	draw_rect(rect, Color(accent, 0.34), false, 1.0)
	draw_line(rect.position, rect.position + Vector2(54, 0), Color(accent, 0.95), 3.0)
