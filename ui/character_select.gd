class_name CharacterSelect
extends Control

signal character_confirmed(index: int)
signal cancelled

var selected := 0
var time := 0.0
var practice_mode := false
var portraits: Array[Texture2D] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portraits = [
		load("res://assets/characters/kira_voss_keyart.png") as Texture2D,
		load("res://assets/characters/dae_ryu_keyart.png") as Texture2D,
		load("res://assets/characters/mina_zero_keyart.png") as Texture2D
	]
	selected = SaveManager.selected_character
	set_process_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		_change(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_change(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("primary") or event.is_action_pressed("ui_accept"):
		AudioManager.play_sfx("ui_confirm", 1.0, 1.0)
		character_confirmed.emit(selected)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause_game") or event.is_action_pressed("ui_cancel"):
		AudioManager.play_sfx("ui_move", 0.75, -3.0)
		cancelled.emit()
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse: Vector2 = event.position
		if mouse.y > 250 and mouse.y < 655:
			selected = clampi(int(mouse.x / 180.0),0,2)
			queue_redraw()
		if event.double_click:
			character_confirmed.emit(selected)

func _change(direction: int) -> void:
	selected = wrapi(selected + direction, 0, 3)
	AudioManager.play_sfx("ui_move", 0.92 + selected*0.06, -2.0)
	queue_redraw()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0,0,540,960),Color("060b22"))
	for i in 12:
		var y := fmod(i*96.0+time*38.0,1040.0)-80.0
		draw_line(Vector2(0,y),Vector2(540,y-180),Color(0.13,0.42,0.7,0.10),2.0)
	draw_string(font,Vector2(0,70),GameText.text("practice_select") if practice_mode else GameText.text("select_vector"),HORIZONTAL_ALIGNMENT_CENTER,540,28,Color.WHITE)
	draw_string(font,Vector2(0,100),GameText.text("practice_sub") if practice_mode else GameText.text("select_sub"),HORIZONTAL_ALIGNMENT_CENTER,540,12,Color(0.46,0.66,0.88))
	for i in 3:
		_draw_card(i,Rect2(12+i*176,165,164,500))
	var data: Dictionary = GameManager.CHARACTERS[selected]
	draw_rect(Rect2(34,700,472,118),Color(0.02,0.035,0.10,0.92))
	draw_line(Vector2(34,700),Vector2(506,700),data.primary_color,2.0)
	var code := String(data.code).to_lower()
	draw_string(font,Vector2(54,735),GameText.text("character_%s_shot" % code),HORIZONTAL_ALIGNMENT_LEFT,-1,22,data.primary_color)
	draw_string(font,Vector2(54,765),GameText.text("character_%s_desc" % code),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	draw_string(font,Vector2(54,796),GameText.text("focus_desc"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(0.58,0.72,0.9))
	draw_string(font,Vector2(0,868),"◀ / ▶  %s" % GameText.text("select"),HORIZONTAL_ALIGNMENT_CENTER,270,14,Color(0.6,0.75,0.92))
	draw_string(font,Vector2(270,868),"%s / A  %s" % [SaveManager.keyboard_binding_label("primary"), GameText.text("deploy")],HORIZONTAL_ALIGNMENT_CENTER,270,14,Color("91f7ff"))

func _draw_card(index: int, rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var data: Dictionary = GameManager.CHARACTERS[index]
	var active := index == selected
	var color: Color = data.primary_color
	draw_rect(rect,Color(color,0.15 if active else 0.04))
	draw_rect(rect,Color(color,0.95 if active else 0.22),false,3.0 if active else 1.0)
	var center := Vector2(rect.position.x+rect.size.x*0.5,rect.position.y+155)
	if active:
		draw_circle(center,73+sin(time*3.0)*3.0,Color(color,0.10))
		draw_arc(center,75,time,PI*1.45+time,40,Color(color,0.62),2.0)
	var portrait_rect := Rect2(rect.position.x + 4.0, rect.position.y + 8.0, rect.size.x - 8.0, 255.0)
	var portrait_tint := Color(1, 1, 1, 1.0 if active else 0.52)
	if portraits[index]:
		draw_texture_rect(portraits[index], portrait_rect, false, portrait_tint)
	draw_string(font,Vector2(rect.position.x,rect.position.y+282),data.name,HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,18,Color.WHITE if active else Color(0.5,0.6,0.75))
	var code := String(data.code).to_lower()
	draw_string(font,Vector2(rect.position.x,rect.position.y+308),GameText.text("character_%s_role" % code),HORIZONTAL_ALIGNMENT_CENTER,rect.size.x,11,color)
	var speed_units: int = [3,2,5][index]
	var power_units: int = [3,5,2][index]
	var width_units: int = [3,2,5][index]
	_draw_stat(rect.position+Vector2(18,345),GameText.text("speed"),speed_units,color)
	_draw_stat(rect.position+Vector2(18,385),GameText.text("power"),power_units,color)
	_draw_stat(rect.position+Vector2(18,425),GameText.text("width"),width_units,color)

func _draw_stat(position: Vector2, label: String, value: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font,position,label,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(0.55,0.66,0.82))
	for i in 5:
		draw_rect(Rect2(position.x+i*25,position.y+10,19,6),color if i<value else Color(0.15,0.2,0.3,1))
