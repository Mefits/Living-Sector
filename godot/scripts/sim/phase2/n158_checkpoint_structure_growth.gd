extends RefCounted
## PERF E: count structure of independently detached N158 checkpoints.
## Never estimate serialized bytes or attribute N9 ownership from a generic tree.
## Called only at existing full parity boundaries, outside paid tick timing.
const MAX_NODES: int = 2000000
const MAX_DEPTH: int = 128
const MAX_WINDOW: int = 100

static func capture(tick: int, checkpoint: Variant) -> Dictionary:
    if tick < 1 or not (checkpoint is Dictionary):
        return {"accepted": false, "reason": "invalid_checkpoint"}
    var stack: Array = [{"value": checkpoint, "depth": 0}]
    var nodes: int = 0
    var dictionaries: int = 0
    var arrays: int = 0
    var leaves: int = 0
    var max_depth: int = 0
    while not stack.is_empty():
        var item: Dictionary = stack.pop_back()
        var value: Variant = item["value"]
        var depth: int = int(item["depth"])
        nodes += 1
        if nodes > MAX_NODES or depth > MAX_DEPTH:
            return {"accepted": false, "reason": "structure_bound_exceeded"}
        max_depth = maxi(max_depth, depth)
        if value is Dictionary:
            dictionaries += 1
            for key in value:
                if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT]:
                    return {"accepted": false, "reason": "unsupported_key"}
                stack.append({"value": value[key], "depth": depth + 1})
        elif value is Array:
            arrays += 1
            for child in value:
                stack.append({"value": child, "depth": depth + 1})
        elif typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT,
                TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3,
                TYPE_COLOR, TYPE_VECTOR2I, TYPE_VECTOR3I]:
            leaves += 1
        else:
            return {"accepted": false, "reason": "unsupported_variant"}
    return {"accepted": true, "tick": tick, "nodes": nodes,
        "dictionaries": dictionaries, "arrays": arrays, "leaves": leaves,
        "max_depth": max_depth, "measurement": "variant_nodes_not_bytes"}

static func pair(left: Dictionary, right: Dictionary, exact: Dictionary) -> Dictionary:
    if exact.get("equal", false) != true or not exact.get("difference", {}).is_empty():
        return {"accepted": false, "reason": "full_parity_required"}
    for row in [left, right]:
        if row.get("accepted", false) != true or row.get("measurement", "") != "variant_nodes_not_bytes":
            return {"accepted": false, "reason": "invalid_structure"}
        for key in ["tick", "nodes", "dictionaries", "arrays", "leaves", "max_depth"]:
            if typeof(row.get(key, null)) != TYPE_INT or int(row[key]) < 0:
                return {"accepted": false, "reason": "invalid_" + key}
        if int(row["nodes"]) != int(row["dictionaries"]) + int(row["arrays"]) + int(row["leaves"]):
            return {"accepted": false, "reason": "inconsistent_node_sum"}
    if int(left["tick"]) != int(right["tick"]):
        return {"accepted": false, "reason": "tick_mismatch"}
    for key in ["nodes", "dictionaries", "arrays", "leaves", "max_depth"]:
        if left[key] != right[key]:
            return {"accepted": false, "reason": "structural_parity_" + key}
    return {"accepted": true, "tick": left["tick"],
        "nodes": left["nodes"], "dictionaries": left["dictionaries"],
        "arrays": left["arrays"], "leaves": left["leaves"],
        "max_depth": left["max_depth"], "measurement": "variant_nodes_not_bytes"}

static func growth(early: Dictionary, late: Dictionary) -> Dictionary:
    for row in [early, late]:
        if row.get("accepted", false) != true or row.get("measurement", "") != "variant_nodes_not_bytes":
            return {"accepted": false, "reason": "invalid_boundary"}
        if typeof(row.get("tick", null)) != TYPE_INT or typeof(row.get("nodes", null)) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_boundary_types"}
    if int(late["tick"]) <= int(early["tick"]):
        return {"accepted": false, "reason": "unordered_boundaries"}
    var deltas: Dictionary = {}
    for key in ["nodes", "dictionaries", "arrays", "leaves"]:
        if typeof(early.get(key, null)) != TYPE_INT or typeof(late.get(key, null)) != TYPE_INT:
            return {"accepted": false, "reason": "invalid_" + key}
        deltas[key] = int(late[key]) - int(early[key])
    return {"accepted": true, "from_tick": early["tick"], "to_tick": late["tick"],
        "delta": deltas, "measurement": "variant_nodes_not_bytes",
        "performance_claim": false}
