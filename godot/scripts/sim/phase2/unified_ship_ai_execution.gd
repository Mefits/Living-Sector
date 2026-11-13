extends RefCounted
## P2 N84 execution + N146 command staging. N14 is the ONLY ship-motion
## physics; this adapter cannot grant cargo, dock spaces, credits or XP.
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")

static func _dispatch(action: Dictionary, _bb: Dictionary,
        world: Dictionary, graph: RefCounted, positions: Dictionary,
        ship_id: String, tick: int, scale: float) -> Dictionary:
    var kind: String = str(action.get("kind", ""))
    var ship: Dictionary = world["ships"][ship_id]
    var location: String = str(ship.get("location", ""))
    if kind == "Travel":
        var to: String = str(action.get("destination", ""))
        if to.is_empty() or not graph.has_location(to):
            return {"status": Bt.FAILURE, "reason": "invalid_native_bt_travel"}
        if location == to and (ship.get("transit", {}) as Dictionary).is_empty():
            return {"status": Bt.SUCCESS}
        if not (ship.get("transit", {}) as Dictionary).is_empty():
            return {"status": Bt.RUNNING, "reason": "physical_n14_transit_active"}
        var proposed: Dictionary = ShipPhase.depart(world, graph,
            positions, tick, scale, ship_id, to)
        if not proposed.get("ok", false):
            return {"status": Bt.RUNNING,
                "reason": str(proposed.get("reason", "n14_departure_not_ready"))}
        var receipt: Dictionary = proposed["ships"][ship_id]["transit"]
        if receipt.is_empty() or str(receipt.get("to", "")) != to:
            return {"status": Bt.FAILURE, "reason": "invalid_native_transit_preview"}
        var cmd: Dictionary = Commands.make_command("BeginTransit", {
            "ship": ship_id, "from": location, "to": to,
            "departure_tick": tick, "arrival_tick": int(receipt["arrival_tick"])
        })
        if cmd.is_empty():
            return {"status": Bt.FAILURE, "reason": "n146_invalid_transit_command"}
        return {"status": Bt.RUNNING, "commands": [cmd],
            "reason": "issued_n146_begin_transit"}
    if kind in ["Dock", "DockAtShipyard", "DockDwell", "Buy", "DeliverCargo",
            "SellAll", "Undock", "Refuel", "Refit", "DeliverPassengers",
            "EmbarkPassengers", "Rest"]:
        # N97/N21 paid dock, market inventory & settlement must be wired
        # before this leaf can run. Do not skip to the next leaf.
        return {"status": Bt.RUNNING, "reason": "awaiting_native_paid_" + kind}
    if kind == "Idle":
        return {"status": Bt.SUCCESS}
    return {"status": Bt.FAILURE, "reason": "unknown_n84_leaf_" + kind}

## All fleet commands are proposed in stable source ship-id order. Only
## BeginTransit is supported at present and checked against real N14
## physics. N146 never applies anything on its own.
static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, tick: int, scale: float) -> Dictionary:
    if graph == null or not (world.get("ships") is Dictionary) or tick < 1:
        return {"ok": false, "reason": "missing_single_world_ai_fleet"}
    var staged: Dictionary = world.duplicate(true)
    var cmd_buffer = Commands.new()
    if not cmd_buffer.begin_phase(tick, "ships"):
        return {"ok": false, "reason": "n146_phase_cannot_begin"}
    var records: Array = []
    var ids: Array = staged["ships"].keys()
    ids.sort()
    var changed: bool = false
    for ship_id in ids:
        var ship: Dictionary = staged["ships"][ship_id]
        var contract_id: String = str(ship.get("active_contract_id", ""))
        if contract_id.is_empty():
            continue
        var board: Dictionary = staged.get("contract_board", {})
        var contracts: Dictionary = board.get("contracts", {})
        var held: Dictionary = contracts.get(contract_id, {})
        if held.is_empty() or str(held.get("status", "")) not in ["accepted", "picked_up"] or str(held.get("fulfiller_id", "")) != str(ship_id):
            return {"ok": false, "reason": "n84_missing_actual_n104_obligation",
                "ship_id": str(ship_id)}
        var bt: Variant = ship.get("current_bt", null)
        if bt == null:
            # Legacy N153 checkpoint before N84 was attached. Do not
            # synthesize a tree or halt the whole simulation on restore.
            records.append({"ship_id": str(ship_id), "contract_id": contract_id,
                "leaf": "", "status": Bt.RUNNING,
                "reason": "legacy_n153_order_needs_n81_replan"})
            continue
        if not (bt is Dictionary) or not Bt.validate(bt):
            return {"ok": false, "reason": "n84_invalid_saved_plan",
                "ship_id": str(ship_id)}
        var current_leaf: String = Bt.current_action(bt)
        # One leaf tick per ship per tick; action may return Running for many
        # physical flight ticks without advancing its saved Sequence.index.
        var detail: Dictionary = {"reason": ""}
        var executor: Callable = func(action: Dictionary, bb: Dictionary) -> Dictionary:
            var result: Dictionary = _dispatch(action, bb, staged, graph,
                positions, str(ship_id), tick, scale)
            detail["reason"] = str(result.get("reason", ""))
            return result
        var next: Dictionary = Bt.tick(bt, executor, {})
        if not next.get("ok", false):
            return {"ok": false, "reason": "n84_tick_rejected",
                "ship_id": str(ship_id)}
        if next["status"] == Bt.FAILURE:
            # Fail closed: leave this original physical World untouched.
            return {"ok": false, "reason": "n84_leaf_failed_" + current_leaf,
                "ship_id": str(ship_id)}
        for command in next.get("commands", []):
            if not cmd_buffer.push(command):
                return {"ok": false, "reason": "n146_invalid_dispatch_command",
                    "ship_id": str(ship_id)}
            if str(command.get("kind", "")) != "BeginTransit" or str(command.get("ship", "")) != str(ship_id):
                return {"ok": false, "reason": "n146_command_not_yet_integrated",
                    "ship_id": str(ship_id)}
            var native_move: Dictionary = ShipPhase.depart(staged, graph,
                positions, tick, scale, str(ship_id), str(command["to"]))
            if not native_move.get("ok", false):
                return {"ok": false, "reason": "n14_authoritative_departure_rejected",
                    "ship_id": str(ship_id)}
            var actual: Dictionary = native_move["ships"][ship_id]["transit"]
            if int(actual.get("arrival_tick", -1)) != int(command["arrival_tick"]) or str(actual.get("from", "")) != str(command["from"]):
                return {"ok": false, "reason": "n146_n14_receipt_mismatch",
                    "ship_id": str(ship_id)}
            staged["ships"] = native_move["ships"]
            staged["ship_next_token"] = int(native_move["next_token"])
            ship = staged["ships"][ship_id]
        if next["tree"] != bt:
            changed = true
        ship["current_bt"] = next["tree"].duplicate(true)
        if not next.get("commands", []).is_empty():
            changed = true
        records.append({"ship_id": str(ship_id), "contract_id": contract_id,
            "leaf": current_leaf, "status": str(next["status"]),
            "reason": detail["reason"]})
    return {"ok": true, "changed": changed, "ships": staged["ships"],
        "next_token": int(staged.get("ship_next_token", 0)),
        "commands": cmd_buffer.drain(), "trace": records}
