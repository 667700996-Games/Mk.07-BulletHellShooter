class_name BulletManager
extends Node2D

signal graze_registered(position: Vector2)

const MOD_STRAIGHT := 0
const MOD_ACCELERATE := 1
const MOD_DECELERATE := 2
const MOD_CURVE := 3
const MOD_WAVE := 4
const MOD_DELAYED := 5
const MAX_BULLETS := 4200
const MAX_ERASE_SPARKS := 160
const ERASE_LIFETIME := 0.34

var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var radii := PackedFloat32Array()
var ages := PackedFloat32Array()
var lifetimes := PackedFloat32Array()
var strengths := PackedFloat32Array()
var delays := PackedFloat32Array()
var colors := PackedColorArray()
var modifiers := PackedInt32Array()
var grazed := PackedByteArray()
var erase_positions := PackedVector2Array()
var erase_colors := PackedColorArray()
var erase_ages := PackedFloat32Array()
var active := true
var collision_enabled := true
var bullet_multimesh: MultiMesh
var bullet_renderer: MultiMeshInstance2D

func _ready() -> void:
	_setup_renderer()

func _setup_renderer() -> void:
	bullet_multimesh = MultiMesh.new()
	bullet_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	bullet_multimesh.use_colors = true
	bullet_multimesh.instance_count = MAX_BULLETS
	bullet_multimesh.visible_instance_count = 0
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = load("res://shaders/enemy_bullet.gdshader") as Shader
	quad.material = shader_material
	bullet_multimesh.mesh = quad
	bullet_renderer = MultiMeshInstance2D.new()
	bullet_renderer.name = "BulletBatch"
	bullet_renderer.multimesh = bullet_multimesh
	bullet_renderer.material = shader_material
	add_child(bullet_renderer)

func count() -> int:
	return positions.size()

func _process(delta: float) -> void:
	for i in range(erase_ages.size() - 1, -1, -1):
		erase_ages[i] += delta
		if erase_ages[i] >= ERASE_LIFETIME:
			_remove_erase_at(i)
	if not erase_ages.is_empty():
		queue_redraw()

func _draw() -> void:
	for i in erase_positions.size():
		var ratio := erase_ages[i] / ERASE_LIFETIME
		var fade := 1.0 - ratio
		var color := erase_colors[i]
		var angle := fmod(erase_positions[i].x * 0.071 + erase_positions[i].y * 0.037, TAU)
		var direction := Vector2.from_angle(angle)
		var spark_position := erase_positions[i] + direction * ratio * 24.0
		draw_circle(erase_positions[i], 8.0 + ratio * 12.0, Color(color, fade * 0.08))
		draw_circle(spark_position, maxf(0.7, fade * 2.8), Color(color, fade * 0.9))
		draw_line(spark_position, spark_position - direction * (5.0 + fade * 9.0), Color(Color.WHITE, fade * 0.72), maxf(0.7, fade * 1.8))

func spawn_bullet(origin: Vector2, angle: float, data: BulletData, speed_scale: float = 1.0, delay_override: float = -1.0) -> void:
	if positions.size() >= MAX_BULLETS:
		return
	positions.append(origin)
	velocities.append(Vector2.from_angle(angle) * data.speed * speed_scale)
	radii.append(data.radius)
	ages.append(0.0)
	lifetimes.append(data.lifetime)
	strengths.append(data.modifier_strength)
	delays.append(data.delay if delay_override < 0.0 else delay_override)
	colors.append(data.color)
	modifiers.append(_modifier_id(data.modifier))
	grazed.append(0)

func update_bullets(delta: float, player_position: Vector2, player_vulnerable: bool) -> bool:
	if not active:
		return false
	var hit := false
	var i := positions.size() - 1
	while i >= 0:
		var age := ages[i] + delta
		ages[i] = age
		if age > lifetimes[i]:
			_remove_at(i)
			i -= 1
			continue
		var delay := delays[i]
		if age >= delay:
			var velocity := velocities[i]
			match modifiers[i]:
				MOD_ACCELERATE:
					var next_speed := minf(velocity.length() + strengths[i] * delta, 420.0)
					velocity = velocity.normalized() * next_speed
				MOD_DECELERATE:
					var next_speed := maxf(36.0, velocity.length() - strengths[i] * delta)
					velocity = velocity.normalized() * next_speed
				MOD_CURVE:
					velocity = velocity.rotated(strengths[i] * delta)
				MOD_WAVE:
					velocity = velocity.rotated(sin(age * 6.0) * strengths[i] * delta * 0.035)
			velocities[i] = velocity
			positions[i] += velocity * delta
		var position := positions[i]
		if position.x < -80.0 or position.x > 620.0 or position.y < -100.0 or position.y > 1040.0:
			_remove_at(i)
			i -= 1
			continue
		if collision_enabled and age >= delay:
			var distance_sq := position.distance_squared_to(player_position)
			var hit_distance := radii[i] + 3.2
			if player_vulnerable and distance_sq <= hit_distance * hit_distance:
				hit = true
				_remove_at(i)
				i -= 1
				continue
			var graze_distance := radii[i] + 18.0
			if grazed[i] == 0 and distance_sq <= graze_distance * graze_distance:
				grazed[i] = 1
				graze_registered.emit(position)
		i -= 1
	_sync_renderer()
	return hit

func clear_all(with_effect: bool = true) -> int:
	var erased := positions.size()
	if with_effect and erased > 0:
		var stride := maxi(1, erased / 80)
		for i in range(0, erased, stride):
			_add_erase_spark(positions[i], colors[i])
		EffectManager.flash(colors[erased - 1], minf(0.2, 0.05 + erased * 0.00008))
	positions.clear()
	velocities.clear()
	radii.clear()
	ages.clear()
	lifetimes.clear()
	strengths.clear()
	delays.clear()
	colors.clear()
	modifiers.clear()
	grazed.clear()
	_sync_renderer()
	return erased

func clear_radius(center: Vector2, radius: float) -> int:
	var erased := 0
	var radius_sq := radius * radius
	for i in range(positions.size() - 1, -1, -1):
		if positions[i].distance_squared_to(center) <= radius_sq:
			if erased % 2 == 0:
				_add_erase_spark(positions[i], colors[i])
			_remove_at(i)
			erased += 1
	_sync_renderer()
	if erased > 0:
		queue_redraw()
	return erased

func _add_erase_spark(at: Vector2, color: Color) -> void:
	if erase_positions.size() >= MAX_ERASE_SPARKS:
		return
	erase_positions.append(at)
	erase_colors.append(color)
	erase_ages.append(0.0)
	queue_redraw()

func _remove_erase_at(index: int) -> void:
	var last := erase_positions.size() - 1
	if index != last:
		erase_positions[index] = erase_positions[last]
		erase_colors[index] = erase_colors[last]
		erase_ages[index] = erase_ages[last]
	erase_positions.resize(last)
	erase_colors.resize(last)
	erase_ages.resize(last)

func _remove_at(index: int) -> void:
	var last := positions.size() - 1
	if index != last:
		positions[index] = positions[last]
		velocities[index] = velocities[last]
		radii[index] = radii[last]
		ages[index] = ages[last]
		lifetimes[index] = lifetimes[last]
		strengths[index] = strengths[last]
		delays[index] = delays[last]
		colors[index] = colors[last]
		modifiers[index] = modifiers[last]
		grazed[index] = grazed[last]
	positions.resize(last)
	velocities.resize(last)
	radii.resize(last)
	ages.resize(last)
	lifetimes.resize(last)
	strengths.resize(last)
	delays.resize(last)
	colors.resize(last)
	modifiers.resize(last)
	grazed.resize(last)

func _modifier_id(value: String) -> int:
	match value:
		"accelerate": return MOD_ACCELERATE
		"decelerate": return MOD_DECELERATE
		"curve": return MOD_CURVE
		"wave": return MOD_WAVE
		"delayed": return MOD_DELAYED
	return MOD_STRAIGHT

func _sync_renderer() -> void:
	if bullet_multimesh == null:
		return
	var amount := positions.size()
	bullet_multimesh.visible_instance_count = amount
	for i in amount:
		var delayed := ages[i] < delays[i]
		var scale := radii[i] + (8.0 if delayed else 4.5)
		var transform := Transform2D(0.0, positions[i]).scaled_local(Vector2(scale, scale))
		bullet_multimesh.set_instance_transform_2d(i, transform)
		var color := colors[i]
		if delayed:
			color.a = 0.30 + absf(sin(ages[i] * 20.0)) * 0.34
		bullet_multimesh.set_instance_color(i, color)
