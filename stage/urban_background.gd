class_name UrbanBackground
extends Node2D

var time := 0.0
var speed_scale := 1.0
var escalation := 0.0
var seed := 7717
var city_keyart: Texture2D

func _ready() -> void:
	city_keyart = load("res://assets/backgrounds/title_megacity.png") as Texture2D

func _process(delta: float) -> void:
	time += delta * speed_scale
	queue_redraw()

func set_escalation(value: float) -> void:
	escalation = clampf(value, 0.0, 1.0)

func _draw() -> void:
	if city_keyart:
		var drift := sin(time * 0.035) * 7.0
		draw_texture_rect(city_keyart, Rect2(-6 + drift, -8, 552, 982), false, Color(0.38, 0.52, 0.78, 0.48))
	# Layer 1: storm-lit sky.
	for band in 24:
		var y := float(band) * 40.0
		var t := float(band) / 23.0
		var color := Color("07122e").lerp(Color("160b2e"), t)
		color = color.lerp(Color("2a0d30"), escalation * 0.25)
		color.a = 0.50
		draw_rect(Rect2(0, y, 540, 42), color)
	_draw_clouds()
	# Layer 2: distant megacity silhouettes.
	_draw_skyline(0.18, 495.0, Color("111c3c"), 25, 28.0, 120.0)
	_draw_skyline(0.30, 590.0, Color("172345"), 19, 36.0, 170.0)
	# Layer 3: nearer buildings and signs.
	_draw_skyline(0.52, 710.0, Color("17213b"), 14, 48.0, 235.0)
	_draw_neon_signs()
	# Layer 4: elevated expressway and moving traffic.
	_draw_highway()
	# Layer 5: foreground gantries.
	_draw_foreground()
	_draw_rain()

func _draw_clouds() -> void:
	for i in 7:
		var x := fmod(float(i * 127) - time * (8.0 + i), 760.0) - 110.0
		var y := 80.0 + float((i * 71) % 230)
		draw_circle(Vector2(x, y), 85.0 + i * 7.0, Color(0.08, 0.12, 0.23, 0.10))
	if fmod(time, 11.0) < 0.08:
		draw_rect(Rect2(0, 0, 540, 680), Color(0.55, 0.72, 1.0, 0.035))

func _draw_skyline(parallax: float, baseline: float, color: Color, count: int, width: float, height: float) -> void:
	var scroll := fmod(time * 42.0 * parallax, width * 2.0)
	for i in range(-2, count + 2):
		var x := float(i) * width - scroll
		var wave := sin(float(i * 43 + seed) * 0.83)
		var h := height * (0.52 + absf(wave) * 0.48)
		var rect := Rect2(x, baseline - h, width + 1.0, h + 390.0)
		draw_rect(rect, color)
		draw_rect(Rect2(x + 3.0, baseline - h + 4.0, width - 6.0, 3.0), Color(0.2, 0.55, 0.9, 0.22))
		for row in int(h / 25.0):
			for col in maxi(1, int(width / 13.0)):
				if (i * 7 + row * 3 + col * 11) % 5 == 0:
					var lit := Color("31d9ff") if (row + col) % 3 else Color("ff4fa8")
					draw_rect(Rect2(x + 6.0 + col * 11.0, baseline - h + 14.0 + row * 24.0, 3.0, 8.0), Color(lit, 0.28))

func _draw_neon_signs() -> void:
	var offset := fmod(time * 22.0, 680.0)
	for i in 6:
		var y := fmod(float(i * 173) + offset, 760.0) + 110.0
		var left := i % 2 == 0
		var x := 12.0 if left else 468.0
		var c := Color("30eaff") if i % 3 else Color("ff3d9e")
		draw_rect(Rect2(x, y, 60, 24), Color(0.02, 0.03, 0.09, 0.85))
		draw_rect(Rect2(x, y, 60, 2), Color(c, 0.8))
		draw_line(Vector2(x + 8, y + 9), Vector2(x + 50, y + 9), Color(c, 0.45), 2.0)
		draw_line(Vector2(x + 18, y + 16), Vector2(x + 43, y + 16), Color(c, 0.32), 2.0)

func _draw_highway() -> void:
	var center := 270.0
	var top_y := 560.0
	var bottom_y := 1040.0
	var road := PackedVector2Array([Vector2(168, top_y), Vector2(372, top_y), Vector2(505, bottom_y), Vector2(35, bottom_y)])
	draw_colored_polygon(road, Color("111827"))
	draw_polyline(PackedVector2Array([Vector2(168, top_y), Vector2(35, bottom_y)]), Color("3a4967"), 8.0)
	draw_polyline(PackedVector2Array([Vector2(372, top_y), Vector2(505, bottom_y)]), Color("3a4967"), 8.0)
	for i in 12:
		var z := fmod(float(i) / 12.0 + time * 0.12, 1.0)
		var y := lerpf(top_y, bottom_y, z * z)
		var half_w := lerpf(15.0, 125.0, z)
		draw_line(Vector2(center - half_w, y), Vector2(center - half_w - 8.0 * z, y + 20.0 * z), Color(0.3, 0.75, 1.0, 0.34), 2.0 + z * 3.0)
		draw_line(Vector2(center + half_w, y), Vector2(center + half_w + 8.0 * z, y + 20.0 * z), Color(1.0, 0.25, 0.55, 0.3), 2.0 + z * 3.0)
	for i in 9:
		var z := fmod(float(i) / 9.0 + time * (0.095 + float(i % 2) * 0.025), 1.0)
		var y := lerpf(top_y, bottom_y, z * z)
		var lane := -1.0 if i % 2 else 1.0
		var x := center + lane * lerpf(34.0, 105.0, z)
		var size := lerpf(2.0, 12.0, z)
		var car_color := Color("ff315c") if lane < 0 else Color("39e8ff")
		draw_rect(Rect2(x - size * 0.5, y, size, size * 1.8), Color(car_color, 0.85))
		draw_circle(Vector2(x, y + size * 1.8), size * 0.9, Color(car_color, 0.14))

func _draw_foreground() -> void:
	var scroll := fmod(time * 105.0, 420.0)
	for i in 4:
		var y := float(i) * 420.0 + scroll - 420.0
		draw_rect(Rect2(-14, y, 48, 180), Color("0a1020"))
		draw_rect(Rect2(506, y + 120, 48, 185), Color("0a1020"))
		draw_line(Vector2(20, y + 20), Vector2(520, y + 140), Color(0.06, 0.10, 0.19, 0.74), 11.0)
		draw_line(Vector2(20, y + 20), Vector2(520, y + 140), Color(0.18, 0.34, 0.52, 0.18), 2.0)

func _draw_rain() -> void:
	for i in 105:
		var x := fmod(float(i * 83 + seed), 620.0) - 40.0
		var speed := 310.0 + float((i * 47) % 220)
		var y := fmod(float(i * 137) + time * speed, 1050.0) - 40.0
		var length := 8.0 + float(i % 7) * 2.5
		draw_line(Vector2(x, y), Vector2(x - length * 0.22, y + length), Color(0.38, 0.72, 1.0, 0.15 + float(i % 3) * 0.04), 1.0)
