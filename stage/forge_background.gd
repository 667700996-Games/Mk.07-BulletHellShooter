class_name ForgeBackground
extends Node2D

## Deterministic orbital-foundry environment for HELIOS FORGE. The open central
## lane stays dark while machinery, molten channels and solar motion live near
## the perimeter, preserving bullet and hitbox readability.

const VIEW_SIZE := Vector2(540.0, 960.0)
const DEFAULT_ROUTE_DURATION := 180.0
const BASE_SEED := 58193

var ambient_time := 0.0
var route_time := 0.0
var route_progress := 0.0
var route_duration := DEFAULT_ROUTE_DURATION
var escalation := 0.0
var encounter_state := "route"
var boss_phase := 0
var encounter_time := 0.0
var seed := BASE_SEED


func _process(delta: float) -> void:
	ambient_time += delta
	if encounter_state != "route":
		encounter_time += delta
	queue_redraw()


func configure(stage_data: StageData) -> void:
	route_duration = DEFAULT_ROUTE_DURATION
	seed = BASE_SEED
	if stage_data == null:
		return
	seed = BASE_SEED ^ stage_data.deterministic_seed_salt
	if stage_data.timeline != null and stage_data.timeline.boss_spawn_time > 0.0:
		route_duration = stage_data.timeline.boss_spawn_time


func set_route_context(value: float, encounter: String, phase: int = 0) -> void:
	var next_encounter := encounter if encounter in ["route", "midboss", "final"] else "route"
	if next_encounter != encounter_state or phase != boss_phase:
		encounter_time = 0.0
	route_time = maxf(value, 0.0)
	route_progress = clampf(route_time / route_duration, 0.0, 1.0)
	encounter_state = next_encounter
	boss_phase = maxi(phase, 0)


func set_escalation(value: float) -> void:
	escalation = clampf(value, 0.0, 1.0)


func _draw() -> void:
	_draw_vault()
	_draw_sun()
	_draw_orbital_rings()
	_draw_foundry_walls()
	_draw_route_landmarks()
	_draw_molten_conduits()
	_draw_slag(false)
	_draw_slag(true)
	_draw_encounter_pressure()
	_draw_readability_glaze()


func _draw_vault() -> void:
	var final_pressure := _final_pressure()
	for band in 32:
		var band_t := float(band) / 31.0
		var color := Color("050507").lerp(Color("17100d"), band_t)
		color = color.lerp(Color("2c1008"), escalation * 0.22 + final_pressure * 0.18)
		draw_rect(Rect2(0.0, band * 30.0, VIEW_SIZE.x, 31.0), color)
	for index in 46:
		var orbit := ambient_time * (1.2 + _unit_hash(index, 3) * 2.3)
		var x := fposmod(_unit_hash(index, 4) * 600.0 + orbit, 600.0) - 30.0
		var y := _unit_hash(index, 5) * 790.0
		var alpha := 0.05 + _unit_hash(index, 6) * 0.12
		draw_circle(Vector2(x, y), 0.6 + _unit_hash(index, 7) * 1.2, Color(1.0, 0.78, 0.38, alpha))


func _draw_sun() -> void:
	var center := Vector2(270.0, 110.0 - route_progress * 74.0)
	var pressure := maxf(escalation, _final_pressure())
	for halo in range(6, 0, -1):
		var radius := 58.0 + halo * 16.0 + sin(ambient_time * 0.42 + halo) * 3.0
		var alpha := (0.010 + float(7 - halo) * 0.007) * (1.0 + pressure * 0.5)
		draw_circle(center, radius, Color(1.0, 0.42 + halo * 0.035, 0.08, alpha))
	draw_circle(center, 54.0, Color(0.98, 0.73, 0.30, 0.20 + pressure * 0.05))
	draw_circle(center, 39.0, Color(1.0, 0.92, 0.68, 0.25))
	for flare in 12:
		var angle := TAU * float(flare) / 12.0 + ambient_time * (0.025 if flare % 2 else -0.018)
		var inner := 57.0
		var outer := 72.0 + _unit_hash(flare, 12) * 35.0
		draw_line(center + Vector2.from_angle(angle) * inner, center + Vector2.from_angle(angle) * outer, Color(1.0, 0.58, 0.16, 0.10), 2.0)


func _draw_orbital_rings() -> void:
	var center := Vector2(270.0, 146.0)
	for ring_index in 4:
		var radius_x := 122.0 + ring_index * 56.0
		var radius_y := 32.0 + ring_index * 14.0
		var rotation := ambient_time * (0.018 + ring_index * 0.007) * (-1.0 if ring_index % 2 else 1.0)
		draw_set_transform(center, rotation, Vector2(radius_x, radius_y))
		draw_arc(Vector2.ZERO, 1.0, PI * 0.04, PI * 0.96, 54, Color(0.94, 0.75, 0.38, 0.12), 0.018)
		draw_arc(Vector2.ZERO, 1.0, PI * 1.04, PI * 1.96, 54, Color(0.35, 0.22, 0.14, 0.42), 0.026)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_foundry_walls() -> void:
	var travel := route_time * 27.0 + ambient_time * 4.0
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var outer_x := 8.0 if side < 0.0 else 532.0
		var inner_x := 108.0 if side < 0.0 else 432.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(outer_x, 0.0), Vector2(inner_x, 0.0), Vector2(inner_x + side * 26.0, 960.0), Vector2(outer_x, 960.0)
		]), Color(0.025, 0.023, 0.025, 0.94))
		draw_line(Vector2(inner_x, 0.0), Vector2(inner_x + side * 26.0, 960.0), Color(0.76, 0.53, 0.25, 0.20), 3.0)
		for segment in 11:
			var y := fposmod(segment * 103.0 + travel, 1130.0) - 110.0
			var width := 62.0 + _unit_hash(segment, 20) * 22.0
			var rect_x := outer_x if side < 0.0 else outer_x - width
			draw_rect(Rect2(rect_x, y, width, 54.0), Color(0.09, 0.07, 0.055, 0.88))
			draw_line(Vector2(rect_x, y + 8.0), Vector2(rect_x + width, y + 8.0), Color(1.0, 0.48, 0.13, 0.13 + escalation * 0.07), 2.0)


func _draw_route_landmarks() -> void:
	var intake_alpha := _segment_alpha(0.02, 0.31)
	var crucible_alpha := _segment_alpha(0.24, 0.56)
	var lens_alpha := _segment_alpha(0.49, 0.79)
	var throne_alpha := smoothstep(0.71, 0.94, route_progress)
	if intake_alpha > 0.01:
		_draw_intake_gate(intake_alpha)
	if crucible_alpha > 0.01:
		_draw_crucible_array(crucible_alpha)
	if lens_alpha > 0.01:
		_draw_lens_corridor(lens_alpha)
	if throne_alpha > 0.01:
		_draw_eclipse_throne(throne_alpha)


func _draw_intake_gate(alpha: float) -> void:
	var center := Vector2(270.0, 448.0)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var jaw := PackedVector2Array([
			center + Vector2(side * 246.0, -132.0), center + Vector2(side * 146.0, -84.0),
			center + Vector2(side * 126.0, 96.0), center + Vector2(side * 236.0, 146.0)
		])
		draw_colored_polygon(jaw, Color(0.08, 0.06, 0.045, alpha * 0.82))
		draw_polyline(PackedVector2Array([jaw[0], jaw[1], jaw[2]]), Color(1.0, 0.66, 0.24, alpha * 0.28), 3.0)
	draw_arc(center, 134.0, PI, TAU, 48, Color(1.0, 0.84, 0.48, alpha * 0.20), 3.0)


func _draw_crucible_array(alpha: float) -> void:
	for index in 5:
		var x := 58.0 + index * 106.0
		var y := 390.0 + absf(index - 2) * 31.0
		var pulse := 0.5 + 0.5 * sin(ambient_time * 1.4 + index * 0.9)
		draw_circle(Vector2(x, y), 27.0, Color(0.055, 0.045, 0.04, alpha * 0.86))
		draw_arc(Vector2(x, y), 29.0 + pulse * 5.0, 0.0, TAU, 28, Color(1.0, 0.40, 0.10, alpha * (0.22 + pulse * 0.16)), 3.0)
		draw_line(Vector2(x, y + 28.0), Vector2(x, y + 188.0), Color(0.42, 0.25, 0.12, alpha * 0.22), 8.0)


func _draw_lens_corridor(alpha: float) -> void:
	for index in 7:
		var y := 268.0 + index * 91.0
		var half_width := 224.0 - index * 10.0
		for side_value in [-1.0, 1.0]:
			var side: float = side_value
			var center := Vector2(270.0 + side * half_width, y)
			draw_arc(center, 24.0, -PI * 0.64, PI * 0.64, 24, Color(0.94, 0.72, 0.34, alpha * 0.22), 4.0)
			draw_line(center, Vector2(270.0 + side * 128.0, y + 34.0), Color(0.18, 0.12, 0.08, alpha * 0.76), 7.0)


func _draw_eclipse_throne(alpha: float) -> void:
	var center := Vector2(270.0, 392.0)
	var pulse := 0.5 + 0.5 * sin(ambient_time * 0.86)
	draw_circle(center, 72.0 + pulse * 4.0, Color(0.005, 0.004, 0.006, alpha * 0.86))
	draw_arc(center, 88.0 + pulse * 7.0, -PI * 0.93, PI * 0.93, 54, Color(1.0, 0.58, 0.16, alpha * 0.23), 4.0)
	for spoke in 8:
		var angle := TAU * float(spoke) / 8.0 + ambient_time * 0.018
		draw_line(center + Vector2.from_angle(angle) * 96.0, center + Vector2.from_angle(angle) * 152.0, Color(0.61, 0.40, 0.19, alpha * 0.14), 5.0)


func _draw_molten_conduits() -> void:
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var points := PackedVector2Array()
		for segment in 10:
			var y := 70.0 + segment * 104.0
			var x := 73.0 if side < 0.0 else 467.0
			x += side * sin(segment * 1.7 + ambient_time * 0.31) * 10.0
			points.append(Vector2(x, y))
		draw_polyline(points, Color(1.0, 0.34, 0.08, 0.12 + escalation * 0.08), 5.0)
		for point_index in points.size():
			var pulse := 0.5 + 0.5 * sin(ambient_time * 2.1 - point_index * 0.78)
			draw_circle(points[point_index], 2.8 + pulse * 2.4, Color(1.0, 0.78, 0.30, 0.20 + pulse * 0.13))


func _draw_slag(foreground: bool) -> void:
	var count := 9 if foreground else 17
	var offset := 80 if foreground else 0
	var speed := 48.0 if foreground else 21.0
	for index in count:
		var key := index + offset
		var side := -1.0 if _unit_hash(key, 40) < 0.5 else 1.0
		var x := 270.0 + side * (124.0 + _unit_hash(key, 41) * 135.0)
		var y := fposmod(_unit_hash(key, 42) * 1120.0 + route_time * speed + ambient_time * 5.0, 1160.0) - 120.0
		var size := 7.0 + _unit_hash(key, 43) * (19.0 if foreground else 13.0)
		var angle := ambient_time * (0.03 + _unit_hash(key, 44) * 0.05) * side
		var direction := Vector2.from_angle(angle)
		var normal := direction.orthogonal()
		var center := Vector2(x, y)
		var points := PackedVector2Array([center + direction * size, center - direction * size * 0.72 + normal * size * 0.42, center - direction * size * 0.34 - normal * size * 0.48])
		draw_colored_polygon(points, Color(0.11, 0.075, 0.045, 0.78 if foreground else 0.46))
		draw_line(points[0], points[1], Color(1.0, 0.44, 0.12, 0.20), 1.2)


func _draw_encounter_pressure() -> void:
	if encounter_state == "midboss":
		var pulse := 0.5 + 0.5 * sin(encounter_time * 1.3)
		for side_value in [-1.0, 1.0]:
			var x := 270.0 + side_value * (151.0 + pulse * 9.0)
			draw_line(Vector2(x, 150.0), Vector2(x, 815.0), Color(1.0, 0.53, 0.14, 0.14 + pulse * 0.08), 4.0)
		draw_arc(Vector2(270.0, 440.0), 160.0 + pulse * 7.0, 0.0, TAU, 64, Color(1.0, 0.79, 0.36, 0.12), 3.0)
	elif encounter_state == "final":
		var pressure := _final_pressure()
		var eclipse := Vector2(270.0, 265.0)
		draw_circle(eclipse, 48.0 + pressure * 22.0, Color(0.0, 0.0, 0.0, 0.28 + pressure * 0.20))
		draw_arc(eclipse, 62.0 + pressure * 28.0, 0.0, TAU, 72, Color(1.0, 0.47, 0.12, 0.12 + pressure * 0.18), 5.0)


func _draw_readability_glaze() -> void:
	for band in 6:
		var rect := Rect2(88.0 + band * 18.0, 110.0 + band * 32.0, 364.0 - band * 36.0, 780.0 - band * 64.0)
		draw_rect(rect, Color(0.004, 0.005, 0.008, 0.018 + band * 0.003), true)


func _segment_alpha(start: float, finish: float) -> float:
	var fade_in := smoothstep(start, minf(finish, start + 0.08), route_progress)
	var fade_out := 1.0 - smoothstep(maxf(start, finish - 0.08), finish, route_progress)
	return fade_in * fade_out


func _final_pressure() -> float:
	if encounter_state != "final":
		return 0.0
	return clampf(0.24 + float(boss_phase) * 0.17, 0.0, 1.0)


func _unit_hash(index: int, salt: int) -> float:
	var value := sin(float(index * 137 + salt * 317 + seed) * 0.0174532925) * 43758.5453
	return fposmod(value, 1.0)
