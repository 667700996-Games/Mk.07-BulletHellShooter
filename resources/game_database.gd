class_name GameDatabase
extends RefCounted

static var _balance_cache: Dictionary = {}
static var _balance_loaded := false
const ENEMY_IDS := [
	"grade_3", "grade_2", "grade_1", "drone", "soldier", "bike", "turret",
	"scout", "mech", "heavy_drone", "guard", "gunship", "shield", "sniper", "summoner",
	"tempest_grade_3", "tempest_grade_2", "tempest_grade_1",
	"forge_grade_3", "forge_grade_2", "forge_grade_1"
]
const PATTERN_IDS := [
	"grade_3_straight", "grade_2_radial", "grade_1_circle", "aimed", "spread",
	"ring", "spiral", "curve", "stream", "burst", "layered", "radial",
	"rotating", "sniper", "summon", "geometric", "tempest_grade_3_straight",
	"tempest_grade_2_radial", "tempest_grade_1_circle", "forge_grade_3_straight",
	"forge_grade_2_radial", "forge_grade_1_circle"
]

static func has_enemy(id: String) -> bool:
	return ENEMY_IDS.has(id)

static func has_pattern(id: String) -> bool:
	return PATTERN_IDS.has(id)

static func enemy(id: String) -> EnemyData:
	var definitions := {
		"grade_3": ["GRADE-3 INTERCEPTOR", 28.0, 128.0, 12.0, 140, 1.65, "grade_3_straight", "straight", Color("ff496c"), 0],
		"grade_2": ["GRADE-2 RADIAL", 315.0, 62.0, 21.0, 520, 2.20, "grade_2_radial", "sway", Color("ffba32"), 1],
		"grade_1": ["GRADE-1 CIRCULAR", 720.0, 42.0, 30.0, 1200, 5.50, "grade_1_circle", "stop", Color("bf5dff"), 2],
		"drone": ["NEON DRONE", 24.0, 120.0, 13.0, 120, 1.45, "aimed", "straight", Color("ff496c"), 0],
		"soldier": ["DROP SOLDIER", 38.0, 78.0, 15.0, 180, 1.2, "spread", "sway", Color("f980ff"), 0],
		"bike": ["HOVER BIKE", 30.0, 175.0, 14.0, 210, 0.75, "stream", "dash", Color("ff9f43"), 0],
		"turret": ["ROAD TURRET", 75.0, 45.0, 19.0, 350, 1.65, "ring", "stop", Color("ff335f"), 1],
		"scout": ["PSYCHIC SCOUT", 42.0, 105.0, 15.0, 260, 1.1, "curve", "orbit", Color("ab65ff"), 0],
		"mech": ["ASSAULT MECH", 230.0, 48.0, 28.0, 900, 0.9, "burst", "stop", Color("ff7535"), 1],
		"heavy_drone": ["HEAVY DRONE", 180.0, 58.0, 27.0, 780, 0.85, "layered", "sway", Color("ff3d8f"), 1],
		"guard": ["PSYCHIC GUARD", 155.0, 66.0, 23.0, 720, 0.72, "spiral", "orbit", Color("cf46ff"), 1],
		"gunship": ["VECTOR GUNSHIP", 320.0, 42.0, 34.0, 1400, 0.62, "radial", "sway", Color("ffba32"), 2],
		"shield": ["AEGIS UNIT", 210.0, 50.0, 25.0, 1100, 1.0, "rotating", "stop", Color("45d6ff"), 1],
		"sniper": ["LATTICE SNIPER", 95.0, 40.0, 18.0, 680, 2.1, "sniper", "stop", Color("ff4b4b"), 1],
		"summoner": ["RIFT SUMMONER", 260.0, 35.0, 26.0, 1600, 1.35, "summon", "orbit", Color("7655ff"), 2],
		# NULL TEMPEST keeps the same readable three-grade combat grammar as the
		# opening route. Its modest stat lift comes from durability and cadence,
		# never from secretly adding bullets to a familiar silhouette.
		"tempest_grade_3": ["TEMPEST NEEDLE", 34.0, 140.0, 12.0, 175, 1.55, "tempest_grade_3_straight", "straight", Color("42e8ff"), 0],
		"tempest_grade_2": ["TEMPEST CORONA", 380.0, 66.0, 22.0, 650, 2.10, "tempest_grade_2_radial", "sway", Color("7785ff"), 1],
		"tempest_grade_1": ["TEMPEST MONOLITH", 860.0, 44.0, 31.0, 1500, 5.20, "tempest_grade_1_circle", "stop", Color("d460ff"), 2],
		# HELIOS FORGE preserves the three-grade readability contract while
		# increasing durability and cadence for the campaign's final operation.
		"forge_grade_3": ["CINDER DART", 40.0, 148.0, 12.0, 210, 1.48, "forge_grade_3_straight", "straight", Color("ffb52e"), 0],
		"forge_grade_2": ["CORONA WHEEL", 430.0, 68.0, 23.0, 780, 2.00, "forge_grade_2_radial", "sway", Color("ff7738"), 1],
		"forge_grade_1": ["HELIOS BASTION", 980.0, 46.0, 32.0, 1850, 4.90, "forge_grade_1_circle", "stop", Color("ffe09b"), 2]
	}
	var row: Array = definitions.get(id, definitions.drone)
	var data := EnemyData.new()
	data.id = id
	data.display_name = row[0]
	data.hp = row[1]
	data.speed = row[2]
	data.radius = row[3]
	data.score_value = row[4]
	data.fire_interval = row[5]
	data.pattern_id = row[6]
	data.movement_id = row[7]
	data.color = row[8]
	data.size_class = row[9]
	data.grade = 3 - data.size_class
	data.power_drop_chance = 0.07 + float(row[9]) * 0.035
	_apply_enemy_balance(data)
	return data

static func pattern(id: String) -> PatternData:
	var definitions := {
		"grade_3_straight": ["straight_burst", 3, 235.0, 1, 0.0, 0.0, Color("ff496c"), 4.0, "straight", 0.0],
		"grade_2_radial": ["radial", 8, 122.0, 1, 360.0, 0.0, Color("ffba32"), 4.8, "straight", 0.0],
		"grade_1_circle": ["circle", 10, 88.0, 1, 360.0, 0.0, Color("bf5dff"), 5.4, "straight", 0.0],
		"aimed": ["aimed", 1, 155.0, 1, 0.0, 0.0, Color("ff4b83"), 5.0, "straight", 0.0],
		"spread": ["spread", 5, 145.0, 1, 42.0, 0.0, Color("ff6cb5"), 5.0, "straight", 0.0],
		"ring": ["ring", 14, 122.0, 1, 360.0, 0.0, Color("ffad43"), 5.0, "decelerate", 32.0],
		"spiral": ["spiral", 4, 138.0, 1, 360.0, 0.75, Color("a84dff"), 5.5, "straight", 0.0],
		"curve": ["wave", 6, 150.0, 1, 55.0, 0.0, Color("ff5ce7"), 5.0, "curve", 0.55],
		"stream": ["stream", 3, 195.0, 1, 16.0, 0.0, Color("ff4747"), 4.0, "accelerate", 35.0],
		"burst": ["burst", 9, 135.0, 2, 80.0, 0.0, Color("ff873a"), 5.5, "straight", 0.0],
		"layered": ["layered", 12, 118.0, 3, 360.0, 0.45, Color("fc4d98"), 5.0, "curve", 0.22],
		"radial": ["radial", 20, 105.0, 2, 360.0, 0.0, Color("ffbd45"), 5.0, "accelerate", 18.0],
		"rotating": ["rotating", 8, 135.0, 1, 360.0, 1.2, Color("4eeaff"), 5.2, "curve", 0.32],
		"sniper": ["aimed", 1, 285.0, 1, 0.0, 0.0, Color("ff3030"), 7.0, "delayed", 0.0],
		"summon": ["ring", 10, 85.0, 2, 360.0, 0.0, Color("7655ff"), 6.0, "wave", 24.0],
		"geometric": ["geometric", 24, 108.0, 2, 360.0, 0.32, Color("ff477e"), 5.0, "curve", 0.18],
		"tempest_grade_3_straight": ["straight_burst", 3, 245.0, 1, 0.0, 0.0, Color("42e8ff"), 4.0, "straight", 0.0],
		"tempest_grade_2_radial": ["radial", 8, 128.0, 1, 360.0, 0.0, Color("7785ff"), 4.8, "straight", 0.0],
		"tempest_grade_1_circle": ["circle", 10, 94.0, 1, 360.0, 0.0, Color("d460ff"), 5.4, "straight", 0.0],
		"forge_grade_3_straight": ["straight_burst", 3, 255.0, 1, 0.0, 0.0, Color("ffb52e"), 4.0, "straight", 0.0],
		"forge_grade_2_radial": ["radial", 8, 134.0, 1, 360.0, 0.0, Color("ff7738"), 4.8, "straight", 0.0],
		"forge_grade_1_circle": ["circle", 10, 98.0, 1, 360.0, 0.0, Color("ffe09b"), 5.4, "straight", 0.0]
	}
	var row: Array = definitions.get(id, definitions.aimed)
	var data := PatternData.new()
	data.id = id
	data.kind = row[0]
	data.count = row[1]
	data.speed = row[2]
	data.speed_layers = row[3]
	data.spread_degrees = row[4]
	data.rotation_speed = row[5]
	data.color = row[6]
	data.radius = row[7]
	data.modifier = row[8]
	data.modifier_strength = row[9]
	if id in ["grade_1_circle", "tempest_grade_1_circle", "forge_grade_1_circle"]:
		data.volley_count = 3
		data.volley_delay = 0.22
	_apply_pattern_balance(data)
	return data

static func global_balance(key: String, default_value: float = 1.0) -> float:
	var values: Dictionary = _balance().get("global", {})
	return float(values.get(key, default_value))

static func _apply_enemy_balance(data: EnemyData) -> void:
	var section: Dictionary = _balance().get("enemies", {})
	var values: Dictionary = section.get(data.id, {})
	data.hp = float(values.get("hp", data.hp)) * global_balance("enemy_hp_scale")
	data.speed = float(values.get("speed", data.speed)) * global_balance("enemy_speed_scale")
	data.fire_interval = float(values.get("fire_interval", data.fire_interval)) * global_balance("enemy_fire_interval_scale")
	data.score_value = int(values.get("score", data.score_value))
	data.power_drop_chance = float(values.get("power_drop", data.power_drop_chance))

static func _apply_pattern_balance(data: PatternData) -> void:
	var section: Dictionary = _balance().get("patterns", {})
	var values: Dictionary = section.get(data.id, {})
	data.count = int(values.get("count", data.count))
	data.speed = float(values.get("speed", data.speed)) * global_balance("enemy_bullet_speed_scale")
	data.radius = float(values.get("radius", data.radius))
	data.volley_count = int(values.get("volley_count", data.volley_count))
	data.volley_delay = float(values.get("volley_delay", data.volley_delay))

static func _balance() -> Dictionary:
	if _balance_loaded:
		return _balance_cache
	_balance_loaded = true
	var text := FileAccess.get_file_as_string("res://resources/balance.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_balance_cache = parsed
	return _balance_cache
