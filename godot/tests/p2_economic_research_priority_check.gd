extends SceneTree
## Controlled comparison through the real N39/N143/N9 execution path.
const EngineWorld = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Fixture = preload("res://scripts/sim/phase1/n39_source_regression_checks.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

const EXPANSIONIST := {"blue": {"id": "blue",
    "personality": {"prefer_goals": {"leader_expansionist": 1.0}}}}
const ISOLATIONIST := {"blue": {"id": "blue",
    "personality": {"prefer_goals": {"leader_isolationist": 1.0}}}}

func _initialize() -> void:
    if not _case(200.0, 210.0, 100.0, 240000, EXPANSIONIST, "industrial_methods", 168.0):
        quit(1)
        return
    if not _case(0.0, 210.0, 100.0, 240000, EXPANSIONIST, "orbital_habitats", 160.0):
        quit(1)
        return
    if not _case(200.0, 0.0, 100.0, 240000, EXPANSIONIST, "orbital_habitats", 0.0):
        quit(1)
        return
    if not _case(0.0, 210.0, 100.0, 240000, ISOLATIONIST, "industrial_methods", 168.0):
        quit(1)
        return
    if not _case(200.0, 210.0, 0.0, 240000, EXPANSIONIST, "", 160.0):
        quit(1)
        return
    if not _case(200.0, 210.0, 100.0, 1000, EXPANSIONIST, "", 160.0):
        quit(1)
        return
    print("P2_ECONOMIC_RESEARCH_PRIORITY_PAID_CAPACITY_PASS")
    quit(0)

func _case(demand: float, ore: float, food: float, treasury: int,
        faction: Dictionary, expected: String, metals_after: float) -> bool:
    var input: Dictionary = Fixture._seed("refinery", {
        "ore": ore, "fuel": 40.0, "food": food, "water": 100.0,
        "electronics": 20.0, "metals": 0.0
    }, {})
    var market: Dictionary = input["markets"]["terra"]
    market["id"] = "market-terra"
    market["prices"] = {"ore": 2.0, "fuel": 5.0, "metals": 15.0, "electronics": 20.0}
    market["demand"] = {"metals": demand}
    market["history"] = {"shortage_ticks": {"metals": 10}}
    input["research"]["blue"] = []
    input["faction_treasuries"] = {"blue": treasury}
    input["research_receipts"] = {}
    input["research_directors"] = {"blue": {"technologies": [], "research": null,
        "progress": 0, "research_required": 0, "history": [], "profile": {}}}

    var world = EngineWorld.new()
    if not world.initialize(input):
        return _fail("fixture schema " + Schema.validate(input))
    var paid_count: int = 0
    for tick in range(1, 6):
        var production: Dictionary = world.run_tick(tick)
        if not production.get("ok", false):
            return _fail(str(production))
        if tick == 5:
            break
        var result: Dictionary = world.apply_native_research_phase(tick, faction, 1)
        if not result.get("ok", false):
            return _fail(str(result))
        for receipt: Dictionary in result["paid"]:
            paid_count += 1
            if receipt["technology"] != expected:
                return _fail("unexpected technology " + str(receipt))
            var expected_unlock: Variant = "industrial_methods" if (
                tick == 4 and expected == "industrial_methods") else null
            if receipt.get("completed_technology") != expected_unlock:
                return _fail("technology completion must follow the final paid shift")
            var money: Dictionary = world.ledger_snapshot()["receipts"].get(receipt["n9_receipt_id"], {})
            if money.get("kind") != "n143_native_research_shift" or int(receipt["cost"]) != 30:
                return _fail("missing paid N9 shift")
        if tick == 1 and expected == "industrial_methods":
            # Checkpoint with paid progress. Later ticks must keep the incumbent.
            var resumed = EngineWorld.new()
            if not resumed.restore(world.snapshot()):
                return _fail("paid project failed to restore")
            world = resumed

    var state: Dictionary = world.world_snapshot()
    var stock: Dictionary = state["markets"]["terra"]["supply"]
    var industrial: bool = expected == "industrial_methods"
    if ore > 0.0:
        var shift: Dictionary = state["facilities"]["producer"]["work_shift"]
        var payroll: Dictionary = world.ledger_snapshot()["receipts"].get(shift.get("receipt"), {})
        if payroll.get("kind") != "native_paid_production" or (
                shift["last_recipe_ticks"].get("smelt_metals") != 5):
            return _fail("missing paid production shift or verified recipe")
    var expected_count: int = 0 if expected.is_empty() else 4
    if paid_count != expected_count or state["research_receipts"].size() != expected_count:
        return _fail("incorrect paid shift count " + str(paid_count))
    if float(stock["electronics"]) != 20.0 - expected_count:
        return _fail("research did not consume electronics")
    if world.ledger_snapshot()["balances"]["faction/blue"] != treasury - 30 * expected_count:
        return _fail("research did not debit the real treasury")
    if state["research"]["blue"].has("industrial_methods") != industrial:
        return _fail("incorrect capacity unlock")
    if not is_equal_approx(float(stock["metals"]), metals_after):
        return _fail("incorrect physical metals output: " + str(stock))
    if ore > 0.0 and (float(stock["ore"]) != (0.0 if industrial else 10.0) or
            float(stock["fuel"]) != (19.0 if industrial else 20.0)):
        return _fail("incorrect physical recipe input use: " + str(stock))
    return true

func _fail(reason: String) -> bool:
    push_error("P2_ECONOMIC_RESEARCH_PRIORITY_FAIL: " + reason)
    return false
