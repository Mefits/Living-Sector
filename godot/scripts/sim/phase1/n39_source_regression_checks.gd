extends RefCounted
## N39 frozen-source regression probes. AUTHORED, NOT RUN (Phase1).
## Run with Godot 4 headless in Phase2 after checking parser and fixtures.
const WorldBridge = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

static func run_all() -> Dictionary:
    var checks: Dictionary = {}
    var source: Dictionary = _seed("refinery", {"ore": 100.0, "fuel": 20.0}, {})
    var engine = WorldBridge.new()
    checks["real_world_initializes"] = engine.initialize(source)
    var result: Dictionary = _through_five(engine)
    var stock: Dictionary = engine.world_snapshot()["markets"]["terra"]["supply"]
    checks["multi_batch_physical_inputs"] = result.get("ok", false) and is_equal_approx(float(stock["ore"]), 0.0) and is_equal_approx(float(stock["fuel"]), 10.0)
    checks["produced_paid_metals"] = is_equal_approx(float(stock.get("metals", 0.0)), 80.0)
    checks["single_wage_with_service_fee"] = engine.balance_of_facility("hub") == 995 and engine.balance_of_facility("producer") == 101 and engine.balance_of_population("household") == 24
    checks["production_receipt_proves_recipe"] = engine.world_snapshot()["facilities"]["producer"]["work_shift"]["last_recipe_ticks"].get("smelt_metals") == 5
    var before_repeat: Dictionary = engine.snapshot()
    checks["same_tick_rejected_without_mutation"] = not engine.run_tick(5).get("ok", true) and engine.snapshot() == before_repeat
    var restore = WorldBridge.new()
    checks["valid_checkpoint_roundtrip"] = restore.restore(before_repeat) and restore.snapshot() == before_repeat
    var forged: Dictionary = before_repeat.duplicate(true)
    forged["world"]["facilities"]["hub"]["credits"] = 123456
    var reject = WorldBridge.new()
    checks["reject_fake_wallet_restore"] = not reject.restore(forged)
    var bankrupted = WorldBridge.new()
    var no_cash: Dictionary = _seed("refinery", {"ore": 100.0, "fuel": 20.0}, {}, 0)
    bankrupted.initialize(no_cash)
    var failed: Dictionary = _through_five(bankrupted)
    checks["reject_unpaid_output_and_stock_intact"] = failed.get("failures", {}).get("producer") == "insufficient_processing_budget" and is_equal_approx(float(bankrupted.world_snapshot()["markets"]["terra"]["supply"]["ore"]), 100.0)
    var no_labor = WorldBridge.new()
    no_labor.initialize(_seed("refinery", {"ore": 100.0, "fuel": 20.0}, {}, 1000, 0))
    var blocked: Dictionary = _through_five(no_labor)
    checks["reject_phantom_employees"] = blocked.get("failures", {}).get("producer") == "insufficient_workers" and float(no_labor.world_snapshot()["markets"]["terra"]["supply"]["ore"]) == 100.0
    var farm = WorldBridge.new()
    farm.initialize(_seed("farm", {"water": 30.0, "food": 4999.0}, {}))
    _through_five(farm)
    var food: Dictionary = farm.world_snapshot()["markets"]["terra"]["supply"]
    checks["farm_fractional_5000_cap"] = is_equal_approx(float(food["food"]), 5000.0) and is_equal_approx(float(food["water"]), 29.7)
    var miner = WorldBridge.new()
    miner.initialize(_seed("mining_rig", {"ore": 100.0}, {"ore": 1.0}))
    _through_five(miner)
    checks["mining_yield_real_body"] = is_equal_approx(float(miner.world_snapshot()["markets"]["terra"]["supply"]["ore"]), 180.0) and is_equal_approx(float(miner.world_snapshot()["bodies"]["body-main"]["resources"]["ore"]), 1.0)
    var salvage = WorldBridge.new()
    salvage.initialize(_seed("salvage_field", {"ore": 0.0}, {"ore": 1.0}))
    _through_five(salvage)
    var salvaged: Dictionary = salvage.world_snapshot()
    checks["salvage_depletes_finite_body"] = float(salvaged["markets"]["terra"]["supply"]["ore"]) > 0.0 and float(salvaged["bodies"]["body-main"]["resources"]["ore"]) < 1.0
    var locked = WorldBridge.new()
    locked.initialize(_seed("alloyplant2", {"rare_ore": 100.0, "metals": 100.0, "fuel": 100.0}, {}))
    var research_fail: Dictionary = _through_five(locked)
    checks["t2_faction_research_gate"] = research_fail.get("failures", {}).get("producer") == "research_required"
    var bad: Dictionary = _seed("mining_rig", {"ore": 1.0}, {"ore": -5.0})
    checks["reject_negative_body_resources"] = Schema.validate(bad) == "invalid_body_resources"
    var total: int = checks.size()
    var passed: int = 0
    for name in checks:
        if checks[name]:
            passed += 1
    return {"passed": passed, "total": total, "all_passed": passed == total,
        "checks": checks}

static func _through_five(engine: RefCounted) -> Dictionary:
    var result: Dictionary = {}
    for tick in range(1, 6):
        result = engine.run_tick(tick)
        if not result.get("ok", false):
            break
    return result

static func _seed(facility_type: String, supply: Dictionary, body_resources: Dictionary,
        owner_cash: int = 1000, population_count: int = 100) -> Dictionary:
    return {
        "facilities": {
            "hub": {"type": "station", "faction": "blue", "location": "terra",
                "body_id": "body-main", "level": 1, "xp": 0, "abandoned": false,
                "crew_count": 0, "morale": 100.0, "credits": owner_cash},
            "producer": {"type": facility_type, "faction": "blue", "location": "terra",
                "body_id": "body-main", "level": 1, "xp": 0, "abandoned": false,
                "crew_count": 4, "morale": 100.0, "credits": 100}
        },
        "markets": {"terra": {"owner": "hub",
            "supply": supply.duplicate(true), "prices": {}, "limits": {}}},
        "populations": {"household": {"faction": "blue", "location": "terra",
            "count": population_count, "wealth": 20, "employed_fraction": 0.0}},
        "bodies": {"body-main": {"resources": body_resources.duplicate(true)}},
        "research": {}, "location_tiers": {}, "station_executing": false
    }
