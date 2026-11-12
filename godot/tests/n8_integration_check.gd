extends SceneTree
## N8 integrated smoke: native recipes + warehouse + ledger + paid shifts.
const Coordinator = preload("res://scripts/sim/economy/production_coordinator.gd")

func _initialize() -> void:
    var factory = {"location":"earth", "recipe":"smelt_metals",
        "facility_type":"refinery", "workers":2, "population":5,
        "employer":"company", "household":"people",
        "stock":{"ore":30.0,"fuel":3.0,"metals":0.0}, "limits":{}}
    var second = factory.duplicate(true)
    second["stock"] = {"ore":20.0,"fuel":2.0,"metals":0.0}
    var sim = Coordinator.new()
    assert(sim.initialize({"company":8,"people":0}, {"a":factory,"b":second}))
    var first = sim.run_tick(1)
    assert(first["ok"] and first["receipts"].size() == 1)
    assert(first["failures"]["b"] == "shared_labor_exhausted")
    assert(sim.balance("company") == 6 and sim.balance("people") == 2)
    assert(sim.stock_of("a")["metals"] == 8.0)
    assert(sim.stock_of("b")["metals"] == 0.0)
    var snapshot = sim.snapshot()
    assert(not sim.run_tick(1)["ok"])
    var restored = Coordinator.new()
    assert(restored.restore(snapshot))
    assert(restored.snapshot() == snapshot)
    assert(not restored.run_tick(1)["ok"])
    var second_tick = restored.run_tick(2)
    assert(second_tick["ok"] and second_tick["receipts"].size() == 1)
    assert(restored.balance("company") == 4 and restored.balance("people") == 4)
    var before = restored.snapshot()
    var invalid = before.duplicate(true)
    invalid["facilities"]["a"]["stock"]["ore"] = -1.0
    assert(not restored.restore(invalid))
    assert(restored.snapshot() == before)
    # Insufficient money cannot create outputs or pay phantom wages.
    var poor = Coordinator.new()
    assert(poor.initialize({"company":1,"people":0}, {"a":factory}))
    var blocked = poor.run_tick(1)
    assert(blocked["ok"] and blocked["receipts"].is_empty())
    assert(blocked["failures"]["a"] == "insufficient_payroll_budget")
    assert(poor.stock_of("a")["metals"] == 0.0 and poor.balance("people") == 0)
    print("N8 integrated production/ledger/labor replay smoke OK")
    quit(0)
