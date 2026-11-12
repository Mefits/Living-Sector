extends SceneTree
## Run: godot --headless --path godot --script res://tests/n7_needs_production_check.gd
const Cycle = preload("res://scripts/sim/economy/needs_production_cycle.gd")

func _make(water: float) -> RefCounted:
    var sim = Cycle.new()
    var f = {"id":"farm-1","location":"earth","recipe":"grow_food",
        "facility_type":"farm","workers":2,"employer":"farm","household":"house",
        "seller":"market"}
    var pop = {"id":"earth-workers","facility_location":"earth",
        "population_count":1000,"consumption":{"food":2.0,"water":1.0},
        "food_satisfaction":50,"safety_satisfaction":50,
        "entertainment_satisfaction":50,"overall_sentiment":50,
        "migration_pressure":0.0}
    var market = {"facility_location":"earth","prices":{"food":1.0,"water":1.0}}
    assert(sim.initialize({"farm":20,"house":20,"market":0},f,pop,market,
        {"food":0.0,"water":water}))
    return sim

func _initialize() -> void:
    var crisis = _make(0.0)
    for tick in range(1, 6):
        var r: Dictionary = crisis.run_tick(tick)
        assert(r["ok"])
    assert(crisis.stock()["food"] == 0.0)
    assert(crisis.population()["food_satisfaction"] == 45)
    assert(crisis.balance("market") == 0)
    assert(crisis.balance("farm") == 20)
    assert(crisis.balance("house") == 20)
    var healthy = _make(10.0)
    for tick in range(1, 6):
        assert(healthy.run_tick(tick)["ok"])
    assert(healthy.stock()["food"] == 8.0)
    assert(healthy.stock()["water"] == 6.0)
    assert(healthy.population()["food_satisfaction"] == 52)
    assert(healthy.balance("farm") == 10)
    assert(healthy.balance("house") == 27)
    assert(healthy.balance("market") == 3)
    var checkpoint: Dictionary = healthy.snapshot()
    assert(not healthy.run_tick(5)["ok"])
    var replay = Cycle.new()
    assert(replay.restore(checkpoint))
    assert(replay.snapshot() == checkpoint)
    for tick in range(6, 11):
        assert(healthy.run_tick(tick)["ok"])
        assert(replay.run_tick(tick)["ok"])
    assert(healthy.snapshot() == replay.snapshot())
    assert(healthy.population()["food_satisfaction"] == 54)
    assert(healthy.balance("farm") + healthy.balance("house") + healthy.balance("market") == 40)
    print("N7 production and population physical stock/ledger smoke OK")
    quit(0)
