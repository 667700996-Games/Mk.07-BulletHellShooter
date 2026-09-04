class_name CreditsScreen
extends Control

## Read-only credits and current-build data disclosure.
##
## Integration contract:
##   var screen := CreditsScreen.new()
##   screen.closed.connect(_show_title)
##   _replace_view(screen)

signal closed

const VIEW_SIZE := Vector2(540, 960)
const PAGE_TITLE_KEYS := [
	"credits_project_title",
	"credits_media_title",
	"credits_privacy_title"
]
const PAGE_BODY_KEYS := [
	"credits_project_body",
	"credits_media_body",
	"credits_privacy_body"
]

var page_index := 0
var time := 0.0
var motion_strength := 0.0
var flash_strength := 0.0
var page_title: Label
var page_body: Label
var page_counter: Label
var previous_button: Button
var next_button: Button
var close_button: Button
var _closing := false


func setup(initial_page: int = 0) -> void:
	page_index = clampi(initial_page, 0, PAGE_TITLE_KEYS.size() - 1)


func page_count() -> int:
	return PAGE_TITLE_KEYS.size()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_effect_profile()
	if not GameManager.settings_changed.is_connected(_refresh_effect_profile):
		GameManager.settings_changed.connect(_refresh_effect_profile)
	_build_copy()
	_build_actions()
	_refresh_page()
	_focus_default_for_page.call_deferred()


func _refresh_effect_profile() -> void:
	motion_strength = clampf(float(SaveManager.settings.get("shake", 0.85)), 0.0, 1.0)
	flash_strength = clampf(float(SaveManager.settings.get("flash", 0.85)), 0.0, 1.0)
	queue_redraw()


func _build_copy() -> void:
	_add_label(GameText.text("credits_overline"), Rect2(34, 42, 472, 20), 10, Color("71efff"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(GameText.text("credits_title"), Rect2(28, 70, 484, 42), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(GameText.text("credits_subtitle"), Rect2(28, 114, 484, 22), 11, Color(0.52, 0.70, 0.91), HORIZONTAL_ALIGNMENT_CENTER)
	page_title = _add_label("", Rect2(52, 192, 436, 38), 21, Color("ffe579"), HORIZONTAL_ALIGNMENT_CENTER)
	page_body = _add_label("", Rect2(58, 255, 424, 466), 14, Color(0.81, 0.88, 0.98), HORIZONTAL_ALIGNMENT_LEFT, true)
	page_body.add_theme_constant_override("line_spacing", 4)
	page_counter = _add_label("", Rect2(220, 756, 100, 22), 11, Color(0.52, 0.70, 0.91), HORIZONTAL_ALIGNMENT_CENTER)


func _build_actions() -> void:
	previous_button = _button(GameText.text("credits_previous"), Vector2(34, 797), Vector2(190, 50), Color("7c8fb2"))
	next_button = _button(GameText.text("credits_next"), Vector2(316, 797), Vector2(190, 50), Color("43e8ff"))
	close_button = _button(GameText.text("credits_close"), Vector2(135, 873), Vector2(270, 52), Color("a45cff"))
	previous_button.pressed.connect(_change_page.bind(-1))
	next_button.pressed.connect(_change_page.bind(1))
	close_button.pressed.connect(_close)
	previous_button.focus_neighbor_right = previous_button.get_path_to(next_button)
	previous_button.focus_neighbor_bottom = previous_button.get_path_to(close_button)
	next_button.focus_neighbor_left = next_button.get_path_to(previous_button)
	next_button.focus_neighbor_bottom = next_button.get_path_to(close_button)
	close_button.focus_neighbor_top = close_button.get_path_to(next_button)


func _add_label(
	value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	alignment := HORIZONTAL_ALIGNMENT_LEFT,
	wrap := false
) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _button(label: String, position_value: Vector2, size_value: Vector2, accent: Color) -> Button:
	var button := Button.new()
	button.text = label
	button.position = position_value
	button.size = size_value
	ArcadeUI.style_button(button, accent)
	button.custom_minimum_size = size_value
	button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.0, -5.0))
	add_child(button)
	return button


func _refresh_page() -> void:
	page_title.text = GameText.text(PAGE_TITLE_KEYS[page_index])
	page_body.text = GameText.text(PAGE_BODY_KEYS[page_index])
	page_counter.text = GameText.text("credits_page_count") % [page_index + 1, page_count()]
	previous_button.disabled = page_index == 0
	next_button.disabled = page_index == page_count() - 1
	queue_redraw()


func _focus_default_for_page() -> void:
	if page_index == page_count() - 1:
		close_button.grab_focus()
	else:
		next_button.grab_focus()


func _change_page(direction: int) -> void:
	var next_page := clampi(page_index + direction, 0, page_count() - 1)
	if next_page == page_index:
		return
	page_index = next_page
	AudioManager.play_sfx("ui_confirm", 0.96 + page_index * 0.05, -3.0)
	_refresh_page()
	if page_index == 0 or page_index == page_count() - 1:
		_focus_default_for_page.call_deferred()


func _close() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_sfx("ui_confirm", 0.9, -3.0)
	closed.emit()


func _process(delta: float) -> void:
	time += delta * lerpf(0.08, 1.0, motion_strength)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _closing or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("move_left"):
		_change_page(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_change_page(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == previous_button and not previous_button.disabled:
			previous_button.pressed.emit()
		elif focused == next_button and not next_button.disabled:
			next_button.pressed.emit()
		else:
			close_button.pressed.emit()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("030716"))
	var grid_alpha := 0.025 + flash_strength * 0.025
	for row in 17:
		var drift := fmod(time * 13.0, 58.0) if motion_strength > 0.15 else 0.0
		var y := float(row) * 58.0 + drift
		draw_line(Vector2(0, y), Vector2(VIEW_SIZE.x, y - 120), Color(0.18, 0.65, 1.0, grid_alpha), 1.0)
	for ring in 6:
		var radius := 62.0 + ring * 49.0 + sin(time * 0.7 + ring) * 3.0 * motion_strength
		draw_arc(Vector2(270, 472), radius, time * 0.025, TAU + time * 0.025, 64, Color(0.35, 0.45, 1.0, grid_alpha), 1.0)
	draw_rect(Rect2(28, 166, 484, 592), Color(0.008, 0.021, 0.062, 0.94))
	draw_rect(Rect2(28, 166, 484, 592), Color(0.255, 0.91, 1.0, 0.26 + flash_strength * 0.10), false, 1.0)
	draw_line(Vector2(28, 166), Vector2(180, 166), Color("43e8ff"), 3.0)
