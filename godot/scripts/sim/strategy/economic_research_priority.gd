extends RefCounted
## Ranks an existing capacity unlock against the normal N155 preferences.
## The market signal is evidence for investment, never a production order.
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const Technology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")

const CAPACITY_TECHS := ["industrial_methods", "automation"]
const MAX_INDUSTRY_PREMIUM := 2.0
# Initial scope: capacity shared by the basic industrial facilities.
# Advanced facilities and retrofit recipes have additional technology/tier gates.
const BASIC_PRODUCERS := ["refinery", "factory", "farm"]

static func recommend(world: Dictionary, faction: String, head: Dictionary) -> Dictionary:
    if bool(head.get("crisis", false)) or head.get("research") != null:
        return {}
    var eligible: Array[Dictionary] = Technology.eligible(head.get("technologies", []))
    if eligible.is_empty():
        return {}
    var pressure: float = 0.0
    for technology in eligible:
        if technology["id"] in CAPACITY_TECHS:
            pressure = _capacity_pressure(world, faction)
            break
    if pressure <= 0.0:
        return {}

    var best: Dictionary = {}
    var best_score: float = -INF
    var profile: Dictionary = head.get("profile", {})
    for technology in eligible:
        var score: float = float(profile.get(technology["field"], 0.0))
        if technology["id"] in CAPACITY_TECHS:
            score += MAX_INDUSTRY_PREMIUM * pressure
        if not is_finite(score):
            continue
        if best.is_empty() or score > best_score or (score == best_score and
                str(technology["id"]) < str(best["id"])):
            best = technology
            best_score = score
    return best if best.get("id", "") in CAPACITY_TECHS else {}

static func _capacity_pressure(world: Dictionary, faction: String) -> float:
    var pressure: float = 0.0
    for facility: Dictionary in world["facilities"].values():
        if facility["faction"] != faction or facility["abandoned"] or (
                facility["type"] not in BASIC_PRODUCERS):
            continue
        var market: Dictionary = world["markets"].get(facility["location"], {})
        if market.is_empty():
            continue
        var owner: Dictionary = world["facilities"][market["owner"]]
        if owner["faction"] != faction or owner["abandoned"]:
            continue
        for recipe in Recipes.for_facility(facility["type"]):
            if str(recipe["id"]).ends_with("_retrofit"):
                continue
            pressure = maxf(pressure, _recipe_pressure(market, recipe))
    return pressure

static func _recipe_pressure(market: Dictionary, recipe: Dictionary) -> float:
    var stock: Dictionary = market["supply"]
    var prices: Dictionary = market["prices"]
    var cost: float = 0.0
    for good in recipe["in"]:
        var quantity: float = float(recipe["in"][good])
        var price: float = float(prices.get(good, 0.0))
        if float(stock.get(good, 0.0)) < quantity or price <= 0.0:
            return 0.0
        cost += quantity * price

    var value: float = 0.0
    var pressure: float = 0.0
    var shortages: Dictionary = market.get("history", {}).get("shortage_ticks", {})
    var demand: Dictionary = market.get("demand", {})
    for good in recipe["out"]:
        var needed: float = float(demand.get(good, 0.0))
        if needed <= 0.0 or int(shortages.get(good, 0)) <= 0:
            continue
        var gap: float = needed - float(stock.get(good, 0.0))
        if gap > 0.0:
            if str(recipe["id"]).ends_with("_retrofit"):
                continue
            pressure = maxf(pressure, gap / needed)
            value += minf(gap, float(recipe["out"][good])) * float(prices.get(good, 0.0))
    return pressure if value > cost else 0.0
