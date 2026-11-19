extends SceneTree
# N144 colony approval owned-write stage: three domains only.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n144_colony_owned_stage.gd

func _initialize() -> void:
    var original: Dictionary = {
        "construction_sites": {"old": {"requirements": {"ore": 4}}},
        "construction_receipts": {"old": {"proof": ["source"]}},
        "research_directors": {"alpha": {"strategic": {"targets": ["ice"]}},
            "beta": {"strategic": {"targets": ["ore"]}}},
        "ships": {"ship": {"cargo": {"ore": 3}}},
        "contract_board": {"contracts": [{"id": "historical"}]}
    }
    var baseline: Dictionary = original.duplicate(true)
    var oracle: Dictionary = original.duplicate(true)
    oracle["construction_sites"]["new"] = {"requirements": {"ore": 9}}
    oracle["construction_receipts"]["new"] = {"proof": ["approved"]}
    oracle["research_directors"]["alpha"]["strategic"] = {"targets": ["water"]}

    var staged: Dictionary = original.duplicate()
    staged["construction_sites"] = original["construction_sites"].duplicate(true)
    staged["construction_receipts"] = original["construction_receipts"].duplicate(true)
    staged["research_directors"] = original["research_directors"].duplicate(true)
    staged["construction_sites"]["new"] = {"requirements": {"ore": 9}}
    staged["construction_receipts"]["new"] = {"proof": ["approved"]}
    staged["research_directors"]["alpha"]["strategic"] = {"targets": ["water"]}
    assert(staged == oracle, "N144 owned stage must match full deep-copy oracle")
    assert(original == baseline, "N144 staged approval must not modify authority")
    assert(staged["research_directors"]["beta"] == baseline["research_directors"]["beta"],
        "N144 must not change another faction's director")

    # Rejected approval must not leak nested changes into the authoritative World.
    var rejected: Dictionary = original.duplicate()
    rejected["construction_sites"] = original["construction_sites"].duplicate(true)
    rejected["construction_receipts"] = original["construction_receipts"].duplicate(true)
    rejected["research_directors"] = original["research_directors"].duplicate(true)
    rejected["construction_sites"]["old"]["requirements"]["ore"] = -1
    rejected["construction_receipts"]["old"]["proof"].append("bad")
    rejected["research_directors"]["beta"]["strategic"]["targets"].append("bad")
    assert(original == baseline, "rejected N144 transaction leaked a mutable alias")

    # Negative control: shallow domain copy is NOT safe for nested director memory.
    var unsafe: Dictionary = original.duplicate()
    unsafe["research_directors"] = original["research_directors"].duplicate()
    unsafe["research_directors"]["alpha"]["strategic"]["targets"].append("leak")
    assert(original["research_directors"]["alpha"]["strategic"]["targets"].has("leak"),
        "negative fixture must expose shallow-copy alias")
    quit(0)
