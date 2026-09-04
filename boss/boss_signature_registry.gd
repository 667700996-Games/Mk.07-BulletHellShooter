class_name BossSignatureRegistry
extends RefCounted

## Registry boundary between authored phase IDs and their optional support
## attacks/presentation. BossController depends only on this interface.

const BUILTIN_PROFILES := {
	"perimeter": {
		"primary_id": "ring", "every": 2, "support_type": "pattern", "pattern_id": "ring",
		"count": 8, "speed_scale": 0.72, "rotation_offset": PI / 8.0, "transition_style": "perimeter"
	},
	"rotary": {
		"primary_id": "rotating", "support_type": "pattern", "pattern_id": "rotating",
		"count": 4, "modifier_strength_scale": -1.0, "rotation_scale": -1.0, "transition_style": "rotary"
	},
	"arbiter": {
		"every": 4, "support_type": "aimed_fan", "fan_count": 3, "fan_spread": 0.24,
		"fan_speed": 168.0, "transition_style": "arbiter"
	},
	"sentence": {
		"primary_id": "aimed", "support_type": "aimed_fan", "fan_count": 2,
		"fan_spread": 0.16, "fan_speed": 188.0, "transition_style": "sentence"
	},
	"halo": {
		"primary_id": "ring", "support_type": "pattern", "pattern_id": "ring", "count": 9,
		"speed_scale": 1.28, "modifier": "accelerate", "modifier_strength": 12.0,
		"rotation_offset": PI / 9.0, "transition_style": "halo"
	},
	"maelstrom": {
		"every": 3, "support_type": "pattern", "pattern_id": "aimed", "speed_add": 34.0,
		"rotation_scale": 0.0, "fixed_intensity": 1.0, "transition_style": "maelstrom"
	},
	"lattice": {
		"primary_id": "geometric", "support_type": "pattern", "pattern_id": "geometric",
		"count": 10, "speed_scale": 0.84, "rotation_offset": PI / 10.0, "transition_style": "lattice"
	},
	"last_light": {
		"every": 4, "support_type": "aimed_fan", "fan_count": 3, "fan_spread": 0.30,
		"fan_speed": 218.0, "transition_style": "last_light"
	},
	"solar_reap": {
		"every": 2, "support_type": "aimed_fan", "fan_count": 3, "fan_spread": 0.21,
		"fan_speed": 176.0, "transition_style": "solar_reap"
	},
	"crown_arc": {
		"primary_id": "rotating", "support_type": "pattern", "pattern_id": "rotating",
		"count": 6, "modifier_strength_scale": -1.0, "rotation_scale": -1.0,
		"transition_style": "crown_arc"
	},
	"furnace_lock": {
		"every": 3, "support_type": "pattern", "pattern_id": "ring", "count": 10,
		"speed_scale": 0.92, "modifier": "accelerate", "modifier_strength": 15.0,
		"rotation_offset": PI / 10.0, "transition_style": "furnace_lock"
	},
	"first_ignition": {
		"primary_id": "spread", "support_type": "aimed_fan", "fan_count": 3,
		"fan_spread": 0.27, "fan_speed": 182.0, "transition_style": "first_ignition"
	},
	"photosphere": {
		"primary_id": "ring", "support_type": "pattern", "pattern_id": "ring", "count": 11,
		"speed_scale": 1.12, "modifier": "accelerate", "modifier_strength": 10.0,
		"rotation_offset": PI / 11.0, "transition_style": "photosphere"
	},
	"prominence": {
		"every": 3, "support_type": "pattern", "pattern_id": "stream", "speed_add": 28.0,
		"rotation_offset": PI / 7.0, "intensity_cap": 1.1, "transition_style": "prominence"
	},
	"blackbody": {
		"primary_id": "geometric", "support_type": "pattern", "pattern_id": "geometric",
		"count": 12, "speed_scale": 0.78, "rotation_offset": PI / 12.0,
		"transition_style": "blackbody"
	},
	"last_dawn": {
		"every": 4, "support_type": "aimed_fan", "fan_count": 4, "fan_spread": 0.34,
		"fan_speed": 224.0, "transition_style": "last_dawn"
	}
}

var _behaviors: Dictionary = {}


func _init(include_builtins: bool = true) -> void:
	if include_builtins:
		for signature_id in BUILTIN_PROFILES:
			register(String(signature_id), BossSignatureBehavior.new(BUILTIN_PROFILES[signature_id]))


static func supports_builtin(signature_id: String) -> bool:
	return BUILTIN_PROFILES.has(signature_id)


static func builtin_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for signature_id in BUILTIN_PROFILES:
		ids.append(String(signature_id))
	ids.sort()
	return ids


func register(signature_id: String, behavior: BossSignatureBehavior, replace_existing: bool = false) -> bool:
	var normalized := signature_id.strip_edges()
	if normalized.is_empty() or behavior == null:
		return false
	if _behaviors.has(normalized) and not replace_existing:
		return false
	_behaviors[normalized] = behavior
	return true


func unregister(signature_id: String) -> bool:
	return _behaviors.erase(signature_id)


func supports(signature_id: String) -> bool:
	return _behaviors.has(signature_id)


func registered_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for signature_id in _behaviors:
		ids.append(String(signature_id))
	ids.sort()
	return ids


func behavior_for(signature_id: String) -> BossSignatureBehavior:
	return _behaviors.get(signature_id) as BossSignatureBehavior


func emit_support(signature_id: String, context: Dictionary) -> int:
	var behavior := behavior_for(signature_id)
	return behavior.emit_support(context) if behavior != null else 0


func draw_transition(signature_id: String, host: Node2D, context: Dictionary) -> void:
	var behavior := behavior_for(signature_id)
	if behavior != null:
		behavior.draw_transition(host, context)
