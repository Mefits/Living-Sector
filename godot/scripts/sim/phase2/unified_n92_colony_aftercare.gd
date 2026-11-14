extends RefCounted
## Miro Chat2 B4: native/crates/sim_core/src/strategy/
## colony_development.rs::observe/next_supply_goal -> coordination.rs.
## Pure source projection of ACTUAL N39 World; no phantom stock, crew,
## market, shipyard hull, money, migration or N104 order.
const N92 = preload("res://scripts/ported/n92_colony_development.gd")

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _outstanding(c: Dictionary) -> bool:
    return str(c.get("status", "")) in [
        "posted", "accepted", "picked_up", "delivered"]

## FactionData/ColonyView from the SAME World. P1 N92.observe is the
## source port of original Rust; never supply a made-up colony footprint.
static func observe(world: Dictionary) -> Dictionary:
    for key in ["facilities", "markets", "populations",
            "contract_board", "faction_treasuries"]:
        if not (world.get(key) is Dictionary):
            return _fail("b4_missing_original_n39_" + key)
    var board: Dictionary = world["contract_board"].get("contracts", {})
    if not (board is Dictionary):
        return _fail("b4_missing_original_n104")
    var contracts: Array = []
    var cids: Array = board.keys()
    cids.sort()
    for cid in cids:
        var contract: Dictionary = board[cid]
        var status: String = str(contract.get("status", ""))
        var qty: int = int(contract.get("quantity", 0))
        if status not in ["posted", "accepted", "picked_up",
                "delivered", "paid", "expired"] or qty < 1:
            return _fail("b4_invalid_original_n104_contract")
        contracts.append({
            "id": str(cid), "destination": str(contract.get(
                "destination_location", "")),
            "commodity": str(contract.get("commodity", "")),
            "type": str(contract.get("contract_type", "")),
            "outstanding": _outstanding(contract)})
    var colony_inputs: Array = []
    var stations: Array = world["facilities"].keys()
    stations.sort()
    for fid in stations:
        var station: Dictionary = world["facilities"][fid]
        var location: String = str(station.get("location", ""))
        if str(station.get("type", "")) != "station" or (
                not location.ends_with("-colony")):
            continue
        var faction: String = str(station.get("faction", ""))
        if faction.is_empty() or not world["faction_treasuries"].has(faction):
            return _fail("b4_unowned_actual_colony")
        var station_count: int = 0
        var locals: Array = []
        var workers_needed: int = 0
        for other_id in stations:
            var fac: Dictionary = world["facilities"][other_id]
            if str(fac.get("location", "")) != location or (
                    str(fac.get("faction", "")) != faction):
                continue
            locals.append({"type": str(fac.get("type", "")),
                "crew_count": int(fac.get("crew_count", 0))})
            if str(fac.get("type", "")) == "station":
                station_count += 1
            if str(fac.get("type", "")) in [
                    "mining_rig", "refinery", "farm", "factory"]:
                workers_needed += int(fac.get("crew_count", 0))
        var people: int = 0
        var food_per: float = 0.0
        var water_per: float = 0.0
        var households: Array = world["populations"].keys()
        households.sort()
        for pid in households:
            var household: Dictionary = world["populations"][pid]
            if str(household.get("location", "")) != location or (
                    str(household.get("faction", "")) != faction):
                continue
            var count: int = int(household.get("count", -1))
            if count < 0:
                return _fail("b4_invalid_original_residents")
            people += count
            food_per += float(household.get("consumption", {}).get("food", 0.0))
            water_per += float(household.get("consumption", {}).get("water", 0.0))
        if not is_finite(food_per) or not is_finite(water_per) or (
                food_per < 0.0 or water_per < 0.0):
            return _fail("b4_invalid_original_household_demand")
        var market: Dictionary = world["markets"].get(location, {})
        var real: bool = not market.is_empty() and station_count == 1 and (
            str(market.get("owner", "")) == str(fid) and
            str(market.get("location", "")) == location)
        if not market.is_empty() and (not (market.get("supply") is Dictionary)
                or not (market.get("demand") is Dictionary)):
            return _fail("b4_broken_colony_market")
        var pending_passenger: String = ""
        for c in cids:
            var item: Dictionary = board[c]
            if str(item.get("contract_type", "")) == "passenger" and (
                    str(item.get("destination_location", "")) == location and
                    str(item.get("requestor_id", "")) in [
                        faction, "faction/" + faction] and
                    _outstanding(item)):
                pending_passenger = str(c)
                break
        colony_inputs.append({
            "faction_id": faction, "location": location,
            "station_type": "station", "population": people,
            "facilities": locals, "market_count": 1 if real else 0,
            "market_owned_by_station": real,
            "stock": market.get("supply", {}).duplicate(true),
            "demand": market.get("demand", {}).duplicate(true),
            "food_per_purchase": food_per,
            "water_per_purchase": water_per,
            "required_workers": workers_needed,
            "pending_passenger_contract": pending_passenger})
    var views: Array = N92.observe(colony_inputs)
    # Rust coordination::run_cycle blocks speculative founding while
    # ANY real colony of that faction is starving, has ambiguous market
    # ownership or lacks verifiable Food/Water reserve. Existing already
    # prepaid N151 sites are not cancelled by this source safety gate.
    var unsafe_founding: Dictionary = {}
    for view in views:
        if int(view.get("population", 0)) <= 0:
            continue
        var safe: bool = bool(view.get("market_unambiguous", false))
        var food: float = float(view.get("food", -1.0))
        var water: float = float(view.get("water", -1.0))
        var food_floor: float = float(view.get("food_reserve_target", -1.0))
        var water_floor: float = float(view.get("water_reserve_target", -1.0))
        if not is_finite(food) or not is_finite(water) or (
                not is_finite(food_floor) or not is_finite(water_floor) or
                food_floor < 0.0 or water_floor < 0.0 or
                food < food_floor or water < water_floor):
            safe = false
        if not safe:
            unsafe_founding[str(view.get("faction_id", ""))] = true
    var goals: Dictionary = {}
    var faction_ids: Array = world["faction_treasuries"].keys()
    faction_ids.sort()
    for fid in faction_ids:
        var goal: Dictionary = N92.next_supply_goal(
            views, contracts, str(fid))
        if goal.is_empty():
            continue
        if str(goal.get("goal_id", "")) not in [
                "colony_life_support", "colony_service_fuel",
                "colony_electronics_chain"] or str(goal.get(
                "commodity", "")) not in [
                "food", "water", "fuel", "electronics"] or not is_finite(
                float(goal.get("score", -1.0))):
            return _fail("b4_source_n92_invalid_goal")
        goal["shortage_ticks"] = 0
        # Funding is not inferred from demand. This is ONLY an option
        # for the original N100/N121 N98 plan, not a paid N104 order.
        goals[str(fid)] = goal.duplicate(true)
    var shipyards: Array = []
    for fid in stations:
        var fac: Dictionary = world["facilities"][fid]
        if str(fac.get("type", "")) != "shipyard":
            continue
        var loc: String = str(fac.get("location", ""))
        var m: Dictionary = world["markets"].get(loc, {})
        var stock: Dictionary = fac.get("module_stock", {})
        if not stock.is_empty() and not (stock.get("stock", {}) is Dictionary):
            return _fail("b4_invalid_original_n154_shipyard_stock")
        shipyards.append({"facility_id": str(fid), "location": loc,
            "faction_id": str(fac.get("faction", "")),
            "market_owned": str(m.get("owner", "")) == str(fid),
            "modules": stock.get("stock", {}).duplicate(true),
            "abandoned": bool(fac.get("abandoned", false))})
    return {"ok": true, "status": "B4_RUST_N92_ACTUAL_COLONY_AFTERCARE",
        "views": views, "goals": goals,
        "unsafe_new_colony_factions": unsafe_founding,
        "shipyards": shipyards,
        "hull_autobuild": false,
        "source": "frozen_N92_N134_N100_N121_N154_modules_and_paid_refit",
        "authority": "read_only_one_N39_world_no_N9_or_N104_changes"}

## Exactly the Rust coordination::run_cycle priority:
## essential Food/Water overrides speculative old head when no active
## native plan; Fuel/Electronics are considered only on wait/migrate.
## An N98/121 paid plan is never displaced mid-flight.
static func stock_head(world: Dictionary, observed: Dictionary,
        faction: String, existing_head: Dictionary) -> Dictionary:
    if not observed.get("ok", false):
        return observed
    var proposed: Dictionary = observed.get("goals", {}).get(faction, {})
    if proposed.is_empty():
        return {"ok": true, "promoted": false,
            "reason": "b4_no_original_colony_stock_shortage"}
    var mode: String = str(world.get("native_planner_mode", "legacy"))
    if mode not in ["htn", "hybrid"]:
        return {"ok": true, "promoted": false,
            "reason": "b4_native_execution_not_opted_in"}
    if not world.get("research_directors", {}).has(faction):
        return {"ok": true, "promoted": false,
            "reason": "b4_original_director_missing"}
    var record: Dictionary = world.get("native_planner_records", {}).get(faction, {})
    if str(record.get("status", "")) in [
            "n98_planned_not_dispatched", "n121_active"] or (
            world.get("native_execution", {}).get("active", {}).has(faction)):
        return {"ok": true, "promoted": false,
            "reason": "b4_original_n98_n121_plan_retained"}
    var choice: String = str(existing_head.get("selected_option", "wait"))
    var important: bool = str(proposed.get("goal_id", "")) == "colony_life_support"
    if not important and choice not in ["wait", "migrate_colony"]:
        return {"ok": true, "promoted": false,
            "reason": "b4_nonessential_supply_does_not_preempt_head"}
    var head: Dictionary = existing_head.duplicate(true)
    head["problem"] = proposed.duplicate(true)
    head["selected_option"] = "wait"
    head["selected_administrator"] = ""
    head["planned_spend"] = 0
    head["reason"] = "colony_life_support_native_goal" if important else (
        "colony_industrial_chain_native_goal")
    # The true N100 planner can STILL return no valid source route.
    # Then the caller must keep original head, never claim supplies.
    return {"ok": true, "promoted": true,
        "head": head, "fallback_head": existing_head.duplicate(true),
        "goal": proposed.duplicate(true),
        "reason": str(head["reason"])}

## A cancelled/failed head proposal is observational only. The ONLY
## legal payment follows N100 N98 proof and N121 N104/N9 funding.
static func verify_promoted_plan(world: Dictionary, faction: String,
        promoted: Dictionary, candidate: Dictionary) -> Dictionary:
    if not promoted.get("promoted", false):
        return {"ok": true, "accepted": false,
            "reason": "b4_no_source_aftercare_intent"}
    if not candidate.get("ok", false):
        return candidate
    var status: String = str(candidate.get("status", ""))
    if status != "n98_planned_not_dispatched":
        return {"ok": true, "accepted": false,
            "reason": str(candidate.get("reason", status))}
    var stored: Dictionary = world.get("native_planner_records", {}).get(faction, {})
    var ledger: Dictionary = stored.get("ledger", {})
    var planner_goal: Dictionary = stored.get("goal", {})
    if str(stored.get("status", "")) != status or (
            not bool(candidate.get("due", false)) or
            int(stored.get("tick", 0)) < 1 or
            not (stored.get("ledger") is Dictionary) or
            str(ledger.get("faction_id", "")) != faction or
            str(planner_goal.get("destination_id", "")) != str(
                promoted.get("goal", {}).get("destination", "")) or
            str(planner_goal.get("commodity", "")) != str(
                promoted.get("goal", {}).get("commodity", ""))):
        return _fail("b4_original_n100_result_not_canonical")
    return {"ok": true, "accepted": true,
        "status": "B4_ORIGINAL_N92_NATIVE_STOCK_PLAN_RECORDED",
        "goal": promoted.get("goal", {}).duplicate(true),
        "plan_id": str(stored.get("ledger", {}).get("plan_id", "")),
        "money_spent": 0, "cargo_created": 0,
        "payment_authority": "only_N121_real_N104_N9"}
