extends RefCounted
## P2 N84 execution + N146 command staging. N14 is the ONLY ship-motion
## physics; this adapter cannot grant cargo, dock spaces, credits or XP.
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const N91 = preload("res://scripts/ported/n91_construction_executor.gd")
const ShipCatalog = preload("res://scripts/sim/ship_catalog.gd")

## Original colony contract targets a temporary physical dock, not a
## market warehouse. All IDs come from the one N39 source receipt.
static func _real_contract_dock(world: Dictionary,
        contract: Dictionary, location: String) -> Dictionary:
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if not market.is_empty():
        var owner_id: String = str(market.get("owner", ""))
        if world.get("facilities", {}).has(owner_id) and str(world["facilities"][owner_id].get("type", "")) == "station":
            return {"id": owner_id, "type": "station"}
    if str(contract.get("contract_type", "")) != "passenger" or (
            str(contract.get("mission_category", "")) != "strategy.colony.v1" or
            str(contract.get("destination_location", "")) != location):
        return {}
    for site_id in world.get("construction_sites", {}):
        var site: Dictionary = world["construction_sites"][site_id]
        if str(site.get("location_name", "")) != location or (
                str(site.get("faction_id", "")) != str(contract.get("faction_id", "")) or
                site.get("labor", {}) is not Dictionary or
                site.get("labor", {}).get("colony_source", null) == null):
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

static func _dispatch(action: Dictionary, _bb: Dictionary,
        world: Dictionary, graph: RefCounted, positions: Dictionary,
        ship_id: String, tick: int, scale: float) -> Dictionary:
    var kind: String = str(action.get("kind", ""))
    var ship: Dictionary = world["ships"][ship_id]
    var location: String = str(ship.get("location", ""))
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
    if kind in ["SellAll", "Refuel", "Rest"]:
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
            var own_goal: String = str(ship.get("current_goal", ""))
            if own_goal not in ["construct", "retrofit", "refit"]:
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
            if str(command.get("kind", "")) in ["RequestDock", "ReleaseDock", "RequestShipTransaction", "RequestRefit"]:
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
            "site_id": N91.target(next["tree"]) if contract_id.is_empty() else "",
            "leaf": current_leaf, "status": str(next["status"]),
            "reason": detail["reason"]})
    return {"ok": true, "changed": changed, "ships": staged["ships"],
        "next_token": int(staged.get("ship_next_token", 0)),
        "commands": cmd_buffer.drain(), "trace": records}
