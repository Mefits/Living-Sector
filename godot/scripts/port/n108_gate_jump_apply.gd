extends RefCounted
## N108: frozen sim_server/src/engine/apply.rs::apply_gate_jump, and
## sim_core/agents/facility/components.rs::gate_transit_fee.
##
## Pure exclusive Apply: returns a detached complete world. All authority
## (gate IDs, first-at-location order, paired orbital position) comes
## from the frozen Rust world snapshot, never inferred from map pixels.
##
## In Rust gate BT optimistically changes local ShipPosition before Apply;
## N108 commits location only after charged and paired destination validated.
## This deliberately FAIL-CLOSED on missing link/position/overflow, fixing
## a source-edge drift bug; enumerate deviation in N108 handoff.
##
## world = {
##  ships: {ship_id:{id,location,docked_at,credits,cargo,position,memory}},
##  facilities:{id:{id,facility_type,location,credits,gate_link?,position?,system_name?}},
##  facilities_at_location:{location:[id...]},
## }
## facility.position MUST come from Rust facility_offset_position(body,id);
## snapshots without authoritative orbit coordinate are NOT accepted.
const RECENT_SYSTEMS_CAP: int = 5
const MAX_I64: int = 9223372036854775807
const MAX_U32: int = 4294967295

static func apply(world: Dictionary, ship_id: String,
        source_location: String, destination_location: String) -> Dictionary:
    if ship_id.is_empty() or source_location.is_empty() or destination_location.is_empty():
        return _reject("invalid_gate_request")
    if (not (world.get("ships", null) is Dictionary)
            or not (world.get("facilities", null) is Dictionary)
            or not (world.get("facilities_at_location", null) is Dictionary)):
        return _reject("missing_gate_world")
    var source_ship: Variant = world["ships"].get(ship_id, null)
    if not (source_ship is Dictionary):
        return _reject("missing_ship")
    if str(source_ship.get("id", "")) != ship_id             or str(source_ship.get("location", "")) != source_location:
        return _reject("ship_not_at_gate")
    var source_ids: Variant = world["facilities_at_location"].get(source_location, null)
    if not (source_ids is Array):
        return _reject("unknown_source_gate")
    var source_gate_id: String = ""
    for facility_id in source_ids:
        var station: Variant = world["facilities"].get(str(facility_id), null)
        if station is Dictionary and station.get("gate_link", null) is Dictionary:
            source_gate_id = str(facility_id)
            break
    if source_gate_id.is_empty():
        return _reject("unknown_source_gate")
    var gate: Dictionary = world["facilities"][source_gate_id]
    var link: Dictionary = gate["gate_link"]
    var paired_id: String = str(link.get("paired_gate_id", ""))
    if paired_id.is_empty():
        return _reject("missing_paired_gate")
    var dest_value: Variant = world["facilities"].get(paired_id, null)
    if not (dest_value is Dictionary):
        return _reject("missing_paired_gate")
    var dest: Dictionary = dest_value
    if str(dest.get("location", "")) != destination_location             or not (dest.get("gate_link", null) is Dictionary):
        return _reject("unlinked_gate_destination")
    if str(dest["gate_link"].get("paired_gate_id", "")) != source_gate_id:
        return _reject("nonreciprocal_gate_link")
    var new_pos: Variant = dest.get("position", null)
    if not _finite_position(new_pos):
        return _reject("missing_authoritative_orbit_position")
    var flat: Variant = link.get("fee_flat", null)
    var by_cargo: Variant = link.get("fee_per_cargo_unit", null)
    if typeof(flat) != TYPE_INT or typeof(by_cargo) != TYPE_INT:
        return _reject("invalid_gate_fee")
    var cargo: Variant = source_ship.get("cargo", null)
    if not (cargo is Dictionary):
        return _reject("missing_ship_cargo")
    var used: int = 0
    for commodity in cargo:
        var count: Variant = cargo[commodity]
        if typeof(count) != TYPE_INT or int(count) < 0 or int(count) > MAX_U32                 or used > MAX_U32 - int(count):
            return _reject("invalid_cargo_quantity")
        used += int(count)
    # Frozen Rust GateLink gate_transit_fee = flat + per_cargo*used.
    # Rust i64 overflow would panic in debug; reject instead of wrap/mint.
    if int(flat) < 0 or int(by_cargo) < 0:
        return _reject("negative_gate_fee")
    if used > 0 and int(by_cargo) > (MAX_I64 - int(flat)) / used:
        return _reject("fee_overflow")
    var fee: int = int(flat) + int(by_cargo) * used
    var ship_credits: Variant = source_ship.get("credits", null)
    var operator_credits: Variant = gate.get("credits", null)
    if typeof(ship_credits) != TYPE_INT or typeof(operator_credits) != TYPE_INT             or int(ship_credits) < fee or int(operator_credits) < 0:
        return _reject("insufficient_gate_funds")
    if int(operator_credits) > MAX_I64 - fee:
        return _reject("gate_credit_overflow")
    var staged: Dictionary = world.duplicate(true)
    var ship: Dictionary = staged["ships"][ship_id]
    var gate_owner: Dictionary = staged["facilities"][source_gate_id]
    ship["credits"] = int(ship_credits) - fee
    gate_owner["credits"] = int(operator_credits) + fee
    gate_owner["dirty"] = true
    ship["location"] = destination_location
    ship["docked_at"] = null
    ship["position"] = new_pos.duplicate(true)
    var dst_system: String = str(dest.get("system_name", ""))
    if not dst_system.is_empty() and ship.get("memory", null) is Dictionary:
        var memory: Dictionary = ship["memory"]
        if not (memory.get("recent_systems", null) is Array):
            return _reject("invalid_recent_systems")
        var systems: Array = memory["recent_systems"]
        if systems.is_empty() or str(systems.back()) != dst_system:
            systems.append(dst_system)
            while systems.size() > RECENT_SYSTEMS_CAP:
                systems.pop_front()
    return {
        "ok": true, "world": staged, "fee": fee,
        "events": [{
            "kind": "ship_gate_jumped", "id": ship_id,
            "src_gate": source_location,
            "dest_gate": destination_location, "fee": fee
        }]
    }

static func _finite_position(value: Variant) -> bool:
    if not (value is Array) or value.size() != 2:
        return false
    for coordinate in value:
        if not (coordinate is int or coordinate is float):
            return false
        if not is_finite(float(coordinate)):
            return false
    return true

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "events": []}
