extends SceneTree

## Release-facing layout audit for every major 540x960 UI surface.
##
## The audit mounts real screen nodes under the project viewport, waits for
## containers and deferred focus calls to settle, then verifies runtime global
## rectangles instead of duplicating authored coordinates. StageSelect and
## CharacterSelect intentionally use a drawn/virtual selection cursor; every
## conventional Button on the other screens must participate in GUI focus.

const EXPECTED_VIEWPORT := Vector2(540.0, 960.0)
const BOUNDS_EPSILON := 0.75

var failures: Array[String] = []
var checks := 0
var screens_checked := 0
var controls_checked := 0
var buttons_checked := 0

var game_manager: Node
var stage_manager: Node
var save_manager: Node
var replay_manager: Node
var audio_manager: Node
var screen_scripts: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	game_manager = get_root().get_node_or_null("GameManager")
	stage_manager = get_root().get_node_or_null("StageManager")
	save_manager = get_root().get_node_or_null("SaveManager")
	replay_manager = get_root().get_node_or_null("ReplayManager")
	audio_manager = get_root().get_node_or_null("AudioManager")
	screen_scripts = {
		"title": load("res://ui/title_screen.gd") as Script,
		"stage_select": load("res://ui/stage_select.gd") as Script,
		"character_select": load("res://ui/character_select.gd") as Script,
		"briefing": load("res://ui/operation_briefing.gd") as Script,
		"ending": load("res://ui/campaign_ending.gd") as Script,
		"results": load("res://ui/results_screen.gd") as Script,
		"records": load("res://ui/records_screen.gd") as Script,
		"credits": load("res://ui/credits_screen.gd") as Script
	}
	if game_manager == null or stage_manager == null or save_manager == null or replay_manager == null or audio_manager == null:
		_fail("required autoloads are unavailable")
		_finish()
		return
	for script_id in screen_scripts:
		if screen_scripts[script_id] == null:
			_fail("screen script failed to load: %s" % script_id)
	if not failures.is_empty():
		_finish()
		return

	_verify_project_display_contract()
	var settings_backup: Dictionary = save_manager.settings.duplicate(true)
	var unlocked_backup: PackedStringArray = save_manager.unlocked_stage_ids.duplicate()
	var character_backup := int(game_manager.selected_character)
	# Layout focus changes normally emit UI one-shots. Audio is outside this
	# audit's scope, and clearing the isolated process cache avoids teardown noise.
	audio_manager.sfx_cache.clear()
	var all_stage_ids: PackedStringArray = stage_manager.stage_ids()
	save_manager.unlocked_stage_ids = all_stage_ids.duplicate()
	game_manager.selected_character = 0

	var effect_profiles := [
		{"id": "standard", "shake": 0.85, "flash": 0.85},
		{"id": "reduced", "shake": 0.15, "flash": 0.10}
	]
	for locale in ["en", "ko"]:
		for profile_value in effect_profiles:
			var profile: Dictionary = profile_value
			save_manager.settings["language"] = locale
			save_manager.settings["shake"] = profile.shake
			save_manager.settings["flash"] = profile.flash
			var context := "%s/%s" % [locale, String(profile.id)]
			await _audit_title(context)
			await _audit_stage_select(context)
			await _audit_character_select(context, false)
			await _audit_character_select(context, true)
			await _audit_operation_briefing(context, profile)
			await _audit_campaign_ending(context, profile)
			await _audit_results(context)
			await _audit_records(context)
			await _audit_credits(context, profile)

	save_manager.settings = settings_backup
	save_manager.unlocked_stage_ids = unlocked_backup
	game_manager.selected_character = character_backup
	audio_manager.stop_music()
	for player_value in audio_manager.sfx_players:
		var player := player_value as AudioStreamPlayer
		if player != null:
			player.stop()
			player.stream = null
	for _frame in 3:
		await process_frame
	_finish()


func _verify_project_display_contract() -> void:
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == int(EXPECTED_VIEWPORT.x), "project viewport width is not 540")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == int(EXPECTED_VIEWPORT.y), "project viewport height is not 960")
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items", "stretch mode must remain canvas_items")
	_check(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep", "stretch aspect must preserve the portrait frame")


func _audit_title(context: String) -> void:
	var screen := screen_scripts.title.new() as Control
	await _mount(screen)
	_audit_control_tree(screen, "%s/title-menu" % context)

	screen.call("_show_options")
	await _settle()
	_audit_control_tree(screen, "%s/title-options" % context)

	screen.call("_show_assists")
	await _settle()
	_audit_control_tree(screen, "%s/title-assists" % context)
	screen.call("_close_assists")
	await _settle()

	screen.call("_show_bindings")
	await _settle()
	_audit_control_tree(screen, "%s/title-keyboard-bindings" % context)
	screen.call("_toggle_binding_mode")
	await _settle()
	_audit_control_tree(screen, "%s/title-gamepad-bindings" % context)
	screen.call("_close_bindings")
	await _settle()
	screen.call("_close_options")
	await _settle()

	screen.call("_show_help")
	await _settle()
	_audit_control_tree(screen, "%s/title-help" % context)
	await _dispose(screen)


func _audit_stage_select(context: String) -> void:
	var screen := screen_scripts.stage_select.new() as Control
	await _mount(screen)
	_audit_control_tree(screen, "%s/stage-select" % context, true)
	var stage_ids: PackedStringArray = screen.stage_ids
	var stage_buttons: Array = screen.stage_buttons
	_check(stage_ids.size() == stage_manager.stage_ids().size(), "%s/stage-select omitted a catalog route" % context)
	_check(stage_buttons.size() == stage_ids.size(), "%s/stage-select card count differs from its catalog" % context)
	_check(int(screen.selected_index) >= 0 and int(screen.selected_index) < stage_ids.size(), "%s/stage-select has no virtual focus selection" % context)
	for button_value in stage_buttons:
		var button := button_value as Button
		_check(button != null and button.focus_mode == Control.FOCUS_NONE, "%s/stage-select card must use the screen's virtual focus contract" % context)
	await _dispose(screen)


func _audit_character_select(context: String, practice: bool) -> void:
	var screen := screen_scripts.character_select.new() as Control
	screen.practice_mode = practice
	screen.stage_data = stage_manager.stage(String(stage_manager.stage_ids()[stage_manager.stage_ids().size() - 1]))
	await _mount(screen)
	var suffix := "practice" if practice else "campaign"
	_audit_control_tree(screen, "%s/character-%s" % [context, suffix], true)
	_check(int(screen.selected) >= 0 and int(screen.selected) < game_manager.CHARACTERS.size(), "%s/character-%s virtual character focus is invalid" % [context, suffix])
	if practice:
		_check(int(screen.selected_phase) >= 0 and int(screen.selected_phase) < screen.stage_data.practice_phase_name_keys.size(), "%s/character-practice phase focus is invalid" % context)
	else:
		_check(int(screen.selected_difficulty) >= 0 and int(screen.selected_difficulty) < game_manager.DIFFICULTY_ORDER.size(), "%s/character-campaign difficulty focus is invalid" % context)
	await _dispose(screen)


func _audit_operation_briefing(context: String, profile: Dictionary) -> void:
	var screen := screen_scripts.briefing.new() as Control
	var final_stage: Resource = stage_manager.stage(String(stage_manager.stage_ids()[stage_manager.stage_ids().size() - 1]))
	screen.setup(final_stage, 2, "expert")
	await _mount(screen)
	_audit_control_tree(screen, "%s/operation-briefing" % context)
	_check(is_equal_approx(float(screen.motion_strength), float(profile.shake)), "%s/operation-briefing ignored motion setting" % context)
	_check(is_equal_approx(float(screen.flash_strength), float(profile.flash)), "%s/operation-briefing ignored flash setting" % context)
	await _dispose(screen)


func _audit_campaign_ending(context: String, profile: Dictionary) -> void:
	var final_stage: Resource = stage_manager.stage(String(stage_manager.stage_ids()[stage_manager.stage_ids().size() - 1]))
	var ending_result := _result_fixture(final_stage.stage_id, true)
	ending_result.character = 1
	var screen := screen_scripts.ending.new() as Control
	screen.setup(ending_result, final_stage)
	await _mount(screen)
	_audit_control_tree(screen, "%s/campaign-ending" % context)
	_check(bool(screen.context_valid), "%s/campaign-ending rejected the final clear fixture" % context)
	var should_reduce := float(profile.shake) <= 0.35 or float(profile.flash) <= 0.25
	_check(bool(screen.reduced_effects) == should_reduce, "%s/campaign-ending reduced-effects state is incorrect" % context)
	if should_reduce:
		_check(is_zero_approx(float(screen.motion_strength)), "%s/campaign-ending retained decorative motion under reduced effects" % context)
		for label_value in screen.reveal_labels:
			var label := label_value as Label
			_check(label != null and is_equal_approx(label.modulate.a, 1.0), "%s/campaign-ending left copy hidden under reduced effects" % context)
	await _dispose(screen)


func _audit_results(context: String) -> void:
	var stage_ids: PackedStringArray = stage_manager.stage_ids()
	var screen := screen_scripts.results.new() as Control
	var result := _result_fixture(String(stage_ids[0]), true)
	result.replay_available = true
	result.replay_id = "a".repeat(64)
	result.medals = ["no_miss", "no_barrier", "phase_perfect"]
	screen.setup(result)
	await _mount(screen)
	_audit_control_tree(screen, "%s/results-four-actions" % context)
	var visible_buttons := _visible_buttons(screen)
	_check(visible_buttons.size() == 4, "%s/results maximum action layout does not contain four buttons" % context)
	_check(screen.next_operation_button != null, "%s/results did not expose the unlocked next operation" % context)
	await _dispose(screen)


func _audit_records(context: String) -> void:
	var screen := screen_scripts.records.new() as Control
	var entries: Array[Dictionary] = [_result_fixture(String(stage_manager.stage_ids()[0]), true)]
	screen.setup_preview(entries, "normal", String(stage_manager.stage_ids()[0]))
	await _mount(screen)
	_audit_control_tree(screen, "%s/records" % context)
	_check(screen.back_button != null and screen.back_button.has_focus(), "%s/records did not preserve its default Back focus" % context)
	_check(screen.diagnostics_export_button != null and not screen.diagnostics_export_button.disabled, "%s/records did not expose the manual diagnostics export" % context)
	_check(screen.diagnostics_export_button.pressed.get_connections().size() == 1, "%s/records diagnostics export is not connected exactly once" % context)
	await _dispose(screen)


func _audit_credits(context: String, profile: Dictionary) -> void:
	var screen := screen_scripts.credits.new() as Control
	screen.setup(0)
	await _mount(screen)
	_check(is_equal_approx(float(screen.motion_strength), float(profile.shake)), "%s/credits ignored motion setting" % context)
	_check(is_equal_approx(float(screen.flash_strength), float(profile.flash)), "%s/credits ignored flash setting" % context)
	for page_index in int(screen.page_count()):
		screen.page_index = page_index
		screen.call("_refresh_page")
		await _settle()
		_audit_control_tree(screen, "%s/credits-page-%d" % [context, page_index + 1])
		_check(screen.page_body.get_visible_line_count() == screen.page_body.get_line_count(), "%s/credits page %d body is vertically truncated" % [context, page_index + 1])
	await _dispose(screen)


func _result_fixture(stage_id: String, cleared: bool) -> Dictionary:
	return {
		"mode": "campaign", "difficulty": "normal", "stage_id": stage_id,
		"cleared": cleared, "assisted": false, "new_high_score": true,
		"score": 2987654, "total_score": 3456789, "enemies_destroyed": 285,
		"graze": 1240, "max_combo": 183, "deaths": 0, "barriers_used": 0,
		"clear_time": 203.45, "boss_bonus": 469135, "boss_phase_metrics": []
	}


func _mount(screen: Control) -> void:
	if screen == null:
		_fail("attempted to mount a null screen")
		return
	get_root().add_child(screen)
	await _settle()


func _dispose(screen: Control) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	await _settle()


func _settle() -> void:
	for _frame in 3:
		await process_frame


func _audit_control_tree(screen: Control, context: String, virtual_focus := false) -> void:
	screens_checked += 1
	var screen_rect := screen.get_global_rect()
	_check(_rect_matches(screen_rect, Rect2(Vector2.ZERO, EXPECTED_VIEWPORT)), "%s root rect is not 540x960: %s" % [context, str(screen_rect)])
	var controls: Array[Control] = [screen]
	for child in screen.find_children("*", "Control", true, false):
		if child is Control:
			controls.append(child as Control)
	var interactive_controls: Array[Control] = []
	for control in controls:
		if not control.is_visible_in_tree():
			continue
		if control is Label or control is BaseButton or control is Range or control is PanelContainer or control is ScrollContainer:
			controls_checked += 1
			var rect := control.get_global_rect()
			_check(_rect_inside_viewport(rect), "%s %s escaped viewport: %s" % [context, _control_name(control), str(rect)])
		if control is Label:
			_audit_label(control as Label, context)
		if control is BaseButton:
			var button := control as BaseButton
			buttons_checked += 1
			interactive_controls.append(button)
			_check(button.size.x + BOUNDS_EPSILON >= button.get_combined_minimum_size().x and button.size.y + BOUNDS_EPSILON >= button.get_combined_minimum_size().y, "%s button is smaller than its localized minimum: %s size=%s minimum=%s" % [context, _control_name(button), str(button.size), str(button.get_combined_minimum_size())])
			if not button.disabled:
				if virtual_focus:
					_check(button.focus_mode == Control.FOCUS_NONE, "%s virtual-focus button unexpectedly entered GUI focus: %s" % [context, _control_name(button)])
				else:
					_check(button.focus_mode != Control.FOCUS_NONE, "%s enabled button has no GUI focus mode: %s" % [context, _control_name(button)])
		elif control is Range:
			interactive_controls.append(control)

	_audit_interactive_overlap(interactive_controls, context)
	var focusable_buttons: Array[BaseButton] = []
	for button in _visible_buttons(screen):
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			focusable_buttons.append(button)
	if not virtual_focus and not focusable_buttons.is_empty():
		var focus_owner := screen.get_viewport().gui_get_focus_owner()
		_check(focus_owner != null and (focus_owner == screen or screen.is_ancestor_of(focus_owner)), "%s has no initial in-screen GUI focus owner" % context)
		for button in focusable_buttons:
			button.grab_focus()
			_check(button.has_focus(), "%s button cannot acquire GUI focus: %s" % [context, _control_name(button)])


func _audit_label(label: Label, context: String) -> void:
	if label.text.is_empty() or label.size.x <= 0.0 or label.size.y <= 0.0:
		return
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		_check(label.get_visible_line_count() == label.get_line_count(), "%s wrapped label is vertically truncated: %s lines=%d/%d" % [context, _control_name(label), label.get_visible_line_count(), label.get_line_count()])
		return
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	for line in label.text.split("\n"):
		var rendered_width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_check(rendered_width <= label.size.x + BOUNDS_EPSILON, "%s label text exceeds its rect: %s %.1f > %.1f" % [context, _control_name(label), rendered_width, label.size.x])


func _audit_interactive_overlap(controls: Array[Control], context: String) -> void:
	for first_index in controls.size():
		var first := controls[first_index]
		if first is BaseButton and (first as BaseButton).disabled:
			continue
		for second_index in range(first_index + 1, controls.size()):
			var second := controls[second_index]
			if second is BaseButton and (second as BaseButton).disabled:
				continue
			var first_rect := first.get_global_rect()
			var second_rect := second.get_global_rect()
			if first_rect.intersects(second_rect):
				var overlap := first_rect.intersection(second_rect)
				_check(overlap.get_area() <= 0.5, "%s interactive controls overlap: %s %s with %s %s" % [context, _control_name(first), str(first_rect), _control_name(second), str(second_rect)])


func _visible_buttons(screen: Control) -> Array[BaseButton]:
	var buttons: Array[BaseButton] = []
	for child in screen.find_children("*", "BaseButton", true, false):
		if child is BaseButton and (child as BaseButton).is_visible_in_tree():
			buttons.append(child as BaseButton)
	return buttons


func _rect_inside_viewport(rect: Rect2) -> bool:
	return rect.position.x >= -BOUNDS_EPSILON and rect.position.y >= -BOUNDS_EPSILON and rect.end.x <= EXPECTED_VIEWPORT.x + BOUNDS_EPSILON and rect.end.y <= EXPECTED_VIEWPORT.y + BOUNDS_EPSILON


func _rect_matches(first: Rect2, second: Rect2) -> bool:
	return first.position.distance_to(second.position) <= BOUNDS_EPSILON and first.size.distance_to(second.size) <= BOUNDS_EPSILON


func _control_name(control: Control) -> String:
	var label := control.name
	if control is BaseButton:
		label += "('%s')" % (control as BaseButton).text.replace("\n", " ")
	elif control is Label:
		label += "('%s')" % (control as Label).text.replace("\n", " ").substr(0, 48)
	return label


func _finish() -> void:
	if failures.is_empty():
		print("UI_LAYOUT_AUDIT_OK viewport=540x960 screens=%d controls=%d buttons=%d checks=%d locales=2 effects=standard+reduced" % [screens_checked, controls_checked, buttons_checked, checks])
		quit(0)
		return
	printerr("UI_LAYOUT_AUDIT_FAILED errors=%d screens=%d controls=%d buttons=%d checks=%d" % [failures.size(), screens_checked, controls_checked, buttons_checked, checks])
	for failure in failures:
		printerr("UI_LAYOUT_ERROR %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
