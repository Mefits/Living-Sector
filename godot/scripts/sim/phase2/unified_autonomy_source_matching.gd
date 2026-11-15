extends RefCounted
## N135 -> N104 admission preparation, pure canonical-world sourcing.
## A source is only a physical market candidate, NOT a valid transport route
## or an escrow-backed contract. N153 must still validate the native graph,
## ship capability and funding before any single-world Apply.
static func match_sources(world: Dictionary, demand: Dictionary) -> Dictionary:
    if not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "canonical_markets_missing"}
    if not bool(demand.get("ok", false)) or not (demand.get("proposals") is Array):
        return {"ok": false, "reason": "n135_demand_not_valid"}
    var markets: Dictionary = world["markets"]
    var facilities: Dictionary = world["facilities"]
    var candidates: Array[Dictionary] = []
    var blocked: Array[Dictionary] = []
    var needs: Array = demand["proposals"].duplicate(true)
    needs.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
    var locations: Array = markets.keys()
    locations.sort()
    for raw_need in needs:
        if not (raw_need is Dictionary):
            return {"ok": false, "reason": "invalid_n135_need"}
        var need: Dictionary = raw_need
        var need_id: String = str(need.get("id", ""))
        var destination: String = str(need.get("location", ""))
        var commodity: String = str(need.get("commodity", ""))
        var quantity: int = int(need.get("quantity", 0))
        var payer: String = str(need.get("station_id", ""))
        if need_id.is_empty() or destination.is_empty() or commodity.is_empty() or quantity <= 0:
            return {"ok": false, "reason": "invalid_n135_terms"}
        if not facilities.has(payer) or not (facilities[payer] is Dictionary):
            return {"ok": false, "reason": "missing_n135_payer"}
        if str(facilities[payer].get("location", "")) != destination:
            return {"ok": false, "reason": "n135_payer_location_mismatch"}
        var found: bool = false
        for location in locations:
            if str(location) == destination:
                continue
            var raw_market: Variant = markets[location]
            if not (raw_market is Dictionary):
                return {"ok": false, "reason": "invalid_source_market"}
            var market: Dictionary = raw_market
            if not (market.get("supply") is Dictionary) or not (market.get("prices") is Dictionary):
                return {"ok": false, "reason": "invalid_source_inventory"}
            var owner: String = str(market.get("owner", ""))
            if not facilities.has(owner) or not (facilities[owner] is Dictionary):
                return {"ok": false, "reason": "missing_source_owner"}
            if str(facilities[owner].get("location", "")) != str(location):
                return {"ok": false, "reason": "source_ownership_mismatch"}
            var stock_value: Variant = market["supply"].get(commodity, 0.0)
            var price_value: Variant = market["prices"].get(commodity, null)
            if not (stock_value is int or stock_value is float):
                return {"ok": false, "reason": "invalid_source_stock"}
            var stock: float = float(stock_value)
            if not is_finite(stock) or stock < 0.0:
                return {"ok": false, "reason": "invalid_source_stock"}
            if stock < float(quantity):
                continue
            if not (price_value is int or price_value is float):
                blocked.append({"need_id": need_id, "source": str(location), "reason": "source_price_missing"})
                continue
            var price: float = float(price_value)
            if not is_finite(price) or price <= 0.0:
                blocked.append({"need_id": need_id, "source": str(location), "reason": "source_price_invalid"})
                continue
            var estimated: float = ceil(price * float(quantity))
            if not is_finite(estimated) or estimated > 9007199254740991.0:
                return {"ok": false, "reason": "source_cost_overflow"}
            var available: int = int(facilities[payer].get("credits", -1))
            if available < 0:
                return {"ok": false, "reason": "invalid_payer_balance"}
            if available < int(estimated):
                blocked.append({"need_id": need_id, "source": str(location),
                    "reason": "payer_cannot_fund_source", "required": int(estimated), "available": available})
                continue
            found = true
            candidates.append({
                "need_id": need_id, "payer": payer, "source_owner": owner,
                "source": str(location), "destination": destination,
                "commodity": commodity, "quantity": quantity,
                "source_stock": stock, "estimated_goods_cost": int(estimated),
                "status": "SOURCE_CANDIDATE_NOT_ROUTED_OR_FUNDED"
            })
        if not found:
            blocked.append({"need_id": need_id, "reason": "no_funded_physical_source"})
    return {"ok": true, "candidates": candidates, "blocked": blocked,
        "status": "CANDIDATES_ONLY_NO_CONTRACT_OR_SHIP_ACTION"}
