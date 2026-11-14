extends RefCounted
## Frozen Rust ShipAction::Refuel / ShipAction::Mine. This proposes
## exclusive N90 -> N146 RequestShipTransaction only. Actual physical
## body resources, tank fuel and N9 credits are owned by N39 Apply.
const N90 = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const N146 = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _failed(why: String) -> Dictionary:
    return {"status": Bt.FAILURE, "reason": "n97_service_" + why}

static func propose(ship: Dictionary, action: Dictionary,
        tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1:
        return _failed("invalid_native_tick")
    var leaf: String = str(action.get("kind", ""))
    if leaf not in ["Refuel", "Mine"]:
        return _failed("unknown_original_service_leaf")
    var slot: Variant = ship.get("transaction", null)
    if not (slot is Dictionary) or not N90.valid_slot(slot):
        return _failed("missing_original_n90_transaction_slot")
    var kind: String = "refuel" if leaf == "Refuel" else "mine"
    var expected: Dictionary = {"kind": kind}
    if kind == "mine":
        expected["location"] = str(action.get("location", ""))
        expected["body_id"] = str(action.get("body_id", ""))
        expected["commodity"] = str(action.get("commodity", ""))
        expected["quantity"] = int(action.get("quantity", 0))
    if not slot["pending"].is_empty():
        var result: Dictionary = N90.poll(slot, expected)
        if not result.get("ok", false):
            return _failed("n90_poll_source_mismatch")
        ship["transaction"] = result["state"].duplicate(true)
        var settled: String = str(result.get("status", ""))
        if settled == N90.RUNNING:
            return {"status": Bt.RUNNING,
                "reason": "n90_await_original_n97_apply"}
        if settled == N90.FAILURE:
            return _failed("original_n97_negative_ack")
        if settled != N90.SUCCESS:
            return _failed("unknown_native_transaction_ack")
        if kind == "mine":
            return {"status": Bt.SUCCESS, "reason": "n97_real_ice_mined"}
        # Original Refuel loops for multiple 2-unit batches
        # until actual tank capacity, not instant full refill.
    if kind == "refuel":
        var fuel: Variant = ship.get("fuel", null)
        var cap: Variant = ship.get("fuel_capacity", null)
        if not (fuel is float or fuel is int) or not (
                cap is float or cap is int) or not is_finite(float(fuel)) or (
                not is_finite(float(cap)) or float(cap) <= 0.0):
            return _failed("invalid_original_fuel")
        if float(fuel) >= float(cap) - 0.001:
            return {"status": Bt.SUCCESS, "reason": "original_tank_full"}
        var location: String = str(ship.get("location", ""))
        if location.is_empty() or not ship.get("transit", {}).is_empty():
            return _failed("refuel_away_from_real_port")
        return _begin(ship, {"kind": kind, "location": location})
    # Rust Mine needs 3 game seconds x original tick_multiplier to
    # elapse on the SAME saved ShipEconomy.dock_dwell_start_tick.
    var mine_location: String = str(action.get("location", ""))
    var body_id: String = str(action.get("body_id", ""))
    var commodity: String = str(action.get("commodity", ""))
    var wanted: int = int(action.get("quantity", 0))
    if mine_location.is_empty() or body_id.is_empty() or commodity != "ice" or (
            mine_location != str(ship.get("location", "")) or
            not ship.get("transit", {}).is_empty() or
            not str(ship.get("docked_at", "")).is_empty()):
        ship["dock_dwell_start_tick"] = null
        return _failed("not_at_actual_mining_waypoint")
    var used: int = 0
    for amount in ship.get("cargo", {}).values():
        used += int(amount)
    var free: int = maxi(0, int(ship.get("cargo_capacity", 0)) - used)
    if free < 1 or wanted < 1:
        ship["dock_dwell_start_tick"] = null
        return _failed("original_hold_full_or_empty_mine_order")
    var start: Variant = ship.get("dock_dwell_start_tick", null)
    if start == null:
        ship["dock_dwell_start_tick"] = tick
        start = tick
    if typeof(start) != TYPE_INT or int(start) > tick or int(start) < 0:
        return _failed("invalid_original_mine_dwell_cursor")
    if tick - int(start) < 3 * multiplier:
        return {"status": Bt.RUNNING, "reason": "original_three_second_mining_shift"}
    ship["dock_dwell_start_tick"] = null
    return _begin(ship, {"kind": "mine", "location": mine_location,
        "body_id": body_id, "commodity": commodity,
        "quantity": mini(40, mini(wanted, free))})

static func _begin(ship: Dictionary, request: Dictionary) -> Dictionary:
    var slot: Dictionary = ship["transaction"]
    var started: Dictionary = N90.begin(slot, request)
    if not started.get("ok", false):
        return _failed("source_n90_exclusive_pending")
    var command: Dictionary = N146.make_command("RequestShipTransaction", {
        "ship": str(ship.get("id", "")),
        "request_id": int(started["request_id"]),
        "operation": "ship_service"})
    if command.is_empty():
        return _failed("original_n146_service_command_refused")
    ship["transaction"] = started["state"].duplicate(true)
    return {"status": Bt.RUNNING, "commands": [command],
        "reason": "n97_source_" + str(request["kind"]) + "_requested"}
