extends RefCounted
## B-only N38 diagnostic. Measures the actual UTF-8 bytes that SaveState
## would write, including exact f64 tags, digest envelope, indentation and
## trailing newline. It never writes files, mutates the snapshot or changes
## the authoritative save limit / recovery protocol.
const SaveState = preload("res://scripts/sim/save_state.gd")

static func measure(snapshot: Dictionary) -> Dictionary:
    if snapshot.is_empty():
        return {"ok": false, "reason": "empty_checkpoint"}
    # Keep the original checkpoint owned by the caller. SaveState._wrap()
    # builds its own transport tree and does not mutate the original.
    var encoded: String = JSON.stringify(
        SaveState._wrap(snapshot), "\t", true, true) + "\n"
    var byte_count: int = encoded.to_utf8_buffer().size()
    var limit: int = SaveState.MAX_SAVE_BYTES
    return {
        "ok": true,
        "encoded_bytes": byte_count,
        "limit_bytes": limit,
        "remaining_bytes": maxi(0, limit - byte_count),
        "over_limit_bytes": maxi(0, byte_count - limit),
        "fits": byte_count <= limit,
        "receipt_count": _receipt_count(snapshot)
    }

static func _receipt_count(snapshot: Dictionary) -> int:
    var native: Variant = snapshot.get("native_production")
    if not (native is Dictionary):
        return 0
    var ledger: Variant = native.get("ledger")
    if not (ledger is Dictionary):
        return 0
    var receipts: Variant = ledger.get("receipts")
    if not (receipts is Dictionary):
        return 0
    return receipts.size()
