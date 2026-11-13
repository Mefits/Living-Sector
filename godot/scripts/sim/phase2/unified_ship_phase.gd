extends RefCounted
## N14/N46 one-World fleet adapter. There is NO second TickRunner, no
## duplicate ship wallet and no fake AI. Original Rust transit rules run
## only for actual explicit departures on native directed navigation edges.
const ShipState = preload("res://scripts/sim/ship_state.gd")
const ShipTransit = preload("res://scripts/sim/ship_transit.gd")

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
        rows.append(ship.duplicate(true))
    if not fleet.restore(rows):
        return {"ok": false, "reason": "invalid_ship_state"}
    var transit = ShipTransit.new()
    if not transit.restore_next_token(int(world["ship_next_token"]), max_token):
        return {"ok": false, "reason": "invalid_ship_token_cursor"}
    return {"ok": true, "fleet": fleet, "transit": transit}

## Move only ships with an EXISTING real N14 transit receipt. Idle ships do
## not automatically decide their routes until the native N153 AI is wired.
static func advance(world: Dictionary, positions: Dictionary,
        tick: int, tick_scale: float, resolver: RefCounted) -> Dictionary:
    if tick < 1 or not is_finite(tick_scale) or tick_scale <= 0.0:
        return {"ok": false, "reason": "invalid_fleet_clock"}
    var opened: Dictionary = _load(world)
    if not opened.get("ok", false):
        return opened
    var state: RefCounted = opened["fleet"]
    var motion: RefCounted = opened["transit"]
    var ids: Array = state.ships.keys()
    ids.sort()
    var outcomes: Dictionary = {}
    var mutable: bool = false
    for id in ids:
        var row: Dictionary = state.ships[id]
        if (row.get("transit", {}) as Dictionary).is_empty():
            continue
        var outcome: String = motion.advance(state, str(id), positions, tick, tick_scale)
        if not (outcome in ["arrived", "moving", "out_of_fuel"]):
            return {"ok": false, "reason": "native_ship_" + outcome,
                "ship": str(id)}
        if outcome == "arrived":
            var location: String = str(state.ships[id].get("location", ""))
            var system_id: String = resolver.system_for_location(location) if resolver != null else ""
            if system_id.is_empty():
                return {"ok": false, "reason": "arrival_system_unmapped", "ship": str(id)}
            state.ships[id]["system_id"] = system_id
        outcomes[str(id)] = outcome
        mutable = true
    if not mutable:
        return {"ok": true, "changed": false, "outcomes": {}}
    var updated: Dictionary = {}
    for id in ids:
        updated[str(id)] = (state.ships[id] as Dictionary).duplicate(true)
    return {"ok": true, "changed": true, "ships": updated,
        "next_token": motion.next_token(), "outcomes": outcomes}

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
    if not motion.depart(state, graph, ship_id, destination,
            positions, tick, tick_scale):
        return {"ok": false, "reason": "native_departure_rejected"}
    var updated: Dictionary = {}
    for id in state.ships:
        updated[str(id)] = (state.ships[id] as Dictionary).duplicate(true)
    return {"ok": true, "changed": true, "ships": updated,
        "next_token": motion.next_token(),
        "outcomes": {ship_id: "departed_to_" + destination}}
