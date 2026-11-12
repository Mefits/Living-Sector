extends RefCounted
## N104. Frozen Rust sim_server/engine/transactions.rs::deliver and
## apply.rs::commit_contract_delivery. Pure staged world; no invented
## contract money or extra world simulation. Source status indexes are
## to be rebuilt by authoritative ContractBoard during Phase 2.
const Quote = preload("res://scripts/port/n104_contract_quote.gd")
const Passengers = preload("res://scripts/port/n104_passenger_contracts.gd")
const MAX_I64: int = 9223372036854775807
const MAX_U32: int = 4294967295
const FOOD_SAT_RECOVER_ON_MET: int = 2
const SHIP_XP_PER_DELIVERY: int = 15
const SHIP_LEVEL_CAP: int = 10
const DRIFT_DELIVERY_PROFIT: float = 0.002
const DELIVERY_STANDING_BUMP: int = 2
const CREW_MISSIONS = {
    "security_detail": {"skill": "combat", "gain": 3},
    "vip_escort": {"skill": "navigation", "gain": 2},
    "customs_assist": {"skill": "trading", "gain": 2},
    "heavy_maintenance": {"skill": "engineering", "gain": 3},
    "salvage_operation": {"skill": "engineering", "gain": 2},
    "production_assist": {"skill": "engineering", "gain": 2},
    "equipment_calibration": {"skill": "engineering", "gain": 2},
    "safety_audit": {"skill": "engineering", "gain": 2}
}
const CONTRACT_TYPES = [
    "delivery", "courier", "passenger", "subsidy", "supply",
    "crew_mission", "construction"
]

static func deliver(world: Dictionary, ship_id: String,
        contract_id: String, tick: int) -> Dictionary:
    if tick < 0 or ship_id.is_empty() or contract_id.is_empty():
        return _bad("invalid_deliver_context")
    var ships: Variant = world.get("ships", null)
    var board: Variant = world.get("contracts", null)
    if not (ships is Dictionary) or not (board is Dictionary):
        return _bad("missing_contract_world")
    var source_ship: Variant = ships.get(ship_id, null)
    var source_contract: Variant = board.get(contract_id, null)
    if not (source_ship is Dictionary) or not (source_contract is Dictionary):
        return _bad("missing_contract_or_ship")
    var ship: Dictionary = source_ship
    var contract: Dictionary = source_contract
    if str(contract.get("fulfiller_id", "")) != ship_id             or str(ship.get("active_contract_id", "")) != contract_id:
        return _bad("wrong_fulfiller")
    if not ["accepted", "picked_up"].has(str(contract.get("status", ""))):
        return _bad("inactive_contract")
    var ship_faction: String = str(ship.get("faction_id", ""))
    var issuer_value: Variant = contract.get("faction_id", null)
    var issuer: String = "" if issuer_value == null else str(issuer_value)
    var relations: Variant = world.get("relations", null)
    if not (relations is Dictionary):
        return _bad("missing_relations")
    if not issuer.is_empty():
        var allowed: Dictionary = Quote.commerce_allowed(relations, ship_faction, issuer)
        if not bool(allowed.get("ok", false)):
            return allowed
        if not bool(allowed["allowed"]):
            return _bad("embargo")
    var funding: Variant = contract.get("funding", null)
    if not (funding is Dictionary):
        return _bad("unverified_legacy_funding")
    var agreed: Variant = funding.get("agreed_payment", null)
    if typeof(agreed) != TYPE_INT:
        return _bad("contract_not_funded_for_ship")
    if typeof(funding.get("reserved", null)) != TYPE_INT             or int(agreed) < 0 or int(funding["reserved"]) < int(agreed):
        return _bad("invalid_contract_escrow")
    var payment: int = int(agreed)
    var cash: Variant = ship.get("credits", null)
    if typeof(cash) != TYPE_INT or int(cash) > MAX_I64 - payment:
        return _bad("credit_overflow")
    var at: String = str(contract.get("destination_location", ""))
    var dock: Dictionary = Passengers._dock_and_controller(world, ship_id, at)
    if not bool(dock.get("ok", false)):
        return dock
    var contract_type: String = str(contract.get("contract_type", ""))
    if not CONTRACT_TYPES.has(contract_type):
        return _bad("invalid_contract_type")
    var commodity: String = str(contract.get("commodity", ""))
    var qty: Variant = contract.get("quantity", null)
    if typeof(qty) != TYPE_INT or int(qty) < 0 or int(qty) > MAX_U32:
        return _bad("invalid_contract_quantity")
    var physical: bool = not ["passenger", "crew_mission"].has(contract_type)
    if physical:
        if not (ship.get("cargo", null) is Dictionary):
            return _bad("missing_cargo")
        if int(qty) <= 0 or typeof(ship["cargo"].get(commodity, null)) != TYPE_INT                 or int(ship["cargo"][commodity]) < int(qty):
            return _bad("insufficient_cargo")
    var household: bool = str(funding.get("source", "")) == "population"             and contract_type == "delivery"
    var pop_id: String = str(contract.get("requestor_id", ""))
    if household:
        var hh: Variant = world.get("populations", null)
        if not (hh is Dictionary) or not (hh.get(pop_id, null) is Dictionary):
            return _bad("missing_contract_recipient")
        var household_record: Dictionary = hh[pop_id]
        if str(household_record.get("facility_location", "")) != at or commodity != "food":
            return _bad("invalid_household_delivery")
        if typeof(household_record.get("population_count", null)) != TYPE_INT                 or int(household_record["population_count"]) <= 0                 or not (household_record.get("sentiment", null) is Dictionary):
            return _bad("missing_contract_recipient")
    var site_index: int = -1
    var market_record: Dictionary = {}
    if physical and contract_type == "construction":
        var sites: Variant = world.get("construction_sites", null)
        if not (sites is Array):
            return _bad("missing_construction_site")
        for i in range(sites.size()):
            var site: Variant = sites[i]
            if not (site is Dictionary):
                return _bad("invalid_construction_site")
            if str(site.get("location_name", "")) == at                     and str(site.get("commodity", "")) == commodity                     and not bool(site.get("completed", false)):
                site_index = i
                break
        if site_index < 0:
            return _bad("missing_construction_site")
        var site: Dictionary = sites[site_index]
        var progress: Variant = site.get("progress_delivered", null)
        var needed: Variant = site.get("progress_required", null)
        if typeof(progress) != TYPE_INT or typeof(needed) != TYPE_INT                 or int(needed) < int(progress) or int(needed) - int(progress) < int(qty):
            return _bad("construction_overdelivery")
        var site_owner: String = str(site.get("faction_id", ""))
        var acceptable: Dictionary = Quote.commerce_allowed(relations, ship_faction, site_owner)
        if not bool(acceptable.get("ok", false)) or not bool(acceptable.get("allowed", false)):
            return _bad("embargo")
        if not issuer.is_empty() and issuer != site_owner:
            return _bad("wrong_construction_owner")
    elif physical and not household:
        var markets: Variant = world.get("markets", null)
        if not (markets is Dictionary) or not (markets.get(at, null) is Dictionary):
            return _bad("missing_market")
        market_record = markets[at]
        var market_ok: Dictionary = _market_preflight(world,
            market_record, ship_faction, at)
        if not bool(market_ok.get("ok", false)):
            return market_ok
        if not (market_record.get("supply", null) is Dictionary):
            return _bad("missing_destination_pricing")
        var prior: Variant = market_record["supply"].get(commodity, 0.0)
        if not _num(prior) or float(prior) < 0.0                 or not is_finite(float(prior) + float(qty)):
            return _bad("invalid_destination_stock")
    var recipient_id: String = ""
    var manifest: Dictionary = {}
    if contract_type == "passenger":
        var embarked: Variant = funding.get("embarked", null)
        if str(contract.get("status", "")) != "picked_up" or not (embarked is Dictionary):
            return _bad("passengers_not_embarked")
        manifest = embarked
        var wealth: Variant = manifest.get("wealth", null)
        if typeof(wealth) != TYPE_INT or int(wealth) < 0:
            return _bad("invalid_passenger_manifest")
        var populations: Variant = world.get("populations", null)
        if not (populations is Dictionary):
            return _bad("missing_passenger_recipient")
        var ids: Array = populations.keys()
        ids.sort()
        var recipient_faction: String = issuer if not issuer.is_empty() else ship_faction
        for id in ids:
            var pop: Variant = populations[id]
            if pop is Dictionary and str(pop.get("facility_location", "")) == at                     and str(pop.get("faction_id", "")) == recipient_faction                     and pop.get("sentiment", null) is Dictionary:
                recipient_id = str(id)
                break
        if recipient_id.is_empty():
            return _bad("missing_passenger_recipient")
        var destination_pop: Dictionary = populations[recipient_id]
        if typeof(destination_pop.get("population_count", null)) != TYPE_INT                 or typeof(destination_pop.get("total_wealth", null)) != TYPE_INT:
            return _bad("missing_passenger_recipient")
        if int(destination_pop["population_count"]) > MAX_I64 - int(qty):
            return _bad("population_overflow")
        if int(destination_pop["total_wealth"]) > MAX_I64 - int(wealth):
            return _bad("credit_overflow")
    # All physical, payee and source checks precede changes.
    var staged: Dictionary = world.duplicate(true)
    var paid_contract: Dictionary = staged["contracts"][contract_id]
    var paid_ship: Dictionary = staged["ships"][ship_id]
    paid_contract["status"] = "paid"
    paid_contract["funding"]["reserved"] -= payment
    paid_contract["funding"]["embarked"] = null
    paid_ship["credits"] = int(cash) + payment
    paid_ship["active_contract_id"] = null
    var events: Array = []
    if not issuer.is_empty():
        if not (paid_ship.get("faction_reputation", null) is Dictionary):
            return _bad("missing_ship_reputation")
        var reputation: Dictionary = paid_ship["faction_reputation"]
        var rep: int = int(reputation.get(issuer, 0))
        var bonus: int = clampi(5 + int(payment / 2000), 1, 15)
        reputation[issuer] = mini(100, rep + bonus)
        if ship_faction != issuer and not ship_faction.is_empty():
            # Frozen Rust RelationState::new starts at zero standing.
            if not (staged.get("relation_standing", null) is Dictionary):
                return _bad("missing_relation_standing")
            var pair: Array = [ship_faction, issuer]
            pair.sort()
            var pair_key: String = str(pair[0]) + "\u001f" + str(pair[1])
            var standing: Dictionary = staged["relation_standing"].get(
                pair_key, {"standing": 0, "since_tick": tick})
            var value: Variant = standing.get("standing", null)
            if typeof(value) != TYPE_INT:
                return _bad("invalid_relation_standing")
            var next: int = clampi(int(value) + DELIVERY_STANDING_BUMP, -100, 100)
            standing["standing"] = next
            standing["last_event_tick"] = tick
            staged["relation_standing"][pair_key] = standing
            events.append({"kind": "faction_standing_changed",
                "a": ship_faction, "b": issuer, "delta": DELIVERY_STANDING_BUMP,
                "new_standing": next, "cause": "delivery"})
    if paid_ship.has("hoard_strikes"):
        paid_ship["hoard_strikes"] = 0
    if paid_ship.get("personality", null) is Dictionary:
        var personality: Dictionary = paid_ship["personality"]
        if _num(personality.get("profit", null)):
            personality["profit"] = clampf(
                float(personality["profit"]) + DRIFT_DELIVERY_PROFIT, 0.0, 1.0)
    if paid_ship.get("progression", null) is Dictionary:
        _ship_xp(staged, paid_ship, ship_id, events)
    if contract_type == "passenger":
        var pop: Dictionary = staged["populations"][recipient_id]
        pop["population_count"] += int(qty)
        pop["total_wealth"] += int(manifest["wealth"])
        pop["sentiment"]["dirty"] = true
        events.append({"kind": "passengers_arrived",
            "contract_id": contract_id, "source": contract.get("source_location", null),
            "destination": at, "head_count": int(qty),
            "payment": payment, "ship_id": ship_id,
            "wealth": int(manifest["wealth"])})
    elif contract_type == "crew_mission":
        var mission: String = str(contract.get("mission_category", ""))
        if CREW_MISSIONS.has(mission):
            var template: Dictionary = CREW_MISSIONS[mission]
            _grant_skill(paid_ship, str(template["skill"]), int(template["gain"]))
            events.append({"kind": "crew_mission_completed",
                "contract_id": contract_id, "category": mission,
                "skill": template["skill"], "skill_gain": template["gain"],
                "payment": payment})
    else:
        var remaining: int = int(paid_ship["cargo"][commodity]) - int(qty)
        if remaining == 0:
            paid_ship["cargo"].erase(commodity)
            if paid_ship.get("cargo_age", null) is Dictionary:
                paid_ship["cargo_age"].erase(commodity)
            if paid_ship.get("cargo_origin", null) is Dictionary:
                paid_ship["cargo_origin"].erase(commodity)
        else:
            paid_ship["cargo"][commodity] = remaining
        if contract_type == "construction":
            var site: Dictionary = staged["construction_sites"][site_index]
            site["progress_delivered"] += int(qty)
            site["dirty"] = true
            events.append({"kind": "construction_progress", "site_id": site.get("id", null),
                "progress": 1.0 if int(site["progress_required"]) == 0 else
                    clampf(float(site["progress_delivered"]) /
                        float(site["progress_required"]), 0.0, 1.0),
                "location": at,
                "labor_completed": (site.get("labor", {}) as Dictionary).get("completed", null),
                "labor_required": (site.get("labor", {}) as Dictionary).get("required", null)})
            events.append({"kind": "contract_delivered", "contract_id": contract_id,
                "contract_type": contract_type, "commodity": commodity,
                "source": contract.get("source_location", null), "destination": at,
                "quantity": int(qty), "ship_id": ship_id,
                "payment": payment, "faction_id": contract.get("faction_id", null)})
        else:
            if household:
                var hh: Dictionary = staged["populations"][pop_id]
                hh["sentiment"]["food_satisfaction"] = mini(100,
                    int(hh["sentiment"].get("food_satisfaction", 0)) + FOOD_SAT_RECOVER_ON_MET)
                hh["sentiment"]["dirty"] = true
                events.append({"kind": "household_delivery_consumed",
                    "tick": tick, "population_id": pop_id,
                    "contract_id": contract_id, "quantity": int(qty)})
            else:
                var market: Dictionary = staged["markets"][at]
                market["supply"][commodity] = float(
                    market["supply"].get(commodity, 0.0)) + float(qty)
                if market.get("history", null) is Dictionary:
                    market["history"]["dirty"] = true
            events.append({"kind": "contract_delivered", "contract_id": contract_id,
                "contract_type": contract_type, "commodity": commodity,
                "destination": at, "payment": payment,
                "faction_id": contract.get("faction_id", null)})
    if paid_ship.has("crew_task"):
        paid_ship["crew_task"] = "unloading"
    _grant_skill(paid_ship, "trading", 1)
    _grant_skill(paid_ship, "navigation", 1)
    return {"ok": true, "world": staged, "events": events,
        "quantity": float(qty), "payment": payment}

## Rust transactions.rs::market_at. Only the legitimate operator's
## facility is a market backing, not an order-book/anonymous credit source.
static func _market_preflight(world: Dictionary, market: Dictionary,
        ship_faction: String, location: String) -> Dictionary:
    var fac_id: String = str(market.get("facility_id", ""))
    if fac_id.is_empty():
        return _bad("missing_market_owner")
    var facilities: Variant = world.get("facilities", null)
    if not (facilities is Dictionary):
        return _bad("missing_seller")
    var facility: Variant = facilities.get(fac_id, null)
    if not (facility is Dictionary):
        return _bad("missing_seller")
    if bool(facility.get("abandoned", false)):
        return _bad("seller_abandoned")
    if str(market.get("location", "")) != location             or str(facility.get("location", "")) != location:
        return _bad("wrong_market_location")
    var rel: Variant = world.get("relations", null)
    if not (rel is Dictionary):
        return _bad("missing_relations")
    var allowed: Dictionary = Quote.commerce_allowed(rel, ship_faction,
        str(facility.get("faction_id", "")))
    if not bool(allowed.get("ok", false)):
        return allowed
    if not bool(allowed.get("allowed", false)):
        return _bad("embargo")
    return {"ok": true}

static func _grant_skill(ship: Dictionary, skill: String, amount: int) -> void:
    var skills: Variant = ship.get("crew_skills", null)
    if not (skills is Dictionary):
        return
    if not ["navigation", "engineering", "trading", "combat"].has(skill):
        return
    skills[skill] = mini(100, int(skills.get(skill, 0)) + amount)

static func _ship_xp(world: Dictionary, ship: Dictionary,
        ship_id: String, events: Array) -> void:
    var progress: Dictionary = ship["progression"]
    var xp: int = mini(MAX_U32, int(progress.get("xp", 0)) + SHIP_XP_PER_DELIVERY)
    var level: int = int(progress.get("level", 1))
    var points: int = int(progress.get("retrofit_points", 0))
    var gained: int = 0
    while level < SHIP_LEVEL_CAP and xp >= level * 100:
        xp -= level * 100
        level += 1
        points = mini(255, points + 1)
        gained += 1
    progress["level"] = level
    progress["xp"] = xp
    progress["retrofit_points"] = points
    progress["dirty"] = true
    if gained > 0:
        events.append({"kind": "ship_leveled_up", "id": ship_id,
            "new_level": level, "retrofit_points": points,
            "levels_gained": gained})

static func _num(v: Variant) -> bool:
    return (v is int or v is float) and is_finite(float(v))

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
