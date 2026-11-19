extends SceneTree
# Astra II-B: N97/N83 paid/refused physical publication vs deep-copy oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "ships": {
            "a": {"credits": 30, "cargo": {"ice": 1}, "memory": {"notes": [1]}},
            "b": {"credits": 40, "cargo": {"ice": 2}, "memory": {"notes": [2]}}},
        "facilities": {
            "f": {"credits": 90, "stock": {"fuel": 20}, "meta": {"v": [3]}},
            "other": {"credits": 10, "stock": {"fuel": 8}}},
        "markets": {
            "loc": {"supply": {"fuel": 10}, "meta": {"v": [4]}},
            "other": {"supply": {"fuel": 20}}},
        "bodies": {
            "ice": {"richness": 10, "meta": {"v": [5]}},
            "other": {"richness": 12}},
        "cargo_receipts": {"old": {"kind": "prior", "nested": [6]}},
        "unrelated": {"nested": [7]}}

func _legacy(source: Dictionary, proposal: Dictionary) -> Dictionary:
    var result: Dictionary = source.duplicate()
    for domain in ["ships", "facilities", "markets", "bodies", "cargo_receipts"]:
        result[domain] = proposal[domain].duplicate(true)
    return result

func _stage(source: Dictionary, proposal: Dictionary, rows: Dictionary,
        receipt_id: String, paid: bool) -> Dictionary:
    return N39._n97_n83_owned_physical_publication(
        source, proposal, "a", rows, receipt_id, paid)

func _initialize() -> void:
    var original: Dictionary = _fixture()
    var frozen: Dictionary = original.duplicate(true)
    var refuel: Dictionary = original.duplicate(true)
    refuel["ships"]["a"]["credits"] = 25
    refuel["facilities"]["f"]["stock"]["fuel"] = 15
    refuel["markets"]["loc"]["supply"]["fuel"] = 8
    refuel["cargo_receipts"]["n97"] = {"kind": "native_n97_refuel", "nested": [8]}
    var refuel_rows: Dictionary = {
        "ships": {"a": true}, "facilities": {"f": true},
        "markets": {"loc": true}, "bodies": {}}
    var committed: Dictionary = _stage(original, refuel, refuel_rows, "n97", true)
    assert(not committed.is_empty())
    assert(committed == _legacy(original, refuel))
    assert(original == frozen)
    assert(is_same(committed["ships"]["b"], original["ships"]["b"]))
    assert(is_same(committed["cargo_receipts"]["old"], original["cargo_receipts"]["old"]))
    refuel["ships"]["a"]["memory"]["notes"].append(99)
    refuel["facilities"]["f"]["meta"]["v"].append(99)
    refuel["markets"]["loc"]["meta"]["v"].append(99)
    refuel["cargo_receipts"]["n97"]["nested"].append(99)
    assert(committed["ships"]["a"]["memory"]["notes"] == [1])
    assert(committed["facilities"]["f"]["meta"]["v"] == [3])
    assert(committed["markets"]["loc"]["meta"]["v"] == [4])
    assert(committed["cargo_receipts"]["n97"]["nested"] == [8])
    # Consecutive mine stage changes only one body and ship, never the
    # preceding paid receipt or unrelated mutable rows.
    var mined: Dictionary = committed.duplicate(true)
    mined["ships"]["a"]["cargo"]["ice"] = 3
    mined["bodies"]["ice"]["richness"] = 8
    mined["cargo_receipts"]["n97mine"] = {"kind": "native_n97_mine", "nested": [9]}
    var mine_rows: Dictionary = {
        "ships": {"a": true}, "facilities": {},
        "markets": {}, "bodies": {"ice": true}}
    var mined_owned: Dictionary = _stage(committed, mined, mine_rows, "n97mine", true)
    assert(mined_owned == _legacy(committed, mined))
    mined_owned["bodies"]["ice"]["meta"]["v"].append(10)
    assert(committed["bodies"]["ice"]["meta"]["v"] == [5])
    # N83 trade uses the same ship/facility/market ownership boundary.
    var trade: Dictionary = committed.duplicate(true)
    trade["ships"]["a"]["credits"] = 20
    trade["facilities"]["f"]["credits"] = 95
    trade["markets"]["loc"]["supply"]["fuel"] = 7
    trade["cargo_receipts"]["n83"] = {"kind": "native_n97_free_buy", "nested": [11]}
    var traded: Dictionary = _stage(committed, trade, refuel_rows, "n83", true)
    assert(traded == _legacy(committed, trade))
    # Rejected N83/N97 may advance the ship transaction cursor, but
    # must not publish physical stock, receipts, or paid balances.
    var rejected: Dictionary = original.duplicate(true)
    rejected["ships"]["a"]["transaction"] = {"request_id": 2}
    var refused: Dictionary = _stage(original, rejected,
        {"ships": {"a": true}, "facilities": {}, "markets": {}, "bodies": {}},
        "none", false)
    assert(refused == _legacy(original, rejected))
    assert(original == frozen)
    # Negative oracle: wrong owner, erased/altered history, extra rows,
    # missing receipt, malformed row and unexpected unrelated domain.
    assert(_stage(original, refuel,
        {"ships": {"a": true}, "facilities": {}, "markets": {"loc": true}, "bodies": {}},
        "n97", true).is_empty())
    var changed_old: Dictionary = original.duplicate(true)
    changed_old["cargo_receipts"]["old"]["nested"].append(12)
    assert(_stage(original, changed_old, refuel_rows, "none", false).is_empty())
    var erased: Dictionary = refuel.duplicate(true)
    erased["cargo_receipts"].erase("old")
    assert(_stage(original, erased, refuel_rows, "n97", true).is_empty())
    var missing: Dictionary = refuel.duplicate(true)
    missing["cargo_receipts"].erase("n97")
    assert(_stage(original, missing, refuel_rows, "n97", true).is_empty())
    var phantom: Dictionary = refuel.duplicate(true)
    phantom["ships"]["c"] = {"credits": 0}
    assert(_stage(original, phantom, refuel_rows, "n97", true).is_empty())
    var malformed: Dictionary = refuel.duplicate(true)
    malformed["facilities"]["f"] = 0
    assert(_stage(original, malformed, refuel_rows, "n97", true).is_empty())
    var unrelated: Dictionary = refuel.duplicate(true)
    unrelated["unrelated"]["nested"].append(42)
    assert(_stage(original, unrelated, refuel_rows, "n97", true).is_empty())
    assert(original == frozen)
    print("PASS p2_perf_a_n97_n83_owned_publication")
    quit()
