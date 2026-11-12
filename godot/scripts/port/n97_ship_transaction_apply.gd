extends RefCounted
## N97: exclusive server-side apply_transaction() from frozen Rust
## native/crates/sim_server/src/engine/transactions.rs.
## This layer is NOT a second ledger or a speculative ship BT action:
## the output world is a new staged authoritative snapshot. Integrate
## with ONE global ledger and tick in Phase 2, not earlier.
const Physical = preload("res://scripts/port/n97_ship_physical_settlement.gd")

const PHYSICAL_KINDS = ["buy", "sell", "mine", "refuel"]
const CONTRACT_KINDS = ["accept", "embark", "deliver"]

## Snapshot contract:
## world["ships"][ship_id]["transaction"] = {
##  "sequence": int,
##  "pending": {"id": int, "request": ShipTransaction as Dictionary,
##              "result": null | {"ok": bool, "reason": str}}
## }
## Rust pending.result == None is required before one exclusive apply.
## Already resolved and out-of-order commands are SILENT no-ops; do not
## generate additional events, money or receipt mutation on retries.
##
## Unsupported contract variants are NOT automatically rejected: their
## authoritative funding, contract and population Apply modules are
## missing from N97. Return deferred without changing mailbox.
static func apply(world: Dictionary, ship_id: String,
        request_id: int, tick: int) -> Dictionary:
    if ship_id.is_empty() or request_id <= 0 or tick < 0:
        return _error("invalid_apply_identity", world)
    if not (world.get("ships", null) is Dictionary):
        return _error("missing_ship_authority", world)
    var source: Variant = world["ships"].get(ship_id, null)
    if not (source is Dictionary):
        return {"ok": true, "status": "noop", "reason": "unknown_ship",
            "world": world, "events": []}
    var transaction: Variant = source.get("transaction", null)
    if not (transaction is Dictionary):
        return _error("missing_transaction_mailbox", world)
    var sequence: Variant = transaction.get("sequence", null)
    var pending: Variant = transaction.get("pending", null)
    if typeof(sequence) != TYPE_INT or not (pending is Dictionary):
        return _error("invalid_mailbox", world)
    if pending.is_empty():
        return {"ok": true, "status": "noop", "reason": "no_pending",
            "world": world, "events": []}
    if typeof(pending.get("id", null)) != TYPE_INT:
        return _error("invalid_pending_id", world)
    if int(pending["id"]) != request_id or pending.get("result", null) != null:
        return {"ok": true, "status": "noop", "reason": "stale_or_replayed",
            "world": world, "events": []}
    var request: Variant = pending.get("request", null)
    if not (request is Dictionary):
        return _error("missing_request_payload", world)
    var kind: String = str(request.get("kind", ""))
    if CONTRACT_KINDS.has(kind):
        return {"ok": false, "status": "deferred",
            "reason": "requires_native_contract_funding_apply",
            "world": world, "events": []}
    if not PHYSICAL_KINDS.has(kind):
        return _error("unknown_transaction_kind", world)
    var result: Dictionary = Physical.simulate(world, ship_id, request, tick)
    # Failure still writes the Rust negative acknowledgement to the BT
    # mailbox, but NONE of the proposed economic mutations are published.
    var staged: Dictionary = world.duplicate(true)
    if bool(result.get("ok", false)):
        staged = (result["world"] as Dictionary).duplicate(true)
    if not (staged["ships"].get(ship_id, null) is Dictionary):
        return _error("transaction_lost_ship", world)
    var target: Dictionary = staged["ships"][ship_id]
    var current: Dictionary = target["transaction"]["pending"]
    if int(current.get("id", -1)) != request_id or current.get("result", null) != null:
        return _error("transaction_changed_before_apply", world)
    current["result"] = {"ok": true} if bool(result.get("ok", false)) else {
        "ok": false, "reason": str(result.get("reason", "rejected"))
    }
    if bool(result.get("ok", false)):
        target["lifecycle_dirty"] = true
    var contract_id: Variant = request.get("contract_id",
        target.get("active_contract_id", null))
    var event: Dictionary = {
        "kind": "ship_transaction_applied" if bool(result.get("ok", false))
            else "ship_transaction_rejected",
        "ship_id": ship_id, "request_id": request_id,
        "operation": kind, "tick": tick,
        "location": request.get("location", null),
        "commodity": "fuel" if kind == "refuel" else request.get("commodity", null),
        "contract_id": contract_id,
        "requested_quantity": request.get("quantity", null),
        "reason": null if bool(result.get("ok", false)) else
            str(result.get("reason", "rejected")),
        "quantity": result.get("quantity", null),
        "payment": result.get("payment", null)
    }
    return {"ok": true,
        "status": "applied" if bool(result.get("ok", false)) else "rejected",
        "world": staged, "events": [event],
        "quantity": result.get("quantity", null),
        "payment": result.get("payment", null),
        "reason": result.get("reason", "")}

static func _error(reason: String, world: Dictionary) -> Dictionary:
    return {"ok": false, "status": "invalid", "reason": reason,
        "world": world, "events": []}
