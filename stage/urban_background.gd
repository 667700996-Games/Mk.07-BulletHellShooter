class_name UrbanBackground
extends Node2D

var time := 0.0
var speed_scale := 1.0
var escalation := 0.0
var route_progress := 0.0
var encounter_state := "route"
var boss_phase := 0
var seed := 7717
var city_keyart: Texture2D

func _ready() -> void:
	city_keyart = load("res://assets/backgrounds/title_megacity.png") as Texture2D

func _process(delta: float) -> void:
	time += delta * speed_scale
	queue_redraw()

func set_escalation(value: float) -> void:
	escalation = clampf(value, 0.0, 1.0)

func set_route_context(route_time: float, encounter: String, phase: int = 0) -> void:
	route_progress = clampf(route_time / 180.0, 0.0, 1.0)
	encounter_state = encounter
	boss_phase = phase
	speed_scale = 0.38 if encounter == "midboss" else (0.72 if encounter == "final" else 1.0)

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
	_draw_route_landmarks()
	# Layer 3: nearer buildings and signs.
	_draw_skyline(0.52, 710.0, Color("17213b"), 14, 48.0, 235.0)
	_draw_neon_signs()
	# Layer 4: elevated expressway and moving traffic.
	_draw_highway()
	# Layer 5: foreground gantries.
	_draw_foreground()
	_draw_rain()

func _draw_route_landmarks() -> void:
	var transit_alpha := _segment_alpha(0.0, 0.34)
	var containment_alpha := _segment_alpha(0.24, 0.60)
	var bridge_alpha := _segment_alpha(0.50, 0.82)
	var spine_alpha := smoothstep(0.70, 0.88, route_progress)
	if transit_alpha > 0.01:
		_draw_transit_gate(transit_alpha)
	if containment_alpha > 0.01:
		_draw_containment_tower(containment_alpha)
	if bridge_alpha > 0.01:
		_draw_broken_skybridge(bridge_alpha)
	if spine_alpha > 0.01:
		_draw_control_spine(spine_alpha)
	if encounter_state == "midboss":
		var lock_alpha := 0.16 + absf(sin(time * 2.8)) * 0.12
		for i in 3:
			var y := 250.0 + i * 145.0
			draw_line(Vector2(48, y), Vector2(492, y), Color(1.0, 0.42, 0.18, lock_alpha), 2.0)
			draw_line(Vector2(80 + i * 58, 170), Vector2(80 + i * 58, 690), Color(1.0, 0.42, 0.18, lock_alpha * 0.55), 1.0)

func _segment_alpha(start: float, finish: float) -> float:
	var fade_in := smoothstep(start, minf(finish, start + 0.08), route_progress)
	var fade_out := 1.0 - smoothstep(maxf(start, finish - 0.08), finish, route_progress)
	return fade_in * fade_out

func _draw_transit_gate(alpha: float) -> void:
	var gate_y := 375.0 + sin(time * 0.32) * 5.0
	for side in [-1.0, 1.0]:
		var x: float = 270.0 + float(side) * 176.0
		draw_rect(Rect2(x - 18.0, gate_y - 135.0, 36.0, 270.0), Color(0.03, 0.09, 0.17, alpha * 0.78))
		draw_line(Vector2(x, gate_y - 118.0), Vector2(x, gate_y + 118.0), Color(0.20, 0.82, 1.0, alpha * 0.34), 3.0)
	draw_arc(Vector2(270, gate_y), 176.0, PI, TAU, 64, Color(0.25, 0.86, 1.0, alpha * 0.42), 5.0)
	draw_arc(Vector2(270, gate_y), 149.0, PI, TAU, 64, Color(0.65, 0.34, 1.0, alpha * 0.24), 2.0)

func _draw_containment_tower(alpha: float) -> void:
	var center := Vector2(270, 390)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-62, 190), center + Vector2(-38, -132),
		center + Vector2(0, -184), center + Vector2(38, -132), center + Vector2(62, 190)
	]), Color(0.025, 0.065, 0.15, alpha * 0.86))
	for i in 5:
		var y := center.y - 110.0 + i * 58.0
		draw_line(Vector2(center.x - 43.0, y), Vector2(center.x + 43.0, y), Color(0.75, 0.22, 1.0, alpha * (0.18 + i * 0.035)), 2.0)
	var pulse := 26.0 + absf(sin(time * 1.7)) * 9.0
	draw_circle(center + Vector2(0, -48), pulse, Color(0.28, 0.88, 1.0, alpha * 0.10))
	draw_arc(center + Vector2(0, -48), pulse, 0, TAU, 32, Color(0.42, 0.92, 1.0, alpha * 0.48), 2.0)

func _draw_broken_skybridge(alpha: float) -> void:
	var left := PackedVector2Array([Vector2(-20, 360), Vector2(214, 405), Vector2(206, 442), Vector2(-20, 414)])
	var right := PackedVector2Array([Vector2(560, 330), Vector2(326, 395), Vector2(334, 432), Vector2(560, 382)])
	draw_colored_polygon(left, Color(0.035, 0.055, 0.11, alpha * 0.90))
	draw_colored_polygon(right, Color(0.035, 0.055, 0.11, alpha * 0.90))
	draw_line(Vector2(16, 377), Vector2(205, 419), Color(0.22, 0.62, 0.92, alpha * 0.24), 3.0)
	draw_line(Vector2(334, 414), Vector2(528, 361), Color(1.0, 0.24, 0.48, alpha * 0.25), 3.0)
	for i in 7:
		var spark_time := fmod(time * (0.7 + i * 0.06) + i * 0.17, 1.0)
		var spark := Vector2(218.0 + i * 17.0, 407.0 + spark_time * 64.0)
		draw_line(spark, spark + Vector2(-4.0 + i, 10.0), Color(1.0, 0.62, 0.25, alpha * (1.0 - spark_time)), 2.0)

func _draw_control_spine(alpha: float) -> void:
	var center := Vector2(270, 350)
	var destruction := clampf(float(boss_phase) / 4.0, 0.0, 1.0) if encounter_state == "final" else 0.0
	var tower_color := Color("111a3c").lerp(Color("321027"), destruction)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-74, 255), center + Vector2(-43, -128),
		center + Vector2(0, -228), center + Vector2(43, -128), center + Vector2(74, 255)
	]), Color(tower_color, alpha * 0.93))
	for i in 4:
		var ring_radius := 72.0 + i * 28.0
		var ring_rotation := time * (0.18 + i * 0.04) * (1.0 if i % 2 else -1.0)
		draw_arc(center + Vector2(0, -92), ring_radius, ring_rotation, ring_rotation + PI * 1.48, 54, Color(0.25 + destruction * 0.65, 0.82 - destruction * 0.52, 1.0 - destruction * 0.55, alpha * (0.32 - i * 0.04)), 2.0)
	draw_line(center + Vector2(0, -208), center + Vector2(0, 235), Color(1.0, 0.86 - destruction * 0.55, 0.92, alpha * 0.58), 4.0)
	if destruction > 0.0:
		for i in 7:
			var crack_y := center.y - 145.0 + i * 52.0
			var crack_x := center.x + sin(float(i) * 2.3) * 34.0
			draw_line(Vector2(crack_x, crack_y), Vector2(crack_x + (-12.0 if i % 2 else 15.0), crack_y + 34.0), Color(1.0, 0.22, 0.38, alpha * destruction * 0.72), 2.0)

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
