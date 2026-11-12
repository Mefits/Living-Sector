extends RefCounted
## N57 opt-in single-authority *implemented* native slice:
## orbital bodies, 24 starter ships/transit, N21 docks and ONE N11 ledger.
## NO automatic AI/trading/production, and NEVER touch P1 user:// saves.
## Construct only once from the frozen seed, or stage a complete N54 snapshot.
signal tick_committed(tick: int)
signal world_halted(reason: String)

const ShipRunner = preload("res://scripts/sim/ship_tick_runner.gd")
const FleetBootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const DockBootstrap = preload("res://scripts/sim/ships/native_dock_bootstrap.gd")
const Funding = preload("res://scripts/sim/ships/native_ship_funding.gd")
const Opening = preload("res://scripts/sim/economy/native_opening_accounts.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Checkpoint = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")
const Crew = preload("res://scripts/sim/ships/native_crew_roster.gd")
const Fitting = preload("res://scripts/sim/ships/native_initial_fitting.gd")

var runner: RefCounted
var ledger: RefCounted
var docking: RefCounted
var _started: bool = false
var _halt_reason: String = ""
var _opening_crew: Array = []
var _opening_fittings: Dictionary = {}

## Builds all staged authorities and publishes them together. No full tank
## is created if any source fails, and no mutable world leaks to the caller.
func start_new_game(seed: Dictionary) -> Dictionary:
    if _started:
        return _fail("world_already_initialized")
    var staged_runner = ShipRunner.new()
    if not staged_runner.start_from_seed(seed):
        return _fail("seed_not_accepted")
    if not staged_runner.bootstrap_new_game_native_fleet(seed):
        return _fail("native_fleet_bootstrap_failed")
    var non_ship: Dictionary = Opening.source_opening_accounts(seed)
    if not bool(non_ship.get("ok", false)):
        return _fail("opening_wallet_sources_missing")
    var staged_ledger = Ledger.new()
    var admitted: Dictionary = Funding.admit_into_empty_world_ledger(
        staged_ledger, seed, non_ship["accounts"])
    if not bool(admitted.get("ok", false)):
        return _fail("single_world_ledger_rejected")
    var staged_docks: Dictionary = DockBootstrap.build_new_game(
        seed, staged_runner._fleet)
    if not bool(staged_docks.get("ok", false)):
        return _fail("native_dock_bootstrap_failed")
    var staged_docking: RefCounted = staged_docks["registry"]
    var crew = Crew.new()
    if not crew.initialize_new_game(staged_runner._fleet):
        return _fail("initial_crew_projection_failed")
    var fitting: Dictionary = Fitting.project_native_seed(seed, staged_runner._fleet)
    if not bool(fitting.get("ok", false)):
        return _fail("initial_fitting_projection_failed")
    var evidence: Dictionary = Checkpoint.capture(staged_runner,
        staged_ledger, staged_docking)
    if not bool(evidence.get("ok", false)):
        return _fail("initial_fleet_cross_domain_mismatch")
    runner = staged_runner
    ledger = staged_ledger
    docking = staged_docking
    _opening_crew = crew.snapshot()
    _opening_fittings = (fitting["records"] as Dictionary).duplicate(true)
    _halt_reason = ""
    _started = true
    runner.ships_phase_completed.connect(_on_ships_phase_completed)
    runner.tick_completed.connect(_on_tick_completed)
    return {
        "ok": true, "ships": int(admitted["ship_count"]),
        "ship_credits": int(admitted["ship_total"]),
        "world_credits": int(admitted["world_total"]),
        "facilities": int(staged_docks["facilities"]),
        "docking_slots": int(staged_docks["total_slots"])
    }

## This is a guarded command, not ship AI. A ship cannot depart a dock
## without a distinct Undock receipt. If N14 departure fails, N21's
## temporary in-transit admission is rolled back to the prior location.
func depart(ship_id: String, destination: String) -> Dictionary:
    if not is_live():
        return _fail("not_live")
    if not _ship_domain_matches(ship_id):
        return _fail("ship_dock_state_mismatch")
    var ship: Dictionary = runner._fleet.ships[ship_id]
    var dock_record: Dictionary = docking.ships[ship_id]
    if not (ship["transit"] as Dictionary).is_empty():
        return _fail("ship_already_in_flight")
    if not str(dock_record.get("docked_at", "")).is_empty():
        return _fail("undock_first")
    var origin: String = str(ship.get("location", ""))
    if origin.is_empty() or not docking.begin_transit(ship_id):
        return _fail("transit_admission_denied")
    if not runner.depart_ship(ship_id, destination):
        if not docking.arrive(ship_id, origin):
            _halt("departure_rollback_failed")
            return _fail("fatal_docking_rollback")
        return _fail("invalid_native_route_or_fuel")
    if not _ship_domain_matches(ship_id):
        _halt("departure_state_mismatch")
        return _fail("fatal_departure_mismatch")
    return {"ok": true, "ship_id": ship_id, "destination": destination,
        "departure_tick": runner.tick_count}

func request_dock(ship_id: String, operation_id: String,
        preferred_type: String = "") -> Dictionary:
    if not is_live() or not _ship_domain_matches(ship_id):
        return _fail("ship_state_unavailable_or_mismatch")
    return docking.request_dock(ship_id, operation_id, preferred_type)

func undock(ship_id: String, operation_id: String) -> Dictionary:
    if not is_live() or not _ship_domain_matches(ship_id):
        return _fail("ship_state_unavailable_or_mismatch")
    return docking.undock(ship_id, operation_id)

func queue_control(kind: String, value: Variant = null) -> bool:
    return is_live() and runner.queue_control(kind, value)

func advance_frame(delta: float) -> void:
    if is_live():
        runner.advance_frame(delta)

## Convenient deterministic test path; same simulation phase code, no
## renderer and no time scheduler duplication.
func advance_one_native_tick() -> bool:
    if not is_live():
        return false
    runner._advance_one_tick()
    return is_live()

func checkpoint() -> Dictionary:
    if not is_live():
        return _fail("not_live")
    return Checkpoint.capture(runner, ledger, docking)

## Fail closed when the resume contains a foreign finance account set or
## modified facility definitions. It must be a saved N57 native slice,
## not a P1 orbital-only save or an N39 production/world snapshot.
func restore_complete(seed: Dictionary, envelope: Dictionary) -> Dictionary:
    # Only a new instance may accept a complete checkpoint. Replacing a live
    # authority here could leave old Runner signals connected to this engine.
    if _started:
        return _fail("restore_requires_new_engine")
    var staged: Dictionary = Checkpoint.stage_restore(envelope, seed)
    if not bool(staged.get("ok", false)):
        return _fail("checkpoint_" + str(staged.get("reason", "invalid")))
    var wallet: Dictionary = staged["ledger"].snapshot()
    if not Opening.same_account_ids(seed, wallet["balances"]):
        return _fail("saved_other_world_wallet_ids_invalid")
    var native_ships: Dictionary = Funding.project_initial_ship_accounts(seed)
    if not bool(native_ships.get("ok", false)):
        return _fail("invalid_native_ship_ids")
    var balances: Dictionary = wallet["balances"]
    var expected: Dictionary = native_ships["accounts"]
    for account in expected:
        if not balances.has(account):
            return _fail("missing_native_ship_wallet")
    var native_others: Dictionary = Opening.source_opening_accounts(seed)
    if not bool(native_others.get("ok", false)):
        return _fail("invalid_native_other_wallet_sources")
    if balances.size() != expected.size() + int((native_others["accounts"] as Dictionary).size()):
        return _fail("unknown_saved_world_wallet")
    # The N57 slice has no income from outside the simulated world.
    # Every N11 transfer is zero-sum, so the 2.76M native money supply
    # MUST be preserved by any saved state, even with a rehashed payload.
    var native_total: int = int(native_ships["total"])
    for amount in (native_others["accounts"] as Dictionary).values():
        if native_total > 9223372036854775807 - int(amount):
            return _fail("native_money_supply_overflow")
        native_total += int(amount)
    if staged["ledger"].total() != native_total:
        return _fail("world_money_supply_changed")
    var bootstrap: Dictionary = FleetBootstrap.build_new_game(seed)
    if not bool(bootstrap.get("ok", false)):
        return _fail("native_source_unavailable")
    # The current N57 slice does NOT support ship refits, size changes,
    # crew reassignment, spawning or altered fuel/cargo capacities. A
    # checksum-valid save cannot silently enlarge native holds or tanks.
    var native_fleet: RefCounted = bootstrap["fleet"]
    var loaded_fleet: RefCounted = staged["runner"]._fleet
    var immutable_ship_keys: Array[String] = [
        "class", "size", "cargo_capacity", "fuel_capacity",
        "crew_size", "crew_roles", "faction_id", "system_id"
    ]
    for id in native_fleet.ships:
        if not loaded_fleet.ships.has(id):
            return _fail("missing_saved_native_ship")
        var frozen_ship: Dictionary = native_fleet.ships[id]
        var saved_ship: Dictionary = loaded_fleet.ships[id]
        for key in immutable_ship_keys:
            if saved_ship.get(key, null) != frozen_ship[key]:
                return _fail("unsupported_native_ship_refit_or_capacity_change")
    var initial_crew = Crew.new()
    if not initial_crew.initialize_new_game(bootstrap["fleet"]):
        return _fail("unavailable_source_crew_projection")
    var initial_fit: Dictionary = Fitting.project_native_seed(seed, bootstrap["fleet"])
    if not bool(initial_fit.get("ok", false)):
        return _fail("unavailable_source_fitting_projection")
    var expected_dock: Dictionary = DockBootstrap.build_new_game(
        seed, bootstrap["fleet"])
    if not bool(expected_dock.get("ok", false)):
        return _fail("native_dock_source_unavailable")
    var expected_facilities: Dictionary = expected_dock["registry"].snapshot()["facilities"]
    var saved_facilities: Dictionary = staged["docking"].snapshot()["facilities"]
    if expected_facilities != saved_facilities:
        return _fail("changed_dock_facility_schema")
    # No observable mutation of this engine before all validation above.
    runner = staged["runner"]
    ledger = staged["ledger"]
    docking = staged["docking"]
    _opening_crew = initial_crew.snapshot()
    _opening_fittings = (initial_fit["records"] as Dictionary).duplicate(true)
    _halt_reason = ""
    _started = true
    runner.ships_phase_completed.connect(_on_ships_phase_completed)
    runner.tick_completed.connect(_on_tick_completed)
    return {"ok": true, "tick": runner.tick_count,
        "ships": runner.live_fleet_snapshot().size(), "ledger_total": ledger.total()}

## Read-only starting projections. They are NOT simulated/resumed mutable
## crew or fitting state and are never substituted for a real Crew save.
func opening_crew_snapshot() -> Array:
    return _opening_crew.duplicate(true)

func opening_fitting_snapshot() -> Dictionary:
    return _opening_fittings.duplicate(true)

func is_live() -> bool:
    return _started and _halt_reason.is_empty()

func halt_reason() -> String:
    return _halt_reason

func _on_ships_phase_completed(_tick: int) -> void:
    if not is_live():
        return
    var ids: Array = runner._fleet.ships.keys()
    ids.sort()
    for id in ids:
        var ship_id: String = str(id)
        if not docking.ships.has(ship_id):
            _halt("missing_dock_record_" + ship_id)
            return
        var ship: Dictionary = runner._fleet.ships[id]
        var dock_record: Dictionary = docking.ships[ship_id]
        var transit: Dictionary = ship.get("transit", {})
        if transit.is_empty() and bool(dock_record.get("in_transit", false)):
            # N14 just arrived in ships phase: commit N21 arrival BEFORE
            # native dock_queue scheduled events in the same tick.
            var location: String = str(ship.get("location", ""))
            if location.is_empty() or not docking.arrive(ship_id, location):
                _halt("arrival_docking_sync_failed_" + ship_id)
                return
        if not _ship_domain_matches(ship_id):
            _halt("ship_domain_desync_" + ship_id)
            return

func _on_tick_completed(tick: int) -> void:
    if is_live():
        tick_committed.emit(tick)

func _ship_domain_matches(ship_id: String) -> bool:
    if runner == null or docking == null or not runner._fleet.ships.has(ship_id) or not docking.ships.has(ship_id):
        return false
    var ship: Dictionary = runner._fleet.ships[ship_id]
    var dock: Dictionary = docking.ships[ship_id]
    var flight: Dictionary = ship.get("transit", {})
    var moving: bool = not flight.is_empty()
    if bool(dock.get("in_transit", false)) != moving:
        return false
    if moving:
        return str(ship.get("location", "")).is_empty() and str(dock.get("location", "")).is_empty() and str(dock.get("docked_at", "")).is_empty()
    return not str(ship.get("location", "")).is_empty() and str(ship.get("location", "")) == str(dock.get("location", ""))

func _halt(reason: String) -> void:
    if not _halt_reason.is_empty():
        return
    _halt_reason = reason
    if runner != null:
        runner._fleet_suspended = true
        runner.clock.set_paused(true)
    world_halted.emit(reason)

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
