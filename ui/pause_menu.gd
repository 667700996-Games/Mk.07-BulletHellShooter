class_name PauseMenu
extends CanvasLayer

signal resume_pressed
signal restart_pressed
signal title_pressed

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.005,0.008,0.025,0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.position = Vector2(105,245)
	panel.custom_minimum_size = Vector2(330,430)
	ArcadeUI.style_panel(panel,Color("43e8ff"))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	panel.add_child(box)
	var title := Label.new()
	title.text = "VECTOR SUSPENDED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",24)
	title.add_theme_color_override("font_color",Color("7af4ff"))
	box.add_child(title)
	var sub := Label.new()
	sub.text = "PAUSE // NEON DISTRICT"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size",11)
	sub.add_theme_color_override("font_color",Color(0.48,0.64,0.82))
	box.add_child(sub)
	var resume := _button("RESUME",Color("43e8ff"))
	var restart := _button("RESTART STAGE",Color("ffb444"))
	var options := _button("AUDIO: %d%%" % int(float(SaveManager.settings.master)*100.0),Color("a45cff"))
	var quit := _button("QUIT TO TITLE",Color("ff4b78"))
	box.add_child(resume)
	box.add_child(restart)
	box.add_child(options)
	box.add_child(quit)
	resume.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); resume_pressed.emit())
	restart.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); restart_pressed.emit())
	quit.pressed.connect(func(): AudioManager.play_sfx("ui_confirm"); title_pressed.emit())
	options.pressed.connect(func():
		var next := wrapf(float(SaveManager.settings.master)+0.2,0.2,1.01)
		SaveManager.set_setting("master",next)
		options.text="AUDIO: %d%%"%int(next*100.0)
		AudioManager.play_sfx("ui_move"))
	resume.grab_focus.call_deferred()

func _button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280,52)
	ArcadeUI.style_button(button,color)
	return button

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		resume_pressed.emit()
		get_viewport().set_input_as_handled()
