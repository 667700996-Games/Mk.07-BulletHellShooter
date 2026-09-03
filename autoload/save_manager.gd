extends Node

const SAVE_PATH := "user://psychic_vector.cfg"
const SAVE_VERSION := 4
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

var high_score := 0
var high_scores := {"story": 0, "normal": 0, "expert": 0}
var selected_character := 0
var selected_difficulty := "normal"
var keyboard_bindings: Dictionary = {}
var persistence_enabled := true
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
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var loaded_version := int(config.get_value("meta", "version", 0))
	var legacy_high_score := maxi(0, int(config.get_value("record", "high_score", 0)))
	high_scores.story = maxi(0, int(config.get_value("record", "high_score_story", 0)))
	high_scores.normal = maxi(0, int(config.get_value("record", "high_score_normal", legacy_high_score)))
	high_scores.expert = maxi(0, int(config.get_value("record", "high_score_expert", 0)))
	high_score = int(high_scores.normal)
	selected_character = clampi(int(config.get_value("profile", "character", 0)), 0, 2)
	selected_difficulty = String(config.get_value("profile", "difficulty", "normal"))
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
	if loaded_version < SAVE_VERSION:
		save_data()

func save_data() -> void:
	if not persistence_enabled:
		return
	var config := ConfigFile.new()
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("record", "high_score", high_score)
	for difficulty_id in DIFFICULTY_IDS:
		config.set_value("record", "high_score_%s" % difficulty_id, int(high_scores.get(difficulty_id, 0)))
	config.set_value("profile", "character", selected_character)
	config.set_value("profile", "difficulty", selected_difficulty)
	for key in settings:
		config.set_value("settings", key, settings[key])
	for action in keyboard_bindings:
		config.set_value("controls", action, int(keyboard_bindings[action]))
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save player data: %s" % error_string(error))

func submit_score(value: int, difficulty_id: String = "normal") -> void:
	var safe_id := difficulty_id if DIFFICULTY_IDS.has(difficulty_id) else "normal"
	if value > int(high_scores.get(safe_id, 0)):
		high_scores[safe_id] = value
		if safe_id == "normal":
			high_score = value
		save_data()

func high_score_for(difficulty_id: String) -> int:
	var safe_id := difficulty_id if DIFFICULTY_IDS.has(difficulty_id) else "normal"
	return int(high_scores.get(safe_id, 0))

func set_selected_character(value: int) -> void:
	selected_character = clampi(value, 0, 2)
	save_data()

func set_selected_difficulty(value: String) -> void:
	selected_difficulty = value if DIFFICULTY_IDS.has(value) else "normal"
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

func _apply_keyboard_binding(action: String, keycode: int) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var keyboard_event := InputEventKey.new()
	keyboard_event.physical_keycode = keycode
	InputMap.action_add_event(action, keyboard_event)

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
		high_scores[difficulty_id] = maxi(0, int(high_scores.get(difficulty_id, 0)))
	high_score = int(high_scores.normal)

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.master))))
	var target_mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
