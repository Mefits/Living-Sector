extends SceneTree
## Local-only N130/N156 acceptance. Do NOT trigger GitHub Actions for this.
## godot --headless --path godot --script res://tests/p2_n130_service_repair_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const N158 = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var frozen: Dictionary = NativeData.load_current_world()
    if frozen.has("error"):
        _fail("frozen Galaxy 0.6.7 seed not found: " + str(frozen["error"]))
        return
    var projected: Dictionary = Adapter.from_seed(frozen)
    if not projected.get("ok", false):
        _fail("real source N39 adapter failed: " + str(projected))
        return
    var world: Dictionary = projected["world"]
    # TEST-ONLY boundary conditions; these are NOT committed to the seed.
    # Sufficient local Tools/Fuel for every real seed facility at tick 20,
    # and low enough initial condition to require a paid repair at tick 40.
    for location in world["markets"]:
        world["markets"][location]["supply"]["tools"] = 5000.0
        world["markets"][location]["supply"]["fuel"] = 5000.0
    for id in world["facilities"]:
        world["facilities"][id]["condition"] = 0.75
        world["facilities"][id]["reserves"] = {}
    if Schema.validate(world) != "":
        _fail("test fixture invalid: " + Schema.validate(world))
        return
    var original_cash: int = _total_cash(world)
    var engine = N39.new()
    if not engine.initialize(world):
        _fail("N39 could not boot exact seeded physical world")
        return
    var at_twenty: Dictionary = {}
    var actual_repair_tick: Dictionary = {}
    for tick in range(1, 41):
        var result: Dictionary = engine.run_tick(tick, 1, {}, 1.0)
        if not result.get("ok", false):
            _fail("canonical N39 stage failed at tick %d: %s" % [tick, str(result)])
            return
        if tick == 20:
            at_twenty = engine.world_snapshot()
            if not result.get("paid_repairs", []).is_empty():
                _fail("repair used unowned Tools before native restock")
                return
            if result.get("service_restock", []).is_empty():
                _fail("native N130 service restock did not buy any real goods")
                return
            for id in at_twenty["facilities"]:
                var facility: Dictionary = at_twenty["facilities"][id]
                if float(facility["reserves"].get("tools", 0.0)) < 1.0:
                    _fail("real facility did not receive private Tool reserves: " + str(id))
                    return
            if _total_cash(at_twenty) != original_cash:
                _fail("N130 restock minted or destroyed credits")
                return
            # 15 owners in three markets. No Food/Water transfers to services.
            for location in at_twenty["markets"]:
                var market: Dictionary = at_twenty["markets"][location]
                if float(market["supply"]["food"]) < 0.0:
                    _fail("restock stole household Food")
                    return
        if tick == 40:
            actual_repair_tick = result.duplicate(true)
    var now: Dictionary = engine.world_snapshot()
    var repaired: Array = actual_repair_tick.get("paid_repairs", [])
    if repaired.is_empty():
        _fail("N156 paid repair never occurred after owned Tools arrived")
        return
    var source_facility: String = str(repaired[0]["facility"])
    var before_tools: float = float(at_twenty["facilities"][source_facility]["reserves"]["tools"])
    var now_tools: float = float(now["facilities"][source_facility]["reserves"]["tools"])
    if not is_equal_approx(before_tools - now_tools, 1.0):
        _fail("paid repair must consume EXACTLY one facility-owned Tool")
        return
    var before_condition: float = float(at_twenty["facilities"][source_facility]["condition"])
    var after_condition: float = float(now["facilities"][source_facility]["condition"])
    if after_condition <= before_condition:
        _fail("real paid repair did not restore condition after decay")
        return
    var real_shift: Dictionary = now["facilities"][source_facility].get("work_shift", {})
    if int(real_shift.get("tick", -1)) != 40 or int(real_shift.get("wages", 0)) <= 0:
        _fail("repair did not commit a real N39 paid WorkShift")
        return
    var before_and_after: Dictionary = engine.snapshot()
    var receipts: Dictionary = before_and_after["ledger"]["receipts"]
    if not receipts.has(str(repaired[0]["receipt"])):
        _fail("repair wages missing from the ONLY N9 ledger")
        return
    var restock_paid: bool = false
    for operation_id in receipts:
        if str(operation_id).begins_with("n130/service/20/"):
            restock_paid = true
            break
    if not restock_paid:
        _fail("N130 purchases not recorded in the ONLY N9 ledger")
        return
    if _total_cash(now) != original_cash or Schema.validate(now) != "":
        _fail("N130/N156 mutated total credits or corrupted canonical world schema")
        return
    # A real JSON checkpoint round-trip must preserve the same Tools/condition,
    # signed payroll receipts and market stock, not create a second N39 ledger.
    var decoded: Variant = JSON.parse_string(JSON.stringify(before_and_after))
    if not (decoded is Dictionary):
        _fail("N39 JSON checkpoint could not be decoded")
        return
    var normalizer = N158.new()
    if not normalizer._normalize_native_snapshot(decoded):
        _fail("N158 JSON integer normalization rejected N130/N156 checkpoint")
        return
    var restored = N39.new()
    if not restored.restore(decoded):
        _fail("N39 did not restore exact paid-repair and restock checkpoint")
        return
    var restored_world: Dictionary = restored.world_snapshot()
    if restored.snapshot()["ledger"] != before_and_after["ledger"]:
        _fail("N9 receipts/balances changed after JSON save/load")
        return
    for id in now["facilities"]:
        var fac: Dictionary = now["facilities"][id]
        var rf: Dictionary = restored_world["facilities"][id]
        if fac["credits"] != rf["credits"] or fac.get("work_shift", {}) != rf.get("work_shift", {}):
            _fail("paid wage receipt changed after restore: " + str(id))
            return
        if fac.get("reserves", {}) != rf.get("reserves", {}) or fac["abandoned"] != rf["abandoned"]:
            _fail("private service inventory changed after restore: " + str(id))
            return
        if absf(float(fac["condition"]) - float(rf["condition"])) > 0.000001:
            _fail("facility condition changed after JSON restore: " + str(id))
            return
    for location in now["markets"]:
        var old_supply: Dictionary = now["markets"][location]["supply"]
        var new_supply: Dictionary = restored_world["markets"][location]["supply"]
        for commodity in old_supply:
            if not new_supply.has(commodity) or absf(
                    float(old_supply[commodity]) - float(new_supply[commodity])) > 0.000001:
                _fail("physical market stock changed after JSON restore: " +
                    str(location) + "/" + str(commodity))
                return
    print("P2_N130_N156_SERVICE_ACCEPTANCE_PASS: owned Tools/Fuel restock, paid repair, one ledger, native order, exact JSON restart")
    quit(0)

func _total_cash(state: Dictionary) -> int:
    var result: int = 0
    for id in state.get("facilities", {}):
        result += int(state["facilities"][id]["credits"])
    for id in state.get("populations", {}):
        result += int(state["populations"][id]["wealth"])
    return result

func _fail(reason: String) -> void:
    push_error("P2_N130_N156_SERVICE_ACCEPTANCE_FAIL: " + reason)
    quit(1)
