extends SceneTree
## Astra III/B: filesystem regression for interrupted N38 rotation.
## Production validates _read_checkpoint + native timeline/coherence before
## passing the three trust flags. These tests exercise recovery transitions.
const SaveState = preload("res://scripts/sim/save_state.gd")

func _write(path: String, value: String) -> void:
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    assert(file != null)
    file.store_string(value)
    file.close()

func _read(path: String) -> String:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    assert(file != null)
    var result: String = file.get_as_text()
    file.close()
    return result

func _clear(path: String) -> void:
    for suffix in ["", ".bak", ".bak.previous", ".pending"]:
        if FileAccess.file_exists(path + suffix):
            assert(DirAccess.remove_absolute(path + suffix) == OK)

func _initialize() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2_perf_b_n38_orphan_reconcile_20261118.tmp")
    _clear(path)
    # Positive: after a crash, valid backup outranks the parked older one.
    _write(path, "primary-A")
    _write(path + ".bak", "backup-B")
    _write(path + ".bak.previous", "older-C")
    _write(path + ".pending", "new-D")
    assert(SaveState._reconcile_parked_backup(path, true, true, true) == OK)
    assert(not FileAccess.file_exists(path + ".bak.previous"))
    assert(_read(path + ".bak") == "backup-B")
    assert(SaveState._promote_verified_pending(path, true) == OK)
    assert(_read(path) == "new-D")
    assert(_read(path + ".bak") == "primary-A")
    _clear(path)

    # Positive: corrupt/missing backup can be repaired from a verified older
    # backup without touching a live primary or the verified pending file.
    _write(path, "primary-E")
    _write(path + ".bak", "corrupt-F")
    _write(path + ".bak.previous", "verified-G")
    _write(path + ".pending", "new-H")
    assert(SaveState._reconcile_parked_backup(path, true, false, true) == OK)
    assert(_read(path + ".bak") == "verified-G")
    assert(not FileAccess.file_exists(path + ".bak.previous"))
    assert(_read(path + ".pending") == "new-H")
    assert(SaveState._promote_verified_pending(path, true) == OK)
    assert(_read(path) == "new-H")
    assert(_read(path + ".bak") == "primary-E")
    _clear(path)

    # Negative: if no checkpoint is verified, do not destroy even the
    # suspicious bytes. Leave pending available for manual recovery.
    _write(path, "bad-I")
    _write(path + ".bak", "bad-J")
    _write(path + ".bak.previous", "bad-K")
    _write(path + ".pending", "pending-L")
    assert(SaveState._reconcile_parked_backup(path, false, false, false) == ERR_FILE_CORRUPT)
    assert(_read(path) == "bad-I")
    assert(_read(path + ".bak") == "bad-J")
    assert(_read(path + ".bak.previous") == "bad-K")
    assert(_read(path + ".pending") == "pending-L")
    _clear(path)

    # Positive: if primary is verified but both recovery copies are corrupt,
    # clear only the invalid backups before rotating the healthy primary.
    _write(path, "valid-M")
    _write(path + ".bak", "bad-N")
    _write(path + ".bak.previous", "bad-O")
    _write(path + ".pending", "new-P")
    assert(SaveState._reconcile_parked_backup(path, true, false, false) == OK)
    assert(not FileAccess.file_exists(path + ".bak"))
    assert(not FileAccess.file_exists(path + ".bak.previous"))
    assert(_read(path) == "valid-M")
    assert(SaveState._promote_verified_pending(path, true) == OK)
    assert(_read(path) == "new-P")
    assert(_read(path + ".bak") == "valid-M")
    _clear(path)

    # Negative: an absent pending file must roll back a valid primary and
    # backup even after the orphan has been reconciled.
    _write(path, "primary-Q")
    _write(path + ".bak", "backup-R")
    _write(path + ".bak.previous", "older-S")
    assert(SaveState._reconcile_parked_backup(path, true, true, true) == OK)
    assert(SaveState._promote_verified_pending(path, true) != OK)
    assert(_read(path) == "primary-Q")
    assert(_read(path + ".bak") == "backup-R")
    _clear(path)
    print("PASS p2_perf_b_n38_orphan_rotation_20261118")
    quit(0)
