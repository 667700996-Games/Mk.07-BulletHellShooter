class_name TitleScreen
extends Control

signal start_pressed

var time := 0.0
var menu: VBoxContainer
var options_panel: PanelContainer
var city_keyart: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city_keyart = load("res://assets/backgrounds/title_megacity.png") as Texture2D
	_build_menu()
	AudioManager.play_music("title")

func _build_menu() -> void:
	menu = VBoxContainer.new()
	menu.position = Vector2(135, 585)
	menu.add_theme_constant_override("separation", 12)
	add_child(menu)
	var start := _menu_button("START GAME")
	var options := _menu_button("OPTIONS")
	var quit := _menu_button("QUIT")
	menu.add_child(start)
	menu.add_child(options)
	menu.add_child(quit)
	start.pressed.connect(_start)
	options.pressed.connect(_show_options)
	quit.pressed.connect(_quit)
	start.grab_focus.call_deferred()

func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	ArcadeUI.style_button(button, Color("35e6ff"))
	button.focus_entered.connect(func(): AudioManager.play_sfx("ui_move", 1.0, -5.0))
	return button

func _start() -> void:
	AudioManager.play_sfx("ui_confirm", 1.0, 0.0)
	start_pressed.emit()

func _quit() -> void:
	AudioManager.play_sfx("ui_confirm", 0.7, -4.0)
	AudioManager.shutdown()
	get_tree().quit()

func _show_options() -> void:
	AudioManager.play_sfx("ui_confirm", 1.15, -2.0)
	menu.visible = false
	options_panel = PanelContainer.new()
	options_panel.position = Vector2(70, 425)
	options_panel.custom_minimum_size = Vector2(400, 450)
	ArcadeUI.style_panel(options_panel, Color("a45cff"))
	add_child(options_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	options_panel.add_child(content)
	var heading := Label.new()
	heading.text = "SYSTEM OPTIONS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("d9c7ff"))
	content.add_child(heading)
	_add_slider(content, "MASTER", "master")
	_add_slider(content, "MUSIC", "music")
	_add_slider(content, "SFX", "sfx")
	_add_slider(content, "SCREEN SHAKE", "shake")
	_add_slider(content, "FLASH", "flash")
	_add_slider(content, "BULLET CONTRAST", "bullet_contrast")
	var auto_fire := CheckButton.new()
	auto_fire.text = "AUTO PRIMARY FIRE"
	auto_fire.button_pressed = bool(SaveManager.settings.auto_fire)
	auto_fire.add_theme_font_size_override("font_size", 15)
	auto_fire.toggled.connect(func(value: bool): SaveManager.set_setting("auto_fire", value))
	content.add_child(auto_fire)
	var fullscreen := CheckButton.new()
	fullscreen.text = "FULLSCREEN"
	fullscreen.button_pressed = bool(SaveManager.settings.fullscreen)
	fullscreen.add_theme_font_size_override("font_size", 15)
	fullscreen.toggled.connect(func(value: bool): SaveManager.set_setting("fullscreen", value))
	content.add_child(fullscreen)
	var controls := Label.new()
	controls.text = "MOVE  WASD / ARROWS / STICK\nSHOT  Z / J / [A]   FOCUS  X / K / [X]\nBARRIER  C / L / [B]   PAUSE  ESC / START"
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color(0.62,0.74,0.9))
	content.add_child(controls)
	var back := _menu_button("BACK")
	back.custom_minimum_size.y = 44
	back.pressed.connect(_close_options)
	content.add_child(back)
	back.grab_focus.call_deferred()

func _add_slider(parent: VBoxContainer, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 95
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(235, 28)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveManager.settings[key])
	slider.value_changed.connect(func(value: float): SaveManager.set_setting(key, value))
	row.add_child(slider)
	parent.add_child(row)

func _close_options() -> void:
	AudioManager.play_sfx("ui_confirm", 0.9, -3.0)
	options_panel.queue_free()
	options_panel = null
	menu.visible = true
	(menu.get_child(0) as Button).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and options_panel != null:
		_close_options()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Cinematic city matte, then code-driven rain and parallax accents.
	if city_keyart:
		draw_texture_rect(city_keyart, Rect2(0, 0, 540, 960), false, Color(0.72, 0.82, 1.0, 0.82))
	draw_rect(Rect2(0, 0, 540, 960), Color(0.005, 0.012, 0.04, 0.35))
	for band in 20:
		var color := Color("050b22").lerp(Color("180a2b"), float(band)/19.0)
		color.a = 0.10 + float(band) / 19.0 * 0.16
		draw_rect(Rect2(0,band*48,540,50),color)
	for i in 18:
		var w := 38.0 + float((i*17)%38)
		var h := 110.0 + float((i*71)%250)
		var x := float(i)*43.0 - fmod(time*11.0,43.0) - 90.0
		draw_rect(Rect2(x,530-h,w,h+440),Color(0.025, 0.055, 0.13, 0.30))
		for row in int(h/28.0):
			if (i+row*3)%4 == 0:
				draw_rect(Rect2(x+8,545-h+row*25,w-16,2),Color(0.15,0.75,1.0,0.26))
	for i in 65:
		var x := fmod(float(i*83),570.0)-15.0
		var y := fmod(float(i*139)+time*(210.0+i%5*35.0),1000.0)-20.0
		draw_line(Vector2(x,y),Vector2(x-4,y+19),Color(0.4,0.75,1.0,0.18),1.0)
	# Psychic vector emblem.
	var center := Vector2(270,245)
	for i in 3:
		var r := 94.0+i*20.0+sin(time*1.6+i)*4.0
		draw_arc(center,r,time*(0.16+i*0.07)+i,PI*1.42+time*(0.16+i*0.07)+i,72,Color(0.24,0.88,1.0,0.28-i*0.05),2.0)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-82),center+Vector2(58,48),center+Vector2(0,22),center+Vector2(-58,48)]),Color(0.15,0.85,1.0,0.18))
	draw_line(center+Vector2(0,-72),center+Vector2(0,66),Color("effdff"),4.0)
	draw_line(center+Vector2(-48,43),center+Vector2(48,43),Color("a55fff"),4.0)
	draw_string(font,Vector2(0,382),"PSYCHIC",HORIZONTAL_ALIGNMENT_CENTER,540,27,Color(0.68,0.82,1.0))
	draw_string(font,Vector2(0,438),"V E C T O R",HORIZONTAL_ALIGNMENT_CENTER,540,46,Color.WHITE)
	draw_line(Vector2(105,460),Vector2(435,460),Color("36ddff"),2.0)
	draw_string(font,Vector2(0,489),"URBAN ANOMALY ASSAULT",HORIZONTAL_ALIGNMENT_CENTER,540,13,Color("b069ff"))
	draw_string(font,Vector2(0,922),"© 2026 VECTOR CELL  //  ORIGINAL ARCADE EDITION",HORIZONTAL_ALIGNMENT_CENTER,540,10,Color(0.34,0.48,0.67))
