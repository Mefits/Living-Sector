extends RefCounted
## N39 / Rust Galaxy 0.6.7 physical production snapshot.
## This is a read/validate boundary, NOT another world/ledger implementation.
## The caller must supply real market, facility, population and body snapshots.
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

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
    for escrow in state.get("escrow_balances", {}):
        result[str(escrow)] = int(state["escrow_balances"][escrow])
    return result

static func facility_account(id: String) -> String:
    return "facility/" + id

static func household_account(id: String) -> String:
    return "population/" + id

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
