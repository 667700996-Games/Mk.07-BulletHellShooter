class_name StageTimelineData
extends Resource

@export var stage_id := "neon_district_01"
@export var intro_lock_time := 4.2
@export var wave_start_time := 5.0
@export var early_wave_end := 60.0
@export var midboss_spawn_time := 90.0
@export var late_wave_start := 135.0
@export var boss_warning_time := 174.0
@export var boss_spawn_time := 180.0
@export var danger_escalation_time := 120.0

@export_group("Wave Rules")
@export_range(1, 12) var enemies_per_wave := 5
@export_range(1, 12) var early_grade_3_count := 5
@export_range(1, 12) var middle_grade_3_count := 4
@export_range(1, 12) var late_grade_3_count := 3
@export var early_wave_interval := 6.4
@export var middle_wave_interval := 5.8
@export var late_wave_interval := 5.2

func section_for_time(value: float, midboss_cleared: bool) -> String:
	if value < wave_start_time:
		return "intro"
	if value < early_wave_end:
		return "opening_waves"
	if value < midboss_spawn_time:
		return "mixed_formations"
	if not midboss_cleared:
		return "midboss"
	if value < late_wave_start:
		return "post_midboss"
	if value < boss_warning_time:
		return "elite_escalation"
	if value < boss_spawn_time:
		return "final_warning"
	return "final_boss"
