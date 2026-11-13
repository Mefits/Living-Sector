extends RefCounted
## N39 / Rust Galaxy 0.6.7 physical production snapshot.
## This is a read/validate boundary, NOT another world/ledger implementation.
## The caller must supply real market, facility, population and body snapshots.
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Technology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const Construction = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")

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
        if not (state["ships"] is Dictionary) or state["ships"].is_empty():
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
            if not state["faction_treasuries"].has(str(site["faction_id"])) or not state["bodies"].has(str(site["body_id"])) or not state["markets"].has(str(site["location_name"])):
                return "construction_missing_physical_owner"
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
    if state.has("location_tiers") and not (state["location_tiers"] is Dictionary):
        return "invalid_location_tiers"
    if state.has("station_executing") and typeof(state["station_executing"]) != TYPE_BOOL:
        return "invalid_station_phase"
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
            return "missing_facility_market"
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
        if pop.has("employed_fraction") and (not _fraction(pop["employed_fraction"]) or float(pop["employed_fraction"]) > 1.0):
            return "invalid_employment"
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
