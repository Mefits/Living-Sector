extends SceneTree
## Short Godot headless P1 parity check, no Rust compile, no plugin.
## Run: Godot --headless --path godot --script res://tests/p1_tick_save_check.gd

const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/tick_runner.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed missing: " + str(seed["error"]))
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("runner seed boot")
        return

    # Native defaults: 8 TPS, world_speed 0.25, tick_scale = 0.03125
    if runner.clock.ticks_per_second != 8 or not is_equal_approx(runner.clock.tick_scale(), 0.03125):
        _fail("native tick defaults changed")
        return
    if runner.implemented_phases() != PackedStringArray(["bodies"]):
        _fail("unported economy/ship phases must not be advertised")
        return

    var sol_seed: Dictionary = runner.world.system_by_id("system-sol")
    var first_earth_angle: float = _body_angle(sol_seed, "earth")
    if not runner.queue_control("pause") or runner.queue_control("transfer_credits", 10000):
        _fail("pause rejected or unsupported economy command accepted")
        return
    runner.advance_frame(0.0)
    runner.advance_frame(1.0)
    if runner.tick_count != 0:
        _fail("pause should prohibit automatic world ticks")
        return

    if not runner.queue_control("step", 8):
        _fail("manual step rejected")
        return
    runner.advance_frame(0.0)
    if runner.tick_count != 8:
        _fail("manual step should advance precisely eight native ticks")
        return
    var sol_after: Dictionary = runner.world.system_by_id("system-sol")
    var expected: float = fposmod(first_earth_angle +
        (360.0 / 700.0) * 0.03125 * 8.0, 360.0)
    if absf(_body_angle(sol_after, "earth") - expected) > 0.0001:
        _fail("body orbital formula differs from Rust")
        return
    if JSON.stringify(sol_seed.get("markets", [])) != JSON.stringify(sol_after.get("markets", [])):
        _fail("P1 orbital ticks must not mutate market inventory or prices")
        return
    if JSON.stringify(sol_seed.get("ships", [])) != JSON.stringify(sol_after.get("ships", [])):
        _fail("P1 orbital ticks must not mutate ship cargo or funds")
        return
    if JSON.stringify(sol_seed.get("facilities", [])) != JSON.stringify(sol_after.get("facilities", [])):
        _fail("P1 orbital ticks must not create real facilities")
        return

    var snapshot: Dictionary = runner.checkpoint()
    var failed: Dictionary = snapshot.duplicate(true)
    failed["seed_fingerprint"] = "wrong-world"
    if runner.restore_checkpoint(failed, seed):
        _fail("invalid save fingerprint must be rejected")
        return
    if runner.tick_count != 8:
        _fail("failed restore may not partially change tick")
        return

    var path: String = "user://tests/p1-orbits-" + str(Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(runner, path) != OK:
        _fail("P1 file save failed")
        return
    var resumed = Runner.new()
    if not resumed.start_from_seed(seed):
        _fail("second boot failed")
        return
    var restored: Dictionary = Saves.load_runner(resumed, seed, path)
    if not restored.get("ok", false):
        _fail("P1 file reload failed: " + str(restored.get("error", "unknown")))
        return
    if resumed.tick_count != 8 or not resumed.clock.paused:
        _fail("tick and paused state must survive reload")
        return
    if absf(_body_angle(resumed.world.system_by_id("system-sol"), "earth") -
            _body_angle(sol_after, "earth")) > 0.00001:
        _fail("body orbit not restored")
        return
    if not resumed.queue_control("speed", 16.0):
        _fail("x16 should be accepted by native clock")
        return
    resumed.advance_frame(0.0)
    if not is_equal_approx(resumed.clock.tick_scale(), 2.0):
        _fail("native x16 scale must be speed/tps = 2.0")
        return
    # Manual steps while paused at 16x are *exactly* one native orbital step each.
    resumed.queue_control("step", 1)
    resumed.advance_frame(0.0)
    if resumed.tick_count != 9:
        _fail("single step after reload must be exactly once")
        return

    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P1_PARITY_PASS: seed 8/3, native clock, pause/step/x16, orbit, no economy drift, atomic save/load")
    quit(0)

func _body_angle(world: Dictionary, body_id: String) -> float:
    for body in world.get("bodies", []):
        if str(body.get("id", "")) == body_id:
            return float(body.get("current_angle", -1.0))
    return -1.0

func _fail(problem: String) -> void:
    push_error("P1_PARITY_FAIL: " + problem)
    quit(1)
