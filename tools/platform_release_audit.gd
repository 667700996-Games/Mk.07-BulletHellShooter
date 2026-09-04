extends SceneTree

## Static release-platform contract for the three supported desktop targets.
##
## This proves that the authored project and export configuration are internally
## consistent. It deliberately does not claim a successful native export,
## signing/notarization, controller hardware pass, or platform certification.

const EXPECTED_VIEWPORT := Vector2i(540, 960)
const COMMON_EXPORT_FEATURE := "psychic_vector_release"
const REQUIRED_EXPORT_EXCLUDES := [
	".github/*", "assets/store/*", "build/*", "dist/*", "docs/*", "native-evidence/*", "playtests/*",
	"release/signing_policy.json", "tests/*", "tools/*"
]
const REQUIRED_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"primary", "focus", "barrier", "pause_game"
]
const MOVEMENT_CONTRACT := {
	"move_left": {"axis": 0, "axis_value": -1.0, "dpad": 13},
	"move_right": {"axis": 0, "axis_value": 1.0, "dpad": 14},
	"move_up": {"axis": 1, "axis_value": -1.0, "dpad": 11},
	"move_down": {"axis": 1, "axis_value": 1.0, "dpad": 12}
}
const BUTTON_CONTRACT := {
	"primary": 0,
	"focus": 2,
	"barrier": 1,
	"pause_game": 6
}
const PRESET_CONTRACTS := {
	"Windows Desktop": {
		"platform": "Windows Desktop",
		"feature": "windows_desktop",
		"architecture": "x86_64",
		"suffix": ".exe"
	},
	"macOS": {
		"platform": "macOS",
		"feature": "macos_desktop",
		"architecture": "universal",
		"suffix": ".zip"
	},
	"Linux": {
		"platform": "Linux/X11",
		"feature": "linux_desktop",
		"architecture": "x86_64",
		"suffix": ".x86_64"
	}
}

var failures: Array[String] = []
var checks := 0
var project_config := ConfigFile.new()
var export_config := ConfigFile.new()
var presets_checked := 0
var actions_checked := 0
var save_manager: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	save_manager = get_root().get_node_or_null("SaveManager")
	_check(save_manager != null, "SaveManager autoload is unavailable")
	var project_error := project_config.load("res://project.godot")
	var export_error := export_config.load("res://export_presets.cfg")
	_check(project_error == OK, "project.godot could not be loaded: %s" % error_string(project_error))
	_check(export_error == OK, "export_presets.cfg could not be loaded: %s" % error_string(export_error))
	if project_error == OK:
		_audit_application_and_display()
		_audit_controller_actions()
	if export_error == OK:
		_audit_export_presets()
	_finish()


func _audit_application_and_display() -> void:
	var project_name := String(project_config.get_value("application", "config/name", "")).strip_edges()
	var main_scene := String(project_config.get_value("application", "run/main_scene", ""))
	var icon_path := String(project_config.get_value("application", "config/icon", ""))
	var features: PackedStringArray = project_config.get_value("application", "config/features", PackedStringArray())
	_check(not project_name.is_empty(), "application name is empty")
	_check(main_scene.begins_with("res://") and ResourceLoader.exists(main_scene), "main scene is missing or not project-relative: %s" % main_scene)
	_check(features.has("GL Compatibility"), "application features must declare GL Compatibility")
	var has_godot_4_feature := false
	for feature in features:
		if feature.begins_with("4."):
			has_godot_4_feature = true
	_check(has_godot_4_feature, "application features do not declare a Godot 4.x baseline")
	_check(String(project_config.get_value("rendering", "renderer/rendering_method", "")) == "gl_compatibility", "desktop renderer must remain gl_compatibility")
	_check(String(project_config.get_value("rendering", "renderer/rendering_method.mobile", "")) == "gl_compatibility", "mobile renderer fallback must remain gl_compatibility")
	_check(bool(project_config.get_value("rendering", "textures/vram_compression/import_s3tc_bptc", false)), "desktop S3TC/BPTC source imports must remain enabled")
	_check(bool(project_config.get_value("rendering", "textures/vram_compression/import_etc2_astc", false)), "macOS universal ARM64 ETC2/ASTC source imports must remain enabled")
	_check(not bool(project_config.get_value("editor", "export/convert_text_resources_to_binary", true)), "release exports must preserve text resources to prevent nested combat-array loss")
	_check(bool(project_config.get_value("application", "run/flush_stdout_on_print", false)), "release stdout must flush build/session markers immediately")
	_check(bool(project_config.get_value("debug", "file_logging/enable_file_logging", false)), "release file logging must remain enabled")
	_check(bool(project_config.get_value("debug", "file_logging/enable_file_logging.pc", false)), "desktop file logging override must remain enabled")
	_check(String(project_config.get_value("debug", "file_logging/log_path", "")) == "user://logs/psychic_vector.log", "runtime log path differs from the disclosed local-data contract")
	_check(int(project_config.get_value("debug", "file_logging/max_log_files", 0)) == 5, "runtime log rotation must retain exactly five files")
	_check(bool(project_config.get_value("debug", "settings/gdscript/always_track_call_stacks", false)), "release GDScript call stacks must remain enabled for local crash diagnosis")
	_check(not String(project_config.get_value("debug", "settings/crash_handler/message", "")).is_empty(), "release crash handler support message is missing")
	_audit_icon(icon_path)

	_check(int(project_config.get_value("display", "window/size/viewport_width", 0)) == EXPECTED_VIEWPORT.x, "viewport width must be 540")
	_check(int(project_config.get_value("display", "window/size/viewport_height", 0)) == EXPECTED_VIEWPORT.y, "viewport height must be 960")
	_check(int(project_config.get_value("display", "window/size/window_width_override", 0)) == EXPECTED_VIEWPORT.x, "desktop window width override must be 540")
	_check(int(project_config.get_value("display", "window/size/window_height_override", 0)) == EXPECTED_VIEWPORT.y, "desktop window height override must be 960")
	_check(int(project_config.get_value("display", "window/size/mode", -1)) == 0, "the release default must explicitly start windowed")
	_check(bool(project_config.get_value("display", "window/size/resizable", false)), "desktop window must remain resizable")
	_check(String(project_config.get_value("display", "window/stretch/mode", "")) == "canvas_items", "stretch mode must be canvas_items")
	_check(String(project_config.get_value("display", "window/stretch/aspect", "")) == "keep", "stretch aspect must preserve the 9:16 frame")
	_check(int(project_config.get_value("display", "window/handheld/orientation", -1)) == 1, "handheld orientation must remain portrait")

	if save_manager != null:
		var save_script := save_manager.get_script() as Script
		_check(save_manager.settings.has("fullscreen") and typeof(save_manager.settings.fullscreen) == TYPE_BOOL, "save settings must contain a boolean fullscreen value")
		_check(Array(save_script.SAVE_SETTING_KEYS).has("fullscreen"), "fullscreen is not persisted")
		_check(save_manager.has_method("apply_settings"), "saved display settings have no apply_settings implementation")


func _audit_icon(icon_path: String) -> void:
	_check(icon_path.begins_with("res://"), "application icon must be project-relative")
	_check(icon_path.get_extension().to_lower() in ["svg", "png", "webp"], "application icon must use a supported source format: %s" % icon_path)
	_check(FileAccess.file_exists(icon_path), "application icon is missing: %s" % icon_path)
	if not FileAccess.file_exists(icon_path):
		return
	if icon_path.get_extension().to_lower() == "svg":
		var icon_file := FileAccess.open(icon_path, FileAccess.READ)
		_check(icon_file != null, "application SVG icon could not be opened")
		if icon_file != null:
			var source := icon_file.get_as_text()
			_check(source.contains("viewBox=\"0 0 512 512\""), "application SVG icon must provide a square 512x512 viewBox")
			_check(not source.to_lower().contains("<script"), "application SVG icon must not contain executable script")


func _audit_controller_actions() -> void:
	var save_script := save_manager.get_script() as Script if save_manager != null else null
	for action in REQUIRED_ACTIONS:
		actions_checked += 1
		var mapping: Dictionary = project_config.get_value("input", action, {})
		_check(not mapping.is_empty(), "input action is missing: %s" % action)
		if mapping.is_empty():
			continue
		var deadzone := float(mapping.get("deadzone", -1.0))
		_check(deadzone >= 0.15 and deadzone <= 0.35, "%s deadzone %.2f is outside the release range" % [action, deadzone])
		var events: Array = mapping.get("events", [])
		_check(_has_keyboard_event(events), "%s has no keyboard binding" % action)
		_check(_has_controller_event(events), "%s has no controller binding" % action)
		if MOVEMENT_CONTRACT.has(action):
			var movement: Dictionary = MOVEMENT_CONTRACT[action]
			_check(_has_axis_event(events, int(movement.axis), float(movement.axis_value)), "%s is missing the expected left-stick direction" % action)
			_check(_has_button_event(events, int(movement.dpad)), "%s is missing the expected D-pad direction" % action)
		else:
			_check(_has_button_event(events, int(BUTTON_CONTRACT[action])), "%s is missing controller button %d" % [action, int(BUTTON_CONTRACT[action])])

	var gameplay_buttons: Array[int] = []
	for action in ["primary", "focus", "barrier"]:
		gameplay_buttons.append(int(BUTTON_CONTRACT[action]))
		if save_script != null:
			_check(Array(save_script.REBIND_ACTIONS).has(action), "%s is not keyboard-remappable" % action)
			_check(Array(save_script.GAMEPAD_REBIND_ACTIONS).has(action), "%s is not controller-remappable" % action)
			_check(int(save_script.DEFAULT_GAMEPAD_BINDINGS.get(action, -1)) == int(BUTTON_CONTRACT[action]), "%s saved controller default differs from project input" % action)
	_check(_unique_count(gameplay_buttons) == gameplay_buttons.size(), "primary/focus/barrier controller defaults overlap")
	for action in MOVEMENT_CONTRACT:
		if save_script != null:
			_check(Array(save_script.REBIND_ACTIONS).has(action), "%s is not keyboard-remappable" % action)


func _audit_export_presets() -> void:
	var preset_sections: Array[String] = []
	for section_value in export_config.get_sections():
		var section := String(section_value)
		if section.begins_with("preset.") and not section.ends_with(".options"):
			preset_sections.append(section)
	_check(preset_sections.size() == PRESET_CONTRACTS.size(), "expected exactly three desktop export presets, found %d" % preset_sections.size())
	var seen_names := {}
	var seen_platforms := {}
	var seen_paths := {}
	for section in preset_sections:
		presets_checked += 1
		var name := String(export_config.get_value(section, "name", ""))
		var platform := String(export_config.get_value(section, "platform", ""))
		var export_path := String(export_config.get_value(section, "export_path", ""))
		_check(PRESET_CONTRACTS.has(name), "%s has unsupported preset name: %s" % [section, name])
		_check(not seen_names.has(name), "duplicate export preset name: %s" % name)
		_check(not seen_platforms.has(platform), "duplicate export platform: %s" % platform)
		_check(not seen_paths.has(export_path), "duplicate export path: %s" % export_path)
		seen_names[name] = true
		seen_platforms[platform] = true
		seen_paths[export_path] = true
		if not PRESET_CONTRACTS.has(name):
			continue
		var contract: Dictionary = PRESET_CONTRACTS[name]
		var option_section := section + ".options"
		_check(platform == String(contract.platform), "%s targets %s instead of %s" % [name, platform, contract.platform])
		_check(bool(export_config.get_value(section, "runnable", false)), "%s is not runnable" % name)
		_check(not bool(export_config.get_value(section, "dedicated_server", true)), "%s is incorrectly configured as a dedicated server" % name)
		_check(String(export_config.get_value(section, "export_filter", "")) == "all_resources", "%s must export all production resources" % name)
		_check(int(export_config.get_value(section, "script_export_mode", -1)) == 2, "%s script export mode is not the release contract" % name)
		_audit_export_filters(name, String(export_config.get_value(section, "exclude_filter", "")))
		_audit_export_path(name, export_path, String(contract.suffix))
		var custom_features := _csv_tokens(String(export_config.get_value(section, "custom_features", "")))
		_check(custom_features.has(COMMON_EXPORT_FEATURE), "%s is missing the common release feature" % name)
		_check(custom_features.has(String(contract.feature)), "%s is missing its platform feature" % name)
		_check(String(export_config.get_value(option_section, "binary_format/architecture", "")) == String(contract.architecture), "%s architecture must be %s" % [name, contract.architecture])
		_check(bool(export_config.get_value(option_section, "texture_format/s3tc_bptc", false)), "%s must enable the desktop S3TC/BPTC texture path" % name)
		if name == "macOS":
			_check(bool(export_config.get_value(option_section, "texture_format/etc2_astc", false)), "macOS universal must enable the ARM64 ETC2/ASTC texture path")
			_check(_valid_bundle_identifier(String(export_config.get_value(option_section, "application/bundle_identifier", ""))), "macOS bundle identifier must use a lowercase reverse-DNS form")
			_check(_valid_numeric_version(String(export_config.get_value(option_section, "application/short_version", "")), 3), "macOS short version must contain exactly three numeric components")
			_check(_valid_numeric_version(String(export_config.get_value(option_section, "application/version", "")), 1), "macOS bundle version must be a positive integer")
		elif name == "Windows Desktop":
			_check(not bool(export_config.get_value(option_section, "texture_format/etc2_astc", true)), "Windows unexpectedly enables the ETC2/ASTC texture path")
			_check(_valid_numeric_version(String(export_config.get_value(option_section, "application/file_version", "")), 4), "Windows file version must contain exactly four numeric components")
			_check(_valid_numeric_version(String(export_config.get_value(option_section, "application/product_version", "")), 4), "Windows product version must contain exactly four numeric components")
		else:
			_check(not bool(export_config.get_value(option_section, "texture_format/etc2_astc", true)), "%s unexpectedly enables the ETC2/ASTC texture path" % name)
	_check(seen_names.size() == PRESET_CONTRACTS.size(), "one or more required desktop presets are missing")


func _audit_export_filters(name: String, raw_filter: String) -> void:
	var filters := _csv_tokens(raw_filter)
	filters.sort()
	var expected: Array[String] = []
	for value in REQUIRED_EXPORT_EXCLUDES:
		expected.append(String(value))
	expected.sort()
	_check(filters == expected, "%s release export exclusion set differs: %s" % [name, str(filters)])


func _audit_export_path(name: String, export_path: String, suffix: String) -> void:
	_check(export_path.begins_with("build/"), "%s export path must stay under build/" % name)
	_check(not export_path.contains("..") and not export_path.contains("\\"), "%s export path is not portable: %s" % [name, export_path])
	_check(export_path.ends_with(suffix), "%s export path must end with %s" % [name, suffix])


func _csv_tokens(value: String) -> Array[String]:
	var tokens: Array[String] = []
	for raw_token in value.split(",", false):
		var token := raw_token.strip_edges()
		if not token.is_empty():
			tokens.append(token)
	return tokens


func _valid_numeric_version(value: String, component_count: int) -> bool:
	var components := value.split(".", true)
	if components.size() != component_count:
		return false
	for component in components:
		if component.is_empty() or not component.is_valid_int():
			return false
		var number := component.to_int()
		if number < 0 or number > 65535:
			return false
	return component_count != 1 or components[0].to_int() > 0


func _valid_bundle_identifier(value: String) -> bool:
	var expression := RegEx.new()
	if expression.compile("^[a-z][a-z0-9]*(\\.[a-z][a-z0-9]*){2,}$") != OK:
		return false
	return expression.search(value) != null


func _has_keyboard_event(events: Array) -> bool:
	for event in events:
		if event is InputEventKey and (event.physical_keycode > 0 or event.keycode > 0):
			return true
	return false


func _has_controller_event(events: Array) -> bool:
	for event in events:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


func _has_axis_event(events: Array, axis: int, axis_value: float) -> bool:
	for event in events:
		if event is InputEventJoypadMotion and int(event.axis) == axis and is_equal_approx(event.axis_value, axis_value):
			return true
	return false


func _has_button_event(events: Array, button_index: int) -> bool:
	for event in events:
		if event is InputEventJoypadButton and int(event.button_index) == button_index:
			return true
	return false


func _unique_count(values: Array[int]) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if not failures.is_empty():
		printerr("PLATFORM_RELEASE_AUDIT_FAILED errors=%d checks=%d presets=%d actions=%d" % [failures.size(), checks, presets_checked, actions_checked])
		for failure in failures:
			printerr("PLATFORM_RELEASE_AUDIT_ERROR %s" % failure)
		quit(1)
		return
	print("PLATFORM_RELEASE_AUDIT_OK checks=%d presets=%d actions=%d viewport=540x960 targets=windows+macos+linux" % [checks, presets_checked, actions_checked])
	quit(0)
