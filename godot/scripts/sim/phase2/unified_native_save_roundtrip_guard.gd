extends RefCounted
## N38/P2: verify the authoritative N39 economic frame survives JSON exactly
## BEFORE promoting a .pending save. A SHA256 over JSON cannot detect a
## lossy conversion that happens BEFORE hashing (notably i64 -> JSON float).
## This only inspects values; never rewrites World, N9, N104 or event history.
const MAX_JSON_EXACT_INT: int = 9007199254740991
const MAX_NESTED_DEPTH: int = 96

## The P1-only legacy checkpoint has no native_production. P2 must preserve
## exactly one N39 World + Ledger object: all market stocks, ship holds,
## household/faction accounts, escrow, contracts, work and strategic receipts.
static func verify_authoritative_frame(original: Dictionary,
        decoded: Dictionary) -> Dictionary:
    var before_has: bool = original.has("native_production")
    var after_has: bool = decoded.has("native_production")
    if before_has != after_has:
        return {"ok": false, "reason": "native_frame_presence_changed"}
    if not before_has:
        return {"ok": true, "scope": "legacy_p1_without_native_frame"}
    if not (original["native_production"] is Dictionary) or not (
            decoded["native_production"] is Dictionary):
        return {"ok": false, "reason": "invalid_native_frame_shape"}
    var before: Dictionary = original["native_production"]
    var after: Dictionary = decoded["native_production"]
    for key in ["version", "tick", "world", "ledger"]:
        if not before.has(key) or not after.has(key):
            return {"ok": false, "reason": "missing_native_frame_" + key}
    if not (before["world"] is Dictionary and after["world"] is Dictionary and
            before["ledger"] is Dictionary and after["ledger"] is Dictionary):
        return {"ok": false, "reason": "invalid_world_or_ledger_shape"}
    var difference: String = _difference(before, after, "native_production", 0)
    if not difference.is_empty():
        return {"ok": false, "reason": "lossy_native_json_roundtrip",
            "field": difference}
    return {"ok": true, "scope": "full_native_world_n9_contracts_receipts"}

## Values are compared by their original type, not JSON.stringify output.
## JSON may decode an integral token as float; accept only an EXACT integral
## conversion, never float rounding of an original 64-bit Rust credit.
static func _difference(original: Variant, decoded: Variant,
        path: String, depth: int) -> String:
    if depth > MAX_NESTED_DEPTH:
        return path + ":over_nested_limit"
    var kind: int = typeof(original)
    var decoded_kind: int = typeof(decoded)
    if kind == TYPE_DICTIONARY:
        if decoded_kind != TYPE_DICTIONARY:
            return path + ":dictionary_type_changed"
        var before: Dictionary = original
        var after: Dictionary = decoded
        if before.size() != after.size():
            return path + ":dictionary_cardinality_changed"
        var keys: Array = before.keys()
        keys.sort_custom(func(a: Variant, b: Variant) -> bool:
            return str(a) < str(b))
        for key in keys:
            # JSON object keys are strings. Numeric Dictionary keys would
            # change identity on restore even when their values match.
            if not (key is String) or not after.has(key):
                return path + ":dictionary_key_changed:" + str(key)
            var difference: String = _difference(before[key], after[key],
                path + "/" + str(key), depth + 1)
            if not difference.is_empty():
                return difference
        return ""
    if kind == TYPE_ARRAY:
        if decoded_kind != TYPE_ARRAY:
            return path + ":array_type_changed"
        var before_items: Array = original
        var after_items: Array = decoded
        if before_items.size() != after_items.size():
            return path + ":array_length_changed"
        for index in range(before_items.size()):
            var difference: String = _difference(before_items[index],
                after_items[index], path + "/" + str(index), depth + 1)
            if not difference.is_empty():
                return difference
        return ""
    if kind == TYPE_INT:
        if decoded_kind == TYPE_INT:
            return "" if int(original) == int(decoded) else path + ":integer_changed"
        if decoded_kind != TYPE_FLOAT:
            return path + ":integer_type_changed"
        var integer: int = int(original)
        var decimal: float = float(decoded)
        if integer > MAX_JSON_EXACT_INT or integer < -MAX_JSON_EXACT_INT:
            return path + ":i64_exceeds_exact_json_float_range"
        if not is_finite(decimal) or decimal != float(integer) or                 decimal != floorf(decimal):
            return path + ":integer_rounded_by_json"
        return ""
    if kind == TYPE_FLOAT:
        if decoded_kind not in [TYPE_INT, TYPE_FLOAT]:
            return path + ":float_type_changed"
        var before_float: float = float(original)
        var after_float: float = float(decoded)
        if not is_finite(before_float) or not is_finite(after_float) or (
                before_float != after_float):
            return path + ":float_changed_by_json"
        return ""
    if kind != decoded_kind:
        return path + ":value_type_changed"
    if kind not in [TYPE_NIL, TYPE_BOOL, TYPE_STRING]:
        # Unexpected Godot objects must not silently become strings/null.
        return path + ":not_json_data"
    return "" if original == decoded else path + ":value_changed"
