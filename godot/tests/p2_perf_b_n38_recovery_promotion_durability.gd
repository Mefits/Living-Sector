extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_perf_b_n38_recovery_promotion_durability.gd
const SaveState = preload("res://scripts/sim/save_state.gd")
var failures: int = 0

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, label: String) -> void:
    if not condition:
        failures += 1
        push_error(label)

func _write(path: String, bytes: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    _check(file != null, "fixture file writable: " + path)
    if file != null:
        file.store_string(bytes)
        file.close()

func _clear(path: String) -> void:
    for suffix in ["", ".pending", ".bak.previous", ".recovery-displaced",
            ".recovery-rejected"]:
        DirAccess.remove_absolute(path + suffix)

func _run() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2-perf-b-n38-promotion.json")
    var displaced: String = path + ".recovery-displaced"
    var rejected: String = path + ".recovery-rejected"
    var pending: String = path + ".pending"
    _clear(path)

    # Negative: a checksum-invalid candidate must not replace the old primary.
    _write(path, "OLD_PRIMARY_BYTE_ORACLE")
    _write(pending, "{invalid checkpoint")
    _check(not SaveState._promote_recovered_checkpoint(path, pending),
        "invalid pending rejected after rename")
    _check(FileAccess.get_file_as_string(path) == "OLD_PRIMARY_BYTE_ORACLE",
        "old primary restored byte-for-byte")
    _check(FileAccess.get_file_as_string(pending) == "{invalid checkpoint",
        "failed candidate retained for recovery")
    _check(not FileAccess.file_exists(displaced), "no leaked displaced file")

    # Negative: the same failed promotion with no primary must restore the
    # candidate filename, not leave an invalid primary masking later restarts.
    _clear(path)
    _write(pending, "{invalid checkpoint")
    _check(not SaveState._promote_recovered_checkpoint(path, pending),
        "invalid pending without primary rejected")
    _check(not FileAccess.file_exists(path), "no invalid primary installed")
    _check(FileAccess.get_file_as_string(pending) == "{invalid checkpoint",
        "candidate bytes retained when primary absent")

    # Negative: a pre-existing orphan must never be overwritten by a new
    # candidate, even when a primary is present.
    _clear(path)
    _write(path, "ORIGINAL")
    _write(displaced, "ORPHAN_BYTES")
    _write(pending, "NEW_BYTES")
    _check(not SaveState._promote_recovered_checkpoint(path, pending),
        "unresolved orphan blocks promotion")
    _check(FileAccess.get_file_as_string(displaced) == "ORPHAN_BYTES",
        "orphan oracle preserved")
    _check(FileAccess.get_file_as_string(path) == "ORIGINAL",
        "primary oracle preserved")

    # Negative: recovery of displaced cannot overwrite a prior rejected
    # checkpoint. Both recovery sources remain independently accessible.
    _clear(path)
    _write(path, "PRIMARY")
    _write(displaced, "DISPLACED")
    _write(rejected, "REJECTED")
    _check(not SaveState._promote_recovered_checkpoint(path, displaced),
        "rejected collision blocks displaced promotion")
    _check(FileAccess.get_file_as_string(rejected) == "REJECTED",
        "rejected bytes preserved")
    _check(FileAccess.get_file_as_string(displaced) == "DISPLACED",
        "displaced bytes preserved")

    # Positive no-op: cleanup without an orphan is successful and does not
    # touch an unrelated primary; actual Runner success remains a separate
    # acceptance gate covered by the save/restart integration suite.
    _clear(path)
    _write(path, "UNCHANGED")
    _check(SaveState._reconcile_recovery_displaced(path, false) == OK,
        "no orphan cleanup is idempotent")
    _check(FileAccess.get_file_as_string(path) == "UNCHANGED",
        "no-op preserves primary")
    _clear(path)
    print("N38 recovery promotion durability: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)
