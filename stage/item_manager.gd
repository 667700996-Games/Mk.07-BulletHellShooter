class_name ItemManager
extends Node2D

signal power_collected(position: Vector2)

var items: Array[Dictionary] = []

func spawn_power(position: Vector2) -> void:
	items.append({"p": position, "v": Vector2(0, 42), "age": 0.0, "phase": float(items.size()) * 1.77})
	queue_redraw()

func update_items(delta: float, player_position: Vector2) -> void:
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		item.age += delta
		item.v.y = minf(125.0, item.v.y + delta * 35.0)
		if item.p.distance_to(player_position) < 115.0:
			var attraction: Vector2 = item.p.direction_to(player_position)
			item.v = item.v.lerp(attraction * 420.0, 1.0 - exp(-delta * 8.0))
		item.p += item.v * delta
		if item.p.distance_to(player_position) < 18.0:
			power_collected.emit(item.p)
			items.remove_at(i)
			continue
		if item.p.y > 1010.0:
			items.remove_at(i)
			continue
		items[i] = item
	queue_redraw()

func clear() -> void:
	items.clear()
	queue_redraw()

func _draw() -> void:
	for item in items:
		var p: Vector2 = item.p
		var pulse := 1.0 + sin(item.age * 7.0 + item.phase) * 0.12
		draw_circle(p, 14.0 * pulse, Color(0.35,0.55,1.0,0.12))
		draw_colored_polygon(PackedVector2Array([p+Vector2(0,-9),p+Vector2(8,0),p+Vector2(0,9),p+Vector2(-8,0)]),Color("57dfff"))
		draw_string(ThemeDB.fallback_font,p+Vector2(-4,5),"P",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("07112b"))
