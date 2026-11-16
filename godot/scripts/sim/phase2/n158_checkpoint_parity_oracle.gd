extends RefCounted
## PERF E: exact detached checkpoint comparator for direct N158 vs owner adapter.
## Inputs must be independently captured, completed-tick snapshots. This module
## never accesses World, runs ticks, or normalizes away BT/RNG/receipt differences.
const MAX_DEPTH: int = 128

static func compare(left: Variant, right: Variant) -> Dictionary:
    var mismatch: Dictionary = _first_difference(left, right, "$", 0)
    return {"equal": mismatch.is_empty(), "difference": mismatch}

static func _first_difference(a: Variant, b: Variant, path: String, depth: int) -> Dictionary:
    if depth > MAX_DEPTH:
        return {"path": path, "reason": "depth_limit"}
    if typeof(a) != typeof(b):
        return {"path": path, "reason": "type_mismatch", "left_type": typeof(a), "right_type": typeof(b)}
    match typeof(a):
        TYPE_DICTIONARY:
            if a.size() != b.size():
                return {"path": path, "reason": "dictionary_size", "left": a.size(), "right": b.size()}
            var keys: Array = a.keys()
            keys.sort_custom(func(x, y): return str(x) < str(y))
            for key in keys:
                if not b.has(key):
                    return {"path": path, "reason": "missing_key", "key": str(key)}
                var diff: Dictionary = _first_difference(a[key], b[key], path + "[" + str(key) + "]", depth + 1)
                if not diff.is_empty():
                    return diff
        TYPE_ARRAY:
            if a.size() != b.size():
                return {"path": path, "reason": "array_size", "left": a.size(), "right": b.size()}
            for i in range(a.size()):
                var diff: Dictionary = _first_difference(a[i], b[i], path + "[" + str(i) + "]", depth + 1)
                if not diff.is_empty():
                    return diff
        TYPE_OBJECT:
            return {"path": path, "reason": "live_object_forbidden"}
        _:
            if a != b:
                return {"path": path, "reason": "value_mismatch"}
    return {}
