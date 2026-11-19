extends SceneTree
# Astra II-B: N104 release owned publication vs original full deep-copy oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _world() -> Dictionary:
    return {
        "ships": {
            "a": {"id": "a", "current_bt": {"steps": [1]}, "active_contract_id": "c"},
            "b": {"id": "b", "current_bt": {"steps": [2]}}},
        "contract_board": {
            "version": 3, "receipt_claims": {"paid": {"items": [1]}},
            "contracts": {
                "c": {"status": "Accepted", "meta": {"notes": [1]}},
                "d": {"status": "Posted", "meta": {"notes": [2]}}}},
        "faction_relations": {
            "a": {"b": {"reputation": 2, "history": [1]}},
            "b": {"a": {"reputation": 4, "history": [2]}}},
        "markets": {"x": {"stock": {"ore": 9}}},
        "dock_receipts": {"old": {"history": [1]}}
    }

func _release(proposed: Dictionary) -> void:
    proposed["ships"]["a"]["active_contract_id"] = ""
    proposed["ships"]["a"]["current_bt"]["steps"].append(3)
    proposed["contract_board"]["contracts"]["c"]["status"] = "Posted"
    proposed["contract_board"]["contracts"]["c"]["meta"]["notes"].append(4)
    proposed["faction_relations"]["a"]["b"]["reputation"] += 1
    proposed["faction_relations"]["a"]["b"]["history"].append(3)

func _initialize() -> void:
    var source: Dictionary = _world()
    var baseline: Dictionary = source.duplicate(true)
    var proposed: Dictionary = source.duplicate(true)
    _release(proposed)
    var published: Dictionary = N39._n104_owned_release_publication(
        source, proposed, "a", "c")
    assert(not published.is_empty())
    var legacy: Dictionary = source.duplicate(true)
    for domain in ["ships", "contract_board", "faction_relations"]:
        legacy[domain] = proposed[domain].duplicate(true)
    assert(published == legacy)
    assert(source == baseline)
    published["ships"]["a"]["current_bt"]["steps"].append(99)
    published["contract_board"]["contracts"]["c"]["meta"]["notes"].append(99)
    published["faction_relations"]["a"]["b"]["history"].append(99)
    assert(source == baseline)
    assert(proposed["ships"]["a"]["current_bt"]["steps"] == [1, 3])
    assert(proposed["contract_board"]["contracts"]["c"]["meta"]["notes"] == [1, 4])
    assert(proposed["faction_relations"]["a"]["b"]["history"] == [1, 3])
    # Untouched histories remain shared for reading; no new mutable owners.
    assert(published["ships"]["b"] == baseline["ships"]["b"])
    assert(published["contract_board"]["contracts"]["d"] == baseline[
        "contract_board"]["contracts"]["d"])
    # A failed Schema/N9 gate must discard the candidate without modifying World.
    var rejected: Dictionary = source.duplicate(true)
    _release(rejected)
    rejected["ships"]["a"]["active_contract_id"] = 777
    assert(source == baseline)
    var corrupt: Dictionary = source.duplicate(true)
    _release(corrupt)
    corrupt["ships"]["b"]["current_bt"]["steps"].append(8)
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    corrupt = source.duplicate(true)
    _release(corrupt)
    corrupt["contract_board"]["contracts"]["d"]["status"] = "Deleted"
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    corrupt = source.duplicate(true)
    _release(corrupt)
    corrupt["contract_board"]["contracts"].erase("d")
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    corrupt = source.duplicate(true)
    _release(corrupt)
    corrupt["ships"].erase("b")
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    corrupt = source.duplicate(true)
    _release(corrupt)
    corrupt["faction_relations"].erase("b")
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    corrupt = source.duplicate(true)
    _release(corrupt)
    corrupt["contract_board"]["contracts"]["c"] = []
    assert(N39._n104_owned_release_publication(source, corrupt, "a", "c").is_empty())
    assert(N39._n104_owned_release_publication(source, proposed, "missing", "c").is_empty())
    assert(N39._n104_owned_release_publication(source, proposed, "a", "missing").is_empty())
    assert(source == baseline)
    print("PASS p2_perf_a_n104_release_owned_publication")
    quit()
