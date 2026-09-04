extends Node

const REPLAY_PATH := "user://psychic_vector_last_replay.json"
const REPLAY_BACKUP_PATH := "user://psychic_vector_last_replay.backup.json"
const REPLAY_STAGING_PATH := "user://psychic_vector_last_replay.pending.json"
const REPLAY_DIRECTORY := "user://psychic_vector_replays"
const STORAGE_VERSION := 1
const MAX_REPLAYS := 12
const MAX_PINNED_REPLAYS := 3
const FORMAT_VERSION := 4
const MIN_SUPPORTED_FORMAT_VERSION := 1
const CONTENT_VERSION := 1
const LEGACY_DEFAULT_STAGE_ID := "neon_district_01"
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
var _replay_entries: Array[Dictionary] = []
var _active_replay_directory := REPLAY_DIRECTORY

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke") or argument.begins_with("--benchmark") or argument.begins_with("--capture"):
			persistence_enabled = false
			break
	if persistence_enabled:
		_load_replay_library(_active_replay_directory)
		_migrate_legacy_replays()
		_enforce_library_limits(true)
	_refresh_last_replay()

func has_replay() -> bool:
	return not last_replay.is_empty()

func list_replays(difficulty_id: String = "", stage_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries := _replay_entries.duplicate()
	var fallback := _last_replay_entry()
	if not fallback.is_empty() and _find_entry(String(fallback.get("id", ""))).is_empty():
		entries.append(fallback)
		entries.sort_custom(_entry_is_newer)
	for entry in entries:
		var replay: Dictionary = entry.get("replay", {})
		if not difficulty_id.is_empty() and String(replay.get("difficulty", "")) != difficulty_id:
			continue
		if not stage_id.is_empty() and String(replay.get("stage_id", LEGACY_DEFAULT_STAGE_ID)) != stage_id:
			continue
		result.append(_public_entry(entry))
	return result

func replay_by_id(id: String) -> Dictionary:
	var entry := _find_entry(id)
	if entry.is_empty():
		var fallback := _last_replay_entry()
		if String(fallback.get("id", "")) == id:
			entry = fallback
	if entry.is_empty() or not bool(entry.get("is_compatible", false)):
		return {}
	return (entry.get("replay", {}) as Dictionary).duplicate(true)

func latest_id() -> String:
	var fallback := _last_replay_entry()
	if not fallback.is_empty() and _find_entry(String(fallback.get("id", ""))).is_empty():
		return String(fallback.get("id", ""))
	for entry in _replay_entries:
		if bool(entry.get("is_compatible", false)):
			return String(entry.get("id", ""))
	return String(_last_replay_entry().get("id", ""))

func replay_count() -> int:
	var count := _replay_entries.size()
	var fallback := _last_replay_entry()
	if not fallback.is_empty() and _find_entry(String(fallback.get("id", ""))).is_empty():
		count += 1
	return count

func is_compatible(entry_or_replay: Dictionary) -> bool:
	if entry_or_replay.has("is_compatible"):
		return bool(entry_or_replay.get("is_compatible", false))
	if entry_or_replay.has("compatible"):
		return bool(entry_or_replay.get("compatible", false))
	if entry_or_replay.has("replay"):
		var nested: Variant = entry_or_replay.get("replay", {})
		return nested is Dictionary and _is_replay_compatible(nested)
	return _is_replay_compatible(entry_or_replay)

func set_pinned(id: String, pinned: bool) -> bool:
	var entry_index := _find_entry_index(id)
	if entry_index < 0:
		return false
	var current: Dictionary = _replay_entries[entry_index]
	if bool(current.get("pinned", false)) == pinned:
		return true
	if pinned and _pinned_count() >= MAX_PINNED_REPLAYS:
		return false
	var updated := current.duplicate(true)
	updated["pinned"] = pinned
	updated = _verify_entry_envelope(updated)
	if updated.is_empty():
		return false
	if persistence_enabled:
		var error := _write_entry_transaction(updated, _active_replay_directory)
		if error != OK:
			push_warning("Could not update replay pin: %s" % error_string(error))
			return false
	_replay_entries[entry_index] = updated
	return true

func build_replay(character_index: int, difficulty_id: String, assisted: bool, seed_value: int, frame_stream: Array, result: Dictionary, stage_id: String = LEGACY_DEFAULT_STAGE_ID) -> Dictionary:
	var raw := {
		"format_version": FORMAT_VERSION,
		"content_version": CONTENT_VERSION,
		"stage_id": stage_id,
		"character": character_index,
		"difficulty": difficulty_id,
		"assisted": assisted,
		"seed": seed_value,
		"frames": frame_stream,
		"expected": {
			"cleared": bool(result.get("cleared", false)),
			"total_score": int(result.get("total_score", 0)),
			"medal_bonus": int(result.get("medal_bonus", 0)),
			"risk_bank_bonus": int(result.get("risk_bank_bonus", 0)),
			"risk_bank_units": _risk_bank_units(result.get("risk_bank_events", [])),
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
	var verified := _verify_replay(replay)
	if verified.is_empty():
		return false
	var id := String(verified.get("checksum", ""))
	var existing_index := _find_entry_index(id)
	if existing_index >= 0:
		var refreshed: Dictionary = _replay_entries[existing_index].duplicate(true)
		refreshed["created_unix"] = _next_created_unix()
		if persistence_enabled:
			var refresh_error := _write_entry_transaction(refreshed, _active_replay_directory)
			if refresh_error != OK:
				push_warning("Could not refresh replay metadata: %s" % error_string(refresh_error))
				return false
		_replay_entries[existing_index] = refreshed
		_sort_entries()
		_refresh_last_replay()
		return true
	var entry := _make_entry(verified, _next_created_unix(), false)
	entry = _verify_entry_envelope(entry)
	if entry.is_empty():
		return false
	if persistence_enabled:
		var error := _write_entry_transaction(entry, _active_replay_directory)
		if error != OK:
			push_warning("Could not save replay safely: %s" % error_string(error))
			return false
	_replay_entries.append(entry)
	_sort_entries()
	_enforce_library_limits(persistence_enabled)
	_refresh_last_replay()
	return not _find_entry(id).is_empty()

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
	var replay_format := int(replay.get("format_version", 0))
	var result_total := int(result.get("total_score", 0))
	var result_medal_bonus := maxi(0, int(result.get("medal_bonus", 0)))
	var result_risk_bank_bonus := maxi(0, int(result.get("risk_bank_bonus", 0)))
	var result_risk_bank_units := _risk_bank_units(result.get("risk_bank_events", []))
	# Format 3 recorded medal bonuses but predates route-risk banking.
	if replay_format < 4:
		result_total = maxi(0, result_total - result_risk_bank_bonus)
	# Formats 1-2 recorded totals before operation medals existed. Compare their
	# original combat total so archived input streams remain verifiable.
	if replay_format < 3:
		result_total = maxi(0, result_total - result_medal_bonus)
	return (
		String(result.get("stage_id", LEGACY_DEFAULT_STAGE_ID)) == String(replay.get("stage_id", LEGACY_DEFAULT_STAGE_ID))
		and bool(result.get("cleared", false)) == bool(expected.get("cleared", false))
		and result_total == int(expected.get("total_score", -1))
		and (replay_format < 3 or result_medal_bonus == int(expected.get("medal_bonus", -1)))
		and (replay_format < 4 or result_risk_bank_bonus == int(expected.get("risk_bank_bonus", -1)))
		and (replay_format < 4 or result_risk_bank_units == expected.get("risk_bank_units", []))
		and int(result.get("deaths", 0)) == int(expected.get("deaths", -1))
		and int(result.get("barriers_used", 0)) == int(expected.get("barriers_used", -1))
		and (result.get("boss_phase_metrics", []) as Array).size() == int(expected.get("boss_phases", -1))
		and absi(roundi(float(result.get("clear_time", 0.0)) * 1000.0) - int(expected.get("clear_time_ms", -1000000))) <= 2
	)

func clear_memory_library() -> void:
	_replay_entries.clear()
	last_replay = {}

func _risk_bank_units(raw_events: Variant) -> Array[int]:
	var units: Array[int] = [0, 0]
	if not raw_events is Array:
		return units
	for raw_event in raw_events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var slot := 0 if String(event.get("checkpoint_id", "")) == "midboss" else (1 if String(event.get("checkpoint_id", "")) == "final_boss" else -1)
		if slot >= 0:
			units[slot] = clampi(int(event.get("units", 0)), 0, 40)
	return units

func _make_entry(replay: Dictionary, created_unix: int, pinned: bool) -> Dictionary:
	var verified := _verify_replay(replay)
	if verified.is_empty():
		return {}
	var id := String(verified.get("checksum", ""))
	return _verify_entry_envelope({
		"storage_version": STORAGE_VERSION,
		"id": id,
		"created_unix": maxi(1, created_unix),
		"pinned": pinned,
		"replay": verified
	})

func _last_replay_entry() -> Dictionary:
	var verified := _verify_replay(last_replay)
	if verified.is_empty():
		return {}
	return _make_entry(verified, int(Time.get_unix_time_from_system()), false)

func _next_created_unix() -> int:
	var created_unix := int(Time.get_unix_time_from_system())
	if not _replay_entries.is_empty():
		created_unix = maxi(created_unix, int(_replay_entries[0].get("created_unix", 0)) + 1)
	return created_unix

func _public_entry(entry: Dictionary) -> Dictionary:
	return entry.duplicate(true)

func _is_replay_compatible(replay: Dictionary) -> bool:
	var verified := _verify_replay(replay)
	return not verified.is_empty() and _stage_is_available(String(verified.get("stage_id", "")))

func _verify_entry_envelope(raw: Dictionary) -> Dictionary:
	if int(raw.get("storage_version", 0)) != STORAGE_VERSION:
		return {}
	var id := String(raw.get("id", ""))
	if not _is_checksum_id(id):
		return {}
	var created_unix := int(raw.get("created_unix", 0))
	if created_unix <= 0 or typeof(raw.get("pinned", null)) != TYPE_BOOL:
		return {}
	var replay_value: Variant = raw.get("replay", {})
	if not replay_value is Dictionary:
		return {}
	var replay: Dictionary = replay_value
	var expected_value: Variant = replay.get("expected", {})
	if not expected_value is Dictionary:
		return {}
	var replay_checksum := String(replay.get("checksum", ""))
	if replay_checksum != id or replay_checksum != _checksum(replay):
		return {}

	var replay_format := int(replay.get("format_version", 0))
	var compatible := (
		replay_format >= MIN_SUPPORTED_FORMAT_VERSION
		and replay_format <= FORMAT_VERSION
		and int(replay.get("content_version", 0)) == CONTENT_VERSION
	)
	var normalized_replay: Dictionary
	if compatible:
		normalized_replay = _verify_replay(replay)
		if normalized_replay.is_empty():
			return {}
		compatible = _stage_is_available(String(normalized_replay.get("stage_id", "")))
	else:
		normalized_replay = replay.duplicate(true)
	return {
		"storage_version": STORAGE_VERSION,
		"id": id,
		"created_unix": created_unix,
		"pinned": bool(raw.get("pinned", false)),
		"is_compatible": compatible,
		"compatible": compatible,
		"replay": normalized_replay
	}

func _is_checksum_id(id: String) -> bool:
	if id.length() != 64:
		return false
	const HEX_DIGITS := "0123456789abcdef"
	for character in id:
		if HEX_DIGITS.find(character) < 0:
			return false
	return true

func _load_replay_library(directory_path: String) -> void:
	_replay_entries.clear()
	if _ensure_replay_directory(directory_path) != OK:
		return
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	var file_names: Array[String] = []
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir():
			file_names.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	_recover_entry_transactions(directory_path, file_names)

	directory = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	file_name = directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".json"):
			var entry := _load_entry_file(directory_path.path_join(file_name))
			if not entry.is_empty():
				_insert_loaded_entry(entry)
		file_name = directory.get_next()
	directory.list_dir_end()
	_sort_entries()

func _recover_entry_transactions(directory_path: String, file_names: Array[String]) -> void:
	var transaction_ids: Dictionary = {}
	for file_name in file_names:
		var suffix := ""
		if file_name.ends_with(".pending"):
			suffix = ".pending"
		elif file_name.ends_with(".backup"):
			suffix = ".backup"
		if suffix.is_empty():
			continue
		var id := file_name.substr(0, file_name.length() - suffix.length())
		if _is_checksum_id(id):
			transaction_ids[id] = true
	for id_value in transaction_ids.keys():
		var id := String(id_value)
		var target_path := directory_path.path_join("%s.json" % id)
		var pending_path := directory_path.path_join("%s.pending" % id)
		var backup_path := directory_path.path_join("%s.backup" % id)
		var target := _load_entry_file(target_path)
		if not target.is_empty():
			_remove_file(pending_path)
			_remove_file(backup_path)
			continue
		var pending := _load_entry_file(pending_path)
		if not pending.is_empty():
			_remove_file(target_path)
			var promote_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_path), ProjectSettings.globalize_path(target_path))
			if promote_error == OK and not _load_entry_file(target_path).is_empty():
				_remove_file(backup_path)
				continue
		var backup := _load_entry_file(backup_path)
		if not backup.is_empty():
			_remove_file(target_path)
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(target_path))
		_remove_file(pending_path)

func _insert_loaded_entry(entry: Dictionary) -> void:
	var existing_index := _find_entry_index(String(entry.get("id", "")))
	if existing_index < 0:
		_replay_entries.append(entry)
		return
	var existing: Dictionary = _replay_entries[existing_index]
	if _entry_is_newer(entry, existing):
		_replay_entries[existing_index] = entry

func _migrate_legacy_replays() -> void:
	var legacy_paths: Array[String] = [REPLAY_PATH, REPLAY_BACKUP_PATH]
	for path in legacy_paths:
		var replay := _load_replay(path)
		if replay.is_empty():
			continue
		var id := String(replay.get("checksum", ""))
		if not _find_entry(id).is_empty():
			continue
		var created_unix := int(FileAccess.get_modified_time(path))
		if created_unix <= 0:
			created_unix = int(Time.get_unix_time_from_system())
		var entry := _make_entry(replay, created_unix, false)
		if entry.is_empty():
			continue
		var error := _write_entry_transaction(entry, _active_replay_directory)
		if error != OK:
			push_warning("Could not migrate legacy replay: %s" % error_string(error))
			continue
		_replay_entries.append(entry)
	_sort_entries()

func _ensure_replay_directory(directory_path: String) -> Error:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))

func _write_entry_transaction(entry: Dictionary, directory_path: String) -> Error:
	var verified := _verify_entry_envelope(entry)
	if verified.is_empty():
		return ERR_FILE_CORRUPT
	var error := _ensure_replay_directory(directory_path)
	if error != OK:
		return error
	var id := String(verified.get("id", ""))
	var target_path := directory_path.path_join("%s.json" % id)
	var pending_path := directory_path.path_join("%s.pending" % id)
	var backup_path := directory_path.path_join("%s.backup" % id)
	_remove_file(pending_path)
	error = _write_entry_file(pending_path, verified)
	var pending := _load_entry_file(pending_path)
	if error != OK or pending.is_empty() or not _entries_match_metadata(pending, verified):
		_remove_file(pending_path)
		return error if error != OK else ERR_FILE_CORRUPT

	if FileAccess.file_exists(backup_path):
		error = _remove_file(backup_path)
		if error != OK:
			_remove_file(pending_path)
			return error
	if FileAccess.file_exists(target_path):
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(target_path), ProjectSettings.globalize_path(backup_path))
		if error != OK:
			_remove_file(pending_path)
			return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_path), ProjectSettings.globalize_path(target_path))
	if error != OK:
		_restore_entry_backup(target_path, backup_path)
		return error
	var promoted := _load_entry_file(target_path)
	if promoted.is_empty() or not _entries_match_metadata(promoted, verified):
		_restore_entry_backup(target_path, backup_path)
		return ERR_FILE_CORRUPT
	_remove_file(backup_path)
	return OK

func _restore_entry_backup(target_path: String, backup_path: String) -> void:
	if not FileAccess.file_exists(backup_path):
		return
	_remove_file(target_path)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(target_path))

func _entries_match_metadata(left: Dictionary, right: Dictionary) -> bool:
	return (
		String(left.get("id", "")) == String(right.get("id", ""))
		and int(left.get("created_unix", 0)) == int(right.get("created_unix", 0))
		and bool(left.get("pinned", false)) == bool(right.get("pinned", false))
	)

func _load_entry_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {}
	return _verify_entry_envelope(parsed)

func _write_entry_file(path: String, entry: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(entry))
	file.flush()
	file.close()
	return OK

func _enforce_library_limits(write_changes: bool) -> void:
	_sort_entries()
	var pinned_seen := 0
	for index in range(_replay_entries.size()):
		var entry: Dictionary = _replay_entries[index]
		if not bool(entry.get("pinned", false)):
			continue
		pinned_seen += 1
		if pinned_seen <= MAX_PINNED_REPLAYS:
			continue
		var unpinned := entry.duplicate(true)
		unpinned["pinned"] = false
		if write_changes:
			var pin_error := _write_entry_transaction(unpinned, _active_replay_directory)
			if pin_error != OK:
				push_warning("Could not normalize replay pin limit: %s" % error_string(pin_error))
				continue
		_replay_entries[index] = unpinned

	while _replay_entries.size() > MAX_REPLAYS:
		var victim_index := -1
		for index in range(_replay_entries.size() - 1, -1, -1):
			if not bool(_replay_entries[index].get("pinned", false)):
				victim_index = index
				break
		if victim_index < 0:
			break
		var victim: Dictionary = _replay_entries[victim_index]
		if write_changes:
			var victim_path := _active_replay_directory.path_join("%s.json" % String(victim.get("id", "")))
			var remove_error := _remove_file(victim_path)
			if remove_error != OK:
				push_warning("Could not evict old replay: %s" % error_string(remove_error))
		_replay_entries.remove_at(victim_index)

func _refresh_last_replay() -> void:
	last_replay = {}
	for entry in _replay_entries:
		if bool(entry.get("is_compatible", false)):
			last_replay = (entry.get("replay", {}) as Dictionary).duplicate(true)
			return

func _sort_entries() -> void:
	_replay_entries.sort_custom(_entry_is_newer)

func _entry_is_newer(left: Dictionary, right: Dictionary) -> bool:
	var left_created := int(left.get("created_unix", 0))
	var right_created := int(right.get("created_unix", 0))
	if left_created != right_created:
		return left_created > right_created
	return String(left.get("id", "")) < String(right.get("id", ""))

func _find_entry(id: String) -> Dictionary:
	var index := _find_entry_index(id)
	return _replay_entries[index] if index >= 0 else {}

func _find_entry_index(id: String) -> int:
	for index in range(_replay_entries.size()):
		if String(_replay_entries[index].get("id", "")) == id:
			return index
	return -1

func _pinned_count() -> int:
	var count := 0
	for entry in _replay_entries:
		if bool(entry.get("pinned", false)):
			count += 1
	return count

func _prepare_replay(raw: Dictionary) -> Dictionary:
	var replay_format := int(raw.get("format_version", 0))
	if replay_format < MIN_SUPPORTED_FORMAT_VERSION or replay_format > FORMAT_VERSION or int(raw.get("content_version", 0)) != CONTENT_VERSION:
		return {}
	var stage_id := LEGACY_DEFAULT_STAGE_ID if replay_format == 1 else String(raw.get("stage_id", ""))
	if not _is_stage_id(stage_id):
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
	var risk_bank_units: Array[int] = [0, 0]
	if replay_format >= 4:
		var raw_risk_units: Variant = raw_expected.get("risk_bank_units", [])
		if not raw_risk_units is Array or raw_risk_units.size() != 2:
			return {}
		risk_bank_units = [clampi(int(raw_risk_units[0]), 0, 40), clampi(int(raw_risk_units[1]), 0, 40)]
	var expected := {
		"cleared": bool(raw_expected.get("cleared", false)),
		"total_score": maxi(0, int(raw_expected.get("total_score", 0))),
		"medal_bonus": maxi(0, int(raw_expected.get("medal_bonus", 0))) if replay_format >= 3 else 0,
		"risk_bank_bonus": maxi(0, int(raw_expected.get("risk_bank_bonus", 0))) if replay_format >= 4 else 0,
		"risk_bank_units": risk_bank_units,
		"deaths": clampi(int(raw_expected.get("deaths", 0)), 0, 99),
		"barriers_used": clampi(int(raw_expected.get("barriers_used", 0)), 0, 999),
		"clear_time_ms": clampi(int(raw_expected.get("clear_time_ms", 0)), 0, 7200000),
		"boss_phases": clampi(int(raw_expected.get("boss_phases", 0)), 0, 64)
	}
	return {
		"format_version": replay_format,
		"content_version": CONTENT_VERSION,
		"stage_id": stage_id,
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
	var expected: Dictionary = replay.get("expected", {})
	# JSON parses every number as a float. Canonicalizing the packed input back to
	# integers keeps a replay's ID stable across an actual disk round trip.
	var canonical_frames: Array[int] = []
	var raw_frames: Variant = replay.get("frames", [])
	if raw_frames is Array:
		canonical_frames.resize(raw_frames.size())
		for index in raw_frames.size():
			canonical_frames[index] = int(raw_frames[index])
	var canonical := [
		int(replay.get("format_version", 0)), int(replay.get("content_version", 0)),
		int(replay.get("character", -1)), String(replay.get("difficulty", "")),
		bool(replay.get("assisted", false)), int(replay.get("seed", 0)),
		canonical_frames,
		bool(expected.get("cleared", false)), int(expected.get("total_score", 0)),
		int(expected.get("deaths", 0)), int(expected.get("barriers_used", 0)),
		int(expected.get("clear_time_ms", 0)), int(expected.get("boss_phases", 0))
	]
	# v1 predates stage-bound playback. Keep its canonical ordering byte-for-byte
	# compatible, while v2 makes the selected stage part of the replay identity.
	if int(replay.get("format_version", 0)) >= 2:
		canonical.insert(2, String(replay.get("stage_id", "")))
	if int(replay.get("format_version", 0)) >= 3:
		canonical.append(int(expected.get("medal_bonus", 0)))
	if int(replay.get("format_version", 0)) >= 4:
		canonical.append(int(expected.get("risk_bank_bonus", 0)))
		var raw_risk_units: Variant = expected.get("risk_bank_units", [0, 0])
		var canonical_risk_units: Array[int] = [0, 0]
		if raw_risk_units is Array and raw_risk_units.size() == 2:
			canonical_risk_units = [int(raw_risk_units[0]), int(raw_risk_units[1])]
		canonical.append(canonical_risk_units)
	return JSON.stringify(canonical).sha256_text()

func _stage_is_available(stage_id: String) -> bool:
	var stage_manager := get_node_or_null("/root/StageManager")
	return stage_manager != null and stage_manager.has_method("has_stage") and bool(stage_manager.call("has_stage", stage_id))

func _is_stage_id(stage_id: String) -> bool:
	if stage_id.is_empty() or stage_id.length() > 64:
		return false
	const ID_CHARACTERS := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	for character in stage_id:
		if ID_CHARACTERS.find(character) < 0:
			return false
	return true

func _load_replay(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = json.data
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
