extends RefCounted
## Frozen Rust strategy/planning/mod.rs::PlanningSnapshot::capture
## -> native_catalogue.rs -> hybrid.rs -> ledger.rs.
## Pure planner/ledger PROPOSAL for the real source N121 execution owner;
## nothing here purchases goods, awards credits, or posts contracts.
const NativeRecipes = preload("res://scripts/sim/economy/native_recipes.gd")
const NativeCatalogue = preload("res://scripts/sim/phase1/n155_native_catalogue.gd")
const NativeHybrid = preload("res://scripts/sim/phase1/n100_hybrid_planner.gd")
const NativeHtn = preload("res://scripts/sim/phase1/n155_htn_methods.gd")
const Validate = preload("res://scripts/sim/phase1/n155_planning_validation.gd")
const NativeLedger = preload("res://scripts/sim/phase1/n98_plan_ledger.gd")
const SourceGoal = preload("res://scripts/sim/phase1/n155_head_strategy_shadow.gd")
const SourceExecution = preload("res://scripts/port/n121_native_execution_state.gd")
const SEARCH_BUDGET: Dictionary = {"max_nodes": 350, "max_depth": 12}
const FACTION_SUBSIDY_FLOOR: int = 5000

static func capture(world: Dictionary, faction: String, tick: int) -> Dictionary:
    if faction.is_empty() or tick < 1 or not world.get(
            "faction_treasuries", {}).has(faction):
        return {"ok": false, "reason": "n100_no_live_faction_treasury"}
    for field in ["facilities", "markets", "ships", "populations", "contract_board"]:
        if not (world.get(field) is Dictionary):
            return {"ok": false, "reason": "n100_missing_real_" + field}
    var facilities: Array = []
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for fid in facility_ids:
        var f: Dictionary = world["facilities"][fid]
        if str(f.get("faction", "")) == faction:
            facilities.append({"facility_id": str(fid),
                "location_id": str(f.get("location", "")),
                "facility_type": str(f.get("type", ""))})
    var markets: Array = []
    var locations: Array = world["markets"].keys()
    locations.sort()
    for loc in locations:
        var m: Dictionary = world["markets"][loc]
        var owner: String = str(m.get("owner", ""))
        if not world["facilities"].has(owner) or str(
                world["facilities"][owner].get("faction", "")) != faction:
            continue
        if str(world["facilities"][owner].get("location", "")) != str(loc):
            return {"ok": false, "reason": "n100_wrong_source_market_owner"}
        markets.append({"market_id": str(m.get("id", "")),
            "facility_id": owner, "location_id": str(loc),
            "stock": m.get("supply", {}).duplicate(true),
            "demand": m.get("demand", {}).duplicate(true),
            "prices": m.get("prices", {}).duplicate(true)})
    var ships: Array = []
    var ship_ids: Array = world["ships"].keys()
    ship_ids.sort()
    for sid in ship_ids:
        var ship: Dictionary = world["ships"][sid]
        if str(ship.get("faction_id", "")) != faction:
            continue
        var cargo_total: int = 0
        for amount in ship.get("cargo", {}).values():
            if typeof(amount) != TYPE_INT or int(amount) < 0:
                return {"ok": false, "reason": "n100_invalid_original_cargo"}
            cargo_total += int(amount)
        # Rust ShipCargo::free() saturates when a refit left cargo
        # temporarily above new capacity. No jettison or phantom space.
        var free: int = maxi(0, int(ship.get("cargo_capacity", 0)) - cargo_total)
        ships.append({"ship_id": str(sid), "class": str(ship.get("class", "")),
            "location_id": ship.get("location", null) if ship.get(
                "transit", {}).is_empty() else null,
            "in_transit": not ship.get("transit", {}).is_empty(),
            "free_cargo": free, "fuel": float(ship.get("fuel", 0.0))})
    var contracts: Dictionary = world["contract_board"].get("contracts", {})
    if not (contracts is Dictionary):
        return {"ok": false, "reason": "n100_invalid_original_contract_board"}
    var commitments: Array = []
    var contract_ids: Array = contracts.keys()
    contract_ids.sort()
    for cid in contract_ids:
        var c: Dictionary = contracts[cid]
        var status: String = str(c.get("status", "")).to_lower()
        if status in ["paid", "expired"]:
            continue
        var owner: String = str(c.get("requestor_id", ""))
        var sponsorship: String = str(c.get("faction_id", ""))
        if owner != faction and owner != "faction/" + faction and sponsorship != faction:
            continue
        commitments.append({
            "contract_id": str(cid), "status": status,
            "source": str(c.get("source_location", "")),
            "destination": str(c.get("destination_location", "")),
            "commodity": str(c.get("commodity", "")),
            "quantity": int(c.get("quantity", 0)),
            "assigned_ship_id": c.get("fulfiller_id", null)})
    var recipes: Array = []
    for original in NativeRecipes.TABLE:
        var ins: Array = []
        var outs: Array = []
        var input_names: Array = original["in"].keys()
        var output_names: Array = original["out"].keys()
        input_names.sort()
        output_names.sort()
        for good in input_names:
            ins.append([str(good), int(original["in"][good])])
        for good in output_names:
            outs.append([str(good), int(original["out"][good])])
        recipes.append({"recipe_id": str(original["id"]),
            "facility_type": str(original["facility"]),
            "inputs": ins, "outputs": outs})
    var known_tech: Array = world.get("research", {}).get(faction, []).duplicate(true)
    known_tech.sort()
    return {"ok": true, "snapshot": {
        "schema_version": 1, "tick": tick, "faction_id": faction,
        "treasury_credits": int(world["faction_treasuries"][faction]),
        "treasury_floor_credits": FACTION_SUBSIDY_FLOOR,
        "owned_markets": markets, "facilities": facilities, "ships": ships,
        "active_commitments": commitments,
        "technologies": known_tech, "recipes": recipes}}

static func propose(world: Dictionary, faction: String, head: Dictionary,
        tick: int, mode: String = "hybrid") -> Dictionary:
    if mode not in ["hybrid", "htn"]:
        return {"ok": true, "status": "legacy_planner_unmodified",
            "faction_id": faction, "tick": tick}
    if str(head.get("selected_option", "wait")) not in ["deliver", "build", "wait"]:
        return {"ok": true, "status": "original_head_other_domain",
            "faction_id": faction, "tick": tick}
    var input: Dictionary = capture(world, faction, tick)
    if not input.get("ok", false):
        return input
    var snapshot: Dictionary = input["snapshot"]
    var head_goal: Dictionary = SourceGoal.goal_from_head(head)
    if head_goal.is_empty():
        return {"ok": true, "status": "no_original_head_stock_goal",
            "faction_id": faction, "tick": tick}
    var promoted: Dictionary = NativeCatalogue.promote_industry_output_goal(
        snapshot, head_goal)
    if not promoted.is_empty():
        head_goal = promoted
    var action_case: Dictionary = NativeCatalogue.native_candidate_request(
        snapshot, head_goal)
    if not action_case.get("ok", false):
        return {"ok": true, "status": "no_source_native_candidate",
            "reason": str(action_case.get("error", "catalogue_unavailable")),
            "tick": tick, "faction_id": faction}
    var projected: Dictionary = action_case["projected"]
    var goal: Dictionary = action_case["goal"]
    var actions: Array = action_case["actions"]
    var budget: Dictionary = action_case["budget"]
    var commander: Dictionary = world.get("research_directors", {}).get(
        faction, {})
    var profile: Dictionary = commander.get("profile", {})
    var preferences: Dictionary = {"cost_weight": float(profile.get(
        "industry", 1.0)), "speed_weight": (3.0 if bool(commander.get(
        "crisis", false)) else maxf(0.25, float(profile.get(
        "expansion", 1.0)))), "caution_weight": float(profile.get(
        "caution", 0.5))}
    var decision: Dictionary = {}
    var plan: Dictionary = {}
    if mode == "hybrid":
        decision = NativeHybrid.decide(projected, goal, actions,
            budget, preferences)
        plan = decision.get("result", {})
    else:
        plan = NativeHtn.plan(projected, goal, actions, budget)
    var status: String = str(plan.get("status", "NoPlan"))
    if status != "Ready":
        return {"ok": true, "status": "no_source_validated_plan",
            "planner_status": status, "faction_id": faction, "tick": tick,
            "roles": decision.get("roles", {}).duplicate(true)}
    var valid: Dictionary = Validate.validate_plan(projected, goal,
        actions, plan, budget)
    if not valid.get("ok", false):
        return {"ok": false, "reason": "n100_native_plan_validation:" +
            str(valid.get("error", "rejected"))}
    # Never set native_dispatch_authorized or mutate the N104 board
    # because a Ready search result is only a conservative forecast.
    var plan_id: String = "native-" + mode + ":" + faction + ":" + str(
        tick) + ":" + str(goal["goal_id"])
    var ledger: Dictionary = NativeLedger.create_plan(
        projected, goal, plan, plan_id)
    if ledger.has("error"):
        return {"ok": false, "reason": "n98_real_source_plan_ledger:" +
            str(ledger["error"])}
    # Rust distinguishes a promoted INDUSTRY-OUTPUT goal from a stock
    # import: true completion needs real paid recipe receipts as well
    # as a physical stock observation, not only ledger step success.
    var observed_stock: float = -1.0
    for market in projected.get("owned_markets", []):
        if str(market.get("location_id", "")) == str(goal["destination_id"]):
            observed_stock = float(market.get("stock", {}).get(
                str(goal["commodity"]), -1.0))
            break
    var delta: int = maxi(0, int(goal["target_units"]) -
        maxi(0, int(floor(observed_stock))))
    return {"ok": true, "status": "n98_planned_not_dispatched",
        "production_goal": not promoted.is_empty() and delta > 0,
        "production_target_delta": delta,
        "tick": tick, "faction_id": faction, "planner_mode": mode,
        "goal": goal.duplicate(true), "actions": actions.duplicate(true),
        "plan": plan.duplicate(true), "ledger": ledger.duplicate(true),
        "roles": decision.get("roles", {}).duplicate(true),
        "source_snapshot_tick": tick,
        "native_dispatch_authorized": false}
