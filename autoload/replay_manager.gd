extends Node

const REPLAY_PATH := "user://psychic_vector_last_replay.json"
const REPLAY_BACKUP_PATH := "user://psychic_vector_last_replay.backup.json"
const REPLAY_STAGING_PATH := "user://psychic_vector_last_replay.pending.json"
const FORMAT_VERSION := 1
const CONTENT_VERSION := 1
const FRAME_STRIDE := 4
const MAX_FRAMES := 90000
const MIN_DELTA_US := 1000
const MAX_DELTA_US := 250000
const AXIS_SCALE := 32767
const MASK_PRIMARY := 1
const MASK_FOCUS := 2
const MASK_BARRIER := 4

var last_replay: Dictionary = {}
var persistence_enabled := true

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke") or argument.begins_with("--benchmark") or argument.begins_with("--capture"):
			persistence_enabled = false
			break
	if persistence_enabled:
		last_replay = load_best_replay(REPLAY_PATH, REPLAY_BACKUP_PATH)

func has_replay() -> bool:
	return not last_replay.is_empty()

func build_replay(character_index: int, difficulty_id: String, assisted: bool, seed_value: int, frame_stream: Array, result: Dictionary) -> Dictionary:
	var raw := {
		"format_version": FORMAT_VERSION,
		"content_version": CONTENT_VERSION,
		"character": character_index,
		"difficulty": difficulty_id,
		"assisted": assisted,
		"seed": seed_value,
		"frames": frame_stream,
		"expected": {
			"cleared": bool(result.get("cleared", false)),
			"total_score": int(result.get("total_score", 0)),
			"deaths": int(result.get("deaths", 0)),
			"barriers_used": int(result.get("barriers_used", 0)),
			"clear_time_ms": roundi(float(result.get("clear_time", 0.0)) * 1000.0),
			"boss_phases": (result.get("boss_phase_metrics", []) as Array).size()
		}
	}
	var replay := _prepare_replay(raw)
	if replay.is_empty():
		return {}
	replay["checksum"] = _checksum(replay)
	return replay

func save_replay(replay: Dictionary) -> bool:
	if not persistence_enabled:
		return false
	var verified := _verify_replay(replay)
	if verified.is_empty():
		return false
	var error := write_replay_transaction(verified, REPLAY_PATH, REPLAY_BACKUP_PATH, REPLAY_STAGING_PATH)
	if error != OK:
		push_warning("Could not save replay safely: %s" % error_string(error))
		return false
	last_replay = verified
	return true

func load_best_replay(primary_path: String, backup_path: String) -> Dictionary:
	var primary := _load_replay(primary_path)
	if not primary.is_empty():
		return primary
	return _load_replay(backup_path)

func write_replay_transaction(replay: Dictionary, primary_path: String, backup_path: String, staging_path: String) -> Error:
	var verified := _verify_replay(replay)
	if verified.is_empty():
		return ERR_FILE_CORRUPT
	_remove_file(staging_path)
	var error := _write_replay(staging_path, verified)
	if error != OK or _load_replay(staging_path).is_empty():
		_remove_file(staging_path)
		return error if error != OK else ERR_FILE_CORRUPT

	var current := _load_replay(primary_path)
	if not current.is_empty():
		error = _write_replay(backup_path, current)
		if error != OK or _load_replay(backup_path).is_empty():
			_remove_file(staging_path)
			return error if error != OK else ERR_FILE_CORRUPT
	if FileAccess.file_exists(primary_path):
		error = _remove_file(primary_path)
		if error != OK:
			_remove_file(staging_path)
			return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(staging_path), ProjectSettings.globalize_path(primary_path))
	if error != OK:
		_remove_file(staging_path)
		if not current.is_empty():
			_write_replay(primary_path, current)
		return error
	if _load_replay(backup_path).is_empty():
		error = _write_replay(backup_path, verified)
		if error != OK or _load_replay(backup_path).is_empty():
			return error if error != OK else ERR_FILE_CORRUPT
	return OK

func matches_expected(result: Dictionary, replay: Dictionary) -> bool:
	var expected: Dictionary = replay.get("expected", {})
	if expected.is_empty():
		return false
	return (
		bool(result.get("cleared", false)) == bool(expected.get("cleared", false))
		and int(result.get("total_score", 0)) == int(expected.get("total_score", -1))
		and int(result.get("deaths", 0)) == int(expected.get("deaths", -1))
		and int(result.get("barriers_used", 0)) == int(expected.get("barriers_used", -1))
		and (result.get("boss_phase_metrics", []) as Array).size() == int(expected.get("boss_phases", -1))
		and absi(roundi(float(result.get("clear_time", 0.0)) * 1000.0) - int(expected.get("clear_time_ms", -1000000))) <= 2
	)

func _prepare_replay(raw: Dictionary) -> Dictionary:
	if int(raw.get("format_version", 0)) != FORMAT_VERSION or int(raw.get("content_version", 0)) != CONTENT_VERSION:
		return {}
	var character_index := int(raw.get("character", -1))
	var difficulty_id := String(raw.get("difficulty", ""))
	var seed_value := int(raw.get("seed", 0))
	if character_index < 0 or character_index >= GameManager.CHARACTERS.size() or not GameManager.DIFFICULTY_ORDER.has(difficulty_id) or seed_value <= 0:
		return {}
	var raw_frames: Variant = raw.get("frames", [])
	if not raw_frames is Array or raw_frames.is_empty() or raw_frames.size() % FRAME_STRIDE != 0:
		return {}
	if raw_frames.size() / FRAME_STRIDE > MAX_FRAMES:
		return {}
	var frames: Array[int] = []
	frames.resize(raw_frames.size())
	for offset in range(0, raw_frames.size(), FRAME_STRIDE):
		var delta_us := int(raw_frames[offset])
		var axis_x := int(raw_frames[offset + 1])
		var axis_y := int(raw_frames[offset + 2])
		var mask := int(raw_frames[offset + 3])
		if delta_us < MIN_DELTA_US or delta_us > MAX_DELTA_US or absi(axis_x) > AXIS_SCALE or absi(axis_y) > AXIS_SCALE or mask < 0 or mask > 7:
			return {}
		frames[offset] = delta_us
		frames[offset + 1] = axis_x
		frames[offset + 2] = axis_y
		frames[offset + 3] = mask
	var raw_expected: Variant = raw.get("expected", {})
	if not raw_expected is Dictionary:
		return {}
	var expected := {
		"cleared": bool(raw_expected.get("cleared", false)),
		"total_score": maxi(0, int(raw_expected.get("total_score", 0))),
		"deaths": clampi(int(raw_expected.get("deaths", 0)), 0, 99),
		"barriers_used": clampi(int(raw_expected.get("barriers_used", 0)), 0, 999),
		"clear_time_ms": clampi(int(raw_expected.get("clear_time_ms", 0)), 0, 7200000),
		"boss_phases": clampi(int(raw_expected.get("boss_phases", 0)), 0, 8)
	}
	return {
		"format_version": FORMAT_VERSION,
		"content_version": CONTENT_VERSION,
		"character": character_index,
		"difficulty": difficulty_id,
		"assisted": bool(raw.get("assisted", false)),
		"seed": seed_value,
		"frames": frames,
		"expected": expected
	}

func _verify_replay(raw: Dictionary) -> Dictionary:
	var replay := _prepare_replay(raw)
	if replay.is_empty():
		return {}
	var expected_checksum := String(raw.get("checksum", ""))
	if expected_checksum.is_empty() or expected_checksum != _checksum(replay):
		return {}
	replay["checksum"] = expected_checksum
	return replay

func _checksum(replay: Dictionary) -> String:
	return JSON.stringify([
		int(replay.get("format_version", 0)), int(replay.get("content_version", 0)),
		int(replay.get("character", -1)), String(replay.get("difficulty", "")),
		bool(replay.get("assisted", false)), int(replay.get("seed", 0)),
		replay.get("frames", []), replay.get("expected", {})
	]).sha256_text()

func _load_replay(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	return _verify_replay(parsed)

func _write_replay(path: String, replay: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(replay))
	file.close()
	return OK

func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
