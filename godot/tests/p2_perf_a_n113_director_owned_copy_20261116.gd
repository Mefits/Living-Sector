extends SceneTree

# Standalone ownership regression for the unpaid N113 strategy write-set.
# Run with godot --headless --path godot --script res://tests/p2_perf_a_n113_director_owned_copy_20261116.gd
func _initialize() -> void:
    var original: Dictionary = {
        "research_directors": {"f1": {"strategic": {"goal": ["old"]}},
            "f2": {"strategic": {"goal": ["keep"]}}},
        "ships": {"ship1": {"cargo": {"ore": 7}}},
        "markets": {"m1": {"stocks": {"ore": 10}}}}
    var strategy: Dictionary = {"goal": ["new"]}
    var oracle: Dictionary = original.duplicate(true)
    oracle["research_directors"]["f1"]["strategic"] = strategy.duplicate(true)

    var staged: Dictionary = original.duplicate()
    staged["research_directors"] = original["research_directors"].duplicate(true)
    staged["research_directors"]["f1"]["strategic"] = strategy.duplicate(true)
    assert(staged == oracle, "N113 bounded stage must match full deep-copy oracle")
    assert(original["research_directors"]["f1"]["strategic"]["goal"] == ["old"])
    assert(staged["research_directors"]["f2"] == original["research_directors"]["f2"])

    # Negative: shallow domain alias would mutate canonical source before validation.
    var unsafe: Dictionary = original.duplicate()
    unsafe["research_directors"]["f1"]["strategic"]["goal"].append("leak")
    assert(original["research_directors"]["f1"]["strategic"]["goal"] == ["old", "leak"],
        "negative fixture must demonstrate an unsafe mutable alias")

    # Positive: after detachment, mutation cannot reach the original director.
    var isolated: Dictionary = original.duplicate()
    isolated["research_directors"] = original["research_directors"].duplicate(true)
    isolated["research_directors"]["f1"]["strategic"]["goal"].append("safe")
    assert(original["research_directors"]["f1"]["strategic"]["goal"] == ["old", "leak"])
    assert(strategy["goal"] == ["new"], "grant strategy must remain detached")
    print("PASS p2_perf_a_n113_director_owned_copy")
    quit(0)
