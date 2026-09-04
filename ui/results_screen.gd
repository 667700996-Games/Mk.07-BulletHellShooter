class_name ResultsScreen
extends Control

signal retry_pressed
signal title_pressed
signal replay_pressed

var result: Dictionary
var time := 0.0
var character_art: Texture2D
var replay_button: Button

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
	var replay_available := String(result.get("mode", "campaign")) == "campaign" and bool(result.get("replay_available", false))
	if replay_available:
		replay_button = Button.new()
		replay_button.text = GameText.text("watch_replay")
		replay_button.position = Vector2(135, 730)
		ArcadeUI.style_button(replay_button, Color("ff4f9f"))
		add_child(replay_button)
		replay_button.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); replay_pressed.emit())
	var retry := Button.new()
	retry.text = GameText.text("retry")
	retry.position = Vector2(135, 792 if replay_available else 790)
	ArcadeUI.style_button(retry,Color("41e7ff"))
	add_child(retry)
	var title := Button.new()
	title.text = GameText.text("return_title")
	title.position = Vector2(135, 854 if replay_available else 856)
	ArcadeUI.style_button(title,Color("a65cff"))
	add_child(title)
	retry.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); retry_pressed.emit())
	title.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); title_pressed.emit())
	(replay_button if replay_available else retry).grab_focus.call_deferred()
	AudioManager.play_music("result")

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
	var report_subtitle := GameText.text("replay_verified") if replay and bool(result.get("replay_verified", false)) else (GameText.text("replay_desync") if replay else (GameText.text("practice_report") if practice else ("%s // %s" % [GameText.text("assisted_report"), GameText.text("difficulty_%s" % difficulty_id)] if assisted else "%s // %s" % [GameText.text("after_action"), GameText.text("difficulty_%s" % difficulty_id)])))
	draw_string(font,Vector2(0,125),report_subtitle,HORIZONTAL_ALIGNMENT_CENTER,540,12,Color(0.5,0.66,0.86))
	var rows := [
		[GameText.text("combat_score"),"%012d" % int(result.get("score",0))],
		[GameText.text("enemies_destroyed"),"%04d" % int(result.get("enemies_destroyed",0))],
		[GameText.text("graze"),"%05d" % int(result.get("graze",0))],
		[GameText.text("max_chain"),"%04d" % int(result.get("max_combo",0))],
		[GameText.text("vector_losses"),"%02d" % int(result.get("deaths",0))],
		[GameText.text("barriers_used"),"%02d" % int(result.get("barriers_used",0))],
		[GameText.text("clear_time"),_format_time(float(result.get("clear_time",0.0)))],
		[GameText.text("phase_bonus"),"+%09d" % int(result.get("boss_bonus",0))]
	]
	var y := 208.0
	for row in rows:
		draw_string(font,Vector2(76,y),row[0],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(0.52,0.67,0.85))
		draw_string(font,Vector2(304,y),row[1],HORIZONTAL_ALIGNMENT_RIGHT,160,17,Color.WHITE)
		draw_line(Vector2(76,y+10),Vector2(464,y+10),Color(0.15,0.29,0.48,0.48),1.0)
		y += 49.0
	draw_rect(Rect2(60,606,420,96),Color(0.03,0.07,0.15,0.88))
	draw_line(Vector2(60,606),Vector2(480,606),Color("52e6ff"),3.0)
	draw_string(font,Vector2(80,635),GameText.text("total_score"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.65,0.78,0.94))
	draw_string(font,Vector2(80,678),"%012d" % int(result.get("total_score",0)),HORIZONTAL_ALIGNMENT_RIGHT,380,31,Color("ffe579"))
	if mode == "campaign" and not assisted and int(result.get("total_score",0)) >= SaveManager.high_score_for(difficulty_id):
		draw_string(font, Vector2(0, 718 if bool(result.get("replay_available", false)) else 743), GameText.text("new_high_score"), HORIZONTAL_ALIGNMENT_CENTER, 540, 15, Color("ff68b0"))

func _format_time(value: float) -> String:
	var minutes := int(value)/60
	var seconds := int(value)%60
	return "%02d:%02d.%02d" % [minutes,seconds,int(fmod(value,1.0)*100.0)]
