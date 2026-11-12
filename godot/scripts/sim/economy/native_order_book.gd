extends RefCounted
## N10: pure native order_book.rs matching. No trades are settled here.
## Rust uses f32 midpoint*(1-spread/2) without cent rounding for trades.
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")

static func valid_order(order: Dictionary, side: String) -> bool:
    if str(order.get("order_type", "")) != side or not Catalog.contains(str(order.get("commodity", ""))):
        return false
    if str(order.get("agent_id", "")).is_empty():
        return false
    if typeof(order.get("id")) != TYPE_INT or int(order["id"]) < 0:
        return false
    if typeof(order.get("placed_at_tick")) != TYPE_INT or int(order["placed_at_tick"]) < 0:
        return false
    if typeof(order.get("quantity")) != TYPE_INT or int(order["quantity"]) <= 0:
        return false
    var price: float = float(order.get("price", -1.0))
    return is_finite(price) and price > 0.0

static func _buy_before(a: Dictionary, b: Dictionary) -> bool:
    if float(a["price"]) != float(b["price"]):
        return float(a["price"]) > float(b["price"])
    return int(a["id"]) < int(b["id"])

static func _sell_before(a: Dictionary, b: Dictionary) -> bool:
    if float(a["price"]) != float(b["price"]):
        return float(a["price"]) < float(b["price"])
    return int(a["id"]) < int(b["id"])

## One commodity per matching call; Rust order book is commodity-scoped at caller.
## Result: trades, remaining_buys, remaining_sells or {} on invalid input.
static func match_orders(buys: Array, sells: Array, spread: float) -> Dictionary:
    if not is_finite(spread) or spread < 0.0 or spread >= 2.0:
        return {}
    var bid: Array = []
    var ask: Array = []
    var commodity := ""
    var ids := {}
    for source in [buys, sells]:
        var side := "buy" if source == buys else "sell"
        for entry in source:
            if not entry is Dictionary or not valid_order(entry, side):
                return {}
            if ids.has(entry["id"]):
                return {}
            ids[entry["id"]] = true
            if commodity != "" and commodity != entry["commodity"]:
                return {}
            commodity = entry["commodity"]
            if side == "buy":
                bid.append(entry.duplicate(true))
            else:
                ask.append(entry.duplicate(true))
    bid.sort_custom(_buy_before)
    ask.sort_custom(_sell_before)
    var trades: Array = []
    var i := 0
    var j := 0
    while i < bid.size() and j < ask.size():
        var b: Dictionary = bid[i]
        var s: Dictionary = ask[j]
        if float(b["price"]) < float(s["price"]):
            break
        var quantity: int = mini(int(b["quantity"]), int(s["quantity"]))
        var trade_price: float = (float(b["price"]) + float(s["price"])) / 2.0 * (1.0 - spread / 2.0)
        trades.append({"buyer_id": b["agent_id"], "seller_id": s["agent_id"], "buy_order_id": b["id"], "sell_order_id": s["id"], "commodity": commodity, "quantity": quantity, "price": trade_price, "total_cost": trade_price * float(quantity)})
        b["quantity"] = int(b["quantity"]) - quantity
        s["quantity"] = int(s["quantity"]) - quantity
        if b["quantity"] == 0:
            i += 1
        if s["quantity"] == 0:
            j += 1
    return {"trades": trades, "remaining_buys": bid.slice(i), "remaining_sells": ask.slice(j)}
