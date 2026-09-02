extends Node

const SAVE_PATH := "user://psychic_vector.cfg"

var high_score := 0
var selected_character := 0
var settings := {
	"master": 0.82,
	"music": 0.68,
	"sfx": 0.82,
	"shake": 0.85,
	"flash": 0.85,
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

func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("record", "high_score", high_score)
	config.set_value("profile", "character", selected_character)
	for key in settings:
		config.set_value("settings", key, settings[key])
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

func apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(settings.master))))
	var target_mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
