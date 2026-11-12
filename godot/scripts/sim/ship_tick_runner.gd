extends "res://scripts/sim/tick_runner.gd"
## N40 CODE_UNVERIFIED. Opt-in native ship tick phase. Never use map pixels,
## route lengths or unknown seed fields as physical world coordinates.
## No ship decision AI, contract transfer, refuelling or cargo mutation here.
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const SeedWorld = preload("res://scripts/sim/world_model.gd")

var _roster: RefCounted
var _fleet: RefCounted
var _transit: RefCounted
var _positions: Dictionary = {}
var _fleet_enabled: bool = false
var _last_ship_results: Dictionary = {}

func start_from_seed(seed: Dictionary) -> bool:
    if not super.start_from_seed(seed):
        return false
    _roster = null
    _fleet = null
    _transit = null
    _positions = {}
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

func implemented_phases() -> PackedStringArray:
    return PackedStringArray(["bodies", "ships"]) if _fleet_enabled else super.implemented_phases()

func depart_ship(ship_id: String, destination: String) -> bool:
    if not _fleet_enabled or not _fleet.ships.has(ship_id):
        return false
    return _transit.depart(_fleet, _roster.registry.graph(), ship_id, destination,
        _positions, tick_count, clock.tick_scale())

func live_fleet_snapshot() -> Array:
    return _fleet.snapshot() if _fleet_enabled else []

func last_ship_results() -> Dictionary:
    return _last_ship_results.duplicate(true)

func _advance_one_tick() -> void:
    tick_count += 1
    var native_delta: float = clock.tick_scale()
    for phase_index in range(NATIVE_PHASE_ORDER.size()):
        var phase: String = NATIVE_PHASE_ORDER[phase_index]
        if phase == "bodies" and cadence.is_due(phase, tick_count):
            world.advance_orbits(native_delta)
        if phase == "ships" and _fleet_enabled:
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

## P1 saves cannot represent the authoritative fleet, route geometry, transit
## nonce or external money/cargo. Fail closed until a combined checkpoint exists.
func checkpoint() -> Dictionary:
    if _fleet_enabled:
        return {}
    return super.checkpoint()

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
    if _fleet_enabled or snapshot.has("fleet_state"):
        return false
    return super.restore_checkpoint(snapshot, frozen_seed)
