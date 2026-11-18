extends SceneTree
## Astra III/B: filesystem-only oracle for the N38 verified-pending
## promotion stage. No fake World or bypass of save_runner coherence guards.
const SaveState = preload("res://scripts/sim/save_state.gd")

func _write(path: String, value: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.close()

func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(file != null)
	var value: String = file.get_as_text()
	file.close()
	return value

func _clear(path: String) -> void:
	for suffix in ["", ".pending", ".bak", ".bak.previous"]:
		var candidate: String = path + suffix
		if FileAccess.file_exists(candidate):
			assert(DirAccess.remove_absolute(candidate) == OK)

func _initialize() -> void:
	var path: String = ProjectSettings.globalize_path(
		"user://p2_perf_b_n38_rotation_20261118.tmp")
	_clear(path)
	# Successful replacement keeps the old primary as the new backup.
	_write(path, "primary-A")
	_write(path + ".bak", "backup-B")
	_write(path + ".pending", "pending-C")
	assert(SaveState._promote_verified_pending(path, true) == OK)
	assert(_read(path) == "pending-C")
	assert(_read(path + ".bak") == "primary-A")
	assert(not FileAccess.file_exists(path + ".bak.previous"))
	# An orphaned backup from an interrupted rotation must never be
	# overwritten or deleted by a subsequent save attempt.
	_write(path + ".bak.previous", "orphan-D")
	_write(path + ".pending", "pending-E")
	assert(SaveState._promote_verified_pending(path, true) != OK)
	assert(_read(path) == "pending-C")
	assert(_read(path + ".bak") == "primary-A")
	assert(_read(path + ".bak.previous") == "orphan-D")
	assert(_read(path + ".pending") == "pending-E")
	_clear(path)
	# A missing pending checkpoint fails promotion and rolls back both
	# the primary and the previously parked backup.
	_write(path, "primary-F")
	_write(path + ".bak", "backup-G")
	assert(SaveState._promote_verified_pending(path, true) != OK)
	assert(_read(path) == "primary-F")
	assert(_read(path + ".bak") == "backup-G")
	assert(not FileAccess.file_exists(path + ".bak.previous"))
	_clear(path)
	# An invalid primary may be replaced without sacrificing a valid backup.
	_write(path, "invalid-H")
	_write(path + ".bak", "backup-I")
	_write(path + ".pending", "pending-J")
	assert(SaveState._promote_verified_pending(path, false) == OK)
	assert(_read(path) == "pending-J")
	assert(_read(path + ".bak") == "backup-I")
	_clear(path)
	print("PASS p2_perf_b_n38_backup_rotation_20261118")
	quit(0)
