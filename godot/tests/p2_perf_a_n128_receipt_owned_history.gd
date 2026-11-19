extends SceneTree
# Astra II-B N128: actual production staging helper against legacy full-copy.
# This tests ownership/rollback; full paid-tick and Schema validation need Godot.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "ships": {
            "ship_a": {"crew_skills": {"pilot": 2}, "memory": {"events": [1]}},
            "ship_b": {"crew_skills": {"pilot": 4}, "memory": {"events": [2]}}},
        "native_crew_xp_receipts": {
            "old": {"proof": {"events": [3]}}},
        "markets": {"loc": {"stocks": {"ore": [4]}}},
        "faction_treasuries": {"alpha": 50}}

func _legacy(world: Dictionary, ship_id: String,
        skills: Dictionary) -> Dictionary:
    var stage: Dictionary = world.duplicate()
    stage["ships"] = world["ships"].duplicate()
    stage["ships"][ship_id] = world["ships"][ship_id].duplicate(true)
    stage["ships"][ship_id]["crew_skills"] = skills.duplicate(true)
    stage["native_crew_xp_receipts"] = world["native_crew_xp_receipts"].duplicate(true)
    return stage

func _append(stage: Dictionary, receipt_id: String) -> bool:
    if stage["native_crew_xp_receipts"].has(receipt_id):
        return false
    stage["native_crew_xp_receipts"][receipt_id] = {
        "id": receipt_id, "proof": {"events": [8]}}
    return true

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var original: Dictionary = world.duplicate(true)
    var optimized: Dictionary = N39._n128_owned_grant_stage(
        world, "ship_a", {"pilot": 5})
    var oracle: Dictionary = _legacy(world, "ship_a", {"pilot": 5})
    assert(_append(optimized, "new"))
    assert(_append(oracle, "new"))
    assert(optimized == oracle)
    assert(world == original)
    # Two sequential valid commands on one ship must retain both receipts.
    optimized = N39._n128_owned_grant_stage(
        optimized, "ship_a", {"pilot": 6})
    oracle = _legacy(oracle, "ship_a", {"pilot": 6})
    assert(_append(optimized, "next"))
    assert(_append(oracle, "next"))
    assert(optimized == oracle)
    assert(world == original)
    # Negative duplicate command: discarded stage must not change World.
    var duplicate: Dictionary = N39._n128_owned_grant_stage(
        optimized, "ship_a", {"pilot": 7})
    assert(not _append(duplicate, "old"))
    assert(optimized == oracle)
    # Negative late Schema failure: staged ship and receipt never publish.
    var rejected: Dictionary = N39._n128_owned_grant_stage(
        world, "ship_b", {"pilot": -1})
    assert(_append(rejected, "invalid"))
    assert(world == original)
    # Newly owned ship and new receipt must not alias the original.
    optimized["ships"]["ship_a"]["memory"]["events"].append(9)
    optimized["native_crew_xp_receipts"]["next"]["proof"]["events"].append(10)
    assert(world == original)
    # Historical receipts are intentionally immutable shared rows: appending
    # to the detached registry must not alter the old authoritative registry.
    assert(world["native_crew_xp_receipts"].size() == 1)
    assert(world["native_crew_xp_receipts"]["old"] == original["native_crew_xp_receipts"]["old"])
    assert(world["ships"]["ship_b"] == original["ships"]["ship_b"])
    assert(world["markets"] == original["markets"])
    assert(world["faction_treasuries"] == original["faction_treasuries"])
    print("PASS p2_perf_a_n128_receipt_owned_history")
    quit()
