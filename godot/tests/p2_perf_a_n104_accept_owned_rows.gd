extends SceneTree
# Astra II-B N104: full deep-copy oracle versus selective paid acceptance rows.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "escrow_balances": {"escrow/a": 12, "escrow/b": 20},
        "faction_treasuries": {"faction/a": 100, "faction/b": 90},
        "facilities": {
            "facility/a": {"credits": 70, "memory": {"history": [1]}},
            "facility/b": {"credits": 30, "memory": {"history": [2]}}},
        "ships": {
            "ship/a": {"active_contract_id": "", "current_bt": {"steps": [1]}},
            "ship/b": {"active_contract_id": "", "current_bt": {"steps": [2]}}},
        "contract_board": {"history": [{"id": "old"}]},
        "unrelated": {"nested": [1, 2]}
    }

func _accept(stage: Dictionary, faction_payer: bool) -> void:
    stage["escrow_balances"]["escrow/a"] += 5
    if faction_payer:
        stage["faction_treasuries"]["faction/a"] -= 5
    else:
        stage["facilities"]["facility/a"]["credits"] -= 5
    stage["ships"]["ship/a"]["active_contract_id"] = "contract/a"
    stage["ships"]["ship/a"]["current_bt"] = {"steps": [3, 4]}
    stage["contract_board"] = {"history": [{"id": "old"}, {"id": "contract/a"}]}

func _initialize() -> void:
    for faction_payer in [false, true]:
        var source: Dictionary = _fixture()
        var before: Dictionary = source.duplicate(true)
        var owned: Dictionary = N39._n104_owned_accept_stage(
            source, "escrow/a", "faction/a", "facility/a", "ship/a", faction_payer)
        assert(not owned.is_empty())
        var oracle: Dictionary = source.duplicate(true)
        _accept(owned, faction_payer)
        _accept(oracle, faction_payer)
        assert(owned == oracle)
        assert(source == before)
        # Deep nested mutation of the two writable rows must not alias source.
        owned["ships"]["ship/a"]["current_bt"]["steps"].append(99)
        if not faction_payer:
            owned["facilities"]["facility/a"]["memory"]["history"].append(99)
        assert(source == before)
        # Unchanged rows and histories are read-only aliases.
        assert(owned["ships"]["ship/b"] == before["ships"]["ship/b"])
        assert(owned["facilities"]["facility/b"] == before["facilities"]["facility/b"])
        # A later failed Schema/ledger validation discards the stage.
        var rejected: Dictionary = N39._n104_owned_accept_stage(
            source, "escrow/a", "faction/a", "facility/a", "ship/a", faction_payer)
        _accept(rejected, faction_payer)
        rejected["escrow_balances"]["escrow/a"] = -500
        assert(source == before)
    var world: Dictionary = _fixture()
    assert(N39._n104_owned_accept_stage(world, "missing", "faction/a",
        "facility/a", "ship/a", false).is_empty())
    assert(N39._n104_owned_accept_stage(world, "escrow/a", "faction/a",
        "facility/a", "missing", false).is_empty())
    assert(N39._n104_owned_accept_stage(world, "escrow/a", "missing",
        "facility/a", "ship/a", true).is_empty())
    assert(N39._n104_owned_accept_stage(world, "escrow/a", "faction/a",
        "missing", "ship/a", false).is_empty())
    var malformed: Dictionary = _fixture()
    malformed["ships"]["ship/a"] = []
    assert(N39._n104_owned_accept_stage(malformed, "escrow/a", "faction/a",
        "facility/a", "ship/a", false).is_empty())
    malformed = _fixture()
    malformed["facilities"]["facility/a"] = []
    assert(N39._n104_owned_accept_stage(malformed, "escrow/a", "faction/a",
        "facility/a", "ship/a", false).is_empty())
    print("PASS p2_perf_a_n104_accept_owned_rows")
    quit()
