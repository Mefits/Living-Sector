extends "res://scripts/sim/tick_runner.gd"
## N40 CODE_UNVERIFIED. Opt-in native ship tick phase. Never use map pixels,
## route lengths or unknown seed fields as physical world coordinates.
## No ship decision AI, contract transfer, refuelling or cargo mutation here.
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const SeedWorld = preload("res://scripts/sim/world_model.gd")
const NativeLocations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const NativeFleetBootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")

var _roster: RefCounted
var _fleet: RefCounted
var _transit: RefCounted
var _positions: Dictionary = {}
var _location_resolver: RefCounted
var _fleet_suspended: bool = false
var _initial_ship_credit_sources: Dictionary = {}
var _initial_bootstrap_allowed: bool = false
var _fleet_enabled: bool = false
var _last_ship_results: Dictionary = {}

func start_from_seed(seed: Dictionary) -> bool:
    if not super.start_from_seed(seed):
        return false
    _roster = null
    _fleet = null
    _transit = null
    _positions = {}
    _location_resolver = null
    _fleet_suspended = false
    _initial_ship_credit_sources = {}
    _initial_bootstrap_allowed = true
    _fleet_enabled = false
    _last_ship_results = {}
    return true

## External caller must provide actual ship fuel, cargo and physical position
## sources. The frozen native JSON has ship class/location, not their amounts
## or complete coordinates. Do NOT synthesize them to make a test pass.
func configure_fleet(seed: Dictionary, fleet: RefCounted, positions: Dictionary,
        fuel_sources: Dictionary, cargo_sources: Dictionary) -> bool:
    if not is_started() or tick_count != 0 or _fleet_enabled or fleet == null:
        return false
    var checked_world = SeedWorld.new()
    if not checked_world.load_seed(seed) or checked_world.seed_fingerprint() != world.seed_fingerprint():
        return false
    var staged_roster = Roster.new()
    if not staged_roster.load_seed(seed) or not staged_roster.validate_authoritative_state(fleet, fuel_sources, cargo_sources):
        return false
    var graph: RefCounted = staged_roster.registry.graph()
    for location in positions:
        if not (location is String) or not graph.has_location(str(location)):
            return false
        var position: Variant = positions[location]
        if not (position is Vector2) or not is_finite(position.x) or not is_finite(position.y):
            return false
    _roster = staged_roster
    _fleet = fleet
    _transit = Transit.new()
    _positions = positions.duplicate(true)
    _fleet_enabled = true
    return true

## N43: opt-in geometry from frozen Rust body/station formulas. Fuel and
## cargo still require independent authoritative sources, NEVER native guesses.
## This is separate from N40's explicitly provided geometry test fixtures.
func configure_fleet_from_native(seed: Dictionary, fleet: RefCounted,
        fuel_sources: Dictionary, cargo_sources: Dictionary) -> bool:
    if not is_started() or tick_count != 0 or _fleet_enabled:
        return false
    var resolver = NativeLocations.new()
    if not resolver.load_seed(seed):
        return false
    var result: Dictionary = resolver.positions_from_world(world,
        calendar.native_time_units, calendar.origin_known)
    if not bool(result.get("ok", false)):
        return false
    var resolved_positions: Dictionary = result.get("positions", {})
    if not configure_fleet(seed, fleet, resolved_positions, fuel_sources, cargo_sources):
        return false
    _location_resolver = resolver
    return true

## Read-only current native coordinates, not screen positions.
func native_positions_snapshot() -> Dictionary:
    return _positions.duplicate(true) if _fleet_enabled and _location_resolver != null else {}

## Only valid for *fresh* frozen Rust seed initialization, at tick 0.
## Unlike restore, the Rust seeder explicitly starts every initial ship with
## a full class-spec tank and empty cargo; do not refuel on subsequent calls.
## Credits remain source metadata, not an economy ledger or a transfer.
func bootstrap_new_game_native_fleet(seed: Dictionary) -> bool:
    if not is_started() or tick_count != 0 or _fleet_enabled or not _initial_bootstrap_allowed:
        return false
    var built: Dictionary = NativeFleetBootstrap.build_new_game(seed)
    if not bool(built.get("ok", false)):
        return false
    var fleet: RefCounted = built["fleet"]
    if not configure_fleet_from_native(seed, fleet,
            built["fuel_sources"], built["cargo_sources"]):
        return false
    _initial_ship_credit_sources = (built["credit_sources"] as Dictionary).duplicate(true)
    _initial_bootstrap_allowed = false
    return true

func initial_ship_credit_sources() -> Dictionary:
    return _initial_ship_credit_sources.duplicate(true)

func implemented_phases() -> PackedStringArray:
    return PackedStringArray(["bodies", "ships"]) if _fleet_enabled else super.implemented_phases()

func depart_ship(ship_id: String, destination: String) -> bool:
    if not _fleet_enabled or _fleet_suspended or not _fleet.ships.has(ship_id):
        return false
    return _transit.depart(_fleet, _roster.registry.graph(), ship_id, destination,
        _positions, tick_count, clock.tick_scale())

func live_fleet_snapshot() -> Array:
    return _fleet.snapshot() if _fleet_enabled else []

func last_ship_results() -> Dictionary:
    return _last_ship_results.duplicate(true)

func _advance_one_tick() -> void:
    if _fleet_suspended:
        return
    tick_count += 1
    var native_delta: float = clock.tick_scale()
    for phase_index in range(NATIVE_PHASE_ORDER.size()):
        var phase: String = NATIVE_PHASE_ORDER[phase_index]
        if phase == "bodies" and cadence.is_due(phase, tick_count):
            world.advance_orbits(native_delta)
        if phase == "ships" and _fleet_enabled:
            if _location_resolver != null:
                # Body orbit has advanced in the earlier native phase.
                # Calendar commits only at end of tick, hence +native_delta.
                var resolved: Dictionary = _location_resolver.positions_from_world(
                    world, calendar.native_time_units + native_delta, calendar.origin_known)
                if not bool(resolved.get("ok", false)):
                    # Stop rather than moving towards stale coordinates.
                    _fleet_suspended = true
                    _last_ship_results = {"__native_positions__": str(resolved.get("error", "invalid"))}
                    clock.set_paused(true)
                else:
                    _positions = resolved["positions"]
                    _advance_fleet(tick_count, native_delta)
            else:
                _advance_fleet(tick_count, native_delta)
        # Same deterministic phase boundary as P1; never consume or emit
        # due events outside their original phase.
        for event in events.take_due(tick_count, phase_index):
            scheduled_event_due.emit(event)
    calendar.advance_committed_tick(native_delta)
    tick_completed.emit(tick_count)

func _advance_fleet(tick: int, native_delta: float) -> void:
    var ids: Array = _fleet.ships.keys()
    ids.sort()
    var outcomes: Dictionary = {}
    for id in ids:
        var ship: Dictionary = _fleet.ships[id]
        if (ship.get("transit", {}) as Dictionary).is_empty():
            continue
        outcomes[str(id)] = _transit.advance(_fleet, str(id), _positions, tick, native_delta)
    _last_ship_results = outcomes

## N54: orbital checkpoint from the BASE P1 runner, even when ships are
## enabled. Only the N54 cross-domain envelope may persist it. The regular
## P1 checkpoint() continues to refuse incomplete saves when a fleet runs.
func orbital_checkpoint_for_fleet_envelope() -> Dictionary:
    return super.checkpoint() if _fleet_enabled else {}

func transit_cursor_for_fleet_envelope() -> int:
    return _transit.next_token() if _fleet_enabled and _transit != null else -1

## N54: bind a full saved fleet ONLY after a fresh runner has successfully
## restored its P1 orbital checkpoint. No N46 full-fuel seeding is allowed.
## This method never changes any state until source/location/flight/nonce
## validation succeeds. New spawned/modified ship inventories need a future
## schema and must fail closed, not become fake Rust native source IDs.
func attach_restored_native_fleet(seed: Dictionary, fleet: RefCounted,
        next_transit_token: int) -> bool:
    if not is_started() or _fleet_enabled or _initial_bootstrap_allowed or fleet == null:
        return false
    if not (fleet.get("ships") is Dictionary):
        return false
    var staged_roster = Roster.new()
    if not staged_roster.load_seed(seed) or staged_roster.keys().size() != fleet.ships.size():
        return false
    var staged_geometry = NativeLocations.new()
    if not staged_geometry.load_seed(seed):
        return false
    var resolved: Dictionary = staged_geometry.positions_from_world(world,
        calendar.native_time_units, calendar.origin_known)
    if not bool(resolved.get("ok", false)):
        return false
    var graph: RefCounted = staged_roster.registry.graph()
    var max_token: int = 0
    var seen: Dictionary = {}
    for id in staged_roster.keys():
        var ship_id: String = str(id)
        if not fleet.ships.has(ship_id):
            return false
        var value: Variant = fleet.ships[ship_id]
        if not (value is Dictionary):
            return false
        var ship: Dictionary = value
        var meta: Dictionary = staged_roster.metadata(ship_id)
        if str(ship.get("id", "")) != ship_id or str(ship.get("class", "")) != str(meta["class"]):
            return false
        if str(ship.get("faction_id", "")) != str(meta["faction_id"]) or str(ship.get("system_id", "")) != str(meta["system_id"]):
            return false
        if not (ship.get("cargo", null) is Dictionary) or not fleet.can_hold(ship_id, ship["cargo"]):
            return false
        var transit_value: Variant = ship.get("transit", null)
        if not (transit_value is Dictionary):
            return false
        var transit: Dictionary = transit_value
        if transit.is_empty():
            var place: String = str(ship.get("location", ""))
            if place.is_empty() or not graph.has_location(place):
                return false
        else:
            if not str(ship.get("location", "")).is_empty():
                return false
            var from_id: String = str(transit.get("from", ""))
            var to_id: String = str(transit.get("to", ""))
            if not graph.has_location(from_id) or not graph.has_location(to_id):
                return false
            var directed: bool = false
            for leg in graph.outgoing(from_id):
                if str(leg["to"]) == to_id:
                    directed = true
                    break
            if not directed:
                return false
            var token_value: Variant = transit.get("token", null)
            var last_value: Variant = transit.get("last_tick", null)
            var departure_value: Variant = transit.get("departure_tick", null)
            if typeof(token_value) != TYPE_INT or typeof(last_value) != TYPE_INT or typeof(departure_value) != TYPE_INT:
                return false
            var token: int = int(token_value)
            var last_tick: int = int(last_value)
            if token < 1 or seen.has(token) or last_tick < 0 or last_tick > tick_count or int(departure_value) < 0 or int(departure_value) > last_tick:
                return false
            seen[token] = true
            max_token = maxi(max_token, token)
            for key in ["position", "departure_position"]:
                var coords: Variant = transit.get(key, null)
                if not (coords is Array) or coords.size() != 2:
                    return false
                if not (coords[0] is int or coords[0] is float) or not (coords[1] is int or coords[1] is float):
                    return false
                if not is_finite(float(coords[0])) or not is_finite(float(coords[1])):
                    return false
            var raw_total: Variant = transit.get("distance_total", null)
            var raw_travelled: Variant = transit.get("distance_travelled", null)
            if not (raw_total is int or raw_total is float) or not (raw_travelled is int or raw_travelled is float):
                return false
            var total: float = float(raw_total)
            var travelled: float = float(raw_travelled)
            if not is_finite(total) or not is_finite(travelled) or total <= 0.0 or travelled < 0.0 or travelled > total:
                return false
    var staged_transit = Transit.new()
    if not staged_transit.restore_next_token(next_transit_token, max_token):
        return false
    _roster = staged_roster
    _location_resolver = staged_geometry
    _positions = (resolved["positions"] as Dictionary).duplicate(true)
    _fleet = fleet
    _transit = staged_transit
    _fleet_suspended = false
    _last_ship_results = {}
    _initial_ship_credit_sources = {}
    _initial_bootstrap_allowed = false
    _fleet_enabled = true
    return true

## P1 saves cannot represent the authoritative fleet, route geometry, transit
## nonce or external money/cargo. Fail closed until a combined checkpoint exists.
func checkpoint() -> Dictionary:
    if _fleet_enabled:
        return {}
    return super.checkpoint()

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
    if _fleet_enabled or snapshot.has("fleet_state"):
        return false
    var restored: bool = super.restore_checkpoint(snapshot, frozen_seed)
    if restored:
        # A tick-zero user save is still a RESTORE, not a fresh game.
        # Never invoke Rust seeder full-tank initialization after it.
        _initial_bootstrap_allowed = false
    return restored
