class_name ArcadeUI
extends RefCounted

static func style_button(button: Button, accent: Color = Color("36ddff")) -> void:
	button.custom_minimum_size = Vector2(270, 52)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.82,0.9,1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _box(Color(0.025,0.04,0.10,0.88), Color(0.18,0.31,0.52,0.8), 1))
	button.add_theme_stylebox_override("hover", _box(Color(accent,0.13), Color(accent,0.9), 2))
	button.add_theme_stylebox_override("focus", _box(Color(accent,0.16), Color(accent,1.0), 2))
	button.add_theme_stylebox_override("pressed", _box(Color(accent,0.28), Color.WHITE, 2))

static func style_panel(panel: PanelContainer, color: Color = Color("36ddff")) -> void:
	panel.add_theme_stylebox_override("panel", _box(Color(0.012,0.02,0.065,0.96), Color(color,0.62), 2, 14))

static func _box(background: Color, border: Color, width: int, radius: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box
