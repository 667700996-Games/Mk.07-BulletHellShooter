extends Node

const SAVE_PATH := "user://psychic_vector.cfg"
const SAVE_BACKUP_PATH := "user://psychic_vector.backup.cfg"
const SAVE_STAGING_PATH := "user://psychic_vector.pending.cfg"
const SAVE_VERSION := 13
const LEGACY_UNSIGNED_VERSION := 6
const LEGACY_DEFAULT_STAGE_ID := "neon_district_01"
const MAX_RUN_HISTORY := 60
const PLAYTEST_EXPORT_PATH := "user://psychic_vector_playtest.json"
const DIFFICULTY_IDS := ["story", "normal", "expert"]
const ASSIST_PRESET_IDS := ["standard", "comfort", "guardian"]
const ASSIST_SETTING_KEYS := ["shake", "flash", "bullet_contrast", "auto_fire", "auto_barrier", "show_hitbox"]
const ASSIST_PRESETS := {
	"standard": {"shake": 0.85, "flash": 0.85, "bullet_contrast": 0.8, "auto_fire": false, "auto_barrier": false, "show_hitbox": false},
	"comfort": {"shake": 0.35, "flash": 0.25, "bullet_contrast": 1.0, "auto_fire": true, "auto_barrier": false, "show_hitbox": true},
	"guardian": {"shake": 0.15, "flash": 0.1, "bullet_contrast": 1.0, "auto_fire": true, "auto_barrier": true, "show_hitbox": true}
}
const REBIND_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"primary", "focus", "barrier"
]
const DEFAULT_BINDINGS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"primary": KEY_Z,
	"focus": KEY_X,
	"barrier": KEY_C
}
const GAMEPAD_REBIND_ACTIONS := ["primary", "focus", "barrier"]
const DEFAULT_GAMEPAD_BINDINGS := {"primary": 0, "focus": 2, "barrier": 1}
const SAVE_SETTING_KEYS := [
	"master", "music", "sfx", "shake", "flash", "bullet_contrast",
	"auto_fire", "auto_barrier", "show_hitbox", "assist_preset", "language", "fullscreen"
]

var high_score := 0
var high_scores := {"story": 0, "normal": 0, "expert": 0}
var stage_high_scores: Dictionary = {
	LEGACY_DEFAULT_STAGE_ID: {"story": 0, "normal": 0, "expert": 0}
}
var unlocked_stage_ids := PackedStringArray([LEGACY_DEFAULT_STAGE_ID])
var selected_character := 0
var selected_difficulty := "normal"
var tutorial_completed := false
var keyboard_bindings: Dictionary = {}
var gamepad_bindings: Dictionary = {"primary": 0, "focus": 2, "barrier": 1}
var run_history: Array[Dictionary] = []
var persistence_enabled := true
var recovered_from_backup := false
var settings := {
	"master": 0.82,
	"music": 0.68,
	"sfx": 0.82,
	"shake": 0.85,
	"flash": 0.85,
	"bullet_contrast": 0.8,
	"auto_fire": false,
	"auto_barrier": false,
	"show_hitbox": false,
	"assist_preset": "standard",
	"language": "en",
	"fullscreen": false
}

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke") or argument.begins_with("--benchmark") or argument.begins_with("--capture"):
			persistence_enabled = false
			break
	load_data()
	apply_settings()

func load_data() -> void:
	recovered_from_backup = false
	var selection := _load_best_config(SAVE_PATH, SAVE_BACKUP_PATH)
	if selection.is_empty():
		return
	var config := selection.config as ConfigFile
	recovered_from_backup = bool(selection.recovered)
	var loaded_version := int(config.get_value("meta", "version", 0))
	var legacy_high_score := _nonnegative_score(config.get_value("record", "high_score", 0))
	high_scores.story = _nonnegative_score(config.get_value("record", "high_score_story", 0))
	high_scores.normal = _nonnegative_score(config.get_value("record", "high_score_normal", legacy_high_score))
	high_scores.expert = _nonnegative_score(config.get_value("record", "high_score_expert", 0))
	high_score = int(high_scores.normal)
	_load_stage_high_scores(config.get_value("record", "stage_high_scores", {}), loaded_version)
	_load_unlocked_stage_ids(config.get_value("progression", "unlocked_stage_ids", []))
	selected_character = clampi(int(config.get_value("profile", "character", 0)), 0, 2)
	selected_difficulty = String(config.get_value("profile", "difficulty", "normal"))
	tutorial_completed = bool(config.get_value("profile", "tutorial_completed", false))
	_sanitize_profile()
	for key in settings:
		settings[key] = config.get_value("settings", key, settings[key])
	_sanitize_settings()
	var used_keys := {}
	for action in REBIND_ACTIONS:
		var keycode := int(config.get_value("controls", action, 0))
		if keycode > 0 and not used_keys.has(keycode):
			keyboard_bindings[action] = keycode
			_apply_keyboard_binding(action, keycode)
			used_keys[keycode] = true
	var used_gamepad_buttons := {}
	for action in GAMEPAD_REBIND_ACTIONS:
		var button_index := int(config.get_value("controls", "gamepad_%s" % action, DEFAULT_GAMEPAD_BINDINGS[action]))
		if button_index >= 0 and button_index <= 31 and not used_gamepad_buttons.has(button_index):
			gamepad_bindings[action] = button_index
			_apply_gamepad_binding(action, button_index)
			used_gamepad_buttons[button_index] = true
	_load_run_history(config.get_value("telemetry", "run_history", []))
	if loaded_version < SAVE_VERSION or recovered_from_backup:
		save_data()

func save_data() -> void:
	if not persistence_enabled:
		return
	var config := _create_save_config()
	var error := _save_config_transaction(config, SAVE_PATH, SAVE_BACKUP_PATH, SAVE_STAGING_PATH)
	if error != OK:
		push_warning("Could not save player data safely: %s" % error_string(error))

func _create_save_config() -> ConfigFile:
	_sync_default_stage_scores_from_legacy()
	_sanitize_progression()
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("record", "high_score", high_score)
	for difficulty_id in DIFFICULTY_IDS:
		config.set_value("record", "high_score_%s" % difficulty_id, int(high_scores.get(difficulty_id, 0)))
	config.set_value("record", "stage_high_scores", stage_high_scores.duplicate(true))
	config.set_value("progression", "unlocked_stage_ids", unlocked_stage_ids.duplicate())
	config.set_value("profile", "character", selected_character)
	config.set_value("profile", "difficulty", selected_difficulty)
	config.set_value("profile", "tutorial_completed", tutorial_completed)
	for key in SAVE_SETTING_KEYS:
		config.set_value("settings", key, settings[key])
	for action in REBIND_ACTIONS:
		config.set_value("controls", action, keyboard_binding(action))
	for action in GAMEPAD_REBIND_ACTIONS:
		config.set_value("controls", "gamepad_%s" % action, gamepad_binding(action))
	config.set_value("telemetry", "run_history", run_history.duplicate(true))
	_seal_config(config)
	return config

func _save_config_transaction(config: ConfigFile, primary_path: String, backup_path: String, staging_path: String) -> Error:
	_remove_file(staging_path)
	var error := config.save(staging_path)
	if error != OK:
		return error
	var staged := ConfigFile.new()
	error = staged.load(staging_path)
	if error != OK or not _config_is_valid(staged):
		_remove_file(staging_path)
		return ERR_FILE_CORRUPT

	var current := ConfigFile.new()
	var current_valid := current.load(primary_path) == OK and _config_is_valid(current)
	if current_valid:
		error = current.save(backup_path)
		if error != OK or not _path_has_valid_config(backup_path):
			_remove_file(staging_path)
			return error if error != OK else ERR_FILE_CORRUPT
	if FileAccess.file_exists(primary_path):
		error = _remove_file(primary_path)
		if error != OK:
			_remove_file(staging_path)
			return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(staging_path), ProjectSettings.globalize_path(primary_path))
	if error != OK:
		_remove_file(staging_path)
		if current_valid:
			current.save(primary_path)
		return error
	if not _path_has_valid_config(backup_path):
		error = config.save(backup_path)
		if error != OK or not _path_has_valid_config(backup_path):
			return error if error != OK else ERR_FILE_CORRUPT
	return OK

func _load_best_config(primary_path: String, backup_path: String) -> Dictionary:
	var primary := ConfigFile.new()
	if primary.load(primary_path) == OK and _config_is_valid(primary):
		return {"config": primary, "recovered": false}
	var backup := ConfigFile.new()
	if backup.load(backup_path) == OK and _config_is_valid(backup):
		return {"config": backup, "recovered": true}
	return {}

func _path_has_valid_config(path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(path) == OK and _config_is_valid(config)

func _seal_config(config: ConfigFile) -> void:
	config.set_value("meta", "write_complete", true)
	config.set_value("meta", "integrity", _config_integrity(config))

func _config_is_valid(config: ConfigFile) -> bool:
	var version := int(config.get_value("meta", "version", 0))
	if version < 0:
		return false
	if version <= LEGACY_UNSIGNED_VERSION:
		return config.has_section_key("meta", "version") or config.has_section_key("record", "high_score")
	if not bool(config.get_value("meta", "write_complete", false)):
		return false
	var expected := String(config.get_value("meta", "integrity", ""))
	return not expected.is_empty() and expected == _config_integrity(config)

func _config_integrity(config: ConfigFile) -> String:
	var payload := [
		int(config.get_value("meta", "version", 0)),
		bool(config.get_value("meta", "write_complete", false)),
		[int(config.get_value("record", "high_score", 0))],
		[int(config.get_value("profile", "character", 0)), String(config.get_value("profile", "difficulty", "normal"))],
		config.get_value("telemetry", "run_history", [])
	]
	if int(config.get_value("meta", "version", 0)) >= 8:
		payload[3].append(bool(config.get_value("profile", "tutorial_completed", false)))
	for difficulty_id in DIFFICULTY_IDS:
		payload[2].append(int(config.get_value("record", "high_score_%s" % difficulty_id, 0)))
	var saved_settings: Array = []
	for key in SAVE_SETTING_KEYS:
		saved_settings.append([key, config.get_value("settings", key, null)])
	payload.append(saved_settings)
	var saved_controls: Array = []
	for action in REBIND_ACTIONS:
		saved_controls.append([action, int(config.get_value("controls", action, 0))])
	for action in GAMEPAD_REBIND_ACTIONS:
		saved_controls.append(["gamepad_%s" % action, int(config.get_value("controls", "gamepad_%s" % action, -1))])
	payload.append(saved_controls)
	# Versions 7-10 were already signed without progression data. Keep their
	# payload byte-for-byte compatible so valid legacy saves can still migrate.
	if int(config.get_value("meta", "version", 0)) >= 11:
		payload.append(["stage_high_scores", config.get_value("record", "stage_high_scores", {})])
		payload.append(["unlocked_stage_ids", config.get_value("progression", "unlocked_stage_ids", [])])
	return JSON.stringify(_canonical_variant(payload)).sha256_text()

func _canonical_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var pairs: Array = []
		for key in keys:
			pairs.append([String(key), _canonical_variant(value[key])])
		return pairs
	if value is Array:
		var normalized: Array = []
		for item in value:
			normalized.append(_canonical_variant(item))
		return normalized
	return value

func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func submit_score(value: int, difficulty_id: String = "normal", stage_id: String = LEGACY_DEFAULT_STAGE_ID) -> void:
	var safe_id := difficulty_id if DIFFICULTY_IDS.has(difficulty_id) else "normal"
	var safe_stage_id := _known_stage_id(stage_id)
	if safe_stage_id.is_empty():
		return
	var current := high_score_for(safe_id, safe_stage_id)
	var safe_value := maxi(0, value)
	if safe_value <= current:
		return
	if safe_stage_id == LEGACY_DEFAULT_STAGE_ID:
		high_scores[safe_id] = safe_value
		if safe_id == "normal":
			high_score = safe_value
		_sync_default_stage_scores_from_legacy()
	else:
		var scores := _scores_for_stage(safe_stage_id)
		scores[safe_id] = safe_value
		stage_high_scores[safe_stage_id] = scores
	save_data()

func high_score_for(difficulty_id: String, stage_id: String = LEGACY_DEFAULT_STAGE_ID) -> int:
	var safe_id := difficulty_id if DIFFICULTY_IDS.has(difficulty_id) else "normal"
	var safe_stage_id := _known_stage_id(stage_id)
	if safe_stage_id.is_empty():
		return 0
	# These fields predate the stage catalog and remain live compatibility
	# mirrors for code that still reads or restores them directly.
	if safe_stage_id == LEGACY_DEFAULT_STAGE_ID:
		return _nonnegative_score(high_scores.get(safe_id, 0))
	return _nonnegative_score(_scores_for_stage(safe_stage_id).get(safe_id, 0))

func is_stage_unlocked(stage_id: String) -> bool:
	var safe_stage_id := _known_stage_id(stage_id)
	if safe_stage_id.is_empty():
		return false
	return safe_stage_id == LEGACY_DEFAULT_STAGE_ID or unlocked_stage_ids.has(safe_stage_id)

func register_stage_clear(stage_id: String) -> bool:
	var changed := _register_stage_clear(stage_id)
	if changed:
		save_data()
	return changed

func record_run(result: Dictionary, character_index: int) -> void:
	var raw_entry := result.duplicate(true)
	raw_entry["timestamp"] = int(Time.get_unix_time_from_system())
	raw_entry["character"] = clampi(character_index, 0, 2)
	var entry := _sanitize_run_entry(raw_entry)
	if entry.is_empty():
		return
	run_history.append(entry)
	while run_history.size() > MAX_RUN_HISTORY:
		run_history.remove_at(0)
	if bool(entry.get("cleared", false)):
		_register_stage_clear(String(entry.get("stage_id", LEGACY_DEFAULT_STAGE_ID)))
	save_data()

func run_summary(difficulty_id: String = "", character_index: int = -1, stage_id: String = "") -> Dictionary:
	return summarize_runs(run_history, difficulty_id, character_index, stage_id)

func summarize_runs(entries: Array, difficulty_id: String = "", character_index: int = -1, stage_id: String = "") -> Dictionary:
	var runs := 0
	var clears := 0
	var assisted_runs := 0
	var total_deaths := 0
	var total_barriers := 0
	var total_clear_time := 0.0
	var best_clear_time := 0.0
	var best_score := 0
	var phase_count := 0
	var overdrive_count := 0
	var medals_earned := 0
	var total_medal_bonus := 0
	var medal_counts := {}
	var risk_banks := 0
	var total_risk_bank_bonus := 0
	var total_risk_reserve_lost := 0
	for definition in ScoreManager.medal_definitions():
		medal_counts[String(definition.id)] = 0
	for entry in entries:
		if not entry is Dictionary:
			continue
		if not difficulty_id.is_empty() and String(entry.get("difficulty", "normal")) != difficulty_id:
			continue
		if character_index >= 0 and int(entry.get("character", 0)) != character_index:
			continue
		if not stage_id.is_empty() and String(entry.get("stage_id", LEGACY_DEFAULT_STAGE_ID)) != stage_id:
			continue
		runs += 1
		assisted_runs += int(bool(entry.get("assisted", false)))
		total_deaths += int(entry.get("deaths", 0))
		total_barriers += int(entry.get("barriers_used", 0))
		if not bool(entry.get("assisted", false)):
			best_score = maxi(best_score, int(entry.get("total_score", 0)))
		if bool(entry.get("cleared", false)):
			clears += 1
			var clear_time := float(entry.get("clear_time", 0.0))
			total_clear_time += clear_time
			if best_clear_time <= 0.0 or clear_time < best_clear_time:
				best_clear_time = clear_time
		for metric in entry.get("boss_phase_metrics", []):
			phase_count += 1
			overdrive_count += int(bool(metric.get("overdrive", false)))
		var entry_medals := ScoreManager.normalize_medal_ids(entry.get("medals", []))
		medals_earned += entry_medals.size()
		total_medal_bonus += int(entry.get("medal_bonus", 0))
		for medal_id in entry_medals:
			medal_counts[medal_id] = int(medal_counts.get(medal_id, 0)) + 1
		var entry_banks := ScoreManager.normalize_risk_bank_events(entry.get("risk_bank_events", []))
		risk_banks += entry_banks.size()
		total_risk_bank_bonus += int(entry.get("risk_bank_bonus", 0))
		total_risk_reserve_lost += int(entry.get("risk_reserve_lost", 0))
	return {
		"runs": runs,
		"clears": clears,
		"clear_rate": float(clears) / float(runs) if runs > 0 else 0.0,
		"assisted_runs": assisted_runs,
		"average_deaths": float(total_deaths) / float(runs) if runs > 0 else 0.0,
		"average_barriers": float(total_barriers) / float(runs) if runs > 0 else 0.0,
		"average_clear_time": total_clear_time / float(clears) if clears > 0 else 0.0,
		"best_clear_time": best_clear_time,
		"best_score": best_score,
		"phases_seen": phase_count,
		"overdrive_rate": float(overdrive_count) / float(phase_count) if phase_count > 0 else 0.0,
		"medals_earned": medals_earned,
		"total_medal_bonus": total_medal_bonus,
		"medal_counts": medal_counts,
		"risk_banks": risk_banks,
		"total_risk_bank_bonus": total_risk_bank_bonus,
		"average_risk_bank_bonus": float(total_risk_bank_bonus) / float(runs) if runs > 0 else 0.0,
		"total_risk_reserve_lost": total_risk_reserve_lost
	}

func playtest_export_json() -> String:
	var summaries := {}
	for difficulty_id in DIFFICULTY_IDS:
		var character_summaries: Array[Dictionary] = []
		for character_index in 3:
			character_summaries.append(run_summary(difficulty_id, character_index))
		summaries[difficulty_id] = {
			"all": run_summary(difficulty_id),
			"characters": character_summaries
		}
	var stage_summaries := {}
	for stage_id in StageManager.stage_ids():
		var stage_summary := run_summary("", -1, stage_id)
		stage_summary["high_scores"] = _scores_for_stage(stage_id)
		stage_summary["unlocked"] = is_stage_unlocked(stage_id)
		stage_summaries[stage_id] = stage_summary
	return JSON.stringify({
		"schema_version": 3,
		"generated_unix": int(Time.get_unix_time_from_system()),
		"privacy": "Local gameplay metrics only; no player identity or network data.",
		"run_count": run_history.size(),
		"summaries": summaries,
		"stage_summaries": stage_summaries,
		"progression": {
			"unlocked_stage_ids": unlocked_stage_ids.duplicate(),
			"stage_high_scores": stage_high_scores.duplicate(true)
		},
		"runs": run_history.duplicate(true)
	}, "\t")

func export_playtest_data() -> bool:
	var file := FileAccess.open(PLAYTEST_EXPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(playtest_export_json())
	return true

func set_selected_character(value: int) -> void:
	selected_character = clampi(value, 0, 2)
	save_data()

func set_selected_difficulty(value: String) -> void:
	selected_difficulty = value if DIFFICULTY_IDS.has(value) else "normal"
	save_data()

func complete_tutorial() -> void:
	if tutorial_completed:
		return
	tutorial_completed = true
	save_data()

func set_setting(key: String, value: Variant) -> void:
	if settings.has(key):
		settings[key] = value
		if ASSIST_SETTING_KEYS.has(key):
			settings.assist_preset = "custom"
		_sanitize_settings()
		apply_settings()
		save_data()
		GameManager.settings_changed.emit()

func apply_assist_preset(preset_id: String) -> void:
	if not ASSIST_PRESET_IDS.has(preset_id):
		return
	var preset: Dictionary = ASSIST_PRESETS[preset_id]
	for key in ASSIST_SETTING_KEYS:
		settings[key] = preset[key]
	settings.assist_preset = preset_id
	_sanitize_settings()
	apply_settings()
	save_data()
	GameManager.settings_changed.emit()

func set_keyboard_binding(action: String, keycode: int) -> void:
	if not REBIND_ACTIONS.has(action) or keycode <= 0:
		return
	var old_keycode := keyboard_binding(action)
	for other_action in REBIND_ACTIONS:
		if other_action != action and _action_has_keyboard_key(other_action, keycode):
			keyboard_bindings[other_action] = old_keycode
			_apply_keyboard_binding(other_action, old_keycode)
			break
	keyboard_bindings[action] = keycode
	_apply_keyboard_binding(action, keycode)
	save_data()

func reset_keyboard_bindings() -> void:
	keyboard_bindings.clear()
	for action in REBIND_ACTIONS:
		var keycode := int(DEFAULT_BINDINGS[action])
		keyboard_bindings[action] = keycode
		_apply_keyboard_binding(action, keycode)
	save_data()

func set_gamepad_binding(action: String, button_index: int) -> void:
	if not GAMEPAD_REBIND_ACTIONS.has(action) or button_index < 0 or button_index > 31:
		return
	var old_button := gamepad_binding(action)
	for other_action in GAMEPAD_REBIND_ACTIONS:
		if other_action != action and gamepad_binding(other_action) == button_index:
			gamepad_bindings[other_action] = old_button
			_apply_gamepad_binding(other_action, old_button)
			break
	gamepad_bindings[action] = button_index
	_apply_gamepad_binding(action, button_index)
	save_data()

func reset_gamepad_bindings() -> void:
	gamepad_bindings = DEFAULT_GAMEPAD_BINDINGS.duplicate(true)
	for action in GAMEPAD_REBIND_ACTIONS:
		_apply_gamepad_binding(action, int(gamepad_bindings[action]))
	save_data()

func keyboard_binding(action: String) -> int:
	if keyboard_bindings.has(action):
		return int(keyboard_bindings[action])
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keyboard_event := event as InputEventKey
			return int(keyboard_event.physical_keycode if keyboard_event.physical_keycode > 0 else keyboard_event.keycode)
	return 0

func keyboard_binding_label(action: String) -> String:
	var keycode := keyboard_binding(action)
	return OS.get_keycode_string(keycode) if keycode > 0 else "UNBOUND"

func gamepad_binding(action: String) -> int:
	if gamepad_bindings.has(action):
		return int(gamepad_bindings[action])
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return (event as InputEventJoypadButton).button_index
	return -1

func gamepad_binding_label(action: String) -> String:
	var button_index := gamepad_binding(action)
	var labels := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "L3", "R3", "LB", "RB", "DPAD UP", "DPAD DOWN", "DPAD LEFT", "DPAD RIGHT", "MISC", "P1", "P2", "P3", "P4", "TOUCH"]
	return "[%s]" % labels[button_index] if button_index >= 0 and button_index < labels.size() else "[BUTTON %d]" % (button_index + 1)

func _apply_keyboard_binding(action: String, keycode: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var keyboard_event := InputEventKey.new()
	keyboard_event.physical_keycode = keycode
	InputMap.action_add_event(action, keyboard_event)

func _apply_gamepad_binding(action: String, button_index: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			InputMap.action_erase_event(action, event)
	var gamepad_event := InputEventJoypadButton.new()
	gamepad_event.button_index = button_index
	InputMap.action_add_event(action, gamepad_event)

func _action_has_keyboard_key(action: String, keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keyboard_event := event as InputEventKey
			var event_keycode := int(keyboard_event.physical_keycode if keyboard_event.physical_keycode > 0 else keyboard_event.keycode)
			if event_keycode == keycode:
				return true
	return false

func _sanitize_settings() -> void:
	for key in ["master", "music", "sfx", "shake", "flash", "bullet_contrast"]:
		settings[key] = clampf(float(settings.get(key, 0.8)), 0.0, 1.0)
	settings.auto_fire = bool(settings.get("auto_fire", false))
	settings.auto_barrier = bool(settings.get("auto_barrier", false))
	settings.show_hitbox = bool(settings.get("show_hitbox", false))
	settings.fullscreen = bool(settings.get("fullscreen", false))
	var preset_id := String(settings.get("assist_preset", "custom"))
	settings.assist_preset = preset_id if ASSIST_PRESET_IDS.has(preset_id) and _assist_preset_matches(preset_id) else "custom"
	var locale := String(settings.get("language", "en"))
	settings.language = locale if locale in ["en", "ko"] else "en"

func _assist_preset_matches(preset_id: String) -> bool:
	var preset: Dictionary = ASSIST_PRESETS[preset_id]
	for key in ASSIST_SETTING_KEYS:
		if preset[key] is float:
			if not is_equal_approx(float(settings.get(key, 0.0)), float(preset[key])):
				return false
		elif settings.get(key) != preset[key]:
			return false
	return true

func _sanitize_profile() -> void:
	selected_character = clampi(selected_character, 0, 2)
	if not DIFFICULTY_IDS.has(selected_difficulty):
		selected_difficulty = "normal"
	for difficulty_id in DIFFICULTY_IDS:
		high_scores[difficulty_id] = _nonnegative_score(high_scores.get(difficulty_id, 0))
	high_score = int(high_scores.normal)
	_sync_default_stage_scores_from_legacy()

func _load_stage_high_scores(raw_scores: Variant, loaded_version: int) -> void:
	stage_high_scores.clear()
	for stage_id in _catalog_stage_ids():
		stage_high_scores[stage_id] = _empty_difficulty_scores()
	if loaded_version >= 11 and raw_scores is Dictionary:
		for raw_stage_id in raw_scores:
			if not (raw_stage_id is String or raw_stage_id is StringName):
				continue
			var stage_id := _known_stage_id(String(raw_stage_id))
			var raw_stage_scores: Variant = raw_scores[raw_stage_id]
			if stage_id.is_empty() or not raw_stage_scores is Dictionary:
				continue
			var scores := _empty_difficulty_scores()
			for difficulty_id in DIFFICULTY_IDS:
				scores[difficulty_id] = _nonnegative_score(raw_stage_scores.get(difficulty_id, 0))
			stage_high_scores[stage_id] = scores
	# v10 and older only had the difficulty mirrors. For v11, taking the
	# maximum also makes an internally inconsistent but valid save lossless.
	var default_scores := _scores_for_stage(LEGACY_DEFAULT_STAGE_ID)
	for difficulty_id in DIFFICULTY_IDS:
		default_scores[difficulty_id] = maxi(
			int(default_scores.get(difficulty_id, 0)),
			_nonnegative_score(high_scores.get(difficulty_id, 0))
		)
	stage_high_scores[LEGACY_DEFAULT_STAGE_ID] = default_scores
	high_scores = default_scores.duplicate(true)
	high_score = int(high_scores.normal)

func _load_unlocked_stage_ids(raw_ids: Variant) -> void:
	unlocked_stage_ids = PackedStringArray([LEGACY_DEFAULT_STAGE_ID])
	if raw_ids is Array or raw_ids is PackedStringArray:
		for raw_id in raw_ids:
			if not (raw_id is String or raw_id is StringName):
				continue
			var stage_id := _known_stage_id(String(raw_id))
			if not stage_id.is_empty() and not unlocked_stage_ids.has(stage_id):
				unlocked_stage_ids.append(stage_id)
	_sanitize_progression()

func _sanitize_progression() -> void:
	var sanitized := PackedStringArray([LEGACY_DEFAULT_STAGE_ID])
	for stage_id in _catalog_stage_ids():
		if unlocked_stage_ids.has(stage_id) and not sanitized.has(stage_id):
			sanitized.append(stage_id)
	unlocked_stage_ids = sanitized
	var sanitized_scores := {}
	for stage_id in _catalog_stage_ids():
		sanitized_scores[stage_id] = _scores_for_stage(stage_id)
	stage_high_scores = sanitized_scores

func _sync_default_stage_scores_from_legacy() -> void:
	for difficulty_id in DIFFICULTY_IDS:
		high_scores[difficulty_id] = _nonnegative_score(high_scores.get(difficulty_id, 0))
	high_score = int(high_scores.normal)
	stage_high_scores[LEGACY_DEFAULT_STAGE_ID] = high_scores.duplicate(true)

func _register_stage_clear(stage_id: String) -> bool:
	var safe_stage_id := _known_stage_id(stage_id)
	if safe_stage_id.is_empty():
		return false
	var catalog_ids := _catalog_stage_ids()
	var stage_index := catalog_ids.find(safe_stage_id)
	if stage_index < 0 or stage_index + 1 >= catalog_ids.size():
		return false
	var next_stage_id := catalog_ids[stage_index + 1]
	if unlocked_stage_ids.has(next_stage_id):
		return false
	unlocked_stage_ids.append(next_stage_id)
	_sanitize_progression()
	return true

func _scores_for_stage(stage_id: String) -> Dictionary:
	var raw_scores: Variant = stage_high_scores.get(stage_id, {})
	var scores := _empty_difficulty_scores()
	if raw_scores is Dictionary:
		for difficulty_id in DIFFICULTY_IDS:
			scores[difficulty_id] = _nonnegative_score(raw_scores.get(difficulty_id, 0))
	return scores

func _empty_difficulty_scores() -> Dictionary:
	return {"story": 0, "normal": 0, "expert": 0}

func _nonnegative_score(value: Variant) -> int:
	if value is int:
		return maxi(0, value)
	if value is float:
		if is_nan(value) or is_inf(value):
			return 0
		return maxi(0, int(value))
	return 0

func _known_stage_id(value: String) -> String:
	var stage_id := value.strip_edges().to_lower()
	if stage_id.is_empty():
		stage_id = LEGACY_DEFAULT_STAGE_ID
	return stage_id if _catalog_stage_ids().has(stage_id) else ""

func _catalog_stage_ids() -> PackedStringArray:
	var stage_ids := StageManager.stage_ids()
	if not stage_ids.has(LEGACY_DEFAULT_STAGE_ID):
		stage_ids.insert(0, LEGACY_DEFAULT_STAGE_ID)
	return stage_ids

func _load_run_history(raw_history: Variant) -> void:
	run_history.clear()
	if not raw_history is Array:
		return
	for raw_entry in raw_history:
		if raw_entry is Dictionary:
			var entry := _sanitize_run_entry(raw_entry)
			if not entry.is_empty():
				run_history.append(entry)
	while run_history.size() > MAX_RUN_HISTORY:
		run_history.remove_at(0)

func _sanitize_run_entry(raw_entry: Dictionary) -> Dictionary:
	var difficulty_id := String(raw_entry.get("difficulty", "normal"))
	if not DIFFICULTY_IDS.has(difficulty_id):
		difficulty_id = "normal"
	var phase_metrics: Array[Dictionary] = []
	var raw_metrics: Variant = raw_entry.get("boss_phase_metrics", [])
	if raw_metrics is Array:
		for raw_metric in raw_metrics:
			if raw_metric is Dictionary and phase_metrics.size() < 64:
				phase_metrics.append({
					"boss_id": String(raw_metric.get("boss_id", "")).substr(0, 24),
					"phase": clampi(int(raw_metric.get("phase", 0)), 0, 64),
					"phase_name": String(raw_metric.get("phase_name", "")).substr(0, 64),
					"clear_time": clampf(float(raw_metric.get("clear_time", 0.0)), 0.0, 3600.0),
					"overdrive": bool(raw_metric.get("overdrive", false))
				})
	var replay_id := _sanitize_replay_id(raw_entry.get("replay_id", ""))
	var stage_id := _sanitize_stage_id(raw_entry.get("stage_id", LEGACY_DEFAULT_STAGE_ID))
	var medals := ScoreManager.normalize_medal_ids(raw_entry.get("medals", []))
	# Medal definitions are authoritative. Recomputing the bonus prevents stale,
	# duplicated, or malformed telemetry from manufacturing archive score data.
	var medal_bonus := ScoreManager.medal_bonus_for_ids(medals)
	var risk_bank_events := ScoreManager.normalize_risk_bank_events(raw_entry.get("risk_bank_events", []))
	var risk_bank_bonus := ScoreManager.risk_bonus_for_events(risk_bank_events)
	return {
		"timestamp": maxi(0, int(raw_entry.get("timestamp", 0))),
		"character": clampi(int(raw_entry.get("character", 0)), 0, 2),
		"difficulty": difficulty_id,
		"stage_id": stage_id,
		"cleared": bool(raw_entry.get("cleared", false)),
		"assisted": bool(raw_entry.get("assisted", false)),
		"total_score": maxi(0, int(raw_entry.get("total_score", 0))),
		"clear_time": clampf(float(raw_entry.get("clear_time", 0.0)), 0.0, 7200.0),
		"route_time": clampf(float(raw_entry.get("route_time", raw_entry.get("clear_time", 0.0))), 0.0, 7200.0),
		"deaths": clampi(int(raw_entry.get("deaths", 0)), 0, 99),
		"barriers_used": clampi(int(raw_entry.get("barriers_used", 0)), 0, 999),
		"enemies_destroyed": clampi(int(raw_entry.get("enemies_destroyed", 0)), 0, 99999),
		"graze": clampi(int(raw_entry.get("graze", 0)), 0, 9999999),
		"max_combo": clampi(int(raw_entry.get("max_combo", 0)), 0, 9999999),
		"medals": medals,
		"medal_bonus": medal_bonus,
		"risk_bank_events": risk_bank_events,
		"risk_bank_bonus": risk_bank_bonus,
		"risk_reserve_peak": clampi(int(raw_entry.get("risk_reserve_peak", 0)), 0, int(ScoreManager.RISK_ROUTE_RULES.reserve_capacity)),
		"risk_reserve_lost": clampi(int(raw_entry.get("risk_reserve_lost", 0)), 0, 999999),
		"risk_reserve_unbanked": clampi(int(raw_entry.get("risk_reserve_unbanked", 0)), 0, int(ScoreManager.RISK_ROUTE_RULES.reserve_capacity)),
		"replay_id": replay_id,
		"boss_phase_metrics": phase_metrics
	}

func _sanitize_replay_id(value: Variant) -> String:
	var replay_id := String(value).strip_edges().to_lower()
	if replay_id.length() != 64:
		return ""
	const HEX_DIGITS := "0123456789abcdef"
	for character in replay_id:
		if HEX_DIGITS.find(character) < 0:
			return ""
	return replay_id

func _sanitize_stage_id(value: Variant) -> String:
	var stage_id := String(value).strip_edges().to_lower()
	if stage_id.is_empty():
		return LEGACY_DEFAULT_STAGE_ID
	if stage_id.length() > 64:
		return LEGACY_DEFAULT_STAGE_ID
	const ID_CHARACTERS := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for character in stage_id:
		if ID_CHARACTERS.find(character) < 0:
			return LEGACY_DEFAULT_STAGE_ID
	return stage_id

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.master))))
	var target_mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
