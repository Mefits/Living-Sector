extends SceneTree
## Run with: godot --headless --path godot --script res://tests/test_n38_recovery_displaced_runner_accept.gd
const SaveState = preload("res://scripts/sim/save_state.gd")
var failures: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _assert(value: bool, label: String) -> void:
    if not value:
        failures += 1
        push_error(label)

func _write(path: String, value: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    _assert(file != null, "fixture open: " + path)
    if file != null:
        file.store_string(value)
        file.close()

func _run() -> void:
    var path: String = "user://n38-displaced-acceptance-b.json"
    var absolute: String = ProjectSettings.globalize_path(path)
    var displaced: String = absolute + ".recovery-displaced"
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(displaced)
    # Positive: a clean path must remain immediately usable.
    _assert(SaveState._reconcile_recovery_displaced(absolute, false) == OK,
        "no orphan is a no-op")
    _write(displaced, "LAST_RECOVERABLE_BYTES")
    # Negative: no primary means the orphan is the sole surviving checkpoint.
    _assert(SaveState._reconcile_recovery_displaced(absolute, false) == ERR_BUSY,
        "save must refuse unresolved orphan")
    _assert(FileAccess.file_exists(displaced), "orphan preserved without primary")
    _write(absolute, "{broken json")
    # Oracle: even a purported successful restore cannot authorize deleting
    # a structurally invalid primary's displaced predecessor.
    _assert(SaveState._reconcile_recovery_displaced(absolute, true) == ERR_FILE_CORRUPT,
        "invalid primary cannot authorize cleanup")
    _assert(FileAccess.file_exists(displaced), "orphan survives corrupt primary")
    _assert(SaveState._reconcile_recovery_displaced(absolute, false) == ERR_BUSY,
        "save cannot use structural preflight as acceptance")
    var original := FileAccess.get_file_as_string(displaced)
    _assert(original == "LAST_RECOVERABLE_BYTES", "orphan bytes unchanged")
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(displaced)
    print("N38 displaced acceptance test: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
