extends SceneTree
## N54 in-memory atomic restoration. Never writes P1 user:// saves.
## Covers only bodies + ships + credits + docking; production N39 excluded.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/ship_tick_runner.gd")
const Bootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const DockBootstrap = preload("res://scripts/sim/ships/native_dock_bootstrap.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Checkpoint = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed) or not runner.bootstrap_new_game_native_fleet(seed):
        _fail("native_ship_bootstrap")
        return
    var initial: Dictionary = Bootstrap.build_new_game(seed)
    if not bool(initial.get("ok", false)):
        _fail("source_fleet")
        return
    var accounts: Dictionary = {}
    var sources: Dictionary = initial["credit_sources"]
    for id in sources:
        accounts["ship:" + str(id)] = int(sources[id])
    # A separate non-ship balance is an EXPLICIT TEST FIXTURE, not
    # a claim about Rust station stock/credits.
    accounts["facility:test-fixture"] = 0
    var ledger = Ledger.new()
    if not ledger.import_accounts(accounts):
        _fail("ledger_init")
        return
    var built_dock: Dictionary = DockBootstrap.build_new_game(seed, initial["fleet"])
    if not bool(built_dock.get("ok", false)):
        _fail("dock_init")
        return
    var dock: RefCounted = built_dock["registry"]
    var captured: Dictionary = Checkpoint.capture(runner, ledger, dock)
    if not bool(captured.get("ok", false)):
        _fail("capture_new_game")
        return
    var disk_like: Variant = JSON.parse_string(JSON.stringify(captured))
    if not (disk_like is Dictionary):
        _fail("json_roundtrip")
        return
    var restored: Dictionary = Checkpoint.stage_restore(disk_like, seed)
    if not bool(restored.get("ok", false)):
        _fail("stage_new_game_" + str(restored.get("reason", "")))
        return
    if restored["runner"].tick_count != 0 or restored["runner"].live_fleet_snapshot().size() != 24:
        _fail("restored_fleet_origin")
        return
    if restored["ledger"].total() != 960000:
        _fail("restored_credit_total")
        return
    if restored["runner"].bootstrap_new_game_native_fleet(seed):
        _fail("refueled_after_restore")
        return
    var miner_id: String = "@system-sol/0"
    if not runner.depart_ship(miner_id, "mine-near-earth"):
        _fail("depart_native")
        return
    if not dock.begin_transit(miner_id):
        _fail("authority_dock_transit_sync")
        return
    runner._advance_one_tick()
    if runner.tick_count != 1:
        _fail("tick")
        return
    var moving: Dictionary = runner._fleet.ships[miner_id]
    if (moving["transit"] as Dictionary).is_empty():
        _fail("expected_midflight")
        return
    var flight_fuel: float = float(moving["fuel"])
    captured = Checkpoint.capture(runner, ledger, dock)
    if not bool(captured.get("ok", false)):
        _fail("capture_midflight")
        return
    disk_like = JSON.parse_string(JSON.stringify(captured))
    restored = Checkpoint.stage_restore(disk_like, seed)
    if not bool(restored.get("ok", false)):
        _fail("stage_midflight_" + str(restored.get("reason", "")))
        return
    if restored["runner"].tick_count != 1:
        _fail("wrong_saved_tick")
        return
    if not is_equal_approx(float(restored["runner"]._fleet.ships[miner_id]["fuel"]), flight_fuel):
        _fail("lost_fuel_on_resume")
        return
    if restored["runner"].transit_cursor_for_fleet_envelope() != runner.transit_cursor_for_fleet_envelope():
        _fail("transit_nonce_reused")
        return
    restored["runner"]._advance_one_tick()
    if float(restored["runner"]._fleet.ships[miner_id]["fuel"]) > flight_fuel:
        _fail("resume_refilled_fuel")
        return
    var before: String = JSON.stringify(runner.live_fleet_snapshot())
    var tampered: Dictionary = disk_like.duplicate(true)
    tampered["payload"]["ship_state"][0]["fuel"] = 98765.0
    if Checkpoint.stage_restore(tampered, seed).get("ok", false):
        _fail("tampered_checksum")
        return
    if before != JSON.stringify(runner.live_fleet_snapshot()):
        _fail("failed_restore_mutated_old_world")
        return
    var inconsistent: Dictionary = disk_like.duplicate(true)
    inconsistent["payload"]["docking"]["ships"][miner_id]["in_transit"] = false
    inconsistent["sha256"] = Checkpoint._canonical(inconsistent["payload"]).sha256_text()
    if Checkpoint.stage_restore(inconsistent, seed).get("ok", false):
        _fail("cross_domain_mismatch")
        return
    print("N54_FLEET_CHECKPOINT_PASS: 24 ship replay, orbital tick, credits, docking, nonce")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N54_FLEET_CHECKPOINT_FAIL " + reason)
    quit(1)
