extends SceneTree
## N135 actual MarketFlow consumption -> station need; pure, no fabricated order.
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {"station-1": {"location": "sol-earth", "faction": "sol", "credits": 1000}},
        "markets": {"sol-earth": {"owner": "station-1",
            "supply": {"food": 3.0, "water": 40.0},
            "prices": {"food": 18.0, "water": 12.0},
            "consumption_window": {
                "food": [{"tick": 8, "qty": 5}, {"tick": 9, "qty": 4}],
                "water": [{"tick": 9, "qty": 10}]}}}
    }
    var before: Dictionary = world.duplicate(true)
    var result: Dictionary = Demand.propose(world, 10)
    assert(result.get("ok", false))
    assert(result["proposals"].size() == 1)
    var row: Dictionary = result["proposals"][0]
    assert(row["commodity"] == "food")
    assert(row["quantity"] == 6)
    assert(row["station_id"] == "station-1")
    assert(row["status"] == "UNFUNDED_PROPOSAL")
    assert(world == before) # No market, wallet or contract mutation.
    assert(Demand.propose(world, 10) == result) # Stable replay.
    world["facilities"]["station-1"]["credits"] = 10
    var unfunded: Dictionary = Demand.propose(world, 10)
    assert(unfunded["proposals"].is_empty())
    assert(unfunded["blocked"][0]["reason"] == "station_cannot_fund_purchase")
    world["markets"]["sol-earth"]["consumption_window"]["food"][0]["tick"] = 11
    assert(not Demand.propose(world, 10).get("ok", true))
    print("P2_N135_LIVE_DEMAND_PROPOSALS_PASS")
    quit()
