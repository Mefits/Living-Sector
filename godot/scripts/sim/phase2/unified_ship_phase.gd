extends RefCounted
## N14/N46 one-World fleet adapter. There is NO second TickRunner, no
## duplicate ship wallet and no fake AI. Original Rust transit rules run
## only for actual explicit departures on native directed navigation edges.
const ShipState = preload("res://scripts/sim/ship_state.gd")
const ShipTransit = preload("res://scripts/sim/ship_transit.gd")
const NativeIntercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const N140Gate = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")
const NativeShipMemory = preload("res://scripts/sim/phase2/unified_native_ship_price_observation.gd")

static func _load(world: Dictionary) -> Dictionary:
    if not (world.get("ships") is Dictionary) or typeof(world.get("ship_next_token", null)) != TYPE_INT:
        return {"ok": false, "reason": "missing_canonical_fleet"}
    var fleet = ShipState.new()
    var ordered: Array = world["ships"].keys()
    ordered.sort()
    var rows: Array = []
    var max_token: int = 0
    for id in ordered:
        var ship: Variant = world["ships"][id]
        if not (ship is Dictionary) or str(ship.get("id", "")) != str(id):
            return {"ok": false, "reason": "invalid_ship_identity"}
        var trans: Variant = ship.get("transit", null)
        if not (trans is Dictionary):
            return {"ok": false, "reason": "invalid_ship_transit"}
        if not trans.is_empty():
            max_token = maxi(max_token, int(trans.get("token", -1)))
        # ShipState.restore validates and deep-copies each record into its own
        # fleet. Passing the read-only source row avoids a redundant full
        # copy before N14/N84 without exposing World to transit mutations.
        rows.append(ship)
    if not fleet.restore(rows):
        return {"ok": false, "reason": "invalid_ship_state"}
    var transit = ShipTransit.new()
    if not transit.restore_next_token(int(world["ship_next_token"]), max_token):
        return {"ok": false, "reason": "invalid_ship_token_cursor"}
    return {"ok": true, "fleet": fleet, "transit": transit}

## Move only ships with an EXISTING real N14 transit receipt. Idle ships do
## not automatically decide their routes until the native N153 AI is wired.
static func advance(world: Dictionary, positions: Dictionary,
        tick: int, tick_scale: float, resolver: RefCounted,
        tick_multiplier: int = 1, observers: Array = [],
        orbital_model: RefCounted = null,
        native_time: float = -1.0) -> Dictionary:
    if tick < 1 or not is_finite(tick_scale) or tick_scale <= 0.0:
        return {"ok": false, "reason": "invalid_fleet_clock"}
    var opened: Dictionary = _load(world)
    if not opened.get("ok", false):
        return opened
    var state: RefCounted = opened["fleet"]
    var motion: RefCounted = opened["transit"]
    # The original Rust tick_ships pass gates N14 flight and N84
    # decisions with one native AgentLod cursor. The cursor is owned
    # by these real N39 ship rows, never a parallel ship runner.
    var gate: Dictionary = N140Gate.stage(
        world, positions, tick, tick_multiplier, observers)
    if not gate.get("ok", false):
        return gate
    # N140.stage already returns a deep-detached fleet (its out copy).
    # This stage exclusively owns the returned rows until the final N39
    # publication copy. A second full-fleet deep copy here is redundant.
    # Never assign world["ships"] directly: motion mutates these rows.
    state.ships = gate["ships"]
    var fired: Dictionary = gate["fired"]
    var ids: Array = state.ships.keys()
    ids.sort()
    var outcomes: Dictionary = {}
    var mutable: bool = bool(gate["changed"])
    # Build N43 ephemerides ONLY for active transits on fired N140 ticks.
    # Cache by destination; all ships use the same committed World/orbit
    # snapshot, with no additional World copy, clock or guessed motion.
    var forecast_cache: Dictionary = {}
    var arrival_cache: Dictionary = {}
    var solar_cache: Dictionary = {}
    var planet_cache: Dictionary = {}
    var target_body_cache: Dictionary = {}
    for id in ids:
        var row: Dictionary = state.ships[id]
        # A skipped Rust ship cannot move, burn fuel, observe prices,
        # update crew needs or make an N84/N148 decision this tick.
        if not fired.has(str(id)):
            continue
        if (row.get("transit", {}) as Dictionary).is_empty():
            continue
        var scale: int = int(fired[str(id)])
        if scale < 1:
            return {"ok": false, "reason": "invalid_native_lod_fired_scale"}
        var destination: String = str(
            (row["transit"] as Dictionary).get("to", ""))
        var forecast: Dictionary = {}
        if forecast_cache.has(destination):
            forecast = forecast_cache[destination]
        elif resolver != null and orbital_model != null and (
                resolver.has_method("ephemeris_for_location") and
                native_time >= 0.0):
            var resolved: Dictionary = resolver.ephemeris_for_location(
                destination, orbital_model, native_time)
            if bool(resolved.get("ok", false)):
                var candidate: Dictionary = resolved["trajectory"]
                # Fail closed: a prediction must agree with the physical
                # N43 coordinate already used for canonical transit.
                var actual: Variant = positions.get(destination, null)
                if actual is Vector2 and (
                        NativeIntercept.valid_trajectory(candidate)) and (
                        NativeIntercept.position_after(candidate, 0.0).distance_to(
                            actual) < 0.0005):
                    forecast = candidate
            forecast_cache[destination] = forecast
        var tolerance: float = ShipTransit.ARRIVAL_THRESHOLD
        if arrival_cache.has(destination):
            tolerance = float(arrival_cache[destination])
        elif resolver != null and resolver.has_method(
                "arrival_tolerance_for_location"):
            var measured: float = float(
                resolver.arrival_tolerance_for_location(destination))
            if measured > 0.0 and is_finite(measured):
                tolerance = measured
            arrival_cache[destination] = tolerance
        var origin_system_id: String = str(row.get("system_id", ""))
        var solar: Dictionary = {}
        if solar_cache.has(origin_system_id):
            solar = solar_cache[origin_system_id]
        elif resolver != null and resolver.has_method(
                "verified_solar_exclusion"):
            solar = resolver.verified_solar_exclusion(origin_system_id)
            solar_cache[origin_system_id] = solar
        var planets: Array = []
        if planet_cache.has(origin_system_id):
            planets = planet_cache[origin_system_id]
        elif resolver != null and orbital_model != null and (
                resolver.has_method("verified_planet_obstacles")):
            planets = resolver.verified_planet_obstacles(
                origin_system_id, orbital_model)
            planet_cache[origin_system_id] = planets
        var target_body_id: String = ""
        if target_body_cache.has(destination):
            target_body_id = str(target_body_cache[destination])
        elif resolver != null and resolver.has_method("body_for_location"):
            target_body_id = resolver.body_for_location(destination)
            target_body_cache[destination] = target_body_id
        var outcome: String = motion.advance(
            state, str(id), positions, tick, tick_scale * float(scale),
            scale, true, forecast, tolerance, solar, planets,
            target_body_id)
        if not (outcome in ["arrived", "moving", "out_of_fuel", "holding"]):
            return {"ok": false, "reason": "native_ship_" + outcome,
                "ship": str(id)}
        if outcome == "arrived":
            var location: String = str(state.ships[id].get("location", ""))
            var system_id: String = resolver.system_for_location(location) if resolver != null else ""
            if system_id.is_empty():
                return {"ok": false, "reason": "arrival_system_unmapped", "ship": str(id)}
            state.ships[id]["system_id"] = system_id
            # Rust ship/mod.rs::advance_transits records ONLY real
            # arrived destinations in ShipMemory.visited; do not
            # pre-reveal markets or neighboring systems on departure.
            var existing_memory: Variant = state.ships[id].get("memory", null)
            if existing_memory == null:
                existing_memory = NativeShipMemory.default_memory()
            if not (existing_memory is Dictionary) or not (
                    existing_memory.get("visited") is Array):
                return {"ok": false, "reason": "native_arrival_memory_invalid",
                    "ship": str(id)}
            var remembered: Dictionary = existing_memory.duplicate(true)
            if not remembered["visited"].has(location):
                remembered["visited"].append(location)
            state.ships[id]["memory"] = remembered
        outcomes[str(id)] = outcome
        mutable = true
    if not mutable:
        return {"ok": true, "changed": false, "outcomes": {},
            "fired": fired.duplicate(true),
            "n140_fired_count": int(gate["fired_count"]),
            "n140_skipped_count": int(gate["skipped_count"]),
            "n140_stats": gate.get("stats", {}).duplicate(true),
            "n140_recomputed": bool(gate["recomputed"])}
    # N140.stage() deep-detaches the entire fleet before motion.advance().
    # No other writer sees state.ships during this phase, and the N39 caller
    # owns the returned preview. Re-copying every nested cargo/BT/memory row
    # here adds a second O(fleet bytes) pass on each moving paid tick.
    # Never return world["ships"]: only the already detached N140 fleet.
    return {"ok": true, "changed": true, "ships": state.ships,
        "next_token": motion.next_token(), "outcomes": outcomes,
        "fired": fired.duplicate(true),
        "n140_fired_count": int(gate["fired_count"]),
        "n140_skipped_count": int(gate["skipped_count"]),
        "n140_stats": gate.get("stats", {}).duplicate(true),
        "n140_recomputed": bool(gate["recomputed"])}

## An explicit player/AI dispatcher can call this only once per command.
## No direct UI mutation: N39 validates and commits the resulting snapshot.
static func depart(world: Dictionary, graph: RefCounted,
        positions: Dictionary, tick: int, tick_scale: float,
        ship_id: String, destination: String) -> Dictionary:
    if ship_id.is_empty() or destination.is_empty() or graph == null:
        return {"ok": false, "reason": "invalid_ship_order"}
    var opened: Dictionary = _load(world)
    if not opened.get("ok", false):
        return opened
    var state: RefCounted = opened["fleet"]
    var motion: RefCounted = opened["transit"]
    # N21: transit cannot release an occupied docking slot implicitly.
    # Issue a real undock command first; no phantom dock or cargo launch.
    if not state.ships.has(ship_id) or not str(state.ships[ship_id].get("docked_at", "")).is_empty():
        return {"ok": false, "reason": "ship_must_undock_first"}
    if not motion.depart(state, graph, ship_id, destination,
            positions, tick, tick_scale):
        return {"ok": false, "reason": "native_departure_rejected"}
    # ShipState.restore() already deep-detached every fleet row from World.
    # motion.depart() mutates only this exclusively owned fleet; copying
    # every row again for a BT travel preview costs O(all ship cargo/BT)
    # per departure proposal, even though N146 will revalidate the command.
    # Return the owned snapshot, never world["ships"] or a shallow alias.
    return {"ok": true, "changed": true, "ships": state.ships,
        "next_token": motion.next_token(),
        "outcomes": {ship_id: "departed_to_" + destination}}
