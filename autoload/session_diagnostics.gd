extends Node

## Privacy-safe, local-only session lifecycle journal.
##
## This does not capture native crashes, stack traces, hardware identifiers, or
## user identity. A previous abnormal exit is inferred only when the prior
## session did not get a chance to persist its clean-exit marker.

const SCHEMA_VERSION := 1
const MAX_SESSION_HISTORY := 12
const MAX_JOURNAL_BYTES := 131072
const JOURNAL_PATH := "user://psychic_vector_session_journal.json"
const JOURNAL_BACKUP_PATH := "user://psychic_vector_session_journal.backup.json"
const JOURNAL_STAGING_PATH := "user://psychic_vector_session_journal.pending.json"
const DIAGNOSTICS_EXPORT_PATH := "user://psychic_vector_diagnostics.json"
const EXIT_REASONS := ["running", "normal", "window_close", "scene_tree_exit", "unclean"]

var persistence_enabled := true
var journal_path := JOURNAL_PATH
var backup_path := JOURNAL_BACKUP_PATH
var staging_path := JOURNAL_STAGING_PATH
var export_path := DIAGNOSTICS_EXPORT_PATH
var auto_start_enabled := true
var prior_session_unclean := false
var recovered_from_backup := false
var journal_reset_after_corruption := false
var last_write_error: Error = OK
var journal: Dictionary = {}

var _session_open := false
var _clean_exit_written := false


func _ready() -> void:
	if not auto_start_enabled:
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--smoke") or argument.begins_with("--benchmark") or argument.begins_with("--capture"):
			persistence_enabled = false
			return
	begin_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		mark_clean_exit("window_close")


func _exit_tree() -> void:
	mark_clean_exit("scene_tree_exit")


func begin_session(timestamp_override: int = -1) -> bool:
	if not persistence_enabled:
		return false
	prior_session_unclean = false
	recovered_from_backup = false
	journal_reset_after_corruption = false
	_clean_exit_written = false
	_session_open = false

	var had_any_file := FileAccess.file_exists(journal_path) or FileAccess.file_exists(backup_path)
	var selection := _load_best_journal()
	if selection.is_empty():
		journal = _empty_journal()
		journal_reset_after_corruption = had_any_file
	else:
		journal = selection.journal
		recovered_from_backup = bool(selection.recovered)

	var previous: Dictionary = journal.get("active_session", {})
	if not previous.is_empty():
		previous = _sanitize_session(previous)
		if not previous.is_empty():
			prior_session_unclean = not bool(previous.get("clean_exit", false))
			if prior_session_unclean:
				previous["ended_at"] = 0
				previous["exit_reason"] = "unclean"
			var history: Array = journal.get("history", [])
			history.append(previous)
			while history.size() > MAX_SESSION_HISTORY:
				history.remove_at(0)
			journal["history"] = history

	var sequence := clampi(int(journal.get("session_sequence", 0)) + 1, 1, 2147483647)
	journal["session_sequence"] = sequence
	journal["active_session"] = {
		"sequence": sequence,
		"started_at": _timestamp(timestamp_override),
		"ended_at": 0,
		"clean_exit": false,
		"exit_reason": "running"
	}
	_seal_journal(journal)
	last_write_error = _save_journal_transaction(journal)
	_session_open = last_write_error == OK
	return _session_open


func mark_clean_exit(reason: String = "normal", timestamp_override: int = -1) -> bool:
	if not persistence_enabled:
		return false
	if _clean_exit_written:
		return true
	if not _session_open:
		return false
	var safe_reason := reason if reason in ["normal", "window_close", "scene_tree_exit"] else "normal"
	var active := _sanitize_session(journal.get("active_session", {}))
	if active.is_empty():
		return false
	active["clean_exit"] = true
	active["ended_at"] = maxi(int(active.get("started_at", 0)), _timestamp(timestamp_override))
	active["exit_reason"] = safe_reason
	journal["active_session"] = active
	_seal_journal(journal)
	last_write_error = _save_journal_transaction(journal)
	_clean_exit_written = last_write_error == OK
	if _clean_exit_written:
		_session_open = false
	return _clean_exit_written


func unclean_exit_count() -> int:
	var count := 0
	for entry_value in journal.get("history", []):
		if entry_value is Dictionary and not bool(entry_value.get("clean_exit", false)):
			count += 1
	return count


func retained_session_count() -> int:
	return Array(journal.get("history", [])).size()


func diagnostics_export_path() -> String:
	return export_path


func export_diagnostics(timestamp_override: int = -1) -> bool:
	if not persistence_enabled:
		return false
	var document := {
		"schema_version": SCHEMA_VERSION,
		"generated_at": _timestamp(timestamp_override),
		"disclosure": "LOCAL MANUAL EXPORT. Missing clean-exit markers infer abnormal termination; this is not a native crash dump.",
		"network_transmission": false,
		"identity_fields_collected": false,
		"retention_limit": MAX_SESSION_HISTORY,
		"prior_session_unclean": prior_session_unclean,
		"recovered_from_backup": recovered_from_backup,
		"journal_reset_after_corruption": journal_reset_after_corruption,
		"history": _export_history(),
		"current_session": _export_session(journal.get("active_session", {}))
	}
	return _write_json_file(export_path, document) == OK


func _empty_journal() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"write_complete": false,
		"session_sequence": 0,
		"active_session": {},
		"history": [],
		"integrity": ""
	}


func _load_best_journal() -> Dictionary:
	var primary := _read_valid_journal(journal_path)
	if not primary.is_empty():
		return {"journal": primary, "recovered": false}
	var backup := _read_valid_journal(backup_path)
	if not backup.is_empty():
		return {"journal": backup, "recovered": true}
	return {}


func _read_valid_journal(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() <= 0 or file.get_length() > MAX_JOURNAL_BYTES:
		file.close()
		return {}
	var source := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(source) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not _journal_is_valid(parsed):
		return {}
	var sanitized := _sanitize_journal(parsed)
	_seal_journal(sanitized)
	return sanitized


func _journal_is_valid(raw: Dictionary) -> bool:
	if int(raw.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	if not bool(raw.get("write_complete", false)):
		return false
	var expected := String(raw.get("integrity", ""))
	if expected.is_empty():
		return false
	var sanitized := _sanitize_journal(raw)
	return expected == _journal_integrity(sanitized)


func _sanitize_journal(raw: Dictionary) -> Dictionary:
	var sanitized := _empty_journal()
	sanitized["session_sequence"] = clampi(int(raw.get("session_sequence", 0)), 0, 2147483647)
	var active := _sanitize_session(raw.get("active_session", {}))
	sanitized["active_session"] = active
	var history: Array = []
	var raw_history: Variant = raw.get("history", [])
	if raw_history is Array:
		var start := maxi(0, raw_history.size() - MAX_SESSION_HISTORY)
		for index in range(start, raw_history.size()):
			var entry := _sanitize_session(raw_history[index])
			if not entry.is_empty():
				history.append(entry)
	sanitized["history"] = history
	return sanitized


func _sanitize_session(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var sequence := int(raw.get("sequence", 0))
	var started_at := int(raw.get("started_at", -1))
	if sequence <= 0 or started_at < 0:
		return {}
	var clean_exit := bool(raw.get("clean_exit", false))
	var ended_at := maxi(0, int(raw.get("ended_at", 0)))
	var reason := String(raw.get("exit_reason", "running"))
	if not EXIT_REASONS.has(reason):
		reason = "normal" if clean_exit else "running"
	if clean_exit and ended_at < started_at:
		ended_at = started_at
	if not clean_exit:
		ended_at = 0
		if reason not in ["running", "unclean"]:
			reason = "running"
	return {
		"sequence": clampi(sequence, 1, 2147483647),
		"started_at": maxi(0, started_at),
		"ended_at": ended_at,
		"clean_exit": clean_exit,
		"exit_reason": reason
	}


func _seal_journal(target: Dictionary) -> void:
	target["schema_version"] = SCHEMA_VERSION
	target["write_complete"] = true
	target["integrity"] = _journal_integrity(target)


func _journal_integrity(target: Dictionary) -> String:
	var payload := [
		SCHEMA_VERSION,
		int(target.get("session_sequence", 0)),
		_export_session(target.get("active_session", {})),
		_export_history_from(target.get("history", []))
	]
	return JSON.stringify(_canonical_variant(payload)).sha256_text()


func _canonical_variant(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var pairs: Array = []
		for key in keys:
			pairs.append([String(key), _canonical_variant(value[key])])
		return pairs
	if value is Array:
		var normalized: Array = []
		for item in value:
			normalized.append(_canonical_variant(item))
		return normalized
	return value


func _save_journal_transaction(target: Dictionary) -> Error:
	_remove_file(staging_path)
	var error := _write_json_file(staging_path, target)
	if error != OK:
		return error
	if _read_valid_journal(staging_path).is_empty():
		_remove_file(staging_path)
		return ERR_FILE_CORRUPT

	var current := _read_valid_journal(journal_path)
	if not current.is_empty():
		error = _write_json_file(backup_path, current)
		if error != OK:
			_remove_file(staging_path)
			return error
	if FileAccess.file_exists(journal_path):
		error = _remove_file(journal_path)
		if error != OK:
			_remove_file(staging_path)
			return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(staging_path), ProjectSettings.globalize_path(journal_path))
	if error != OK:
		_remove_file(staging_path)
		if not current.is_empty():
			_write_json_file(journal_path, current)
		return error
	# Keep the backup synchronized after commit. If termination occurs before
	# this line, the newly committed primary remains authoritative.
	error = _write_json_file(backup_path, target)
	if error != OK or _read_valid_journal(backup_path).is_empty():
		return error if error != OK else ERR_FILE_CORRUPT
	return OK


func _write_json_file(path: String, document: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	return error


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _export_history() -> Array:
	return _export_history_from(journal.get("history", []))


func _export_history_from(raw_history: Variant) -> Array:
	var result: Array = []
	if not raw_history is Array:
		return result
	var start := maxi(0, raw_history.size() - MAX_SESSION_HISTORY)
	for index in range(start, raw_history.size()):
		var entry := _export_session(raw_history[index])
		if not entry.is_empty():
			result.append(entry)
	return result


func _export_session(raw: Variant) -> Dictionary:
	var session := _sanitize_session(raw)
	if session.is_empty():
		return {}
	return {
		"sequence": int(session.sequence),
		"started_at": int(session.started_at),
		"ended_at": int(session.ended_at),
		"clean_exit": bool(session.clean_exit),
		"exit_reason": String(session.exit_reason)
	}


func _timestamp(override_value: int) -> int:
	return maxi(0, override_value) if override_value >= 0 else int(Time.get_unix_time_from_system())
