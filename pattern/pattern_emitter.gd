class_name PatternEmitter
extends RefCounted

static func emit(manager: BulletManager, origin: Vector2, target: Vector2, data: PatternData, rotation: float = 0.0, intensity: float = 1.0) -> void:
	var base_angle := origin.angle_to_point(target)
	var count := maxi(1, int(float(data.count) * clampf(intensity, 0.65, 1.45)))
	var layers := data.speed_layers
	var bullet := data.make_bullet()
	match data.kind:
		"aimed":
			manager.spawn_bullet(origin, base_angle, bullet)
		"spread", "burst", "stream":
			var spread := deg_to_rad(data.spread_degrees)
			for layer in layers:
				for i in count:
					var ratio := 0.5 if count == 1 else float(i) / float(count - 1)
					manager.spawn_bullet(origin, base_angle - spread * 0.5 + spread * ratio, bullet, 1.0 + layer * 0.22, layer * 0.045)
		"ring", "radial":
			for layer in layers:
				for i in count:
					manager.spawn_bullet(origin, rotation + TAU * float(i) / float(count) + layer * 0.08, bullet, 1.0 + layer * 0.28)
		"spiral", "rotating":
			for i in count:
				manager.spawn_bullet(origin, rotation + TAU * float(i) / float(count), bullet)
		"wave":
			var spread := deg_to_rad(data.spread_degrees)
			for i in count:
				var offset := (float(i) - float(count - 1) * 0.5) / maxf(1.0, float(count - 1))
				manager.spawn_bullet(origin, base_angle + offset * spread, bullet)
		"layered", "geometric":
			for layer in layers:
				for i in count:
					var alternating := 0.5 / float(count) if layer % 2 else 0.0
					manager.spawn_bullet(origin, rotation + TAU * (float(i) / float(count) + alternating), bullet, 0.8 + layer * 0.30, layer * 0.065)

static func emit_aimed_fan(manager: BulletManager, origin: Vector2, target: Vector2, count: int, spread: float, speed: float, color: Color) -> void:
	var bullet := BulletData.new()
	bullet.speed = speed
	bullet.color = color
	bullet.radius = 5.0
	var center := origin.angle_to_point(target)
	for i in count:
		var ratio := 0.5 if count == 1 else float(i) / float(count - 1)
		manager.spawn_bullet(origin, center + lerpf(-spread * 0.5, spread * 0.5, ratio), bullet)
