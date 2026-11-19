extends SceneTree
# Astra II-B N15: bounded owned publication after full N39 Schema/N9 guards.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _source() -> Dictionary:
    return {
        "ships": {
            "a": {"cargo": {"ore": 3}, "memory": {"nested": [1]}, "docked_at": "dock"},
            "b": {"cargo": {"ore": 8}, "memory": {"nested": [2]}, "docked_at": "dock"}},
        "markets": {
            "loc": {"supply": {"ore": 30}, "history": {"old": [3]}},
            "other": {"supply": {"ore": 60}, "history": {"old": [4]}}},
        "cargo_receipts": {"old": {"nested": [5]}},
        "dock_receipts": {"dock-old": {"nested": [6]}},
        "facilities": {"dock": {"stock": [7]}}}

func _old_oracle(source: Dictionary, proposal: Dictionary) -> Dictionary:
    var result: Dictionary = source.duplicate()
    for domain in ["ships", "markets", "dock_receipts", "cargo_receipts"]:
        result[domain] = proposal[domain].duplicate(true)
    return result

func _initialize() -> void:
    var source: Dictionary = _source()
    var baseline: Dictionary = source.duplicate(true)
    var proposal: Dictionary = source.duplicate(true)
    proposal["ships"]["a"]["cargo"]["ore"] = 5
    proposal["markets"]["loc"]["supply"]["ore"] = 28
    proposal["cargo_receipts"]["cargo-1"] = {"nested": [10], "kind": "load"}
    var owned: Dictionary = N39._n15_owned_logistics_publication(
        source, proposal, "a", "loc", "load", "cargo_receipts", "cargo-1")
    assert(not owned.is_empty())
    assert(owned == _old_oracle(source, proposal))
    assert(source == baseline)
    # Proposal-owned mutable data cannot be modified through committed rows.
    proposal["ships"]["a"]["cargo"]["ore"] = 99
    proposal["markets"]["loc"]["supply"]["ore"] = 99
    proposal["cargo_receipts"]["cargo-1"]["nested"].append(11)
    assert(owned["ships"]["a"]["cargo"]["ore"] == 5)
    assert(owned["markets"]["loc"]["supply"]["ore"] == 28)
    assert(owned["cargo_receipts"]["cargo-1"]["nested"] == [10])
    # A second paid transfer uses the first published World as authority.
    var proposal2: Dictionary = owned.duplicate(true)
    proposal2["ships"]["a"]["cargo"]["ore"] = 4
    proposal2["markets"]["loc"]["supply"]["ore"] = 29
    proposal2["cargo_receipts"]["cargo-2"] = {"nested": [12]}
    var second: Dictionary = N39._n15_owned_logistics_publication(
        owned, proposal2, "a", "loc", "unload", "cargo_receipts", "cargo-2")
    assert(second == _old_oracle(owned, proposal2))
    second["ships"]["a"]["memory"]["nested"].append(20)
    second["markets"]["loc"]["history"]["old"].append(21)
    second["cargo_receipts"]["cargo-2"]["nested"].append(22)
    assert(owned["ships"]["a"]["memory"]["nested"] == [1])
    assert(owned["markets"]["loc"]["history"]["old"] == [3])
    assert(proposal2["cargo_receipts"]["cargo-2"]["nested"] == [12])
    # Undock changes only ship + dock receipt, no market copies.
    var undock: Dictionary = source.duplicate(true)
    undock["ships"]["a"]["docked_at"] = ""
    undock["dock_receipts"]["undock-1"] = {"nested": [13]}
    var stage: Dictionary = N39._n15_owned_logistics_publication(
        source, undock, "a", "", "undock", "dock_receipts", "undock-1")
    assert(stage == _old_oracle(source, undock))
    assert(stage["markets"] == source["markets"])
    stage["dock_receipts"]["undock-1"]["nested"].append(14)
    assert(undock["dock_receipts"]["undock-1"]["nested"] == [13])
    # Negative/preflight: no stage may be published on invalid ownership,
    # duplicate receipt, missing ship, absent market, or wrong domain.
    assert(N39._n15_owned_logistics_publication(
        source, proposal, "missing", "loc", "load", "cargo_receipts", "cargo-1").is_empty())
    assert(N39._n15_owned_logistics_publication(
        source, proposal, "a", "missing", "load", "cargo_receipts", "cargo-1").is_empty())
    assert(N39._n15_owned_logistics_publication(
        source, proposal, "a", "loc", "load", "dock_receipts", "cargo-1").is_empty())
    assert(N39._n15_owned_logistics_publication(
        source, proposal, "a", "loc", "dock", "cargo_receipts", "cargo-1").is_empty())
    var duplicate: Dictionary = source.duplicate(true)
    duplicate["cargo_receipts"]["old"] = {"nested": [8]}
    assert(N39._n15_owned_logistics_publication(
        source, duplicate, "a", "loc", "load", "cargo_receipts", "old").is_empty())
    assert(source == baseline)
    print("PASS p2_perf_a_n15_logistics_owned_publication")
    quit()
