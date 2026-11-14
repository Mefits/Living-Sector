extends SceneTree
## N38 native IEEE-754 precision codec, hashed JSON envelope and old-v1
## compatibility. This is persistence-only, not a synthetic gameplay test.
const Save = preload("res://scripts/sim/save_state.gd")
const NativeFrame = preload("res://scripts/sim/phase2/unified_native_save_roundtrip_guard.gd")

func _initialize() -> void:
    var native: Dictionary = {
        "version": 1, "tick": 360,
        "world": {
            "markets": {"alpha-station": {
                "supply": {"fuel": 0.1 + 0.2, "metals": 94.5},
                "history": {"trend_samples": [{"tick": 16,
                    "supply": {"fuel": 0.1 + 0.2}}]}}},
            "ships": {"source-ship": {"cargo": {"fuel": 0.1 + 0.2}}},
            "faction_treasuries": {"faction": 2743001}},
        "ledger": {"version": 1,
            "balances": {"faction/faction": 2743001}, "receipts": {}}}
    # Original native N81 may carry a typed StringName key in a BT
    # action; JSON alone loses that identity. The authenticated exact
    # dictionary token must keep it across disk serialization.
    var original_bt_action: Dictionary = {"kind": "DeliverCargo"}
    original_bt_action[&"contract_id"] = "source-paid-contract"
    native["world"]["ships"]["source-ship"]["current_bt"] = {
        "kind": "action", "action": original_bt_action}
    var source: Dictionary = {"format": "living-sector-godot",
        "tick": 360, "native_production": native,
        "orbital_angles": {"source_orbit": 0.1 + 0.2}}
    var envelope: Dictionary = Save._wrap(source)
    if not (envelope.get("payload") is Dictionary):
        _fail("N38 exact native envelope not written")
        return
    var encoded_fuel: Variant = envelope["payload"]["native_production"][
        "world"]["markets"]["alpha-station"]["supply"]["fuel"]
    if not (encoded_fuel is Dictionary) or not encoded_fuel.has(
            Save.NATIVE_F64_TAG):
        _fail("N38 native float was serialized as lossy JSON number")
        return
    var transport: Variant = JSON.parse_string(JSON.stringify(
        envelope, "\t", true, true))
    if not (transport is Dictionary):
        _fail("N38 JSON transport unreadable")
        return
    var restored: Dictionary = Save._unwrap(transport)
    if restored.is_empty() or not (restored.get("native_production") is Dictionary):
        _fail("N38 exact native envelope integrity or codec rejected")
        return
    var source_fuel: float = native["world"]["markets"][
        "alpha-station"]["supply"]["fuel"]
    var decoded_fuel: Variant = restored["native_production"][
        "world"]["markets"]["alpha-station"]["supply"]["fuel"]
    # Native N38 authoritatively allows exactly representable JSON int
    # tokens to reload as TYPE_FLOAT, then normalizes only those integer
    # fields before strict World validation. Raw Dictionary equality is
    # incorrectly stricter than real N38 (1 != 1.0 by Variant type).
    # Its existing frame guard verifies EVERY actual native float and
    # every money/stock/cargo/contract value without a single ULP loss.
    var native_guard: Dictionary = NativeFrame.verify_authoritative_frame(
        source, restored)
    var restored_bt_action: Variant = restored["native_production"][
        "world"]["ships"]["source-ship"]["current_bt"]["action"]
    var original_key_type: int = typeof(original_bt_action.keys()[1])
    var restored_key_type: int = TYPE_NIL
    if restored_bt_action is Dictionary:
        for key in restored_bt_action:
            if str(key) == "contract_id":
                restored_key_type = typeof(key)
                break
    if not (restored_bt_action is Dictionary) or (
            not restored_bt_action.has(&"contract_id")) or (
            restored_key_type != TYPE_STRING_NAME):
        _fail("N38 lost typed native BT paid contract_id key; original=" +
            str(original_key_type) + " restored=" + str(restored_key_type))
        return
    var orbit_original: float = source["orbital_angles"]["source_orbit"]
    var orbit_restored: Variant = restored.get("orbital_angles", {}).get(
        "source_orbit", null)
    if typeof(orbit_restored) != TYPE_FLOAT or orbit_restored != orbit_original:
        _fail("P1 orbital f64 changed across the same N38 hashed JSON envelope")
        return
    if typeof(decoded_fuel) != TYPE_FLOAT or decoded_fuel != source_fuel or (
            not native_guard.get("ok", false)):
        _fail("N38 exact native frame rejected; " + str(native_guard) +
            " source_fuel=" + str(source_fuel) +
            " decoded_fuel=" + str(decoded_fuel))
        return
    var altered: Dictionary = transport.duplicate(true)
    altered["payload"]["native_production"]["world"]["markets"][
        "alpha-station"]["supply"]["fuel"][Save.NATIVE_F64_TAG] = "tampered"
    if not Save._unwrap(altered).is_empty():
        _fail("N38 SHA did not protect native exact-float payload")
        return
    # Existing legacy v1 JSON envelopes use original numbers without a
    # special native precision tag. They must continue to be accepted.
    var old_payload: Dictionary = source.duplicate(true)
    var old: Dictionary = {
        "envelope_format": Save.ENVELOPE_FORMAT,
        "envelope_version": Save.ENVELOPE_VERSION,
        "payload_sha256": Save._canonical(old_payload).sha256_text(),
        "payload": old_payload}
    if Save._unwrap(old).is_empty():
        _fail("N38 old JSON v1 checkpoint no longer readable")
        return
    print("P2_N38_NATIVE_F64_EXACT_JSON_ENVELOPE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N38_NATIVE_F64_ENVELOPE_FAIL: " + reason)
    quit(1)
