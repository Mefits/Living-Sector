extends SceneTree
## N38 Astra III/B: invalid primary must survive a verified pending promotion.
## Exercise the actual filesystem rotation helper, without enabling a new format.
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var root: String = ProjectSettings.globalize_path(
        "user://perf-b-n38-invalid-primary-%d" % Time.get_ticks_usec())
    if DirAccess.make_dir_recursive_absolute(root) != OK:
        _fail("mkdir")
        return
    var path: String = root.path_join("save.json")
    if not _write(path, "CORRUPT-PRIMARY") or not _write(
            path + ".pending", "VERIFIED-PENDING"):
        _fail("fixture")
        return
    if SaveState._promote_verified_pending(path, false) != OK:
        _fail("invalid-primary promotion")
        return
    if _read(path) != "VERIFIED-PENDING" or _read(
            path + ".recovery-rejected") != "CORRUPT-PRIMARY":
        _fail("primary destroyed or pending not promoted")
        return
    if FileAccess.file_exists(path + ".pending"):
        _fail("pending not consumed")
        return
    # A second bad primary must not overwrite the previously rejected bytes.
    if not _write(path, "SECOND-CORRUPT") or not _write(
            path + ".pending", "SECOND-VERIFIED"):
        _fail("collision fixture")
        return
    if SaveState._promote_verified_pending(path, false) != ERR_ALREADY_EXISTS:
        _fail("rejected checkpoint collision accepted")
        return
    if _read(path) != "SECOND-CORRUPT" or _read(
            path + ".recovery-rejected") != "CORRUPT-PRIMARY" or _read(
            path + ".pending") != "SECOND-VERIFIED":
        _fail("collision modified checkpoint")
        return
    # A missing pending file must fail without losing the original primary.
    DirAccess.remove_absolute(path + ".recovery-rejected")
    DirAccess.remove_absolute(path + ".pending")
    if SaveState._promote_verified_pending(path, false) == OK:
        _fail("missing pending accepted")
        return
    if _read(path) != "SECOND-CORRUPT":
        _fail("failed promotion lost original primary")
        return
    if FileAccess.file_exists(path + ".recovery-rejected"):
        _fail("rollback left an unnecessary rejected file")
        return
    # Healthy primary follows the original backup rotation path.
    if not _write(path + ".pending", "NEXT-VERIFIED"):
        _fail("healthy fixture")
        return
    if SaveState._promote_verified_pending(path, true) != OK:
        _fail("healthy rotation")
        return
    if _read(path) != "NEXT-VERIFIED" or _read(
            path + ".bak") != "SECOND-CORRUPT":
        _fail("healthy backup parity")
        return
    for suffix in ["", ".pending", ".bak", ".bak.previous",
            ".recovery-rejected"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)
    DirAccess.remove_absolute(root)
    print("PASS p2_perf_b_n38_invalid_primary_promotion")
    quit(0)

func _write(path: String, value: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(value)
    file.flush()
    var ok: bool = file.get_error() == OK
    file.close()
    return ok

func _read(path: String) -> String:
    if not FileAccess.file_exists(path):
        return ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var value: String = file.get_as_text()
    file.close()
    return value

func _fail(message: String) -> void:
    push_error("FAIL p2_perf_b_n38_invalid_primary_promotion: " + message)
    quit(1)
