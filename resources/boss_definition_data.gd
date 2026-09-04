class_name BossDefinitionData
extends Resource

## Editor-authored identity, presentation, and phase roster for one boss.
## Combat code consumes the stable ID; all player-facing text remains a key.

@export_group("Identity")
@export var boss_id := ""
@export var display_name_key := ""
@export var is_final := false

@export_group("Presentation")
@export var key_art: Texture2D
@export var combat_art: Texture2D
@export_range(1.0, 256.0, 1.0) var radius := 58.0
@export var art_size := Vector2(208.0, 208.0)
@export var fallback_rect := Rect2(-104.0, -90.0, 208.0, 208.0)
@export_range(0.0, 0.2, 0.001) var bank_amount := 0.018
@export_range(0.1, 20.0, 0.1) var death_duration := 2.1

@export_group("Combat")
@export var phases: Array[BossPhaseData] = []

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if boss_id.strip_edges().is_empty():
		errors.append("boss_id is empty")
	if display_name_key.strip_edges().is_empty():
		errors.append("display_name_key is empty")
	if key_art == null:
		errors.append("key_art is missing")
	if combat_art == null:
		errors.append("combat_art is missing")
	if radius <= 0.0:
		errors.append("radius must be positive")
	if art_size.x <= 0.0 or art_size.y <= 0.0:
		errors.append("art_size must be positive")
	if fallback_rect.size.x <= 0.0 or fallback_rect.size.y <= 0.0:
		errors.append("fallback_rect size must be positive")
	if death_duration <= 0.0:
		errors.append("death_duration must be positive")
	if phases.is_empty():
		errors.append("phases is empty")
	for phase_index in phases.size():
		var phase := phases[phase_index]
		if phase == null:
			errors.append("phases[%d] is missing" % phase_index)
			continue
		if phase.name_key.strip_edges().is_empty():
			errors.append("phases[%d].name_key is empty" % phase_index)
		if phase.hp <= 0.0:
			errors.append("phases[%d].hp must be positive" % phase_index)
		if phase.duration <= 0.0:
			errors.append("phases[%d].duration must be positive" % phase_index)
		if phase.fire_interval <= 0.0 or phase.telegraph_time < 0.0 or phase.transition_time < 0.0:
			errors.append("phases[%d] has invalid timing" % phase_index)
		if not ["hover", "wide", "cross", "aggressive"].has(phase.movement_id):
			errors.append("phases[%d] has an unknown movement ID" % phase_index)
		if phase.signature_id.strip_edges().is_empty():
			errors.append("phases[%d].signature_id is empty" % phase_index)
		if phase.pattern_ids.is_empty() and phase.attack_sequence.is_empty():
			errors.append("phases[%d] has no attacks" % phase_index)
		for pattern_id in phase.pattern_ids:
			if not GameDatabase.has_pattern(pattern_id):
				errors.append("phases[%d] has an unknown pattern ID: %s" % [phase_index, pattern_id])
		for pattern_id in phase.attack_sequence:
			if not GameDatabase.has_pattern(pattern_id):
				errors.append("phases[%d] has an unknown sequence pattern ID: %s" % [phase_index, pattern_id])
	return errors

func is_valid() -> bool:
	return validation_errors().is_empty()
