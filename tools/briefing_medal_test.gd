extends SceneTree

## Verifies that the pre-flight medal goals are sourced from scoring data and
## remain inside their dedicated 540x960 briefing panel in both locales.

var failures: Array[String] = []
var score_manager: Node
var save_manager: Node
var stage_manager: Node
var audio_manager: Node
var presenter_script: Script
var briefing_script: Script


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	score_manager = get_root().get_node_or_null("ScoreManager")
	save_manager = get_root().get_node_or_null("SaveManager")
	stage_manager = get_root().get_node_or_null("StageManager")
	audio_manager = get_root().get_node_or_null("AudioManager")
	presenter_script = load("res://ui/performance_medal_presenter.gd") as Script
	briefing_script = load("res://ui/operation_briefing.gd") as Script
	if score_manager == null or save_manager == null or stage_manager == null or audio_manager == null or presenter_script == null or briefing_script == null:
		_fail("required scripts or autoloads are unavailable")
		_finish()
		return
	# Focus movement normally plays a generated UI sound. This isolated layout
	# test needs no audio and clearing the cache avoids leaving playback objects
	# alive when the custom SceneTree exits immediately.
	audio_manager.sfx_cache.clear()
	var original_language := String(save_manager.settings.get("language", "en"))
	for locale in ["en", "ko"]:
		save_manager.settings["language"] = locale
		_test_presenter_contract(locale)
		for stage_id in stage_manager.stage_ids():
			await _test_briefing_layout(locale, stage_manager.stage(stage_id))
	save_manager.settings["language"] = original_language
	audio_manager.stop_music()
	for player_value in audio_manager.sfx_players:
		var player := player_value as AudioStreamPlayer
		if player != null:
			player.stop()
			player.stream = null
	audio_manager.sfx_cache.clear()
	for _frame in 3:
		await process_frame
	_finish()


func _test_presenter_contract(locale: String) -> void:
	var definitions: Array = score_manager.medal_definitions()
	var rows: Array = presenter_script.briefing_rows()
	_check(rows.size() == definitions.size(), "%s presenter row count diverges from ScoreManager" % locale)
	for index in mini(rows.size(), definitions.size()):
		var row: Dictionary = rows[index]
		var definition: Dictionary = definitions[index]
		_check(String(row.get("id", "")) == String(definition.get("id", "")), "%s medal order/ID diverged at row %d" % [locale, index])
		_check(int(row.get("bonus", 0)) == int(definition.get("bonus", -1)), "%s medal bonus diverged at row %d" % [locale, index])
		_check(not String(row.get("title", "")).is_empty() and not String(row.get("description", "")).is_empty(), "%s medal copy is empty at row %d" % [locale, index])
		_check(String(row.get("bonus_text", "")) == "+%06d" % int(definition.get("bonus", 0)), "%s compact bonus copy is invalid at row %d" % [locale, index])


func _test_briefing_layout(locale: String, stage_data: Resource) -> void:
	var briefing: Control = briefing_script.new()
	briefing.setup(stage_data, 0, "normal")
	get_root().add_child(briefing)
	await process_frame
	var definitions: Array = score_manager.medal_definitions()
	var rows: Array = briefing.medal_goal_rows
	var labels: Array = briefing.medal_goal_labels
	_check(rows.size() == definitions.size(), "%s briefing omitted a medal goal" % locale)
	_check(labels.size() == 1 + definitions.size() * 3, "%s briefing medal labels are incomplete" % locale)
	var medal_rect: Rect2 = briefing_script.MEDAL_PANEL_RECT
	for label_value in labels:
		if not label_value is Label:
			_fail("%s briefing medal entry is not a Label" % locale)
			continue
		var label := label_value as Label
		var label_rect := Rect2(label.position, label.size)
		_check(medal_rect.encloses(label_rect), "%s medal copy escaped its dedicated panel: '%s' %s" % [locale, label.text, str(label_rect)])
		var rendered_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		_check(rendered_width <= label.size.x + 0.5, "%s medal copy exceeds its row: '%s' %.1f > %.1f" % [locale, label.text, rendered_width, label.size.x])
	var objective_rect: Rect2 = briefing_script.OBJECTIVE_PANEL_RECT
	var transmission_rect: Rect2 = briefing_script.TRANSMISSION_PANEL_RECT
	_check(objective_rect.end.y < medal_rect.position.y, "%s medal panel overlaps the primary objective" % locale)
	_check(medal_rect.end.y < transmission_rect.position.y, "%s medal panel overlaps the transmission" % locale)
	_check(briefing.continue_button.position.y > transmission_rect.end.y, "%s medal/transmission content overlaps deployment actions" % locale)
	for child in briefing.find_children("*", "Label", true, false):
		var copy_label := child as Label
		if copy_label != null and copy_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			_check(copy_label.get_visible_line_count() == copy_label.get_line_count(), "%s/%s briefing copy is truncated: '%s'" % [locale, String(stage_data.stage_id), copy_label.text])
	briefing.queue_free()
	await process_frame


func _finish() -> void:
	if failures.is_empty():
		print("BRIEFING_MEDAL_TEST_OK medals=%d stages=%d locales=2 panel=%s viewport=540x960" % [
			score_manager.medal_definitions().size(),
			stage_manager.stage_ids().size(),
			str(briefing_script.MEDAL_PANEL_RECT)
		])
		quit(0)
		return
	printerr("BRIEFING_MEDAL_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("BRIEFING_MEDAL_ERROR %s" % failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
