extends RefCounted
## N135 -> N104 admission boundary. Pure validation against the SAME N39
## physical World and the SAME N9 ledger snapshot. This does NOT post or
## reserve anything: the unique N39 Apply must commit the escrow transfer and
## board insertion atomically. A successful result is NOT an active contract.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

static func validate(world: Dictionary, ledger_snapshot: Dictionary,
        demand: Dictionary, tick: int, existing_contracts: Dictionary = {}) -> Dictionary:
    if tick < 0 or not (world.get("facilities") is Dictionary) or not (world.get("markets") is Dictionary):
        return _reject("missing_canonical_world")
    if not (ledger_snapshot.get("balances") is Dictionary) or not (ledger_snapshot.get("receipts") is Dictionary):
        return _reject("missing_canonical_ledger")
    if not (demand.get("id") is String) or not str(demand["id"]).begins_with("n135:need:"):
        return _reject("invalid_demand_identity")
    if str(demand.get("status", "")) != "UNFUNDED_PROPOSAL":
        return _reject("not_a_demand_proposal")
    if typeof(demand.get("tick", null)) != TYPE_INT or int(demand["tick"]) > tick:
        return _reject("invalid_demand_tick")
    var id: String = str(demand["id"])
    if existing_contracts.has(id):
        return _reject("already_posted")
    var buyer: String = str(demand.get("station_id", ""))
    var seller: String = str(demand.get("source_station_id", ""))
    var destination: String = str(demand.get("location", ""))
    var source: String = str(demand.get("source_location", ""))
    var commodity: String = str(demand.get("commodity", ""))
    if buyer.is_empty() or seller.is_empty() or buyer == seller or destination.is_empty() or source.is_empty() or destination == source or commodity.is_empty():
        return _reject("invalid_contract_parties")
    var facilities: Dictionary = world["facilities"]
    var markets: Dictionary = world["markets"]
    if not (facilities.get(buyer) is Dictionary) or not (facilities.get(seller) is Dictionary):
        return _reject("missing_physical_station")
    if not (markets.get(source) is Dictionary) or not (markets.get(destination) is Dictionary):
        return _reject("missing_physical_market")
    var buyer_fac: Dictionary = facilities[buyer]
    var seller_fac: Dictionary = facilities[seller]
    var source_market: Dictionary = markets[source]
    var destination_market: Dictionary = markets[destination]
    if str(buyer_fac.get("location", "")) != destination or str(seller_fac.get("location", "")) != source:
        return _reject("station_location_changed")
    if str(source_market.get("owner", "")) != seller or str(destination_market.get("owner", "")) != buyer:
        return _reject("market_owner_changed")
    if not (source_market.get("supply") is Dictionary) or not (destination_market.get("supply") is Dictionary):
        return _reject("invalid_market_inventory")
    if typeof(demand.get("quantity", null)) != TYPE_INT or int(demand["quantity"]) <= 0:
        return _reject("invalid_quantity")
    var quantity: int = int(demand["quantity"])
    var available_value: Variant = source_market["supply"].get(commodity, null)
    if not (available_value is int or available_value is float) or not is_finite(float(available_value)):
        return _reject("invalid_source_stock")
    if float(available_value) < float(quantity):
        return _reject("source_stock_changed")
    if typeof(demand.get("estimated_cost", null)) != TYPE_INT or int(demand["estimated_cost"]) <= 0:
        return _reject("invalid_payment")
    var payment: int = int(demand["estimated_cost"])
    var account: String = Schema.facility_account(buyer)
    var balances: Dictionary = ledger_snapshot["balances"]
    if typeof(balances.get(account, null)) != TYPE_INT or typeof(buyer_fac.get("credits", null)) != TYPE_INT:
        return _reject("missing_payer_account")
    if int(balances[account]) != int(buyer_fac["credits"]):
        return _reject("payer_ledger_world_diverged")
    if int(balances[account]) < payment:
        return _reject("payer_insufficient_funds")
    # Recompute current offer from the destination's real price; never trust
    # a stale proposal after N150 repricing or an arbitrary client payload.
    if not (destination_market.get("prices") is Dictionary):
        return _reject("missing_current_price")
    var price: Variant = destination_market["prices"].get(commodity, null)
    if not (price is int or price is float) or not is_finite(float(price)) or float(price) <= 0.0:
        return _reject("invalid_current_price")
    var current_cost: float = ceil(float(quantity) * float(price))
    if not is_finite(current_cost) or current_cost > 9007199254740991.0 or int(current_cost) != payment:
        return _reject("stale_or_invalid_offer")
    return {"ok": true, "status": "VALIDATED_NOT_COMMITTED",
        "contract_id": id, "kind": "delivery", "payer_account": account,
        "buyer_station_id": buyer, "seller_station_id": seller,
        "source_location": source, "destination_location": destination,
        "commodity": commodity, "quantity": quantity, "payment": payment,
        "validated_at_tick": tick}

static func _reject(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
