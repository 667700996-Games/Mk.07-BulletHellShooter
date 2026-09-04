class_name TempestBackground
extends Node2D

## Procedural environment for the Tempest Arcology stage family.
##
## All composition is generated from route time, encounter state and fixed hashes.
## No random number generator or external texture is used, keeping replay captures
## visually stable while allowing ambient motion during gated boss encounters.

const VIEW_SIZE := Vector2(540.0, 960.0)
const DEFAULT_ROUTE_DURATION := 180.0
const BASE_SEED := 46021

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
	if stage_data.timeline == null:
		return
	var configured_duration := float(stage_data.timeline.boss_spawn_time)
	if is_finite(configured_duration) and configured_duration > 0.0:
		route_duration = configured_duration

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
	_draw_storm_vault()
	_draw_distant_cloud_strata()
	_draw_anomaly_core()
	_draw_arcology_crown()
	_draw_route_landmarks()
	_draw_floating_ruins(false)
	_draw_energy_conduits()
	_draw_foreground_clouds()
	_draw_floating_ruins(true)
	_draw_lightning()
	_draw_readability_glaze()

func _draw_storm_vault() -> void:
	var final_pressure := _final_pressure()
	for band in 32:
		var band_t := float(band) / 31.0
		var top := Color("06091e").lerp(Color("171039"), band_t)
		var energized := Color("120a2d").lerp(Color("071e39"), band_t)
		var color := top.lerp(energized, 0.16 + escalation * 0.28)
		color = color.lerp(Color("2a092f"), final_pressure * 0.14)
		draw_rect(Rect2(0.0, band * 30.0, VIEW_SIZE.x, 31.0), color)
	# Sparse charged dust establishes scale without competing with bullets.
	for index in 42:
		var drift := ambient_time * (2.0 + _unit_hash(index, 2) * 4.0)
		var x := fposmod(_unit_hash(index, 3) * 620.0 + drift, 620.0) - 40.0
		var y := _unit_hash(index, 4) * 760.0
		var brightness := 0.06 + _unit_hash(index, 5) * 0.09
		var color := Color(0.38, 0.86, 1.0, brightness)
		draw_circle(Vector2(x, y), 0.7 + _unit_hash(index, 6), color)

func _draw_distant_cloud_strata() -> void:
	for layer in 3:
		var layer_speed := 5.0 + layer * 4.0
		var y_base := 82.0 + layer * 155.0
		var layer_color: Color = [Color(0.17, 0.10, 0.31, 0.22), Color(0.07, 0.20, 0.30, 0.18), Color(0.20, 0.08, 0.27, 0.14)][layer]
		for index in 8:
			var radius := 52.0 + _unit_hash(index + layer * 11, 8) * 58.0
			var x := fposmod(index * 91.0 + layer * 37.0 - ambient_time * layer_speed, 730.0) - 95.0
			var y := y_base + sin(ambient_time * 0.09 + index * 1.7 + layer) * 17.0
			draw_circle(Vector2(x, y), radius, layer_color)
	# Thin cyan storm shelf makes the upper horizon distinct from the city stage.
	var shelf_y := 268.0 + sin(ambient_time * 0.08) * 9.0
	var shelf := PackedVector2Array([Vector2(-30, shelf_y + 34), Vector2(80, shelf_y - 7), Vector2(190, shelf_y + 15), Vector2(320, shelf_y - 20), Vector2(445, shelf_y + 8), Vector2(570, shelf_y - 13), Vector2(570, shelf_y + 77), Vector2(-30, shelf_y + 77)])
	draw_colored_polygon(shelf, Color(0.08, 0.27, 0.39, 0.11 + escalation * 0.025))
	draw_polyline(PackedVector2Array([Vector2(-10, shelf_y + 24), Vector2(100, shelf_y - 2), Vector2(225, shelf_y + 12), Vector2(350, shelf_y - 13), Vector2(550, shelf_y + 14)]), Color(0.30, 0.91, 1.0, 0.10), 2.0)

func _draw_anomaly_core() -> void:
	var pressure := _final_pressure()
	var center := Vector2(270.0, 174.0 + sin(ambient_time * 0.19) * 3.0)
	var core_radius := 27.0 + route_progress * 8.0 + pressure * 25.0
	# Broad, faint corona. The bright core stays above the usual combat focus.
	for ring in range(5, 0, -1):
		var corona_radius := core_radius + ring * (12.0 + pressure * 4.0)
		draw_circle(center, corona_radius, Color(0.31, 0.12, 0.60, (0.010 + pressure * 0.008) * ring))
	var core_color := Color("75efff").lerp(Color("e378ff"), pressure)
	draw_circle(center, core_radius, Color(core_color, 0.075 + pressure * 0.035))
	draw_arc(center, core_radius, 0.0, TAU, 64, Color(core_color, 0.58), 2.0)
	draw_circle(center, 6.0 + pressure * 5.0, Color(0.84, 0.98, 1.0, 0.70))
	for ring in 4:
		var radius := core_radius + 18.0 + ring * 19.0
		var direction := -1.0 if ring % 2 == 0 else 1.0
		var rotation := ambient_time * (0.10 + ring * 0.025) * direction
		var arc_length := PI * (0.84 + ring * 0.09)
		draw_arc(center, radius, rotation, rotation + arc_length, 42, Color(0.40, 0.90 - ring * 0.08, 1.0, 0.25 - ring * 0.035 + pressure * 0.07), 2.0)
	if pressure > 0.08:
		_draw_anomaly_rifts(center, core_radius, pressure)

func _draw_anomaly_rifts(center: Vector2, radius: float, pressure: float) -> void:
	var spoke_count := mini(5 + boss_phase, 11)
	for index in spoke_count:
		var angle := float(index) * TAU / float(spoke_count) + sin(index * 2.1) * 0.16
		var inner := center + Vector2.from_angle(angle) * (radius + 5.0)
		var elbow := center + Vector2.from_angle(angle + sin(index * 1.8) * 0.12) * (radius + 29.0 + index * 3.0)
		var outer := center + Vector2.from_angle(angle - 0.09) * (radius + 54.0 + pressure * 34.0)
		var points := PackedVector2Array([inner, elbow, outer])
		draw_polyline(points, Color(0.85, 0.44, 1.0, pressure * 0.28), 1.4)

func _draw_arcology_crown() -> void:
	var horizon := 342.0
	var final_pressure := _final_pressure()
	# Shattered megastructure ring surrounding the anomaly.
	for segment in 14:
		if segment in [3, 4, 9]:
			continue
		var angle_a := PI + float(segment) / 14.0 * PI
		var angle_b := PI + float(segment + 1) / 14.0 * PI
		var center := Vector2(270.0, horizon + 118.0)
		var radius_a := Vector2(230.0, 202.0)
		var lift := final_pressure * sin(segment * 2.35) * 20.0
		var a := center + Vector2(cos(angle_a) * radius_a.x, sin(angle_a) * radius_a.y + lift)
		var b := center + Vector2(cos(angle_b) * radius_a.x, sin(angle_b) * radius_a.y + lift)
		draw_line(a, b, Color(0.12, 0.18, 0.34, 0.82), 13.0)
		draw_line(a, b, Color(0.32, 0.72, 0.92, 0.15 + final_pressure * 0.08), 2.0)
	# Crown pylons live at the sides, leaving a subdued central lane.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for index in 4:
			var x: float = 270.0 + side * (112.0 + index * 54.0)
			var height := 154.0 - index * 17.0
			var tilt: float = side * (13.0 + index * 3.0)
			var base_y := horizon + 204.0
			var pylon := PackedVector2Array([Vector2(x - 16, base_y), Vector2(x - 9 + tilt, base_y - height), Vector2(x + 10 + tilt, base_y - height - 24), Vector2(x + 18, base_y)])
			draw_colored_polygon(pylon, Color(0.025, 0.055, 0.13, 0.88))
			draw_line(Vector2(x + tilt, base_y - height + 4), Vector2(x + 2, base_y - 10), Color(0.25, 0.79, 0.96, 0.13), 2.0)

func _draw_route_landmarks() -> void:
	var gate_alpha := _segment_alpha(0.02, 0.29)
	var choir_alpha := _segment_alpha(0.22, 0.53)
	var fracture_alpha := _segment_alpha(0.47, 0.78)
	var ascent_alpha := smoothstep(0.70, 0.91, route_progress)
	if gate_alpha > 0.01:
		_draw_wind_gate(gate_alpha)
	if choir_alpha > 0.01:
		_draw_resonator_choir(choir_alpha)
	if fracture_alpha > 0.01:
		_draw_fracture_field(fracture_alpha)
	if ascent_alpha > 0.01:
		_draw_anomaly_elevator(ascent_alpha)
	if encounter_state == "midboss":
		_draw_midboss_lock()

func _draw_wind_gate(alpha: float) -> void:
	var center := Vector2(270, 438 + sin(ambient_time * 0.27) * 7.0)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var x: float = center.x + side * 190.0
		var wing := PackedVector2Array([Vector2(x, center.y - 144), Vector2(x - side * 42, center.y - 94), Vector2(x - side * 61, center.y + 158), Vector2(x + side * 19, center.y + 116)])
		draw_colored_polygon(wing, Color(0.04, 0.07, 0.16, alpha * 0.86))
		draw_polyline(PackedVector2Array([wing[0], wing[1], wing[2]]), Color(0.28, 0.88, 1.0, alpha * 0.32), 2.0)
	draw_arc(center, 190.0, PI, TAU, 56, Color(0.52, 0.35, 1.0, alpha * 0.34), 4.0)
	draw_arc(center, 155.0, PI, TAU, 56, Color(0.29, 0.90, 1.0, alpha * 0.20), 2.0)

func _draw_resonator_choir(alpha: float) -> void:
	for index in 5:
		var x := 62.0 + index * 104.0
		var y := 355.0 + absf(index - 2) * 33.0 + sin(ambient_time * 0.30 + index) * 5.0
		var height := 196.0 - absf(index - 2) * 19.0
		var shard := PackedVector2Array([Vector2(x - 19, y + height), Vector2(x - 11, y + 25), Vector2(x, y), Vector2(x + 13, y + 29), Vector2(x + 22, y + height)])
		draw_colored_polygon(shard, Color(0.035, 0.055, 0.13, alpha * 0.82))
		draw_line(Vector2(x, y + 32), Vector2(x, y + height - 12), Color(0.66, 0.35, 1.0, alpha * 0.23), 3.0)
		var pulse_y := y + 55.0 + fposmod(route_time * 17.0 + index * 41.0, maxf(30.0, height - 80.0))
		draw_circle(Vector2(x, pulse_y), 3.0, Color(0.44, 0.94, 1.0, alpha * 0.48))

func _draw_fracture_field(alpha: float) -> void:
	for index in 16:
		var x := 28.0 + _unit_hash(index, 31) * 484.0
		var y := 300.0 + _unit_hash(index, 32) * 350.0
		var size := 10.0 + _unit_hash(index, 33) * 29.0
		var angle := ambient_time * (0.025 + _unit_hash(index, 34) * 0.04) * (-1.0 if index % 2 else 1.0)
		var direction := Vector2.from_angle(angle)
		var normal := direction.orthogonal()
		var shard := PackedVector2Array([Vector2(x, y) + direction * size, Vector2(x, y) - direction * size * 0.72 + normal * size * 0.24, Vector2(x, y) - direction * size * 0.37 - normal * size * 0.18])
		draw_colored_polygon(shard, Color(0.08, 0.08, 0.19, alpha * 0.63))
		draw_line(shard[0], shard[1], Color(0.39, 0.82, 1.0, alpha * 0.17), 1.0)

func _draw_anomaly_elevator(alpha: float) -> void:
	var center_x := 270.0
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var x: float = center_x + side * 214.0
		draw_line(Vector2(x, 230), Vector2(center_x + side * 132.0, 885), Color(0.08, 0.12, 0.25, alpha * 0.86), 18.0)
		draw_line(Vector2(x, 230), Vector2(center_x + side * 132.0, 885), Color(0.31, 0.86, 1.0, alpha * 0.19), 2.0)
	for rung in 10:
		var y := 250.0 + rung * 66.0
		var width := lerpf(418.0, 266.0, float(rung) / 9.0)
		draw_line(Vector2(center_x - width * 0.5, y), Vector2(center_x + width * 0.5, y), Color(0.34, 0.22, 0.58, alpha * 0.12), 2.0)

func _draw_midboss_lock() -> void:
	var pulse := 0.5 + 0.5 * sin(encounter_time * 1.45)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var x: float = 270.0 + side * (145.0 + pulse * 9.0)
		draw_line(Vector2(x, 165), Vector2(x, 795), Color(0.52, 0.35, 1.0, 0.18), 3.0)
		for node in 5:
			var y := 225.0 + node * 124.0
			draw_arc(Vector2(x, y), 8.0 + pulse * 3.0, 0, TAU, 20, Color(0.40, 0.92, 1.0, 0.30), 2.0)
	draw_arc(Vector2(270, 470), 153.0 + pulse * 8.0, 0.0, TAU, 64, Color(0.65, 0.32, 1.0, 0.13), 2.0)

func _draw_floating_ruins(foreground: bool) -> void:
	var count := 10 if foreground else 18
	var layer_offset := 70 if foreground else 0
	var speed := 42.0 if foreground else 18.0
	var pressure := _final_pressure()
	for index in count:
		var key := index + layer_offset
		var lane := -1.0 if _unit_hash(key, 42) < 0.5 else 1.0
		var edge_distance := (38.0 + _unit_hash(key, 43) * (104.0 if foreground else 160.0))
		var x := 270.0 + lane * (270.0 - edge_distance)
		var travel := route_time * speed + ambient_time * (8.0 if foreground else 3.0)
		var y := fposmod(_unit_hash(key, 44) * 1150.0 + travel, 1160.0) - 130.0
		var base_size := 17.0 + _unit_hash(key, 45) * (42.0 if foreground else 27.0)
		var breakup := pressure * sin(key * 1.91) * 18.0
		x += breakup
		var angle := _unit_hash(key, 46) * TAU + ambient_time * (0.012 + _unit_hash(key, 47) * 0.025) * lane
		_draw_ruin(Vector2(x, y), base_size, angle, foreground, pressure, key)

func _draw_ruin(center: Vector2, size: float, angle: float, foreground: bool, pressure: float, key: int) -> void:
	var direction := Vector2.from_angle(angle)
	var normal := direction.orthogonal()
	var points := PackedVector2Array([
		center + direction * size,
		center + normal * size * 0.58 - direction * size * 0.23,
		center - direction * size * 0.86 + normal * size * 0.18,
		center - normal * size * 0.45 - direction * size * 0.28
	])
	var alpha := 0.88 if foreground else 0.57
	var body := Color(0.018, 0.027, 0.075, alpha)
	draw_colored_polygon(points, body)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2]]), Color(0.25, 0.62, 0.84, 0.13 + pressure * 0.08), 1.5)
	if key % 3 == 0:
		var conduit_a := center - direction * size * 0.48
		var conduit_b := center + direction * size * 0.54
		draw_line(conduit_a, conduit_b, Color(0.60, 0.30, 1.0, 0.15 + pressure * 0.13), 2.0)

func _draw_energy_conduits() -> void:
	var pressure := _final_pressure()
	var conduit_color := Color("42e7ff").lerp(Color("d55cff"), pressure)
	for side in [-1.0, 1.0]:
		var points := PackedVector2Array()
		for segment in 9:
			var y := 90.0 + segment * 110.0
			var x := 24.0 if side < 0.0 else 516.0
			x += side * sin(segment * 1.63 + ambient_time * 0.24) * 12.0
			points.append(Vector2(x, y))
		draw_polyline(points, Color(conduit_color, 0.14 + escalation * 0.09), 3.0)
		for node in 8:
			var position := points[node]
			var pulse := 0.5 + 0.5 * sin(ambient_time * 1.8 - node * 0.75 + side)
			draw_circle(position, 3.0 + pulse * 2.0, Color(conduit_color, 0.24 + pulse * 0.17))
	# A few low-alpha links cross the lower arena, never the player focus area at full brightness.
	for link in 3:
		var y := 690.0 + link * 104.0
		var energy_alpha := 0.035 + escalation * 0.025
		draw_line(Vector2(18, y), Vector2(522, y + sin(link * 2.0) * 28.0), Color(conduit_color, energy_alpha), 1.0)

func _draw_foreground_clouds() -> void:
	var scroll := route_time * 31.0 + ambient_time * 7.0
	for index in 12:
		var y := fposmod(index * 107.0 + scroll, 1160.0) - 120.0
		var side := -1.0 if index % 2 == 0 else 1.0
		var x := 270.0 + side * (215.0 + sin(index * 1.3) * 42.0)
		var radius := 62.0 + (index % 4) * 14.0
		var color := Color(0.06, 0.10, 0.22, 0.24)
		draw_circle(Vector2(x, y), radius, color)
		draw_circle(Vector2(x - side * 48.0, y + 18.0), radius * 0.72, Color(color, 0.18))

func _draw_lightning() -> void:
	var pressure := maxf(escalation, _final_pressure())
	var interval := lerpf(7.4, 3.8, pressure)
	var lightning_clock := ambient_time + route_time * 0.06
	var cycle := int(floor(lightning_clock / interval))
	var local_time := fposmod(lightning_clock, interval)
	var active_length := 0.10 + pressure * 0.055
	if local_time > active_length:
		return
	# Short, restrained flashes avoid a full-screen strobe while preserving storm impact.
	var alpha := (1.0 - local_time / active_length) * (0.28 + pressure * 0.18)
	var side := -1.0 if _unit_hash(cycle, 70) < 0.5 else 1.0
	var start := Vector2(270.0 + side * (145.0 + _unit_hash(cycle, 71) * 100.0), -15.0)
	var points := PackedVector2Array([start])
	var current := start
	for segment in 7:
		current += Vector2(side * (_unit_hash(cycle * 11 + segment, 72) - 0.5) * 55.0, 48.0 + _unit_hash(segment, 73) * 34.0)
		points.append(current)
	draw_polyline(points, Color(0.57, 0.93, 1.0, alpha * 0.34), 7.0)
	draw_polyline(points, Color(0.87, 0.98, 1.0, alpha), 1.6)
	if cycle % 3 == 0:
		var branch_start := points[3]
		var branch := PackedVector2Array([branch_start, branch_start + Vector2(-side * 31.0, 35.0), branch_start + Vector2(-side * 53.0, 68.0)])
		draw_polyline(branch, Color(0.70, 0.53, 1.0, alpha * 0.56), 1.2)

func _draw_readability_glaze() -> void:
	# A constant translucent well keeps player, enemy silhouettes and bullets legible.
	var center := Vector2(270.0, 535.0)
	for ring in range(5, 0, -1):
		var radius := Vector2(76.0 + ring * 39.0, 135.0 + ring * 61.0)
		var alpha := 0.006 + float(6 - ring) * 0.004
		draw_set_transform(center, 0.0, radius)
		draw_circle(Vector2.ZERO, 1.0, Color(0.008, 0.014, 0.046, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _segment_alpha(start: float, finish: float) -> float:
	var fade_in := smoothstep(start, minf(finish, start + 0.08), route_progress)
	var fade_out := 1.0 - smoothstep(maxf(start, finish - 0.08), finish, route_progress)
	return fade_in * fade_out

func _final_pressure() -> float:
	if encounter_state != "final":
		return 0.0
	return clampf(0.24 + float(boss_phase) * 0.17, 0.0, 1.0)

func _unit_hash(index: int, salt: int) -> float:
	var value := sin(float(index * 127 + salt * 311 + seed) * 0.0174532925) * 43758.5453
	return fposmod(value, 1.0)
