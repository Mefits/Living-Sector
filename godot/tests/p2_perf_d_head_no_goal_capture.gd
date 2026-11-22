extends SceneTree
## Astra II-C: Head no-goal must not traverse growing unrelated registries.
## Positive oracle: no-goal status is stable regardless of unrelated rows.
## Negative oracle: clock/treasury/required-registry preflight still rejects.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 10000},
        "facilities": {}, "markets": {}, "ships": {},
        "populations": {}, "contract_board": {"contracts": {}}
    }
    var no_goal: Dictionary = {"selected_option": "wait"}
    var expected: Dictionary = {"ok": true,
        "status": "no_original_head_stock_goal",
        "faction_id": "alpha", "tick": 5}
    assert(Head.propose(world, "alpha", no_goal, 5) == expected)
    for i in range(500):
        var id: String = "f-%04d" % i
        world["facilities"][id] = {"faction": "beta", "location": id}
        world["ships"][id] = {"faction_id": "beta", "cargo": {"ore": -99}}
        world["contract_board"]["contracts"][id] = {
            "requestor_id": "beta", "status": "active"}
    # No goal means no native plan and no inspection of unrelated cargo.
    assert(Head.propose(world, "alpha", no_goal, 5) == expected)
    assert(world["ships"]["f-0000"]["cargo"]["ore"] == -99)
    assert(Head.propose(world, "alpha", no_goal, 0).get("reason") ==
        "n100_no_live_faction_treasury")
    assert(Head.propose(world, "missing", no_goal, 5).get("reason") ==
        "n100_no_live_faction_treasury")
    world["markets"] = []
    assert(Head.propose(world, "alpha", no_goal, 5).get("reason") ==
        "n100_missing_real_markets")
    world["markets"] = {}
    # A real goal still enters the source capture and rejects invalid cargo.
    var with_goal: Dictionary = {"selected_option": "deliver",
        "problem": {"goal_id": "g", "destination": "station",
            "commodity": "ore", "score": 1.0}}
    world["ships"]["f-0000"]["faction_id"] = "alpha"
    assert(Head.propose(world, "alpha", with_goal, 5).get("reason") ==
        "n100_invalid_original_cargo")
    print("PASS p2_perf_d_head_no_goal_capture")
    quit(0)
