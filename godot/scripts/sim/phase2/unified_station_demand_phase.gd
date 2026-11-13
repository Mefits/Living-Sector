extends RefCounted
## P2 N135 admission stage: pure, deterministic station demand projection.
## Reads ONLY current N39 market/owner rows. Does not post a contract, reserve
## money, create cargo, or invent a station/ship. A future single Apply must
## validate funding and source stock before admitting these proposals to N104.
static func propose(world: Dictionary, tick: int) -> Dictionary:
    if tick < 0 or not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "missing_canonical_market_or_facilities"}
    var markets: Dictionary = world["markets"]
    var facilities: Dictionary = world["facilities"]
    var proposals: Array[Dictionary] = []
    var blocked: Array[Dictionary] = []
    var locations: Array = markets.keys()
    locations.sort()
    for location in locations:
        var raw = markets[location]
        if not (raw is Dictionary):
            return {"ok": false, "reason": "invalid_market_row"}
        var market: Dictionary = raw
        if not (market.get("supply") is Dictionary) or not (market.get("prices") is Dictionary) or not (market.get("consumption_window") is Dictionary):
            return {"ok": false, "reason": "invalid_market_stock_or_consumption"}
        var owner_id: String = str(market.get("owner", ""))
        if owner_id.is_empty() or not (facilities.get(owner_id) is Dictionary):
            return {"ok": false, "reason": "missing_actual_station_owner"}
        var owner: Dictionary = facilities[owner_id]
        if str(owner.get("location", "")) != str(location):
            return {"ok": false, "reason": "station_market_location_mismatch"}
        var credits: int = int(owner.get("credits", -1))
        if credits < 0:
            return {"ok": false, "reason": "invalid_station_funds"}
        var consumed: Dictionary = market["consumption_window"]
        var commodities: Array = consumed.keys()
        commodities.sort()
        for commodity in commodities:
            # N151/N150 MarketFlow stores real purchases as [{tick, qty}],
            # NOT a scalar rate or the seed's static market.demand.
            var entries = consumed[commodity]
            if not (entries is Array):
                return {"ok": false, "reason": "invalid_consumption_window"}
            var consumed_amount: float = 0.0
            for entry in entries:
                if not (entry is Dictionary) or not (entry.get("qty") is int or entry.get("qty") is float):
                    return {"ok": false, "reason": "invalid_consumption_receipt"}
                var qty: float = float(entry["qty"])
                if not is_finite(qty) or qty < 0.0 or not (entry.get("tick") is int or entry.get("tick") is float):
                    return {"ok": false, "reason": "invalid_consumption_receipt"}
                if float(entry["tick"]) > float(tick):
                    return {"ok": false, "reason": "future_consumption_receipt"}
                consumed_amount += qty
            var stock_value = market["supply"].get(commodity, 0.0)
            var price_value = market["prices"].get(commodity, null)
            if not (stock_value is int or stock_value is float):
                return {"ok": false, "reason": "invalid_demand_or_stock"}
            var stock: float = float(stock_value)
            if not is_finite(consumed_amount) or not is_finite(stock) or consumed_amount < 0.0 or stock < 0.0:
                return {"ok": false, "reason": "nonfinite_demand_or_stock"}
            if consumed_amount <= stock or consumed_amount <= 0.0:
                continue
            if not (price_value is int or price_value is float) or not is_finite(float(price_value)) or float(price_value) <= 0.0:
                blocked.append({"location": str(location), "commodity": str(commodity), "reason": "missing_market_price"})
                continue
            var deficit: float = ceil(consumed_amount - stock)
            if deficit > 2147483647.0:
                return {"ok": false, "reason": "demand_overflow"}
            var quantity: int = int(deficit)
            var estimated_cost: float = ceil(float(quantity) * float(price_value))
            if not is_finite(estimated_cost) or estimated_cost > 9007199254740991.0:
                return {"ok": false, "reason": "cost_overflow"}
            var row: Dictionary = {
                "id": "n135:need:%s:%s" % [str(location), str(commodity)],
                "tick": tick, "station_id": owner_id,
                "location": str(location), "faction": str(owner.get("faction", "")),
                "commodity": str(commodity), "quantity": quantity,
                "observed_consumption": consumed_amount, "observed_stock": stock,
                "estimated_cost": int(estimated_cost),
                "reason": "observed_consumption_exceeds_physical_market_stock",
                "status": "UNFUNDED_PROPOSAL"
            }
            if credits < int(estimated_cost):
                blocked.append({"location": str(location), "commodity": str(commodity),
                    "reason": "station_cannot_fund_purchase", "needed": int(estimated_cost),
                    "available": credits})
            else:
                proposals.append(row)
    return {"ok": true, "tick": tick, "proposals": proposals, "blocked": blocked,
        "status": "PROPOSALS_ONLY_NOT_POSTED"}
