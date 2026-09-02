class_name EnemyUnit
extends RefCounted

var data: EnemyData
var position := Vector2.ZERO
var spawn_position := Vector2.ZERO
var target_position := Vector2.ZERO
var velocity := Vector2.ZERO
var hp := 1.0
var max_hp := 1.0
var age := 0.0
var fire_timer := 0.0
var movement_phase := 0.0
var entering := true
var dead := false
var flash := 0.0
var rotation := 0.0
var variant := 0
var elite := false

func setup(enemy_data: EnemyData, origin: Vector2, target: Vector2, seed_value: int = 0, is_elite: bool = false) -> EnemyUnit:
	data = enemy_data
	spawn_position = origin
	position = origin
	target_position = target
	max_hp = data.hp * (1.55 if is_elite else 1.0)
	hp = max_hp
	variant = abs(seed_value) % 4
	elite = is_elite
	fire_timer = 0.45 + float(variant) * 0.12
	movement_phase = float(seed_value % 17) * 0.37
	return self

func update(delta: float, play_time: float) -> bool:
	age += delta
	flash = maxf(0.0, flash - delta * 8.0)
	rotation += delta * (0.45 if variant % 2 == 0 else -0.45)
	if entering:
		position = position.lerp(target_position, 1.0 - exp(-delta * 4.2))
		if position.distance_to(target_position) < 5.0 or age > 1.3:
			entering = false
			position = target_position
	else:
		match data.movement_id:
			"straight":
				position.y += data.speed * delta * 0.48
			"sway":
				position.y += data.speed * delta * 0.26
				position.x += sin(age * 1.7 + movement_phase) * data.speed * delta * 0.42
			"dash":
				position.y += data.speed * delta * 0.62
				position.x += sin(age * 3.2 + movement_phase) * data.speed * delta * 0.66
			"orbit":
				position.x = target_position.x + sin(age * 1.15 + movement_phase) * (55.0 + variant * 12.0)
				position.y = target_position.y + sin(age * 0.72 + movement_phase) * 25.0 + age * data.speed * 0.06
			"stop":
				position.x = target_position.x + sin(age * 0.8 + movement_phase) * 24.0
				position.y = target_position.y + sin(age * 1.1 + movement_phase) * 10.0
	fire_timer -= delta
	var lifespan := 18.0 + float(data.size_class) * 7.0
	return position.y > 1050.0 or position.x < -90.0 or position.x > 630.0 or age > lifespan

func ready_to_fire() -> bool:
	return not entering and fire_timer <= 0.0

func reset_fire(difficulty: float = 1.0) -> void:
	fire_timer = data.fire_interval / clampf(difficulty, 0.85, 1.5)

func damage(amount: float) -> bool:
	if data.id == "shield":
		amount *= 0.58
	hp -= amount
	flash = 1.0
	if hp <= 0.0:
		dead = true
	return dead
