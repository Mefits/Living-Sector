extends RefCounted
## N130 frozen Rust restock inside the ONE N39 physical World/N9 ledger.
## Order: after N156 paid repair + abandonment, before recipes/mining.
## Services draw only Fuel/Tools (NEVER household Food/Water).
const Restock = preload("res://scripts/sim/facility_restock_n130.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

const INTERVAL: int = 20
const THRESHOLD: float = 100.0
const TARGET: float = 500.0
const COMMODITIES: Array[String] = ["fuel", "tools"]

## Mutates only CALLER'S staged world+ledger. Caller owns atomic swap.
## A failed proposal must prevent that swap, never debit canonical funds.
static func apply(staged: Dictionary, ledger: RefCounted,
        tick: int, multiplier: int) -> Dictionary:
    if tick < 1 or multiplier < 1 or multiplier > 10000:
        return {"ok": false, "reason": "invalid_native_restock_clock"}
    if not (staged.get("facilities") is Dictionary and
            staged.get("markets") is Dictionary and
            staged.get("populations") is Dictionary):
        return {"ok": false, "reason": "missing_authoritative_stocks"}
    if tick % (INTERVAL * multiplier) != 0:
        return {"ok": true, "due": false, "purchases": []}
    var facilities: Dictionary = staged["facilities"]
    var markets: Dictionary = staged["markets"]
    var ids: Array = facilities.keys()
    ids.sort()
    var purchases: Array = []
    # Rust walks the live ECS facilities. Stable ID ordering is explicit
    # here, so limited supplies yield deterministic, replayable receipts.
    for id in ids:
        var buyer: Dictionary = facilities[id]
        if bool(buyer.get("abandoned", false)):
            continue
        var location: String = str(buyer.get("location", ""))
        if not markets.has(location):
            return {"ok": false, "reason": "missing_service_market"}
        var market: Dictionary = markets[location]
        var seller_id: String = str(market.get("owner", ""))
        if not facilities.has(seller_id):
            return {"ok": false, "reason": "missing_service_seller"}
        var seller: Dictionary = facilities[seller_id]
        # N150 faction relations are NOT connected yet. This exact seed
        # contains only same-faction, same-market service trades; never
        # silently authorize unknown inter-faction commerce.
        if str(buyer.get("faction", "")) != str(seller.get("faction", "")):
            continue
        if bool(seller.get("abandoned", false)) or str(seller.get("location", "")) != location:
            continue
        var buyer_reserves: Variant = buyer.get("reserves", {})
        if not (buyer_reserves is Dictionary):
            return {"ok": false, "reason": "invalid_owned_service_reserves"}
        var projected_buyer: Dictionary = {
            "id": str(id), "location": location,
            "credits": int(buyer.get("credits", -1)),
            "abandoned": false,
            "reserves": buyer_reserves.duplicate(true)
        }
        var projected_seller: Dictionary = {
            "id": seller_id, "location": location,
            "credits": int(seller.get("credits", -1)),
            "abandoned": bool(seller.get("abandoned", false)),
            "reserves": seller.get("reserves", {}).duplicate(true)
        }
        var projected_market: Dictionary = {
            "location": location, "supply": market["supply"].duplicate(true),
            "prices": market["prices"].duplicate(true)
        }
        var proposed: Dictionary = Restock.plan(projected_buyer, projected_seller,
            projected_market, COMMODITIES, THRESHOLD, TARGET, true)
        if not bool(proposed.get("ok", false)):
            return {"ok": false, "reason": "native_restock_" + str(proposed.get("reason", "rejected"))}
        if not bool(proposed.get("changed", false)):
            continue
        var is_internal: bool = str(id) == seller_id
        for item in proposed["purchases"]:
            var commodity: String = str(item.get("commodity", ""))
            var qty: float = float(item.get("quantity", 0.0))
            var cost: int = int(item.get("cost", -1))
            if not COMMODITIES.has(commodity) or not is_finite(qty) or qty < 1.0 or cost < 0:
                return {"ok": false, "reason": "invalid_native_restock_ticket"}
            if is_internal:
                if cost != 0:
                    return {"ok": false, "reason": "self_restock_must_be_free"}
            else:
                if cost <= 0:
                    return {"ok": false, "reason": "unpaid_market_restock"}
                var op_id: String = "n130/service/%d/%s/%s" % [tick, str(id), commodity]
                var payment: Dictionary = ledger.transfer(op_id,
                    Schema.facility_account(str(id)),
                    Schema.facility_account(seller_id),
                    cost, tick, "native_service_restock")
                if not payment.get("ok", false):
                    return {"ok": false, "reason": "native_restock_payment_" +
                        str(payment.get("reason", "rejected"))}
            purchases.append({
                "buyer": str(id), "seller": seller_id, "commodity": commodity,
                "quantity": qty, "cost": cost, "tick": tick
            })
        buyer["reserves"] = proposed["buyer"]["reserves"].duplicate(true)
        market["supply"] = proposed["market"]["supply"].duplicate(true)
        buyer["credits"] = ledger.balance(Schema.facility_account(str(id)))
        seller["credits"] = ledger.balance(Schema.facility_account(seller_id))
        if int(buyer["credits"]) != int(proposed["buyer"]["credits"]):
            return {"ok": false, "reason": "buyer_account_restock_mismatch"}
        if int(seller["credits"]) != int(proposed["seller"]["credits"]):
            return {"ok": false, "reason": "seller_account_restock_mismatch"}
    # The call-site commits this WHOLE validated stage, not one purchase.
    return {"ok": true, "due": true, "purchases": purchases}
