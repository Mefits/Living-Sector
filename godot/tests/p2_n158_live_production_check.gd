extends SceneTree
## P2-N158 FIRST LIVE INTEGRATION acceptance test.
## Command: godot --headless --path godot --script res://tests/p2_n158_live_production_check.gd
## This file is AUTHORED, NOT YET EXECUTED in the GitHub-only environment.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("source seed unavailable: " + str(seed["error"]))
        return
    var a = Runner.new()
    if not a.start_from_seed(seed):
        _fail("P2 seed projection boot: " + a.boot_error())
        return
    if a.clock.ticks_per_second != 8 or a.clock.tick_multiplier() != 32:
        _fail("original Rust 8 TPS / x0.25 tick_multiplier must be 32")
        return
    var stats: Dictionary = a.production_stats()
    if stats.get("markets") != 3 or stats.get("active_facilities") != 15 or stats.get("populations") != 3:
        _fail("unexpected original source market/facility/population counts: " + str(stats))
        return
    if a.implemented_phases() != PackedStringArray(["bodies", "facilities"]):
        _fail("only bodies and N39 facilities may advertise real execution")
        return
    var before: Dictionary = a.economy_snapshot()
    if before["markets"]["earth-station"]["owner"] != "facility-earth-station":
        _fail("physical market owner not resolved from frozen station")
        return
    var bank_before: int = _sum_credits(before)
    var earth_before: Dictionary = before["markets"]["earth-station"]["supply"]
    a.queue_control("pause")
    a.queue_control("speed", 8.0)
    a.advance_frame(0.0)
    if a.clock.tick_multiplier() != 1:
        _fail("source x8 tick_multiplier must be 1")
        return
    a.advance_frame(1.0)
    if a.tick_count != 0 or a.economy_snapshot() != before:
        _fail("paused simulation must not pay wages or move stock")
        return
    a.queue_control("step", 5)
    a.advance_frame(0.0)
    if a.tick_count != 5:
        _fail("one native five-tick production step")
        return
    var current: Dictionary = a.economy_snapshot()
    var produced: Dictionary = current["markets"]["earth-station"]["supply"]
    var result: Dictionary = a.last_native_result()
    if not result.get("ok", false) or result.get("receipts", []).size() <= 0:
        _fail("paid facility output did not execute: " + JSON.stringify(result))
        return
    if produced == earth_before:
        _fail("real source physical market inventory did not change")
        return
    if _sum_credits(current) != bank_before:
        _fail("wages or stock fee created/destroyed credits")
        return
    var paid_for_real: bool = false
    for facility_id in current["facilities"]:
        var shift: Dictionary = current["facilities"][facility_id].get("work_shift", {})
        if not shift.is_empty() and int(shift.get("tick", -1)) == 5 and int(shift.get("wages", 0)) > 0:
            paid_for_real = true
            break
    if not paid_for_real:
        _fail("market output was not backed by paid workforce")
        return
    var source_save: Dictionary = a.checkpoint()
    if not source_save.has("native_production") or int(source_save["native_production"]["tick"]) != 5:
        _fail("N39 physical state absent from save checkpoint")
        return
    var path: String = "user://tests/p2-n158-production-" + str(Time.get_ticks_usec()) + ".json"
    var write_result: Error = Saves.save_runner(a, path)
    if write_result != OK:
        _fail("atomic native production save failed: " + str(write_result))
        return
    var b = Runner.new()
    if not b.start_from_seed(seed):
        _fail("second real seed boot failed")
        return
    var loaded: Dictionary = Saves.load_runner(b, seed, path)
    if not loaded.get("ok", false):
        _fail("native production restore failed: " + str(loaded.get("error", "")))
        return
    if b.tick_count != 5 or b.economy_snapshot()["markets"]["earth-station"]["supply"] != produced:
        _fail("physical market stock mismatch after file restart")
        return
    if _sum_credits(b.economy_snapshot()) != bank_before:
        _fail("funds conservation failed across file restart")
        return
    var invalid: Dictionary = b.checkpoint()
    invalid["native_production"]["world"]["markets"]["earth-station"]["supply"]["ore"] = -100.0
    var stable: Dictionary = b.checkpoint()
    if b.restore_checkpoint(invalid, seed) or b.checkpoint() != stable:
        _fail("failed checkpoint validation mutated live economic world")
        return
    b.queue_control("pause")
    b.queue_control("step", 5)
    b.advance_frame(0.0)
    if b.tick_count != 10 or _sum_credits(b.economy_snapshot()) != bank_before:
        _fail("source production did not resume without double payroll at tick 10")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_N158_PRODUCTION_ACCEPTANCE_PASS: frozen seed 8/3, live goods, paid payroll, tick, conservation, checkpoint/restart")
    quit(0)

func _sum_credits(world: Dictionary) -> int:
    var result: int = 0
    for id in world.get("facilities", {}):
        result += int(world["facilities"][id]["credits"])
    for id in world.get("populations", {}):
        result += int(world["populations"][id]["wealth"])
    return result

func _fail(reason: String) -> void:
    push_error("P2_N158_PRODUCTION_ACCEPTANCE_FAIL: " + reason)
    quit(1)
