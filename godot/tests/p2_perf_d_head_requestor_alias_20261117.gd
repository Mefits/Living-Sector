extends SceneTree
## Negative oracle: requestor alias and sponsor membership must remain exact.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 9000},
        "facilities": {}, "markets": {}, "ships": {}, "populations": {},
        "contract_board": {"contracts": {
            "a": {"requestor_id": "faction/alpha", "status": "OPEN"},
            "b": {"requestor_id": "alpha", "status": "Open"},
            "c": {"requestor_id": "faction/beta", "faction_id": "alpha", "status": "open"},
            "d": {"requestor_id": "faction/alphabeta", "status": "open"},
            "e": {"requestor_id": "faction/alpha", "status": "PAID"},
            "f": {"requestor_id": "faction/alpha", "status": "expired"},
            "g": {"requestor_id": "faction/beta", "status": "open"}
        }}
    }
    var original: Dictionary = world.duplicate(true)
    var result: Dictionary = Head.capture(world, "alpha", 1)
    assert(result.get("ok", false), "valid source board must capture")
    var commitments: Array = result["snapshot"]["active_commitments"]
    assert(commitments.size() == 3, "must include only live own/sponsored")
    assert(commitments[0]["contract_id"] == "a")
    assert(commitments[1]["contract_id"] == "b")
    assert(commitments[2]["contract_id"] == "c")
    for item in commitments:
        assert(item["status"] == "open", "status normalization unchanged")
    assert(world == original, "capture must not mutate source World")
    world["contract_board"]["contracts"]["a"]["requestor_id"] = "faction/beta"
    var changed: Dictionary = Head.capture(world, "alpha", 2)
    assert(changed.get("ok", false))
    assert(changed["snapshot"]["active_commitments"].size() == 2,
        "owner change must be visible on next capture")
    assert(commitments.size() == 3, "prior capture must remain detached")
    print("P2_PERF_D_HEAD_REQUESTOR_ALIAS_PASS")
    quit()
