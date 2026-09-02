class_name PlayerProjectileManager
extends Node2D

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var damages := PackedFloat32Array()
var radii := PackedFloat32Array()
var colors := PackedColorArray()
var piercing := PackedByteArray()
var ages := PackedFloat32Array()

func spawn(origin: Vector2, velocity: Vector2, damage: float, radius: float, color: Color, pierce: bool = false) -> void:
	positions.append(origin)
	velocities.append(velocity)
	damages.append(damage)
	radii.append(radius)
	colors.append(color)
	piercing.append(1 if pierce else 0)
	ages.append(0.0)

func update_projectiles(delta: float) -> void:
	for i in range(positions.size() - 1, -1, -1):
		positions[i] += velocities[i] * delta
		ages[i] += delta
		if positions[i].y < -60.0 or positions[i].x < -50.0 or positions[i].x > 590.0 or ages[i] > 3.5:
			remove_at(i)
	queue_redraw()

func remove_at(index: int) -> void:
	var last := positions.size() - 1
	if index != last:
		positions[index] = positions[last]
		velocities[index] = velocities[last]
		damages[index] = damages[last]
		radii[index] = radii[last]
		colors[index] = colors[last]
		piercing[index] = piercing[last]
		ages[index] = ages[last]
	positions.resize(last)
	velocities.resize(last)
	damages.resize(last)
	radii.resize(last)
	colors.resize(last)
	piercing.resize(last)
	ages.resize(last)

func clear() -> void:
	positions.clear()
	velocities.clear()
	damages.clear()
	radii.clear()
	colors.clear()
	piercing.clear()
	ages.clear()
	queue_redraw()

func _draw() -> void:
	for i in positions.size():
		var p := positions[i]
		var r := radii[i]
		var c := colors[i]
		draw_line(p + Vector2(0, 13 + r), p - Vector2(0, 8 + r), Color(c, 0.18), r * 2.8)
		draw_line(p + Vector2(0, 8), p - Vector2(0, 6), c, r * 1.45)
		draw_circle(p - Vector2(0, 7), r * 0.72, Color.WHITE)
