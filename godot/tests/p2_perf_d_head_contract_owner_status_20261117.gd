extends SceneTree
## Negative oracle: filtering unrelated ContractBoard rows before status
## normalization must not change Head.capture commitment order or content.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world := {
        "faction_treasuries": {"alpha": 10000},
        "facilities": {}, "markets": {}, "ships": {}, "populations": {},
        "contract_board": {"contracts": {}}, "research": {"alpha": []}
    }
    var contracts: Dictionary = world["contract_board"]["contracts"]
    for i in range(240):
        var id := "contract_%03d" % i
        contracts[id] = {
            "requestor_id": "faction/beta" if i % 3 == 0 else "faction/alpha",
            "faction_id": "beta" if i % 3 == 0 else "alpha",
            "status": "PAID" if i % 7 == 0 else ("expired" if i % 11 == 0 else "Open"),
            "source_location": "sol", "destination_location": "mars",
            "commodity": "ore", "quantity": i, "fulfiller_id": null
        }
    contracts["sponsor_only"] = {"requestor_id": "other", "faction_id": "alpha",
        "status": "Open", "quantity": 2}
    var expected: Array = []
    var ids: Array = contracts.keys()
    ids.sort()
    for id in ids:
        var c: Dictionary = contracts[id]
        var status: String = str(c.get("status", "")).to_lower()
        if status in ["paid", "expired"]:
            continue
        var owner: String = str(c.get("requestor_id", ""))
        var sponsor: String = str(c.get("faction_id", ""))
        if owner == "alpha" or owner == "faction/alpha" or sponsor == "alpha":
            expected.append(str(id))
    var captured: Dictionary = Head.capture(world, "alpha", 1)
    assert(captured.get("ok", false), "capture failed")
    var actual: Array = []
    for item in captured["snapshot"]["active_commitments"]:
        actual.append(item["contract_id"])
    assert(actual == expected, "owner/status filtering or sorted order changed")
    contracts["contract_001"]["requestor_id"] = "faction/beta"
    contracts["contract_001"]["faction_id"] = "beta"
    captured = Head.capture(world, "alpha", 2)
    actual.clear()
    for item in captured["snapshot"]["active_commitments"]:
        actual.append(item["contract_id"])
    assert(not actual.has("contract_001"), "owner change not reflected")
    assert(contracts["contract_001"]["status"] == "Open", "World was mutated")
    print("PASS p2_perf_d_head_contract_owner_status_20261117")
    quit(0)
