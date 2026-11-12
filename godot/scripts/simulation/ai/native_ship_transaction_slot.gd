extends RefCounted
## N90: frozen Rust agents/ship/transactions.rs and actions.rs.
## ONE outstanding request per ship. The Apply phase alone commits/rejects.
## This is a TRANSIENT mailbox; sequence is not a durable replay journal.
## No in-place ship/cargo/credit mutations, no Godot scene dependencies.

const RUNNING: String = "running"
const SUCCESS: String = "success"
const FAILURE: String = "failure"
const NONE: String = "none"
const MAX_SEQUENCE: int = 9223372036854775807
const TRANSACTION_KINDS = [
    "accept", "buy", "sell", "refuel", "mine", "embark", "deliver"
]

static func empty() -> Dictionary:
    return {"sequence": 0, "pending": {}}

static func valid_slot(slot: Dictionary) -> bool:
    var seq: Variant = slot.get("sequence", null)
    if typeof(seq) != TYPE_INT or int(seq) < 0:
        return false
    var pending: Variant = slot.get("pending", null)
    if not (pending is Dictionary):
        return false
    if pending.is_empty():
        return true
    if typeof(pending.get("id", null)) != TYPE_INT:
        return false
    if int(pending["id"]) <= 0 or int(pending["id"]) > int(seq):
        return false
    var request: Variant = pending.get("request", null)
    if not (request is Dictionary) or not TRANSACTION_KINDS.has(str(request.get("kind", ""))):
        return false
    if not pending.has("result"):
        return false
    if not (pending["result"] == null
            or pending["result"] == "ok"
            or pending["result"] == "error"):
        return false
    return true

## Rust TransactionSlot::begin() checked_add then emit
## RequestShipTransaction { ship, request_id }. A pending request makes
## all other economic action leaves wait or fail; no second issue.
static func begin(slot: Dictionary, request: Dictionary) -> Dictionary:
    if not valid_slot(slot):
        return _failure(slot, "invalid_slot")
    if not TRANSACTION_KINDS.has(str(request.get("kind", ""))):
        return _failure(slot, "invalid_transaction_kind")
    if not (slot["pending"] as Dictionary).is_empty():
        return _failure(slot, "pending_exists")
    if int(slot["sequence"]) == MAX_SEQUENCE:
        return _failure(slot, "sequence_overflow")
    var updated: Dictionary = slot.duplicate(true)
    updated["sequence"] = int(updated["sequence"]) + 1
    updated["pending"] = {
        "id": int(updated["sequence"]),
        "request": request.duplicate(true),
        "result": null
    }
    return {
        "ok": true, "status": RUNNING, "state": updated,
        "request_id": int(updated["sequence"]),
        "command": {"type": "RequestShipTransaction",
                    "request_id": int(updated["sequence"])}
    }

## Acknowledgment can only be attached by the authoritative Apply phase.
## False = rejection; true = committed. Duplicate/mismatched replies do
## NOT emit a second receipt and do not change the mailbox.
static func acknowledge(slot: Dictionary, request_id: int, success: bool) -> Dictionary:
    if not valid_slot(slot):
        return _failure(slot, "invalid_slot")
    var pending: Dictionary = slot["pending"]
    if pending.is_empty() or int(pending["id"]) != request_id:
        return _failure(slot, "unknown_request_id")
    if pending["result"] != null:
        return _failure(slot, "duplicate_apply_reply")
    var updated: Dictionary = slot.duplicate(true)
    updated["pending"]["result"] = "ok" if success else "error"
    return {"ok": true, "state": updated}

## Rust poll_transaction: if a DIFFERENT transaction is outstanding,
## clear it and return Failure; if no Apply response yet, Running;
## on confirmed result, consume pending and report Success/Failure.
## An ABSENT mailbox returns NONE (caller should prepare a fresh request).
## Matching only by the fields that Rust matches for each leaf.
static func poll(slot: Dictionary, expected: Dictionary) -> Dictionary:
    if not valid_slot(slot):
        return _failure(slot, "invalid_slot")
    var pending: Dictionary = slot["pending"]
    if pending.is_empty():
        return {"ok": true, "status": NONE, "state": slot.duplicate(true)}
    var request: Dictionary = pending["request"]
    if not _matching(request, expected):
        var cleared: Dictionary = slot.duplicate(true)
        cleared["pending"] = {}
        return {
            "ok": true, "status": FAILURE, "state": cleared,
            "reason": "pending_different_action"
        }
    if pending["result"] == null:
        return {"ok": true, "status": RUNNING, "state": slot.duplicate(true)}
    var updated: Dictionary = slot.duplicate(true)
    updated["pending"] = {}
    return {
        "ok": true, "status": SUCCESS if pending["result"] == "ok" else FAILURE,
        "state": updated,
        "reason": "apply_accepted" if pending["result"] == "ok" else "apply_rejected"
    }

static func _matching(request: Dictionary, expected: Dictionary) -> bool:
    var kind: String = str(expected.get("kind", ""))
    if kind == "sell_all":
        return request.get("kind", "") == "sell"
    if str(request.get("kind", "")) != kind:
        return false
    match kind:
        "buy", "sell":
            return request.get("commodity", null) == expected.get("commodity", null)
        "accept", "embark", "deliver":
            return request.get("contract_id", null) == expected.get("contract_id", null)
        "mine":
            # Rust Mine checks old qty > 0 and <= current requested qty.
            return (
                request.get("location", null) == expected.get("location", null)
                and request.get("body_id", null) == expected.get("body_id", null)
                and request.get("commodity", null) == expected.get("commodity", null)
                and typeof(request.get("quantity", null)) == TYPE_INT
                and typeof(expected.get("quantity", null)) == TYPE_INT
                and int(request["quantity"]) > 0
                and int(request["quantity"]) <= int(expected["quantity"])
            )
        "refuel":
            return true
        _:
            return false

## Rust replanning resets transaction.pending without resetting
## transaction.sequence. This cancellation is separate from any command
## already accepted by the Apply phase — that phase still needs its own
## request_id checks and anti-replay rules.
static func cancel_on_replan(slot: Dictionary) -> Dictionary:
    if not valid_slot(slot):
        return _failure(slot, "invalid_slot")
    var updated: Dictionary = slot.duplicate(true)
    updated["pending"] = {}
    return {"ok": true, "state": updated}

static func _failure(slot: Dictionary, reason: String) -> Dictionary:
    return {"ok": false, "status": FAILURE, "reason": reason,
            "state": slot.duplicate(true)}
