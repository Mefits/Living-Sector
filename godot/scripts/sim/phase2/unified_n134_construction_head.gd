extends RefCounted
## Real N134 construction-only head decision, NOT a new faction planner.
## N111 original strategy/options.rs comparison of actual N154 offers and
## one SOURCE N39 market/recipe forecast. The existing N134 cycle must
## emit an exact construction grant before N154/N104 can spend N9 funds.
const NativeConstruction = preload("res://scripts/sim/phase2/unified_native_construction_phase.gd")
const N111 = preload("res://scripts/native_port/n111_options.gd")
const N134 = preload("res://scripts/sim/phase1/n134_coordination_cycle.gd")
const N134Head = preload("res://scripts/sim/phase1/n134_coordination_head.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")

const HORIZON: int = 1200
const DEMAND_WINDOW: int = 100
const SHIPMENT_TIME: int = 120
const DELIVERY_REWARD: int = 1600
const CONSTRUCTION_PAYMENT: int = 10000
const MATERIAL_LOT: int = 200

static func _forecast(world: Dictionary, candidate: Dictionary) -> Dictionary:
    var goal: Dictionary = candidate.get("goal", {})
    var loc: String = str(goal.get("destination", ""))
    var commodity: String = str(goal.get("commodity", ""))
    var kind: String = str(candidate.get("facility_type", ""))
    var market: Dictionary = world.get("markets", {}).get(loc, {})
    if market.is_empty() or commodity.is_empty() or kind.is_empty():
        return {}
    var remaining: int = int(candidate.get("remaining", 0))
    var shipments: int = (maxi(0, remaining) + MATERIAL_LOT - 1) / MATERIAL_LOT
    var delay: int = shipments * SHIPMENT_TIME
    var productive: int = maxi(0, HORIZON - delay)
    var price: float = float(market.get("prices", {}).get(commodity, 0.0))
    var unit_value: float = price if is_finite(price) and price > 0.0 else 0.0
    var need: float = N111.unmet(float(market.get("demand", {}).get(commodity, 0.0)),
        float(market.get("supply", {}).get(commodity, 0.0)), DEMAND_WINDOW)
    var units: float = 0.0
    var material_cost: float = 0.0
    if kind == "mining_rig":
        var richness: float = float(candidate.get("raw_richness", 0.0))
        if is_finite(richness) and richness > 0.0:
            units = float(productive / 5) * 80.0 * richness
    else:
        var best_value: float = -INF
        for recipe in Recipes.for_facility(kind):
            if not recipe["out"].has(commodity):
                continue
            var per_batch: int = int(recipe["out"][commodity])
            if per_batch < 1:
                continue
            var useful: int = ceili(need / float(per_batch))
            var cycles: int = mini(productive / 5, useful)
            if cycles < 1:
                continue
            # Exactly source Need::production(): one real local recipe
            # over CLONED destination stock, no assumed future imports.
            var supply: Dictionary = market["supply"].duplicate(true)
            var output: Dictionary = Recipes.execute(str(recipe["id"]),
                supply, 1.0, cycles, market["prices"])
            var batch_units: float = float(output.get(commodity, 0.0))
            var inputs: float = 0.0
            for good in recipe["in"]:
                var before: float = float(market["supply"].get(good, 0.0))
                var after: float = float(supply.get(good, 0.0))
                var used: float = maxf(0.0, before - after)
                inputs += used * float(market["prices"].get(good, 0.0))
            var value: float = minf(batch_units, need) * unit_value - inputs
            if is_finite(value) and value > best_value:
                best_value = value
                units = batch_units
                material_cost = inputs
    if not is_finite(units) or not is_finite(material_cost) or units < 0.0 or material_cost < 0.0:
        return {}
    var source_location: String = str(candidate.get("source", ""))
    var material: String = str(candidate.get("delivery_commodity", ""))
    if not world.get("markets", {}).has(source_location):
        return {}
    var source_market: Dictionary = world["markets"][source_location]
    var stock: float = float(source_market.get("supply", {}).get(material, 0.0))
    if not is_finite(stock) or stock < 0.0:
        return {}
    return {
        "reason": str(candidate.get("reason", "not_ready")),
        "shipments": shipments, "remaining": remaining,
        "material": material, "total_cost": int(candidate.get("total_cost", 0)),
        "source": source_location, "source_stock": stock,
        "site_id": str(candidate.get("site_id", "")),
        "first_purchase_cost": int(candidate.get("source_price", -1)),
        "native_output_units": units, "native_input_cost": material_cost}

static func choose(world: Dictionary, factions: Dictionary,
        original: RefCounted, graph: RefCounted,
        faction: String, tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "n134_invalid_native_clock"}
    if not world.get("faction_treasuries", {}).has(faction) or not factions.has(faction):
        return {"ok": false, "reason": "n134_missing_real_faction_treasury"}
    var source: Dictionary = NativeConstruction.observe(
        world, factions, original, graph, faction, tick)
    if not source.get("ok", false):
        return source
    var view: Dictionary = source.get("view", {})
    var goals: Array = []
    var offers: Dictionary = {}
    var markets: Dictionary = {}
    for location in world.get("markets", {}):
        markets[location] = world["markets"][location]
    for row in view.get("offers", []):
        if not (row is Dictionary):
            continue
        var goal: Dictionary = row.get("goal", {})
        if str(goal.get("goal_id", "")).begins_with("player_"):
            continue
        if not markets.has(str(goal.get("destination", ""))):
            continue
        var key: String = str(goal.get("destination", "")) + "|" + str(goal.get("commodity", ""))
        goals.append(goal.duplicate(true))
        offers[key] = _forecast(world, row)
    # N135 independently owns station supply orders. This bridge
    # cannot authorize a source N134 logistics subsidy without a
    # native N121 subsidy quote; mark that alternative unavailable.
    var assessments: Dictionary = {}
    for goal in goals:
        assessments[str(goal["destination"]) + "|" + str(goal["commodity"])] = {
            "reason": "n121_subsidy_quote_not_available"}
    var comparison: Dictionary = N111.compare_goals(goals, markets,
        assessments, offers, int(world["faction_treasuries"][faction]),
        multiplier, {"demand_window": DEMAND_WINDOW,
            "shipment_time": SHIPMENT_TIME,
            "delivery_reward": DELIVERY_REWARD,
            "construction_payment": CONSTRUCTION_PAYMENT,
            "delivery_quantity": MATERIAL_LOT})
    var contract_view: Array = []
    for cid in world.get("construction_contracts", {}):
        var c: Dictionary = world.get("contract_board", {}).get("contracts", {}).get(cid, {})
        if c.is_empty():
            continue
        var row: Dictionary = c.duplicate(true)
        row["requestor_id"] = faction if str(c.get("requestor_id", "")) == "faction/" + faction else ""
        row["mission_category"] = "strategy.construction.v1"
        contract_view.append(row)
    var commander: Dictionary = world.get("research_directors", {}).get(faction, {}).duplicate(true)
    var cycle = N134.new()
    var preview: Dictionary = cycle.preview_cycle(tick, multiplier, {
        "mode": "Execute", "native_execution_enabled": false,
        "factions": {faction: {
            "view": {"treasury": int(world["faction_treasuries"][faction])},
            "comparison": comparison, "commander": commander,
            "candidate_inputs": {}}},
        "contracts": contract_view})
    if not preview.get("ok", false):
        return preview
    var head: Dictionary = preview.get("heads", {}).get(faction, {})
    if str(head.get("selected_option", "wait")) != "build" or str(head.get("selected_administrator", "")) != "construction":
        return {"ok": true, "authorized": false, "head": head,
            "reason": str(head.get("reason", "source_n134_wait"))}
    var permission: bool = N134Head.authorized(true, preview.get("grants", {}),
        faction, "construction", head.get("problem", {}))
    if not permission:
        return {"ok": false, "reason": "n134_grant_not_verified"}
    var staged: Dictionary = NativeConstruction.stage(
        world, factions, original, graph, faction, tick, multiplier, true)
    if not staged.get("ok", false):
        return {"ok": true, "authorized": false,
            "head": head, "reason": str(staged.get("reason", "n154_not_ready"))}
    var goal: Dictionary = staged.get("post", {})
    var intended: Dictionary = head.get("problem", {})
    var chosen_goal: Dictionary = {
        "commodity": str(staged.get("site", {}).get("commodity", "")),
        "destination": str(goal.get("destination_location", ""))}
    # The N154 site may use a different input commodity from its
    # goal. Verify selected target through N154 source offer identity.
    var selected_offer: Dictionary = {}
    for row in view.get("offers", []):
        if N134Head.same_problem(row.get("goal", {}), intended) and row.get("ready", false):
            selected_offer = row
            break
    if selected_offer.is_empty() or str(selected_offer.get("source", "")) != str(goal.get("source_location", "")) or str(selected_offer.get("delivery_commodity", "")) != str(goal.get("commodity", "")):
        return {"ok": true, "authorized": false, "head": head,
            "reason": "n134_grant_does_not_match_n154_material_contract"}
    return {"ok": true, "authorized": true, "head": head,
        "staged": staged, "reason": "source_n134_N111_positive_build"}
