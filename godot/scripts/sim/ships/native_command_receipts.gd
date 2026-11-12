extends RefCounted
## N66: exactly-once request identity across dock/undock/depart actions.
## Wraps N57 authorities; never creates a second ship/dock/money world.
const Save = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")
const ALLOWED := ["dock", "undock", "depart", "depart_itinerary_hop"]
var _receipts: Dictionary = {}
const MAX_RECEIPTS := 100000

func execute(live: RefCounted, operation_id: String, kind: String,
        ship_id: String, args: Dictionary = {}) -> Dictionary:
    if live == null or not live.has_method("is_live") or not live.is_live():
        return _reject("world_not_live")
    if operation_id.is_empty() or operation_id.length() > 160 or not ALLOWED.has(kind):
        return _reject("invalid_command")
    if ship_id.is_empty() or not live.runner._fleet.ships.has(ship_id):
        return _reject("unknown_ship")
    var request: Dictionary = {"kind": kind, "ship_id": ship_id,
        "args": args.duplicate(true)}
    var fingerprint: String = Save._canonical(request).sha256_text()
    if _receipts.has(operation_id):
        var existing: Dictionary = _receipts[operation_id]
        if existing["fingerprint"] != fingerprint:
            return _reject("operation_payload_conflict")
        var replay: Dictionary = (existing["result"] as Dictionary).duplicate(true)
        replay["replayed"] = true
        return replay
    if _receipts.size() >= MAX_RECEIPTS:
        return _reject("receipt_capacity_reached")
    var result: Dictionary = {}
    match kind:
        "dock":
            if args.keys().size() > 1 or (args.has("preferred_type") and not (args["preferred_type"] is String)):
                return _reject("invalid_dock_arguments")
            result = live.request_dock(ship_id, operation_id,
                str(args.get("preferred_type", "")))
        "undock":
            if not args.is_empty():
                return _reject("unexpected_arguments")
            result = live.undock(ship_id, operation_id)
        "depart":
            if args.keys() != ["destination"] or not (args.get("destination", null) is String):
                return _reject("invalid_departure_arguments")
            result = live.depart(ship_id, str(args["destination"]))
        "depart_itinerary_hop":
            if args.keys() != ["itinerary"] or not (args.get("itinerary", null) is Dictionary):
                return _reject("invalid_itinerary_arguments")
            result = live.depart_itinerary_hop(ship_id, args["itinerary"])
        _:
            return _reject("unsupported_command")
    # Persist both success and stable rejection: the exact same operation
    # must not run again with changed world conditions after a reload.
    _receipts[operation_id] = {"operation_id": operation_id,
        "fingerprint": fingerprint, "request": request, "result": result.duplicate(true)}
    return result.duplicate(true)

func snapshot() -> Array:
    var ids: Array = _receipts.keys()
    ids.sort()
    var records: Array = []
    for id in ids:
        records.append((_receipts[id] as Dictionary).duplicate(true))
    return records

func restore(records: Array) -> bool:
    if records.size() > MAX_RECEIPTS:
        return false
    var restored: Dictionary = {}
    for item in records:
        if not (item is Dictionary):
            return false
        var value: Dictionary = item
        var op: String = str(value.get("operation_id", ""))
        var request: Variant = value.get("request", null)
        var result: Variant = value.get("result", null)
        var digest: Variant = value.get("fingerprint", null)
        if op.is_empty() or op.length() > 160 or restored.has(op):
            return false
        if not (request is Dictionary) or not (result is Dictionary) or not (digest is String):
            return false
        var kind: String = str(request.get("kind", ""))
        var ship: String = str(request.get("ship_id", ""))
        if not ALLOWED.has(kind) or ship.is_empty() or not (request.get("args", null) is Dictionary):
            return false
        if Save._canonical(request).sha256_text() != digest:
            return false
        if not (result.get("ok", null) is bool):
            return false
        restored[op] = value.duplicate(true)
    _receipts = restored
    return true

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
