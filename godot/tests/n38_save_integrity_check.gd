extends SceneTree
## N38: corrupt primary, valid backup, legacy v1 and deterministic integrity.
## Run: Godot --headless --path godot --script res://tests/n38_save_integrity_check.gd
## CODE_UNVERIFIED until run in Godot.

const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("missing native seed")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("seed initialization")
        return
    runner.queue_control("pause")
    runner.advance_frame(0.0)
    runner.queue_control("step", 7)
    runner.advance_frame(0.0)
    var original: Dictionary = runner.checkpoint()
    var path: String = "user://tests/n38-" + str(Time.get_ticks_usec()) + ".json"
    var abs_path: String = ProjectSettings.globalize_path(path)
    if Saves.save_runner(runner, path) != OK:
        _fail("first save")
        return
    var first_text: String = FileAccess.get_file_as_string(abs_path)
    var wrapped: Variant = JSON.parse_string(first_text)
    if not (wrapped is Dictionary) or not wrapped.has("payload_sha256"):
        _fail("missing integrity envelope")
        return
    if Saves.save_runner(runner, path) != OK:
        _fail("second save")
        return
    var second_text: String = FileAccess.get_file_as_string(abs_path)
    if first_text != second_text:
        _fail("identical state must produce identical bytes")
        return
    if not FileAccess.file_exists(abs_path + ".bak"):
        _fail("second save should retain backup")
        return

    # Corrupt a valid JSON field without updating the digest. Primary must
    # be rejected and the valid backup restored without changing live state.
    var tampered: Dictionary = wrapped.duplicate(true)
    tampered["payload"]["tick"] = 9000
    var file := FileAccess.open(abs_path, FileAccess.WRITE)
    file.store_string(JSON.stringify(tampered))
    file.close()
    var resumed = Runner.new()
    if not resumed.start_from_seed(seed):
        _fail("second seed initialization")
        return
    var recovered: Dictionary = Saves.load_runner(resumed, seed, path)
    if not recovered.get("ok", false) or recovered.get("source", "") != abs_path + ".bak":
        _fail("tampered primary must fall back to backup")
        return
    if resumed.tick_count != 7:
        _fail("backup restored wrong tick")
        return

    # A fresh save must not replace a valid backup with a corrupted primary.
    if Saves.save_runner(resumed, path) != OK:
        _fail("save after corrupt primary")
        return
    if Saves._read_checkpoint(abs_path + ".bak").is_empty():
        _fail("known-good backup lost after corrupt primary")
        return

    # Reject corrupt primary AND backup without mutating the live runner.
    var bad := FileAccess.open(abs_path, FileAccess.WRITE)
    bad.store_string("{")
    bad.close()
    bad = FileAccess.open(abs_path + ".bak", FileAccess.WRITE)
    bad.store_string("{")
    bad.close()
    if Saves.load_runner(resumed, seed, path).get("ok", false):
        _fail("two invalid files accepted")
        return
    if resumed.tick_count != 7:
        _fail("failed load mutated live state")
        return

    # Historical P1 checkpoints have no envelope; preserve compatibility.
    var legacy := FileAccess.open(abs_path, FileAccess.WRITE)
    legacy.store_string(JSON.stringify(original))
    legacy.close()
    if not Saves.load_runner(resumed, seed, path).get("ok", false):
        _fail("legacy checkpoint no longer loads")
        return
    if resumed.tick_count != 7:
        _fail("legacy checkpoint tick")
        return
    for suffix in ["", ".bak", ".pending"]:
        if FileAccess.file_exists(abs_path + suffix):
            DirAccess.remove_absolute(abs_path + suffix)
    print("N38_SAVE_INTEGRITY_PASS: deterministic digest, tamper, fallback, backup, legacy")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N38_SAVE_INTEGRITY_FAIL: " + reason)
    quit(1)
