extends RefCounted
## B-only diagnostic: exact N38 encoded-byte growth across two committed
## checkpoints. Not a save backend, and never an authority for ledger writes.
## Compares the original immutable receipt records, not just their counts.
const SizeProbe = preload("res://scripts/sim/phase2/p2_perf_b_n38_encoded_size_probe.gd")

static func measure(before: Dictionary, after: Dictionary) -> Dictionary:
    if before.is_empty() or after.is_empty():
        return {"ok": false, "reason": "empty_checkpoint"}
    var old_receipts: Variant = _receipts(before)
    var new_receipts: Variant = _receipts(after)
    if not (old_receipts is Dictionary) or not (new_receipts is Dictionary):
        return {"ok": false, "reason": "missing_n9_receipts"}
    if new_receipts.size() < old_receipts.size():
        return {"ok": false, "reason": "receipt_history_shrank"}
    for id in old_receipts:
        if not new_receipts.has(id):
            return {"ok": false, "reason": "old_receipt_missing"}
        if new_receipts[id] != old_receipts[id]:
            return {"ok": false, "reason": "old_receipt_changed"}
    var old_size: Dictionary = SizeProbe.measure(before)
    var new_size: Dictionary = SizeProbe.measure(after)
    if not old_size.get("ok", false) or not new_size.get("ok", false):
        return {"ok": false, "reason": "encoding_failed"}
    var delta_receipts: int = new_receipts.size() - old_receipts.size()
    var delta_bytes: int = int(new_size["encoded_bytes"]) - int(old_size["encoded_bytes"])
    # Delta includes ALL checkpoint changes; it is not an isolated receipt
    # allocation cost. Negative byte deltas are valid if other data shrank.
    return {
        "ok": true,
        "before_bytes": old_size["encoded_bytes"],
        "after_bytes": new_size["encoded_bytes"],
        "delta_bytes": delta_bytes,
        "before_receipts": old_receipts.size(),
        "after_receipts": new_receipts.size(),
        "added_receipts": delta_receipts,
        "bytes_per_added_receipt_observed": (
            float(delta_bytes) / float(delta_receipts) if delta_receipts > 0 else 0.0),
        "limit_bytes": new_size["limit_bytes"],
        "remaining_bytes": new_size["remaining_bytes"],
        "over_limit_bytes": new_size["over_limit_bytes"],
        "fits": new_size["fits"]
    }

static func _receipts(snapshot: Dictionary) -> Variant:
    var native: Variant = snapshot.get("native_production")
    if not (native is Dictionary):
        return null
    var ledger: Variant = native.get("ledger")
    if not (ledger is Dictionary):
        return null
    var receipts: Variant = ledger.get("receipts")
    if not (receipts is Dictionary):
        return null
    return receipts
