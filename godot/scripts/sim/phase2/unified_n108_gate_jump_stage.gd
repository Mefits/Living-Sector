extends RefCounted
## Frozen Rust engine/apply.rs::apply_gate_jump, but source-hardened:
## the ship is moved ONLY after a real paired GateLink and a complete
## original destination facility position are proved. Never infer an
## extra edge from a visual route or synthesize an orbital position.
## Pure stage: the one N39 World and N9 remain the only authorities.
const SourceGate = preload("res://scripts/port/n108_gate_jump_apply.gd")
const N9 = preload("res://scripts/sim/economy/credit_ledger.gd")

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": "n108_gate_" + reason}

static func _original_position(fac: Dictionary) -> Array:
    # Only a persisted authoritative source position (e.g. original
    # N154 orbit materialization) is accepted. Rust's actual gate
    # placement uses DefaultHasher on FACILITY ID, not N43's distinct
    # location FNV orbit hash. Never silently substitute the latter.
    var pos: Variant = fac.get("position", null)
    if pos is Dictionary:
        if (pos.get("x") is float or pos.get("x") is int) and (
                pos.get("y") is float or pos.get("y") is int):
            pos = [pos["x"], pos["y"]]
    if not (pos is Array) or pos.size() != 2:
        return []
    if not (pos[0] is float or pos[0] is int) or not (
            pos[1] is float or pos[1] is int) or not is_finite(
            float(pos[0])) or not is_finite(float(pos[1])):
        return []
    return [float(pos[0]), float(pos[1])]

static func _real_gate(world: Dictionary, location: String) -> Dictionary:
    # The real Rust facility_by_id / facilities_at_location query may
    # find multiple entities. Without their original ECS insertion
    # ordering, an ambiguous gate must never send fees to an arbitrary
    # one. Single source-linked gate at this location is unambiguous.
    var candidates: Array = []
    for fid in world.get("facilities", {}):
        var fac: Dictionary = world["facilities"][fid]
        if str(fac.get("location", "")) == location and str(
                fac.get("type", "")) == "gate" and fac.get(
                "gate_link", null) is Dictionary:
            candidates.append(str(fid))
    if candidates.size() != 1:
        return _bad("missing_or_ambiguous_source_gate")
    var chosen: String = str(candidates[0])
    return {"ok": true, "id": chosen,
        "facility": world["facilities"][chosen]}

static func preflight(world: Dictionary, resolver: RefCounted,
        ship_id: String, source: String, destination: String) -> Dictionary:
    if ship_id.is_empty() or source.is_empty() or destination.is_empty() or (
            source == destination or resolver == null or not resolver.has_method(
            "system_for_body")):
        return _bad("invalid_source_command")
    if not (world.get("ships") is Dictionary) or not (
            world["ships"].has(ship_id)):
        return _bad("missing_live_ship")
    var ship: Dictionary = world["ships"][ship_id]
    if str(ship.get("location", "")) != source or not (
            ship.get("transit", {}) is Dictionary) or not ship["transit"].is_empty():
        return _bad("ship_not_at_real_source_gate")
    if not str(ship.get("docked_at", "")).is_empty():
        return _bad("ship_must_release_source_n21_dock")
    if not (world.get("facilities") is Dictionary):
        return _bad("missing_one_facility_registry")
    var start: Dictionary = _real_gate(world, source)
    if not start.get("ok", false):
        return start
    var source_id: String = str(start["id"])
    var source_fac: Dictionary = start["facility"]
    var link: Dictionary = source_fac["gate_link"]
    var dest_id: String = str(link.get("paired_gate_id", ""))
    if dest_id.is_empty() or dest_id == source_id or not world[
            "facilities"].has(dest_id):
        return _bad("original_paired_gate_not_present")
    var dst: Dictionary = world["facilities"][dest_id]
    if str(dst.get("type", "")) != "gate" or str(
            dst.get("location", "")) != destination or not (
            dst.get("gate_link", null) is Dictionary) or str(
            dst["gate_link"].get("paired_gate_id", "")) != source_id:
        return _bad("source_gate_pair_not_reciprocal")
    if bool(source_fac.get("abandoned", false)) or bool(dst.get(
            "abandoned", false)):
        return _bad("real_gate_abandoned")
    for gate in [source_fac, dst]:
        if not world.get("bodies", {}).has(str(gate.get("body_id", ""))):
            return _bad("gate_has_no_actual_body")
    var source_system: String = resolver.system_for_body(str(
        source_fac["body_id"]))
    var destination_system: String = resolver.system_for_body(str(
        dst["body_id"]))
    if source_system.is_empty() or destination_system.is_empty() or (
            str(ship.get("system_id", "")) != source_system):
        return _bad("wrong_actual_ship_system")
    var pos: Array = _original_position(dst)
    if pos.is_empty():
        return _bad("missing_original_paired_gate_orbit_position")
    var fee_flat: Variant = link.get("fee_flat", null)
    var fee_cargo: Variant = link.get("fee_per_cargo_unit", null)
    if typeof(fee_flat) != TYPE_INT or typeof(fee_cargo) != TYPE_INT or (
            int(fee_flat) < 0 or int(fee_cargo) < 0):
        return _bad("invalid_original_gate_price")
    var cargo_used: int = 0
    for commodity in ship.get("cargo", {}):
        var quantity: Variant = ship["cargo"][commodity]
        if typeof(quantity) != TYPE_INT or int(quantity) < 0 or (
                int(quantity) > 4294967295) or (
                cargo_used > 4294967295 - int(quantity)):
            return _bad("invalid_actual_cargo_load")
        cargo_used += int(quantity)
    var maximum: int = 9223372036854775807
    if cargo_used > 0 and int(fee_cargo) > (maximum - int(
            fee_flat)) / cargo_used:
        return _bad("source_i64_gate_fee_overflow")
    var total: int = int(fee_flat) + int(fee_cargo) * cargo_used
    if int(ship.get("credits", -1)) < total:
        return _bad("actual_ship_cannot_pay_gate")
    if int(source_fac.get("credits", -1)) < 0 or (
            int(source_fac["credits"]) > maximum - total):
        return _bad("gate_operator_wallet_would_overflow")
    return {"ok": true, "source_gate_id": source_id,
        "destination_gate_id": dest_id, "source": source,
        "destination": destination, "source_system": source_system,
        "destination_system": destination_system,
        "position": pos, "fee": total, "cargo_used": cargo_used}

static func stage(world: Dictionary, ledger_snapshot: Dictionary,
        resolver: RefCounted, ship_id: String, source: String,
        destination: String, tick: int) -> Dictionary:
    if tick < 1:
        return _bad("invalid_real_n158_ships_tick")
    var checked: Dictionary = preflight(world, resolver, ship_id,
        source, destination)
    if not checked.get("ok", false):
        return checked
    var source_id: String = str(checked["source_gate_id"])
    var dest_id: String = str(checked["destination_gate_id"])
    var receipt_id: String = "n108:gate:" + ship_id + ":" + str(tick)
    if not (world.get("native_gate_jump_receipts", {}) is Dictionary) or (
            world.get("native_gate_jump_receipts", {}).has(receipt_id)):
        return _bad("duplicate_or_corrupt_native_gate_receipt")
    # Authoritative components projected for ORIGINAL N108 P1 apply.
    # Source facility IDs & links never come from a search over visuals.
    var src: Dictionary = world["facilities"][source_id].duplicate(true)
    var dst: Dictionary = world["facilities"][dest_id].duplicate(true)
    src["id"] = source_id
    dst["id"] = dest_id
    src["position"] = _original_position(src)
    dst["position"] = checked["position"].duplicate(true)
    src["system_name"] = str(checked["source_system"])
    dst["system_name"] = str(checked["destination_system"])
    var physical: Dictionary = {"ships": {}, "facilities": {},
        "facilities_at_location": {}}
    physical["ships"][ship_id] = world["ships"][ship_id].duplicate(true)
    physical["facilities"][source_id] = src
    physical["facilities"][dest_id] = dst
    physical["facilities_at_location"][source] = [source_id]
    physical["facilities_at_location"][destination] = [dest_id]
    var source_result: Dictionary = SourceGate.apply(physical, ship_id,
        source, destination)
    if not source_result.get("ok", false):
        return _bad("original_p1_apply_" + str(source_result.get(
            "reason", "refused")))
    var source_ship: Dictionary = world["ships"][ship_id]
    var after: Dictionary = source_result["world"]["ships"][ship_id]
    var src_fac: Dictionary = source_result["world"]["facilities"][source_id]
    var fee: int = int(checked["fee"])
    if int(source_result.get("fee", -1)) != fee or int(after.get(
            "credits", -1)) != int(source_ship["credits"]) - fee or (
            int(src_fac.get("credits", -1)) != int(world["facilities"][
                source_id]["credits"]) + fee) or str(after.get(
            "location", "")) != destination or after.get(
            "position", null) != checked["position"]:
        return _bad("p1_gate_fee_or_physical_position_disagrees")
    var paid_world: Dictionary = world.duplicate(true)
    var ship: Dictionary = paid_world["ships"][ship_id]
    ship["credits"] = int(after["credits"])
    ship["location"] = destination
    ship["system_id"] = str(checked["destination_system"])
    ship["position"] = checked["position"].duplicate(true)
    ship["docked_at"] = ""
    # Source N108 appends destination to recent_systems and never
    # creates a visit or a fake flight. Preserve the actual result.
    if after.get("memory", null) is Dictionary:
        ship["memory"] = after["memory"].duplicate(true)
    paid_world["facilities"][source_id]["credits"] = int(
        src_fac["credits"])
    paid_world["facilities"][source_id]["dirty"] = true
    var money: Dictionary = ledger_snapshot.duplicate(true)
    var financial_id: String = ""
    if fee > 0:
        var bank := N9.new()
        if not bank.restore(ledger_snapshot):
            return _bad("original_bank_snapshot_invalid")
        financial_id = receipt_id
        var trans: Dictionary = bank.transfer(receipt_id, "ship:" +
            ship_id, "facility:" + source_id, fee, tick,
            "native_n108_gate_jump")
        if not trans.get("ok", false):
            return _bad("paid_gate_" + str(trans.get("reason", "unfunded")))
        if bank.balance("ship:" + ship_id) != int(ship["credits"]) or (
                bank.balance("facility:" + source_id) != int(
                paid_world["facilities"][source_id]["credits"])):
            return _bad("n9_original_gate_wallet_mismatch")
        money = bank.snapshot()
    var event: Dictionary = {
        "operation_id": receipt_id, "tick": tick, "kind": "native_n108_gate_jump",
        "ship_id": ship_id, "source_gate_id": source_id,
        "destination_gate_id": dest_id, "source": source,
        "destination": destination, "source_system": checked["source_system"],
        "destination_system": checked["destination_system"],
        "fee": fee, "cargo_used": int(checked["cargo_used"]),
        "financial_receipt": financial_id, "position": checked[
            "position"].duplicate(true)}
    if not paid_world.has("native_gate_jump_receipts"):
        paid_world["native_gate_jump_receipts"] = {}
    paid_world["native_gate_jump_receipts"][receipt_id] = event.duplicate(true)
    return {"ok": true, "status": "applied", "world": paid_world,
        "ledger_snapshot": money, "receipt": event, "tick": tick,
        "ship_id": ship_id, "source": source,
        "destination": destination, "fee": fee}
