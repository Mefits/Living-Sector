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
    if a.implemented_phases() != PackedStringArray(["bodies", "ships", "facilities", "populations", "markets"]):
        _fail("N158 must advertise only the five actually wired P2 phases")
        return
    if a.fleet_snapshot().size() != 24:
        _fail("24 real N46 source ships were not admitted to N39 world")
        return
    var before: Dictionary = a.economy_snapshot()
    if before["markets"]["earth-station"]["owner"] != "facility-earth-station":
        _fail("physical market owner not resolved from frozen station")
        return
    var food_price_before: float = float(before["markets"]["earth-station"]["prices"]["food"])
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
    var population_phase: Dictionary = a.last_population_result()
    if not population_phase.get("ok", false) or int(population_phase.get("purchases", 0)) < 6:
        _fail("N151 real paid Food/Water consumption not applied: " + str(population_phase))
        return
    if int(current["populations"]["pop-residents-earth-station"]["food_satisfaction"]) != 72:
        _fail("N151 original household food satisfaction did not recover after both needs")
        return
    if current["markets"]["earth-station"]["consumption_window"].get("food", []).size() != 1:
        _fail("real N151 Food consumption absent from SAME N150 MarketFlow")
        return
    if not a.last_market_result().get("ok", false):
        _fail("N150 real market tick rejected: " + str(a.last_market_result()))
        return
    if float(current["markets"]["earth-station"]["prices"]["food"]) >= food_price_before:
        _fail("same real market must reprice supplied food using original N131 engine")
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
    var receipts: Dictionary = a.production.snapshot()["ledger"]["receipts"]
    var purchased: int = 0
    for receipt_id in receipts:
        if str(receipt_id).begins_with("n151/consumption/"):
            purchased += 1
    if purchased < 6:
        _fail("N151 purchases did not create real N9 paid transfer receipts")
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
    var restored_supply: Dictionary = b.economy_snapshot()["markets"]["earth-station"]["supply"]
    if b.tick_count != 5 or restored_supply != produced:
        _fail("physical market stock mismatch after file restart: tick=%d expected=5; %s" % [
            b.tick_count, _stock_restore_diff(produced, restored_supply)])
        return
    if b.economy_snapshot()["markets"]["earth-station"]["prices"] != current["markets"]["earth-station"]["prices"]:
        _fail("N150 real market prices changed across file restart")
        return
    var expected_flow: Dictionary = current["markets"]["earth-station"]["consumption_window"]
    var restored_flow: Dictionary = b.economy_snapshot()["markets"]["earth-station"]["consumption_window"]
    if restored_flow != expected_flow:
        _fail("N151 consumed Food/Water rolling MarketFlow was not restored; expected=" +
            JSON.stringify(expected_flow, "", true, true) + " actual=" +
            JSON.stringify(restored_flow, "", true, true))
        return
    for commodity in restored_flow:
        for sample in restored_flow[commodity]:
            if not (sample is Dictionary) or typeof(sample.get("tick")) != TYPE_INT:
                _fail("N151 restored MarketFlow sample tick must remain TYPE_INT: " + str(commodity))
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
    b.queue_control("step", 6)
    b.advance_frame(0.0)
    if b.tick_count != 16:
        _fail("N150 real-market time cursor failed to reach 16")
        return
    var trends: Array = b.economy_snapshot()["markets"]["earth-station"]["history"]["trend_samples"]
    if trends.size() != 1 or int(trends[0]["tick"]) != 16:
        _fail("N150 market trend sample must be stored on real tick 16")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_UNIFIED_ECONOMY_ACCEPTANCE_PASS: source 8/3, N39 production, N151 paid Food/Water, N150 price/trend, single ledger, saved/restarted")
    quit(0)

func _stock_restore_diff(expected: Dictionary, actual: Dictionary) -> String:
    # Exact values matter for deterministic physical inventory. Do not hide
    # serialization loss behind approximate comparisons or mutate live stock.
    var keys: Array = expected.keys()
    for key in actual.keys():
        if not keys.has(key):
            keys.append(key)
    keys.sort()
    var differences: PackedStringArray = PackedStringArray()
    for key in keys:
        if not expected.has(key):
            differences.append("%s: unexpected=%s" % [str(key), str(actual[key])])
        elif not actual.has(key):
            differences.append("%s: missing expected=%s" % [str(key), str(expected[key])])
        elif expected[key] != actual[key]:
            differences.append("%s: expected=%s actual=%s delta=%s" % [
                str(key), str(expected[key]), str(actual[key]),
                str(float(actual[key]) - float(expected[key]))])
    if differences.is_empty():
        return "stocks equal; investigate tick mismatch"
    return "; ".join(differences)


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
