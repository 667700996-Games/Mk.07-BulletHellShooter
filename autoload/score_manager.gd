extends Node

signal score_changed(score: int)
signal combo_changed(combo: int, multiplier: float)
signal graze_changed(count: int)

var score := 0
var enemies_destroyed := 0
var graze := 0
var combo := 0
var max_combo := 0
var deaths := 0
var boss_bonus := 0
var combo_time := 0.0

func reset_run() -> void:
	score = 0
	enemies_destroyed = 0
	graze = 0
	combo = 0
	max_combo = 0
	deaths = 0
	boss_bonus = 0
	combo_time = 0.0

func tick(delta: float) -> void:
	if combo <= 0:
		return
	combo_time -= delta
	if combo_time <= 0.0:
		combo = maxi(0, combo - maxi(1, combo / 8))
		combo_time = 0.22 if combo > 0 else 0.0
		combo_changed.emit(combo, multiplier())

func register_kill(base_value: int, risk: float = 0.0) -> int:
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_time = 2.25
	enemies_destroyed += 1
	var gained := int(float(base_value) * multiplier() * (1.0 + clampf(risk, 0.0, 0.75)))
	add_score(gained)
	combo_changed.emit(combo, multiplier())
	return gained

func register_graze() -> void:
	graze += 1
	combo_time = maxf(combo_time, 1.25)
	add_score(20 + mini(combo, 200))
	graze_changed.emit(graze)

func register_death() -> void:
	deaths += 1
	combo = 0
	combo_time = 0.0
	combo_changed.emit(combo, multiplier())

func add_boss_bonus(value: int) -> void:
	boss_bonus += value
	add_score(value)

func add_score(value: int) -> void:
	score += maxi(0, value)
	score_changed.emit(score)

func multiplier() -> float:
	if combo >= 180: return 5.0
	if combo >= 100: return 3.0
	if combo >= 55: return 2.0
	if combo >= 28: return 1.5
	if combo >= 12: return 1.2
	return 1.0

func result(clear_time: float, cleared: bool) -> Dictionary:
	return {
		"score": score - boss_bonus,
		"enemies_destroyed": enemies_destroyed,
		"graze": graze,
		"max_combo": max_combo,
		"deaths": deaths,
		"clear_time": clear_time,
		"boss_bonus": boss_bonus,
		"total_score": score,
		"cleared": cleared
	}
