extends RefCounted
## Rust engine/transactions.rs::mine/refuel on actual N39 World.
## N90 exclusively owns the source request. P1 original N97 physical
## settlement runs on a detached view, then results are reconciled
## against the ONE N9 ledger and current body/market/facility/ship.
## This file is pure: it cannot publish money, free fuel, ice or XP.
const SourceN97 = preload("res://scripts/port/n97_ship_transaction_apply.gd")
const N90 = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const N9 = preload("res://scripts/sim/economy/credit_ledger.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")

static func _bad(why: String) -> Dictionary:
    return {"ok": false, "reason": "n97_service_" + why}

## Native source Apply rejection must acknowledge the ONE N90
## pending request without changing any physical/financial domain.
## This is used only for genuine physical rejection (missing port,
## not at a registered mining body); corrupted authority still fails.
static func _rejected(world: Dictionary, ledger_snapshot: Dictionary,
        ship_id: String, request_id: int, tick: int,
        kind: String, why: String) -> Dictionary:
    var staged: Dictionary = world.duplicate(true)
    var ship: Dictionary = staged["ships"][ship_id]
    var reply: Dictionary = N90.acknowledge(
        ship["transaction"], request_id, false)
    if not reply.get("ok", false):
        return _bad("source_negative_ack_cannot_be_persisted")
    ship["transaction"] = reply["state"].duplicate(true)
    return {"ok": true, "status": "rejected", "world": staged,
        "ledger_snapshot": ledger_snapshot.duplicate(true),
        "kind": kind, "tick": tick, "ship_id": ship_id,
        "request_id": request_id, "reason": why}


static func _source_view(world: Dictionary, resolver: RefCounted,
        ship_id: String, request: Dictionary) -> Dictionary:
    if not (world.get("ships") is Dictionary) or not world["ships"].has(ship_id):
        return _bad("missing_actual_ship")
    if not (world.get("bodies") is Dictionary) or not (
            world.get("facilities") is Dictionary) or not (
            world.get("markets") is Dictionary) or resolver == null:
        return _bad("missing_original_physical_registry")
    if not resolver.has_method("source_system_offset_for_body") or not (
            resolver.has_method("system_for_location") and resolver.has_method(
            "body_for_location")):
        return _bad("missing_source_orbit_registry")
    var ship: Dictionary = world["ships"][ship_id]
    var kind: String = str(request.get("kind", ""))
    var loc: String = str(request.get("location", ""))
    if loc.is_empty() or loc != str(ship.get("location", "")):
        return _bad("request_location_not_reached")
    var projected_ship: Dictionary = ship.duplicate(true)
    projected_ship["crew_task"] = str(ship.get("crew", {}).get(
        "current_task", "idle"))
    var view: Dictionary = {
        "ships": {}, "facilities": {}, "markets": {},
        "bodies": {}, "relations": {}, "market_controllers": {}
    }
    view["ships"][ship_id] = projected_ship
    if kind == "mine":
        var body_id: String = str(request.get("body_id", ""))
        if body_id.is_empty() or not world["bodies"].has(body_id):
            return _bad("missing_real_deposit_body")
        # Rust ShipPosition.universe_offset is the system offset, not
        # the current orbital pixel/vector of a rendered planet.
        if resolver.body_for_location(loc) != body_id or (
                resolver.system_for_location(loc) != str(ship.get("system_id", ""))):
            return _bad("mining_ship_not_in_original_body_system")
        var offset: Array = resolver.source_system_offset_for_body(body_id)
        if offset.size() != 2:
            return _bad("missing_original_body_system_offset")
        var body: Dictionary = world["bodies"][body_id].duplicate(true)
        body["body_id"] = body_id
        body["universe_offset"] = offset.duplicate(true)
        view["bodies"][body_id] = body
        projected_ship["universe_offset"] = offset.duplicate(true)
        # N39 represents undocked as ""; the Rust N97 fixture uses
        # Option::None. Never change canonical N39 dock authority.
        if str(ship.get("docked_at", "")).is_empty():
            projected_ship["docked_at"] = null
        return {"ok": true, "world": view, "kind": kind,
            "body_id": body_id, "location": loc}
    if kind != "refuel":
        return _bad("not_source_ship_service_kind")
    var dock_id: String = str(ship.get("docked_at", ""))
    if dock_id.is_empty() or not world["facilities"].has(dock_id):
        return _bad("no_actual_native_fuel_operator")
    var real_dock: Dictionary = world["facilities"][dock_id]
    if str(real_dock.get("location", "")) != loc:
        return _bad("real_dock_not_at_ships_location")
    var fac: Dictionary = real_dock.duplicate(true)
    fac["faction_id"] = str(real_dock.get("faction", ""))
    var actual_occupants: Array = []
    for other_id in world["ships"]:
        var other: Dictionary = world["ships"][other_id]
        if str(other.get("docked_at", "")) == dock_id:
            actual_occupants.append(str(other_id))
    fac["docked_ships"] = actual_occupants
    view["facilities"][dock_id] = fac
    var pairs: Variant = world.get("faction_relations", {})
    if not (pairs is Dictionary) or not Relations.validate_pairs(pairs):
        return _bad("invalid_original_relations")
    for row in pairs.values():
        var a: String = str(row.get("a", ""))
        var b: String = str(row.get("b", ""))
        if a.is_empty() or b.is_empty():
            return _bad("invalid_real_treaty_parties")
        view["relations"][a + "\u001f" + b] = str(row.get("treaty", "neutral"))
    view["market_controllers"][loc] = str(real_dock.get("faction", ""))
    if world["markets"].has(loc):
        var market: Dictionary = world["markets"][loc].duplicate(true)
        var operator: String = str(market.get("owner", ""))
        market["facility_id"] = operator
        market["location"] = loc
        view["markets"][loc] = market
        if world["facilities"].has(operator) and operator != dock_id:
            var seller: Dictionary = world["facilities"][operator].duplicate(true)
            seller["faction_id"] = str(seller.get("faction", ""))
            view["facilities"][operator] = seller
        if world["facilities"].has(operator):
            view["market_controllers"][loc] = str(
                world["facilities"][operator].get("faction", ""))
    return {"ok": true, "world": view, "kind": kind,
        "facility_id": dock_id, "location": loc}

static func stage(world: Dictionary, ledger_snapshot: Dictionary,
        resolver: RefCounted, ship_id: String, request_id: int,
        tick: int) -> Dictionary:
    if tick < 1 or request_id < 1 or ship_id.is_empty():
        return _bad("invalid_native_n90_identity")
    if not (world.get("ships") is Dictionary) or not world["ships"].has(ship_id):
        return _bad("unknown_live_ship")
    var ship: Dictionary = world["ships"][ship_id]
    var slot: Variant = ship.get("transaction", null)
    if not (slot is Dictionary) or not N90.valid_slot(slot):
        return _bad("invalid_original_transaction_slot")
    var pending: Variant = slot["pending"]
    if not (pending is Dictionary) or pending.is_empty() or int(
            pending.get("id", -1)) != request_id or pending.get("result", 1) != null:
        return _bad("stale_or_replayed_n90_request")
    var request: Variant = pending.get("request", null)
    if not (request is Dictionary) or str(request.get(
            "kind", "")) not in ["mine", "refuel"]:
        return _bad("non_service_original_n90_request")
    var kind: String = str(request["kind"])
    var projection: Dictionary = _source_view(world, resolver, ship_id, request)
    if not projection.get("ok", false):
        var physical: String = str(projection.get("reason", ""))
        if physical in [
                "n97_service_request_location_not_reached",
                "n97_service_mining_ship_not_in_original_body_system",
                "n97_service_missing_real_deposit_body",
                "n97_service_no_actual_native_fuel_operator",
                "n97_service_real_dock_not_at_ships_location"]:
            return _rejected(world, ledger_snapshot, ship_id,
                request_id, tick, kind, physical)
        return projection
    var p_world: Dictionary = projection["world"]
    var outcome: Dictionary = SourceN97.apply(p_world, ship_id, request_id, tick)
    if not outcome.get("ok", false):
        return _bad("original_n97_" + str(outcome.get("reason", "invalid")))
    var accepted_status: String = str(outcome.get("status", ""))
    if accepted_status not in ["applied", "rejected"]:
        return _bad("original_n97_unexpected_status")
    var detached: Dictionary = outcome["world"]
    var projected_ship: Dictionary = detached["ships"][ship_id]
    var next_world: Dictionary = world.duplicate(true)
    var live_ship: Dictionary = next_world["ships"][ship_id]
    live_ship["transaction"] = projected_ship["transaction"].duplicate(true)
    if accepted_status == "rejected":
        return {"ok": true, "status": "rejected", "world": next_world,
            "ledger_snapshot": ledger_snapshot.duplicate(true),
            "tick": tick, "ship_id": ship_id, "request_id": request_id,
            "kind": kind, "reason": str(outcome.get("reason", ""))}
    var transferred: float = float(outcome.get("quantity", NAN))
    var payment: int = int(outcome.get("payment", -1))
    if not is_finite(transferred) or transferred <= 0.0 or payment < 0:
        return _bad("invalid_source_service_amount")
    var receipt_id: String = "n97:service:" + ship_id + ":" + str(request_id)
    if not (next_world.get("cargo_receipts") is Dictionary) or (
            next_world["cargo_receipts"].has(receipt_id)):
        return _bad("missing_or_duplicate_source_physical_receipt")
    var next_ledger: Dictionary = ledger_snapshot.duplicate(true)
    var details: Dictionary = {
        "operation_id": receipt_id, "tick": tick,
        "kind": "native_n97_" + kind, "ship_id": ship_id,
        "location": str(request["location"]), "request_id": request_id,
        "quantity": transferred, "payment": payment, "quantities": {}
    }
    if kind == "refuel":
        var fid: String = str(projection.get("facility_id", ""))
        var p_facility: Dictionary = detached["facilities"][fid]
        var actual_fac: Dictionary = world["facilities"][fid]
        if payment <= 0 or int(projected_ship.get("credits", -1)) != int(ship.get(
                "credits", -1)) - payment or int(p_facility.get("credits", -1)) != int(
                actual_fac.get("credits", -1)) + payment:
            return _bad("source_refuel_did_not_settle_exact_money")
        if not is_equal_approx(float(projected_ship.get(
                "fuel", NAN)) - float(ship.get("fuel", NAN)), transferred):
            return _bad("source_refuel_did_not_add_real_fuel")
        var before_reserve: float = float(actual_fac.get(
            "reserves", {}).get("fuel", 0.0))
        var after_reserve: float = float(p_facility.get(
            "reserves", {}).get("fuel", NAN))
        var from_reserve: float = before_reserve - after_reserve
        var loc: String = str(request["location"])
        var from_market: float = 0.0
        if world["markets"].has(loc):
            var before_supply: float = float(world["markets"][loc].get(
                "supply", {}).get("fuel", 0.0))
            var after_supply: float = float(detached["markets"][loc].get(
                "supply", {}).get("fuel", NAN))
            from_market = before_supply - after_supply
            if from_market < -0.00001 or not is_finite(from_market):
                return _bad("invalid_real_market_fuel_outflow")
            next_world["markets"][loc]["supply"] = detached["markets"][loc][
                "supply"].duplicate(true)
            if from_market > 0.0:
                next_world["markets"][loc]["dirty"] = true
        if from_reserve < -0.00001 or not is_finite(from_reserve) or not (
                is_equal_approx(from_reserve + from_market, transferred)):
            return _bad("refuel_created_source_fuel")
        var money := N9.new()
        if not money.restore(ledger_snapshot):
            return _bad("invalid_canonical_n9_snapshot")
        var paid: Dictionary = money.transfer(
            receipt_id, "ship:" + ship_id, "facility:" + fid,
            payment, tick, "native_n97_refuel")
        if not paid.get("ok", false):
            return _bad("n9_real_refuel_" + str(paid.get("reason", "rejected")))
        if money.balance("ship:" + ship_id) != int(projected_ship[
                "credits"]) or money.balance("facility:" + fid) != int(
                p_facility["credits"]):
            return _bad("n97_and_real_n9_refuel_cash_mismatch")
        next_ledger = money.snapshot()
        live_ship["fuel"] = float(projected_ship["fuel"])
        live_ship["credits"] = int(projected_ship["credits"])
        next_world["facilities"][fid]["reserves"] = p_facility[
            "reserves"].duplicate(true)
        next_world["facilities"][fid]["credits"] = int(
            p_facility["credits"])
        next_world["facilities"][fid]["dirty"] = true
        details["facility_id"] = fid
        details["from_reserve"] = from_reserve
        details["from_market"] = from_market
        details["financial_receipt"] = receipt_id
    else:
        var bid: String = str(projection.get("body_id", ""))
        if payment != 0 or not is_equal_approx(
                transferred, float(roundi(transferred))):
            return _bad("mining_source_took_money_or_partial_ice")
        var extracted: int = roundi(transferred)
        var before_richness: float = float(world["bodies"][bid].get(
            "resources", {}).get("ice", NAN))
        var after_richness: float = float(detached["bodies"][bid].get(
            "resources", {}).get("ice", NAN))
        if not is_finite(before_richness) or not is_finite(after_richness) or (
                after_richness > before_richness) or not is_equal_approx(
                before_richness - after_richness, transferred / 8000.0):
            return _bad("mining_ice_not_debited_from_original_body")
        if int(projected_ship["cargo"].get("ice", 0)) - int(
                ship["cargo"].get("ice", 0)) != extracted or (
                int(projected_ship.get("credits", -1)) != int(
                ship.get("credits", -1))):
            return _bad("mining_real_hold_not_balanced")
        live_ship["cargo"] = projected_ship["cargo"].duplicate(true)
        live_ship["cargo_age"] = projected_ship["cargo_age"].duplicate(true)
        live_ship["crew_skills"] = projected_ship["crew_skills"].duplicate(true)
        if live_ship.get("crew") is Dictionary:
            live_ship["crew"]["current_task"] = str(
                projected_ship.get("crew_task", "engineering"))
        next_world["bodies"][bid]["resources"] = detached["bodies"][bid][
            "resources"].duplicate(true)
        details["body_id"] = bid
        details["quantity"] = extracted
        details["quantities"]["ice"] = extracted
    next_world["cargo_receipts"][receipt_id] = details.duplicate(true)
    return {"ok": true, "status": "applied", "world": next_world,
        "ledger_snapshot": next_ledger, "receipt": details,
        "ship_id": ship_id, "request_id": request_id,
        "kind": kind, "tick": tick, "payment": payment,
        "quantity": details["quantity"]}
