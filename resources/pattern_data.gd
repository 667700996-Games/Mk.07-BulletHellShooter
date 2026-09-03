class_name PatternData
extends Resource

@export var id := "aimed"
@export_enum("aimed", "straight_burst", "spread", "ring", "circle", "spiral", "wave", "burst", "rotating", "layered", "radial", "stream", "geometric") var kind := "aimed"
@export var count := 1
@export var speed := 150.0
@export var speed_layers := 1
@export var spread_degrees := 30.0
@export var rotation_speed := 0.0
@export var color := Color("ff4e9b")
@export var radius := 5.0
@export var modifier := "straight"
@export var modifier_strength := 0.0

func make_bullet() -> BulletData:
	var bullet := BulletData.new()
	bullet.speed = speed
	bullet.radius = radius
	bullet.color = color
	bullet.modifier = modifier
	bullet.modifier_strength = modifier_strength
	if modifier == "delayed":
		bullet.delay = 0.72
	return bullet
