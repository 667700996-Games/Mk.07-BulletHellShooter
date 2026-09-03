extends Node

const SAVE_PATH := "user://psychic_vector.cfg"
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
var selected_character := 0
var keyboard_bindings: Dictionary = {}
var settings := {
	"master": 0.82,
	"music": 0.68,
	"sfx": 0.82,
	"shake": 0.85,
	"flash": 0.85,
	"bullet_contrast": 0.8,
	"auto_fire": false,
	"fullscreen": false
}

func _ready() -> void:
	load_data()
	apply_settings()

func load_data() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	high_score = int(config.get_value("record", "high_score", 0))
	selected_character = clampi(int(config.get_value("profile", "character", 0)), 0, 2)
	for key in settings:
		settings[key] = config.get_value("settings", key, settings[key])
	for action in REBIND_ACTIONS:
		var keycode := int(config.get_value("controls", action, 0))
		if keycode > 0:
			keyboard_bindings[action] = keycode
			_apply_keyboard_binding(action, keycode)

func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("record", "high_score", high_score)
	config.set_value("profile", "character", selected_character)
	for key in settings:
		config.set_value("settings", key, settings[key])
	for action in keyboard_bindings:
		config.set_value("controls", action, int(keyboard_bindings[action]))
	config.save(SAVE_PATH)

func submit_score(value: int) -> void:
	if value > high_score:
		high_score = value
		save_data()

func set_selected_character(value: int) -> void:
	selected_character = clampi(value, 0, 2)
	save_data()

func set_setting(key: String, value: Variant) -> void:
	if settings.has(key):
		settings[key] = value
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

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.master))))
	var target_mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
