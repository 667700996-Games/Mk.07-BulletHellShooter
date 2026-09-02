extends Node

signal stage_started(stage_id: String)
signal section_changed(section: String)
signal stage_finished(stage_id: String, cleared: bool, time: float)

var active_stage := ""
var elapsed := 0.0
var section := "idle"

func begin(stage_id: String) -> void:
	active_stage = stage_id
	elapsed = 0.0
	section = "intro"
	stage_started.emit(active_stage)
	section_changed.emit(section)

func update_time(value: float) -> void:
	elapsed = value
	var next_section := _section_for_time(value)
	if next_section != section:
		section = next_section
		section_changed.emit(section)

func finish(cleared: bool) -> void:
	stage_finished.emit(active_stage, cleared, elapsed)
	active_stage = ""
	section = "idle"

func _section_for_time(value: float) -> String:
	if value < 15.0: return "intro"
	if value < 62.0: return "opening_waves"
	if value < 122.0: return "mixed_formations"
	if value < 165.0: return "heavy_units"
	if value < 260.0: return "midboss"
	if value < 330.0: return "high_density"
	if value < 425.0: return "elite_escalation"
	return "final_boss"
