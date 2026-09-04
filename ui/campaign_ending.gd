class_name CampaignEnding
extends Control

## Data-driven campaign epilogue shown between the final clear and results.
##
## Root integration contract:
##   if CampaignEnding.supports(result, result_stage):
##       var ending := CampaignEnding.new()
##       ending.setup(result, result_stage)
##       ending.results_requested.connect(_show_results_after_ending)
##       _replace_view(ending)
##
## `results_requested` returns a deep copy of the supplied result and adds the
## boolean `ending_skipped`, so the normal ResultsScreen can be constructed
## without retaining this node. Call `supports` before replacing the view: it
## rejects failures, practice/replay runs, non-final catalog stages, mismatched
## stage IDs, and StageData without authored ending content.

signal results_requested(result: Dictionary)

const VIEW_SIZE := Vector2(540.0, 960.0)
const PORTRAIT_PATHS := [
	"res://assets/characters/kira_voss_keyart.png",
	"res://assets/characters/dae_ryu_keyart.png",
	"res://assets/characters/mina_zero_keyart.png"
]

var result_data: Dictionary = {}
var stage_data: StageData
var selected_character := 0
var character_art: Texture2D
var results_button: Button
var reveal_labels: Array[Label] = []
var reveal_delays: Array[float] = []
var elapsed := 0.0
var reveal_time := 0.0
var motion_strength := 0.0
var flash_strength := 0.0
var reduced_effects := false
var context_valid := false
var _closing := false


static func supports(candidate_result: Dictionary, candidate_stage: StageData) -> bool:
	if candidate_stage == null or not candidate_stage.ending_enabled:
		return false
	if String(candidate_result.get("mode", "campaign")) != "campaign" or not bool(candidate_result.get("cleared", false)):
		return false
	if String(candidate_result.get("stage_id", "")) != candidate_stage.stage_id:
		return false
	var catalog := StageManager.stage_ids()
	if catalog.is_empty():
		return false
	return String(catalog[catalog.size() - 1]) == candidate_stage.stage_id


func setup(result: Dictionary, data: StageData) -> void:
	result_data = result.duplicate(true)
	stage_data = data
	context_valid = supports(result_data, stage_data)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(true)
	if not context_valid:
		push_error("CampaignEnding rejected a non-final or incomplete campaign result")
		call_deferred("_return_invalid_context")
		return
	selected_character = clampi(int(result_data.get("character", GameManager.selected_character)), 0, PORTRAIT_PATHS.size() - 1)
	character_art = load(PORTRAIT_PATHS[selected_character]) as Texture2D
	_refresh_effect_profile()
	_build_copy()
	_build_action()
	_update_reveal()
	AudioManager.play_music("result")
	queue_redraw()


func _refresh_effect_profile() -> void:
	motion_strength = clampf(float(SaveManager.settings.get("shake", 0.85)), 0.0, 1.0)
	flash_strength = clampf(float(SaveManager.settings.get("flash", 0.85)), 0.0, 1.0)
	reduced_effects = motion_strength <= 0.35 or flash_strength <= 0.25
	if reduced_effects:
		motion_strength = 0.0


func _build_copy() -> void:
	var accent := stage_data.ending_accent
	_add_reveal_label(GameText.text(stage_data.ending_eyebrow_key), Rect2(34, 38, 472, 20), 10, Color(accent, 0.92), 0.0, false, HORIZONTAL_ALIGNMENT_CENTER)
	_add_reveal_label(GameText.text("campaign_ending"), Rect2(34, 68, 472, 42), 29, Color("f1f8ff"), 0.12, false, HORIZONTAL_ALIGNMENT_CENTER)
	_add_reveal_label(GameText.text(stage_data.title_key), Rect2(34, 111, 472, 22), 12, Color(accent, 0.92), 0.24, false, HORIZONTAL_ALIGNMENT_CENTER)

	_add_reveal_label(GameText.text(stage_data.ending_title_key), Rect2(46, 177, 448, 38), 25, Color("fff0c7"), 0.52, false, HORIZONTAL_ALIGNMENT_CENTER)
	_add_reveal_label(GameText.text(stage_data.ending_body_key), Rect2(56, 229, 428, 126), 13, Color(0.83, 0.89, 0.98), 0.72, true, HORIZONTAL_ALIGNMENT_CENTER)

	_add_reveal_label(GameText.text("ending_final_transmission"), Rect2(54, 410, 432, 18), 10, Color(accent, 0.92), 1.12)
	_add_reveal_label(GameText.text(stage_data.ending_transmission_source_key), Rect2(66, 443, 408, 20), 10, Color("a8c9ef"), 1.28)
	_add_reveal_label(GameText.text(stage_data.ending_transmission_key), Rect2(66, 476, 408, 62), 13, Color(0.91, 0.94, 1.0), 1.44, true)

	_add_reveal_label(GameText.text("ending_epilogue"), Rect2(54, 592, 432, 18), 10, Color("ffe579"), 1.78)
	var character_name := String(GameManager.CHARACTERS[selected_character].get("name", "VECTOR"))
	_add_reveal_label(character_name, Rect2(66, 625, 408, 26), 18, Color("fff1b5"), 1.94)
	var epilogue_key := String(stage_data.ending_epilogue_keys[selected_character])
	_add_reveal_label(GameText.text(epilogue_key), Rect2(66, 663, 408, 72), 12, Color(0.84, 0.91, 1.0), 2.10, true)

	var score_stamp := GameText.text("ending_score_stamp") % [
		int(result_data.get("total_score", 0)), _format_time(float(result_data.get("clear_time", 0.0)))
	]
	_add_reveal_label(score_stamp, Rect2(34, 779, 472, 20), 11, Color(0.57, 0.75, 0.92), 2.34, false, HORIZONTAL_ALIGNMENT_CENTER)
	_add_label(GameText.text("ending_skip_hint"), Rect2(0, 922, VIEW_SIZE.x, 18), 10, Color(0.46, 0.59, 0.77), false, HORIZONTAL_ALIGNMENT_CENTER)


func _build_action() -> void:
	results_button = Button.new()
	results_button.text = GameText.text("ending_view_results")
	results_button.position = Vector2(135, 842)
	results_button.size = Vector2(270, 54)
	ArcadeUI.style_button(results_button, stage_data.ending_accent)
	results_button.size = Vector2(270, 54)
	results_button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.02, -5.0))
	results_button.pressed.connect(_request_results.bind(false))
	add_child(results_button)
	results_button.grab_focus.call_deferred()


func _add_reveal_label(
	value: String,
	rect: Rect2,
	font_size: int,
	color: Color,
	delay: float,
	wrap := false,
	alignment := HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := _add_label(value, rect, font_size, color, wrap, alignment)
	reveal_labels.append(label)
	reveal_delays.append(delay)
	return label


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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("line_spacing", 3)
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if not wrap else VERTICAL_ALIGNMENT_TOP
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _process(delta: float) -> void:
	if not context_valid:
		return
	elapsed += delta
	if not reduced_effects:
		reveal_time += delta
		_update_reveal()
	queue_redraw()


func _update_reveal() -> void:
	for index in reveal_labels.size():
		var alpha := 1.0
		if not reduced_effects:
			var linear := clampf((reveal_time - reveal_delays[index]) / 0.48, 0.0, 1.0)
			alpha = linear * linear * (3.0 - 2.0 * linear)
		reveal_labels[index].modulate.a = alpha


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _closing:
		return
	if event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		_request_results(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary"):
		_request_results(false)
		get_viewport().set_input_as_handled()


func _request_results(skipped: bool) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play_sfx("ui_confirm", 1.08 if not skipped else 0.86, -1.0 if not skipped else -3.0)
	var completed_result := result_data.duplicate(true)
	completed_result["ending_skipped"] = skipped
	results_requested.emit(completed_result)


func _return_invalid_context() -> void:
	if _closing:
		return
	_closing = true
	results_requested.emit(result_data.duplicate(true))


func _draw() -> void:
	var accent := stage_data.ending_accent if stage_data != null else Color("a969ff")
	_draw_sky(accent)
	if character_art != null:
		var portrait_alpha := 0.14 + flash_strength * 0.07
		draw_texture_rect(character_art, Rect2(286, 486, 274, 411), false, Color(0.67, 0.75, 0.94, portrait_alpha))

	_draw_cinematic_panel(Rect2(28, 153, 484, 224), accent, 0.82)
	_draw_cinematic_panel(Rect2(38, 397, 464, 165), accent, 0.93)
	_draw_cinematic_panel(Rect2(38, 579, 464, 176), Color("ffe579"), 0.93)
	draw_line(Vector2(34, 809), Vector2(506, 809), Color(accent, 0.42), 1.0)

	var signal_center := Vector2(270, 371)
	var ring_phase := elapsed * 0.12 * motion_strength
	for ring_index in 3:
		var radius := 19.0 + ring_index * 9.0
		var ring_alpha := (0.19 - ring_index * 0.04) * (0.55 + flash_strength * 0.45)
		draw_arc(signal_center, radius, -1.8 + ring_phase, 1.8 + ring_phase, 40, Color(accent, ring_alpha), 1.0)


func _draw_sky(accent: Color) -> void:
	for band in 20:
		var ratio := float(band) / 19.0
		var sky_color := Color("030615").lerp(Color("16102d"), ratio)
		draw_rect(Rect2(0, band * 48.0, VIEW_SIZE.x, 50.0), sky_color)

	var drift := elapsed * 2.8 * motion_strength
	for star_index in 52:
		var x := fmod(float(star_index * 83 + 31) + drift * (0.25 + float(star_index % 3) * 0.16), VIEW_SIZE.x + 30.0) - 15.0
		var y := 18.0 + fmod(float(star_index * 47 + 19), 410.0)
		var twinkle := 1.0
		if not reduced_effects:
			twinkle = 0.72 + 0.28 * sin(elapsed * (0.45 + float(star_index % 5) * 0.08) + star_index)
		var alpha := (0.08 + float(star_index % 4) * 0.025) * twinkle * (0.65 + flash_strength * 0.35)
		draw_circle(Vector2(x, y), 0.8 + float(star_index % 3) * 0.35, Color(0.64, 0.83, 1.0, alpha))

	var dawn_center := Vector2(270, 350)
	for glow_index in range(8, 0, -1):
		var glow_radius := 22.0 + glow_index * 19.0
		var glow_alpha := (9.0 - glow_index) * 0.0045 * (0.6 + flash_strength * 0.4)
		draw_circle(dawn_center, glow_radius, Color(accent, glow_alpha))
	draw_line(Vector2(0, 351), Vector2(VIEW_SIZE.x, 351), Color(accent, 0.26), 1.0)
	draw_line(Vector2(90, 352), Vector2(450, 352), Color("fff1bd", 0.26 + flash_strength * 0.12), 2.0)

	for structure_index in 12:
		var left := float(structure_index * 49 - 18)
		var height := 25.0 + float((structure_index * 37) % 88)
		var lean := float((structure_index % 3) - 1) * 8.0
		var silhouette := PackedVector2Array([
			Vector2(left, 394), Vector2(left + lean + 7, 394 - height),
			Vector2(left + 34 + lean, 394 - height * 0.82), Vector2(left + 41, 394)
		])
		draw_colored_polygon(silhouette, Color(0.025, 0.035, 0.085, 0.92))
		draw_polyline(PackedVector2Array([silhouette[0], silhouette[1], silhouette[2], silhouette[3]]), Color(accent, 0.11), 1.0)

	if not reduced_effects:
		var sweep_x := fmod(elapsed * 31.0 * motion_strength, 650.0) - 55.0
		draw_line(Vector2(sweep_x, 0), Vector2(sweep_x - 180.0, VIEW_SIZE.y), Color(accent, flash_strength * 0.028), 1.0)


func _draw_cinematic_panel(rect: Rect2, accent: Color, opacity: float) -> void:
	draw_rect(rect, Color(0.01, 0.021, 0.058, opacity))
	draw_rect(rect, Color(accent, 0.27), false, 1.0)
	draw_line(rect.position, rect.position + Vector2(64, 0), Color(accent, 0.94), 3.0)
	draw_line(rect.end - Vector2(64, 0), rect.end, Color(accent, 0.42), 1.0)


func _format_time(value: float) -> String:
	var minutes := int(value) / 60
	var seconds := int(value) % 60
	return "%02d:%02d.%02d" % [minutes, seconds, int(fmod(value, 1.0) * 100.0)]
