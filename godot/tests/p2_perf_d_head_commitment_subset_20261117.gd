extends SceneTree
## Regression: faction Head capture must preserve sorted original commitments
## while excluding unrelated, expired and paid contracts.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var contracts: Dictionary = {}
    for i in range(240):
        var id: String = "contract-%03d" % i
        contracts[id] = {
            "status": "open", "requestor_id": "other",
            "faction_id": "other", "source_location": "a",
            "destination_location": "b", "commodity": "ore",
            "quantity": i + 1, "fulfiller_id": null
        }
    contracts["contract-201"]["faction_id"] = "alpha"
    contracts["contract-009"]["requestor_id"] = "faction/alpha"
    contracts["contract-115"]["requestor_id"] = "alpha"
    contracts["contract-115"]["status"] = "paid"
    contracts["contract-150"]["faction_id"] = "alpha"
    contracts["contract-150"]["status"] = "expired"
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 9000},
        "facilities": {}, "markets": {}, "ships": {},
        "populations": {}, "contract_board": {"contracts": contracts},
        "research": {}
    }
    var result: Dictionary = Head.capture(world, "alpha", 42)
    assert(result.get("ok", false), str(result))
    var commitments: Array = result["snapshot"]["active_commitments"]
    assert(commitments.size() == 2)
    assert(commitments[0]["contract_id"] == "contract-009")
    assert(commitments[1]["contract_id"] == "contract-201")
    assert(commitments[0]["quantity"] == 10)
    assert(commitments[1]["quantity"] == 202)
    # An owner change is visible on the next capture; no stale index.
    contracts["contract-201"]["faction_id"] = "other"
    contracts["contract-002"]["requestor_id"] = "alpha"
    var changed: Dictionary = Head.capture(world, "alpha", 43)
    assert(changed.get("ok", false), str(changed))
    var next_rows: Array = changed["snapshot"]["active_commitments"]
    assert(next_rows.size() == 2)
    assert(next_rows[0]["contract_id"] == "contract-002")
    assert(next_rows[1]["contract_id"] == "contract-009")
    # Snapshot rows must not alias mutable source contracts.
    contracts["contract-002"]["quantity"] = 999
    assert(next_rows[0]["quantity"] == 3)
    print("PASS p2_perf_d_head_commitment_subset_20261117")
    quit()
