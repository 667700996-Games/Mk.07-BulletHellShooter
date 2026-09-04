class_name StageData
extends Resource

## Complete, editor-authored definition of one campaign stage.
##
## Runtime systems consume stable IDs while presentation strings remain locale
## keys. Keeping both in this resource lets new stages reuse the same controller
## without introducing another set of stage-specific constants.

@export_group("Identity")
@export var stage_id := ""
@export var title_key := ""
@export var subtitle_key := ""
@export var result_key := ""
@export var pause_key := ""

@export_group("Operation Briefing")
@export var briefing_eyebrow_key := ""
@export var briefing_situation_key := ""
@export var briefing_objective_key := ""
@export var briefing_transmission_source_key := ""
@export var briefing_transmission_key := ""
@export var briefing_accent := Color("43e8ff")

@export_group("Campaign Ending")
@export var ending_enabled := false
@export var ending_eyebrow_key := ""
@export var ending_title_key := ""
@export var ending_body_key := ""
@export var ending_transmission_source_key := ""
@export var ending_transmission_key := ""
@export var ending_epilogue_keys := PackedStringArray()
@export var ending_accent := Color("a969ff")

@export_group("Runtime")
@export var timeline: StageTimelineData
@export var background_scene: PackedScene
@export var post_shader: Shader
@export var stage_music_id := ""
@export var boss_music_id := ""

@export_group("Radio Comms")
@export var radio_events: Array[StageRadioEvent] = []

@export_group("Route Hazards")
@export var hazard_events: Array[StageHazardData] = []

@export_group("Midboss")
@export var midboss_id := ""
@export var midboss_name_key := ""
@export var midboss_subtitle_key := ""
@export var midboss_defeat_title_key := ""
@export var midboss_defeat_subtitle_key := ""

@export_group("Final Boss")
@export var final_boss_id := ""
@export var final_boss_name_key := ""
@export var final_boss_subtitle_key := ""
@export var final_boss_defeat_title_key := ""
@export var final_boss_defeat_subtitle_key := ""
@export_range(1, 64, 1) var expected_boss_phase_count := 1
@export var practice_phase_name_keys := PackedStringArray()

@export_group("Enemy Roster")
@export var grade_1_enemy_id := ""
@export var grade_2_enemy_id := ""
@export var grade_3_enemy_id := ""

@export_group("Determinism")
@export var deterministic_seed_salt := 1

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	_require_text(errors, stage_id, "stage_id")
	_require_text(errors, title_key, "title_key")
	_require_text(errors, subtitle_key, "subtitle_key")
	_require_text(errors, result_key, "result_key")
	_require_text(errors, pause_key, "pause_key")
	_require_text(errors, briefing_eyebrow_key, "briefing_eyebrow_key")
	_require_text(errors, briefing_situation_key, "briefing_situation_key")
	_require_text(errors, briefing_objective_key, "briefing_objective_key")
	_require_text(errors, briefing_transmission_source_key, "briefing_transmission_source_key")
	_require_text(errors, briefing_transmission_key, "briefing_transmission_key")
	if ending_enabled:
		_require_text(errors, ending_eyebrow_key, "ending_eyebrow_key")
		_require_text(errors, ending_title_key, "ending_title_key")
		_require_text(errors, ending_body_key, "ending_body_key")
		_require_text(errors, ending_transmission_source_key, "ending_transmission_source_key")
		_require_text(errors, ending_transmission_key, "ending_transmission_key")
		if ending_epilogue_keys.size() != 3:
			errors.append("ending_epilogue_keys must contain one entry for each of the three playable characters")
		for ending_index in ending_epilogue_keys.size():
			_require_text(errors, ending_epilogue_keys[ending_index], "ending_epilogue_keys[%d]" % ending_index)
	if timeline == null:
		errors.append("timeline is missing")
	elif not stage_id.is_empty() and timeline.stage_id != stage_id:
		errors.append("timeline.stage_id must match stage_id")
	if background_scene == null:
		errors.append("background_scene is missing")
	else:
		var background_probe := background_scene.instantiate()
		if not background_probe is Node2D:
			errors.append("background_scene root must be Node2D")
		elif not background_probe.has_method("configure") or not background_probe.has_method("set_route_context") or not background_probe.has_method("set_escalation"):
			errors.append("background_scene does not implement the stage background contract")
		background_probe.free()
	if post_shader == null:
		errors.append("post_shader is missing")
	_require_text(errors, stage_music_id, "stage_music_id")
	_require_text(errors, boss_music_id, "boss_music_id")
	if radio_events.size() < 3 or radio_events.size() > 5:
		errors.append("radio_events must contain between 3 and 5 events")
	var radio_ids := {}
	var previous_radio_time := -1.0
	for radio_index in radio_events.size():
		var radio_event := radio_events[radio_index]
		if radio_event == null:
			errors.append("radio_events[%d] is missing" % radio_index)
			continue
		for error in radio_event.validation_errors(timeline.boss_spawn_time if timeline != null else 3600.0):
			errors.append("radio_events[%d]: %s" % [radio_index, error])
		if radio_ids.has(radio_event.event_id):
			errors.append("duplicate radio event_id: %s" % radio_event.event_id)
		radio_ids[radio_event.event_id] = true
		if radio_event.trigger_time <= previous_radio_time:
			errors.append("radio_events must be ordered by increasing trigger_time")
		previous_radio_time = radio_event.trigger_time
	var hazard_ids := {}
	for hazard_index in hazard_events.size():
		var hazard := hazard_events[hazard_index]
		if hazard == null:
			errors.append("hazard_events[%d] is missing" % hazard_index)
			continue
		for error in hazard.validation_errors(timeline.boss_spawn_time if timeline != null else 3600.0):
			errors.append("hazard_events[%d]: %s" % [hazard_index, error])
		if hazard_ids.has(hazard.hazard_id):
			errors.append("duplicate hazard_id: %s" % hazard.hazard_id)
		hazard_ids[hazard.hazard_id] = true
	_require_text(errors, midboss_id, "midboss_id")
	_require_text(errors, midboss_name_key, "midboss_name_key")
	_require_text(errors, midboss_subtitle_key, "midboss_subtitle_key")
	_require_text(errors, midboss_defeat_title_key, "midboss_defeat_title_key")
	_require_text(errors, midboss_defeat_subtitle_key, "midboss_defeat_subtitle_key")
	_require_text(errors, final_boss_id, "final_boss_id")
	_require_text(errors, final_boss_name_key, "final_boss_name_key")
	_require_text(errors, final_boss_subtitle_key, "final_boss_subtitle_key")
	_require_text(errors, final_boss_defeat_title_key, "final_boss_defeat_title_key")
	_require_text(errors, final_boss_defeat_subtitle_key, "final_boss_defeat_subtitle_key")
	if not midboss_id.is_empty() and not final_boss_id.is_empty():
		if midboss_id == final_boss_id:
			errors.append("midboss_id and final_boss_id must be different")
		var midboss_definition := BossController.definition_for_id(midboss_id)
		var final_boss_definition := BossController.definition_for_id(final_boss_id)
		if midboss_definition == null:
			errors.append("midboss_id is not present in the boss catalog")
		elif midboss_definition.is_final:
			errors.append("midboss definition cannot be marked final")
		elif midboss_definition.display_name_key != midboss_name_key:
			errors.append("midboss_name_key does not match its boss definition")
		if final_boss_definition == null:
			errors.append("final_boss_id is not present in the boss catalog")
		elif not final_boss_definition.is_final:
			errors.append("final boss definition must be marked final")
		elif final_boss_definition.display_name_key != final_boss_name_key:
			errors.append("final_boss_name_key does not match its boss definition")
		if midboss_definition != null and final_boss_definition != null:
			if midboss_definition.phases.size() + final_boss_definition.phases.size() != expected_boss_phase_count:
				errors.append("expected_boss_phase_count does not match the boss definitions")
			if final_boss_definition.phases.size() != practice_phase_name_keys.size():
				errors.append("practice phase count does not match the final boss definition")
			else:
				for phase_index in final_boss_definition.phases.size():
					if final_boss_definition.phases[phase_index].name_key != practice_phase_name_keys[phase_index]:
						errors.append("practice phase key does not match final boss phase %d" % phase_index)
	_require_text(errors, grade_1_enemy_id, "grade_1_enemy_id")
	_require_text(errors, grade_2_enemy_id, "grade_2_enemy_id")
	_require_text(errors, grade_3_enemy_id, "grade_3_enemy_id")
	if not grade_1_enemy_id.is_empty() and (grade_1_enemy_id == grade_2_enemy_id or grade_1_enemy_id == grade_3_enemy_id or grade_2_enemy_id == grade_3_enemy_id):
		errors.append("grade enemy IDs must be unique")
	if expected_boss_phase_count < 1:
		errors.append("expected_boss_phase_count must be positive")
	if practice_phase_name_keys.is_empty():
		errors.append("practice_phase_name_keys is empty")
	elif practice_phase_name_keys.size() > expected_boss_phase_count:
		errors.append("practice phase count exceeds expected boss phase count")
	for phase_index in practice_phase_name_keys.size():
		_require_text(errors, practice_phase_name_keys[phase_index], "practice_phase_name_keys[%d]" % phase_index)
	if deterministic_seed_salt == 0:
		errors.append("deterministic_seed_salt must be non-zero")
	return errors

func is_valid() -> bool:
	return validation_errors().is_empty()

func _require_text(errors: PackedStringArray, value: String, field_name: String) -> void:
	if value.strip_edges().is_empty():
		errors.append("%s is empty" % field_name)
