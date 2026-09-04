extends Node

## Focused regression test for route-clock narrative transmissions.

var failures: Array[String] = []
var save_manager: Node
var stage_manager: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	save_manager = get_tree().root.get_node_or_null("SaveManager")
	stage_manager = get_tree().root.get_node_or_null("StageManager")
	if save_manager == null or stage_manager == null:
		failures.append("required autoloads are unavailable")
		_finish({})
		return
	var settings_backup: Dictionary = save_manager.settings.duplicate(true)
	save_manager.settings.shake = 0.0
	save_manager.settings.flash = 0.0
	var stage: StageData = stage_manager.default_stage()
	_check(stage != null and stage.radio_events.size() >= 3, "default stage has no authored radio sequence")
	if stage == null or stage.radio_events.is_empty():
		_finish(settings_backup)
		return

	var overlay := RadioCommsOverlay.new()
	overlay.setup(stage.radio_events)
	add_child(overlay)
	await get_tree().process_frame
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and overlay.focus_mode == Control.FOCUS_NONE, "radio overlay can intercept combat focus or pointer input")
	_check(not overlay.is_processing_input() and not overlay.is_processing_unhandled_input(), "radio overlay consumes gameplay input callbacks")
	_check(is_zero_approx(overlay._motion_strength) and is_zero_approx(overlay._flash_strength), "reduced-effects settings did not disable radio motion and flash")

	var started := PackedStringArray()
	var finished := PackedStringArray()
	overlay.event_started.connect(func(event_id: String): started.append(event_id))
	overlay.event_finished.connect(func(event_id: String): finished.append(event_id))
	var first_event: StageRadioEvent = stage.radio_events[0]
	overlay.update_route_time(first_event.trigger_time, true)
	_check(not overlay.has_fired(first_event.event_id), "radio event fired while the route clock was paused")
	overlay.update_route_time(first_event.trigger_time, false)
	overlay.update_route_time(first_event.trigger_time, false)
	_check(overlay.has_fired(first_event.event_id) and started.count(first_event.event_id) == 1, "radio event did not fire exactly once")

	var last_event: StageRadioEvent = stage.radio_events[stage.radio_events.size() - 1]
	overlay.update_route_time(last_event.trigger_time, false)
	_check(overlay.pending_count() == stage.radio_events.size() - 1, "radio events reached during an active message were not queued")
	overlay._process(first_event.duration + 0.01)
	_check(finished.has(first_event.event_id) and started.size() == 2, "radio message did not auto-exit into the queued sequence")
	overlay.queue_free()
	await get_tree().process_frame
	_finish(settings_backup)


func _finish(settings_backup: Dictionary) -> void:
	if save_manager != null and not settings_backup.is_empty():
		save_manager.settings = settings_backup
	if failures.is_empty():
		print("RADIO_COMMS_TEST_OK events=%d once=ok route_pause=ok queue=ok auto_exit=ok input_passthrough=ok reduced_effects=ok" % stage_manager.default_stage().radio_events.size())
		get_tree().quit(0)
		return
	printerr("RADIO_COMMS_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("RADIO_COMMS_ERROR %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
