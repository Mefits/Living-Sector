extends SceneTree
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Crew = preload("res://scripts/sim/phase2/unified_n149_ship_crew_phase.gd")
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
func _initialize() -> void:
    var sim = Runtime.new()
    assert(sim.start_from_seed(Native.load_current_world()))
    var saved: Dictionary = sim.production.snapshot()
    var bank = Ledger.new()
    assert(bank.restore(saved.ledger))
    var world: Dictionary = saved.world
    var ids: Array = world.ships.keys()
    ids.sort()
    var fired: Dictionary = {}
    for sid in ids:
        fired[sid] = 1
    # Wage and ordinary ticks use the identical frozen Rust core.
    for tick in [1, 160, 320, 600]:
        var legacy: Dictionary = Crew.stage(world, bank.snapshot(), tick, 1.0, 1, fired)
        var owned: Dictionary = Crew.stage_owned(world, bank, tick, 1.0, 1, fired)
        assert(legacy.ok and owned.ok)
        var child: RefCounted = owned.owned_ledger
        owned.erase("owned_ledger")
        owned.ledger_snapshot = child.snapshot()
        assert(legacy == owned)
        assert(child.retains_owned_receipts(bank))
        assert(bank.snapshot() == saved.ledger)
    var bad: Dictionary = fired.duplicate()
    bad["zz-missing-ship"] = 1
    assert(not Crew.stage_owned(world,bank,160,1.0,1,bad).ok)
    assert(bank.snapshot() == saved.ledger)
    # Paid receipt retention and public copies cannot change a parent's row.
    var money = Ledger.new()
    assert(money.import_accounts({"ship:s": 1000,"facility/f": 100}))
    assert(money.transfer("old", "ship:s", "facility/f", 10, 1, "test").ok)
    var pristine = money.snapshot()
    var fork = money.fork()
    assert(fork.transfer("new", "ship:s", "facility/f", 10, 2, "test").ok)
    assert(fork.retains_owned_receipts(money))
    var exported = fork.receipt_copy("old")
    exported.legs[0].delta = -999
    assert(money.snapshot() == pristine)
    assert(not fork.transfer("old", "ship:s", "facility/f", 10, 2, "test").ok)
    var replacement = Ledger.new()
    assert(replacement.restore(fork.snapshot()))
    assert(not replacement.retains_owned_receipts(money))
    var missing = money.fork()
    var partitions: Array = missing.get("_receipt_partitions")
    var bucket: int = int("old".hash()) & (Ledger.RECEIPT_PARTITIONS - 1)
    partitions[bucket] = {}
    assert(not missing.retains_owned_receipts(money))
    # Same paid source docking arithmetic and receipt, both staging modes.
    var fixture: Dictionary = {"ships":{"s":{"location":"x","credits":990,"docked_at":"","dock_attempt_start_tick":null}},
        "facilities":{"f":{"location":"x","credits":110,"docking_capacity":1,"condition":1.0,"dock_queue":[]}},
        "dock_receipts":{},"faction_relations":{}}
    var legacy_dock: Dictionary = Dock._admit(fixture.duplicate(true),money.snapshot(),"f","s",2,"test")
    var owned_dock: Dictionary = Dock._admit(fixture.duplicate(true),money.fork(),"f","s",2,"test")
    assert(legacy_dock.ok and owned_dock.ok)
    owned_dock.ledger_snapshot = owned_dock.ledger_snapshot.snapshot()
    assert(legacy_dock == owned_dock)
    assert(money.snapshot() == pristine)
    # A staffing-only colony work shift is a valid saved source row.
    var fid: String = str(world.facilities.keys()[0])
    saved.world.facilities[fid].work_shift = {"tick":0,"workers":{}}
    assert(sim._normalize_native_snapshot(saved))
    for key in ["wages","input_payment","processing_fee"]:
        var invalid: Dictionary = saved.duplicate(true)
        invalid.world.facilities[fid].work_shift[key] = 0.5
        assert(not sim._normalize_native_snapshot(invalid))
    print("LATE_GROWTH_OWNED_PASS crew_parity rollback history docking save_normalization")
    quit()
