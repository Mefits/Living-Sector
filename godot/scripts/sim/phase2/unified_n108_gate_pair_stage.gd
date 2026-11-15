extends RefCounted
## Explicit admin-style GateLink assignment, not a new technology,
## faction AI choice, station production recipe or auto-pair policy.
## Frozen Rust spawner loads paired_gate_id from real facilities; we
## assign that same canonical component only after BOTH gate facilities
## exist in the ONE N39 World, with the same 200/2/3 Rust defaults.
const RustOrbit = preload("res://scripts/sim/phase2/unified_n108_native_facility_orbit.gd")
const DEFAULT_FEE_FLAT: int = 200
const DEFAULT_FEE_PER_CARGO: int = 2
const DEFAULT_THROUGHPUT: int = 3

static func reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": "n108_pair_" + reason}

static func _position(pos: Variant) -> bool:
    if pos is Dictionary:
        return (pos.get("x") is int or pos.get("x") is float) and (
            pos.get("y") is int or pos.get("y") is float) and (
            is_finite(float(pos["x"])) and is_finite(float(pos["y"])))
    if pos is Array and pos.size() == 2:
        return (pos[0] is int or pos[0] is float) and (
            pos[1] is int or pos[1] is float) and (
            is_finite(float(pos[0])) and is_finite(float(pos[1])))
    return false

static func stage(world: Dictionary, resolver: RefCounted,
        gate_a: String, gate_b: String, tick: int) -> Dictionary:
    if tick < 0 or gate_a.is_empty() or gate_b.is_empty() or gate_a == gate_b:
        return reject("invalid_explicit_pair")
    if resolver == null or not resolver.has_method("system_for_body") or (
            not (world.get("facilities") is Dictionary)) or not (
            world["facilities"].has(gate_a) and world["facilities"].has(gate_b)):
        return reject("actual_source_gates_missing")
    var first: Dictionary = world["facilities"][gate_a]
    var second: Dictionary = world["facilities"][gate_b]
    if str(first.get("type", "")) != "gate" or str(second.get("type", "")) != "gate" or (
            bool(first.get("abandoned", false)) or bool(second.get("abandoned", false))):
        return reject("not_two_active_gate_facilities")
    if first.has("gate_link") or second.has("gate_link"):
        return reject("source_gate_already_paired")
    for gate in [first, second]:
        if str(gate.get("body_id", "")).is_empty() or not world.get(
                "bodies", {}).has(str(gate["body_id"])) or not _position(
                gate.get("position", null)):
            return reject("gate_has_no_authoritative_built_position")
    var system_a: String = resolver.system_for_body(str(first["body_id"]))
    var system_b: String = resolver.system_for_body(str(second["body_id"]))
    if system_a.is_empty() or system_b.is_empty() or system_a == system_b or (
            str(first.get("location", "")) == str(second.get("location", ""))):
        return reject("gate_pair_not_in_distinct_real_star_systems")
    # Signed source pair order makes receipts independent of caller order.
    var names: Array = [gate_a, gate_b]
    names.sort()
    var pair_id: String = "n108:pair:" + str(names[0]) + ":" + str(names[1])
    if not (world.get("native_gate_pair_receipts", {}) is Dictionary) or (
            world.get("native_gate_pair_receipts", {}).has(pair_id)):
        return reject("original_gate_pair_already_registered")
    var staged: Dictionary = world.duplicate(true)
    staged["facilities"][gate_a]["gate_link"] = {
        "paired_gate_id": gate_b,
        "fee_flat": DEFAULT_FEE_FLAT,
        "fee_per_cargo_unit": DEFAULT_FEE_PER_CARGO,
        "throughput_cap": DEFAULT_THROUGHPUT}
    staged["facilities"][gate_b]["gate_link"] = {
        "paired_gate_id": gate_a,
        "fee_flat": DEFAULT_FEE_FLAT,
        "fee_per_cargo_unit": DEFAULT_FEE_PER_CARGO,
        "throughput_cap": DEFAULT_THROUGHPUT}
    staged["facilities"][gate_a]["dirty"] = true
    staged["facilities"][gate_b]["dirty"] = true
    if not staged.has("native_gate_pair_receipts"):
        staged["native_gate_pair_receipts"] = {}
    var receipt: Dictionary = {
        "operation_id": pair_id,
        "kind": "native_n108_explicit_gate_pair",
        "source": "explicit_native_admin",
        "tick": tick, "a": str(names[0]), "b": str(names[1]),
        "system_a": system_a if gate_a == names[0] else system_b,
        "system_b": system_b if gate_b == names[1] else system_a,
        "fee_flat": DEFAULT_FEE_FLAT,
        "fee_per_cargo_unit": DEFAULT_FEE_PER_CARGO,
        "throughput_cap": DEFAULT_THROUGHPUT}
    staged["native_gate_pair_receipts"][pair_id] = receipt.duplicate(true)
    return {"ok": true, "changed": true,
        "world": staged, "receipt": receipt, "pair_id": pair_id,
        "kind": "native_n108_explicit_gate_pair"}
