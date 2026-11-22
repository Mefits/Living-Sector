extends SceneTree
# N144 head-only path: root + owning director, no paid proposal.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n144_head_only_owned_stage.gd

func _initialize() -> void:
    var world: Dictionary = {
        "research_directors": {
            "alpha": {"strategic": {"targets": ["ore"]}, "history": [1, 2]},
            "beta": {"strategic": {"targets": ["ice"]}}},
        "ships": {"s1": {"cargo": {"ore": 12}}},
        "contract_board": {"contracts": {"old": {"amount": 20}}},
        "markets": {"m1": {"stock": {"water": 10}}}
    }
    var baseline: Dictionary = world.duplicate(true)
    var oracle: Dictionary = world.duplicate(true)
    var head_memory: Dictionary = {"targets": ["water"]}
    oracle["research_directors"]["alpha"]["strategic"] = head_memory.duplicate(true)

    var staged: Dictionary = world.duplicate()
    staged["research_directors"] = world["research_directors"].duplicate()
    staged["research_directors"]["alpha"] = world["research_directors"]["alpha"].duplicate(true)
    staged["research_directors"]["alpha"]["strategic"] = head_memory.duplicate(true)
    assert(staged == oracle, "head-only stage differs from full World oracle")
    assert(world == baseline, "head-only stage modified authority")
    staged["research_directors"]["alpha"]["history"].append(99)
    staged["research_directors"]["alpha"]["strategic"]["targets"].append("gas")
    assert(world == baseline, "rejected head-only stage leaked nested director mutation")
    head_memory["targets"].append("mutated after proposal")
    assert(staged["research_directors"]["alpha"]["strategic"]["targets"] == ["water", "gas"],
        "published director must not alias incoming head memory")
    assert(staged["research_directors"]["beta"] == baseline["research_directors"]["beta"],
        "foreign director was changed")

    var untouched: Dictionary = world.duplicate()
    assert(untouched == world, "no-head no-paid path should be a no-op")

    # Negative fixture: a shallow director row aliases the canonical nested memory.
    var unsafe_world: Dictionary = baseline.duplicate(true)
    var unsafe: Dictionary = unsafe_world.duplicate()
    unsafe["research_directors"] = unsafe_world["research_directors"].duplicate()
    unsafe["research_directors"]["alpha"] = unsafe_world["research_directors"]["alpha"].duplicate()
    unsafe["research_directors"]["alpha"]["history"].append(777)
    assert(unsafe_world["research_directors"]["alpha"]["history"].has(777),
        "negative fixture must demonstrate nested alias")
    quit(0)
