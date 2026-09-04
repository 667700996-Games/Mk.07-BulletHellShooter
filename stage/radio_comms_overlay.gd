class_name RadioCommsOverlay
extends Control

## Non-interactive presentation layer for StageRadioEvent resources.
##
## Integration contract:
##   radio_comms = RadioCommsOverlay.new()
##   radio_comms.setup(stage_data.radio_events)
##   hud_layer.add_child(radio_comms)
##   radio_comms.move_to_front()
##
## During campaign/replay processing, after advancing the route clock:
##   radio_comms.update_route_time(play_time, midboss_is_active)
##
## Do not update this overlay in boss practice. The second argument suspends
## event admission during the untimed midboss gate; already visible messages
## still leave automatically on wall-clock time.

signal event_started(event_id: String)
signal event_finished(event_id: String)

const VIEW_SIZE := Vector2(540, 960)
const PANEL_RECT := Rect2(18, 728, 504, 146)
const TRIGGER_EPSILON := 0.001

var _events: Array[StageRadioEvent] = []
var _pending: Array[StageRadioEvent] = []
var _fired_ids := {}
var _next_event_index := 0
var _active_event: StageRadioEvent
var _active_elapsed := 0.0
var _animation_time := 0.0
var _motion_strength := 0.0
var _flash_strength := 0.0


func setup(events: Array[StageRadioEvent]) -> void:
	_events.clear()
	for radio_event in events:
		if radio_event != null:
			_events.append(radio_event)
	_events.sort_custom(func(a: StageRadioEvent, b: StageRadioEvent): return a.trigger_time < b.trigger_time)
	reset_route()


func reset_route() -> void:
	_pending.clear()
	_fired_ids.clear()
	_next_event_index = 0
	_active_event = null
	_active_elapsed = 0.0
	queue_redraw()


func update_route_time(route_time: float, route_paused: bool = false) -> void:
	if route_paused:
		return
	while _next_event_index < _events.size():
		var radio_event := _events[_next_event_index]
		if radio_event.trigger_time > route_time + TRIGGER_EPSILON:
			break
		_next_event_index += 1
		if _fired_ids.has(radio_event.event_id):
			continue
		_fired_ids[radio_event.event_id] = true
		_pending.append(radio_event)
	_show_next_event()


func has_fired(event_id: String) -> bool:
	return _fired_ids.has(event_id)


func pending_count() -> int:
	return _pending.size()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_input(false)
	set_process_unhandled_input(false)
	_refresh_effect_profile()
	if not GameManager.settings_changed.is_connected(_refresh_effect_profile):
		GameManager.settings_changed.connect(_refresh_effect_profile)


func _refresh_effect_profile() -> void:
	_motion_strength = clampf(float(SaveManager.settings.get("shake", 0.85)), 0.0, 1.0)
	_flash_strength = clampf(float(SaveManager.settings.get("flash", 0.85)), 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_animation_time += delta * lerpf(0.08, 1.0, _motion_strength)
	if _active_event == null:
		return
	_active_elapsed += delta
	if _active_elapsed >= _active_event.duration:
		var finished_id := _active_event.event_id
		_active_event = null
		_active_elapsed = 0.0
		event_finished.emit(finished_id)
		_show_next_event()
	queue_redraw()


func _show_next_event() -> void:
	if _active_event != null or _pending.is_empty():
		return
	_active_event = _pending.pop_front()
	_active_elapsed = 0.0
	event_started.emit(_active_event.event_id)
	queue_redraw()


func _draw() -> void:
	if _active_event == null:
		return
	var entrance := clampf(_active_elapsed / 0.28, 0.0, 1.0)
	var exit_fade := clampf((_active_event.duration - _active_elapsed) / 0.42, 0.0, 1.0)
	var alpha := entrance * exit_fade
	var slide := (1.0 - entrance) * -34.0 * _motion_strength
	var panel := Rect2(PANEL_RECT.position + Vector2(slide, 0), PANEL_RECT.size)
	var accent := _active_event.accent

	draw_rect(panel, Color(0.006, 0.015, 0.05, alpha * 0.92))
	draw_rect(panel, Color(accent, alpha * (0.42 + _flash_strength * 0.18)), false, 1.0)
	draw_line(panel.position, panel.position + Vector2(92, 0), Color(accent, alpha), 3.0)
	draw_line(panel.position + Vector2(0, panel.size.y), panel.position + Vector2(panel.size.x, panel.size.y), Color(accent, alpha * 0.24), 1.0)

	var signal_x := panel.position.x + 23.0
	var signal_y := panel.position.y + 31.0
	for index in 6:
		var wave := 3.0 + absf(sin(_animation_time * 2.4 + float(index))) * (3.0 + 5.0 * _flash_strength)
		draw_line(Vector2(signal_x + index * 3.0, signal_y - wave), Vector2(signal_x + index * 3.0, signal_y + wave), Color(accent, alpha * 0.76), 1.0)

	var font := ThemeDB.fallback_font
	draw_string(font, panel.position + Vector2(52, 35), GameText.text(_active_event.speaker_key), HORIZONTAL_ALIGNMENT_LEFT, 416, 13, Color(accent, alpha))
	var message_lines := GameText.text(_active_event.message_key).split("\n")
	for line_index in mini(message_lines.size(), 3):
		draw_string(font, panel.position + Vector2(24, 77 + line_index * 24), message_lines[line_index], HORIZONTAL_ALIGNMENT_LEFT, 456, 14, Color(0.91, 0.95, 1.0, alpha))
