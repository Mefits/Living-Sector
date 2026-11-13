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
    var contract_id: String = str(ship.get("active_contract_id", ""))
    var contracts: Dictionary = world.get("contract_board", {}).get("contracts", {})
    var c: Dictionary = contracts.get(contract_id, {})
    var stage: String = str(c.get("status", ""))
    var at: String = str(c.get("source_location", "")) if stage == "accepted" else str(c.get("destination_location", ""))
    if kind == "Dock":
        if stage not in ["accepted", "picked_up"] or location != at:
            return {"status": Bt.RUNNING, "reason": "n21_contract_location_not_ready"}
        var facility: String = str(world.get("markets", {}).get(at, {}).get("owner", ""))
        var existing_dock: String = str(ship.get("docked_at", ""))
        if not existing_dock.is_empty():
            if existing_dock == facility:
                return {"status": Bt.SUCCESS}
            # A restored ship may be docked at another station in the same
            # location. Release the physical N21 slot before retrying the
            # exact contract warehouse; never stall the entire world tick.
            var release_wrong: Dictionary = Commands.make_command("ReleaseDock", {
                "ship": ship_id, "facility_location": location,
                "contract_id": contract_id})
            return {"status": Bt.RUNNING, "commands": [release_wrong],
                "reason": "n21_recover_wrong_contract_dock"} if not release_wrong.is_empty() else {"status": Bt.FAILURE}
        if not (ship.get("transit", {}) as Dictionary).is_empty():
            return {"status": Bt.RUNNING, "reason": "n21_flight_not_finished"}
        var dock_cmd: Dictionary = Commands.make_command("RequestDock", {
            "ship": ship_id, "facility_location": at,
            "contract_id": contract_id, "preferred_facility_type": "station"})
        return {"status": Bt.RUNNING, "commands": [dock_cmd],
            "reason": "n146_n21_request_dock"} if not dock_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "DockDwell":
        if str(ship.get("docked_at", "")).is_empty():
            return {"status": Bt.RUNNING, "reason": "n21_dwell_requires_actual_dock"}
        var dock_tick: int = -1
        for receipt in world.get("dock_receipts", {}).values():
            if str(receipt.get("ship_id", "")) == ship_id and str(receipt.get("action", "")) == "dock":
                dock_tick = maxi(dock_tick, int(receipt.get("tick", -1)))
        if dock_tick < 0:
            return {"status": Bt.RUNNING, "reason": "no_verified_n21_dock_time"}
        var dwell_seconds: int = maxi(0, int(action.get("seconds", 0)))
        return {"status": Bt.SUCCESS} if tick - dock_tick >= dwell_seconds * 8 else {"status": Bt.RUNNING, "reason": "source_n84_dock_dwell"}
    if kind == "Undock":
        if str(ship.get("docked_at", "")).is_empty():
            return {"status": Bt.SUCCESS}
        if stage == "accepted" and location == str(c.get("source_location", "")):
            return {"status": Bt.RUNNING, "reason": "cannot_leave_without_n97_pickup"}
        var release_cmd: Dictionary = Commands.make_command("ReleaseDock", {
            "ship": ship_id, "facility_location": location,
            "contract_id": contract_id})
        return {"status": Bt.RUNNING, "commands": [release_cmd],
            "reason": "n146_n21_release_dock"} if not release_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "Buy":
        if stage == "picked_up":
            return {"status": Bt.SUCCESS}
        if stage != "accepted" or location != str(c.get("source_location", "")):
            return {"status": Bt.RUNNING, "reason": "n97_pickup_location_unavailable"}
        var source_owner: String = str(world.get("markets", {}).get(location, {}).get("owner", ""))
        if source_owner.is_empty():
            return {"status": Bt.FAILURE, "reason": "n97_source_market_owner_missing"}
        var source_dock: String = str(ship.get("docked_at", ""))
        if source_dock != source_owner:
            var fix_kind: String = "RequestDock" if source_dock.is_empty() else "ReleaseDock"
            var fix_cmd: Dictionary = Commands.make_command(fix_kind, {
                "ship": ship_id, "facility_location": location,
                "contract_id": contract_id, "preferred_facility_type": "station"})
            return {"status": Bt.RUNNING, "commands": [fix_cmd],
                "reason": "n97_wait_exact_source_warehouse"} if not fix_cmd.is_empty() else {"status": Bt.FAILURE}
        if str(action.get("commodity", "")) != str(c.get("commodity", "")) or int(action.get("qty", 0)) != int(c.get("quantity", -1)):
            return {"status": Bt.FAILURE, "reason": "n97_buy_not_matching_n104_contract"}
        var buy_cmd: Dictionary = Commands.make_command("RequestShipTransaction", {
            "ship": ship_id, "request_id": tick,
            "operation": "pickup", "contract_id": contract_id})
        return {"status": Bt.RUNNING, "commands": [buy_cmd],
            "reason": "n146_n97_actual_purchase"} if not buy_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "DeliverCargo":
        if stage != "picked_up" or location != str(c.get("destination_location", "")):
            return {"status": Bt.RUNNING, "reason": "n104_delivery_location_unavailable"}
        var destination_owner: String = str(world.get("markets", {}).get(location, {}).get("owner", ""))
        if destination_owner.is_empty():
            return {"status": Bt.FAILURE, "reason": "n104_destination_market_owner_missing"}
        var destination_dock: String = str(ship.get("docked_at", ""))
        if destination_dock != destination_owner:
            var fix_kind: String = "RequestDock" if destination_dock.is_empty() else "ReleaseDock"
            var fix_cmd: Dictionary = Commands.make_command(fix_kind, {
                "ship": ship_id, "facility_location": location,
                "contract_id": contract_id, "preferred_facility_type": "station"})
            return {"status": Bt.RUNNING, "commands": [fix_cmd],
                "reason": "n104_wait_exact_destination_warehouse"} if not fix_cmd.is_empty() else {"status": Bt.FAILURE}
        if str(action.get("contract_id", "")) != contract_id:
            return {"status": Bt.FAILURE, "reason": "n104_delivery_wrong_contract"}
        var delivery_cmd: Dictionary = Commands.make_command("RequestShipTransaction", {
            "ship": ship_id, "request_id": tick,
            "operation": "delivery", "contract_id": contract_id})
        return {"status": Bt.RUNNING, "commands": [delivery_cmd],
            "reason": "n146_n104_real_delivery"} if not delivery_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind in ["DockAtShipyard", "SellAll", "Refuel", "Refit", "DeliverPassengers",
            "EmbarkPassengers", "Rest"]:
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
            if str(command.get("ship", "")) != str(ship_id):
                return {"ok": false, "reason": "n146_ship_actor_mismatch",
                    "ship_id": str(ship_id)}
            if str(command.get("kind", "")) in ["RequestDock", "ReleaseDock", "RequestShipTransaction"]:
                # N39 applies these commands in the same physical ships
                # phase, AFTER the N84 cursor is committed. No side effects
                # in a BT or command-buffer proposal.
                continue
            if str(command.get("kind", "")) != "BeginTransit":
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
