extends SceneTree
## N151 native 200*mult abstract demographic migration, real N39/N9
## transaction on a real-seed world with explicit changed test demographics.
## Godot gate NOT executed by agent (no binary, no Github Actions).
const Native = preload("res://scripts/native_data.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const World = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Migration = preload("res://scripts/sim/phase2/unified_population_phase.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("real frozen Galaxy seed is missing")
        return
    var imported: Dictionary = Adapter.from_seed(seed)
    if not imported.get("ok", false):
        _fail("real N39 world could not be projected: " + str(imported.get("reason", "?")))
        return
    var staged: Dictionary = imported["world"]
    var ids: Array = staged["populations"].keys()
    ids.sort()
    if ids.size() < 2:
        _fail("real seed has fewer than two native households")
        return
    var source_id: String = str(ids[0])
    var dest_id: String = str(ids[1])
    var source: Dictionary = staged["populations"][source_id]
    var dest: Dictionary = staged["populations"][dest_id]
    if str(source.get("location", "")) == str(dest.get("location", "")):
        _fail("fixture does not have physically different populations")
        return
    source["count"] = 500
    source["wealth"] = 100000
    source["migration_pressure"] = 1.2
    source["overall_sentiment"] = 15
    dest["overall_sentiment"] = 90
    dest["wealth"] = 20000
    for id in ids:
        if str(id) in [source_id, dest_id]:
            continue
        staged["populations"][id]["overall_sentiment"] = 40
        staged["populations"][id]["migration_pressure"] = 0.0
    var owner = World.new()
    if not owner.initialize(staged):
        _fail("N39 refused valid source-seeded household fixture")
        return
    var due_wrong: Dictionary = Migration.migration_proposal(
        owner.world_snapshot(), 199, 1)
    if not due_wrong.get("ok", false) or due_wrong.get("due", false):
        _fail("N151 migration occurred outside 200-tick native cadence")
        return
    for tick in range(1, 201):
        var step: Dictionary = owner.run_tick(tick, 1)
        if not step.get("ok", false):
            _fail("real N39 tick %d failed: %s" % [
                tick, str(step.get("reason", "unknown"))])
            return
    var before: Dictionary = owner.world_snapshot()
    var bank_before: Dictionary = owner.ledger_snapshot()
    var post: Dictionary = owner.apply_native_population_migration(200, 1)
    if not post.get("ok", false) or int(post.get("moved", 0)) != 100:
        _fail("native 100-person migration did not commit")
        return
    var after: Dictionary = owner.world_snapshot()
    var bank_after: Dictionary = owner.ledger_snapshot()
    var cash: int = int(before["populations"][source_id]["wealth"])
    var expected_transfer: int = int(cash / int(before["populations"][source_id]["count"])) * 100
    var change: int = int(post.get("wealth", -1))
    if change != expected_transfer or change <= 0:
        _fail("native i128 proportional household wealth calculation changed")
        return
    if int(after["populations"][source_id]["count"]) != int(before["populations"][source_id]["count"]) - 100 or int(after["populations"][dest_id]["count"]) != int(before["populations"][dest_id]["count"]) + 100:
        _fail("population headcount not conserved")
        return
    if int(after["populations"][source_id]["wealth"]) != cash - change or int(after["populations"][dest_id]["wealth"]) != int(before["populations"][dest_id]["wealth"]) + change:
        _fail("N9 household money and physical population diverged")
        return
    var receipt_id: String = str(post.get("receipt_id", ""))
    if receipt_id.is_empty() or not bank_after["receipts"].has(receipt_id):
        _fail("positive native wealth transfer lacks N9 receipt")
        return
    var before_total: int = 0
    var after_total: int = 0
    for balance in bank_before["balances"].values():
        before_total += int(balance)
    for balance in bank_after["balances"].values():
        after_total += int(balance)
    if before_total != after_total:
        _fail("native migration created or destroyed credits")
        return
    var saved: Dictionary = owner.snapshot()
    var reloaded = World.new()
    if not reloaded.restore(saved) or reloaded.world_snapshot() != after or reloaded.ledger_snapshot() != bank_after:
        _fail("N38 migration checkpoint did not restore same World and N9")
        return
    if owner.apply_native_population_migration(200, 1).get("ok", false):
        _fail("N151 duplicate transfer in same tick accepted")
        return
    var tampered: Dictionary = saved.duplicate(true)
    tampered["ledger"]["receipts"].erase(receipt_id)
    var denied = World.new()
    if denied.restore(tampered):
        _fail("N38 accepted missing N151 receipt from checkpoint")
        return
    print("P2_N151_REAL_SEED_200_TICK_HOUSEHOLD_MIGRATION_N9_N38_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N151_MIGRATION_FAIL: " + reason)
    quit(1)
