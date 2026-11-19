extends SceneTree
# Astra II-B: N150 observation and N149 paid crew publish the same
# owned ship write-set, retaining old deep-copy results without old aliases.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _world() -> Dictionary:
    return {
        "ships": {
            "a": {"memory": {"prices": [1]}, "crew": {"morale": [2]},
                "cargo": {"food": 3}, "credits": 10},
            "b": {"memory": {"prices": [4]}, "crew": {"morale": [5]},
                "cargo": {"food": 6}, "credits": 20}},
        "markets": {"loc": {"history": [7]}},
        "native_crew_xp_receipts": {"old": {"proof": [8]}}}

func _oracle(world: Dictionary, proposed: Dictionary) -> Dictionary:
    var stage: Dictionary = world.duplicate()
    stage["ships"] = proposed.duplicate(true)
    return stage

func _initialize() -> void:
    var world: Dictionary = _world()
    var initial: Dictionary = world.duplicate(true)
    var candidate: Dictionary = world["ships"].duplicate(true)
    candidate["a"]["memory"]["prices"].append(9)
    var optimized: Dictionary = N39._owned_fleet_publication_stage(
        world, candidate, {"a": true})
    assert(not optimized.is_empty())
    assert(optimized == _oracle(world, candidate))
    assert(world == initial)
    # N149: a second paid update may touch crew, cargo and credits.
    var second: Dictionary = optimized["ships"].duplicate(true)
    second["a"]["crew"]["morale"].append(10)
    second["a"]["cargo"]["food"] = 2
    second["a"]["credits"] = 9
    var stage2: Dictionary = N39._owned_fleet_publication_stage(
        optimized, second, {"a": true})
    assert(stage2 == _oracle(optimized, second))
    assert(world == initial)
    # Changed rows must not alias either authoritative World or source proposal.
    stage2["ships"]["a"]["memory"]["prices"].append(11)
    stage2["ships"]["a"]["crew"]["morale"].append(12)
    assert(world == initial)
    assert(optimized["ships"]["a"]["memory"]["prices"] == [1, 9])
    assert(second["a"]["crew"]["morale"] == [2, 10])
    # No-op stages preserve exact values; no unrelated registry is modified.
    var noop: Dictionary = N39._owned_fleet_publication_stage(
        world, world["ships"], {})
    assert(noop == _oracle(world, world["ships"]))
    assert(noop["markets"] == world["markets"])
    # Rejected proposal cannot change World (wrong roster, forbidden sleeper,
    # malformed row). The caller must never publish these empty stages.
    var missing: Dictionary = {"a": candidate["a"]}
    assert(N39._owned_fleet_publication_stage(world, missing, {"a": true}).is_empty())
    assert(N39._owned_fleet_publication_stage(world, candidate, {"b": true}).is_empty())
    var invalid: Dictionary = world["ships"].duplicate()
    invalid["a"] = "invalid"
    assert(N39._owned_fleet_publication_stage(world, invalid, {"a": true}).is_empty())
    assert(world == initial)
    print("PASS p2_perf_a_n150_n149_fleet_owned_publication")
    quit()
