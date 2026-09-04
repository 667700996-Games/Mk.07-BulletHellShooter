extends Node

signal score_changed(score: int)
signal combo_changed(combo: int, multiplier: float)
signal graze_changed(count: int)
signal risk_reserve_changed(current: int, capacity: int)
signal risk_bank_committed(checkpoint_id: String, units: int, bonus: int)
signal risk_reserve_forfeited(reason: String, units: int)

# Route scoring converts optional close-range play into two bounded score
# decisions. Reserve is charged only by grazes, banked once at each boss gate,
# and forfeited by either defensive escape route. The low 60k maximum keeps it
# subordinate to combat execution and the 275k perfect medal stack.
const RISK_ROUTE_RULES := {
	"reserve_capacity": 40,
	"charge_per_graze": 1,
	"forfeit_on_death": true,
	"forfeit_on_barrier": true,
	"checkpoints": {
		"midboss": {"score_per_unit": 500, "closes_route": false},
		"final_boss": {"score_per_unit": 1000, "closes_route": true}
	}
}

# Performance medals are deliberately authored as data. A medal is evaluated
# once at the end of a run, so stacked goals cannot accidentally award the
# same bonus more than once and adding a future goal does not require another
# scoring branch.
const MEDAL_DEFINITIONS := [
	{
		"id": "no_miss",
		"title_key": "medal_no_miss",
		"description_key": "medal_no_miss_desc",
		"bonus": 100000,
		"requirements": {"cleared": true, "deaths_max": 0}
	},
	{
		"id": "no_barrier",
		"title_key": "medal_no_barrier",
		"description_key": "medal_no_barrier_desc",
		"bonus": 50000,
		"requirements": {"cleared": true, "barriers_max": 0}
	},
	{
		"id": "phase_perfect",
		"title_key": "medal_phase_perfect",
		"description_key": "medal_phase_perfect_desc",
		"bonus": 125000,
		"requirements": {"cleared": true, "all_boss_phases_on_time": true}
	}
]

var score := 0
var enemies_destroyed := 0
var graze := 0
var combo := 0
var max_combo := 0
var deaths := 0
var barriers_used := 0
var boss_bonus := 0
var combo_time := 0.0
var boss_phase_metrics: Array[Dictionary] = []
var risk_route_enabled := true
var risk_route_open := true
var risk_reserve := 0
var risk_reserve_peak := 0
var risk_reserve_lost := 0
var risk_bank_bonus := 0
var risk_bank_events: Array[Dictionary] = []
var _risk_banked_checkpoints := {}

func reset_run() -> void:
	score = 0
	enemies_destroyed = 0
	graze = 0
	combo = 0
	max_combo = 0
	deaths = 0
	barriers_used = 0
	boss_bonus = 0
	combo_time = 0.0
	boss_phase_metrics.clear()
	risk_route_enabled = true
	risk_route_open = true
	risk_reserve = 0
	risk_reserve_peak = 0
	risk_reserve_lost = 0
	risk_bank_bonus = 0
	risk_bank_events.clear()
	_risk_banked_checkpoints.clear()

func configure_route_scoring(enabled: bool) -> void:
	risk_route_enabled = enabled
	if not enabled:
		risk_route_open = false
		risk_reserve = 0

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
	_charge_risk_reserve()
	graze_changed.emit(graze)

func register_death() -> void:
	_forfeit_risk_reserve("death")
	deaths += 1
	combo = 0
	combo_time = 0.0
	combo_changed.emit(combo, multiplier())

func register_barrier() -> void:
	_forfeit_risk_reserve("barrier")
	barriers_used += 1

func _charge_risk_reserve() -> void:
	if not risk_route_enabled or not risk_route_open:
		return
	var capacity := int(RISK_ROUTE_RULES.reserve_capacity)
	var next_reserve := mini(capacity, risk_reserve + int(RISK_ROUTE_RULES.charge_per_graze))
	if next_reserve == risk_reserve:
		return
	risk_reserve = next_reserve
	risk_reserve_peak = maxi(risk_reserve_peak, risk_reserve)
	risk_reserve_changed.emit(risk_reserve, capacity)

func _forfeit_risk_reserve(reason: String) -> int:
	if not risk_route_enabled or risk_reserve <= 0:
		return 0
	if not bool(RISK_ROUTE_RULES.get("forfeit_on_%s" % reason, false)):
		return 0
	var lost := risk_reserve
	risk_reserve = 0
	risk_reserve_lost += lost
	risk_reserve_changed.emit(0, int(RISK_ROUTE_RULES.reserve_capacity))
	risk_reserve_forfeited.emit(reason, lost)
	return lost

func bank_risk_reserve(checkpoint_id: String) -> int:
	if not risk_route_enabled or not risk_route_open or _risk_banked_checkpoints.has(checkpoint_id):
		return 0
	var checkpoints: Dictionary = RISK_ROUTE_RULES.checkpoints
	var checkpoint: Dictionary = checkpoints.get(checkpoint_id, {})
	if checkpoint.is_empty():
		return 0
	_risk_banked_checkpoints[checkpoint_id] = true
	var units := risk_reserve
	risk_reserve = 0
	if bool(checkpoint.get("closes_route", false)):
		risk_route_open = false
	if units <= 0:
		return 0
	var score_per_unit := maxi(0, int(checkpoint.get("score_per_unit", 0)))
	var bonus := units * score_per_unit
	risk_bank_bonus += bonus
	risk_bank_events.append({
		"checkpoint_id": checkpoint_id,
		"units": units,
		"score_per_unit": score_per_unit,
		"bonus": bonus
	})
	add_score(bonus)
	risk_reserve_changed.emit(0, int(RISK_ROUTE_RULES.reserve_capacity))
	risk_bank_committed.emit(checkpoint_id, units, bonus)
	return bonus

func risk_route_rules() -> Dictionary:
	return RISK_ROUTE_RULES.duplicate(true)

func normalize_risk_bank_events(raw_events: Variant) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	if not raw_events is Array:
		return normalized
	var checkpoints: Dictionary = RISK_ROUTE_RULES.checkpoints
	var seen := {}
	for raw_event in raw_events:
		if not raw_event is Dictionary:
			continue
		var checkpoint_id := String((raw_event as Dictionary).get("checkpoint_id", ""))
		if seen.has(checkpoint_id) or not checkpoints.has(checkpoint_id):
			continue
		var units := clampi(int((raw_event as Dictionary).get("units", 0)), 0, int(RISK_ROUTE_RULES.reserve_capacity))
		if units <= 0:
			continue
		seen[checkpoint_id] = true
		var score_per_unit := maxi(0, int((checkpoints[checkpoint_id] as Dictionary).get("score_per_unit", 0)))
		normalized.append({
			"checkpoint_id": checkpoint_id,
			"units": units,
			"score_per_unit": score_per_unit,
			"bonus": units * score_per_unit
		})
	return normalized

func risk_bonus_for_events(raw_events: Variant) -> int:
	var total := 0
	for event in normalize_risk_bank_events(raw_events):
		total += int(event.bonus)
	return total

func register_boss_phase(boss_id: String, phase: int, phase_name: String, clear_time: float, entered_overdrive: bool) -> void:
	boss_phase_metrics.append({
		"boss_id": boss_id,
		"phase": phase,
		"phase_name": phase_name,
		"clear_time": clear_time,
		"overdrive": entered_overdrive
	})

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

func medal_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for definition in MEDAL_DEFINITIONS:
		definitions.append((definition as Dictionary).duplicate(true))
	return definitions

func medal_definition(medal_id: String) -> Dictionary:
	for definition in MEDAL_DEFINITIONS:
		if String(definition.get("id", "")) == medal_id:
			return (definition as Dictionary).duplicate(true)
	return {}

func normalize_medal_ids(raw_medals: Variant) -> Array[String]:
	var normalized: Array[String] = []
	if not raw_medals is Array and not raw_medals is PackedStringArray:
		return normalized
	for raw_medal in raw_medals:
		var medal_id := String(raw_medal)
		if not normalized.has(medal_id) and not medal_definition(medal_id).is_empty():
			normalized.append(medal_id)
	return normalized

func medal_bonus_for_ids(raw_medals: Variant) -> int:
	var total := 0
	for medal_id in normalize_medal_ids(raw_medals):
		total += int(medal_definition(medal_id).get("bonus", 0))
	return total

func evaluate_medals(run: Dictionary, expected_boss_phases: int) -> Array[String]:
	var earned: Array[String] = []
	for definition in MEDAL_DEFINITIONS:
		if _meets_medal_requirements(definition, run, expected_boss_phases):
			earned.append(String(definition.id))
	return earned

func _meets_medal_requirements(definition: Dictionary, run: Dictionary, expected_boss_phases: int) -> bool:
	var requirements: Dictionary = definition.get("requirements", {})
	for requirement in requirements:
		match String(requirement):
			"cleared":
				if bool(run.get("cleared", false)) != bool(requirements[requirement]):
					return false
			"deaths_max":
				if int(run.get("deaths", 0)) > int(requirements[requirement]):
					return false
			"barriers_max":
				if int(run.get("barriers_used", 0)) > int(requirements[requirement]):
					return false
			"all_boss_phases_on_time":
				if bool(requirements[requirement]) and not _all_boss_phases_on_time(run, expected_boss_phases):
					return false
			_:
				# Unknown requirement keys fail closed so an authoring typo can
				# never turn a medal into free score.
				return false
	return true

func _all_boss_phases_on_time(run: Dictionary, expected_boss_phases: int) -> bool:
	var raw_metrics: Variant = run.get("boss_phase_metrics", [])
	if expected_boss_phases <= 0 or not raw_metrics is Array:
		return false
	var metrics: Array = raw_metrics
	if metrics.size() != expected_boss_phases:
		return false
	for metric in metrics:
		if not metric is Dictionary or bool((metric as Dictionary).get("overdrive", true)):
			return false
	return true

func result(clear_time: float, cleared: bool, expected_boss_phases: int = 0, award_medals: bool = true) -> Dictionary:
	var base_result := {
		"score": score - boss_bonus - risk_bank_bonus,
		"enemies_destroyed": enemies_destroyed,
		"graze": graze,
		"max_combo": max_combo,
		"deaths": deaths,
		"barriers_used": barriers_used,
		"clear_time": clear_time,
		"boss_bonus": boss_bonus,
		"risk_bank_bonus": risk_bank_bonus,
		"risk_bank_events": risk_bank_events.duplicate(true),
		"risk_reserve_peak": risk_reserve_peak,
		"risk_reserve_lost": risk_reserve_lost,
		"risk_reserve_unbanked": risk_reserve,
		"boss_phase_metrics": boss_phase_metrics.duplicate(true),
		"cleared": cleared
	}
	var medals: Array[String] = []
	if award_medals:
		medals = evaluate_medals(base_result, expected_boss_phases)
	var medal_bonus := medal_bonus_for_ids(medals)
	base_result["medals"] = medals
	base_result["medal_bonus"] = medal_bonus
	base_result["total_score"] = score + medal_bonus
	return base_result
