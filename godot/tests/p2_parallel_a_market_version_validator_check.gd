extends SceneTree
## N39 II-A.2.2: versioned N150 read-set and immutable source Schema oracle.
## Run with LS_PROFILE_NATIVE_PHASES=1 to assert measured oracle invocation.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Local = preload("res://scripts/sim/phase1/n39_market_observation_validator.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("original seed rejected")
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("time controls rejected")
        return
    sim.advance_frame(0.0)
    if not sim.queue_control("step", 1):
        _fail("step rejected")
        return
    sim.advance_frame(0.0)
    if sim.tick_count != 1 or not sim.last_phase_failure().is_empty():
        _fail("first real economy tick failed: " + str(sim.last_phase_failure()))
        return
    var frozen: Dictionary = sim.production.snapshot()
    var world: Dictionary = frozen["world"]
    var markets: Dictionary = world["markets"]
    if not Schema.validate(world).is_empty():
        _fail("original Schema oracle rejected canonical world")
        return
    var updates: Dictionary = {}
    var market_ids: Array = markets.keys()
    market_ids.sort()
    for loc in market_ids:
        var old: Dictionary = markets[loc]
        updates[loc] = {"id": old["id"]}
        for key in ["prices", "demand", "seed_demand",
                "consumption_window", "orders", "history"]:
            updates[loc][key] = old[key].duplicate(true)
    var first: String = str(market_ids[0])
    var price_id: String = str(markets[first]["prices"].keys()[0])
    var version: int = sim.production.market_observation_version()
    if Local.validate_observation_proposal(world, updates, version, version) != "":
        _fail("canonical observation preflight rejected")
        return
    var invalid: Dictionary = updates.duplicate(true)
    invalid[first]["prices"][price_id] = -1.0
    var bad_world: Dictionary = world.duplicate(true)
    bad_world["markets"][first]["prices"][price_id] = -1.0
    if Local.validate_observation_proposal(world, invalid, version, version) != (
            "invalid_market_price") or Schema.validate(bad_world) != "invalid_market_price":
        _fail("negative price not rejected by local and full validators")
        return
    if sim.production.apply_market_phase(1, invalid, version):
        _fail("negative observation committed")
        return
    bad_world = world.duplicate(true)
    bad_world["markets"][first]["owner"] = "forged-market-owner"
    if Schema.validate(bad_world) != "missing_market_owner":
        _fail("full oracle did not detect forged owner")
        return
    invalid = updates.duplicate(true)
    invalid[first]["id"] = "forged-market-identity"
    if Local.validate_observation_proposal(world, invalid, version, version) != (
            "forged_market_identity") or sim.production.apply_market_phase(
                    1, invalid, version):
        _fail("forged market identity accepted")
        return
    if sim.production.snapshot() != frozen:
        _fail("rejected observation modified canonical state")
        return
    if not sim.production.apply_market_phase(1, updates, version):
        _fail("canonical observation commit failed")
        return
    if sim.production.snapshot() != frozen:
        _fail("identity observation commit changed World or N9")
        return
    if sim.production.market_observation_version() != version + 1:
        _fail("successful observation write did not advance generation")
        return
    if sim.production.apply_market_phase(1, updates, version):
        _fail("stale observation generation accepted")
        return
    updates[first]["prices"][price_id] = 123456789.0
    updates[first]["history"].clear()
    if sim.production.snapshot() != frozen:
        _fail("external observation retained mutable alias")
        return

    var dock: Dictionary = {"ok": true, "world": world.duplicate(true),
        "ledger_snapshot": frozen["ledger"].duplicate(true),
        "status": "unchanged", "changed": false}
    var missing_account: Dictionary = dock.duplicate(true)
    var account_ids: Array = missing_account["ledger_snapshot"]["balances"].keys()
    missing_account["ledger_snapshot"]["balances"].erase(account_ids[0])
    if sim.production._commit_native_n21(missing_account).get("ok", false):
        _fail("N21 accepted missing canonical wallet")
        return
    var extra_account: Dictionary = dock.duplicate(true)
    extra_account["ledger_snapshot"]["balances"]["unauthorized/cash"] = 0
    if sim.production._commit_native_n21(extra_account).get("ok", false):
        _fail("N21 accepted fabricated extra wallet")
        return
    bad_world = world.duplicate(true)
    var ship_ids: Array = bad_world["ships"].keys()
    ship_ids.sort()
    var fid: String = str(bad_world["facilities"].keys()[0])
    bad_world["facilities"][fid]["dock_queue"] = [str(ship_ids[0]), str(ship_ids[0])]
    if Schema.validate(bad_world) != "invalid_native_n21_fifo_identity":
        _fail("duplicate dock FIFO waiter bypassed Schema")
        return
    if sim.production.snapshot() != frozen:
        _fail("invalid N21 or FIFO mutation touched authoritative World/N9")
        return
    if OS.get_environment("LS_PROFILE_NATIVE_PHASES") == "1":
        var metrics: Dictionary = sim.production.native_schema_profile()
        var saw_oracle: bool = false
        for site in metrics.get("schema", {}):
            if str(site).begins_with("validate:") and int(
                    metrics["schema"][site]["calls"]) > 0:
                saw_oracle = true
        if not saw_oracle:
            _fail("full Schema oracle invocation not recorded")
            return
    print("P2_PARALLEL_A_MARKET_VERSION_VALIDATOR_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PARALLEL_A_MARKET_VERSION_VALIDATOR_FAIL: " + reason)
    quit(1)
