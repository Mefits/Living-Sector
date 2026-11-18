extends RefCounted
## E-owned bounded observation of detached authoritative checkpoint encoding.
## Encoding is deliberately outside the paid tick and does not change N38.
const MAX_ENCODED_BYTES: int = 268435456
const CHECKPOINTS: Array[int] = [1, 20, 60, 100, 200, 300, 600, 900]

static func measure(tick: int, direct: Dictionary, worker: Dictionary,
        exact_gate: Dictionary) -> Dictionary:
    if not CHECKPOINTS.has(tick) or exact_gate.get("accepted", false) != true or (
            int(exact_gate.get("tick", -1)) != tick or
            exact_gate.get("exact", false) != true):
        return {"accepted": false, "reason": "unverified_exact_boundary"}
    var sizes: Dictionary = {}
    var costs: Dictionary = {}
    for side in ["direct", "worker"]:
        var checkpoint: Dictionary = direct if side == "direct" else worker
        if typeof(checkpoint.get("tick", null)) != TYPE_INT or (
                int(checkpoint["tick"]) != tick):
            return {"accepted": false, "reason": "invalid_" + side + "_clock"}
        var started: int = Time.get_ticks_usec()
        var encoded: PackedByteArray = var_to_bytes(checkpoint)
        var elapsed: int = Time.get_ticks_usec() - started
        if elapsed < 0 or encoded.is_empty() or encoded.size() > MAX_ENCODED_BYTES:
            return {"accepted": false, "reason": "invalid_" + side + "_encoding"}
        sizes[side] = encoded.size()
        costs[side] = elapsed
        # Do not retain encoded payloads, World references or duplicate trees.
    return {"accepted": true, "tick": tick, "encoded_bytes": sizes,
        "encode_wall_usec": costs, "time_kind": "elapsed_wall_not_cpu",
        "included_in_paid_tick_window": false, "exact_parity_gate": true}

static func summarize(rows: Array, expected: Array[int]) -> Dictionary:
    if rows.size() != expected.size() or rows.is_empty() or rows.size() > CHECKPOINTS.size():
        return {"accepted": false, "reason": "incomplete_checkpoint_bytes"}
    var previous: int = -1
    var first: Dictionary = {}
    var last: Dictionary = {}
    var max_bytes: Dictionary = {"direct": 0, "worker": 0}
    var total_encode_usec: Dictionary = {"direct": 0, "worker": 0}
    var series: Array[Dictionary] = []
    for i in range(rows.size()):
        if not (rows[i] is Dictionary):
            return {"accepted": false, "reason": "malformed_row"}
        var row: Dictionary = rows[i]
        var tick: int = expected[i]
        if not CHECKPOINTS.has(tick) or tick <= previous or (
                typeof(row.get("tick", null)) != TYPE_INT or int(row["tick"]) != tick or
                row.get("accepted", false) != true or
                row.get("exact_parity_gate", false) != true or
                row.get("time_kind", "") != "elapsed_wall_not_cpu" or
                row.get("included_in_paid_tick_window", true) != false):
            return {"accepted": false, "reason": "invalid_checkpoint_boundary"}
        var bytes: Variant = row.get("encoded_bytes")
        var costs: Variant = row.get("encode_wall_usec")
        if not (bytes is Dictionary) or not (costs is Dictionary) or (
                bytes.size() != 2 or costs.size() != 2):
            return {"accepted": false, "reason": "incomplete_encoding_sides"}
        for side in ["direct", "worker"]:
            if typeof(bytes.get(side, null)) != TYPE_INT or (
                    int(bytes[side]) < 1 or int(bytes[side]) > MAX_ENCODED_BYTES or
                    typeof(costs.get(side, null)) != TYPE_INT or int(costs[side]) < 0):
                return {"accepted": false, "reason": "invalid_" + side + "_sample"}
            max_bytes[side] = maxi(int(max_bytes[side]), int(bytes[side]))
            total_encode_usec[side] = int(total_encode_usec[side]) + int(costs[side])
        var detached: Dictionary = {"tick": tick, "encoded_bytes": bytes.duplicate(true),
            "encode_wall_usec": costs.duplicate(true)}
        if first.is_empty():
            first = detached
        last = detached
        series.append(detached)
        previous = tick
    var growth: Dictionary = {}
    for side in ["direct", "worker"]:
        growth[side] = int(last["encoded_bytes"][side]) - int(first["encoded_bytes"][side])
    return {"accepted": true, "from_tick": first["tick"], "to_tick": last["tick"],
        "growth_bytes": growth, "peak_encoded_bytes": max_bytes,
        "total_encode_wall_usec": total_encode_usec, "samples": series,
        "time_kind": "elapsed_wall_not_cpu", "performance_claim": false}
