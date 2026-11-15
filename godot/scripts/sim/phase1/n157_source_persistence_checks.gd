extends RefCounted
## Frozen Rust N157 targeted source assertions; AUTHORED, NOT EXECUTED.
## sim_db/persistence.rs checkpoint_rollback/ship-flight/site/tombstone tests.
const Contract = preload("res://scripts/sim/phase1/n157_native_db_write_contract.gd")
const Transaction = preload("res://scripts/sim/phase1/n157_native_persist_transaction.gd")
const Worker = preload("res://scripts/sim/phase1/n157_native_economic_frame_buffer.gd")
const Boot = preload("res://scripts/sim/phase1/n157_native_boot_recovery.gd")

static func run_all() -> Dictionary:
    var checks: Dictionary = {}
    var database: Dictionary = _database()
    var worker = Worker.new()
    checks["initial_valid_stable_seed"] = worker.initialize(database, 1)
    var frame1: Array = [_faction(850), _board(150), _tick(1)]
    checks["whole_frame_admitted"] = worker.try_admit_frame(
        1, frame1, ["faction/issuer"]).get("accepted", false)
    var saturated: Dictionary = worker.try_admit_frame(
        2, [_board(150), _tick(2)], ["contracts"])
    checks["backpressure_keeps_dirty"] = (
        not saturated.get("accepted", true)
        and saturated.get("reason", "") == "channel_backpressure"
        and worker.pending_count() == 1)
    worker.drain_admitted()
    checks["later_frame_replaces_only_own_keys"] = (
        worker.try_admit_frame(2, [_board(150), _tick(2)]).get("accepted", false))
    worker.drain_admitted()
    checks["retains_payer_debit_from_previous_frame"] = worker.buffered_count() == 3
    var before_failure: Dictionary = worker.current_database()
    var failed: Dictionary = worker.checkpoint_barrier(true)
    checks["failed_transaction_has_no_ack"] = (
        not failed.get("acknowledged", true) and worker.buffered_count() == 3)
    checks["failure_keeps_complete_old_database"] = worker.current_database() == before_failure
    var saved: Dictionary = worker.source_snapshot()
    var restored_worker = Worker.new()
    checks["pending_frame_restore_retries"] = (
        restored_worker.restore_source_snapshot(saved)
        and restored_worker.buffered_count() == 3)
    var admitted: Dictionary = restored_worker.checkpoint_barrier()
    var committed: Dictionary = restored_worker.current_database()
    checks["retry_commits_tick_contract_and_debit"] = (
        admitted.get("acknowledged", false)
        and int(committed["factions"]["issuer"]["treasury"]) == 850
        and int(committed["contracts"]["contract-1"]["funding"]["reserved"]) == 150
        and int(committed["simulation_state"]["tick_counter"]["current_tick"]) == 2)
    checks["no_double_spend_on_flush_retry"] = (
        restored_worker.checkpoint_barrier().get("acknowledged", false)
        and restored_worker.current_database() == committed)
    checks["stale_tick_rejected"] = not restored_worker.try_admit_frame(
        2, [_board(150), _tick(2)]).get("accepted", true)
    checks["reject_partial_without_contract_board"] = not restored_worker.try_admit_frame(
        3, [_tick(3), _faction(840)]).get("accepted", true)
    checks["reject_mismatched_tick"] = not restored_worker.try_admit_frame(
        3, [_board(150), _tick(99)]).get("accepted", true)
    var deleted_site: Array = [
        {"kind": "site_delete", "agent_id": "site-1", "data": {}},
        {"kind": "site_upsert", "agent_id": "site-1",
            "data": {"completed": false, "commodity": "ore", "name": "Old site"}}
    ]
    var site_result: Dictionary = Transaction.transact(_database(), deleted_site)
    checks["tombstone_wins_site_upsert"] = (
        site_result.get("ok", false)
        and not site_result["state"]["construction_sites"].has("site-1"))
    var stale_ship: Array = [
        {"kind": "delete_ship", "db_id": 9, "data": {}},
        {"kind": "ship", "db_id": 9, "data": {"credits": 999}}]
    var ship_result: Dictionary = Transaction.transact(_database(), stale_ship)
    checks["tombstone_wins_stale_ship"] = (
        ship_result.get("ok", false)
        and not ship_result["state"]["ships"].has("9"))
    var original_db: Dictionary = _database()
    var injected: Dictionary = Transaction.transact(original_db, [_faction(800)], true)
    checks["atomic_staging_failure_preserves_original"] = (
        not injected.get("ok", true) and original_db["factions"]["issuer"]["treasury"] == 880)
    var trend_a: Dictionary = {"kind": "market_trend", "market_db_id": 1,
        "tick": 16, "data": {"entries": [{"commodity": "ore", "price": 5.0, "supply": 80.0}]}}
    var trend_b: Dictionary = {"kind": "market_trend", "market_db_id": 1,
        "tick": 32, "data": {"entries": [{"commodity": "ore", "price": 6.0, "supply": 60.0}]}}
    checks["market_trend_key_uses_tick"] = Contract.dedup_key(trend_a) != Contract.dedup_key(trend_b)
    var trends: Dictionary = Transaction.transact(_database(), [trend_a, trend_b])
    checks["different_trend_ticks_persist"] = (
        trends.get("ok", false)
        and trends["state"]["market_trend_samples"].size() == 2)
    var same_trend: Dictionary = Transaction.transact(
        _database(), [trend_a, trend_a])
    checks["same_tick_trend_replace"] = (
        same_trend.get("ok", false)
        and same_trend["state"]["market_trend_samples"].size() == 1)
    var retire: Array = [
        {"kind": "retire_ship", "agent_id": "ship-a", "tick": 2,
            "data": {"reason": "bankrupt"}},
        {"kind": "retire_ship", "agent_id": "ship-b", "tick": 2,
            "data": {"reason": "bankrupt"}}
    ]
    var retired: Dictionary = Transaction.transact(_database(), retire)
    checks["multiple_ship_retirements_not_collapsed"] = (
        retired.get("ok", false) and retired["state"]["retirements"].size() == 2)
    var boot: Dictionary = Boot.build_read_only_boot_plan(_database())
    checks["restores_stable_facility_identity"] = (
        boot.get("ok", false)
        and boot["stable_facility_ids"].get("1") == "facility-port-hub"
        and boot["stable_facility_ids"].get("2") == "facility-port-shipyard")
    checks["restores_ship_docking_from_db_id"] = (
        boot.get("ok", false)
        and boot["ships"][0]["resume"]["docked_at_agent"] == "facility-port-hub")
    checks["replay_seed_unchanged"] = (
        boot.get("ok", false) and boot["world_seed"]["seed"] == "9007199254740994")
    checks["completed_site_not_resurrected"] = (
        boot.get("ok", false) and boot["construction_sites"].is_empty())
    var legacy: Dictionary = _database()
    legacy["contracts"]["contract-1"]["initial_payment"] = 0
    var back: Dictionary = Boot.build_read_only_boot_plan(legacy)
    checks["legacy_initial_payment_fallback"] = (
        back.get("ok", false)
        and back["contracts"][0]["initial_payment"] == 120)
    var unknown: Dictionary = _database()
    unknown["contracts"]["contract-1"]["status"] = "obsolete"
    var unknown_plan: Dictionary = Boot.build_read_only_boot_plan(unknown)
    checks["unknown_contract_status_skipped"] = (
        unknown_plan.get("ok", false)
        and unknown_plan["skipped_unknown_contracts"].has("contract-1")
        and unknown_plan["contracts"].is_empty())
    var orphan_trend: Dictionary = _database()
    orphan_trend["market_trend_samples"]["ghost"] = {"market_db_id": 999,
        "tick": 16, "commodity": "ore", "price": 10.0, "supply": 10.0}
    var no_trend: Dictionary = Boot.build_read_only_boot_plan(orphan_trend)
    checks["orphan_market_trend_skipped"] = (
        no_trend.get("ok", false) and no_trend["market_trends"].is_empty())
    var broken: Dictionary = _database()
    broken["ships"]["9"]["resume_json"] = "{broken"
    checks["malformed_resume_rejected"] = (
        not Boot.build_read_only_boot_plan(broken).get("ok", true))
    var ok_count: int = 0
    for name in checks:
        if checks[name]:
            ok_count += 1
    return {"checks": checks, "passed": ok_count, "total": checks.size(),
        "all_passed": ok_count == checks.size()}

static func _tick(tick: int) -> Dictionary:
    return {"kind": "tick", "data": {"current_tick": tick}}

static func _faction(treasury: int) -> Dictionary:
    return {"kind": "faction", "id": "issuer", "data": {"treasury": treasury}}

static func _board(reserved: int) -> Dictionary:
    var row: Dictionary = _database()["contracts"]["contract-1"].duplicate(true)
    row["funding"]["reserved"] = reserved
    return {"kind": "contract_board", "data": {"rows": [row]}}

static func _database() -> Dictionary:
    var db: Dictionary = Transaction.empty_database()
    db["factions"]["issuer"] = {"treasury": 880, "id": "issuer"}
    db["facilities"]["1"] = {"name": "Hub", "facility_type": "station",
        "type": "station", "location_name": "port", "body_id": "earth",
        "faction_id": "issuer", "credits": 500}
    db["facilities"]["2"] = {"name": "Shipyard", "facility_type": "shipyard",
        "type": "shipyard", "location_name": "port", "body_id": "earth",
        "faction_id": "issuer", "credits": 1000}
    db["markets"]["1"] = {"facility_db_id": 1, "location": "port",
        "supply": {"ore": 100.0}, "prices": {"ore": 5.0}}
    db["populations"]["1"] = {"facility_id": 1, "total_wealth": 20,
        "population_count": 10, "faction_id": "issuer"}
    db["ships"]["9"] = {"name": "A", "class": "courier",
        "resume_json": "{\"docked_db_id\":1,\"cargo_age\":{},\"cargo_origin\":{}}"}
    db["construction_sites"]["site-1"] = {"completed": true,
        "commodity": "ore", "name": "Old finished site"}
    db["contracts"]["contract-1"] = {"id": "contract-1", "contract_type": "delivery",
        "status": "posted", "requestor_id": "1", "commodity": "ore",
        "quantity": 10, "source_location": "port",
        "destination_location": "port", "payment": 120, "initial_payment": 120,
        "min_reputation": 0, "initial_min_reputation": 0,
        "renewal_count": 0, "posted_at_tick": 0, "expires_at_tick": 1000,
        "funding": {"reserved": 120, "spent": 0}}
    db["simulation_state"]["tick_counter"] = {"current_tick": 0}
    db["simulation_state"]["world_seed"] = {"seed": "9007199254740994"}
    return db
