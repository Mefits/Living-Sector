extends SceneTree
# A-owned negative regression: N128 copy-on-write ownership boundary.
# Run with Godot --headless --script res://tests/p2_perf_a_n128_owned_crew_copy.gd

func _initialize() -> void:
    var original: Dictionary = {
        "ships": {
            "ship-a": {"crew_skills": {"piloting": 2}, "cargo": {"ore": 5}},
            "ship-b": {"crew_skills": {"piloting": 7}, "cargo": {"ore": 9}}
        },
        "native_crew_xp_receipts": {"prior": {"id": "prior", "tick": 1}},
        "contract_board": {"contracts": {"c1": {"cargo": [1, 2]}}}
    }
    var oracle: Dictionary = original.duplicate(true)
    oracle["ships"]["ship-a"]["crew_skills"] = {"piloting": 3}
    oracle["native_crew_xp_receipts"]["new"] = {"id": "new", "tick": 2}

    var stage: Dictionary = original.duplicate()
    stage["ships"] = original["ships"].duplicate()
    stage["ships"]["ship-a"] = original["ships"]["ship-a"].duplicate(true)
    stage["ships"]["ship-a"]["crew_skills"] = {"piloting": 3}
    stage["native_crew_xp_receipts"] = original["native_crew_xp_receipts"].duplicate(true)
    stage["native_crew_xp_receipts"]["new"] = {"id": "new", "tick": 2}
    assert(stage == oracle, "N128 staged World differs from full deep-copy oracle")
    assert(original["ships"]["ship-a"]["crew_skills"]["piloting"] == 2)
    assert(not original["native_crew_xp_receipts"].has("new"))
    assert(original["ships"]["ship-b"]["cargo"]["ore"] == 9)

    # Negative: direct mutation of an unowned nested record corrupts source.
    var bad: Dictionary = original.duplicate()
    bad["ships"] = original["ships"].duplicate()
    bad["ships"]["ship-a"]["crew_skills"]["piloting"] = 99
    assert(original["ships"]["ship-a"]["crew_skills"]["piloting"] == 99,
        "negative fixture must demonstrate shallow-copy alias")
    quit(0)
