extends SceneTree
const Admission = preload("res://scripts/sim/phase2/unified_contract_demand_admission.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {
            "buyer": {"location": "dst", "credits": 100},
            "seller": {"location": "src", "credits": 20}
        },
        "markets": {
            "src": {"owner": "seller", "supply": {"Water": 10.0}},
            "dst": {"owner": "buyer", "supply": {"Water": 0.0},
                "prices": {"Water": 4.0}}
        }
    }
    var ledger: Dictionary = {"balances": {"facility/buyer": 100,
        "facility/seller": 20}, "receipts": {}}
    var demand: Dictionary = {"id": "n135:need:dst:Water",
        "status": "UNFUNDED_PROPOSAL", "tick": 5,
        "station_id": "buyer", "source_station_id": "seller",
        "location": "dst", "source_location": "src",
        "commodity": "Water", "quantity": 5, "estimated_cost": 20}
    var baseline: Dictionary = world.duplicate(true)
    var result: Dictionary = Admission.validate(world, ledger, demand, 5)
    if not result.get("ok", false) or result.get("status") != "VALIDATED_NOT_COMMITTED":
        _fail("real funded physical order rejected: " + str(result))
        return
    if world != baseline:
        _fail("validator mutated canonical stock")
        return
    world["markets"]["src"]["supply"]["Water"] = 4.0
    if Admission.validate(world, ledger, demand, 5).get("reason") != "source_stock_changed":
        _fail("stale source inventory accepted")
        return
    world["markets"]["src"]["supply"]["Water"] = 10.0
    ledger["balances"]["facility/buyer"] = 10
    world["facilities"]["buyer"]["credits"] = 10
    if Admission.validate(world, ledger, demand, 5).get("reason") != "payer_insufficient_funds":
        _fail("unfunded escrow accepted")
        return
    ledger["balances"]["facility/buyer"] = 100
    world["facilities"]["buyer"]["credits"] = 100
    world["markets"]["dst"]["prices"]["Water"] = 5.0
    if Admission.validate(world, ledger, demand, 5).get("reason") != "stale_or_invalid_offer":
        _fail("stale N150 price accepted")
        return
    world["markets"]["dst"]["prices"]["Water"] = 4.0
    if Admission.validate(world, ledger, demand, 5, {demand["id"]: {}}).get("reason") != "already_posted":
        _fail("duplicate contract identity accepted")
        return
    print("P2 contract admission validation PASS (not an escrow execution test)")
    quit(0)

func _fail(reason: String) -> void:
    push_error(reason)
    quit(1)
