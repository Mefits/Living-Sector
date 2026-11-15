extends SceneTree
## Pure N135 regression: a supply proposal must name real source stock.
const Demand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {
            "buyer": {"location": "A", "credits": 1000, "faction": "F"},
            "seller": {"location": "B", "credits": 1000, "faction": "F"}
        },
        "markets": {
            "A": {"owner": "buyer", "supply": {"Water": 1.0},
                "prices": {"Water": 5.0},
                "consumption_window": {"Water": [{"tick": 1, "qty": 8.0}]}},
            "B": {"owner": "seller", "supply": {"Water": 12.0},
                "prices": {"Water": 4.0}, "consumption_window": {}}
        }
    }
    var proposal: Dictionary = Demand.propose(world, 2)
    assert(proposal.get("ok", false))
    assert(proposal["proposals"].size() == 1)
    assert(proposal["proposals"][0]["source_location"] == "B")
    assert(proposal["proposals"][0]["quantity"] == 7)
    assert(proposal["proposals"][0]["status"] == "UNFUNDED_PROPOSAL")
    assert(world["markets"]["B"]["supply"]["Water"] == 12.0)
    world["markets"]["B"]["supply"]["Water"] = 6.0
    var unavailable: Dictionary = Demand.propose(world, 2)
    assert(unavailable.get("ok", false))
    assert(unavailable["proposals"].is_empty())
    assert(unavailable["blocked"][0]["reason"] == "no_physical_supplier_with_available_stock")
    quit(0)
