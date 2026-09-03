class_name CombatFX
extends Node2D

var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var phase_glyphs: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 0x56454354

func burst(position: Vector2, color: Color, size: float = 1.0, count: int = 14) -> void:
	for i in count:
		var angle := rng.randf() * TAU
		var speed := rng.randf_range(55.0, 240.0) * size
		particles.append({
			"p": position, "v": Vector2.from_angle(angle) * speed,
			"life": rng.randf_range(0.22, 0.62), "max": 0.62,
			"color": color, "size": rng.randf_range(1.8, 5.2) * size
		})
	rings.append({"p": position, "age": 0.0, "life": 0.35 + size * 0.08, "color": color, "size": size})

func muzzle(position: Vector2, color: Color) -> void:
	burst(position, color, 0.35, 4)

func graze(position: Vector2) -> void:
	for i in 4:
		particles.append({"p": position, "v": Vector2(rng.randf_range(-45, 45), rng.randf_range(-75, -25)), "life": 0.24, "max": 0.24, "color": Color("ffffff"), "size": 1.8})

func shockwave(position: Vector2, color: Color, size: float = 1.0) -> void:
	rings.append({"p": position, "age": 0.0, "life": 0.72, "color": color, "size": size * 3.2})

func phase_break(position: Vector2, color: Color, signature: String) -> void:
	phase_glyphs.append({
		"p": position,
		"age": 0.0,
		"life": 0.72 if signature != "last_light" else 1.05,
		"color": color,
		"signature": signature,
		"rotation": rng.randf_range(0.0, TAU)
	})
	burst(position, color, 1.05 if signature != "last_light" else 1.55, 18 if signature != "last_light" else 34)

func floater(position: Vector2, text: String, color: Color = Color.WHITE, scale: float = 1.0) -> void:
	floaters.append({"p": position, "text": text, "age": 0.0, "life": 0.85, "color": color, "scale": scale})

func _process(delta: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= delta
		if p.life <= 0.0:
			particles.remove_at(i)
			continue
		p.p += p.v * delta
		p.v *= exp(-delta * 3.2)
		particles[i] = p
	for i in range(rings.size() - 1, -1, -1):
		var ring: Dictionary = rings[i]
		ring.age += delta
		if ring.age >= ring.life:
			rings.remove_at(i)
			continue
		rings[i] = ring
	for i in range(floaters.size() - 1, -1, -1):
		var item: Dictionary = floaters[i]
		item.age += delta
		item.p.y -= delta * 42.0
		if item.age >= item.life:
			floaters.remove_at(i)
			continue
		floaters[i] = item
	for i in range(phase_glyphs.size() - 1, -1, -1):
		var glyph: Dictionary = phase_glyphs[i]
		glyph.age += delta
		if glyph.age >= glyph.life:
			phase_glyphs.remove_at(i)
			continue
		phase_glyphs[i] = glyph
	queue_redraw()

func _draw() -> void:
	for particle in particles:
		var alpha: float = clampf(float(particle.life) / float(particle.max), 0.0, 1.0)
		var color: Color = particle.color
		draw_circle(particle.p, particle.size * (0.55 + alpha * 0.45), Color(color, alpha * 0.22))
		draw_circle(particle.p, particle.size * 0.45, Color(color, alpha))
	for ring in rings:
		var ratio: float = ring.age / ring.life
		var color: Color = ring.color
		var radius: float = lerpf(4.0, 78.0 * ring.size, ease(ratio, -1.5))
		draw_arc(ring.p, radius, 0.0, TAU, 48, Color(color, (1.0 - ratio) * 0.8), maxf(1.0, 5.0 * (1.0 - ratio)))
	for item in floaters:
		var ratio: float = item.age / item.life
		var color: Color = item.color
		draw_string(ThemeDB.fallback_font, item.p, item.text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, int(14.0 * item.scale), Color(color, 1.0 - ratio))
	for glyph in phase_glyphs:
		_draw_phase_glyph(glyph)

func _draw_phase_glyph(glyph: Dictionary) -> void:
	var ratio: float = glyph.age / glyph.life
	var fade := 1.0 - ratio
	var center: Vector2 = glyph.p
	var color: Color = glyph.color
	var rotation: float = glyph.rotation + ratio * 1.8
	var reach := lerpf(24.0, 142.0, ease(ratio, -1.5))
	match String(glyph.signature):
		"perimeter":
			draw_rect(Rect2(center - Vector2.ONE * reach * 0.62, Vector2.ONE * reach * 1.24), Color(color, fade * 0.72), false, 4.0 * fade + 1.0)
		"rotary":
			for i in 8:
				var angle := rotation + TAU * float(i) / 8.0
				draw_line(center + Vector2.from_angle(angle) * 14.0, center + Vector2.from_angle(angle) * reach, Color(color, fade * 0.78), 3.0)
		"arbiter":
			var triangle := PackedVector2Array()
			for i in 4:
				triangle.append(center + Vector2.from_angle(rotation + TAU * float(i) / 3.0) * reach)
			draw_polyline(triangle, Color(color, fade * 0.82), 4.0)
		"sentence":
			draw_line(center + Vector2(-reach, reach * 0.34), center + Vector2(reach, -reach * 0.34), Color(color, fade * 0.9), 7.0 * fade + 1.0)
			draw_line(center + Vector2(-reach * 0.55, -reach * 0.45), center + Vector2(reach * 0.55, reach * 0.45), Color.WHITE, 2.0 * fade + 0.5)
		"halo":
			for i in 3:
				draw_arc(center, reach * (0.42 + i * 0.26), rotation * (1.0 if i % 2 else -1.0), rotation * (1.0 if i % 2 else -1.0) + PI * 1.72, 48, Color(color, fade * (0.86 - i * 0.16)), 4.0)
		"maelstrom":
			for i in 22:
				var t := float(i) / 21.0
				var point := center + Vector2.from_angle(rotation + t * TAU * 2.8) * reach * t
				draw_circle(point, 2.0 + fade * 4.0, Color(color, fade * (1.0 - t * 0.5)))
		"lattice":
			draw_set_transform(center, rotation, Vector2.ONE)
			for i in 3:
				var half_size := reach * (0.32 + i * 0.2)
				draw_rect(Rect2(-Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), Color(color, fade * (0.85 - i * 0.18)), false, 3.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"last_light":
			for i in 16:
				var angle := rotation + TAU * float(i) / 16.0
				var inner := 12.0 + float(i % 2) * 16.0
				draw_line(center + Vector2.from_angle(angle) * inner, center + Vector2.from_angle(angle) * reach * 1.35, Color(color, fade * 0.9), 2.0 + float(i % 2) * 3.0)
