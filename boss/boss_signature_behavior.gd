class_name BossSignatureBehavior
extends RefCounted

## One pluggable boss-phase signature. Built-in signatures use declarative
## profiles, while future content may subclass this type and override either
## method without changing BossController.

const SUPPORT_PATTERN := "pattern"
const SUPPORT_AIMED_FAN := "aimed_fan"

var profile: Dictionary = {}


func _init(values: Dictionary = {}) -> void:
	profile = values.duplicate(true)


func emit_support(context: Dictionary) -> int:
	if not _passes_trigger(context):
		return 0
	var manager: BulletManager = context.get("bullet_manager") as BulletManager
	if manager == null:
		return 0
	var before := manager.count()
	var origin: Vector2 = context.get("origin", Vector2.ZERO)
	var target: Vector2 = context.get("target", Vector2.ZERO)
	var support_type := String(profile.get("support_type", ""))
	match support_type:
		SUPPORT_PATTERN:
			_emit_pattern(manager, origin, target, context)
		SUPPORT_AIMED_FAN:
			var accent: Color = context.get("accent", Color.WHITE)
			PatternEmitter.emit_aimed_fan(
				manager,
				origin,
				target,
				int(profile.get("fan_count", 1)),
				float(profile.get("fan_spread", 0.0)),
				float(profile.get("fan_speed", 155.0)),
				accent
			)
	return manager.count() - before


func draw_transition(host: Node2D, context: Dictionary) -> void:
	if host == null:
		return
	var center: Vector2 = context.get("center", Vector2.ZERO)
	var color: Color = context.get("color", Color.WHITE)
	var energy := float(context.get("energy", 0.0))
	var reach := float(context.get("reach", 0.0))
	var rotation := float(context.get("rotation", 0.0))
	var radius := float(context.get("radius", 0.0))
	var style := String(profile.get("transition_style", ""))
	match style:
		"perimeter":
			for i in 4:
				var angle := TAU * float(i) / 4.0 + rotation
				host.draw_line(center + Vector2.from_angle(angle) * radius, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.82), 3.0)
		"rotary":
			for i in 8:
				var angle := TAU * float(i) / 8.0 + rotation * 1.8
				host.draw_line(center + Vector2.from_angle(angle) * 16.0, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.68), 2.0 + float(i % 2))
		"arbiter":
			for i in 3:
				var angle := TAU * float(i) / 3.0 - rotation
				var point := center + Vector2.from_angle(angle) * reach
				host.draw_circle(point, 7.0 + energy * 5.0, Color(color, energy * 0.72))
				host.draw_line(center, point, Color(color, energy * 0.34), 2.0)
		"sentence":
			var target: Vector2 = context.get("target", Vector2.ZERO)
			var host_position: Vector2 = context.get("host_position", Vector2.ZERO)
			var aim := (target - host_position).normalized()
			if aim == Vector2.ZERO:
				aim = Vector2.DOWN
			host.draw_line(center - aim * reach * 0.25, center + aim * reach, Color(color, energy * 0.72), 4.0)
			host.draw_line(center - aim.rotated(PI * 0.5) * 38.0, center + aim.rotated(PI * 0.5) * 38.0, Color.WHITE, energy * 2.0)
		"halo":
			for i in 3:
				var direction := 1.0 if i % 2 else -1.0
				host.draw_arc(center, reach * (0.48 + i * 0.22), rotation * direction, rotation * direction + PI * 1.55, 48, Color(color, energy * (0.72 - i * 0.12)), 3.0)
		"maelstrom":
			for i in 18:
				var progress := float(i) / 17.0
				var angle := rotation * 2.0 + progress * TAU * 2.4
				var point := center + Vector2.from_angle(angle) * reach * progress
				host.draw_circle(point, 2.0 + energy * 3.0, Color(color, energy * (1.0 - progress * 0.45)))
		"lattice":
			host.draw_set_transform(center, rotation * 0.7, Vector2.ONE)
			for i in 3:
				var half_size := reach * (0.35 + i * 0.2)
				host.draw_rect(Rect2(-Vector2.ONE * half_size, Vector2.ONE * half_size * 2.0), Color(color, energy * (0.72 - i * 0.16)), false, 2.5)
			host.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"last_light":
			for i in 12:
				var angle := TAU * float(i) / 12.0 + rotation
				var inner := radius * (0.45 if i % 2 else 0.7)
				host.draw_line(center + Vector2.from_angle(angle) * inner, center + Vector2.from_angle(angle) * reach, Color(color, energy * 0.78), 2.0 + float(i % 2) * 2.0)


func _passes_trigger(context: Dictionary) -> bool:
	var required_primary := String(profile.get("primary_id", ""))
	if not required_primary.is_empty() and String(context.get("primary_id", "")) != required_primary:
		return false
	var every := maxi(1, int(profile.get("every", 1)))
	return int(context.get("cursor", 0)) % every == 0


func _emit_pattern(manager: BulletManager, origin: Vector2, target: Vector2, context: Dictionary) -> void:
	var pattern_id := String(profile.get("pattern_id", ""))
	if pattern_id.is_empty() or not GameDatabase.has_pattern(pattern_id):
		return
	var pattern := GameDatabase.pattern(pattern_id)
	var count_override := int(profile.get("count", 0))
	if count_override > 0:
		pattern.count = count_override
	pattern.speed = pattern.speed * float(profile.get("speed_scale", 1.0)) + float(profile.get("speed_add", 0.0))
	pattern.modifier_strength *= float(profile.get("modifier_strength_scale", 1.0))
	if profile.has("modifier"):
		pattern.modifier = String(profile.modifier)
	if profile.has("modifier_strength"):
		pattern.modifier_strength = float(profile.modifier_strength)
	var rotation := float(context.get("rotation", 0.0)) * float(profile.get("rotation_scale", 1.0)) + float(profile.get("rotation_offset", 0.0))
	var difficulty := float(context.get("difficulty", 1.0))
	var intensity := float(profile.get("fixed_intensity", minf(float(profile.get("intensity_cap", 1.0)), difficulty)))
	PatternEmitter.emit(manager, origin, target, pattern, rotation, intensity)
