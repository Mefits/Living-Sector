extends RefCounted
## N39 / Rust Galaxy 0.6.7 physical production snapshot.
## This is a read/validate boundary, NOT another world/ledger implementation.
## The caller must supply real market, facility, population and body snapshots.
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const NativeShipLifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const NativeShipLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")
const Technology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const Construction = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const NativeRelations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")
const ShipyardRecipes = preload("res://scripts/sim/shipyard/native_module_recipes_n132.gd")
const SourceExecution = preload("res://scripts/port/n121_native_execution_state.gd")

static func validate(state: Dictionary) -> String:
    for key in ["facilities", "markets", "populations", "bodies"]:
        if not (state.get(key) is Dictionary):
            return "missing_" + key
    if state["facilities"].is_empty() or state["markets"].is_empty():
        return "empty_world"
    # Ships are optional only for genuinely older P2 saves. Never refill
    # their tanks from the frozen seed during restoration. A new game has
    # all 24 ships in this SAME authoritative physical world and ledger.
    if state.has("ships"):
        if not (state["ships"] is Dictionary):
            return "invalid_fleet"
        if typeof(state.get("ship_next_token", null)) != TYPE_INT or int(state["ship_next_token"]) < 1:
            return "invalid_ship_transit_nonce"
        for receipts_key in ["dock_receipts", "cargo_receipts"]:
            if state.has(receipts_key) and not (state[receipts_key] is Dictionary):
                return "invalid_fleet_receipts"
        var dock_occupancy: Dictionary = {}
        var fleet = ShipState.new()
        var rows: Array = []
        var max_token: int = 0
        for ship_id in state["ships"]:
            var ship_value: Variant = state["ships"][ship_id]
            if not _id(ship_id) or not (ship_value is Dictionary):
                return "invalid_ship"
            var ship: Dictionary = ship_value
            if str(ship.get("id", "")) != str(ship_id):
                return "invalid_ship_identity"
            if ship.has("lifecycle"):
                if not (ship["lifecycle"] is Dictionary) or not NativeShipLifecycle._valid_lifecycle(ship["lifecycle"]):
                    return "invalid_persisted_native_n148_lifecycle"
            if ship.has("lod"):
                if not (ship["lod"] is Dictionary):
                    return "invalid_persisted_native_n140_lod"
                var cursor: Dictionary = ship["lod"]
                if typeof(cursor.get("divisor", null)) != TYPE_INT or typeof(cursor.get("next_tick", null)) != TYPE_INT or not NativeShipLod._cursor_ok(cursor):
                    return "invalid_persisted_native_n140_cursor"
            # Frozen Rust ShipMemory: each observed PriceMemory carries a
            # current source MarketPricing float and its exact tick.
            # No omniscient/mirrored market or second Market book.
            if ship.has("memory"):
                if not (ship["memory"] is Dictionary):
                    return "invalid_native_ship_memory"
                var mem: Dictionary = ship["memory"]
                for key in ["price_knowledge", "visited", "recent_systems",
                        "route_performance", "contract_rejections"]:
                    if not mem.has(key):
                        return "incomplete_native_ship_memory_" + key
                if not (mem["price_knowledge"] is Dictionary and mem["visited"] is Array and
                        mem["recent_systems"] is Array and mem["route_performance"] is Dictionary and
                        mem["contract_rejections"] is Dictionary):
                    return "invalid_native_ship_memory_components"
                for loc in mem["price_knowledge"]:
                    var records: Variant = mem["price_knowledge"][loc]
                    if not _id(loc) or not (records is Dictionary):
                        return "invalid_native_price_market_location"
                    for commodity in records:
                        var known: Variant = records[commodity]
                        if not _id(commodity) or not (known is Dictionary) or not (
                                known.get("price", null) is float or known.get("price", null) is int) or (
                                not is_finite(float(known["price"])) or float(known["price"]) < 0.0):
                            return "invalid_native_price_memory_amount"
                        if typeof(known.get("tick", null)) != TYPE_INT or int(known["tick"]) < 0:
                            return "invalid_native_price_memory_tick"
                for loc in mem["visited"]:
                    if not _id(loc):
                        return "invalid_native_visited_location"
                for system in mem["recent_systems"]:
                    if not _id(system):
                        return "invalid_native_recent_system"
            # N149 live ship crew is the original aggregated Rust ShipCrew:
            # payroll accumulates nonspendable wages_credits, not a new
            # N9 bank. Older P2 saves without this component stay valid.
            if ship.has("crew"):
                if not (ship["crew"] is Dictionary):
                    return "invalid_native_ship_crew"
                var crew: Dictionary = ship["crew"]
                if typeof(crew.get("size", null)) != TYPE_INT or int(crew["size"]) != int(ship.get("crew_size", -1)):
                    return "invalid_native_crew_headcount"
                if typeof(crew.get("wages_credits", null)) != TYPE_INT or int(crew["wages_credits"]) < 0:
                    return "invalid_native_crew_accrued_wages"
                if not (crew.get("current_task") is String) or str(crew["current_task"]) not in [
                        "idle", "piloting", "engineering", "trading", "loading",
                        "unloading", "eating", "resting", "on_mission"]:
                    return "invalid_native_crew_task"
                for stat in ["hunger", "fatigue", "morale", "health"]:
                    if not (crew.get(stat) is int or crew.get(stat) is float) or not is_finite(float(crew[stat])) or float(crew[stat]) < 0.0 or float(crew[stat]) > 100.0:
                        return "invalid_native_ship_crew_" + stat
                if crew.has("dirty") and typeof(crew["dirty"]) != TYPE_BOOL:
                    return "invalid_native_ship_crew_dirty"
                if not (ship.get("cargo_age", null) is Dictionary):
                    return "missing_native_ship_cargo_age"
                for commodity in ship["cargo_age"]:
                    if not _id(commodity) or typeof(ship["cargo_age"][commodity]) != TYPE_INT or int(ship["cargo_age"][commodity]) < 0:
                        return "invalid_native_ship_cargo_age"
                if not (ship.get("crew_efficiency", null) is float or ship.get("crew_efficiency", null) is int):
                    return "invalid_native_crew_economy_efficiency"
                if not is_finite(float(ship["crew_efficiency"])) or float(ship["crew_efficiency"]) < 0.1 or float(ship["crew_efficiency"]) > 1.0:
                    return "native_crew_efficiency_out_of_bounds"
                if ship.has("crew_skills"):
                    if not (ship["crew_skills"] is Dictionary):
                        return "invalid_native_crew_skills"
                    for skill in ["navigation", "engineering", "trading", "combat"]:
                        if typeof(ship["crew_skills"].get(skill, null)) != TYPE_INT or int(ship["crew_skills"][skill]) < 0 or int(ship["crew_skills"][skill]) > 100:
                            return "invalid_native_ship_crew_skill"

            if ship.has("current_bt") and ship["current_bt"] != null:
                if not (ship["current_bt"] is Dictionary) or not NativeBt.validate(ship["current_bt"]):
                    return "invalid_persisted_native_bt"
            var cid: String = str(ship.get("active_contract_id", ""))
            if not cid.is_empty():
                if not state.has("contract_board") or not (state["contract_board"].get("contracts") is Dictionary):
                    return "orphaned_ship_contract"
                var contracts: Dictionary = state["contract_board"]["contracts"]
                if not contracts.has(cid):
                    return "unknown_ship_contract"
                var linked: Dictionary = contracts[cid]
                if str(linked.get("fulfiller_id", "")) != str(ship_id) or str(linked.get("status", "")) not in ["accepted", "picked_up", "delivered"]:
                    return "stale_ship_contract_assignment"
            if typeof(ship.get("credits", null)) != TYPE_INT or int(ship["credits"]) < 0:
                return "invalid_ship_credits"
            if ship.has("comms_bonus") and (not _fraction(ship["comms_bonus"]) or float(ship["comms_bonus"]) > 0.10):
                return "invalid_native_comms_bonus"
            if ship.has("max_source_cost") and (typeof(ship["max_source_cost"]) != TYPE_INT or int(ship["max_source_cost"]) < 0):
                return "invalid_native_source_purchase_limit"
            var trans: Variant = ship.get("transit", null)
            if not (trans is Dictionary):
                return "invalid_ship_transit"
            if trans.is_empty() and str(ship.get("location", "")).is_empty():
                return "invalid_ship_location"
            var dock_id: String = str(ship.get("docked_at", ""))
            if not dock_id.is_empty():
                if not trans.is_empty() or not state["facilities"].has(dock_id):
                    return "invalid_ship_docked_at"
                var dock_fac: Dictionary = state["facilities"][dock_id]
                if str(ship["location"]) != str(dock_fac.get("location", "")):
                    return "invalid_ship_dock_location"
                if typeof(dock_fac.get("docking_capacity", null)) != TYPE_INT:
                    return "missing_dock_capacity"
                dock_occupancy[dock_id] = int(dock_occupancy.get(dock_id, 0)) + 1
                if int(dock_occupancy[dock_id]) > int(dock_fac["docking_capacity"]):
                    return "dock_capacity_exceeded"
            if not trans.is_empty():
                for key in ["last_tick", "departure_tick", "arrival_tick", "token"]:
                    if typeof(trans.get(key, null)) != TYPE_INT:
                        return "invalid_ship_transit_tick"
                if int(trans["token"]) < 1:
                    return "invalid_ship_transit_token"
                max_token = maxi(max_token, int(trans["token"]))
            rows.append(ship.duplicate(true))
        if int(state["ship_next_token"]) <= max_token or not fleet.restore(rows):
            return "invalid_ship_state"
    elif state.has("ship_next_token"):
        return "orphaned_ship_transit_nonce"
    for receipt_key in ["dock_receipts", "cargo_receipts"]:
        for op in state.get(receipt_key, {}):
            var receipt: Variant = state[receipt_key][op]
            if not _id(op) or not (receipt is Dictionary) or str(receipt.get("operation_id", "")) != str(op):
                return "invalid_fleet_receipt_identity"
            if typeof(receipt.get("tick", null)) != TYPE_INT or int(receipt["tick"]) < 0:
                return "invalid_fleet_receipt_tick"
    for op in state.get("dock_receipts", {}):
        if state.get("cargo_receipts", {}).has(op):
            return "duplicate_fleet_receipt"
    # ContractBoard and escrow balances are a single optional P2 component.
    # Older saves can lack both. Never accept a half-funded board.
    if state.has("contract_board") != state.has("escrow_balances"):
        return "partial_contract_authority"
    if state.has("contract_board"):
        if not (state["contract_board"] is Dictionary) or not (state["escrow_balances"] is Dictionary):
            return "invalid_contract_state"
        var board: Dictionary = state["contract_board"]
        if typeof(board.get("version", null)) != TYPE_INT or int(board["version"]) != 1:
            return "invalid_contract_board_version"
        if not (board.get("contracts") is Dictionary) or not (board.get("receipt_claims") is Dictionary):
            return "invalid_contract_board"
        var contracts: Dictionary = board["contracts"]
        var escrows: Dictionary = state["escrow_balances"]
        if contracts.size() != escrows.size():
            return "contract_escrow_cardinality_mismatch"
        for id in contracts:
            if not _id(id) or not (contracts[id] is Dictionary):
                return "invalid_contract_row"
            var c: Dictionary = contracts[id]
            var account: String = "escrow:" + str(id)
            if c.get("id") != id or str(c.get("escrow_account", "")) != account:
                return "invalid_contract_escrow_id"
            if typeof(c.get("reserved", null)) != TYPE_INT or int(c["reserved"]) < 0:
                return "invalid_contract_reserve"
            if not escrows.has(account) or typeof(escrows[account]) != TYPE_INT:
                return "invalid_contract_escrow_balance"
            if int(escrows[account]) != int(c["reserved"]):
                return "contract_escrow_balance_mismatch"
        for account in escrows:
            if not _id(account) or not str(account).begins_with("escrow:"):
                return "invalid_escrow_account"
            if not contracts.has(str(account).substr(7)):
                return "orphaned_escrow_account"
    # N152 native administrative removal records are historical source
    # snapshots, NOT second ship/facility registries. Every record must
    # name one gone actor and one auditable N9 wallet-destruction receipt.
    if state.has("native_admin_removals"):
        if not (state["native_admin_removals"] is Dictionary):
            return "invalid_native_admin_history"
        for operation_id in state["native_admin_removals"]:
            var row: Variant = state["native_admin_removals"][operation_id]
            if not (row is Dictionary):
                return "invalid_native_admin_row"
            var kind: String = str(row.get("kind", ""))
            var id: String = str(row.get("id", ""))
            var expected_id: String = "admin:" + kind + ":" + id + ":remove"
            if kind not in ["ship", "facility"] or not _id(id) or str(operation_id) != expected_id or str(row.get("ledger_receipt", "")) != expected_id:
                return "invalid_native_admin_identity"
            if typeof(row.get("tick", null)) != TYPE_INT or int(row["tick"]) < 0 or typeof(row.get("credits_lost", null)) != TYPE_INT or int(row["credits_lost"]) < 0:
                return "invalid_native_admin_finances"
            if kind == "ship":
                if state.get("ships", {}).has(id) or not (row.get("retirement", null) is Dictionary):
                    return "native_retired_ship_still_live"
                var retirement: Dictionary = row["retirement"]
                for field in ["final_credits", "final_crew_morale", "final_fuel_pct",
                        "broke_strikes", "hoard_strikes", "retired_at_tick"]:
                    if typeof(retirement.get(field, null)) != TYPE_INT:
                        return "invalid_native_retirement_value"
                if str(retirement.get("agent_id", "")) != id or int(retirement["retired_at_tick"]) != int(row["tick"]) or int(retirement["final_credits"]) != int(row["credits_lost"]):
                    return "native_retirement_money_diverged"
            elif state["facilities"].has(id) or not (row.get("retirement", null) is Dictionary):
                return "native_removed_facility_still_live"
    if state.has("research") and not (state["research"] is Dictionary):
        return "invalid_research"
    # N143 + N9 are a single source-grounded optional component. Legacy
    # checkpoints have none of the three fields and never mint treasury on
    # restore. New games include the REAL frozen faction balances.
    var treasury_keys: Array[String] = ["faction_treasuries",
        "research_directors", "research_receipts"]
    var research_fields_present: int = 0
    for field in treasury_keys:
        if state.has(field):
            research_fields_present += 1
    if research_fields_present != 0 and research_fields_present != 3:
        return "partial_native_research_authority"
    if research_fields_present == 3:
        if not (state["faction_treasuries"] is Dictionary) or not (state["research_directors"] is Dictionary) or not (state["research_receipts"] is Dictionary):
            return "invalid_faction_research_authority"
        var treasuries: Dictionary = state["faction_treasuries"]
        var directors: Dictionary = state["research_directors"]
        if treasuries.is_empty() or treasuries.size() != directors.size():
            return "faction_research_identity_mismatch"
        for faction in treasuries:
            if not _id(faction) or typeof(treasuries[faction]) != TYPE_INT or int(treasuries[faction]) < 0:
                return "invalid_native_treasury"
            if not (directors.get(faction) is Dictionary) or not state.get("research", {}).has(faction):
                return "orphaned_native_research_head"
            var head: Dictionary = directors[faction]
            if not (head.get("technologies") is Array) or head["technologies"] != state["research"][faction]:
                return "native_research_history_divergence"
            if typeof(head.get("progress")) != TYPE_INT or int(head["progress"]) < 0 or typeof(head.get("research_required")) != TYPE_INT or int(head["research_required"]) < 0:
                return "invalid_native_research_progress"
            if head.get("last_research_tick") != null and (typeof(head["last_research_tick"]) != TYPE_INT or int(head["last_research_tick"]) < 0):
                return "invalid_native_last_research_tick"
            if not (head.get("profile") is Dictionary) or not (head.get("history") is Array):
                return "missing_native_director_profile"
            var pending: Variant = head.get("research", null)
            if pending != null and not Technology.find(str(pending)).has("work"):
                return "invalid_native_research_target"
            for technology_id in head["technologies"]:
                if not _id(technology_id) or Technology.find(str(technology_id)).is_empty():
                    return "invalid_completed_native_technology"
            if pending != null:
                if head["technologies"].has(str(pending)) or int(head["research_required"]) != Technology.required_work(str(pending)):
                    return "native_target_progress_mismatch"
        var research_receipts: Dictionary = state["research_receipts"]
        for receipt_id in research_receipts:
            var item: Variant = research_receipts[receipt_id]
            if not _id(receipt_id) or not (item is Dictionary):
                return "invalid_paid_research_receipt"
            if str(item.get("receipt_id", "")) != str(receipt_id) or not treasuries.has(str(item.get("faction_id", ""))):
                return "orphaned_paid_research_receipt"
            if typeof(item.get("tick", null)) != TYPE_INT or int(item["tick"]) < 1:
                return "invalid_research_receipt_tick"
    # Construction is a complete optional canonical N154 domain, not
    # a second SiteRegistry. Legacy checkpoints omit all four fields.
    var construction_keys: Array[String] = [
        "construction_sites", "construction_contracts",
        "construction_receipts", "construction_next_db_id"]
    var construction_count: int = 0
    for key in construction_keys:
        if state.has(key):
            construction_count += 1
    if construction_count not in [0, 4]:
        return "partial_native_construction_authority"
    if construction_count == 4:
        if not (state["construction_sites"] is Dictionary) or not (state["construction_contracts"] is Dictionary) or not (state["construction_receipts"] is Dictionary):
            return "invalid_native_construction_registry"
        if typeof(state["construction_next_db_id"]) != TYPE_INT or int(state["construction_next_db_id"]) >= 0:
            return "invalid_native_construction_db_allocator"
        for sid in state["construction_sites"]:
            var site: Variant = state["construction_sites"][sid]
            if not _id(sid) or not (site is Dictionary) or str(site.get("id", "")) != str(sid):
                return "invalid_construction_site_identity"
            for field in ["faction_id", "body_id", "location_name", "commodity",
                    "facility_type", "name"]:
                if not _id(site.get(field, null)):
                    return "invalid_native_site_" + field
            if not state["faction_treasuries"].has(str(site["faction_id"])) or not state["bodies"].has(str(site["body_id"])):
                return "construction_missing_physical_owner"
            # Rust colony::commission registers a ConstructionSite BEFORE
            # any colony dock/market exists. Only an actual colony project
            # with a source station may lack a destination market.
            var is_foundation: bool = site.get("labor", {}) is Dictionary and site["labor"].get("colony_source", null) != null
            if not state["markets"].has(str(site["location_name"])):
                if not is_foundation or str(site["location_name"]) != str(site["body_id"]) + "-colony" or bool(site.get("completed", false)):
                    return "construction_missing_physical_owner"
                var sponsor: String = str(site["labor"].get("colony_source", ""))
                if not state["markets"].has(sponsor):
                    return "colony_foundation_missing_real_sponsor"
                var owner: String = str(state["markets"][sponsor].get("owner", ""))
                if not state["facilities"].has(owner) or str(state["facilities"][owner].get("faction", "")) != str(site["faction_id"]) or str(state["facilities"][owner].get("type", "")) != "station":
                    return "colony_foundation_invalid_sponsor"
                if int(site["progress_delivered"]) != 0 or int(site.get("progress_required", -1)) != 600:
                    return "colony_foundation_invalid_physical_progress"
            for field in ["progress_required", "progress_delivered", "spawned_at_tick"]:
                if typeof(site.get(field, null)) != TYPE_INT or int(site[field]) < 0:
                    return "invalid_native_site_progress"
            if int(site["progress_required"]) <= 0 or int(site["progress_delivered"]) > int(site["progress_required"]):
                return "construction_materials_overfilled"
            if typeof(site.get("completed")) != TYPE_BOOL or not (site.get("labor") is Dictionary):
                return "invalid_native_site_lifecycle"
            var labor: Dictionary = site["labor"]
            for field in ["required", "completed"]:
                if typeof(labor.get(field, null)) != TYPE_INT or int(labor[field]) < 0:
                    return "invalid_native_construction_labor"
            if int(labor["completed"]) > int(labor["required"]):
                return "construction_labor_overfilled"
            if labor.get("last_shift") != null:
                if not (labor["last_shift"] is Dictionary) or typeof(labor["last_shift"].get("tick", null)) != TYPE_INT or not (labor["last_shift"].get("workers") is Array):
                    return "invalid_construction_last_shift"
            if not (site.get("position") is Dictionary):
                return "invalid_construction_site_orbit_position"
            var pos: Dictionary = site["position"]
            for key in ["x", "y"]:
                if not (pos.get(key) is float or pos.get(key) is int) or not is_finite(float(pos[key])):
                    return "invalid_construction_orbit_coordinate"
            if Construction.ready_for_materialization(site) and bool(site["completed"]):
                return "construction_completed_site_not_despawned"
        for cid in state["construction_contracts"]:
            var site_id: Variant = state["construction_contracts"][cid]
            if not _id(cid) or not _id(site_id) or not state["construction_sites"].has(str(site_id)):
                return "invalid_construction_contract_site_link"
            if not state.get("contract_board", {}).get("contracts", {}).has(cid):
                return "orphaned_construction_delivery"
            var c: Dictionary = state["contract_board"]["contracts"][cid]
            var site: Dictionary = state["construction_sites"][site_id]
            if str(c.get("contract_type", "")) != "delivery" or str(c.get("commodity", "")) != str(site["commodity"]) or str(c.get("destination_location", "")) != str(site["location_name"]):
                return "construction_contract_terms_mismatch"
            if str(c.get("requestor_id", "")) != faction_account(str(site["faction_id"])):
                return "construction_contract_payer_mismatch"
        for receipt_id in state["construction_receipts"]:
            if not _id(receipt_id) or not (state["construction_receipts"][receipt_id] is Dictionary):
                return "invalid_construction_receipt"
            if str(state["construction_receipts"][receipt_id].get("id", "")) != str(receipt_id):
                return "invalid_construction_receipt_identity"
            var construction_receipt: Dictionary = state["construction_receipts"][receipt_id]
            if str(construction_receipt.get("kind", "")) == "colony_dock_prepared":
                var prepared_site: String = str(construction_receipt.get("site_id", ""))
                var prepared_id: String = str(construction_receipt.get("facility_id", ""))
                var prepared_pop: String = str(construction_receipt.get("population_id", ""))
                var planned: Dictionary = state["construction_sites"].get(prepared_site, {})
                var prepared_facility: Dictionary = state["facilities"].get(prepared_id, {})
                var prepared_household: Dictionary = state["populations"].get(prepared_pop, {})
                if planned.is_empty() or prepared_facility.is_empty() or prepared_household.is_empty():
                    return "n151_temporary_dock_missing_live_actors"
                if str(receipt_id) != "n151_colony_dock:" + prepared_site or (
                        str(construction_receipt.get("destination_location", "")) != str(planned.get("location_name", "")) or
                        str(prepared_facility.get("location", "")) != str(planned.get("location_name", "")) or
                        str(prepared_facility.get("type", "")) != "construction_dock" or
                        str(prepared_household.get("colony_dock_id", "")) != prepared_id or
                        str(prepared_household.get("construction_source_site_id", "")) != prepared_site or
                        typeof(construction_receipt.get("tick", null)) != TYPE_INT or
                        int(construction_receipt["tick"]) < int(planned.get("spawned_at_tick", 0)) or
                        typeof(construction_receipt.get("native_db_id", null)) != TYPE_INT or
                        int(construction_receipt["native_db_id"]) >= 0 or
                        int(prepared_facility.get("native_db_id", 0)) != int(construction_receipt["native_db_id"]) or
                        int(prepared_household.get("native_db_id", 0)) != int(construction_receipt["native_db_id"]) or
                        int(construction_receipt.get("population_count", -1)) != 0 or
                        int(construction_receipt.get("credits", -1)) != 0):
                    return "n151_invalid_source_dock_preparation_proof"
            if str(construction_receipt.get("kind", "")) == "colony_approved":
                if typeof(construction_receipt.get("tick", null)) != TYPE_INT or int(construction_receipt["tick"]) < 1:
                    return "invalid_native_colony_approval_tick"
                if int(construction_receipt.get("capital", -1)) != 0 or str(construction_receipt.get("n9_receipt_id", "invalid")) != "":
                    return "native_colony_approval_cannot_mint_credits"
                if not _id(construction_receipt.get("site_id", null)) or not _id(construction_receipt.get("body_id", null)) or not _id(construction_receipt.get("source_location", null)):
                    return "invalid_native_colony_approval_identity"
                var active_site: Dictionary = state["construction_sites"].get(str(construction_receipt["site_id"]), {})
                if not active_site.is_empty():
                    if str(active_site.get("body_id", "")) != str(construction_receipt["body_id"]) or str(active_site.get("location_name", "")) != str(construction_receipt.get("destination_location", "")) or str(active_site.get("labor", {}).get("colony_source", "")) != str(construction_receipt["source_location"]):
                        return "native_colony_approval_site_diverged"
    if state.has("location_tiers") and not (state["location_tiers"] is Dictionary):
        return "invalid_location_tiers"
    if state.has("native_planner_mode") or state.has("native_planner_records") or state.has("native_execution"):
        if not state.has("native_planner_mode") or not state.has("native_planner_records") or not state.has("native_planner_last_tick") or not state.has("native_execution"):
            return "incomplete_native_n100_n98_n121_state"
        if str(state["native_planner_mode"]) not in ["legacy", "htn", "hybrid"]:
            return "invalid_native_planner_mode"
        if not (state["native_planner_records"] is Dictionary) or typeof(state["native_planner_last_tick"]) != TYPE_INT or int(state["native_planner_last_tick"]) < 0:
            return "invalid_native_n100_plan_cursor"
        if not (state["native_execution"] is Dictionary) or not SourceExecution.validate(state["native_execution"]):
            return "invalid_native_n121_execution_state"
        for faction in state["native_planner_records"]:
            if not state.get("faction_treasuries", {}).has(faction):
                return "n100_plan_for_unknown_faction"
            var record: Variant = state["native_planner_records"][faction]
            if not (record is Dictionary):
                return "invalid_native_n100_record"
            if str(record.get("faction_id", "")) != str(faction) or typeof(record.get("tick", null)) != TYPE_INT or int(record["tick"]) < 1 or int(record["tick"]) > int(state["native_planner_last_tick"]):
                return "invalid_native_n100_plan_time"
            if typeof(record.get("source_snapshot_tick", null)) != TYPE_INT or int(record["source_snapshot_tick"]) != int(record["tick"]):
                return "invalid_native_n100_source_time"
            if str(record.get("status", "")) == "n98_planned_not_dispatched":
                for part in ["goal", "plan", "ledger"]:
                    if not (record.get(part) is Dictionary):
                        return "missing_original_n100_plan"
                if not (record.get("actions") is Array):
                    return "missing_original_n100_actions"
                var ledger: Dictionary = record["ledger"]
                if typeof(ledger.get("schema_version", null)) != TYPE_INT or int(ledger["schema_version"]) != 1 or str(ledger.get("faction_id", "")) != str(faction):
                    return "invalid_native_n98_ledger_identity"
                if str(ledger.get("goal_id", "")) != str(record["goal"].get("goal_id", "")) or str(ledger.get("planner_id", "")) != str(record["plan"].get("planner_id", "")):
                    return "native_n100_n98_goal_disagreement"
                if not (ledger.get("steps") is Array) or ledger["steps"].is_empty():
                    return "missing_native_n98_steps"
                for entry in ledger["steps"]:
                    if not (entry is Dictionary) or str(entry.get("phase", "")) != "planned" or str(entry.get("native_order_id", "")) != "":
                        return "native_n100_preempted_n121_without_receipt"
                    if typeof(entry.get("updated_tick", null)) != TYPE_INT or int(entry["updated_tick"]) != int(record["tick"]) or not (entry.get("step") is Dictionary):
                        return "invalid_native_n98_step_cursor"
    # Source N121 dispatch IDs belong to one REAL canonical N104 board.
    # No second indexed contract authority or off-ledger faction escrow.
    if state.has("native_htn_contracts") != state.has("native_htn_next_id"):
        return "partial_native_n121_contract_identity"
    if state.has("native_htn_contracts"):
        if not (state["native_htn_contracts"] is Dictionary) or typeof(state["native_htn_next_id"]) != TYPE_INT or int(state["native_htn_next_id"]) < 1:
            return "invalid_native_n121_contract_serial"
        var native_ids: Dictionary = {}
        var seen_dispatch: Dictionary = {}
        for contract_id in state["native_htn_contracts"]:
            var meta: Variant = state["native_htn_contracts"][contract_id]
            var contract: Variant = state.get("contract_board", {}).get("contracts", {}).get(contract_id, null)
            if not (meta is Dictionary) or not (contract is Dictionary):
                return "n121_orphaned_real_n104_contract"
            var faction: String = str(meta.get("faction_id", ""))
            var key: String = str(meta.get("dispatch_key", ""))
            if faction.is_empty() or key.is_empty() or seen_dispatch.has(key) or not state.get("faction_treasuries", {}).has(faction):
                return "n121_duplicate_or_foreign_native_dispatch"
            seen_dispatch[key] = true
            if str(meta.get("plan_id", "")).is_empty() or str(meta.get("step_id", "")).is_empty() or typeof(meta.get("tick", null)) != TYPE_INT or int(meta["tick"]) < 1:
                return "n121_malformed_original_step_receipt"
            if (str(contract.get("contract_type", "")) != "delivery" or
                    str(contract.get("funding_source", "")) != "faction" or
                    str(contract.get("requestor_id", "")) != "faction/" + faction or
                    str(contract.get("native_htn_key", "")) != key or
                    str(contract.get("escrow_account", "")) != "escrow:" + str(contract_id) or
                    str(contract.get("mission_category", "")) != "strategy.logistics.v1"):
                return "n121_forbidden_parallel_contract_authority"
            var identifier: String = str(contract_id)
            if not identifier.begins_with("n121-") or not identifier.substr(5).is_valid_int():
                return "n121_invalid_original_order_serial"
            var number: int = int(identifier.substr(5))
            if number < 1 or number >= int(state["native_htn_next_id"]) or native_ids.has(number):
                return "n121_duplicate_or_future_order"
            native_ids[number] = true
        var source_execution: Dictionary = state.get("native_execution", {})
        for active_id in source_execution.get("active", {}):
            var plan: Variant = source_execution["active"][active_id]
            if not state.get("faction_treasuries", {}).has(active_id) or not (plan is Dictionary) or not (plan.get("ledger") is Dictionary):
                return "n121_orphaned_original_active_plan"
            var ledger: Dictionary = plan["ledger"]
            if str(ledger.get("faction_id", "")) != str(active_id) or not (ledger.get("steps") is Array) or str(ledger.get("plan_id", "")).is_empty():
                return "n121_invalid_original_active_plan_identity"
            var record: Dictionary = state.get("native_planner_records", {}).get(active_id, {})
            if str(record.get("status", "")) != "n121_active" or str(record.get("ledger", {}).get("plan_id", "")) != str(ledger["plan_id"]):
                return "n121_active_plan_outside_authoritative_n39"
            for step in ledger["steps"]:
                if not (step is Dictionary) or typeof(step.get("updated_tick", null)) != TYPE_INT:
                    return "n121_invalid_real_n98_step_tick"
                var phase: String = str(step.get("phase", ""))
                if phase not in ["planned", "prepared", "submitted", "running", "succeeded", "failed", "cancelled"]:
                    return "n121_unknown_native_n98_phase"
                if phase in ["submitted", "running", "succeeded", "failed"]:
                    var order: String = str(step.get("native_order_id", ""))
                    if order.begins_with("n121-"):
                        var evidence: Dictionary = state["native_htn_contracts"].get(order, {})
                        if str(evidence.get("plan_id", "")) != str(ledger["plan_id"]) or str(evidence.get("step_id", "")) != str(step.get("step", {}).get("step_id", "")):
                            return "n121_n98_step_not_paid_by_n104"
    if state.has("station_executing") and typeof(state["station_executing"]) != TYPE_BOOL:
        return "invalid_station_phase"
    # Source N18 one administrator per (faction, location). Retention
    # memory and its tick cursor belong to the SAME N39/N38 world; they
    # may be omitted only on genuinely old, non-executing checkpoints.
    if state.has("station_administration") != state.has("station_administration_last_tick"):
        return "partial_native_station_administration"
    if bool(state.get("station_executing", false)) and not state.has("station_administration"):
        return "native_station_execution_without_persisted_admin"
    if state.has("station_administration"):
        if not (state["station_administration"] is Dictionary) or typeof(state["station_administration_last_tick"]) != TYPE_INT or int(state["station_administration_last_tick"]) < 0:
            return "invalid_native_administrator_cursor"
        for key in state["station_administration"]:
            var saved: Variant = state["station_administration"][key]
            if not (key is String) or not (saved is Dictionary):
                return "invalid_native_administrator_record"
            if int(saved.get("version", -1)) != 1 or not (saved.get("last_plan") is Dictionary) or not (saved.get("retained") is Dictionary) or not (saved.get("producer") is Dictionary):
                return "invalid_native_administrator_snapshot"
            if typeof(saved.get("last_plan_tick", null)) != TYPE_INT or int(saved["last_plan_tick"]) < 0 or int(saved["last_plan_tick"]) > int(state["station_administration_last_tick"]):
                return "invalid_native_administrator_plan_time"
            var view: Dictionary = saved["last_plan"]
            if str(view.get("faction_id", "")) + "|" + str(view.get("location", "")) != str(key):
                return "native_administrator_wrong_station"
            if not state.get("faction_treasuries", {}).has(str(view.get("faction_id", ""))) or not state["markets"].has(str(view.get("location", ""))):
                return "native_administrator_unknown_faction_or_station"
            for fid in saved["retained"]:
                if not state["facilities"].has(fid) or typeof(saved["retained"][fid]) != TYPE_BOOL:
                    return "native_administrator_retained_foreign_facility"
    for id in state["facilities"]:
        if not _id(id) or not (state["facilities"][id] is Dictionary):
            return "invalid_facility"
        var fac: Dictionary = state["facilities"][id]
        for key in ["type", "faction", "location", "body_id"]:
            if not _id(fac.get(key, null)):
                return "invalid_facility_" + key
        if fac.has("docking_capacity") and (typeof(fac["docking_capacity"]) != TYPE_INT or int(fac["docking_capacity"]) < 0):
            return "invalid_facility_docking_capacity"
        if fac.has("native_db_id") and (typeof(fac["native_db_id"]) != TYPE_INT or int(fac["native_db_id"]) >= 0 or not _id(fac.get("construction_source_site_id", null))):
            return "invalid_materialized_native_facility"
        for key in ["crew_count", "level", "xp", "credits"]:
            if typeof(fac.get(key, null)) != TYPE_INT or int(fac[key]) < 0:
                return "invalid_facility_" + key
        if int(fac["level"]) < 1 or int(fac["level"]) > 10 or int(fac["crew_count"]) > 65535:
            return "invalid_facility_level_or_crew"
        if typeof(fac.get("abandoned", null)) != TYPE_BOOL:
            return "invalid_abandoned"
        # Fuel/Tools reserves belong to this facility, never to a market.
        # Older checkpoints may omit this optional source component; their
        # actual owned inventory is then empty, NOT borrowed market stock.
        var owned: Variant = fac.get("reserves", {})
        if not (owned is Dictionary) or Inventory.validate(owned) != "":
            return "invalid_facility_owned_reserves"
        if fac.has("condition") and (not _fraction(fac["condition"]) or float(fac["condition"]) > 1.0):
            return "invalid_facility_condition"
        if fac.has("abandon_counter") and (typeof(fac["abandon_counter"]) != TYPE_INT or int(fac["abandon_counter"]) < 0 or int(fac["abandon_counter"]) > 4294967295):
            return "invalid_facility_abandon_counter"
        var morale: Variant = fac.get("morale", null)
        if not _fraction(morale) or float(morale) > 100.0:
            return "invalid_morale"
        for key in ["fitting_output_mult"]:
            if fac.has(key) and (not _fraction(fac[key]) or float(fac[key]) <= 0.0):
                return "invalid_fitting"
        if fac.has("fitting_batches_bonus") and (typeof(fac["fitting_batches_bonus"]) != TYPE_INT or int(fac["fitting_batches_bonus"]) < 0):
            return "invalid_fitting_batches"
        # Real N154 shipyards store manufactured modules on the actual
        # FacilityOperations, not in the adjacent public Market supply.
        if fac.has("module_stock"):
            if str(fac["type"]) != "shipyard" or not (fac["module_stock"] is Dictionary):
                return "invalid_native_shipyard_module_owner"
            var module_state: Dictionary = fac["module_stock"]
            if not (module_state.get("stock") is Dictionary) or typeof(module_state.get("dirty", null)) != TYPE_BOOL:
                return "invalid_native_module_stock"
            for slug in module_state["stock"]:
                var units: Variant = module_state["stock"][slug]
                if not ShipyardRecipes.RECIPES.has(slug) or typeof(units) != TYPE_INT or int(units) < 0 or int(units) > 4294967295:
                    return "unknown_native_module_stock_entry"
        if fac.has("assigned_workers") and (typeof(fac["assigned_workers"]) != TYPE_INT or int(fac["assigned_workers"]) < 0):
            return "invalid_station_assignment"
        if fac.has("lod_divisor") and (typeof(fac["lod_divisor"]) != TYPE_INT or int(fac["lod_divisor"]) < 1):
            return "invalid_lod_divisor"
        if fac.has("lod_next_tick") and (typeof(fac["lod_next_tick"]) != TYPE_INT or int(fac["lod_next_tick"]) < 0):
            return "invalid_lod_cursor"
        if fac.has("work_shift"):
            var shift: Variant = fac["work_shift"]
            if not (shift is Dictionary):
                return "invalid_work_shift"
            if not shift.is_empty():
                if typeof(shift.get("tick", null)) != TYPE_INT or int(shift["tick"]) < 0 or not (shift.get("workers") is Dictionary):
                    return "invalid_work_shift"
                for pid in shift["workers"]:
                    if not _id(pid) or typeof(shift["workers"][pid]) != TYPE_INT or int(shift["workers"][pid]) <= 0:
                        return "invalid_work_shift_workers"
        if not state["markets"].has(str(fac["location"])):
            # Exact Rust engine/colony.rs::prepare_docks permits an EMPTY
            # construction_dock for an approved, unfinished colony site.
            # This dock has NO Market and cannot be used as a warehouse.
            var site_ref: String = str(fac.get("construction_source_site_id", ""))
            var founding: Dictionary = state.get("construction_sites", {}).get(site_ref, {})
            var dock_proof: Dictionary = state.get("construction_receipts", {}).get(
                "n151_colony_dock:" + site_ref, {})
            if str(fac["type"]) != "construction_dock" or founding.is_empty() or (
                    str(founding.get("location_name", "")) != str(fac["location"]) or
                    str(founding.get("body_id", "")) != str(fac["body_id"]) or
                    str(founding.get("faction_id", "")) != str(fac["faction"]) or
                    bool(founding.get("completed", false)) or
                    str(dock_proof.get("kind", "")) != "colony_dock_prepared" or
                    str(dock_proof.get("facility_id", "")) != str(id) or
                    int(dock_proof.get("native_db_id", 0)) != int(fac.get("native_db_id", -1)) or
                    int(fac.get("credits", -1)) != 0 or
                    int(fac.get("crew_count", -1)) != 0 or
                    int(fac.get("docking_capacity", -1)) != 4):
                return "unapproved_marketless_colony_dock"

    for location in state["markets"]:
        if not _id(location) or not (state["markets"][location] is Dictionary):
            return "invalid_market"
        var market: Dictionary = state["markets"][location]
        if not _id(market.get("owner", null)) or not state["facilities"].has(market["owner"]):
            return "missing_market_owner"
        var owner: Dictionary = state["facilities"][market["owner"]]
        if str(owner["location"]) != str(location):
            return "remote_market_owner"
        if not (market.get("supply") is Dictionary) or not (market.get("prices") is Dictionary):
            return "invalid_market_data"
        var limits: Variant = market.get("limits", {})
        if not (limits is Dictionary) or Inventory.validate(market["supply"], limits) != "":
            return "invalid_market_inventory"
        for commodity in market["prices"]:
            if not Inventory.valid_amount(market["prices"][commodity]):
                return "invalid_market_price"
    # N104 physical passengers carry people and real N9 wealth between stations.
    if state.has("passenger_manifests") != state.has("passenger_receipts"):
        return "partial_passenger_authority"
    if state.has("passenger_manifests"):
        var manifests: Variant = state["passenger_manifests"]
        var receipts: Variant = state["passenger_receipts"]
        if not (manifests is Dictionary and receipts is Dictionary):
            return "invalid_passenger_registries"
        for cid in manifests:
            var m: Variant = manifests[cid]
            var c: Dictionary = state.get("contract_board", {}).get("contracts", {}).get(cid, {})
            if not (m is Dictionary) or str(c.get("contract_type", "")) != "passenger":
                return "orphaned_passenger_manifest"
            var phase: String = str(m.get("phase", ""))
            var quantity: int = int(m.get("quantity", 0))
            var carried: int = int(m.get("wealth", -1))
            if phase not in ["embarked", "delivered"] or quantity <= 0 or quantity != int(c.get("quantity", -1)) or carried < 0 or int(m.get("initial_wealth", -1)) < carried:
                return "invalid_passenger_manifest_values"
            if str(m.get("ship_id", "")) != str(c.get("fulfiller_id", "")) or (phase == "embarked" and not state.get("ships", {}).has(str(m.get("ship_id", "")))) or not state["populations"].has(str(m.get("origin_population_id", ""))):
                return "invalid_passenger_manifest_actor"
            var boarding_id: String = "passenger:" + str(cid) + ":embark"
            if str(c.get("picked_up_receipt", "")) != boarding_id or str(receipts.get(boarding_id, {}).get("action", "")) != "load":
                return "passenger_missing_original_boarding"
            if phase == "embarked":
                if str(c.get("status", "")) != "picked_up" or not (c.get("embarked", null) is Dictionary) or int(c["embarked"].get("wealth", -1)) != int(m["wealth"]):
                    return "passenger_manifest_not_in_flight"
            else:
                var landing_id: String = "passenger:" + str(cid) + ":delivery"
                if str(c.get("status", "")) != "paid" or carried != 0 or str(c.get("delivered_receipt", "")) != landing_id or str(receipts.get(landing_id, {}).get("action", "")) != "unload" or not state["populations"].has(str(m.get("destination_population_id", ""))):
                    return "passenger_missing_paid_disembarkation"
        for receipt_id in receipts:
            var proof: Variant = receipts[receipt_id]
            if not (proof is Dictionary) or str(proof.get("kind", "")) != "passenger" or str(proof.get("operation_id", "")) != str(receipt_id) or not manifests.has(str(proof.get("contract_id", ""))):
                return "orphaned_passenger_receipt"
    for id in state["populations"]:
        if not _id(id) or not (state["populations"][id] is Dictionary):
            return "invalid_population"
        var pop: Dictionary = state["populations"][id]
        if not _id(pop.get("faction", null)) or not _id(pop.get("location", null)):
            return "invalid_population_identity"
        if typeof(pop.get("count", null)) != TYPE_INT or int(pop["count"]) < 0:
            return "invalid_population_count"
        if typeof(pop.get("wealth", null)) != TYPE_INT or int(pop["wealth"]) < 0:
            return "invalid_household_balance"
        if not state["markets"].has(str(pop["location"])):
            var site_ref: String = str(pop.get("construction_source_site_id", ""))
            var dock_id: String = str(pop.get("colony_dock_id", ""))
            var house_proof: Dictionary = state.get("construction_receipts", {}).get(
                "n151_colony_dock:" + site_ref, {})
            var home_dock: Dictionary = state["facilities"].get(dock_id, {})
            var home_site: Dictionary = state.get("construction_sites", {}).get(site_ref, {})
            if str(pop.get("demographic", "")) != "workers" or (
                    home_dock.is_empty() or home_site.is_empty() or
                    str(home_dock.get("type", "")) != "construction_dock" or
                    str(home_dock.get("location", "")) != str(pop["location"]) or
                    str(home_site.get("location_name", "")) != str(pop["location"]) or
                    str(home_site.get("faction_id", "")) != str(pop["faction"]) or
                    str(home_dock.get("faction", "")) != str(pop["faction"]) or
                    str(house_proof.get("population_id", "")) != str(id) or
                    str(house_proof.get("facility_id", "")) != dock_id or
                    int(pop.get("native_db_id", 0)) != int(home_dock.get("native_db_id", -1))):
                return "unapproved_marketless_colony_household"
        if pop.has("employed_fraction") and (not _fraction(pop["employed_fraction"]) or float(pop["employed_fraction"]) > 1.0):
            return "invalid_employment"
    # N151 native abstract migration has ONE persisted event and, when
    # wealth > 0, ONE corresponding immutable N9 household transfer.
    # Old saves without this optional metadata stay valid.
    if state.has("population_migration_last"):
        if not (state["population_migration_last"] is Dictionary):
            return "invalid_native_migration_record"
        var event: Dictionary = state["population_migration_last"]
        var origin: String = str(event.get("source_id", ""))
        var destination: String = str(event.get("destination_id", ""))
        if origin == destination or not state["populations"].has(origin) or not state["populations"].has(destination):
            return "invalid_native_migration_endpoints"
        if typeof(event.get("tick", null)) != TYPE_INT or int(event["tick"]) <= 0 or typeof(event.get("count", null)) != TYPE_INT or int(event["count"]) < 1 or int(event["count"]) > 100:
            return "invalid_native_migration_count_or_tick"
        if typeof(event.get("wealth_transferred", null)) != TYPE_INT or int(event["wealth_transferred"]) < 0 or not (event.get("receipt_id", null) is String):
            return "invalid_native_migration_money"
        if (int(event["wealth_transferred"]) == 0) != str(event["receipt_id"]).is_empty():
            return "invalid_native_migration_receipt_link"
        if str(event.get("source_location", "")) != str(state["populations"][origin]["location"]) or str(event.get("destination_location", "")) != str(state["populations"][destination]["location"]):
            return "invalid_native_migration_location"
    for id in state["bodies"]:
        if not _id(id) or not (state["bodies"][id] is Dictionary):
            return "invalid_body"
        var body: Dictionary = state["bodies"][id]
        if not (body.get("resources") is Dictionary) or Inventory.validate(body["resources"]) != "":
            return "invalid_body_resources"
    if state.has("research"):
        for faction in state["research"]:
            if not _id(faction) or not (state["research"][faction] is Array):
                return "invalid_technologies"
            for tech in state["research"][faction]:
                if not _id(tech):
                    return "invalid_technology"
    if state.has("location_tiers"):
        for faction in state["location_tiers"]:
            if not _id(faction) or not (state["location_tiers"][faction] is Dictionary):
                return "invalid_tiers"
            for location in state["location_tiers"][faction]:
                var tier: Variant = state["location_tiers"][faction][location]
                if not _id(location) or typeof(tier) != TYPE_INT or int(tier) < 1 or int(tier) > 4:
                    return "invalid_tier"
    # N150 original faction-relations matrix is empty at fresh seed.
    # Old N38 saves may omit it; no silent diplomatic reinitialization.
    if state.has("faction_relations") != state.has("faction_relations_last_tick"):
        return "half_present_native_faction_relations"
    if state.has("faction_relations"):
        if not (state["faction_relations"] is Dictionary) or not NativeRelations.validate_pairs(state["faction_relations"]):
            return "invalid_native_faction_relations"
        if typeof(state["faction_relations_last_tick"]) != TYPE_INT or int(state["faction_relations_last_tick"]) < 0:
            return "invalid_native_relations_tick"
        var owners: Dictionary = state.get("faction_treasuries", {})
        for pair in state["faction_relations"].values():
            if not owners.has(str(pair.get("a", ""))) or not owners.has(str(pair.get("b", ""))):
                return "phantom_native_relation_faction"
    # Frozen Rust BodyTerritory defaults exist even before first
    # faction-cycle recomputation. Older saves lacking both keys remain
    # compatible; never fill them with fabricated territorial claims.
    if state.has("body_territory") != state.has("territory_last_tick"):
        return "half_present_native_body_territory"
    if state.has("body_territory"):
        if not (state["body_territory"] is Dictionary) or typeof(state["territory_last_tick"]) != TYPE_INT or int(state["territory_last_tick"]) < 0:
            return "invalid_native_territory_clock"
        if state["body_territory"].size() != state["bodies"].size():
            return "missing_native_body_territory"
        for body in state["body_territory"]:
            if not state["bodies"].has(body) or not (state["body_territory"][body] is Dictionary):
                return "foreign_native_body_territory"
            var row: Dictionary = state["body_territory"][body]
            if not row.has("controlling_faction") or not row.has("contested") or typeof(row["contested"]) != TYPE_BOOL:
                return "invalid_native_body_control"
            var controlling: Variant = row["controlling_faction"]
            if controlling != null and (not (controlling is String) or not state.get("faction_treasuries", {}).has(controlling)):
                return "native_territory_has_phantom_owner"
            if bool(row["contested"]) and controlling == null:
                return "native_contested_body_without_controller"
    # N129 tax, bailout and targeted relief share one persisted
    # phase cursor, so restoring a checkpoint cannot pay twice.
    if state.has("faction_finance_last_tick"):
        if typeof(state["faction_finance_last_tick"]) != TYPE_INT or int(state["faction_finance_last_tick"]) < 0:
            return "invalid_native_faction_finance_cursor"
    if Recipes.validate() != "":
        return "native_recipes_unavailable"
    return ""

static func accounts(state: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for id in state["facilities"]:
        result[facility_account(str(id))] = int(state["facilities"][id]["credits"])
    for id in state["populations"]:
        result[household_account(str(id))] = int(state["populations"][id]["wealth"])
    for id in state.get("ships", {}):
        result[ship_account(str(id))] = int(state["ships"][id]["credits"])
    for faction in state.get("faction_treasuries", {}):
        result[faction_account(str(faction))] = int(state["faction_treasuries"][faction])
    for escrow in state.get("escrow_balances", {}):
        result[str(escrow)] = int(state["escrow_balances"][escrow])
    for cid in state.get("passenger_manifests", {}):
        result["passengers/" + str(cid)] = int(state["passenger_manifests"][cid]["wealth"])
    return result

static func facility_account(id: String) -> String:
    return "facility/" + id

static func household_account(id: String) -> String:
    return "population/" + id

static func faction_account(id: String) -> String:
    return "faction/" + id

static func ship_account(id: String) -> String:
    return "ship:" + id


static func has_tech(state: Dictionary, faction: String, tech: String) -> bool:
    var researched: Variant = state.get("research", {}).get(faction, [])
    return researched is Array and researched.has(tech)

static func tier_at(state: Dictionary, faction: String, location: String) -> int:
    var tiers: Variant = state.get("location_tiers", {}).get(faction, {})
    return int(tiers.get(location, 1)) if tiers is Dictionary else 1

static func _id(value: Variant) -> bool:
    return value is String and not value.is_empty()

static func _fraction(value: Variant) -> bool:
    return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)) and float(value) >= 0.0
