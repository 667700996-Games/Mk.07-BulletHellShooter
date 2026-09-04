extends SceneTree

## Contract test for the privacy-safe local session journal. All writes use a
## process-specific /tmp directory; the production user-data journal is never
## read or changed by this smoke test.

const DIAGNOSTICS_SCRIPT := preload("res://autoload/session_diagnostics.gd")

var failures: Array[String] = []
var test_directory := "/tmp/psychic_vector_session_diagnostics_%d" % OS.get_process_id()
var primary_path := test_directory.path_join("journal.json")
var backup_path := test_directory.path_join("journal.backup.json")
var staging_path := test_directory.path_join("journal.pending.json")
var export_path := test_directory.path_join("diagnostics.json")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(test_directory)
	_test_corrupt_reset_and_unclean_detection()
	_test_backup_recovery_and_bounded_retention()
	_test_v1_build_identity_migration()
	_test_manual_privacy_safe_export()
	await _test_runtime_clean_exit_hooks()
	_cleanup()
	_finish()


func _test_corrupt_reset_and_unclean_detection() -> void:
	_write_text(primary_path, "x".repeat(131073))
	_write_text(backup_path, "{ truncated")
	var first: Variant = _diagnostics()
	_check(first.begin_session(100), "fresh journal could not replace corrupt primary and backup")
	_check(first.journal_reset_after_corruption, "corrupt journal reset was not exposed")
	_check(not first.prior_session_unclean, "corrupt bytes were misreported as a prior abnormal exit")
	_check(not first._read_valid_journal(primary_path).is_empty(), "replacement primary journal is invalid")
	_check(not first._read_valid_journal(backup_path).is_empty(), "replacement backup journal is invalid")
	_check(not FileAccess.file_exists(staging_path), "committed journal left its staging file behind")

	# Deliberately omit a clean-exit marker to simulate a killed process. The
	# next instance must infer, rather than claim to capture, an abnormal exit.
	var second: Variant = _diagnostics()
	_check(second.begin_session(200), "second session did not open")
	_check(second.prior_session_unclean, "missing clean marker was not detected on the next start")
	_check(second.unclean_exit_count() == 1, "unclean prior session was not retained exactly once")
	var history: Array = second.journal.get("history", [])
	_check(history.size() == 1 and String(history[0].get("exit_reason", "")) == "unclean", "inferred exit did not use the bounded unclean reason")
	_check(second.mark_clean_exit("normal", 250), "clean-exit marker could not be persisted")
	_check(second.mark_clean_exit("normal", 260), "clean-exit marking is not idempotent")
	var clean_disk: Dictionary = second._read_valid_journal(primary_path)
	_check(bool((clean_disk.get("active_session", {}) as Dictionary).get("clean_exit", false)), "clean-exit marker did not survive disk verification")
	first.free()
	second.free()


func _test_backup_recovery_and_bounded_retention() -> void:
	# The synchronized backup contains the clean session. Corrupting only the
	# primary must recover without inventing another abnormal exit.
	_write_text(primary_path, "[]")
	var recovered: Variant = _diagnostics()
	_check(recovered.begin_session(300), "valid backup was not promoted into a new session")
	_check(recovered.recovered_from_backup, "backup recovery status was not exposed")
	_check(not recovered.prior_session_unclean, "clean backup recovery became a false abnormal exit")
	_check(recovered.mark_clean_exit("scene_tree_exit", 320), "recovered session could not close cleanly")

	var latest: Variant = recovered
	for index in 16:
		latest.free()
		latest = _diagnostics()
		_check(latest.begin_session(400 + index * 10), "retention session %d could not open" % index)
		_check(latest.mark_clean_exit("normal", 405 + index * 10), "retention session %d could not close" % index)
	var history: Array = latest.journal.get("history", [])
	_check(history.size() == latest.MAX_SESSION_HISTORY, "session history exceeded or missed its 12-entry bound")
	_check(int(history[0].get("sequence", 0)) > 1, "bounded journal retained its oldest entry")
	for entry_value in history:
		_check(entry_value is Dictionary and bool(entry_value.get("clean_exit", false)), "bounded clean history contains an invalid session")
	latest.free()


func _test_manual_privacy_safe_export() -> void:
	_remove_file(export_path)
	var diagnostics: Variant = _diagnostics()
	_check(diagnostics.begin_session(900), "export test session could not open")
	_check(not FileAccess.file_exists(export_path), "diagnostics were exported without a player action")
	_check(diagnostics.export_diagnostics(910), "manual diagnostics export failed")
	var document := _read_json(export_path)
	_check(not document.is_empty(), "diagnostics export is not valid JSON")
	var expected_keys := [
		"schema_version", "generated_at", "disclosure", "network_transmission", "build_identity",
		"identity_fields_collected", "retention_limit", "prior_session_unclean",
		"recovered_from_backup", "journal_reset_after_corruption", "history", "current_session"
	]
	var actual_keys: Array = document.keys()
	actual_keys.sort()
	expected_keys.sort()
	_check(actual_keys == expected_keys, "diagnostics export leaked or omitted top-level fields: %s" % str(actual_keys))
	_check(not bool(document.get("network_transmission", true)), "export claims or enables network transmission")
	_check(not bool(document.get("identity_fields_collected", true)), "export claims identity collection")
	var exported_build: Dictionary = document.get("build_identity", {})
	var current_build: Dictionary = diagnostics.current_build_identity()
	var build_keys: Array = exported_build.keys()
	var expected_build_keys: Array = current_build.keys()
	build_keys.sort()
	expected_build_keys.sort()
	_check(build_keys == expected_build_keys, "export build identity fields differ from the release contract")
	for string_key in ["product_name", "version", "release_channel", "godot_version", "candidate_id"]:
		_check(String(exported_build.get(string_key, "")) == String(current_build.get(string_key, "")), "export build identity differs at %s" % string_key)
	_check(int(exported_build.get("schema_version", 0)) == int(current_build.get("schema_version", 0)), "export build identity schema differs")
	_check(int(exported_build.get("build_number", 0)) == int(current_build.get("build_number", 0)), "export build number differs")
	_check(bool(exported_build.get("unsigned", false)) == bool(current_build.get("unsigned", false)), "export unsigned marker differs")
	_check(String(exported_build.get("candidate_id", "")) == "PsychicVector-0.1.0-alpha.1-build.18-unsigned", "release candidate ID was not exported")
	_check(int(document.get("retention_limit", 0)) == diagnostics.MAX_SESSION_HISTORY, "export does not disclose its retention limit")
	_check(Array(document.get("history", [])).size() <= diagnostics.MAX_SESSION_HISTORY, "export bypassed bounded retention")
	_check(String(document.get("disclosure", "")).contains("not a native crash dump"), "export does not distinguish inferred exits from crash capture")
	_check(not JSON.stringify(document).contains(test_directory), "export contains a local absolute path")
	var session_keys := ["build_id", "clean_exit", "ended_at", "exit_reason", "sequence", "started_at"]
	for entry_value in Array(document.get("history", [])) + [document.get("current_session", {})]:
		if not entry_value is Dictionary or entry_value.is_empty():
			continue
		var entry_keys: Array = entry_value.keys()
		entry_keys.sort()
		_check(entry_keys == session_keys, "session export contains an unexpected identity or environment field")
		_check(not String(entry_value.get("build_id", "")).is_empty(), "session export omitted its non-player build ID")
	_check(diagnostics.mark_clean_exit("normal", 920), "export test session could not close cleanly")
	diagnostics.free()


func _test_v1_build_identity_migration() -> void:
	for path in [primary_path, backup_path, staging_path]:
		_remove_file(path)
	var signer: Variant = _diagnostics()
	var legacy := {
		"schema_version": signer.LEGACY_SCHEMA_VERSION,
		"write_complete": true,
		"session_sequence": 7,
		"active_session": {
			"sequence": 7,
			"started_at": 700,
			"ended_at": 720,
			"clean_exit": true,
			"exit_reason": "normal"
		},
		"history": [],
		"integrity": ""
	}
	legacy["integrity"] = signer._legacy_journal_integrity(legacy)
	_write_text(primary_path, JSON.stringify(legacy, "\t"))
	var migrated: Variant = _diagnostics()
	_check(migrated.begin_session(800), "valid v1 journal did not migrate into a new session")
	_check(not migrated.journal_reset_after_corruption, "valid v1 journal was misreported as corrupt")
	_check(int(migrated.journal.get("schema_version", 0)) == migrated.SCHEMA_VERSION, "v1 journal did not migrate to schema v2")
	var history: Array = migrated.journal.get("history", [])
	_check(history.size() == 1 and String(history[0].get("build_id", "")) == migrated.LEGACY_BUILD_ID, "legacy session did not receive an explicit unknown-build marker")
	var active: Dictionary = migrated.journal.get("active_session", {})
	_check(String(active.get("build_id", "")) == migrated.current_build_id(), "new session did not bind the current release candidate")
	var disk: Dictionary = migrated._read_valid_journal(primary_path)
	_check(int(disk.get("schema_version", 0)) == migrated.SCHEMA_VERSION, "migrated v2 journal did not survive integrity verification")
	_check(migrated.mark_clean_exit("normal", 820), "migrated session could not close cleanly")
	signer.free()
	migrated.free()


func _test_runtime_clean_exit_hooks() -> void:
	var window_close: Variant = _diagnostics()
	_check(window_close.begin_session(1000), "window-close session could not open")
	window_close._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var window_disk: Dictionary = window_close._read_valid_journal(primary_path)
	var window_active: Dictionary = window_disk.get("active_session", {})
	_check(bool(window_active.get("clean_exit", false)) and String(window_active.get("exit_reason", "")) == "window_close", "window close did not persist its clean-exit reason")
	window_close.free()

	var tree_exit: Variant = _diagnostics()
	tree_exit.auto_start_enabled = false
	get_root().add_child(tree_exit)
	_check(tree_exit.begin_session(1100), "tree-exit session could not open")
	tree_exit.queue_free()
	await process_frame
	var verifier: Variant = _diagnostics()
	var tree_disk: Dictionary = verifier._read_valid_journal(primary_path)
	var tree_active: Dictionary = tree_disk.get("active_session", {})
	_check(bool(tree_active.get("clean_exit", false)) and String(tree_active.get("exit_reason", "")) == "scene_tree_exit", "SceneTree removal did not persist its clean-exit reason")
	verifier.free()


func _diagnostics() -> Variant:
	var instance: Variant = DIAGNOSTICS_SCRIPT.new()
	instance.persistence_enabled = true
	instance.journal_path = primary_path
	instance.backup_path = backup_path
	instance.staging_path = staging_path
	instance.export_path = export_path
	return instance


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write test fixture: %s" % path)
		return
	file.store_string(value)
	file.flush()
	file.close()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var source := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(source)
	return parsed if parsed is Dictionary else {}


func _cleanup() -> void:
	for path in [primary_path, backup_path, staging_path, export_path]:
		_remove_file(path)
	DirAccess.remove_absolute(test_directory)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("SESSION_DIAGNOSTICS_TEST_OK inference=next-start clean_exit=atomic backup=recovered retention=12 migration=v1-v2 build=correlated export=manual+local+identity-free")
		quit(0)
		return
	printerr("SESSION_DIAGNOSTICS_TEST_FAILED errors=%d" % failures.size())
	for failure in failures:
		printerr("SESSION_DIAGNOSTICS_ERROR %s" % failure)
	quit(1)
