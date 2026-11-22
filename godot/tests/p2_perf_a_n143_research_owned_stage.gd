extends SceneTree
# N143 paid research write-set isolation versus a full World deep-copy oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n143_research_owned_stage.gd

const OWNED: Array[String] = ["research_directors", "research",
    "research_receipts", "research_mandates", "faction_charters",
    "faction_treasuries", "facilities", "populations", "markets"]

func _initialize() -> void:
    var before: Dictionary = {
        "research_directors": {"a": {"research": {"progress": 1}}},
        "research": {"a": ["t0"]},
        "research_receipts": {},
        "research_mandates": {"a": {"mode": "delegated", "paid": 0}},
        "faction_charters": {"a": {"paid": 0}},
        "faction_treasuries": {"a": 100},
        "facilities": {"f": {"credits": 10}},
        "populations": {"p": {"wealth": 5}},
        "markets": {"m": {"supply": {"electronics": 4.0}}},
        "ships": {"s": {"cargo": {"ore": 8}}},
        "contract_board": {"contracts": {"c": {"status": "posted"}}}}
    var frozen: Dictionary = before.duplicate(true)
    var oracle: Dictionary = before.duplicate(true)
    var stage: Dictionary = before.duplicate(false)
    for domain in OWNED:
        stage[domain] = before[domain].duplicate(true)
    for candidate in [oracle, stage]:
        candidate["research_directors"]["a"]["research"]["progress"] = 2
        candidate["research"]["a"].append("t1")
        candidate["research_receipts"]["r"] = {"receipt_id": "r"}
        candidate["research_mandates"]["a"]["paid"] = 1
        candidate["faction_charters"]["a"]["paid"] = 1
        candidate["faction_treasuries"]["a"] = 89
        candidate["facilities"]["f"]["credits"] = 11
        candidate["populations"]["p"]["wealth"] = 15
        candidate["markets"]["m"]["supply"]["electronics"] = 3.0
    assert(stage == oracle, "N143 owned write stage must match full World oracle")
    assert(before == frozen, "N143 rejected stage must not mutate authority")
    # Mutating the caller after staging cannot change the committed owned domains.
    before["markets"]["m"]["supply"]["electronics"] = -1.0
    assert(stage["markets"]["m"]["supply"]["electronics"] == 3.0)
    # Negative regression: shallow copying the market domain leaks nested supply.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["markets"] = frozen["markets"].duplicate(false)
    unsafe["markets"]["m"]["supply"]["electronics"] = -100.0
    assert(frozen["markets"]["m"]["supply"]["electronics"] == -100.0,
        "negative fixture must demonstrate nested mutable alias")
    assert(stage["ships"] == before["ships"])
    quit(0)
