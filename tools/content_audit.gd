extends SceneTree

## Production content gate for every entry in StageManager.STAGE_CATALOG.
##
## This intentionally lives outside gameplay code. It turns the authored route,
## encounter, presentation, and localization contracts into a deterministic CI
## check without mutating imported resources.

const ROUTE_SECONDS := 180.0
const WAVE_START_SECONDS := 5.0
const ENEMIES_PER_WAVE := 5
const EARLY_GRADE_3_COUNT := 5
const MIDDLE_GRADE_3_COUNT := 4
const LATE_GRADE_3_COUNT := 3
const MIDBOSS_PHASE_COUNT := 3
const FINAL_BOSS_PHASE_COUNT := 5
const MIN_WAVES_PER_STAGE := 24
const MAX_WAVES_PER_STAGE := 32
const MIN_ENEMIES_PER_STAGE := 120
const MAX_ENEMIES_PER_STAGE := 160
const MAX_HAZARD_TRIGGERS_PER_STAGE := 24
const MIN_RADIO_EVENTS_PER_STAGE := 3
const MAX_RADIO_EVENTS_PER_STAGE := 5
const RADIO_BEAT_WINDOW_SECONDS := 20.0
const MIN_MIDBOSS_PHASE_HP := 1100.0
const MAX_MIDBOSS_PHASE_HP := 2600.0
const MIN_FINAL_BOSS_PHASE_HP := 1700.0
const MAX_FINAL_BOSS_PHASE_HP := 4500.0
const MIN_MIDBOSS_TOTAL_HP := 4000.0
const MAX_MIDBOSS_TOTAL_HP := 6500.0
const MIN_FINAL_BOSS_TOTAL_HP := 12000.0
const MAX_FINAL_BOSS_TOTAL_HP := 17000.0
const MIN_STAGE_BOSS_TOTAL_HP := 16000.0
const MAX_STAGE_BOSS_TOTAL_HP := 22000.0
const MIN_MIDBOSS_FIRE_INTERVAL := 0.40
const MAX_MIDBOSS_FIRE_INTERVAL := 0.85
const MIN_FINAL_BOSS_FIRE_INTERVAL := 0.24
const MAX_FINAL_BOSS_FIRE_INTERVAL := 0.75
const MIN_ATTACK_SEQUENCE_LENGTH := 4
const MAX_ATTACK_SEQUENCE_LENGTH := 8
const MIN_PHASE_PATTERN_DIVERSITY := 2
const MAX_PHASE_PATTERN_DIVERSITY := 4
const MIN_HAZARD_WARNING_SECONDS := 1.0
const MIN_KEY_ART_DIMENSION := 512
const MIN_COMBAT_SHEET_DIMENSION := 512
const MIN_COMBAT_FRAME_DIMENSION := 256
const HAZARD_PLAYFIELD_HEIGHT := 850.0
const EPSILON := 0.001

const BASE_REQUIRED_TEXT_KEYS := [
	"environment_hazard",
	"evasive_action"
]

var errors: Array[String] = []
var stage_ids := {}
var stage_salts := {}
var boss_ids := {}
var enemy_ids := {}
var hazard_ids := {}
var radio_event_ids := {}
var phase_name_keys := {}
var boss_count := 0
var hazard_count := 0
var expected_wave_count := 0
var expected_enemy_count := 0
var hazard_trigger_count := 0
var radio_event_count := 0
var boss_phase_count := 0
var texture_count := 0
var stage_manager: Node
var game_text_script: Script
var game_database_script: Script
var boss_controller_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	stage_manager = get_root().get_node_or_null("StageManager")
	if stage_manager == null:
		_fail("runtime", "StageManager autoload is unavailable")
		_finish([])
		return
	game_text_script = load("res://resources/game_text.gd") as Script
	game_database_script = load("res://resources/game_database.gd") as Script
	boss_controller_script = load("res://boss/boss_controller.gd") as Script
	if game_text_script == null or game_database_script == null or boss_controller_script == null:
		_fail("runtime", "one or more content contract scripts could not be loaded")
		_finish([])
		return
	var catalog: Array = stage_manager.get_script().STAGE_CATALOG
	if catalog.is_empty():
		_fail("catalog", "StageManager.STAGE_CATALOG must contain at least one stage")
	for stage_index in catalog.size():
		var stage: Variant = catalog[stage_index]
		_audit_stage(stage, stage_index)
	_audit_campaign_ending(catalog)
	_audit_localization_parity()
	_finish(catalog)


func _finish(catalog: Array) -> void:

	if not errors.is_empty():
		printerr("CONTENT_AUDIT_FAILED errors=%d stages=%d bosses=%d hazards=%d radio_events=%d textures=%d locales=2 waves=%d enemies=%d hazard_triggers=%d boss_phases=%d" % [
			errors.size(), catalog.size(), boss_count, hazard_count, radio_event_count, texture_count,
			expected_wave_count, expected_enemy_count, hazard_trigger_count, boss_phase_count
		])
		for error in errors:
			printerr("CONTENT_AUDIT_ERROR %s" % error)
		quit(1)
		return

	print("CONTENT_AUDIT_OK stages=%d bosses=%d hazards=%d radio_events=%d textures=%d locale_keys=%d route=%.0fs waves=%d enemies=%d hazard_triggers=%d boss_phases=%d" % [
		catalog.size(), boss_count, hazard_count, radio_event_count, texture_count, game_text_script.EN.size(), ROUTE_SECONDS,
		expected_wave_count, expected_enemy_count, hazard_trigger_count, boss_phase_count
	])
	quit(0)


func _audit_stage(stage: Variant, stage_index: int) -> void:
	var context := "stage[%d]" % stage_index
	if stage == null:
		_fail(context, "catalog entry is null")
		return
	context = "stage[%s]" % stage.stage_id
	_audit_stable_id(stage.stage_id, context + ".stage_id", true)
	_claim_unique(stage_ids, stage.stage_id, context + ".stage_id", "stage ID")
	if stage.deterministic_seed_salt < 1:
		_fail(context + ".deterministic_seed_salt", "salt must be a positive integer")
	_claim_unique(stage_salts, stage.deterministic_seed_salt, context + ".deterministic_seed_salt", "stage seed salt")

	for validation_error in stage.validation_errors():
		_fail(context, "StageData validation: %s" % validation_error)

	_audit_required_key(stage.title_key, context + ".title_key")
	_audit_required_key(stage.subtitle_key, context + ".subtitle_key")
	_audit_required_key(stage.result_key, context + ".result_key")
	_audit_required_key(stage.pause_key, context + ".pause_key")
	_audit_required_key(stage.briefing_eyebrow_key, context + ".briefing_eyebrow_key")
	_audit_required_key(stage.briefing_situation_key, context + ".briefing_situation_key")
	_audit_required_key(stage.briefing_objective_key, context + ".briefing_objective_key")
	_audit_required_key(stage.briefing_transmission_source_key, context + ".briefing_transmission_source_key")
	_audit_required_key(stage.briefing_transmission_key, context + ".briefing_transmission_key")
	_audit_required_key(stage.midboss_subtitle_key, context + ".midboss_subtitle_key")
	_audit_required_key(stage.midboss_defeat_title_key, context + ".midboss_defeat_title_key")
	_audit_required_key(stage.midboss_defeat_subtitle_key, context + ".midboss_defeat_subtitle_key")
	_audit_required_key(stage.final_boss_subtitle_key, context + ".final_boss_subtitle_key")
	_audit_required_key(stage.final_boss_defeat_title_key, context + ".final_boss_defeat_title_key")
	_audit_required_key(stage.final_boss_defeat_subtitle_key, context + ".final_boss_defeat_subtitle_key")

	_audit_timeline(stage, context)
	_audit_radio_events(stage, context)
	_audit_enemy(stage.grade_3_enemy_id, 3, context + ".grade_3_enemy_id")
	_audit_enemy(stage.grade_2_enemy_id, 2, context + ".grade_2_enemy_id")
	_audit_enemy(stage.grade_1_enemy_id, 1, context + ".grade_1_enemy_id")
	var midboss_hp := _audit_boss(stage.midboss_id, false, stage.midboss_name_key, MIDBOSS_PHASE_COUNT, context + ".midboss")
	var final_boss_hp := _audit_boss(stage.final_boss_id, true, stage.final_boss_name_key, FINAL_BOSS_PHASE_COUNT, context + ".final_boss")
	var stage_boss_hp := midboss_hp + final_boss_hp
	if stage_boss_hp < MIN_STAGE_BOSS_TOTAL_HP or stage_boss_hp > MAX_STAGE_BOSS_TOTAL_HP:
		_fail(context + ".boss_total_hp", "authored midboss + final-boss HP must be %.0f..%.0f, got %.0f" % [
			MIN_STAGE_BOSS_TOTAL_HP, MAX_STAGE_BOSS_TOTAL_HP, stage_boss_hp
		])
	if stage.expected_boss_phase_count != MIDBOSS_PHASE_COUNT + FINAL_BOSS_PHASE_COUNT:
		_fail(context + ".expected_boss_phase_count", "must equal %d (%d midboss + %d final)" % [
			MIDBOSS_PHASE_COUNT + FINAL_BOSS_PHASE_COUNT, MIDBOSS_PHASE_COUNT, FINAL_BOSS_PHASE_COUNT
		])
	_audit_hazards(stage, context)


func _audit_campaign_ending(catalog: Array) -> void:
	var ending_count := 0
	for stage_index in catalog.size():
		var stage: Variant = catalog[stage_index]
		if stage == null or not stage.ending_enabled:
			continue
		ending_count += 1
		var context := "stage[%s].ending" % stage.stage_id
		if stage_index != catalog.size() - 1:
			_fail(context, "only the final catalog stage may enable the campaign ending")
		_audit_required_key(stage.ending_eyebrow_key, context + ".ending_eyebrow_key")
		_audit_required_key(stage.ending_title_key, context + ".ending_title_key")
		_audit_required_key(stage.ending_body_key, context + ".ending_body_key")
		_audit_required_key(stage.ending_transmission_source_key, context + ".ending_transmission_source_key")
		_audit_required_key(stage.ending_transmission_key, context + ".ending_transmission_key")
		if stage.ending_epilogue_keys.size() != 3:
			_fail(context + ".ending_epilogue_keys", "must contain one localized epilogue for each playable character")
		for epilogue_index in stage.ending_epilogue_keys.size():
			_audit_required_key(stage.ending_epilogue_keys[epilogue_index], "%s.ending_epilogue_keys[%d]" % [context, epilogue_index])
	if catalog.size() > 1 and ending_count != 1:
		_fail("catalog.ending", "a multi-stage campaign must author exactly one ending on its final stage")
	for key in ["campaign_ending", "ending_epilogue", "ending_final_transmission", "ending_view_results", "ending_skip_hint", "ending_score_stamp"]:
		_audit_required_key(key, "catalog.ending.ui")


func _audit_radio_events(stage: Variant, context: String) -> void:
	var count: int = stage.radio_events.size()
	if count < MIN_RADIO_EVENTS_PER_STAGE or count > MAX_RADIO_EVENTS_PER_STAGE:
		_fail(context + ".radio_events", "must contain %d..%d authored transmissions, got %d" % [
			MIN_RADIO_EVENTS_PER_STAGE, MAX_RADIO_EVENTS_PER_STAGE, count
		])
	if stage.timeline == null:
		return
	var has_opening := false
	var has_pre_midboss := false
	var has_post_midboss := false
	var has_pre_final_warning := false
	for event_index in count:
		var radio_event: Variant = stage.radio_events[event_index]
		var event_context := "%s.radio_events[%d]" % [context, event_index]
		if radio_event == null:
			continue
		radio_event_count += 1
		_audit_stable_id(radio_event.event_id, event_context + ".event_id")
		_claim_unique(radio_event_ids, radio_event.event_id, event_context + ".event_id", "radio event ID")
		_audit_required_key(radio_event.speaker_key, event_context + ".speaker_key")
		_audit_required_key(radio_event.message_key, event_context + ".message_key")
		var trigger_time := float(radio_event.trigger_time)
		var display_end := trigger_time + float(radio_event.duration)
		if trigger_time < stage.timeline.midboss_spawn_time and display_end > stage.timeline.midboss_spawn_time + EPSILON:
			_fail(event_context, "display window %.3f..%.3f overlaps midboss entry at %.3fs" % [
				trigger_time, display_end, stage.timeline.midboss_spawn_time
			])
		if trigger_time < stage.timeline.boss_warning_time and display_end > stage.timeline.boss_warning_time + EPSILON:
			_fail(event_context, "display window %.3f..%.3f overlaps final warning at %.3fs" % [
				trigger_time, display_end, stage.timeline.boss_warning_time
			])
		has_opening = has_opening or (trigger_time + EPSILON >= stage.timeline.wave_start_time
			and trigger_time <= stage.timeline.wave_start_time + 15.0 + EPSILON)
		has_pre_midboss = has_pre_midboss or (trigger_time + EPSILON >= stage.timeline.midboss_spawn_time - RADIO_BEAT_WINDOW_SECONDS
			and trigger_time <= stage.timeline.midboss_spawn_time - 2.0 + EPSILON)
		has_post_midboss = has_post_midboss or (trigger_time + EPSILON >= stage.timeline.midboss_spawn_time + 1.0
			and trigger_time <= stage.timeline.midboss_spawn_time + RADIO_BEAT_WINDOW_SECONDS + EPSILON)
		has_pre_final_warning = has_pre_final_warning or (trigger_time + EPSILON >= stage.timeline.boss_warning_time - RADIO_BEAT_WINDOW_SECONDS
			and trigger_time <= stage.timeline.boss_warning_time - 2.0 + EPSILON)
	if not has_opening:
		_fail(context + ".radio_events", "missing an opening transmission in the first 15 seconds after wave start")
	if not has_pre_midboss:
		_fail(context + ".radio_events", "missing a transmission 2..%.0f seconds before midboss entry" % RADIO_BEAT_WINDOW_SECONDS)
	if not has_post_midboss:
		_fail(context + ".radio_events", "missing a post-midboss transmission within %.0f seconds of route resumption" % RADIO_BEAT_WINDOW_SECONDS)
	if not has_pre_final_warning:
		_fail(context + ".radio_events", "missing a transmission 2..%.0f seconds before the final warning" % RADIO_BEAT_WINDOW_SECONDS)


func _audit_timeline(stage: Variant, context: String) -> void:
	var timeline: Variant = stage.timeline
	if timeline == null:
		return
	if not is_equal_approx(timeline.wave_start_time, WAVE_START_SECONDS):
		_fail(context + ".timeline.wave_start_time", "must be exactly %.1fs, got %.3fs" % [WAVE_START_SECONDS, timeline.wave_start_time])
	if not is_equal_approx(timeline.boss_spawn_time, ROUTE_SECONDS):
		_fail(context + ".timeline.boss_spawn_time", "must be exactly %.1fs of route time, got %.3fs" % [ROUTE_SECONDS, timeline.boss_spawn_time])
	if timeline.enemies_per_wave != ENEMIES_PER_WAVE:
		_fail(context + ".timeline.enemies_per_wave", "must equal %d, got %d" % [ENEMIES_PER_WAVE, timeline.enemies_per_wave])
	if timeline.early_grade_3_count != EARLY_GRADE_3_COUNT:
		_fail(context + ".timeline.early_grade_3_count", "must equal %d, got %d" % [EARLY_GRADE_3_COUNT, timeline.early_grade_3_count])
	if timeline.middle_grade_3_count != MIDDLE_GRADE_3_COUNT:
		_fail(context + ".timeline.middle_grade_3_count", "must equal %d, got %d" % [MIDDLE_GRADE_3_COUNT, timeline.middle_grade_3_count])
	if timeline.late_grade_3_count != LATE_GRADE_3_COUNT:
		_fail(context + ".timeline.late_grade_3_count", "must equal %d, got %d" % [LATE_GRADE_3_COUNT, timeline.late_grade_3_count])
	if not (timeline.wave_start_time < timeline.early_wave_end
			and timeline.early_wave_end < timeline.midboss_spawn_time
			and timeline.midboss_spawn_time < timeline.late_wave_start
			and timeline.late_wave_start < timeline.boss_warning_time
			and timeline.boss_warning_time < timeline.boss_spawn_time):
		_fail(context + ".timeline", "route markers must be strictly ordered from wave start through final boss")
	_audit_wave_budget(timeline, context)


func _audit_wave_budget(timeline: Variant, context: String) -> void:
	for interval_name in ["early_wave_interval", "middle_wave_interval", "late_wave_interval"]:
		var interval := float(timeline.get(interval_name))
		if interval <= 0.0:
			_fail(context + ".timeline.%s" % interval_name, "must be positive, got %.3f" % interval)
			return
	var cutoff := minf(float(timeline.boss_warning_time), float(timeline.boss_spawn_time))
	var scheduled_time := float(timeline.wave_start_time)
	var waves := 0
	while scheduled_time < cutoff - EPSILON:
		waves += 1
		var interval := float(timeline.late_wave_interval)
		if scheduled_time < timeline.early_wave_end:
			interval = float(timeline.early_wave_interval)
		elif scheduled_time < timeline.late_wave_start:
			interval = float(timeline.middle_wave_interval)
		scheduled_time += interval
		if waves > MAX_WAVES_PER_STAGE + 1:
			break
	var enemies := waves * int(timeline.enemies_per_wave)
	expected_wave_count += waves
	expected_enemy_count += enemies
	if waves < MIN_WAVES_PER_STAGE or waves > MAX_WAVES_PER_STAGE:
		_fail(context + ".timeline.wave_budget", "expected route waves must be %d..%d, got %d" % [
			MIN_WAVES_PER_STAGE, MAX_WAVES_PER_STAGE, waves
		])
	if enemies < MIN_ENEMIES_PER_STAGE or enemies > MAX_ENEMIES_PER_STAGE:
		_fail(context + ".timeline.enemy_budget", "expected route enemies must be %d..%d, got %d (%d waves x %d enemies)" % [
			MIN_ENEMIES_PER_STAGE, MAX_ENEMIES_PER_STAGE, enemies, waves, timeline.enemies_per_wave
		])


func _audit_enemy(enemy_id: String, expected_grade: int, context: String) -> void:
	_audit_stable_id(enemy_id, context)
	_claim_unique(enemy_ids, enemy_id, context, "stage enemy ID")
	if not game_database_script.has_enemy(enemy_id):
		_fail(context, "is not present in GameDatabase.ENEMY_IDS")
		return
	var enemy: Variant = game_database_script.enemy(enemy_id)
	if enemy == null or enemy.id != enemy_id:
		_fail(context, "does not resolve exactly (fallbacks are forbidden)")
		return
	if enemy.grade != expected_grade:
		_fail(context, "must resolve to grade %d, got grade %d" % [expected_grade, enemy.grade])


func _audit_boss(boss_id: String, expected_final: bool, expected_name_key: String, expected_phases: int, context: String) -> float:
	_audit_stable_id(boss_id, context + ".boss_id")
	_claim_unique(boss_ids, boss_id, context + ".boss_id", "boss ID")
	_audit_required_key(expected_name_key, context + ".display_name_key")
	var definition: Variant = boss_controller_script.definition_for_id(boss_id)
	if definition == null:
		_fail(context, "boss ID does not resolve exactly in BossController.BOSS_CATALOG")
		return 0.0
	boss_count += 1
	boss_phase_count += definition.phases.size()
	for validation_error in definition.validation_errors():
		_fail(context, "BossDefinitionData validation: %s" % validation_error)
	if definition.boss_id != boss_id:
		_fail(context + ".boss_id", "resource ID '%s' does not match catalog ID '%s'" % [definition.boss_id, boss_id])
	if definition.is_final != expected_final:
		_fail(context + ".is_final", "must be %s for this encounter role" % str(expected_final))
	if definition.display_name_key != expected_name_key:
		_fail(context + ".display_name_key", "must match StageData key '%s'" % expected_name_key)
	if definition.phases.size() != expected_phases:
		_fail(context + ".phases", "must contain exactly %d phases, got %d" % [expected_phases, definition.phases.size()])
	var total_hp := 0.0
	var min_phase_hp := MIN_FINAL_BOSS_PHASE_HP if expected_final else MIN_MIDBOSS_PHASE_HP
	var max_phase_hp := MAX_FINAL_BOSS_PHASE_HP if expected_final else MAX_MIDBOSS_PHASE_HP
	var min_fire_interval := MIN_FINAL_BOSS_FIRE_INTERVAL if expected_final else MIN_MIDBOSS_FIRE_INTERVAL
	var max_fire_interval := MAX_FINAL_BOSS_FIRE_INTERVAL if expected_final else MAX_MIDBOSS_FIRE_INTERVAL
	for phase_index in definition.phases.size():
		var phase: Variant = definition.phases[phase_index]
		if phase == null:
			continue
		var phase_context := "%s.phases[%d]" % [context, phase_index]
		if not boss_controller_script.supports_signature_id(phase.signature_id):
			_fail(phase_context + ".signature_id", "unregistered built-in signature '%s'" % phase.signature_id)
		_audit_required_key(phase.name_key, phase_context + ".name_key")
		_claim_unique(phase_name_keys, phase.name_key, phase_context + ".name_key", "boss phase name key")
		total_hp += float(phase.hp)
		if phase.hp < min_phase_hp or phase.hp > max_phase_hp:
			_fail(phase_context + ".hp", "authored phase HP must be %.0f..%.0f, got %.0f" % [min_phase_hp, max_phase_hp, phase.hp])
		if phase.fire_interval < min_fire_interval or phase.fire_interval > max_fire_interval:
			_fail(phase_context + ".fire_interval", "must be %.2f..%.2fs, got %.3fs" % [
				min_fire_interval, max_fire_interval, phase.fire_interval
			])
		if phase.attack_sequence.size() < MIN_ATTACK_SEQUENCE_LENGTH or phase.attack_sequence.size() > MAX_ATTACK_SEQUENCE_LENGTH:
			_fail(phase_context + ".attack_sequence", "must contain %d..%d authored attacks, got %d" % [
				MIN_ATTACK_SEQUENCE_LENGTH, MAX_ATTACK_SEQUENCE_LENGTH, phase.attack_sequence.size()
			])
		var declared_patterns := {}
		for pattern_id in phase.pattern_ids:
			if declared_patterns.has(pattern_id):
				_fail(phase_context + ".pattern_ids", "declares duplicate pattern '%s'" % pattern_id)
			declared_patterns[pattern_id] = true
		if declared_patterns.size() < MIN_PHASE_PATTERN_DIVERSITY or declared_patterns.size() > MAX_PHASE_PATTERN_DIVERSITY:
			_fail(phase_context + ".pattern_ids", "must declare %d..%d distinct patterns, got %d" % [
				MIN_PHASE_PATTERN_DIVERSITY, MAX_PHASE_PATTERN_DIVERSITY, declared_patterns.size()
			])
		var sequence_patterns := {}
		var previous_pattern := ""
		for sequence_index in phase.attack_sequence.size():
			var pattern_id := String(phase.attack_sequence[sequence_index])
			sequence_patterns[pattern_id] = true
			if not declared_patterns.has(pattern_id):
				_fail(phase_context + ".attack_sequence[%d]" % sequence_index, "pattern '%s' is not declared in pattern_ids" % pattern_id)
			if pattern_id == previous_pattern:
				_fail(phase_context + ".attack_sequence[%d]" % sequence_index, "may not repeat pattern '%s' consecutively" % pattern_id)
			previous_pattern = pattern_id
		if sequence_patterns.size() < MIN_PHASE_PATTERN_DIVERSITY or sequence_patterns.size() > MAX_PHASE_PATTERN_DIVERSITY:
			_fail(phase_context + ".attack_sequence", "must exercise %d..%d distinct patterns, got %d" % [
				MIN_PHASE_PATTERN_DIVERSITY, MAX_PHASE_PATTERN_DIVERSITY, sequence_patterns.size()
			])
	var min_total_hp := MIN_FINAL_BOSS_TOTAL_HP if expected_final else MIN_MIDBOSS_TOTAL_HP
	var max_total_hp := MAX_FINAL_BOSS_TOTAL_HP if expected_final else MAX_MIDBOSS_TOTAL_HP
	if total_hp < min_total_hp or total_hp > max_total_hp:
		_fail(context + ".total_hp", "authored encounter HP must be %.0f..%.0f, got %.0f" % [min_total_hp, max_total_hp, total_hp])
	_audit_texture(definition.key_art, context + ".key_art", false)
	_audit_texture(definition.combat_art, context + ".combat_art", true)
	return total_hp


func _audit_texture(texture: Variant, context: String, is_combat_sheet: bool) -> void:
	if texture == null:
		return
	texture_count += 1
	var width := int(texture.get_width())
	var height := int(texture.get_height())
	var minimum := MIN_COMBAT_SHEET_DIMENSION if is_combat_sheet else MIN_KEY_ART_DIMENSION
	if width < minimum or height < minimum:
		_fail(context, "texture '%s' must be at least %dx%d, got %dx%d" % [texture.resource_path, minimum, minimum, width, height])
	if not is_combat_sheet:
		return
	if width % 2 != 0 or height % 2 != 0:
		_fail(context, "2x2 combat sheet '%s' must have even dimensions, got %dx%d" % [texture.resource_path, width, height])
	if width / 2 < MIN_COMBAT_FRAME_DIMENSION or height / 2 < MIN_COMBAT_FRAME_DIMENSION:
		_fail(context, "each 2x2 combat frame must be at least %dx%d, got %dx%d" % [
			MIN_COMBAT_FRAME_DIMENSION, MIN_COMBAT_FRAME_DIMENSION, width / 2, height / 2
		])


func _audit_hazards(stage: Variant, context: String) -> void:
	if stage.timeline == null:
		return
	var stage_trigger_count := 0
	for hazard_index in stage.hazard_events.size():
		var hazard: Variant = stage.hazard_events[hazard_index]
		var hazard_context := "%s.hazards[%d]" % [context, hazard_index]
		if hazard == null:
			continue
		hazard_count += 1
		_audit_stable_id(hazard.hazard_id, hazard_context + ".hazard_id")
		_claim_unique(hazard_ids, hazard.hazard_id, hazard_context + ".hazard_id", "hazard ID")
		if hazard.warning_time + EPSILON < MIN_HAZARD_WARNING_SECONDS:
			_fail(hazard_context + ".warning_time", "must be at least %.1fs, got %.3fs" % [MIN_HAZARD_WARNING_SECONDS, hazard.warning_time])
		if hazard.interval <= 0.0 or hazard.end_time < hazard.start_time:
			continue
		var trigger_time := float(hazard.start_time)
		var trigger_index := 0
		while trigger_time <= hazard.end_time + EPSILON:
			var effect_end := trigger_time + _hazard_lifetime(hazard)
			if _point_in_closed_interval(stage.timeline.midboss_spawn_time, trigger_time, effect_end):
				_fail(hazard_context, "trigger %d lifecycle %.3f..%.3f overlaps midboss entry at %.3fs" % [
					trigger_index, trigger_time, effect_end, stage.timeline.midboss_spawn_time
				])
			if _closed_intervals_overlap(trigger_time, effect_end, stage.timeline.boss_warning_time, stage.timeline.boss_spawn_time):
				_fail(hazard_context, "trigger %d lifecycle %.3f..%.3f overlaps final-boss warning window %.3f..%.3f" % [
					trigger_index, trigger_time, effect_end, stage.timeline.boss_warning_time, stage.timeline.boss_spawn_time
				])
			trigger_index += 1
			stage_trigger_count += 1
			trigger_time = hazard.start_time + float(trigger_index) * hazard.interval
			if trigger_index > 20000:
				_fail(hazard_context, "produces more than 20,000 scheduled triggers")
				break
	hazard_trigger_count += stage_trigger_count
	if stage_trigger_count > MAX_HAZARD_TRIGGERS_PER_STAGE:
		_fail(context + ".hazards", "scheduled hazard triggers must not exceed %d, got %d" % [
			MAX_HAZARD_TRIGGERS_PER_STAGE, stage_trigger_count
		])


func _hazard_lifetime(hazard: Variant) -> float:
	if hazard.kind == "debris_field":
		return hazard.warning_time + float(maxi(0, hazard.burst_count - 1)) * 0.08 + HAZARD_PLAYFIELD_HEIGHT / maxf(hazard.speed, EPSILON) + 2.0
	return hazard.warning_time + hazard.active_time


func _audit_localization_parity() -> void:
	var en_keys: Array = game_text_script.EN.keys()
	var ko_keys: Array = game_text_script.KO.keys()
	for key_value in en_keys:
		var key := String(key_value)
		if not game_text_script.KO.has(key):
			_fail("localization.KO", "missing key '%s' present in EN" % key)
			continue
		if String(game_text_script.EN[key]).strip_edges().is_empty():
			_fail("localization.EN.%s" % key, "translation is empty")
		if String(game_text_script.KO[key]).strip_edges().is_empty():
			_fail("localization.KO.%s" % key, "translation is empty")
		if _format_tokens(String(game_text_script.EN[key])) != _format_tokens(String(game_text_script.KO[key])):
			_fail("localization.%s" % key, "EN/KO printf placeholders do not match")
	for key_value in ko_keys:
		var key := String(key_value)
		if not game_text_script.EN.has(key):
			_fail("localization.EN", "missing key '%s' present in KO" % key)
	for key in BASE_REQUIRED_TEXT_KEYS:
		_audit_required_key(key, "localization.required")


func _audit_required_key(key: String, context: String) -> void:
	_audit_stable_id(key, context)
	if not game_text_script.EN.has(key):
		_fail(context, "required localization key '%s' is missing from EN" % key)
	elif String(game_text_script.EN[key]).strip_edges().is_empty():
		_fail(context, "required EN localization '%s' is empty" % key)
	if not game_text_script.KO.has(key):
		_fail(context, "required localization key '%s' is missing from KO" % key)
	elif String(game_text_script.KO[key]).strip_edges().is_empty():
		_fail(context, "required KO localization '%s' is empty" % key)


func _audit_stable_id(value: String, context: String, stage_suffix_required: bool = false) -> void:
	if value.is_empty():
		_fail(context, "stable ID must not be empty")
		return
	var regex := RegEx.new()
	var pattern := "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*_[0-9]{2}$" if stage_suffix_required else "^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$"
	if regex.compile(pattern) != OK or regex.search(value) == null:
		var rule := "lower_snake_case ending in a two-digit sequence" if stage_suffix_required else "lower_snake_case"
		_fail(context, "'%s' must use %s" % [value, rule])


func _claim_unique(registry: Dictionary, value: Variant, context: String, label: String) -> void:
	if registry.has(value):
		_fail(context, "duplicate %s '%s'; first declared at %s" % [label, str(value), String(registry[value])])
		return
	registry[value] = context


func _closed_intervals_overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> bool:
	return a_start <= b_end + EPSILON and b_start <= a_end + EPSILON


func _point_in_closed_interval(point: float, start: float, end: float) -> bool:
	return point + EPSILON >= start and point - EPSILON <= end


func _format_tokens(value: String) -> PackedStringArray:
	var regex := RegEx.new()
	regex.compile("%(?:[0-9]+\\$)?[-+ #0]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[diouxXeEfFgGsc%]")
	var tokens := PackedStringArray()
	for result in regex.search_all(value):
		var token := result.get_string()
		if token != "%%":
			tokens.append(token)
	return tokens


func _fail(context: String, message: String) -> void:
	errors.append("[%s] %s" % [context, message])
