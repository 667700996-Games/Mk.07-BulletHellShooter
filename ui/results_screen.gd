class_name ResultsScreen
extends Control

signal retry_pressed
signal title_pressed
signal replay_pressed(replay_id: String)
signal next_operation_pressed(stage_id: String)

var result: Dictionary
var time := 0.0
var character_art: Texture2D
var replay_button: Button
var next_operation_button: Button
var next_stage_id := ""
var medal_ids: Array[String] = []
var medal_bonus := 0

func setup(data: Dictionary) -> void:
	result = data

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var art_paths := [
		"res://assets/characters/kira_voss_keyart.png",
		"res://assets/characters/dae_ryu_keyart.png",
		"res://assets/characters/mina_zero_keyart.png"
	]
	character_art = load(art_paths[GameManager.selected_character]) as Texture2D
	medal_ids = ScoreManager.normalize_medal_ids(result.get("medals", []))
	medal_bonus = ScoreManager.medal_bonus_for_ids(medal_ids)
	var replay_id := String(result.get("replay_id", ""))
	var replay_available := String(result.get("mode", "campaign")) == "campaign" and bool(result.get("replay_available", false)) and not replay_id.is_empty()
	next_stage_id = _eligible_next_stage_id()
	var next_operation_available := not next_stage_id.is_empty()
	if next_operation_available:
		next_operation_button = Button.new()
		next_operation_button.text = GameText.text("next_operation")
		next_operation_button.position = Vector2(135, 730)
		ArcadeUI.style_button(next_operation_button, Color("69ffa8"))
		add_child(next_operation_button)
		next_operation_button.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); next_operation_pressed.emit(next_stage_id))
	if replay_available:
		replay_button = Button.new()
		replay_button.text = GameText.text("watch_replay")
		replay_button.position = Vector2(135, 786 if next_operation_available else 730)
		ArcadeUI.style_button(replay_button, Color("ff4f9f"))
		add_child(replay_button)
		replay_button.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); replay_pressed.emit(replay_id))
	var retry := Button.new()
	retry.text = GameText.text("retry")
	if next_operation_available:
		retry.position = Vector2(135, 842 if replay_available else 792)
	else:
		retry.position = Vector2(135, 792 if replay_available else 790)
	ArcadeUI.style_button(retry,Color("41e7ff"))
	add_child(retry)
	var title := Button.new()
	title.text = GameText.text("return_title")
	if next_operation_available:
		title.position = Vector2(135, 898 if replay_available else 854)
	else:
		title.position = Vector2(135, 854 if replay_available else 856)
	ArcadeUI.style_button(title,Color("a65cff"))
	add_child(title)
	retry.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); retry_pressed.emit())
	title.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); title_pressed.emit())
	(next_operation_button if next_operation_available else (replay_button if replay_available else retry)).grab_focus.call_deferred()
	AudioManager.play_music("result")

func _eligible_next_stage_id() -> String:
	if String(result.get("mode", "campaign")) != "campaign" or not bool(result.get("cleared", false)):
		return ""
	var completed_stage_id := String(result.get("stage_id", ""))
	if not StageManager.has_stage(completed_stage_id):
		return ""
	var catalog := StageManager.stage_ids()
	var completed_index := catalog.find(completed_stage_id)
	if completed_index < 0 or completed_index + 1 >= catalog.size():
		return ""
	var candidate := String(catalog[completed_index + 1])
	return candidate if StageManager.has_stage(candidate) and SaveManager.is_stage_unlocked(candidate) else ""

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0,0,540,960),Color("05091d"))
	if character_art:
		draw_texture_rect(character_art, Rect2(278, 90, 262, 393), false, Color(0.40, 0.52, 0.72, 0.18))
	for i in 8:
		var radius := 80.0+i*42.0+sin(time+i)*5.0
		draw_arc(Vector2(270,330),radius,time*(0.12+i*0.02)+i,PI*1.35+time*(0.12+i*0.02)+i,60,Color(0.18,0.62,1.0,0.1),1.0)
	var cleared: bool = result.get("cleared",false)
	var mode := String(result.get("mode", "campaign"))
	var practice := mode == "practice"
	var replay := mode == "replay"
	var assisted := bool(result.get("assisted", false))
	var difficulty_id := String(result.get("difficulty", "normal"))
	var result_title := GameText.text("practice_complete") if practice and cleared else (GameText.text("mission_complete") if cleared else GameText.text("vector_lost"))
	draw_string(font,Vector2(0,94),result_title,HORIZONTAL_ALIGNMENT_CENTER,540,32,Color("64f5ff") if cleared else Color("ff496d"))
	var after_action_key := String(result.get("after_action_key", "after_action"))
	var practice_boss_name := "boss_seraph_name"
	var result_stage := StageManager.stage(String(result.get("stage_id", StageManager.DEFAULT_STAGE_ID)))
	if result_stage != null:
		practice_boss_name = result_stage.final_boss_name_key
	var practice_report := GameText.text("practice_report_stage") % GameText.text(practice_boss_name)
	var report_subtitle := GameText.text("replay_verified") if replay and bool(result.get("replay_verified", false)) else (GameText.text("replay_desync") if replay else (practice_report if practice else ("%s // %s" % [GameText.text("assisted_report"), GameText.text("difficulty_%s" % difficulty_id)] if assisted else "%s // %s" % [GameText.text(after_action_key), GameText.text("difficulty_%s" % difficulty_id)])))
	draw_string(font,Vector2(0,125),report_subtitle,HORIZONTAL_ALIGNMENT_CENTER,540,12,Color(0.5,0.66,0.86))
	var rows := [
		[GameText.text("combat_score"),"%012d" % int(result.get("score",0))],
		[GameText.text("enemies_destroyed"),"%04d" % int(result.get("enemies_destroyed",0))],
		[GameText.text("graze"),"%05d" % int(result.get("graze",0))],
		[GameText.text("max_chain"),"%04d" % int(result.get("max_combo",0))],
		[GameText.text("vector_losses"),"%02d" % int(result.get("deaths",0))],
		[GameText.text("barriers_used"),"%02d" % int(result.get("barriers_used",0))],
		[GameText.text("clear_time"),_format_time(float(result.get("clear_time",0.0)))],
		[GameText.text("risk_bank_bonus"),"+%09d" % int(result.get("risk_bank_bonus",0))],
		[GameText.text("phase_bonus"),"+%09d" % int(result.get("boss_bonus",0))]
	]
	var y := 195.0
	for row in rows:
		draw_string(font,Vector2(76,y),row[0],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.52,0.67,0.85))
		draw_string(font,Vector2(304,y),row[1],HORIZONTAL_ALIGNMENT_RIGHT,160,17,Color.WHITE)
		draw_line(Vector2(76,y+10),Vector2(464,y+10),Color(0.15,0.29,0.48,0.48),1.0)
		y += 43.0
	var medal_rect := Rect2(60, 572, 420, 52)
	draw_rect(medal_rect, Color(0.025, 0.052, 0.12, 0.92))
	draw_rect(medal_rect, Color("a65cff"), false, 1.0)
	draw_string(font, Vector2(78, 591), "%s  %d/%d" % [GameText.text("performance_medals"), medal_ids.size(), ScoreManager.medal_definitions().size()], HORIZONTAL_ALIGNMENT_LEFT, 260, 11, Color("d5bbff"))
	draw_string(font, Vector2(344, 591), "+%09d" % medal_bonus, HORIZONTAL_ALIGNMENT_RIGHT, 116, 11, Color("ffe579"))
	draw_string(font, Vector2(78, 614), _medal_title_line(), HORIZONTAL_ALIGNMENT_LEFT, 382, 11, Color(0.78, 0.88, 1.0))
	draw_rect(Rect2(60,632,420,76),Color(0.03,0.07,0.15,0.88))
	draw_line(Vector2(60,632),Vector2(480,632),Color("52e6ff"),3.0)
	draw_string(font,Vector2(80,657),GameText.text("total_score"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.65,0.78,0.94))
	draw_string(font,Vector2(80,696),"%012d" % int(result.get("total_score",0)),HORIZONTAL_ALIGNMENT_RIGHT,380,27,Color("ffe579"))
	if mode == "campaign" and not assisted and bool(result.get("new_high_score", false)):
		var has_top_action := replay_button != null or next_operation_button != null
		draw_string(font, Vector2(0, 718 if has_top_action else 743), GameText.text("new_high_score"), HORIZONTAL_ALIGNMENT_CENTER, 540, 15, Color("ff68b0"))

func _format_time(value: float) -> String:
	var minutes := int(value)/60
	var seconds := int(value)%60
	return "%02d:%02d.%02d" % [minutes,seconds,int(fmod(value,1.0)*100.0)]

func _medal_title_line() -> String:
	if medal_ids.is_empty():
		return "—"
	var titles := PackedStringArray()
	for medal_id in medal_ids:
		var definition := ScoreManager.medal_definition(medal_id)
		if not definition.is_empty():
			titles.append(GameText.text(String(definition.get("title_key", ""))))
	return "  ·  ".join(titles) if not titles.is_empty() else "—"
