class_name BulletData
extends Resource

@export var speed := 150.0
@export var radius := 5.0
@export var color := Color("ff4e9b")
@export var damage := 1.0
@export var lifetime := 9.0
@export_enum("straight", "accelerate", "decelerate", "curve", "wave", "delayed") var modifier := "straight"
@export var modifier_strength := 0.0
@export var delay := 0.0

func copy() -> BulletData:
	var result := BulletData.new()
	result.speed = speed
	result.radius = radius
	result.color = color
	result.damage = damage
	result.lifetime = lifetime
	result.modifier = modifier
	result.modifier_strength = modifier_strength
	result.delay = delay
	return result
