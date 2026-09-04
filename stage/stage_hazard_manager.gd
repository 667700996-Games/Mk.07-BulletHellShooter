class_name StageHazardManager
extends Node2D

signal hazard_warning(hazard_id: String, kind: String)

const PLAY_RECT := Rect2(22.0, 70.0, 496.0, 850.0)
const MAX_ACTIVE_OBJECTS := 96

var events: Array[StageHazardData] = []
var next_trigger_times: Array[float] = []
var active_lanes: Array[Dictionary] = []
var active_debris: Array[Dictionary] = []
var active_rings: Array[Dictionary] = []
var active_flares: Array[Dictionary] = []
var active_molten_fragments: Array[Dictionary] = []
var active_coronas: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var trigger_serial := 0

func configure(hazard_events: Array[StageHazardData], seed_value: int) -> void:
	events.clear()
	next_trigger_times.clear()
	for event in hazard_events:
		if event == null:
			continue
		events.append(event)
		next_trigger_times.append(event.start_time)
	rng.seed = maxi(1, seed_value)
	trigger_serial = 0
	clear_all()

func update_hazards(delta: float, route_time: float, player_position: Vector2, vulnerable: bool) -> bool:
	_trigger_due_events(route_time)
	var hit := false
	for index in range(active_lanes.size() - 1, -1, -1):
		var lane := active_lanes[index]
		lane.warning_left = maxf(0.0, float(lane.warning_left) - delta)
		if is_zero_approx(float(lane.warning_left)):
			lane.active_left = float(lane.active_left) - delta
			if vulnerable and float(lane.active_left) > 0.0 and (lane.rect as Rect2).has_point(player_position):
				hit = true
		active_lanes[index] = lane
		if float(lane.active_left) <= 0.0:
			active_lanes.remove_at(index)
	for index in range(active_debris.size() - 1, -1, -1):
		var debris := active_debris[index]
		debris.warning_left = maxf(0.0, float(debris.warning_left) - delta)
		if is_zero_approx(float(debris.warning_left)):
			debris.position = (debris.position as Vector2) + (debris.velocity as Vector2) * delta
			debris.life = float(debris.life) - delta
			if vulnerable and (debris.position as Vector2).distance_squared_to(player_position) <= pow(float(debris.radius) + 5.0, 2.0):
				hit = true
		active_debris[index] = debris
		if float(debris.life) <= 0.0 or float((debris.position as Vector2).y) > PLAY_RECT.end.y + 90.0:
			active_debris.remove_at(index)
	for index in range(active_rings.size() - 1, -1, -1):
		var ring := active_rings[index]
		ring.warning_left = maxf(0.0, float(ring.warning_left) - delta)
		if is_zero_approx(float(ring.warning_left)):
			ring.active_left = float(ring.active_left) - delta
			var progress := 1.0 - clampf(float(ring.active_left) / maxf(0.001, float(ring.active_time)), 0.0, 1.0)
			ring.radius = lerpf(24.0, float(ring.max_radius), progress)
			var distance := (ring.center as Vector2).distance_to(player_position)
			if vulnerable and absf(distance - float(ring.radius)) <= float(ring.width) * 0.5 + 5.0:
				hit = true
		active_rings[index] = ring
		if float(ring.active_left) <= 0.0:
			active_rings.remove_at(index)
	for index in range(active_flares.size() - 1, -1, -1):
		var flare := active_flares[index]
		flare.warning_left = maxf(0.0, float(flare.warning_left) - delta)
		if is_zero_approx(float(flare.warning_left)):
			flare.active_left = float(flare.active_left) - delta
			var progress := 1.0 - clampf(float(flare.active_left) / maxf(0.001, float(flare.active_time)), 0.0, 1.0)
			var center_y := lerpf(float(flare.from_y), float(flare.to_y), progress)
			flare.rect = Rect2(PLAY_RECT.position.x, center_y - float(flare.width) * 0.5, PLAY_RECT.size.x, float(flare.width))
			if vulnerable and float(flare.active_left) > 0.0 and (flare.rect as Rect2).has_point(player_position):
				hit = true
		active_flares[index] = flare
		if float(flare.active_left) <= 0.0:
			active_flares.remove_at(index)
	for index in range(active_molten_fragments.size() - 1, -1, -1):
		var fragment := active_molten_fragments[index]
		fragment.warning_left = maxf(0.0, float(fragment.warning_left) - delta)
		if is_zero_approx(float(fragment.warning_left)):
			fragment.velocity = (fragment.velocity as Vector2) + (fragment.acceleration as Vector2) * delta
			fragment.position = (fragment.position as Vector2) + (fragment.velocity as Vector2) * delta
			fragment.life = float(fragment.life) - delta
			fragment.spin = float(fragment.spin) + float(fragment.spin_speed) * delta
			if vulnerable and (fragment.position as Vector2).distance_squared_to(player_position) <= pow(float(fragment.radius) + 5.0, 2.0):
				hit = true
		active_molten_fragments[index] = fragment
		if float(fragment.life) <= 0.0 or float((fragment.position as Vector2).y) > PLAY_RECT.end.y + 100.0:
			active_molten_fragments.remove_at(index)
	for index in range(active_coronas.size() - 1, -1, -1):
		var corona := active_coronas[index]
		corona.warning_left = maxf(0.0, float(corona.warning_left) - delta)
		if is_zero_approx(float(corona.warning_left)):
			corona.active_left = float(corona.active_left) - delta
			var progress := 1.0 - clampf(float(corona.active_left) / maxf(0.001, float(corona.active_time)), 0.0, 1.0)
			corona.radius = lerpf(float(corona.max_radius), float(corona.min_radius), progress)
			corona.rotation = float(corona.rotation) + delta * float(corona.rotation_speed)
			var distance := (corona.center as Vector2).distance_to(player_position)
			if vulnerable and absf(distance - float(corona.radius)) <= float(corona.width) * 0.5 + 5.0:
				hit = true
		active_coronas[index] = corona
		if float(corona.active_left) <= 0.0:
			active_coronas.remove_at(index)
	queue_redraw()
	return hit

func clear_all() -> void:
	active_lanes.clear()
	active_debris.clear()
	active_rings.clear()
	active_flares.clear()
	active_molten_fragments.clear()
	active_coronas.clear()
	queue_redraw()

func active_count() -> int:
	return (active_lanes.size() + active_debris.size() + active_rings.size()
		+ active_flares.size() + active_molten_fragments.size() + active_coronas.size())

func _trigger_due_events(route_time: float) -> void:
	for event_index in events.size():
		var event := events[event_index]
		var guard := 0
		while next_trigger_times[event_index] <= route_time and next_trigger_times[event_index] <= event.end_time and guard < 32:
			_spawn_event(event)
			next_trigger_times[event_index] += event.interval
			guard += 1

func _spawn_event(event: StageHazardData) -> void:
	if active_count() >= MAX_ACTIVE_OBJECTS:
		return
	trigger_serial += 1
	hazard_warning.emit(event.hazard_id, event.kind)
	match event.kind:
		"lightning_lane":
			_spawn_lanes(event)
		"debris_field":
			_spawn_debris(event)
		"shock_ring":
			_spawn_ring(event)
		"solar_flare":
			_spawn_solar_flare(event)
		"molten_fragments":
			_spawn_molten_fragments(event)
		"corona_wave":
			_spawn_corona_wave(event)

func _spawn_lanes(event: StageHazardData) -> void:
	var vertical := event.orientation == "vertical" or (event.orientation == "alternate" and trigger_serial % 2 == 0)
	var count := mini(event.lane_count, 4)
	var axis_start := PLAY_RECT.position.x if vertical else PLAY_RECT.position.y
	var axis_size := PLAY_RECT.size.x if vertical else PLAY_RECT.size.y
	var offset := rng.randf_range(0.12, 0.88) * axis_size
	for lane_index in count:
		var stagger := (float(lane_index) - float(count - 1) * 0.5) * maxf(event.width * 1.8, axis_size / float(count + 1))
		var center := clampf(axis_start + offset + stagger, axis_start + event.width * 0.5, axis_start + axis_size - event.width * 0.5)
		var rect := Rect2(center - event.width * 0.5, PLAY_RECT.position.y, event.width, PLAY_RECT.size.y) if vertical else Rect2(PLAY_RECT.position.x, center - event.width * 0.5, PLAY_RECT.size.x, event.width)
		active_lanes.append({
			"rect": rect, "warning_left": event.warning_time, "active_left": event.active_time,
			"color": event.color, "vertical": vertical, "hazard_id": event.hazard_id
		})

func _spawn_debris(event: StageHazardData) -> void:
	for debris_index in mini(event.burst_count, 12):
		if active_count() >= MAX_ACTIVE_OBJECTS:
			break
		var radius := rng.randf_range(event.width * 0.18, event.width * 0.34)
		var x := rng.randf_range(PLAY_RECT.position.x + radius, PLAY_RECT.end.x - radius)
		var drift := rng.randf_range(-65.0, 65.0)
		active_debris.append({
			"position": Vector2(x, PLAY_RECT.position.y - 30.0 - debris_index * radius * 1.4),
			"velocity": Vector2(drift, event.speed * rng.randf_range(0.84, 1.16)),
			"radius": radius, "warning_left": event.warning_time + debris_index * 0.08,
			"life": PLAY_RECT.size.y / event.speed + 2.0, "color": event.color,
			"hazard_id": event.hazard_id
		})

func _spawn_ring(event: StageHazardData) -> void:
	var center := Vector2(
		rng.randf_range(PLAY_RECT.position.x + 130.0, PLAY_RECT.end.x - 130.0),
		rng.randf_range(PLAY_RECT.position.y + 180.0, PLAY_RECT.position.y + 420.0)
	)
	active_rings.append({
		"center": center, "radius": 24.0, "max_radius": event.max_radius,
		"width": event.width, "warning_left": event.warning_time,
		"active_left": event.active_time, "active_time": event.active_time,
		"color": event.color, "hazard_id": event.hazard_id
	})

func _spawn_solar_flare(event: StageHazardData) -> void:
	var downward := trigger_serial % 2 == 1
	var half_width := event.width * 0.5
	var from_y := PLAY_RECT.position.y + half_width if downward else PLAY_RECT.end.y - half_width
	var to_y := PLAY_RECT.end.y - half_width if downward else PLAY_RECT.position.y + half_width
	active_flares.append({
		"rect": Rect2(PLAY_RECT.position.x, from_y - half_width, PLAY_RECT.size.x, event.width),
		"from_y": from_y, "to_y": to_y, "width": event.width,
		"warning_left": event.warning_time, "active_left": event.active_time,
		"active_time": event.active_time, "color": event.color,
		"downward": downward, "hazard_id": event.hazard_id
	})

func _spawn_molten_fragments(event: StageHazardData) -> void:
	for fragment_index in mini(event.burst_count, 12):
		if active_count() >= MAX_ACTIVE_OBJECTS:
			break
		var radius := rng.randf_range(event.width * 0.16, event.width * 0.30)
		var x := rng.randf_range(PLAY_RECT.position.x + radius, PLAY_RECT.end.x - radius)
		var drift := rng.randf_range(-92.0, 92.0)
		active_molten_fragments.append({
			"position": Vector2(x, PLAY_RECT.position.y - 34.0 - fragment_index * radius * 1.55),
			"velocity": Vector2(drift, event.speed * rng.randf_range(0.62, 0.82)),
			"acceleration": Vector2(0.0, event.speed * rng.randf_range(0.62, 0.88)),
			"radius": radius, "warning_left": event.warning_time + fragment_index * 0.08,
			"life": PLAY_RECT.size.y / event.speed + 2.0,
			"spin": rng.randf_range(0.0, TAU), "spin_speed": rng.randf_range(-4.2, 4.2),
			"color": event.color, "hazard_id": event.hazard_id
		})

func _spawn_corona_wave(event: StageHazardData) -> void:
	var center := Vector2(
		rng.randf_range(PLAY_RECT.position.x + 145.0, PLAY_RECT.end.x - 145.0),
		rng.randf_range(PLAY_RECT.position.y + 225.0, PLAY_RECT.position.y + 390.0)
	)
	active_coronas.append({
		"center": center, "radius": event.max_radius, "max_radius": event.max_radius,
		"min_radius": 34.0, "width": event.width, "warning_left": event.warning_time,
		"active_left": event.active_time, "active_time": event.active_time,
		"rotation": rng.randf_range(0.0, TAU),
		"rotation_speed": rng.randf_range(0.55, 0.82) * (-1.0 if trigger_serial % 2 else 1.0),
		"color": event.color, "hazard_id": event.hazard_id
	})

func _draw() -> void:
	for lane in active_lanes:
		var rect: Rect2 = lane.rect
		var color: Color = lane.color
		var warning_left := float(lane.warning_left)
		if warning_left > 0.0:
			var pulse := 0.12 + absf(sin(warning_left * 18.0)) * 0.16
			draw_rect(rect, Color(color, pulse), true)
			draw_rect(rect, Color(color, 0.72), false, 2.0)
		else:
			draw_rect(rect, Color(color, 0.30), true)
			draw_rect(rect.grow(3.0), Color(Color.WHITE, 0.80), false, 3.0)
			var center := rect.get_center()
			if bool(lane.vertical):
				draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), Color(Color.WHITE, 0.88), 3.0)
			else:
				draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), Color(Color.WHITE, 0.88), 3.0)
	for debris in active_debris:
		var debris_position: Vector2 = debris.position
		var radius := float(debris.radius)
		var color: Color = debris.color
		if float(debris.warning_left) > 0.0:
			draw_line(Vector2(debris_position.x, PLAY_RECT.position.y), Vector2(debris_position.x, PLAY_RECT.position.y + 42.0), Color(color, 0.68), 2.0)
			draw_arc(Vector2(debris_position.x, PLAY_RECT.position.y + 28.0), radius + 5.0, 0.0, TAU, 20, Color(color, 0.8), 2.0)
		else:
			draw_line(debris_position - (debris.velocity as Vector2).normalized() * radius * 3.0, debris_position, Color(color, 0.42), radius * 0.65)
			draw_circle(debris_position, radius + 4.0, Color(color, 0.20))
			draw_circle(debris_position, radius, Color(color, 0.82))
			draw_circle(debris_position - Vector2(radius * 0.22, radius * 0.24), radius * 0.32, Color(Color.WHITE, 0.62))
	for ring in active_rings:
		var center: Vector2 = ring.center
		var radius := float(ring.radius)
		var color: Color = ring.color
		if float(ring.warning_left) > 0.0:
			draw_circle(center, 22.0, Color(color, 0.12))
			draw_arc(center, 28.0 + absf(sin(float(ring.warning_left) * 12.0)) * 8.0, 0.0, TAU, 36, Color(color, 0.78), 2.0)
		else:
			draw_arc(center, radius, 0.0, TAU, 72, Color(color, 0.88), float(ring.width))
			draw_arc(center, radius, 0.0, TAU, 72, Color(Color.WHITE, 0.72), 2.0)
	for flare in active_flares:
		var rect: Rect2 = flare.rect
		var color: Color = flare.color
		if float(flare.warning_left) > 0.0:
			var start_y := float(flare.from_y)
			var end_y := float(flare.to_y)
			var pulse := 0.38 + absf(sin(float(flare.warning_left) * 14.0)) * 0.34
			draw_line(Vector2(PLAY_RECT.position.x, start_y), Vector2(PLAY_RECT.end.x, start_y), Color(color, pulse), 4.0)
			draw_line(Vector2(PLAY_RECT.get_center().x, start_y), Vector2(PLAY_RECT.get_center().x, end_y), Color(color, 0.14), 2.0)
			for marker in 5:
				var x := PLAY_RECT.position.x + (float(marker) + 0.5) * PLAY_RECT.size.x / 5.0
				var direction := 1.0 if bool(flare.downward) else -1.0
				draw_line(Vector2(x - 7.0, start_y + direction * 11.0), Vector2(x, start_y + direction * 18.0), Color(color, 0.72), 2.0)
				draw_line(Vector2(x + 7.0, start_y + direction * 11.0), Vector2(x, start_y + direction * 18.0), Color(color, 0.72), 2.0)
		else:
			draw_rect(rect.grow(8.0), Color(color, 0.12), true)
			draw_rect(rect, Color(color, 0.42), true)
			draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Color(Color.WHITE, 0.88), 3.0)
	for fragment in active_molten_fragments:
		var fragment_position: Vector2 = fragment.position
		var radius := float(fragment.radius)
		var color: Color = fragment.color
		if float(fragment.warning_left) > 0.0:
			draw_line(Vector2(fragment_position.x, PLAY_RECT.position.y), Vector2(fragment_position.x, PLAY_RECT.position.y + 54.0), Color(color, 0.76), 2.0)
			draw_arc(Vector2(fragment_position.x, PLAY_RECT.position.y + 31.0), radius + 7.0, 0.0, TAU, 20, Color(Color.WHITE, 0.68), 2.0)
		else:
			var velocity: Vector2 = fragment.velocity
			draw_line(fragment_position - velocity.normalized() * radius * 5.0, fragment_position, Color(color, 0.52), radius * 0.72)
			var direction := Vector2.from_angle(float(fragment.spin))
			var normal := direction.orthogonal()
			var shard := PackedVector2Array([
				fragment_position + direction * radius * 1.25,
				fragment_position - direction * radius * 0.82 + normal * radius * 0.55,
				fragment_position - direction * radius * 0.55 - normal * radius * 0.62
			])
			draw_colored_polygon(shard, Color(color, 0.90))
			draw_circle(fragment_position, radius * 0.28, Color(1.0, 0.93, 0.68, 0.88))
	for corona in active_coronas:
		var center: Vector2 = corona.center
		var radius := float(corona.radius)
		var color: Color = corona.color
		var rotation := float(corona.rotation)
		if float(corona.warning_left) > 0.0:
			draw_arc(center, float(corona.max_radius), 0.0, TAU, 72, Color(color, 0.38), 2.0)
			draw_arc(center, float(corona.min_radius), 0.0, TAU, 36, Color(color, 0.48), 2.0)
			for spoke in 8:
				var angle := TAU * float(spoke) / 8.0 + rotation
				draw_line(center + Vector2.from_angle(angle) * float(corona.min_radius), center + Vector2.from_angle(angle) * float(corona.max_radius), Color(color, 0.10), 1.0)
		else:
			draw_arc(center, radius, 0.0, TAU, 80, Color(color, 0.82), float(corona.width))
			draw_arc(center, radius, 0.0, TAU, 80, Color(Color.WHITE, 0.72), 2.0)
			for node in 10:
				var angle := TAU * float(node) / 10.0 + rotation
				draw_circle(center + Vector2.from_angle(angle) * radius, 3.2, Color(1.0, 0.86, 0.46, 0.88))
