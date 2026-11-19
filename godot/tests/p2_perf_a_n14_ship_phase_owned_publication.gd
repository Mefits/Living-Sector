extends SceneTree
# Astra II-B N14: row-owned fleet publication versus legacy deep-fleet oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {"ships": {
        "a": {"id": "a", "name": "A", "class": "miner", "faction_id": "f",
            "size": 1, "cargo_capacity": 10, "fuel_capacity": 20,
            "crew_size": 1, "crew_roles": {"pilot": 1}, "cargo": {"ore": 2},
            "credits": 50, "docked_at": "", "transit": {"path": [1, 2]},
            "current_bt": {"state": {"steps": [1]}}},
        "b": {"id": "b", "name": "B", "class": "miner", "faction_id": "f",
            "size": 1, "cargo_capacity": 10, "fuel_capacity": 20,
            "crew_size": 1, "crew_roles": {"pilot": 1}, "cargo": {"ore": 3},
            "credits": 70, "docked_at": "", "transit": {"path": [4]},
            "current_bt": {"state": {"steps": [2]}}}},
        "ship_next_token": 7, "markets": {"m": {"history": [1, 2]}},
        "dock_receipts": {"old": {"items": [5]}}}

func _legacy(world: Dictionary, proposal: Dictionary, token: int) -> Dictionary:
    var result: Dictionary = world.duplicate()
    result["ships"] = proposal.duplicate(true)
    result["ship_next_token"] = token
    return result

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var baseline: Dictionary = world.duplicate(true)
    var proposal: Dictionary = world["ships"].duplicate(true)
    proposal["a"]["transit"]["path"].append(3)
    proposal["a"]["current_bt"]["state"]["steps"].append(6)
    var stage: Dictionary = N39._n14_owned_ship_phase_stage(world, proposal, 8)
    assert(not stage.is_empty())
    assert(stage == _legacy(world, proposal, 8))
    assert(world == baseline)
    # Mutation of a changed row cannot escape into the proposal or old World.
    stage["ships"]["a"]["transit"]["path"].append(9)
    stage["ships"]["a"]["current_bt"]["state"]["steps"].append(10)
    assert(world == baseline)
    assert(proposal["a"]["transit"]["path"] == [1, 2, 3])
    assert(proposal["a"]["current_bt"]["state"]["steps"] == [1, 6])
    # A second publication must detach the newly modified row, not re-copy
    # or mutate a previous generation's unchanged nested components.
    var second: Dictionary = stage["ships"].duplicate(true)
    second["b"]["transit"]["path"].append(7)
    var stage2: Dictionary = N39._n14_owned_ship_phase_stage(stage, second, 9)
    assert(stage2 == _legacy(stage, second, 9))
    stage2["ships"]["b"]["transit"]["path"].append(8)
    assert(stage["ships"]["b"]["transit"]["path"] == [4])
    assert(world == baseline)
    # No ship mutation, only token publication; no unrelated domains change.
    var noop: Dictionary = N39._n14_owned_ship_phase_stage(world, world["ships"], 8)
    assert(noop == _legacy(world, world["ships"], 8))
    assert(noop["markets"] == world["markets"])
    # Negative: missing/extra ship, malformed row and each immutable field.
    var missing: Dictionary = proposal.duplicate(true)
    missing.erase("b")
    assert(N39._n14_owned_ship_phase_stage(world, missing, 8).is_empty())
    var extra: Dictionary = proposal.duplicate(true)
    extra["c"] = proposal["a"].duplicate(true)
    assert(N39._n14_owned_ship_phase_stage(world, extra, 8).is_empty())
    var malformed: Dictionary = proposal.duplicate(true)
    malformed["b"] = "invalid"
    assert(N39._n14_owned_ship_phase_stage(world, malformed, 8).is_empty())
    for field in ["id", "name", "class", "faction_id", "size",
            "cargo_capacity", "fuel_capacity", "crew_size", "crew_roles",
            "cargo", "credits", "docked_at"]:
        var invalid: Dictionary = proposal.duplicate(true)
        invalid["a"][field] = null
        assert(N39._n14_owned_ship_phase_stage(world, invalid, 8).is_empty())
    assert(world == baseline)
    print("PASS p2_perf_a_n14_ship_phase_owned_publication")
    quit()
