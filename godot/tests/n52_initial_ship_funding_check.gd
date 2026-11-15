extends SceneTree
## N52: no money duplication. Frozen Rust seeder credits become N11 initial
## balances exactly once, combined with separately sourced world balances.
const NativeData = preload("res://scripts/native_data.gd")
const Funding = preload("res://scripts/sim/ships/native_ship_funding.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native_seed")
        return
    var projection: Dictionary = Funding.project_initial_ship_accounts(seed)
    if not bool(projection.get("ok", false)) or int(projection.get("ship_count", 0)) != 24:
        _fail("ship_source_count")
        return
    if int(projection.get("total", -1)) != 960000:
        _fail("source_credit_total")
        return
    var accounts: Dictionary = projection["accounts"]
    if int(accounts.get("ship:@system-sol/0", -1)) != 40000 or accounts.size() != 24:
        _fail("native_ship_balances")
        return
    var ledger = Ledger.new()
    if Funding.admit_into_empty_world_ledger(ledger, seed, {}).get("ok", false):
        _fail("no_other_world_provenance")
        return
    if ledger.total() != 0:
        _fail("failed_admission_mutated_ledger")
        return
    # These two accounts are explicit TEST FIXTURES, not native station
    # balances. A production caller must supply actual world sources.
    var source_fixture: Dictionary = {"facility:fixture": 500, "faction:fixture": 100}
    var result: Dictionary = Funding.admit_into_empty_world_ledger(ledger, seed, source_fixture)
    if not bool(result.get("ok", false)) or int(result["world_total"]) != 960600:
        _fail("single_world_import")
        return
    if ledger.total() != 960600 or ledger.balance("ship:@system-sol/0") != 40000:
        _fail("imported_balances")
        return
    var unchanged: String = JSON.stringify(ledger.snapshot())
    if Funding.admit_into_empty_world_ledger(ledger, seed, source_fixture).get("ok", false):
        _fail("duplicate_import")
        return
    if unchanged != JSON.stringify(ledger.snapshot()):
        _fail("duplicate_import_mutated")
        return
    if Funding.admit_into_empty_world_ledger(Ledger.new(), seed,
            {"ship:@system-sol/0": 1}).get("ok", false):
        _fail("credit_source_collision")
        return
    var bad_seed: Dictionary = seed.duplicate(true)
    for i in range((bad_seed["worlds"] as Array).size()):
        if str(bad_seed["worlds"][i]["system"]["id"]) == "system-sol":
            bad_seed["worlds"][i]["ships"][0]["credits"] = -1
            break
    if Funding.project_initial_ship_accounts(bad_seed).get("ok", false):
        _fail("negative_seed_credits")
        return
    if not ledger.transfer("ship1:test-transfer", "ship:@system-sol/0",
            "ship:@system-sol/1", 17, 1, "test_ship_to_ship").get("ok", false):
        _fail("single_transfer")
        return
    if ledger.total() != 960600:
        _fail("money_conservation")
        return
    var saved: Dictionary = ledger.snapshot()
    var restored = Ledger.new()
    if not restored.restore(saved) or restored.total() != 960600:
        _fail("ledger_restore")
        return
    if restored.transfer("ship1:test-transfer", "ship:@system-sol/0",
            "ship:@system-sol/1", 17, 2, "test_ship_to_ship").get("ok", false):
        _fail("replayed_transfer")
        return
    print("N52_SHIP_FUNDING_PASS: ship credits 960000, one world ledger, no reimport")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N52_SHIP_FUNDING_FAIL " + reason)
    quit(1)
