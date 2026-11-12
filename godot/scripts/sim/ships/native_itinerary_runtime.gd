extends RefCounted
## N64 optional one-authority route runtime: a ship performs at most one
## physical next leg per native tick, after actual arrival. This is an
## in-memory adapter only; never overwrites the P1 disk save.
const Live = preload("res://scripts/sim/live_native_fleet_engine.gd")
const Intents = preload("res://scripts/sim/ships/itinerary_intent_registry.gd")
const BaseSave = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")
const CommandReceipts = preload("res://scripts/sim/ships/native_command_receipts.gd")
const FORMAT := "living-sector-itinerary-runtime"
const VERSION := 2 # N66 adds mandatory command_receipts domain

var engine: RefCounted
var intents: RefCounted
var commands: RefCounted
var _active: bool = false
var _last_dispatch_tick: int = -1

func start_new(seed: Dictionary) -> Dictionary:
    if _active:
        return _fail("runtime_already_active")
    var candidate = Live.new()
    var result: Dictionary = candidate.start_new_game(seed)
    if not bool(result.get("ok", false)):
        return result
    engine = candidate
    intents = Intents.new()
    commands = CommandReceipts.new()
    _active = true
    _last_dispatch_tick = -1
    return {"ok": true, "ships": int(result["ships"])}

func assign_route(ship_id: String, operation_id: String, destination: String) -> Dictionary:
    if not _active or not engine.is_live():
        return _fail("world_not_live")
    var plan: Dictionary = engine.plan_ship_itinerary(ship_id, destination)
    if not bool(plan.get("ok", false)):
        return plan
    return intents.register(ship_id, operation_id, plan,
        engine.runner._roster.registry.graph(), engine.runner._fleet.ships)

## N66: player/AI-issued commands get persistent unique IDs.
## Scheduled N64 route dispatch remains a deterministic simulation phase.
func execute_command(operation_id: String, kind: String,
        ship_id: String, args: Dictionary = {}) -> Dictionary:
    if not _active or not engine.is_live():
        return _fail("world_not_live")
    return commands.execute(engine, operation_id, kind, ship_id, args)

func dispatch_current_tick() -> Dictionary:
    if not _active or not engine.is_live():
        return _fail("world_not_live")
    var tick: int = engine.runner.tick_count
    if tick <= _last_dispatch_tick:
        return _fail("already_dispatched_this_tick")
    var checked: Dictionary = _reconcile_arrivals()
    if not bool(checked.get("ok", false)):
        return checked
    var results: Dictionary = {}
    var records: Array = intents.snapshot()
    for record in records:
        if str(record.get("status", "")) != "ready":
            continue
        var ship_id: String = str(record["ship_id"])
        var candidate: Dictionary = intents.command_for_next_leg(
            ship_id, engine.runner._fleet.ships, engine.runner._roster.registry.graph())
        if not bool(candidate.get("ok", false)):
            results[ship_id] = str(candidate.get("reason", "invalid_route"))
            continue
        var planned: Dictionary = {
            "origin": (candidate["remaining"] as Array)[0],
            "destination": (candidate["remaining"] as Array).back(),
            "locations": (candidate["remaining"] as Array).duplicate(),
            "distance": float(candidate["distance"])
        }
        var admission: Dictionary = engine.depart_itinerary_hop(ship_id, planned)
        if not bool(admission.get("ok", false)):
            results[ship_id] = str(admission.get("reason", "physical_departure_rejected"))
            continue
        if not intents.confirm_departure(ship_id, engine.runner._fleet.ships):
            engine._halt("intent_after_physical_departure_mismatch")
            return _fail("fatal_intent_desync")
        results[ship_id] = "departed:" + str(admission["departed_to"])
    # Keep the cursor even if no ships could depart; no replay within a tick.
    _last_dispatch_tick = tick
    return {"ok": true, "tick": tick, "outcomes": results}

func advance_native_tick() -> Dictionary:
    if not _active or not engine.is_live():
        return _fail("world_not_live")
    if not engine.advance_one_native_tick():
        return _fail("world_tick_failed_" + engine.halt_reason())
    return dispatch_current_tick()

func _reconcile_arrivals() -> Dictionary:
    for entry in intents.snapshot():
        if str(entry.get("status", "")) != "flying":
            continue
        var id: String = str(entry["ship_id"])
        if not engine.runner._fleet.ships.has(id) or not engine.docking.ships.has(id):
            return _fail("missing_ship_at_arrival")
        var ship: Dictionary = engine.runner._fleet.ships[id]
        var docking: Dictionary = engine.docking.ships[id]
        if (ship["transit"] as Dictionary).is_empty():
            if bool(docking.get("in_transit", true)) or not intents.confirm_arrival(
                    id, engine.runner._fleet.ships):
                engine._halt("intent_arrival_desync")
                return _fail("fatal_arrival_desync")
    return {"ok": true}

## This envelope must be used INSTEAD OF an N54-only save if any route
## intents exist. It stores the native ship/ledger/docking world + route
## progression and the last dispatch tick in a single integrity scope.
func checkpoint() -> Dictionary:
    if not _active or not engine.is_live():
        return _fail("world_not_live")
    var synced: Dictionary = _reconcile_arrivals()
    if not bool(synced.get("ok", false)):
        return synced
    var native: Dictionary = engine.checkpoint()
    if not bool(native.get("ok", false)):
        return _fail("world_checkpoint_refused")
    var payload: Dictionary = {
        "format": FORMAT, "version": VERSION,
        "world": native, "intents": intents.snapshot(),
        "command_receipts": commands.snapshot(),
        "last_dispatch_tick": _last_dispatch_tick
    }
    var normalized: Variant = JSON.parse_string(JSON.stringify(payload))
    if not (normalized is Dictionary):
        return _fail("cannot_normalize")
    return {"ok": true, "payload": normalized,
        "sha256": BaseSave._canonical(normalized).sha256_text()}

## An atomic staged restore into a fresh runtime. Never mutate an existing
## engine, and never reseed ship fuel, bank balances or intent progress.
func restore_new(seed: Dictionary, envelope: Dictionary) -> Dictionary:
    if _active:
        return _fail("restore_requires_fresh_runtime")
    var body: Variant = envelope.get("payload", null)
    var digest: Variant = envelope.get("sha256", null)
    if not (body is Dictionary) or not (digest is String):
        return _fail("invalid_envelope")
    if BaseSave._canonical(body).sha256_text() != digest:
        return _fail("bad_checksum")
    if body.get("format", "") != FORMAT or body.get("version", -1) != VERSION:
        return _fail("wrong_format")
    if not (body.get("world", null) is Dictionary) or not (body.get("intents", null) is Array) or not (body.get("command_receipts", null) is Array):
        return _fail("missing_domain")
    var raw_tick: Variant = body.get("last_dispatch_tick", null)
    if not (raw_tick is int or raw_tick is float) or not is_finite(float(raw_tick)):
        return _fail("invalid_dispatch_cursor")
    if absf(float(raw_tick)) > 9007199254740991.0 or float(int(raw_tick)) != float(raw_tick):
        return _fail("invalid_dispatch_cursor")
    var candidate = Live.new()
    var world_result: Dictionary = candidate.restore_complete(seed, body["world"])
    if not bool(world_result.get("ok", false)):
        return _fail("world_restore_" + str(world_result.get("reason", "invalid")))
    var cursor: int = int(raw_tick)
    if cursor < -1 or cursor > candidate.runner.tick_count:
        return _fail("future_dispatch_cursor")
    var checked: Array = (body["intents"] as Array).duplicate(true)
    for entry in checked:
        if not (entry is Dictionary):
            return _fail("malformed_intent")
        var index_value: Variant = entry.get("index", null)
        if not (index_value is int or index_value is float) or not is_finite(float(index_value)):
            return _fail("invalid_intent_index")
        if absf(float(index_value)) > 9007199254740991.0 or float(int(index_value)) != float(index_value):
            return _fail("invalid_intent_index")
        entry["index"] = int(index_value)
    var staged = Intents.new()
    if not staged.restore(checked, candidate.runner._fleet.ships,
            candidate.runner._roster.registry.graph()):
        return _fail("intent_state_mismatch")
    var staged_commands = CommandReceipts.new()
    if not staged_commands.restore(body["command_receipts"]):
        return _fail("invalid_command_receipts")
    engine = candidate
    intents = staged
    commands = staged_commands
    _last_dispatch_tick = cursor
    _active = true
    return {"ok": true, "tick": engine.runner.tick_count,
        "intents": intents.snapshot().size()}

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
