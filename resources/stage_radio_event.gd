class_name StageRadioEvent
extends Resource

## One localized, route-clock-driven in-game transmission.
##
## The overlay owns display time. `trigger_time` is route time, so an untimed
## midboss encounter never advances this schedule.

@export_group("Identity")
@export var event_id := ""
@export var speaker_key := ""
@export var message_key := ""

@export_group("Timing")
@export_range(0.0, 3600.0, 0.1) var trigger_time := 0.0
@export_range(1.5, 8.0, 0.1) var duration := 4.2

@export_group("Presentation")
@export var accent := Color("43e8ff")


func validation_errors(route_duration: float = 3600.0) -> PackedStringArray:
	var errors := PackedStringArray()
	if event_id.strip_edges().is_empty():
		errors.append("event_id is empty")
	if speaker_key.strip_edges().is_empty():
		errors.append("speaker_key is empty")
	if message_key.strip_edges().is_empty():
		errors.append("message_key is empty")
	if trigger_time < 0.0 or trigger_time >= route_duration:
		errors.append("trigger_time must be inside the route")
	if duration < 1.5 or duration > 8.0:
		errors.append("duration must be between 1.5 and 8.0 seconds")
	if accent.a <= 0.0:
		errors.append("accent must be visible")
	return errors


func is_valid(route_duration: float = 3600.0) -> bool:
	return validation_errors(route_duration).is_empty()
