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
var enemy_animation: Dictionary = {}

func _ready() -> void:
	rng.seed = 0x41524249
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	enemy_art = {
		"drone": load("res://assets/enemies/neon_drone.png") as Texture2D,
		"trooper": load("res://assets/enemies/psychic_trooper.png") as Texture2D,
		"mech": load("res://assets/enemies/assault_mech.png") as Texture2D,
		"gunship": load("res://assets/enemies/vector_gunship.png") as Texture2D
	}
	enemy_animation = {
		"drone": load("res://assets/enemies/neon_drone_combat_sheet.png") as Texture2D,
		"trooper": load("res://assets/enemies/psychic_trooper_combat_sheet.png") as Texture2D,
		"mech": load("res://assets/enemies/assault_mech_combat_sheet.png") as Texture2D,
		"gunship": load("res://assets/enemies/vector_gunship_combat_sheet.png") as Texture2D
	}

func configure(manager: BulletManager, seed_value: int = 0x41524249) -> void:
	bullet_manager = manager
	rng.seed = seed_value

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
		enemy.update_animation(delta)
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
			var target_id := enemy.get_instance_id()
			if projectiles.piercing[shot_index] != 0 and projectiles.has_hit_target(shot_index, target_id):
				continue
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
				else:
					projectiles.mark_hit_target(shot_index, target_id)
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
	var archetype := _art_archetype(enemy.data.id)
	var animation_texture: Texture2D = enemy_animation.get(archetype) as Texture2D
	var fallback_texture: Texture2D = enemy_art.get(archetype) as Texture2D
	var procedural_alpha := entry_alpha * (0.12 if animation_texture or fallback_texture else 1.0)
	if enemy.entering:
		draw_line(enemy.spawn_position, p, Color(enemy.data.color, (1.0 - entry_alpha) * 0.35), 5.0)
		draw_arc(p, r + 14.0 * (1.0 - entry_alpha), 0, TAU, 24, Color(enemy.data.color, entry_alpha * 0.7), 2.0)
	match enemy.data.id:
		"drone", "heavy_drone", "grade_3":
			var wing := r * (1.55 if enemy.data.id == "heavy_drone" else 1.25)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0,-r), p + Vector2(wing,r*0.6), p + Vector2(0,r*0.35), p + Vector2(-wing,r*0.6)]), Color(color, procedural_alpha))
			draw_circle(p, r * 0.48, Color(Color("17213d"), procedural_alpha))
			draw_circle(p, r * 0.25, Color(Color.WHITE, procedural_alpha))
		"soldier", "guard", "sniper", "summoner":
			draw_circle(p + Vector2(0,-r*0.55), r*0.32, Color(color, procedural_alpha))
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r*0.2),p+Vector2(r*0.72,r),p+Vector2(0,r*0.72),p+Vector2(-r*0.72,r)]), Color(color.darkened(0.18), procedural_alpha))
			draw_line(p+Vector2(-r*0.4,0),p+Vector2(r*0.8,r*0.36),Color(color, procedural_alpha),3.0)
		"bike":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r*1.4),p+Vector2(r*0.7,r),p,p+Vector2(-r*0.7,r)]),Color(color, procedural_alpha))
			draw_line(p+Vector2(-r, r),p+Vector2(r,r),Color(Color.WHITE, procedural_alpha),2.0)
		"turret", "mech", "shield", "grade_1":
			draw_rect(Rect2(p-Vector2(r*0.75,r*0.65),Vector2(r*1.5,r*1.3)),Color(color.darkened(0.25), procedural_alpha))
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(r*0.7,0),p+Vector2(0,r*0.45),p+Vector2(-r*0.7,0)]),Color(color, procedural_alpha))
			draw_line(p,p+Vector2(0,r*1.35),Color(Color.WHITE, procedural_alpha),4.0)
		"gunship", "grade_2":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-r),p+Vector2(r*1.65,r*0.45),p+Vector2(r*0.45,r),p+Vector2(0,r*0.45),p+Vector2(-r*0.45,r),p+Vector2(-r*1.65,r*0.45)]),Color(color.darkened(0.2), procedural_alpha))
			for x in [-r*0.8,r*0.8]:
				draw_circle(p+Vector2(x,r*0.35),r*0.28,Color(color, procedural_alpha))
		_:
			draw_circle(p,r,Color(color, procedural_alpha))
	# Detailed authored animation over a subdued procedural readability silhouette.
	# Static art remains available as a safe fallback if a sheet cannot be loaded.
	if animation_texture or fallback_texture:
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
		var bob := sin(enemy.age * (2.8 + enemy.variant * 0.17) + enemy.movement_phase) * (1.2 + enemy.data.size_class * 0.45)
		var bank := sin(enemy.age * 1.65 + enemy.movement_phase) * (0.025 if enemy.data.movement_id == "stop" else 0.065)
		var recoil_offset := Vector2(0.0, -enemy.fire_recoil * (3.0 + enemy.data.size_class))
		var pulse := 1.0 + enemy.fire_recoil * 0.055
		draw_set_transform(p + Vector2(0.0, bob) + recoil_offset, bank, Vector2.ONE * pulse)
		if animation_texture:
			var prior_alpha := 1.0 - enemy.animation_blend
			if prior_alpha > 0.001:
				_draw_animation_frame(animation_texture, enemy.previous_animation_frame, art_size, tint, prior_alpha)
			_draw_animation_frame(animation_texture, enemy.animation_frame, art_size, tint, enemy.animation_blend)
		else:
			draw_texture_rect(fallback_texture, Rect2(-art_size * 0.5, art_size), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if enemy.hp / enemy.max_hp < 0.42 and enemy.data.size_class > 0:
		var damage_alpha := 0.35 + absf(sin(enemy.age * 12.0)) * 0.35
		for crack_index in 3:
			var crack_start := p + Vector2(-r * 0.35 + crack_index * r * 0.3, -r * 0.2 + crack_index * 4.0)
			draw_line(crack_start, crack_start + Vector2(5.0 - crack_index * 3.0, r * 0.48), Color(1.0, 0.48, 0.24, damage_alpha), 1.4)
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

func _draw_animation_frame(texture: Texture2D, frame: int, art_size: Vector2, tint: Color, alpha: float) -> void:
	var cell_size := Vector2(texture.get_width() * 0.5, texture.get_height() * 0.5)
	var source := Rect2(Vector2(float(frame % 2), float(frame / 2)) * cell_size, cell_size)
	var frame_tint := Color(tint.r, tint.g, tint.b, tint.a * alpha)
	draw_texture_rect_region(texture, Rect2(-art_size * 0.5, art_size), source, frame_tint)
