extends SceneTree
## N104 publish boundary: unchanged domains remain authoritative, changed
## domains are detached from an externally owned staged World.
func _initialize() -> void:
    var source: Dictionary = {
        "ships": {"s": {"cargo": {"ore": 2}}},
        "contract_board": {"contracts": {"c": {"status": "Accepted"}}},
        "faction_relations": {"f": {"g": 0}},
        "markets": {"m": {"supply": {"ore": 10}}},
        "dock_receipts": {"r": {"paid": true}}}
    var stage: Dictionary = source.duplicate(true)
    stage["ships"]["s"]["cargo"]["ore"] = 3
    stage["contract_board"]["contracts"]["c"]["status"] = "Posted"
    stage["faction_relations"]["f"]["g"] = 1
    var committed: Dictionary = source.duplicate()
    for domain in ["ships", "contract_board", "faction_relations"]:
        committed[domain] = stage[domain].duplicate(true)
    assert(committed == stage, "bounded N104 publish differs from full-stage oracle")
    assert(committed == stage.duplicate(true), "deep-copy oracle mismatch")
    stage["ships"]["s"]["cargo"]["ore"] = 99
    stage["contract_board"]["contracts"]["c"]["status"] = "Forged"
    stage["faction_relations"]["f"]["g"] = 999
    assert(committed["ships"]["s"]["cargo"]["ore"] == 3, "ship mutable alias")
    assert(committed["contract_board"]["contracts"]["c"]["status"] == "Posted", "contract mutable alias")
    assert(committed["faction_relations"]["f"]["g"] == 1, "relations mutable alias")
    assert(source["ships"]["s"]["cargo"]["ore"] == 2, "source World modified")
    assert(source["markets"]["m"]["supply"]["ore"] == 10, "unowned domain modified")
    assert(committed["markets"] == source["markets"], "untouched market changed")
    # Negative: a shallow copy of the staged write-set must leak mutations.
    var unsafe: Dictionary = source.duplicate()
    unsafe["ships"] = stage["ships"]
    stage["ships"]["s"]["cargo"]["ore"] = 100
    assert(unsafe["ships"]["s"]["cargo"]["ore"] == 100, "negative alias fixture invalid")
    assert(committed["ships"]["s"]["cargo"]["ore"] == 3, "detached publish leaked")
    print("PASS p2_perf_a_n104_release_owned_domains")
    quit()
