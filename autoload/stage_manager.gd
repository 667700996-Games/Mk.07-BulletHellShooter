extends Node

signal stage_started(stage_id: String)
signal section_changed(section: String)
signal stage_finished(stage_id: String, cleared: bool, time: float)

const DEFAULT_STAGE_ID := "neon_district_01"
const STAGE_CATALOG: Array[StageData] = [
	preload("res://resources/neon_district_stage.tres") as StageData,
	preload("res://resources/null_tempest_stage.tres") as StageData,
	preload("res://resources/helios_forge_stage.tres") as StageData
]

var active_stage := ""
var active_stage_data: StageData
var elapsed := 0.0
var section := "idle"
var timeline: StageTimelineData
var _stages_by_id: Dictionary = {}
var _ordered_stage_ids := PackedStringArray()
var _catalog_initialized := false

func _ready() -> void:
	_ensure_catalog()

func default_stage() -> StageData:
	_ensure_catalog()
	return stage(DEFAULT_STAGE_ID)

func stage(stage_id: String) -> StageData:
	_ensure_catalog()
	return _stages_by_id.get(stage_id) as StageData

func stage_ids() -> PackedStringArray:
	_ensure_catalog()
	return _ordered_stage_ids.duplicate()

func has_stage(stage_id: String) -> bool:
	_ensure_catalog()
	return _stages_by_id.has(stage_id)

func begin_stage(data: StageData) -> void:
	if data == null:
		push_error("StageManager.begin_stage received null StageData")
		return
	var errors := data.validation_errors()
	if not errors.is_empty():
		push_error("StageManager rejected invalid stage '%s': %s" % [data.stage_id, "; ".join(errors)])
		return
	_begin_runtime(data.stage_id, data.timeline, data)

func begin(stage_id: String, stage_timeline: StageTimelineData = null) -> void:
	_ensure_catalog()
	var catalog_stage := stage(stage_id)
	var resolved_timeline := stage_timeline
	if resolved_timeline == null and catalog_stage != null:
		resolved_timeline = catalog_stage.timeline
	_begin_runtime(stage_id, resolved_timeline, catalog_stage)

func _begin_runtime(stage_id: String, stage_timeline: StageTimelineData, data: StageData) -> void:
	active_stage = stage_id
	active_stage_data = data
	timeline = stage_timeline
	elapsed = 0.0
	section = "intro"
	stage_started.emit(active_stage)
	section_changed.emit(section)

func update_time(value: float, midboss_cleared: bool = false) -> void:
	elapsed = value
	var next_section := timeline.section_for_time(value, midboss_cleared) if timeline != null else _fallback_section_for_time(value)
	if next_section != section:
		section = next_section
		section_changed.emit(section)

func update_elapsed(value: float) -> void:
	elapsed = value

func set_section(value: String) -> void:
	if value == section:
		return
	section = value
	section_changed.emit(section)

func finish(cleared: bool) -> void:
	stage_finished.emit(active_stage, cleared, elapsed)
	active_stage = ""
	active_stage_data = null
	section = "idle"
	timeline = null

func _ensure_catalog() -> void:
	if _catalog_initialized:
		return
	_catalog_initialized = true
	_stages_by_id.clear()
	_ordered_stage_ids.clear()
	for data in STAGE_CATALOG:
		if data == null:
			push_error("StageManager catalog contains a null stage resource")
			continue
		var errors := data.validation_errors()
		if _stages_by_id.has(data.stage_id):
			errors.append("duplicate stage_id")
		if not errors.is_empty():
			push_error("Invalid StageData '%s': %s" % [data.stage_id, "; ".join(errors)])
			continue
		_stages_by_id[data.stage_id] = data
		_ordered_stage_ids.append(data.stage_id)
	if not _stages_by_id.has(DEFAULT_STAGE_ID):
		push_error("StageManager default stage '%s' is missing or invalid" % DEFAULT_STAGE_ID)

func _fallback_section_for_time(value: float) -> String:
	if value < 5.0: return "intro"
	if value < 60.0: return "opening_waves"
	if value < 90.0: return "mixed_formations"
	if value < 135.0: return "post_midboss"
	if value < 174.0: return "elite_escalation"
	if value < 180.0: return "final_warning"
	return "final_boss"
