extends SceneTree
## N57: one authoritative real seed → fleet + docks + world ledger
## → native tick → arrival → in-memory checkpoint/resume. No FileAccess.
const NativeData = preload("res://scripts/native_data.gd")
const Engine = preload("res://scripts/sim/live_native_fleet_engine.gd")
const Checkpoint = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")

var engine: RefCounted
var resumed_engine: RefCounted
var phase_count: int = 0
var observed_arrival_sync: bool = false

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    # Godot's JSON parser can expose whole-number source amounts as
    # float. Accept exact floats but never silently round fractions.
    var json_floats: Dictionary = seed.duplicate(true)
    json_floats["factions"][0]["treasury"] = 240000.0
    for i in range((json_floats["worlds"] as Array).size()):
        if str(json_floats["worlds"][i]["system"]["id"]) == "system-sol":
            json_floats["worlds"][i]["facilities"][0]["credits"] = 60000.0
            json_floats["worlds"][i]["facilities"][0]["docking_capacity"] = 12.0
            json_floats["worlds"][i]["populations"][0]["total_wealth"] = 60000.0
            break
    if not Engine.new().start_new_game(json_floats).get("ok", false):
        _fail("whole_number_json_float_rejected")
        return
    json_floats["factions"][0]["treasury"] = 240000.5
    if Engine.new().start_new_game(json_floats).get("ok", false):
        _fail("fractional_seed_credit_accepted")
        return
    engine = Engine.new()
    var start: Dictionary = engine.start_new_game(seed)
    if not bool(start.get("ok", false)):
        _fail("new_game_" + str(start.get("reason", "")))
        return
    # Source-backed: ships 24*40000, facilities 15*60000,
    # factions 3*240000, populations 3*60000. No test-only wallets.
    if start["ships"] != 24 or start["facilities"] != 15 or start["docking_slots"] != 60:
        _fail("real_world_entities")
        return
    if int(start["ship_credits"]) != 960000 or int(start["world_credits"]) != 2760000:
        _fail("real_money_supply")
        return
    if engine.ledger.total() != 2760000:
        _fail("ledger_inconsistent")
        return
    var crew: Array = engine.opening_crew_snapshot()
    if crew.size() != 24 or engine.opening_fitting_snapshot().size() != 24:
        _fail("initial_crew_fitting_unavailable")
        return
    var aggregate_crew: int = 0
    for entry in crew:
        aggregate_crew += int(entry["size"])
    if aggregate_crew != 123:
        _fail("source_crew_count")
        return
    if str(engine.start_new_game(seed).get("reason", "")) != "world_already_initialized":
        _fail("double_start")
        return
    var initial_checkpoint: Dictionary = engine.checkpoint()
    if not bool(initial_checkpoint.get("ok", false)):
        _fail("initial_complete_checkpoint")
        return
    var restored_zero = Engine.new()
    if not restored_zero.restore_complete(seed,
            JSON.parse_string(JSON.stringify(initial_checkpoint))).get("ok", false):
        _fail("restore_native_tick_zero")
        return
    if restored_zero.runner.bootstrap_new_game_native_fleet(seed):
        _fail("tick_zero_restore_refilled")
        return
    if restored_zero.opening_crew_snapshot().size() != 24 or restored_zero.opening_fitting_snapshot().size() != 24:
        _fail("opening_source_views_lost_after_restore")
        return
    var ship_id: String = "@system-sol/0"
    var docked: Dictionary = engine.request_dock(ship_id, "n57:dock:first", "station")
    if not bool(docked.get("ok", false)):
        _fail("real_station_dock")
        return
    if engine.request_dock(ship_id, "n57:dock:first", "station") != docked:
        _fail("replayed_dock")
        return
    if engine.depart(ship_id, "mine-near-earth").get("ok", false):
        _fail("departed_still_docked")
        return
    if not engine.undock(ship_id, "n57:undock").get("ok", false):
        _fail("undock")
        return
    if engine.depart(ship_id, "pirate-outpost").get("ok", false):
        _fail("invalid_route")
        return
    if engine.docking.ships[ship_id]["in_transit"]:
        _fail("failed_departure_left_dock_in_transit")
        return
    var depart: Dictionary = engine.depart(ship_id, "mine-near-earth")
    if not bool(depart.get("ok", false)):
        _fail("native_departure_" + str(depart.get("reason", "")))
        return
    if not engine.docking.ships[ship_id]["in_transit"] or not (engine.runner._fleet.ships[ship_id]["transit"] is Dictionary):
        _fail("dual_departure_state")
        return
    engine.runner.ships_phase_completed.connect(_on_ships_phase)
    # One scheduled notification is delivered *after* N57 dock arrival
    # synchronization within native dock_queue phase of the SAME tick.
    for t in range(1, 120):
        if not engine.runner.schedule_event("n57:doc:" + str(t), t, "dock_queue",
                ship_id, "observer_only"):
            _fail("event_schedule")
            return
    engine.runner.scheduled_event_due.connect(_check_event)
    if not engine.advance_one_native_tick():
        _fail("first_tick")
        return
    if engine.runner.tick_count != 1 or phase_count != 1:
        _fail("tick_phase_missing")
        return
    var first_fuel: float = float(engine.runner._fleet.ships[ship_id]["fuel"])
    if first_fuel >= 120.0:
        _fail("fuel_not_debited")
        return
    var saved_midflight: Dictionary = engine.checkpoint()
    if not bool(saved_midflight.get("ok", false)):
        _fail("midflight_checkpoint")
        return
    var resumed = Engine.new()
    var resume_result: Dictionary = resumed.restore_complete(seed,
        JSON.parse_string(JSON.stringify(saved_midflight)))
    if not bool(resume_result.get("ok", false)):
        _fail("midflight_restore_" + str(resume_result.get("reason", "")))
        return
    if not is_equal_approx(float(resumed.runner._fleet.ships[ship_id]["fuel"]), first_fuel):
        _fail("fuel_changed_on_restore")
        return
    if resumed.runner.transit_cursor_for_fleet_envelope() != engine.runner.transit_cursor_for_fleet_envelope():
        _fail("transit_token_changed")
        return
    resumed_engine = resumed
    resumed.runner.ships_phase_completed.connect(_on_resumed_ships_phase)
    resumed.runner.scheduled_event_due.connect(_check_resumed_event)
    if resumed.runner.bootstrap_new_game_native_fleet(seed):
        _fail("resumed_full_tank")
        return
    var restored_finished: bool = false
    for i in range(120):
        if not resumed.advance_one_native_tick():
            _fail("midflight_resumed_tick_" + resumed.halt_reason())
            return
        var ship: Dictionary = resumed.runner._fleet.ships[ship_id]
        if (ship["transit"] as Dictionary).is_empty():
            restored_finished = true
            if str(ship["location"]) != "mine-near-earth" or bool(resumed.docking.ships[ship_id]["in_transit"]):
                _fail("arrival_not_synchronized")
                return
            break
    if not restored_finished or not observed_arrival_sync:
        _fail("ship_never_arrived_or_phase_unsynced")
        return
    # Replay protection and deterministic state do not remove original
    # engine's live state or rewrite its save/user files.
    if engine.runner.tick_count != 1:
        _fail("staged_restore_changed_original")
        return
    var checksum_corrupt: Dictionary = saved_midflight.duplicate(true)
    checksum_corrupt["payload"]["ship_state"][0]["fuel"] = 9999.0
    var original_state: String = JSON.stringify(resumed.runner.live_fleet_snapshot())
    if Engine.new().restore_complete(seed, checksum_corrupt).get("ok", false):
        _fail("corrupt_envelope_accepted")
        return
    if original_state != JSON.stringify(resumed.runner.live_fleet_snapshot()):
        _fail("corrupt_restore_changed_live_world")
        return
    # A valid hash is only an integrity signal, not authorization.
    # Semantically forged saves must also fail after rehashing.
    var forged: Dictionary = saved_midflight.duplicate(true)
    forged["payload"]["docking"]["facilities"]["facility-earth-station"]["capacity"] = 999
    forged["sha256"] = Checkpoint._canonical(forged["payload"]).sha256_text()
    if Engine.new().restore_complete(seed, forged).get("ok", false):
        _fail("forged_dock_capacity_accepted")
        return
    forged = saved_midflight.duplicate(true)
    forged["payload"]["ledger"]["balances"]["extra:phantom"] = 1000
    forged["sha256"] = Checkpoint._canonical(forged["payload"]).sha256_text()
    if Engine.new().restore_complete(seed, forged).get("ok", false):
        _fail("forged_wallet_accepted")
        return
    forged = saved_midflight.duplicate(true)
    forged["payload"]["ledger"]["balances"]["facility:facility-earth-station"] = 61000
    forged["sha256"] = Checkpoint._canonical(forged["payload"]).sha256_text()
    if Engine.new().restore_complete(seed, forged).get("ok", false):
        _fail("rehashed_money_supply_inflation_accepted")
        return
    forged = saved_midflight.duplicate(true)
    forged["payload"]["ship_state"][0]["cargo_capacity"] = 100000
    forged["sha256"] = Checkpoint._canonical(forged["payload"]).sha256_text()
    if Engine.new().restore_complete(seed, forged).get("ok", false):
        _fail("forged_ship_cargo_capacity_accepted")
        return
    if original_state != JSON.stringify(resumed.runner.live_fleet_snapshot()):
        _fail("forged_restore_mutated_live_world")
        return
    if resumed.restore_complete(seed, saved_midflight).get("reason", "") != "restore_requires_new_engine":
        _fail("live_world_restore_replaced_signal_authority")
        return
    if not engine.is_live() or not resumed.is_live() or engine.ledger.total() != 2760000 or resumed.ledger.total() != 2760000:
        _fail("cross_domain_conservation")
        return
    print("N57_LIVE_FLEET_ENGINE_PASS: 24 ships, 15 facilities, 60 docks, credits=2760000")
    quit(0)

func _on_ships_phase(_tick: int) -> void:
    phase_count += 1
    var ship_id := "@system-sol/0"
    var state: Dictionary = engine.runner._fleet.ships[ship_id]
    if (state["transit"] as Dictionary).is_empty() and str(state["location"]) == "mine-near-earth":
        observed_arrival_sync = not bool(engine.docking.ships[ship_id]["in_transit"])

func _check_event(event: Dictionary) -> void:
    if str(event.get("kind", "")) != "observer_only":
        return
    var id: String = str(event.get("entity_id", ""))
    if id != "@system-sol/0":
        return
    var state: Dictionary = engine.runner._fleet.ships[id]
    var transit: Dictionary = state["transit"]
    var dock_state: Dictionary = engine.docking.ships[id]
    if transit.is_empty() and bool(dock_state["in_transit"]):
        _fail("dock_queue_saw_stale_arrival")


func _on_resumed_ships_phase(_tick: int) -> void:
    var id: String = "@system-sol/0"
    var state: Dictionary = resumed_engine.runner._fleet.ships[id]
    if (state["transit"] as Dictionary).is_empty() and str(state["location"]) == "mine-near-earth":
        observed_arrival_sync = not bool(resumed_engine.docking.ships[id]["in_transit"])

func _check_resumed_event(event: Dictionary) -> void:
    if str(event.get("kind", "")) != "observer_only":
        return
    var id: String = str(event.get("entity_id", ""))
    if id != "@system-sol/0":
        return
    var state: Dictionary = resumed_engine.runner._fleet.ships[id]
    var dock_state: Dictionary = resumed_engine.docking.ships[id]
    if (state["transit"] as Dictionary).is_empty() and bool(dock_state["in_transit"]):
        _fail("restored_dock_queue_observed_stale_arrival")

func _fail(reason: String) -> void:
    push_error("N57_LIVE_FLEET_FAIL " + reason)
    quit(1)
