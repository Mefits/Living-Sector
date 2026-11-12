extends SceneTree
## N36 startup and real Control wiring acceptance. Run after headless editor import.
## Godot --headless --path godot --script res://tests/n36_startup_compat_check.gd
## CODE_UNVERIFIED until this script is actually run in Godot.
const MainScene = preload("res://scenes/main.tscn")
const NativeData = preload("res://scripts/native_data.gd")
var _test_save_path: String = ""

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var main: Control = MainScene.instantiate()
    root.add_child(main)
    await process_frame
    var health: Dictionary = main.call("startup_health")
    if not health.get("ok", false):
        _fail("boot health: " + JSON.stringify(health))
        return
    if health.get("implemented_phases") != PackedStringArray(["bodies"]):
        _fail("unimplemented economy advertised as live")
        return
    var runner = main.get("_runner")
    if runner == null or runner.tick_count != 0:
        _fail("invalid initial tick")
        return
    # Exercise the real Control wiring rather than only constructing the model.
    main.call("_toggle_pause")
    if not runner.clock.paused:
        _fail("pause button did not pause")
        return
    main.call("_step", 3)
    if runner.tick_count != 3 or not runner.clock.paused:
        _fail("step while paused must execute precisely three ticks")
        return
    main.call("_change_speed", 5)
    if not is_equal_approx(float(runner.clock.world_speed), 16.0):
        _fail("speed menu x16 did not reach clock")
        return
    main.call("_toggle_observer")
    if not main.get("_observer_panel").visible:
        _fail("observer panel did not open")
        return
    main.call("_toggle_observer")
    if main.get("_observer_panel").visible:
        _fail("observer panel did not close")
        return
    var before: Dictionary = runner.checkpoint()
    # Isolated test path: never overwrite the player's actual save or backup.
    _test_save_path = "user://tests/n36-startup-" + str(Time.get_ticks_usec()) + ".json"
    main.call("_save_game", _test_save_path)
    main.call("_step", 2)
    if runner.tick_count != 5:
        _fail("second manual step failed")
        return
    main.call("_load_game", _test_save_path)
    if runner.tick_count != 3 or runner.checkpoint().get("seed_fingerprint") != before.get("seed_fingerprint"):
        _fail("UI save/load did not restore tick and seed")
        return
    # A live seed reload must not secretly create resources or contracts.
    var current: Dictionary = NativeData.load_current_world()
    if current.has("error") or runner.world.seed_stats().get("ships", 0) != current.get("seed_stats", {}).get("ships", -1):
        _fail("seed ship count changed")
        return
    _cleanup_test_save()
    print("N36_STARTUP_PASS ", JSON.stringify(main.call("startup_health")))
    main.queue_free()
    quit(0)

func _fail(reason: String) -> void:
    _cleanup_test_save()
    push_error("N36_STARTUP_FAIL " + reason)
    quit(1)

func _cleanup_test_save() -> void:
    if _test_save_path.is_empty():
        return
    var absolute_path: String = ProjectSettings.globalize_path(_test_save_path)
    for suffix in ["", ".bak", ".pending"]:
        var candidate: String = absolute_path + suffix
        if FileAccess.file_exists(candidate):
            DirAccess.remove_absolute(candidate)
    _test_save_path = ""
