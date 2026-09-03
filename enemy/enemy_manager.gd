class_name EnemyManager
extends Node2D

signal enemy_destroyed(position: Vector2, value: int, color: Color, size_class: int)
signal power_item_requested(position: Vector2)
signal contact_hit

var enemies: Array[EnemyUnit] = []
var rng := RandomNumberGenerator.new()
var bullet_manager: BulletManager
var player_position := Vector2(270, 820)
var difficulty := 1.0
var frozen := false
var enemy_art: Dictionary = {}

func _ready() -> void:
	rng.seed = 0x41524249
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	enemy_art = {
		"drone": load("res://assets/enemies/neon_drone.png") as Texture2D,
		"trooper": load("res://assets/enemies/psychic_trooper.png") as Texture2D,
		"mech": load("res://assets/enemies/assault_mech.png") as Texture2D,
		"gunship": load("res://assets/enemies/vector_gunship.png") as Texture2D
	}

func configure(manager: BulletManager) -> void:
	bullet_manager = manager

func spawn(id: String, origin: Vector2, target: Vector2, elite: bool = false) -> EnemyUnit:
	if enemies.size() >= 64:
		return null
	var unit := EnemyUnit.new().setup(GameDatabase.enemy(id), origin, target, rng.randi(), elite)
	enemies.append(unit)
	queue_redraw()
	return unit

func update_enemies(delta: float, stage_time: float, target: Vector2, next_difficulty: float) -> void:
	if frozen:
		return
	player_position = target
	difficulty = next_difficulty
	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		if enemy.update(delta, stage_time):
			enemies.remove_at(i)
			continue
		if enemy.ready_to_fire() and bullet_manager != null:
			_fire(enemy, stage_time)
			enemy.reset_fire(difficulty)
		if not enemy.entering and enemy.position.distance_squared_to(player_position) < pow(enemy.data.radius + 6.0, 2.0):
			contact_hit.emit()
	queue_redraw()

func collide_projectiles(projectiles: PlayerProjectileManager, damage_scale: float = 1.0) -> int:
	var hits := 0
	for shot_index in range(projectiles.positions.size() - 1, -1, -1):
		if shot_index >= projectiles.positions.size():
			continue
		var shot_position := projectiles.positions[shot_index]
		for enemy_index in range(enemies.size() - 1, -1, -1):
			var enemy := enemies[enemy_index]
			if enemy.entering and enemy.age < 0.22:
				continue
			var distance := enemy.data.radius + projectiles.radii[shot_index]
			if shot_position.distance_squared_to(enemy.position) <= distance * distance:
				hits += 1
				var destroyed := enemy.damage(projectiles.damages[shot_index] * damage_scale)
				if destroyed:
					_destroy_enemy(enemy_index)
				if projectiles.piercing[shot_index] == 0:
					projectiles.remove_at(shot_index)
				break
	return hits

func damage_radius(center: Vector2, radius: float, damage: float) -> int:
	var destroyed := 0
	for i in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[i]
		if enemy.position.distance_to(center) <= radius + enemy.data.radius:
			if enemy.damage(damage):
				_destroy_enemy(i)
				destroyed += 1
	return destroyed

func clear_all(silent: bool = false) -> void:
	if silent:
		enemies.clear()
	else:
		for i in range(enemies.size() - 1, -1, -1):
			_destroy_enemy(i)
	queue_redraw()

func _destroy_enemy(index: int) -> void:
	var enemy := enemies[index]
	var risk := clampf(1.0 - enemy.position.distance_to(player_position) / 300.0, 0.0, 0.75)
	var gained := ScoreManager.register_kill(enemy.data.score_value, risk)
	enemy_destroyed.emit(enemy.position, gained, enemy.data.color, enemy.data.size_class)
	if rng.randf() < enemy.data.power_drop_chance:
		power_item_requested.emit(enemy.position)
	enemies.remove_at(index)

func _fire(enemy: EnemyUnit, stage_time: float) -> void:
	var data := GameDatabase.pattern(enemy.data.pattern_id)
	var rotation := stage_time * data.rotation_speed + enemy.movement_phase
	PatternEmitter.emit(bullet_manager, enemy.position, player_position, data, rotation, minf(1.25, difficulty))
	AudioManager.play_sfx("enemy_shot", rng.randf_range(0.88, 1.12), -13.0)
	if enemy.data.id == "summoner" and enemies.size() < 22 and rng.randf() < 0.45:
		for side in [-1.0, 1.0]:
			spawn("drone", enemy.position, enemy.position + Vector2(side * 70.0, 85.0))

func _draw() -> void:
	for enemy in enemies:
		_draw_enemy(enemy)

func _draw_enemy(enemy: EnemyUnit) -> void:
	var p := enemy.position
	var r := enemy.data.radius
	var color := Color.WHITE if enemy.flash > 0.0 else enemy.data.color
	var entry_alpha := clampf(enemy.age / 0.35, 0.0, 1.0)
	if enemy.entering:
		draw_line(enemy.spawn_position, p, Color(enemy.data.color, (1.0 - entry_alpha) * 0.35), 5.0)
		draw_arc(p, r + 14.0 * (1.0 - entry_alpha), 0, TAU, 24, Color(enemy.data.color, entry_alpha * 0.7), 2.0)
	match enemy.data.id:
		"drone", "heavy_drone", "grade_3":
			var wing := r * (1.55 if enemy.data.id == "heavy_drone" else 1.25)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0,-r), p + Vector2(wing,r*0.6), p + Vector2(0,r*0.35), p + Vector2(-wing,r*0.6)]), Color(color, entry_alpha))
			draw_circle(p, r * 0.48, Color("17213d"))
			draw_circle(p, r * 0.25, Color("ffffff"))
		"soldier", "guard", "sniper", "summoner":
			draw_circle(p + Vector2(0,-r*0.55), r*0.32, Color(color,entry_alpha))
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r*0.2),p+Vector2(r*0.72,r),p+Vector2(0,r*0.72),p+Vector2(-r*0.72,r)]), Color(color.darkened(0.18),entry_alpha))
			draw_line(p+Vector2(-r*0.4,0),p+Vector2(r*0.8,r*0.36),color,3.0)
			if enemy.data.id == "sniper" and enemy.fire_timer < 0.55:
				draw_line(p, player_position, Color(1.0,0.12,0.12,0.22 + (0.55-enemy.fire_timer)*0.45), 1.0)
		"bike":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r*1.4),p+Vector2(r*0.7,r),p,p+Vector2(-r*0.7,r)]),Color(color,entry_alpha))
			draw_line(p+Vector2(-r, r),p+Vector2(r,r),Color.WHITE,2.0)
		"turret", "mech", "shield", "grade_1":
			draw_rect(Rect2(p-Vector2(r*0.75,r*0.65),Vector2(r*1.5,r*1.3)),Color(color.darkened(0.25),entry_alpha))
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(r*0.7,0),p+Vector2(0,r*0.45),p+Vector2(-r*0.7,0)]),Color(color,entry_alpha))
			draw_line(p,p+Vector2(0,r*1.35),Color.WHITE,4.0)
			if enemy.data.id == "shield":
				draw_arc(p,r+8.0,enemy.rotation,enemy.rotation+PI*1.55,30,Color("62edff"),3.0)
		"gunship", "grade_2":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(r*1.65,r*0.45),p+Vector2(r*0.45,r),p+Vector2(0,r*0.45),p+Vector2(-r*0.45,r),p+Vector2(-r*1.65,r*0.45)]),Color(color.darkened(0.2),entry_alpha))
			for x in [-r*0.8,r*0.8]:
				draw_circle(p+Vector2(x,r*0.35),r*0.28,color)
		_:
			draw_circle(p,r,color)
	# Detailed authored cutout over the procedural silhouette; the latter remains as
	# a high-contrast fallback/outline and keeps special units readable at 48 px.
	var archetype := _art_archetype(enemy.data.id)
	var texture: Texture2D = enemy_art.get(archetype)
	if texture:
		var art_size := Vector2(r * 3.25, r * 3.25)
		if archetype == "trooper":
			art_size = Vector2(r * 2.55, r * 3.82)
		elif archetype == "mech":
			art_size = Vector2(r * 2.95, r * 4.18)
		elif archetype == "gunship":
			art_size = Vector2(r * 3.65, r * 3.35)
		var tint := Color(1, 1, 1, entry_alpha)
		if enemy.flash > 0.0:
			tint = Color(1.8, 1.8, 1.8, entry_alpha)
		draw_texture_rect(texture, Rect2(p - art_size * 0.5, art_size), false, tint)
	if enemy.data.id == "sniper" and enemy.fire_timer < 0.55:
		draw_line(p, player_position, Color(1.0,0.12,0.12,0.30 + (0.55-enemy.fire_timer)*0.55), 1.0)
	if enemy.data.id == "shield":
		draw_arc(p,r+10.0,enemy.rotation,enemy.rotation+PI*1.55,30,Color("62edff"),3.0)
	# Health strip for medium and special units.
	if enemy.data.size_class > 0:
		var ratio := clampf(enemy.hp / enemy.max_hp, 0.0, 1.0)
		draw_rect(Rect2(p.x-r,p.y+r+7,r*2,3),Color("32162d"))
		draw_rect(Rect2(p.x-r,p.y+r+7,r*2*ratio,3),color)
	if enemy.elite:
		draw_arc(p, r + 5.0, enemy.rotation, enemy.rotation + PI * 1.5, 22, Color("ffd965"), 2.0)

func _art_archetype(id: String) -> String:
	match id:
		"drone", "heavy_drone", "scout", "grade_3": return "drone"
		"soldier", "guard", "sniper", "summoner": return "trooper"
		"turret", "mech", "shield", "grade_1": return "mech"
		"bike", "gunship", "grade_2": return "gunship"
	return "drone"
