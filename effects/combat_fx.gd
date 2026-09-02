class_name CombatFX
extends Node2D

var particles: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
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
