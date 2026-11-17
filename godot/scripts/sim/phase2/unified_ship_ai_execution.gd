extends RefCounted
## P2 N84 execution + N146 command staging. N14 is the ONLY ship-motion
## physics; this adapter cannot grant cargo, dock spaces, credits or XP.
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const N91 = preload("res://scripts/ported/n91_construction_executor.gd")
const ShipCatalog = preload("res://scripts/sim/ship_catalog.gd")
const NativeTradeAction = preload("res://scripts/sim/phase2/unified_n83_trade_action.gd")
const NativeServiceAction = preload("res://scripts/sim/phase2/unified_n97_ship_service_action.gd")
const N90 = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const N104Resume = preload("res://scripts/sim/phase2/unified_n104_contract_resume.gd")

## Original colony contract targets a temporary physical dock, not a
## market warehouse. All IDs come from the one N39 source receipt.
static func _real_contract_dock(world: Dictionary,
        contract: Dictionary, location: String) -> Dictionary:
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if not market.is_empty():
        var owner_id: String = str(market.get("owner", ""))
        if world.get("facilities", {}).has(owner_id) and str(world["facilities"][owner_id].get("type", "")) == "station":
            return {"id": owner_id, "type": "station"}
    # The Rust ContractType::Construction uses the SAME prepared site
    # dock as founding passengers, but deposits into N154 rather than a
    # non-existent Market warehouse.
    if str(contract.get("contract_type", "")) not in ["passenger", "construction"] or (
            str(contract.get("mission_category", "")) != "strategy.colony.v1" or
            str(contract.get("destination_location", "")) != location):
        return {}
    # Construction contracts name exactly one authoritative site. Avoid a
    # full scan of the growing colony-site history on every N84 dock leaf.
    # Passenger contracts retain the original ordered scan/tie-break.
    var site_ids: Array = world.get("construction_sites", {}).keys()
    if str(contract.get("contract_type", "")) == "construction":
        var required_site: String = str(contract.get("colony_site_id", ""))
        if not world.get("construction_sites", {}).has(required_site):
            return {}
        site_ids = [required_site]
    for site_id in site_ids:
        var site: Dictionary = world["construction_sites"][site_id]
        if str(site.get("location_name", "")) != location or (
                str(site.get("faction_id", "")) != str(contract.get("faction_id", "")) or
                site.get("labor", {}) is not Dictionary or
                site.get("labor", {}).get("colony_source", null) == null or
                (str(contract.get("contract_type", "")) == "construction" and
                str(contract.get("colony_site_id", "")) != str(site_id))):
            continue
        var proof: Dictionary = world.get("construction_receipts", {}).get(
            "n151_colony_dock:" + str(site_id), {})
        var fid: String = str(proof.get("facility_id", ""))
        var fac: Dictionary = world.get("facilities", {}).get(fid, {})
        if str(proof.get("kind", "")) == "colony_dock_prepared" and (
                str(fac.get("type", "")) == "construction_dock" and
                str(fac.get("location", "")) == location and
                not bool(fac.get("abandoned", false))):
            return {"id": fid, "type": "construction_dock"}
    return {}

## Frozen Rust ShipAction::Dock / DockAtShipyard: ShipEconomy
## wait starts on the FIRST N84 attempt, not when N21 FIFO grants a slot.
## N38 saves this nullable integer cursor.
const DOCK_WAIT_CONTRACT: int = 150
const DOCK_WAIT_DEFAULT: int = 60
const DOCK_WAIT_LOW_MORALE: int = 30
const DOCK_LOW_MORALE_THRESHOLD: float = 40.0

static func _native_dock_wait(ship: Dictionary, tick: int,
        multiplier: int) -> Dictionary:
    if not (ship.get("transit", {}) is Dictionary):
        return {"status": Bt.FAILURE, "reason": "n21_invalid_original_transit"}
    if not ship["transit"].is_empty():
        # N14 Travel must finish before the N21 wait clock begins.
        return {"status": Bt.RUNNING, "reason": "n21_wait_real_n14_arrival"}
    if not str(ship.get("docked_at", "")).is_empty():
        ship["dock_attempt_start_tick"] = null
        return {}
    if str(ship.get("location", "")).is_empty():
        ship["dock_attempt_start_tick"] = null
        return {"status": Bt.FAILURE, "reason": "n21_missing_real_dock_location"}
    var start: Variant = ship.get("dock_attempt_start_tick", null)
    if start == null:
        ship["dock_attempt_start_tick"] = tick
        start = tick
    elif typeof(start) != TYPE_INT or int(start) < 0 or int(start) > tick:
        return {"status": Bt.FAILURE, "reason": "n21_invalid_saved_wait_clock"}
    var crew: Dictionary = ship.get("crew", {})
    var morale: float = float(crew.get("morale", 100.0))
    var budget: int = DOCK_WAIT_CONTRACT if not str(
        ship.get("active_contract_id", "")).is_empty() else (
        DOCK_WAIT_LOW_MORALE if morale < DOCK_LOW_MORALE_THRESHOLD else
        DOCK_WAIT_DEFAULT)
    budget *= maxi(1, multiplier)
    if tick - int(start) >= budget:
        ship["dock_attempt_start_tick"] = null
        return {"status": Bt.FAILURE, "reason": "n21_original_dock_wait_timeout"}
    return {}

static func _dispatch(action: Dictionary, _bb: Dictionary,
        world: Dictionary, graph: RefCounted, positions: Dictionary,
        ship_id: String, tick: int, scale: float,
        multiplier: int = 1, dock_ticks: Dictionary = {}) -> Dictionary:
    var kind: String = str(action.get("kind", ""))
    var ship: Dictionary = world["ships"][ship_id]
    var location: String = str(ship.get("location", ""))
    if kind in ["Dock", "DockAtShipyard"]:
        var patience: Dictionary = _native_dock_wait(ship, tick, multiplier)
        if not patience.is_empty():
            return patience
    if kind == "GateJump":
        # Frozen Rust ShipAction::GateJump proposes a N146 command;
        # position and the gate fee change ONLY in N108's single N39
        # Apply. Waiting for an actual paired gate is NOT a teleport.
        var source_gate_location: String = str(action.get("src_gate", ""))
        var dest_gate_location: String = str(action.get("dest_gate", ""))
        if source_gate_location.is_empty() or dest_gate_location.is_empty() or (
                source_gate_location == dest_gate_location):
            return {"status": Bt.FAILURE, "reason": "n108_invalid_source_gate_leaf"}
        if location == dest_gate_location and ship.get("transit", {}).is_empty():
            return {"status": Bt.SUCCESS, "reason": "n108_real_gate_arrival_confirmed"}
        if location != source_gate_location or not ship.get("transit", {}).is_empty():
            return {"status": Bt.RUNNING, "reason": "n108_source_gate_arrival_pending"}
        if not str(ship.get("docked_at", "")).is_empty():
            return {"status": Bt.RUNNING, "reason": "n108_actual_n21_gate_undock_needed"}
        # N84 may evaluate many GateJump leaves in the same paid tick.
        # Build the gate roster once per proposal, retaining the original
        # facilities iteration order and ambiguous-gate rejection. N84 only
        # mutates ship rows; N39 applies gate/facility changes after proposal.
        # dock_ticks is call-scoped scratch, never stored in World/N38.
        if not dock_ticks.has("_n84_gate_roster"):
            var gate_roster: Dictionary = {}
            for fid in world.get("facilities", {}):
                var fac: Dictionary = world["facilities"][fid]
                if str(fac.get("type", "")) == "gate" and fac.get(
                        "gate_link", null) is Dictionary:
                    var gate_location: String = str(fac.get("location", ""))
                    if not gate_roster.has(gate_location):
                        gate_roster[gate_location] = []
                    gate_roster[gate_location].append(str(fid))
            dock_ticks["_n84_gate_roster"] = gate_roster
        var gates: Array = dock_ticks["_n84_gate_roster"].get(location, [])
        if gates.size() != 1:
            return {"status": Bt.RUNNING, "reason": "n108_unbuilt_or_ambiguous_source_gate"}
        var origin: Dictionary = world["facilities"][gates[0]]
        var paired: String = str(origin["gate_link"].get(
            "paired_gate_id", ""))
        var destination: Dictionary = world.get("facilities", {}).get(paired, {})
        if destination.is_empty() or str(destination.get("type", "")) != "gate" or (
                str(destination.get("location", "")) != dest_gate_location or
                not (destination.get("gate_link") is Dictionary) or str(
                destination["gate_link"].get("paired_gate_id", "")) != str(
                gates[0])):
            return {"status": Bt.RUNNING, "reason": "n108_gate_has_no_real_paired_exit"}
        if int(ship.get("credits", 0)) < 50:
            return {"status": Bt.RUNNING, "reason": "n108_ship_cannot_pay_source_gate"}
        # A real fee may exceed Rust's optimistic 50-credit BT
        # estimate; the authoritative N39/N9 Apply rechecks it.
        var gate_cmd: Dictionary = Commands.make_command(
            "RequestGateJump", {"ship": ship_id,
                "src_gate_location": source_gate_location,
                "dest_gate_location": dest_gate_location})
        return {"status": Bt.RUNNING, "commands": [gate_cmd],
            "reason": "n108_wait_exclusive_real_gate_apply"} if not gate_cmd.is_empty() else {
            "status": Bt.FAILURE, "reason": "n108_invalid_n146_request"}
    if kind == "Travel":
        var engineering_site: String = str(action.get("construction_site_id", ""))
        if not engineering_site.is_empty():
            var actual_site: Dictionary = world.get("construction_sites", {}).get(engineering_site, {})
            if actual_site.is_empty() or str(ship.get("current_goal", "")) != "construct" or str(ship.get("active_contract_id", "")) != "" or str(actual_site.get("faction_id", "")) != str(ship.get("faction_id", "")):
                return {"status": Bt.FAILURE, "reason": "n91_unverified_engineering_travel"}
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
    # N91 construction is a noncommercial real engineering task, NOT
    # a fictitious N104 payment. N141 alone awards paid progress.
    if kind in ["ConstructionUndock", "ConstructionDock", "Construct"]:
        var site_id: String = str(action.get("site_id", ""))
        var site: Dictionary = world.get("construction_sites", {}).get(site_id, {})
        if site.is_empty():
            return {"status": Bt.SUCCESS, "reason": "n154_site_already_materialized"}
        if str(ship.get("current_goal", "")) != "construct" or str(ship.get("active_contract_id", "")) != "" or str(site.get("faction_id", "")) != str(ship.get("faction_id", "")):
            return {"status": Bt.FAILURE, "reason": "n91_invalid_construction_actor"}
        if not ShipCatalog.spec(str(ship.get("class", ""))).get("crew_roles", []).has("engineer"):
            return {"status": Bt.FAILURE, "reason": "n91_no_engineering_crew"}
        var site_location: String = str(site.get("location_name", ""))
        if kind == "ConstructionUndock":
            if not ship.get("transit", {}).is_empty():
                return {"status": Bt.RUNNING, "reason": "n91_undock_waiting_for_flight"}
            var old_dock: String = str(ship.get("docked_at", ""))
            if old_dock.is_empty():
                return {"status": Bt.SUCCESS, "reason": "n91_released_real_origin_dock"}
            var origin_station: Dictionary = world.get("facilities", {}).get(old_dock, {})
            if origin_station.is_empty() or str(origin_station.get("location", "")) != location:
                return {"status": Bt.FAILURE, "reason": "n91_invalid_engineer_origin_dock"}
            var unmoor: Dictionary = Commands.make_command("ReleaseDock", {
                "ship": ship_id, "facility_location": location,
                "construction_site_id": site_id})
            return {"status": Bt.RUNNING, "commands": [unmoor],
                "reason": "n91_real_origin_n21_undock"} if not unmoor.is_empty() else {"status": Bt.FAILURE}
        if location != site_location or not ship.get("transit", {}).is_empty():
            return {"status": Bt.RUNNING, "reason": "n91_site_arrival_pending"}
        var station_id: String = str(world.get("markets", {}).get(location, {}).get("owner", ""))
        var required_type: String = "station"
        if station_id.is_empty():
            # Rust N91 engineer physically docks at prepare_docks' temporary
            # colony port while N154 still has no station or Market.
            var proof: Dictionary = world.get("construction_receipts", {}).get(
                "n151_colony_dock:" + site_id, {})
            var candidate: String = str(proof.get("facility_id", ""))
            var fac: Dictionary = world.get("facilities", {}).get(candidate, {})
            if str(proof.get("kind", "")) == "colony_dock_prepared" and (
                    str(fac.get("type", "")) == "construction_dock" and
                    str(fac.get("location", "")) == location and
                    str(fac.get("construction_source_site_id", "")) == site_id):
                station_id = candidate
                required_type = "construction_dock"
        if station_id.is_empty() or not world.get("facilities", {}).has(station_id):
            return {"status": Bt.RUNNING, "reason": "n91_site_physical_dock_not_prepared"}
        var dock_id: String = str(ship.get("docked_at", ""))
        if kind == "ConstructionDock":
            if dock_id == station_id:
                return {"status": Bt.SUCCESS, "reason": "n91_physically_docked"}
            var request_kind: String = "RequestDock" if dock_id.is_empty() else "ReleaseDock"
            var command: Dictionary = Commands.make_command(request_kind, {
                "ship": ship_id, "facility_location": location,
                "construction_site_id": site_id,
                "preferred_facility_type": required_type})
            if command.is_empty():
                return {"status": Bt.FAILURE, "reason": "n146_n91_dock_request_invalid"}
            return {"status": Bt.RUNNING, "commands": [command],
                "reason": "n91_wait_real_n21_dock"}
        if dock_id != station_id:
            return {"status": Bt.RUNNING, "reason": "n91_construct_requires_actual_dock"}
        if int(site.get("progress_delivered", 0)) < int(site.get("progress_required", 1)):
            return {"status": Bt.RUNNING, "reason": "n91_material_delivery_pending"}
        return {"status": Bt.RUNNING, "reason": "n91_wait_n141_paid_work"}
    var contract_id: String = str(ship.get("active_contract_id", ""))
    # N83 trade, N103 native ice delivery and N80 gate exploration all
    # use the SAME actual N21 market dock and N146 command Apply.
    # Mine may SELL its physically extracted ice, never buy free stock.
    var local_goal: String = str(ship.get("current_goal", ""))
    if contract_id.is_empty() and local_goal in [
            "trade_route", "mine", "mine_ice", "deliver_mined_ice", "explore"]:
        if kind in ["Buy", "Sell", "SellAll"]:
            if local_goal == "trade_route" or (
                    local_goal in ["mine", "mine_ice", "deliver_mined_ice"] and
                    kind == "Sell" and
                    str(action.get("commodity", "")) == "ice"):
                return NativeTradeAction.propose(ship, action, world, tick)
            return {"status": Bt.FAILURE, "reason": "n80_unverified_market_leaf"}
        if kind in ["Dock", "Undock"]:
            # Rust lets a ship leave its original real dock before
            # travelling to a market; departure does NOT require an
            # origin market. Destination Dock DOES require N39 Market.
            if not ship.get("transit", {}).is_empty():
                return {"status": Bt.RUNNING, "reason": "n83_wait_real_ship_arrival"}
            var docked: String = str(ship.get("docked_at", ""))
            if kind == "Undock" and docked.is_empty():
                return {"status": Bt.SUCCESS}
            var market: Dictionary = world.get("markets", {}).get(location, {})
            var station_id: String = str(market.get("owner", ""))
            if kind == "Dock":
                var station: Dictionary = world.get("facilities", {}).get(station_id, {})
                if station.is_empty() or str(station.get("location", "")) != location or (
                        int(station.get("docking_capacity", 0)) < 1 or
                        bool(station.get("abandoned", false))):
                    return {"status": Bt.RUNNING, "reason": "n83_no_real_trade_dock"}
                if docked == station_id:
                    return {"status": Bt.SUCCESS}
            elif not world.get("facilities", {}).has(docked) or str(world["facilities"][docked].get("location", "")) != location:
                return {"status": Bt.FAILURE, "reason": "n83_cannot_leave_missing_real_origin_dock"}
            var operation: String = "RequestDock" if kind == "Dock" and docked.is_empty() else "ReleaseDock"
            var dock_cmd: Dictionary = Commands.make_command(operation, {
                "ship": ship_id, "facility_location": location,
                "native_free_trade": true, "native_source_goal": local_goal,
                "preferred_facility_type": "station"})
            return {"status": Bt.RUNNING, "commands": [dock_cmd],
                "reason": "n83_wait_real_market_dock"} if not dock_cmd.is_empty() else {"status": Bt.FAILURE}
    var contracts: Dictionary = world.get("contract_board", {}).get("contracts", {})
    var c: Dictionary = contracts.get(contract_id, {})
    var stage: String = str(c.get("status", ""))
    var at: String = str(c.get("source_location", "")) if stage == "accepted" else str(c.get("destination_location", ""))
    if kind == "Dock":
        if stage not in ["accepted", "picked_up"] or location != at:
            return {"status": Bt.RUNNING, "reason": "n21_contract_location_not_ready"}
        var assigned_dock: Dictionary = _real_contract_dock(world, c, at)
        var facility: String = str(assigned_dock.get("id", ""))
        if facility.is_empty():
            return {"status": Bt.RUNNING, "reason": "n151_original_contract_dock_not_prepared"}
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
            "contract_id": contract_id,
            "preferred_facility_type": str(assigned_dock["type"])})
        return {"status": Bt.RUNNING, "commands": [dock_cmd],
            "reason": "n146_n21_request_dock"} if not dock_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "DockDwell":
        if str(ship.get("docked_at", "")).is_empty():
            return {"status": Bt.RUNNING, "reason": "n21_dwell_requires_actual_dock"}
        # The N84 pass may evaluate DockDwell for many ships. Build the
        # latest authoritative N21 dock receipt cursor only on first use,
        # then reuse it for this read-only proposal pass. Never persist it
        # across ticks: N21 may undock/redock between paid ticks.
        if not dock_ticks.has("_ready"):
            for receipt in world.get("dock_receipts", {}).values():
                if str(receipt.get("action", "")) != "dock":
                    continue
                var receipt_ship: String = str(receipt.get("ship_id", ""))
                dock_ticks[receipt_ship] = maxi(
                    int(dock_ticks.get(receipt_ship, -1)),
                    int(receipt.get("tick", -1)))
            dock_ticks["_ready"] = true
        var dock_tick: int = int(dock_ticks.get(ship_id, -1))
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
            "contract_id": contract_id,
            "native_refit": contract_id.is_empty() and str(ship.get("current_goal", "")) in ["refit", "retrofit"]})
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
    if kind == "EmbarkPassengers":
        if str(c.get("contract_type", "")) != "passenger" or str(ship.get("active_contract_id", "")) != contract_id:
            return {"status": Bt.FAILURE, "reason": "n104_nonpassenger_embark_leaf"}
        if stage == "picked_up":
            return {"status": Bt.SUCCESS}
        if stage != "accepted" or location != str(c.get("source_location", "")) or not (ship.get("transit", {}) as Dictionary).is_empty():
            return {"status": Bt.RUNNING, "reason": "n104_wait_physical_passenger_origin"}
        var origin_station: String = str(world.get("markets", {}).get(location, {}).get("owner", ""))
        if origin_station.is_empty() or not world.get("facilities", {}).has(origin_station):
            return {"status": Bt.RUNNING, "reason": "n104_missing_real_passenger_source"}
        var real_dock: String = str(ship.get("docked_at", ""))
        if real_dock != origin_station:
            var dock_kind: String = "RequestDock" if real_dock.is_empty() else "ReleaseDock"
            var dock_cmd: Dictionary = Commands.make_command(dock_kind, {
                "ship": ship_id, "facility_location": location,
                "contract_id": contract_id, "preferred_facility_type": "station"})
            return {"status": Bt.RUNNING, "commands": [dock_cmd],
                "reason": "n104_wait_real_embark_dock"} if not dock_cmd.is_empty() else {"status": Bt.FAILURE}
        var boarding: Dictionary = Commands.make_command("RequestShipTransaction", {
            "ship": ship_id, "request_id": tick, "operation": "passenger_embark",
            "contract_id": contract_id})
        return {"status": Bt.RUNNING, "commands": [boarding],
            "reason": "n146_n104_real_passenger_embark"} if not boarding.is_empty() else {"status": Bt.FAILURE}
    if kind in ["DeliverCargo", "DeliverPassengers"]:
        if kind == "DeliverPassengers" and str(c.get("contract_type", "")) != "passenger":
            return {"status": Bt.FAILURE, "reason": "n104_passenger_leaf_wrong_kind"}
        if stage != "picked_up" or location != str(c.get("destination_location", "")):
            return {"status": Bt.RUNNING, "reason": "n104_delivery_location_unavailable"}
        var destination: Dictionary = _real_contract_dock(world, c, location)
        var destination_owner: String = str(destination.get("id", ""))
        if destination_owner.is_empty():
            return {"status": Bt.RUNNING, "reason": "n104_real_destination_dock_not_ready"}
        var destination_dock: String = str(ship.get("docked_at", ""))
        if destination_dock != destination_owner:
            var fix_kind: String = "RequestDock" if destination_dock.is_empty() else "ReleaseDock"
            var fix_cmd: Dictionary = Commands.make_command(fix_kind, {
                "ship": ship_id, "facility_location": location,
                "contract_id": contract_id,
                "preferred_facility_type": str(destination["type"])})
            return {"status": Bt.RUNNING, "commands": [fix_cmd],
                "reason": "n104_wait_exact_destination_dock"} if not fix_cmd.is_empty() else {"status": Bt.FAILURE}
        if str(action.get("contract_id", "")) != contract_id:
            return {"status": Bt.FAILURE, "reason": "n104_delivery_wrong_contract"}
        var delivery_cmd: Dictionary = Commands.make_command("RequestShipTransaction", {
            "ship": ship_id, "request_id": tick,
            "operation": "passenger_delivery" if str(c.get("contract_type", "")) == "passenger" else "delivery",
            "contract_id": contract_id})
        return {"status": Bt.RUNNING, "commands": [delivery_cmd],
            "reason": "n146_n104_real_delivery"} if not delivery_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "DockAtShipyard":
        # Real N108 shipyard has a separate N21 slot from the N97
        # station warehouse. Do not fabricate a dock just from location.
        if str(ship.get("current_goal", "")) not in ["retrofit", "refit"] or not contract_id.is_empty():
            return {"status": Bt.FAILURE, "reason": "n108_no_real_refit_goal"}
        var old_dock: String = str(ship.get("docked_at", ""))
        var dock_fac: Dictionary = world.get("facilities", {}).get(old_dock, {})
        if not dock_fac.is_empty() and str(dock_fac.get("type", "")) == "shipyard":
            return {"status": Bt.SUCCESS}
        if not ship.get("transit", {}).is_empty():
            return {"status": Bt.RUNNING, "reason": "n108_wait_native_arrival"}
        var found: bool = false
        for id in world.get("facilities", {}):
            var fac: Dictionary = world["facilities"][id]
            if str(fac.get("type", "")) == "shipyard" and not fac.get("abandoned", false) and str(fac.get("location", "")) == location:
                found = true
                break
        if not found:
            return {"status": Bt.RUNNING, "reason": "n108_no_built_shipyard_here"}
        var dock_cmd: Dictionary = Commands.make_command(
            "RequestDock" if old_dock.is_empty() else "ReleaseDock", {
                "ship": ship_id, "facility_location": location,
                "preferred_facility_type": "shipyard", "native_refit": true})
        return {"status": Bt.RUNNING, "commands": [dock_cmd],
            "reason": "n108_wait_real_n21_shipyard_dock"} if not dock_cmd.is_empty() else {"status": Bt.FAILURE}
    if kind == "Refit":
        if str(ship.get("current_goal", "")) not in ["retrofit", "refit"] or not contract_id.is_empty():
            return {"status": Bt.FAILURE, "reason": "n108_refit_without_live_goal"}
        var slot: String = str(action.get("slot", action.get("refit_slot", "")))
        var slug: String = str(action.get("slug", action.get("refit_slug", "")))
        var slots: Dictionary = ship.get("fitting", {}).get("slots", {})
        if slot.is_empty() or slug.is_empty() or not slots.has(slot):
            return {"status": Bt.RUNNING, "reason": "n108_missing_original_refit_slot_or_slug"}
        if str(slots[slot]) == slug:
            return {"status": Bt.SUCCESS}
        var yard_id: String = str(ship.get("docked_at", ""))
        var yard: Dictionary = world.get("facilities", {}).get(yard_id, {})
        if yard.is_empty() or str(yard.get("type", "")) != "shipyard" or bool(yard.get("abandoned", false)):
            return {"status": Bt.RUNNING, "reason": "n108_ship_not_physically_at_yard"}
        if int(yard.get("module_stock", {}).get("stock", {}).get(slug, 0)) < 1 or int(ship.get("progression", {}).get("retrofit_points", 0)) < 1:
            return {"status": Bt.RUNNING, "reason": "n108_no_paid_module_or_retrofit_point"}
        var command: Dictionary = Commands.make_command("RequestRefit", {
            "ship": ship_id, "slot": slot, "slug": slug})
        return {"status": Bt.RUNNING, "commands": [command],
            "reason": "n146_n108_paid_refit_request"} if not command.is_empty() else {"status": Bt.FAILURE}
    if kind in ["Refuel", "Mine"]:
        # Source N90 exclusive service requests. Only N97/N39 Apply can
        # move fuel, mined ice, money or engineering skill experience.
        return NativeServiceAction.propose(ship, action, tick, multiplier)
    if kind == "Rest":
        return {"status": Bt.RUNNING, "reason": "awaiting_native_rest_" + kind}
    if kind == "Idle":
        return {"status": Bt.SUCCESS}
    return {"status": Bt.FAILURE, "reason": "unknown_n84_leaf_" + kind}

## All fleet commands are proposed in stable source ship-id order. N14
## transit and N21/N90/N97/N108 commands pass one N146 queue; N39/N9
## remain the only physical/financial Apply authority.
static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, tick: int, scale: float,
        multiplier: int = 1) -> Dictionary:
    if graph == null or not (world.get("ships") is Dictionary) or tick < 1:
        return {"ok": false, "reason": "missing_single_world_ai_fleet"}
    # N84 mutates only its owned ship rows and scalar ship_next_token.
    # Full World deep-copy here duplicated growing World-side receipts,
    # markets and construction history every ship tick. N9 ledger remains
    # a separate N39 store. Keep all other
    # source state read-only; detach the fleet before the first BT write.
    # N39/N146 remains the sole authoritative mutation/commit path.
    var staged: Dictionary = world.duplicate()
    staged["ships"] = (world["ships"] as Dictionary).duplicate(true)
    var cmd_buffer = Commands.new()
    if not cmd_buffer.begin_phase(tick, "ships"):
        return {"ok": false, "reason": "n146_phase_cannot_begin"}
    var records: Array = []
    var ids: Array = staged["ships"].keys()
    ids.sort()
    var changed: bool = false
    # Per-proposal scratch only; no World or N38 state is added.
    var dock_ticks: Dictionary = {}
    for ship_id in ids:
        var ship: Dictionary = staged["ships"][ship_id]
        var contract_id: String = str(ship.get("active_contract_id", ""))
        if contract_id.is_empty():
            var own_goal: String = str(ship.get("current_goal", ""))
            if own_goal not in ["construct", "retrofit", "refit", "trade_route",
                    "mine", "mine_ice", "deliver_mined_ice", "explore", "refuel"]:
                continue
            var assigned_bt: Variant = ship.get("current_bt", null)
            if not (assigned_bt is Dictionary) or not Bt.validate(assigned_bt):
                return {"ok": false, "reason": "n84_invalid_active_source_plan",
                    "ship_id": str(ship_id)}
            if own_goal == "construct":
                var target_site: String = N91.target(assigned_bt)
                if target_site.is_empty():
                    return {"ok": false, "reason": "n91_active_construct_target_missing",
                        "ship_id": str(ship_id)}
                if not staged.get("construction_sites", {}).has(target_site):
                    # Native N154 has materialized the construction site:
                    # release only its N91 plan, never its physical dock.
                    ship["current_goal"] = "idle"
                    ship["current_bt"] = null
                    ship["current_goal_score"] = 0.0
                    ship["planning_source"] = "n91_construction_materialized"
                    changed = true
                    records.append({"ship_id": str(ship_id), "contract_id": "",
                        "site_id": target_site, "leaf": "", "status": Bt.SUCCESS,
                        "reason": "n154_construction_completed"})
                    continue
        var board: Dictionary = staged.get("contract_board", {})
        var contracts: Dictionary = board.get("contracts", {})
        var held: Dictionary = contracts.get(contract_id, {})
        if not contract_id.is_empty() and (held.is_empty() or str(held.get("status", "")) not in ["accepted", "picked_up"] or str(held.get("fulfiller_id", "")) != str(ship_id)):
            return {"ok": false, "reason": "n84_missing_actual_n104_obligation",
                "ship_id": str(ship_id)}
        var bt: Variant = ship.get("current_bt", null)
        if bt == null:
            var recovered: Dictionary = {}
            if not contract_id.is_empty():
                # Rust resume_contract_bt rebuilds a real GOAP tree
                # from the current ship, cargo and held N104 contract.
                recovered = N104Resume.propose(ship, held, graph, staged)
                if recovered.get("ok", false):
                    ship["current_bt"] = recovered["tree"].duplicate(true)
                    ship["current_goal"] = str(recovered["goal"])
                    ship["last_plan_tick"] = tick
                    ship["planning_source"] = "n104_original_n81_checkpoint_resume"
                    changed = true
                    records.append({"ship_id": str(ship_id),
                        "contract_id": contract_id, "leaf": "",
                        "status": Bt.RUNNING,
                        "reason": "n104_original_goap_recovered"})
                    continue
            var missing_plan_reason: String = "n84_no_source_idle_plan"
            if not contract_id.is_empty():
                missing_plan_reason = "n104_wait_source_resume_" + str(
                    recovered.get("reason", "missing_real_route"))
            records.append({"ship_id": str(ship_id),
                "contract_id": contract_id, "leaf": "",
                "status": Bt.RUNNING, "reason": missing_plan_reason})
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
                positions, str(ship_id), tick, scale, multiplier, dock_ticks)
            detail["reason"] = str(result.get("reason", ""))
            return result
        var next: Dictionary = Bt.tick(bt, executor, {})
        if not next.get("ok", false):
            return {"ok": false, "reason": "n84_tick_rejected",
                "ship_id": str(ship_id)}
        if next["status"] == Bt.FAILURE:
            if contract_id.is_empty() and str(ship.get(
                    "current_goal", "")) in [
                        "trade_route", "mine", "mine_ice",
                        "deliver_mined_ice", "explore", "refuel",
                        "construct", "retrofit", "refit"]:
                # Rust failed speculative ship goals may be replanned;
                # never halt the N158 world or manufacture a fill.
                # Any settled prior purchases remain physical cargo.
                var active_slot: Dictionary = ship.get("transaction", N90.empty())
                var canceled: Dictionary = N90.cancel_on_replan(active_slot)
                if not canceled.get("ok", false):
                    return {"ok": false, "reason": "n83_replan_invalid_n90_slot"}
                ship["transaction"] = canceled["state"].duplicate(true)
                ship["current_goal"] = "idle"
                ship["current_goal_score"] = 0.0
                ship["current_bt"] = null
                ship["dock_attempt_start_tick"] = null
                ship["planning_source"] = "n21_source_dock_timeout_replan" if (
                    detail["reason"] == "n21_original_dock_wait_timeout") else (
                    "n84_original_failed_goal_replan")
                changed = true
                records.append({"ship_id": str(ship_id), "contract_id": "",
                    "leaf": current_leaf, "status": Bt.FAILURE,
                    "reason": detail["reason"]})
                continue
            if not contract_id.is_empty():
                var picked_up: bool = str(held.get("status", "")) == "picked_up"
                var good: String = str(held.get("commodity", ""))
                var required: int = int(held.get("quantity", 0))
                var physical_job: bool = str(held.get(
                    "contract_type", "")) not in ["passenger", "crew_mission"]
                var has_original_load: bool = physical_job and required > 0 and (
                    int(ship.get("cargo", {}).get(good, 0)) >= required)
                # Rust ContractBoard::release is guarded Accepted only.
                # A physically loaded ship must never release this
                # paid N104 obligation for a second free pickup.
                if not picked_up and not has_original_load:
                    var release: Dictionary = Commands.make_command(
                        "ReleaseContract", {"ship": str(ship_id),
                        "ship_id": str(ship_id), "contract_id": contract_id,
                        "reason": "bt_failure"})
                    if release.is_empty() or not cmd_buffer.push(release):
                        return {"ok": false,
                            "reason": "n104_invalid_n146_release_command",
                            "ship_id": str(ship_id)}
                    var pending: Dictionary = N90.cancel_on_replan(
                        ship.get("transaction", N90.empty()))
                    if not pending.get("ok", false):
                        return {"ok": false,
                            "reason": "n104_invalid_original_n90_cancel",
                            "ship_id": str(ship_id)}
                    ship["transaction"] = pending["state"].duplicate(true)
                    ship["current_bt"] = null
                    ship["dock_attempt_start_tick"] = null
                    # Only N39 ReleaseContract Apply is authorized to
                    # clear active_contract_id and return to Posted.
                    ship["planning_source"] = (
                        "n104_pending_release_on_bt_failure")
                    changed = true
                    records.append({"ship_id": str(ship_id),
                        "contract_id": contract_id, "leaf": current_leaf,
                        "status": Bt.FAILURE,
                        "reason": "n104_release_accepted_to_n153"})
                    continue
                # Rust resume_contract_bt starts with actual cargo;
                # a PickedUp run bypasses Accept and Buy permanently.
                var resume: Dictionary = N104Resume.propose(
                    ship, held, graph, staged)
                ship["dock_attempt_start_tick"] = null
                if resume.get("ok", false):
                    var canceled_slot: Dictionary = N90.cancel_on_replan(
                        ship.get("transaction", N90.empty()))
                    if not canceled_slot.get("ok", false):
                        return {"ok": false,
                            "reason": "n104_invalid_pickup_resume_mailbox"}
                    ship["transaction"] = canceled_slot["state"].duplicate(true)
                    ship["current_bt"] = resume["tree"].duplicate(true)
                    ship["current_goal"] = str(resume["goal"])
                    ship["last_plan_tick"] = tick
                    ship["planning_source"] = "n104_original_n81_pickedup_resume"
                    changed = true
                    records.append({"ship_id": str(ship_id),
                        "contract_id": contract_id, "leaf": current_leaf,
                        "status": Bt.RUNNING,
                        "reason": "n104_replanned_from_actual_paid_cargo"})
                    continue
                # Missing physical proof/route cannot justify
                # destroying N104 escrow. The next N140 gate can
                # retry; no phantom goods, money or board release.
                ship["planning_source"] = "n104_replan_blocked_real_source"
                changed = true
                records.append({"ship_id": str(ship_id),
                    "contract_id": contract_id, "leaf": current_leaf,
                    "status": Bt.RUNNING, "reason": str(resume.get(
                        "reason", "no_native_resume_route"))})
                continue
            return {"ok": false, "reason": "n84_leaf_failed_" + current_leaf,
                "ship_id": str(ship_id)}
        for command in next.get("commands", []):
            if not cmd_buffer.push(command):
                return {"ok": false, "reason": "n146_invalid_dispatch_command",
                    "ship_id": str(ship_id)}
            if str(command.get("ship", "")) != str(ship_id):
                return {"ok": false, "reason": "n146_ship_actor_mismatch",
                    "ship_id": str(ship_id)}
            if str(command.get("kind", "")) in ["RequestDock", "ReleaseDock", "RequestShipTransaction", "RequestRefit", "GrantCrewXp", "RequestGateJump"]:
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
        if ship != world["ships"][ship_id]:
            # An N90 poll may clear a paid acknowledgment without a new
            # command; that single-owner cursor must still be committed.
            changed = true
        ship["current_bt"] = next["tree"].duplicate(true)
        if next["status"] == Bt.SUCCESS and contract_id.is_empty() and (
                str(ship.get("current_goal", "")) in [
                    "trade_route", "mine", "mine_ice",
                    "deliver_mined_ice", "explore", "refuel"]):
            ship["current_goal"] = "idle"
            ship["current_goal_score"] = 0.0
            ship["current_bt"] = null
            ship["planning_source"] = "n83_original_traded_and_finished"
            changed = true
        if not next.get("commands", []).is_empty():
            changed = true
        records.append({"ship_id": str(ship_id), "contract_id": contract_id,
            "site_id": N91.target(next["tree"]) if contract_id.is_empty() else "",
            "leaf": current_leaf, "status": str(next["status"]),
            "reason": detail["reason"]})
    return {"ok": true, "changed": changed, "ships": staged["ships"],
        "next_token": int(staged.get("ship_next_token", 0)),
        "commands": cmd_buffer.drain(), "trace": records}
