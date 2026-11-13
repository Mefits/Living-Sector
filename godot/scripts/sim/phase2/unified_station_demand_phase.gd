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
    # Proposal-only reservations prevent two destinations claiming the same
    # physical stock or one station spending its credits twice in one tick.
    # These are NOT canonical escrow or stock mutations.
    var proposed_source_stock: Dictionary = {}
    var proposed_station_spend: Dictionary = {}
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
            # N135 may split one real deficit across multiple source stations.
            # A proposal cannot reserve stock twice, and the destination may
            # not promise more money than its actual current station credits.
            var remaining: int = quantity
            var sources: Array = markets.keys()
            sources.sort()
            for source in sources:
                if remaining <= 0:
                    break
                if str(source) == str(location):
                    continue
                var source_market = markets[source]
                if not (source_market is Dictionary) or not (source_market.get("supply") is Dictionary):
                    continue
                var source_owner_id: String = str(source_market.get("owner", ""))
                if not (facilities.get(source_owner_id) is Dictionary):
                    continue
                if str(facilities[source_owner_id].get("location", "")) != str(source):
                    continue
                var raw_available = source_market["supply"].get(commodity, 0.0)
                if not (raw_available is int or raw_available is float):
                    continue
                var physical_available: float = float(raw_available)
                if not is_finite(physical_available) or physical_available < 0.0:
                    return {"ok": false, "reason": "invalid_supplier_stock"}
                var source_key: String = "%s:%s" % [str(source), str(commodity)]
                var already_proposed: int = int(proposed_source_stock.get(source_key, 0))
                var available: int = maxi(0, int(minf(floor(physical_available), 2147483647.0)) - already_proposed)
                if available <= 0:
                    continue
                var station_spend: int = int(proposed_station_spend.get(owner_id, 0))
                var price: float = float(price_value)
                var affordable: int = maxi(0, int(floor(float(credits - station_spend) / price)))
                var allocated: int = mini(remaining, mini(available, affordable))
                if allocated <= 0:
                    continue
                var cost_float: float = ceil(float(allocated) * price)
                if not is_finite(cost_float) or cost_float > 9007199254740991.0:
                    return {"ok": false, "reason": "cost_overflow"}
                var cost: int = int(cost_float)
                # Ceil on the full order can exceed a fractional unit budget.
                while allocated > 0 and cost > credits - station_spend:
                    allocated -= 1
                    cost = int(ceil(float(allocated) * price))
                if allocated <= 0:
                    continue
                var row: Dictionary = {
                    "id": "n135:need:%s:%s:%s" % [str(location), str(commodity), str(source)],
                    "tick": tick, "station_id": owner_id,
                    "location": str(location), "faction": str(owner.get("faction", "")),
                    "source_location": str(source),
                    "source_station_id": source_owner_id,
                    "source_available_stock": physical_available,
                    "commodity": str(commodity), "quantity": allocated,
                    "observed_consumption": consumed_amount, "observed_stock": stock,
                    "estimated_cost": cost,
                    "reason": "observed_consumption_exceeds_physical_market_stock",
                    "status": "UNFUNDED_PROPOSAL"
                }
                proposals.append(row)
                proposed_source_stock[source_key] = already_proposed + allocated
                proposed_station_spend[owner_id] = station_spend + cost
                remaining -= allocated
            if remaining > 0:
                blocked.append({"location": str(location), "commodity": str(commodity),
                    "reason": "insufficient_unreserved_stock_or_funds",
                    "unfilled_quantity": remaining,
                    "available_funds": maxi(0, credits - int(proposed_station_spend.get(owner_id, 0)))})
    return {"ok": true, "tick": tick, "proposals": proposals, "blocked": blocked,
        "status": "PROPOSALS_ONLY_NOT_POSTED"}

