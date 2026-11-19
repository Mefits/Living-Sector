extends SceneTree
## Astra III/B: recovery promotion preserves original bytes on failure.
## The fixture tests filesystem transitions, not an unexecuted N38 replay.
const SaveState = preload("res://scripts/sim/save_state.gd")

func _write(path: String, value: String) -> void:
    var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    assert(f != null)
    f.store_string(value)
    f.close()

func _read(path: String) -> String:
    var f: FileAccess = FileAccess.open(path, FileAccess.READ)
    assert(f != null)
    var text: String = f.get_as_text()
    f.close()
    return text

func _clear(path: String) -> void:
    for suffix in ["", ".bak", ".bak.previous", ".pending",
            ".recovery-displaced"]:
        if FileAccess.file_exists(path + suffix):
            assert(DirAccess.remove_absolute(path + suffix) == OK)

func _initialize() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2_perf_b_n38_pending_recovery_rollback.tmp")
    _clear(path)
    # Positive: promote a previously restored pending checkpoint while
    # preserving the unrelated verified backup and cleaning the parked file.
    _write(path, "old-primary")
    _write(path + ".bak", "last-good-backup")
    _write(path + ".pending", "runner-verified-pending")
    assert(SaveState._promote_recovered_checkpoint(path, path + ".pending"))
    assert(_read(path) == "runner-verified-pending")
    assert(_read(path + ".bak") == "last-good-backup")
    assert(not FileAccess.file_exists(path + ".recovery-displaced"))
    _clear(path)

    # Negative: missing source cannot destroy the existing primary.
    _write(path, "keep-primary")
    assert(not SaveState._promote_recovered_checkpoint(path, path + ".pending"))
    assert(_read(path) == "keep-primary")
    _clear(path)

    # Negative: a parked orphan is never overwritten or discarded. The
    # recovered candidate remains available to load on the next launch.
    _write(path, "live-primary")
    _write(path + ".recovery-displaced", "crash-recovery")
    _write(path + ".bak.previous", "verified-previous")
    assert(not SaveState._promote_recovered_checkpoint(
        path, path + ".bak.previous"))
    assert(_read(path) == "live-primary")
    assert(_read(path + ".recovery-displaced") == "crash-recovery")
    assert(_read(path + ".bak.previous") == "verified-previous")
    _clear(path)

    # Positive: recovery into an absent primary needs no temporary parking.
    _write(path + ".bak.previous", "recovered-previous")
    assert(SaveState._promote_recovered_checkpoint(
        path, path + ".bak.previous"))
    assert(_read(path) == "recovered-previous")
    assert(not FileAccess.file_exists(path + ".recovery-displaced"))
    _clear(path)
    print("PASS p2_perf_b_n38_pending_recovery_rollback_20261118")
    quit(0)
