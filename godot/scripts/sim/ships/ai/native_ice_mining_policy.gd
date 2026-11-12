extends RefCounted
## N80. Exact profitable_mining_quantity / choose_ice_mining_trip from
## frozen Rust agents/ship/behavior.rs, plus SALVAGE_UNITS_PER_RICHNESS
## from agents/facility/mod.rs. Produces read-only ShipAction proposals.
const Goals = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const SALVAGE_UNITS_PER_RICHNESS: float = 8000.0
const MAX_LOT: int = 40
const MAX_U32: int = 4294967295

## Real buyer cash and fuel opportunity cost, no synthetic mine resources.
## In Rust the cost is an ESTIMATE, no money/fuel is actually debited.
static func profitable_mining_quantity(cargo_free: int, available_ice: int,
        unit_price: float, buyer_credits: int, distance: int,
        fuel_rate: float, fuel_price: float, speed_modifier: float) -> Dictionary:
    if cargo_free < 0 or cargo_free > MAX_U32 or available_ice < 0             or available_ice > MAX_U32 or distance < 0 or distance > MAX_U32:
        return _err("invalid_physical_source")
    if not is_finite(unit_price) or unit_price <= 0.0             or not is_finite(fuel_rate) or fuel_rate < 0.0             or not is_finite(fuel_price) or fuel_price < 0.0             or not is_finite(speed_modifier) or speed_modifier <= 0.0             or buyer_credits <= 0:
        return _err("unprofitable_or_unknown_buyer")
    var payable: int = mini(MAX_U32,
        int(floor(float(buyer_credits) / float(unit_price))))
    var qty: int = mini(mini(cargo_free, MAX_LOT), mini(available_ice, payable))
    if qty <= 0:
        return _err("no_payable_ice")
    var revenue: float = floor(float(unit_price) * float(qty))
    var opportunity: float = 2.0 * float(distance) * float(fuel_rate)         * float(fuel_price) / float(speed_modifier)
    var net: float = revenue - opportunity
    if not is_finite(net) or net < 1.0 or net >= 9223372036854775808.0:
        return _err("not_profitable")
    return {"ok": true, "quantity": qty, "net_profit": int(floor(net)),
        "fuel_opportunity_cost": opportunity}

## Distances are real Rust WorldRegistry::travel_distance results, not
## positions, map pixels, or fuel/tick values. source_distance_by_pair:
## { "depot_location\u001fsite_location": nonnegative integer }. The
## caller may provide either original direction (Rust checks reverse too).
static func choose_ice_mining_trip(at_location: String, faction_id: String,
        carried_ice: int, cargo_free: int, fuel_rate: float, speed_modifier: float,
        personality: Dictionary, sites: Array, depots: Array,
        source_distance_by_pair: Dictionary) -> Dictionary:
    if at_location.is_empty() or faction_id.is_empty()             or not Personality.validate(personality) or carried_ice < 0:
        return _err("invalid_ship_state")
    if cargo_free < 0 or cargo_free > MAX_U32:
        return _err("invalid_free_hold")
    var options: Array = []
    for depot_value in depots:
        if not (depot_value is Dictionary):
            return _err("invalid_depot")
        var depot: Dictionary = depot_value
        if str(depot.get("faction_id", "")) != faction_id:
            continue
        for site_value in sites:
            if not (site_value is Dictionary):
                return _err("invalid_site")
            var site: Dictionary = site_value
            var site_loc: String = str(site.get("location", ""))
            var depot_loc: String = str(depot.get("location", ""))
            var richness: Variant = site.get("richness", null)
            if site_loc.is_empty() or depot_loc.is_empty() or not _number(richness):
                return _err("unknown_site_source")
            if carried_ice == 0 and (float(richness) <= 0.0                     or float(richness) * SALVAGE_UNITS_PER_RICHNESS < 1.0):
                continue
            var link: String = depot_loc + "\u001f" + site_loc
            var reverse: String = site_loc + "\u001f" + depot_loc
            var distance_value: Variant = source_distance_by_pair.get(link,
                source_distance_by_pair.get(reverse, null))
            if not (distance_value is int) or int(distance_value) < 0                     or int(distance_value) > MAX_U32:
                continue
            var distance: int = int(distance_value)
            if at_location != depot_loc and at_location != site_loc:
                continue
            var quantity: int = 0
            var score: float = 0.0
            if carried_ice > 0:
                # Even a currently insolvent buyer may offer an actual
                # dock/market; allow delivering existing cargo.
                score = Goals.TIER_HOUSEKEEPING_WEIGHT                     * maxf(float(personality["profit"]), 0.3) * 1.3
            else:
                var available: int = mini(MAX_U32,
                    int(floor(maxf(0.0, float(richness)
                        * SALVAGE_UNITS_PER_RICHNESS))))
                var trial: Dictionary = profitable_mining_quantity(
                    cargo_free, available,
                    float(depot.get("ice_unit_price", -1.0)),
                    int(depot.get("buyer_credits", 0)), distance, fuel_rate,
                    float(depot.get("fuel_unit_price", -1.0)),
                    speed_modifier)
                if not bool(trial.get("ok", false)):
                    continue
                quantity = int(trial["quantity"])
                score = Goals.score_strategic(int(trial["net_profit"]), "mine",
                    personality, false)
            var actions: Array = []
            if carried_ice == 0:
                if at_location == depot_loc:
                    actions.append({"action": "Undock"})
                    actions.append({"action": "Travel", "destination": site_loc})
                actions.append({"action": "Mine", "location": site_loc,
                    "body_id": str(site.get("body_id", "")),
                    "commodity": "ice", "quantity": quantity})
            if at_location == site_loc or carried_ice == 0:
                actions.append({"action": "Travel", "destination": depot_loc})
            actions.append({"action": "Dock"})
            actions.append({"action": "Sell", "commodity": "ice", "quantity": 0})
            actions.append({"action": "Undock"})
            options.append({"name": "deliver_mined_ice" if carried_ice > 0 else "mine_ice",
                "feasible": true, "score": score, "distance": distance,
                "site_location": site_loc, "depot_location": depot_loc,
                "quantity": quantity, "actions": actions})
    if options.is_empty():
        return _err("no_profitable_native_mining_trip")
    # Rust options.sort_by: SCORE desc, distance ASC, site name ASC.
    # This deterministic insertion ordering preserves ties.
    var ordered: Array = []
    for option in options:
        var insert_at: int = ordered.size()
        for i in range(ordered.size()):
            var prev: Dictionary = ordered[i]
            if float(option["score"]) > float(prev["score"])                     or (is_equal_approx(float(option["score"]), float(prev["score"]))                     and (int(option["distance"]) < int(prev["distance"])                     or (int(option["distance"]) == int(prev["distance"])                     and str(option["site_location"]) < str(prev["site_location"])))):
                insert_at = i
                break
        ordered.insert(insert_at, option)
    return {"ok": true, "proposal": ordered[0].duplicate(true)}

static func _number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _err(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
