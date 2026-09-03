class_name TitleScreen
extends Control

signal start_pressed
signal practice_pressed

var time := 0.0
var menu: VBoxContainer
var options_panel: PanelContainer
var bindings_panel: PanelContainer
var assist_panel: PanelContainer
var help_panel: PanelContainer
var help_button: Button
var bindings_button: Button
var assist_button: Button
var assist_preset_button: Button
var assist_description: Label
var binding_buttons: Dictionary = {}
var binding_mode := "keyboard"
var waiting_action := ""
var waiting_binding_device := "keyboard"
var waiting_button: Button
var controller_status_label: Label
var city_keyart: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	city_keyart = load("res://assets/backgrounds/title_megacity.png") as Texture2D
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_build_menu()
	AudioManager.play_music("title")

func _build_menu() -> void:
	menu = VBoxContainer.new()
	menu.position = Vector2(135, 560)
	menu.add_theme_constant_override("separation", 12)
	add_child(menu)
	var start := _menu_button(GameText.text("start_game"))
	var practice := _menu_button(GameText.text("boss_practice"))
	var options := _menu_button(GameText.text("options"))
	help_button = _menu_button(GameText.text("how_to_play"))
	var quit := _menu_button(GameText.text("quit"))
	menu.add_child(start)
	menu.add_child(practice)
	menu.add_child(options)
	menu.add_child(help_button)
	menu.add_child(quit)
	start.pressed.connect(_start)
	practice.pressed.connect(func(): AudioManager.play_sfx("ui_confirm", 1.12, 0.0); practice_pressed.emit())
	options.pressed.connect(_show_options)
	help_button.pressed.connect(_show_help)
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
	options_panel.position = Vector2(70, 350)
	options_panel.custom_minimum_size = Vector2(400, 450)
	ArcadeUI.style_panel(options_panel, Color("a45cff"))
	add_child(options_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	options_panel.add_child(content)
	var heading := Label.new()
	heading.text = GameText.text("system_options")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("d9c7ff"))
	content.add_child(heading)
	_add_slider(content, GameText.text("master"), "master")
	_add_slider(content, GameText.text("music"), "music")
	_add_slider(content, GameText.text("sfx"), "sfx")
	_add_slider(content, GameText.text("screen_shake"), "shake")
	_add_slider(content, GameText.text("flash"), "flash")
	_add_slider(content, GameText.text("bullet_contrast"), "bullet_contrast")
	var fullscreen := CheckButton.new()
	fullscreen.text = GameText.text("fullscreen")
	fullscreen.button_pressed = bool(SaveManager.settings.fullscreen)
	fullscreen.add_theme_font_size_override("font_size", 15)
	fullscreen.toggled.connect(func(value: bool): SaveManager.set_setting("fullscreen", value))
	content.add_child(fullscreen)
	var language := _menu_button(GameText.text("language"))
	language.custom_minimum_size.y = 40
	language.pressed.connect(_toggle_language)
	content.add_child(language)
	assist_button = _menu_button(GameText.text("accessibility_assists"))
	assist_button.custom_minimum_size.y = 40
	assist_button.pressed.connect(_show_assists)
	content.add_child(assist_button)
	bindings_button = _menu_button(GameText.text("key_bindings"))
	bindings_button.custom_minimum_size.y = 40
	bindings_button.pressed.connect(_show_bindings)
	content.add_child(bindings_button)
	var controls := Label.new()
	controls.text = GameText.text("controls_hint") % [
		SaveManager.keyboard_binding_label("move_up"),
		SaveManager.keyboard_binding_label("primary"),
		SaveManager.keyboard_binding_label("focus"),
		SaveManager.keyboard_binding_label("barrier")
	]
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color(0.62,0.74,0.9))
	content.add_child(controls)
	var back := _menu_button(GameText.text("back"))
	back.custom_minimum_size.y = 44
	back.pressed.connect(_close_options)
	content.add_child(back)
	back.grab_focus.call_deferred()

func _show_help() -> void:
	AudioManager.play_sfx("ui_confirm", 1.08, -2.0)
	menu.visible = false
	help_panel = PanelContainer.new()
	help_panel.position = Vector2(48, 350)
	help_panel.custom_minimum_size = Vector2(444, 520)
	ArcadeUI.style_panel(help_panel, Color("43e8ff"))
	add_child(help_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	help_panel.add_child(content)
	var heading := Label.new()
	heading.text = GameText.text("briefing_title")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color("a8f8ff"))
	content.add_child(heading)
	var body := Label.new()
	body.text = GameText.text("briefing_body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(396, 390)
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.76, 0.84, 0.96))
	body.add_theme_constant_override("line_spacing", 3)
	content.add_child(body)
	var back := _menu_button(GameText.text("back"))
	back.custom_minimum_size.y = 42
	back.pressed.connect(_close_help)
	content.add_child(back)
	back.grab_focus.call_deferred()

func _close_help() -> void:
	AudioManager.play_sfx("ui_confirm", 0.9, -3.0)
	help_panel.queue_free()
	help_panel = null
	menu.visible = true
	help_button.grab_focus.call_deferred()

func _show_assists() -> void:
	AudioManager.play_sfx("ui_confirm", 1.05, -3.0)
	options_panel.visible = false
	assist_panel = PanelContainer.new()
	assist_panel.position = Vector2(55, 300)
	assist_panel.custom_minimum_size = Vector2(430, 540)
	ArcadeUI.style_panel(assist_panel, Color("43e8ff"))
	add_child(assist_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	assist_panel.add_child(content)
	var heading := Label.new()
	heading.text = GameText.text("accessibility_assists")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("a8f8ff"))
	content.add_child(heading)
	assist_preset_button = _menu_button("")
	assist_preset_button.custom_minimum_size.y = 44
	assist_preset_button.pressed.connect(_cycle_assist_preset)
	content.add_child(assist_preset_button)
	assist_description = Label.new()
	assist_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	assist_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	assist_description.custom_minimum_size = Vector2(382, 52)
	assist_description.add_theme_font_size_override("font_size", 12)
	assist_description.add_theme_color_override("font_color", Color(0.64,0.78,0.94))
	content.add_child(assist_description)
	_add_assist_toggle(content, "show_hitbox", "show_hitbox")
	_add_assist_toggle(content, "auto_fire", "auto_fire")
	_add_assist_toggle(content, "auto_barrier", "auto_barrier")
	_add_assist_slider(content, GameText.text("bullet_contrast"), "bullet_contrast")
	_add_assist_slider(content, GameText.text("screen_shake"), "shake")
	_add_assist_slider(content, GameText.text("flash"), "flash")
	var ranking_note := Label.new()
	ranking_note.text = GameText.text("assist_ranking_note")
	ranking_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ranking_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ranking_note.custom_minimum_size = Vector2(382, 45)
	ranking_note.add_theme_font_size_override("font_size", 11)
	ranking_note.add_theme_color_override("font_color", Color("ffb7cf"))
	content.add_child(ranking_note)
	var back := _menu_button(GameText.text("back_options"))
	back.custom_minimum_size.y = 42
	back.pressed.connect(_close_assists)
	content.add_child(back)
	_refresh_assist_copy()
	assist_preset_button.grab_focus.call_deferred()

func _add_assist_toggle(parent: VBoxContainer, text_key: String, setting_key: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = GameText.text(text_key)
	toggle.button_pressed = bool(SaveManager.settings[setting_key])
	toggle.add_theme_font_size_override("font_size", 15)
	toggle.toggled.connect(func(value: bool):
		SaveManager.set_setting(setting_key, value)
		_refresh_assist_copy()
	)
	parent.add_child(toggle)

func _add_assist_slider(parent: VBoxContainer, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 125
	label.add_theme_font_size_override("font_size", 13)
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(240, 28)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveManager.settings[key])
	slider.value_changed.connect(func(value: float):
		SaveManager.set_setting(key, value)
		_refresh_assist_copy()
	)
	row.add_child(slider)
	parent.add_child(row)

func _cycle_assist_preset() -> void:
	var current := String(SaveManager.settings.get("assist_preset", "custom"))
	var index := SaveManager.ASSIST_PRESET_IDS.find(current)
	var next_id: String = SaveManager.ASSIST_PRESET_IDS[0 if index < 0 else wrapi(index + 1, 0, SaveManager.ASSIST_PRESET_IDS.size())]
	SaveManager.apply_assist_preset(next_id)
	assist_panel.queue_free()
	assist_panel = null
	_show_assists()

func _refresh_assist_copy() -> void:
	if assist_preset_button == null or assist_description == null:
		return
	var preset_id := String(SaveManager.settings.get("assist_preset", "custom"))
	assist_preset_button.text = "%s: %s" % [GameText.text("assist_preset"), GameText.text("assist_%s" % preset_id)]
	assist_description.text = GameText.text("assist_%s_desc" % preset_id)

func _close_assists() -> void:
	if assist_panel != null:
		assist_panel.queue_free()
		assist_panel = null
	assist_preset_button = null
	assist_description = null
	options_panel.visible = true
	AudioManager.play_sfx("ui_confirm", 0.92, -3.0)
	assist_button.grab_focus.call_deferred()

func _show_bindings() -> void:
	AudioManager.play_sfx("ui_confirm", 1.05, -3.0)
	options_panel.visible = false
	bindings_panel = PanelContainer.new()
	bindings_panel.position = Vector2(70, 285 if binding_mode == "keyboard" else 340)
	bindings_panel.custom_minimum_size = Vector2(400, 600 if binding_mode == "keyboard" else 470)
	ArcadeUI.style_panel(bindings_panel, Color("43e8ff"))
	add_child(bindings_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	bindings_panel.add_child(content)
	var heading := Label.new()
	heading.text = GameText.text("key_bindings")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("a8f8ff"))
	content.add_child(heading)
	var device_button := _menu_button(GameText.text("binding_device") % GameText.text("device_%s" % binding_mode))
	device_button.custom_minimum_size.y = 40
	device_button.pressed.connect(_toggle_binding_mode)
	content.add_child(device_button)
	if binding_mode == "gamepad":
		controller_status_label = Label.new()
		controller_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		controller_status_label.add_theme_font_size_override("font_size", 11)
		controller_status_label.add_theme_color_override("font_color", Color(0.62,0.78,0.94))
		content.add_child(controller_status_label)
		_refresh_controller_status()
	binding_buttons.clear()
	var actions: Array = SaveManager.REBIND_ACTIONS if binding_mode == "keyboard" else SaveManager.GAMEPAD_REBIND_ACTIONS
	for action in actions:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = GameText.text(action)
		label.custom_minimum_size = Vector2(205, 40)
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var button := Button.new()
		button.text = SaveManager.keyboard_binding_label(action) if binding_mode == "keyboard" else SaveManager.gamepad_binding_label(action)
		ArcadeUI.style_button(button, Color("43e8ff"))
		button.custom_minimum_size = Vector2(145, 40)
		button.pressed.connect(_begin_rebind.bind(action, button))
		row.add_child(button)
		binding_buttons[action] = button
		content.add_child(row)
	var reset := _menu_button(GameText.text("reset_keys") if binding_mode == "keyboard" else GameText.text("reset_gamepad"))
	reset.custom_minimum_size.y = 36
	reset.pressed.connect(_reset_bindings)
	content.add_child(reset)
	var hint := Label.new()
	hint.text = GameText.text("binding_hint") if binding_mode == "keyboard" else GameText.text("gamepad_binding_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.7, 0.88))
	content.add_child(hint)
	var back := _menu_button(GameText.text("back_options"))
	back.custom_minimum_size.y = 40
	back.pressed.connect(_close_bindings)
	content.add_child(back)
	device_button.grab_focus.call_deferred()

func _begin_rebind(action: String, button: Button) -> void:
	waiting_action = action
	waiting_binding_device = binding_mode
	waiting_button = button
	button.text = GameText.text("press_key") if binding_mode == "keyboard" else GameText.text("press_button")
	AudioManager.play_sfx("ui_move", 1.18, -4.0)

func _toggle_binding_mode() -> void:
	waiting_action = ""
	waiting_button = null
	binding_mode = "gamepad" if binding_mode == "keyboard" else "keyboard"
	if bindings_panel != null:
		bindings_panel.queue_free()
		bindings_panel = null
	_show_bindings()

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_controller_status()

func _refresh_controller_status() -> void:
	if controller_status_label == null:
		return
	var connected := Input.get_connected_joypads().size()
	controller_status_label.text = GameText.text("gamepad_connected") % connected if connected > 0 else GameText.text("gamepad_disconnected")

func _toggle_language() -> void:
	SaveManager.set_setting("language", "en" if GameText.is_korean() else "ko")
	if bindings_panel != null:
		bindings_panel.queue_free()
		bindings_panel = null
	if options_panel != null:
		options_panel.queue_free()
		options_panel = null
	if menu != null:
		menu.queue_free()
	_build_menu()
	_show_options()

func _reset_bindings() -> void:
	if binding_mode == "keyboard":
		SaveManager.reset_keyboard_bindings()
	else:
		SaveManager.reset_gamepad_bindings()
	for action in binding_buttons:
		(binding_buttons[action] as Button).text = SaveManager.keyboard_binding_label(action) if binding_mode == "keyboard" else SaveManager.gamepad_binding_label(action)
	AudioManager.play_sfx("ui_confirm", 0.82, -2.0)

func _close_bindings() -> void:
	waiting_action = ""
	waiting_binding_device = "keyboard"
	waiting_button = null
	controller_status_label = null
	binding_buttons.clear()
	if bindings_panel != null:
		bindings_panel.queue_free()
		bindings_panel = null
	options_panel.visible = true
	AudioManager.play_sfx("ui_confirm", 0.92, -3.0)
	bindings_button.grab_focus.call_deferred()

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
	bindings_button = null
	assist_button = null
	menu.visible = true
	(menu.get_child(0) as Button).grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if not waiting_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			var key_event := event as InputEventKey
			if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
				waiting_button.text = SaveManager.keyboard_binding_label(waiting_action) if waiting_binding_device == "keyboard" else SaveManager.gamepad_binding_label(waiting_action)
				waiting_action = ""
				waiting_button = null
				get_viewport().set_input_as_handled()
				return
			if waiting_binding_device == "keyboard":
				var keycode := int(key_event.physical_keycode if key_event.physical_keycode > 0 else key_event.keycode)
				SaveManager.set_keyboard_binding(waiting_action, keycode)
				waiting_button.text = SaveManager.keyboard_binding_label(waiting_action)
				waiting_action = ""
				waiting_button = null
				AudioManager.play_sfx("ui_confirm", 1.16, -2.0)
				get_viewport().set_input_as_handled()
				return
		elif waiting_binding_device == "gamepad" and event is InputEventJoypadButton and event.pressed:
			var button_event := event as InputEventJoypadButton
			SaveManager.set_gamepad_binding(waiting_action, button_event.button_index)
			waiting_button.text = SaveManager.gamepad_binding_label(waiting_action)
			waiting_action = ""
			waiting_button = null
			AudioManager.play_sfx("ui_confirm", 1.16, -2.0)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause_game") and bindings_panel != null:
		_close_bindings()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game") and assist_panel != null:
		_close_assists()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause_game") and help_panel != null:
		_close_help()
		get_viewport().set_input_as_handled()
		return
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
