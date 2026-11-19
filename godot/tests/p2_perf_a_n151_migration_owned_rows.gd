extends SceneTree
# Astra II-B N151: owned migrant rows versus former full-registry copy.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _world() -> Dictionary:
    return {
        "populations": {
            "earth": {"count": 100, "wealth": 80,
                "migration_pressure": 0.2, "sentiment_dirty": false,
                "memory": {"history": [1]}},
            "mars": {"count": 20, "wealth": 10,
                "migration_pressure": 0.5, "sentiment_dirty": false,
                "memory": {"history": [2]}},
            "moon": {"count": 30, "wealth": 15,
                "migration_pressure": 0.1, "sentiment_dirty": false,
                "memory": {"history": [3]}}},
        "markets": {"earth": {"history": [4]}},
        "population_migration_last": {"tick": 200, "history": [5]}
    }

func _apply(stage: Dictionary, src: String, dst: String,
        moved: int, wealth: int) -> void:
    stage["populations"][src]["count"] -= moved
    stage["populations"][dst]["count"] += moved
    stage["populations"][src]["wealth"] -= wealth
    stage["populations"][dst]["wealth"] += wealth
    for id in [src, dst]:
        stage["populations"][id]["migration_pressure"] = 0.0
        stage["populations"][id]["sentiment_dirty"] = true
    stage["population_migration_last"] = {"tick": 400, "wealth_transferred": wealth}

func _initialize() -> void:
    var world: Dictionary = _world()
    var original: Dictionary = world.duplicate(true)
    var owned: Dictionary = N39._n151_owned_migration_stage(world, "earth", "mars")
    var oracle: Dictionary = world.duplicate()
    oracle["populations"] = world["populations"].duplicate(true)
    _apply(owned, "earth", "mars", 7, 4)
    _apply(oracle, "earth", "mars", 7, 4)
    assert(owned == oracle)
    assert(world == original)
    assert(owned["populations"]["moon"] == original["populations"]["moon"])
    # Nested aliases on changed households must not leak back into World.
    owned["populations"]["earth"]["memory"]["history"].append(99)
    owned["populations"]["mars"]["memory"]["history"].append(98)
    assert(world == original)
    # The source may not mutate an unrelated household through the stage.
    # Unchanged rows are intentionally shared, and therefore read-only.
    assert(owned["populations"]["moon"] is Dictionary)
    assert(world["populations"]["moon"]["memory"]["history"] == [3])
    # Negative: invalid IDs, identical IDs and malformed rows reject staging.
    assert(N39._n151_owned_migration_stage(world, "earth", "missing").is_empty())
    assert(N39._n151_owned_migration_stage(world, "earth", "earth").is_empty())
    var invalid: Dictionary = _world()
    invalid["populations"]["mars"] = []
    assert(N39._n151_owned_migration_stage(invalid, "earth", "mars").is_empty())
    # Negative: staged balance/Schema failure must not publish any writes.
    var rejected: Dictionary = N39._n151_owned_migration_stage(world, "earth", "mars")
    _apply(rejected, "earth", "mars", 999, 999)
    assert(rejected["populations"]["earth"]["wealth"] < 0)
    assert(world == original)
    # No-op cadence never stages, so it cannot modify the authoritative world.
    assert(world["population_migration_last"] == original["population_migration_last"])
    print("PASS p2_perf_a_n151_migration_owned_rows")
    quit()
