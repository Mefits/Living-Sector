extends SceneTree
## CODE_UNVERIFIED / TEST_NOT_RUN. Run headless from godot project root.
const SaveState = preload("res://scripts/sim/save_state.gd")

var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, message: String) -> void:
    if not condition:
        _failures.append(message)

func _put(path: String, payload: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    _check(file != null, "cannot write " + path)
    if file != null:
        file.store_string(payload)
        file.close()

func _read(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var payload: String = file.get_as_text()
    file.close()
    return payload

func _clean(base: String) -> void:
    for suffix in ["", ".pending", ".bak", ".bak.previous",
            ".recovery-displaced", ".recovery-rejected"]:
        var path: String = base + suffix
        if FileAccess.file_exists(path):
            DirAccess.remove_absolute(path)

func _run() -> void:
    var base: String = ProjectSettings.globalize_path(
        "user://p2_perf_b_displaced_recovery_20261118.json")
    _clean(base)

    # Positive: after an interrupted recovery, a restored displaced
    # checkpoint replaces a corrupt primary without overwriting its bytes.
    _put(base, "damaged primary")
    _put(base + ".recovery-displaced", "restored candidate")
    _check(SaveState._promote_recovered_checkpoint(
        base, base + ".recovery-displaced"), "displaced promotion rejected")
    _check(_read(base) == "restored candidate", "wrong promoted bytes")
    _check(_read(base + ".recovery-rejected") == "damaged primary",
        "rejected original was lost")

    # Negative: an existing rejected checkpoint cannot be overwritten.
    _put(base + ".recovery-displaced", "second candidate")
    _check(not SaveState._promote_recovered_checkpoint(
        base, base + ".recovery-displaced"), "overwrote rejected original")
    _check(_read(base) == "restored candidate", "failed promotion changed primary")
    _check(_read(base + ".recovery-displaced") == "second candidate",
        "failed promotion destroyed candidate")

    # Negative: invalid primary cannot authorize deleting the only orphan.
    _check(SaveState._reconcile_recovery_displaced(base) == OK,
        "invalid primary reconcile returned error")
    _check(FileAccess.file_exists(base + ".recovery-displaced"),
        "invalid primary removed orphan")

    # Positive: promotion with no primary preserves the recovered payload.
    _clean(base)
    _put(base + ".recovery-displaced", "only survivor")
    _check(SaveState._promote_recovered_checkpoint(
        base, base + ".recovery-displaced"), "orphan-only promotion failed")
    _check(_read(base) == "only survivor", "orphan-only payload lost")
    _check(not FileAccess.file_exists(base + ".recovery-rejected"),
        "orphan-only promotion created rejected file")

    # Negative: missing candidate leaves existing primary untouched.
    _check(not SaveState._promote_recovered_checkpoint(
        base, base + ".pending"), "missing pending accepted")
    _check(_read(base) == "only survivor", "missing pending damaged primary")

    _clean(base)
    if _failures.is_empty():
        print("PASS p2_perf_b_n38_displaced_recovery_20261118")
        quit(0)
    else:
        for failure in _failures:
            push_error(failure)
        quit(1)
