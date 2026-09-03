extends Node

signal stage_started(stage_id: String)
signal section_changed(section: String)
signal stage_finished(stage_id: String, cleared: bool, time: float)

var active_stage := ""
var elapsed := 0.0
var section := "idle"
var timeline: StageTimelineData

func begin(stage_id: String, stage_timeline: StageTimelineData = null) -> void:
	active_stage = stage_id
	timeline = stage_timeline
	elapsed = 0.0
	section = "intro"
	stage_started.emit(active_stage)
	section_changed.emit(section)

func update_time(value: float, midboss_cleared: bool = false) -> void:
	elapsed = value
	var next_section := timeline.section_for_time(value, midboss_cleared) if timeline != null else _fallback_section_for_time(value)
	if next_section != section:
		section = next_section
		section_changed.emit(section)

func finish(cleared: bool) -> void:
	stage_finished.emit(active_stage, cleared, elapsed)
	active_stage = ""
	section = "idle"
	timeline = null

func _fallback_section_for_time(value: float) -> String:
	if value < 5.0: return "intro"
	if value < 60.0: return "opening_waves"
	if value < 90.0: return "mixed_formations"
	if value < 135.0: return "post_midboss"
	if value < 174.0: return "elite_escalation"
	if value < 180.0: return "final_warning"
	return "final_boss"
