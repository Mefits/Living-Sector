extends SceneTree
# Astra II-B: N21 owned publication after full source Schema/N9 oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "ships": {
            "a": {"credits": 20, "cargo": {"ice": 2}, "memory": {"nested": [1]}},
            "b": {"credits": 30, "cargo": {"ice": 4}, "memory": {"nested": [2]}}},
        "facilities": {
            "dock": {"credits": 100, "dock_queue": ["a"], "nested": {"v": [3]}},
            "other": {"credits": 40, "dock_queue": [], "nested": {"v": [4]}}},
        "dock_receipts": {"old": {"kind": "dock", "nested": [5]}},
        "markets": {"loc": {"supply": {"ice": 9}}}}

func _legacy(source: Dictionary, proposed: Dictionary) -> Dictionary:
    var old: Dictionary = source.duplicate()
    for domain in ["ships", "facilities", "dock_receipts"]:
        old[domain] = proposed[domain].duplicate(true)
    return old

func _initialize() -> void:
    var source: Dictionary = _fixture()
    var original: Dictionary = source.duplicate(true)
    var proposed: Dictionary = source.duplicate(true)
    proposed["ships"]["a"]["credits"] = 15
    proposed["facilities"]["dock"]["credits"] = 105
    proposed["facilities"]["dock"]["dock_queue"] = []
    proposed["dock_receipts"]["new"] = {"kind": "dock", "nested": [6]}
    var committed: Dictionary = N39._n21_owned_commit_rows(source, proposed)
    assert(not committed.is_empty())
    assert(committed == _legacy(source, proposed))
    assert(source == original)
    # A proposal can be reused or mutated after publication; changed rows
    # and new receipts must never alias that proposal or source.
    proposed["ships"]["a"]["memory"]["nested"].append(10)
    proposed["facilities"]["dock"]["nested"]["v"].append(11)
    proposed["dock_receipts"]["new"]["nested"].append(12)
    assert(committed["ships"]["a"]["memory"]["nested"] == [1])
    assert(committed["facilities"]["dock"]["nested"]["v"] == [3])
    assert(committed["dock_receipts"]["new"]["nested"] == [6])
    assert(source == original)
    # Unchanged rows remain authoritative read-only aliases; the owned
    # publication is deliberately not a fully detached World snapshot.
    assert(is_same(committed["ships"]["b"], source["ships"]["b"]))
    assert(is_same(committed["facilities"]["other"], source["facilities"]["other"]))
    assert(is_same(committed["dock_receipts"]["old"], source["dock_receipts"]["old"]))
    # Second consecutive paid docking operation retains the first receipt.
    var next: Dictionary = committed.duplicate(true)
    next["ships"]["b"]["credits"] = 27
    next["facilities"]["dock"]["credits"] = 108
    next["dock_receipts"]["second"] = {"kind": "dock", "nested": [7]}
    var committed2: Dictionary = N39._n21_owned_commit_rows(committed, next)
    assert(committed2 == _legacy(committed, next))
    committed2["ships"]["b"]["cargo"]["ice"] = 99
    committed2["dock_receipts"]["second"]["nested"].append(8)
    assert(committed["ships"]["b"]["cargo"]["ice"] == 4)
    assert(next["dock_receipts"]["second"]["nested"] == [7])
    # Negative: no partial owned publication for topology corruption,
    # erased/replaced historical receipts or malformed mutable rows.
    var missing_ship: Dictionary = proposed.duplicate(true)
    missing_ship["ships"].erase("b")
    assert(N39._n21_owned_commit_rows(source, missing_ship).is_empty())
    var extra_facility: Dictionary = proposed.duplicate(true)
    extra_facility["facilities"]["phantom"] = {"credits": 1}
    assert(N39._n21_owned_commit_rows(source, extra_facility).is_empty())
    var missing_receipt: Dictionary = proposed.duplicate(true)
    missing_receipt["dock_receipts"].erase("old")
    assert(N39._n21_owned_commit_rows(source, missing_receipt).is_empty())
    var tampered: Dictionary = proposed.duplicate(true)
    tampered["dock_receipts"]["old"]["nested"].append(99)
    assert(N39._n21_owned_commit_rows(source, tampered).is_empty())
    var malformed: Dictionary = proposed.duplicate(true)
    malformed["ships"]["a"] = 1
    assert(N39._n21_owned_commit_rows(source, malformed).is_empty())
    assert(source == original)
    print("PASS p2_perf_a_n21_commit_row_owned")
    quit()
