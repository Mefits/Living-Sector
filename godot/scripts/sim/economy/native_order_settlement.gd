extends RefCounted
## N25: Rust order_book.rs matching + local atomic settlement.
## State is plain data; no per-agent Nodes. Godot runtime: CODE_UNVERIFIED.

static func match_orders(buys: Array, sells: Array, spread: float) -> Dictionary:
	var bids: Array = buys.duplicate(true)
	var asks: Array = sells.duplicate(true)
	# Rust sorts descending bids and ascending asks. ID is a deterministic tie-break.
	bids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["price"]) != float(b["price"]):
			return float(a["price"]) > float(b["price"])
		return int(a["id"]) < int(b["id"]))
	asks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["price"]) != float(b["price"]):
			return float(a["price"]) < float(b["price"])
		return int(a["id"]) < int(b["id"]))
	var trades: Array = []
	var i := 0
	var j := 0
	while i < bids.size() and j < asks.size():
		var bid: Dictionary = bids[i]
		var ask: Dictionary = asks[j]
		if float(bid["price"]) < float(ask["price"]):
			break
		# Rust matches one commodity per book; never cross-match different goods.
		if str(bid["commodity"]) != str(ask["commodity"]):
			return {"ok": false, "error": "mixed_commodity_book"}
		var qty: int = mini(int(bid["quantity"]), int(ask["quantity"]))
		if qty <= 0:
			return {"ok": false, "error": "non_positive_quantity"}
		var price: float = (float(bid["price"]) + float(ask["price"])) * 0.5 * (1.0 - spread * 0.5)
		trades.append({"buyer_id": str(bid["agent_id"]), "seller_id": str(ask["agent_id"]), "commodity": str(bid["commodity"]), "quantity": qty, "price": price, "total_cost": price * float(qty), "buy_order_id": int(bid["id"]), "sell_order_id": int(ask["id"])})
		bid["quantity"] = int(bid["quantity"]) - qty
		ask["quantity"] = int(ask["quantity"]) - qty
		if int(bid["quantity"]) == 0:
			i += 1
		if int(ask["quantity"]) == 0:
			j += 1
	return {"ok": true, "trades": trades, "remaining_buys": bids.slice(i), "remaining_sells": asks.slice(j)}


static func settle(trade: Dictionary, balances: Dictionary, inventories: Dictionary, receipts: Dictionary, receipt_id: String, location_by_agent: Dictionary = {}) -> Dictionary:
	# Caller owns state. All validation happens before the first mutation.
	if receipts.has(receipt_id):
		return {"ok": false, "error": "duplicate_receipt"}
	var buyer := str(trade.get("buyer_id", ""))
	var seller := str(trade.get("seller_id", ""))
	var good := str(trade.get("commodity", ""))
	var qty := int(trade.get("quantity", 0))
	var cost := float(trade.get("total_cost", -1.0))
	if buyer.is_empty() or seller.is_empty() or buyer == seller or good.is_empty() or qty <= 0 or not is_finite(cost) or cost < 0.0:
		return {"ok": false, "error": "invalid_trade"}
	if not balances.has(buyer) or not balances.has(seller) or not inventories.has(buyer) or not inventories.has(seller):
		return {"ok": false, "error": "missing_account"}
	if not location_by_agent.is_empty() and (not location_by_agent.has(buyer) or not location_by_agent.has(seller) or location_by_agent[buyer] != location_by_agent[seller]):
		return {"ok": false, "error": "not_colocated"}
	var bstock: Dictionary = inventories[buyer]
	var sstock: Dictionary = inventories[seller]
	var available := int(sstock.get(good, 0))
	var buyer_money := float(balances[buyer])
	if available < qty:
		return {"ok": false, "error": "insufficient_stock"}
	if buyer_money < cost:
		return {"ok": false, "error": "insufficient_funds"}
	if not is_finite(buyer_money) or not is_finite(float(balances[seller])):
		return {"ok": false, "error": "invalid_balance"}
	# Inventory is transferred, not created; money moves between real accounts.
	sstock[good] = available - qty
	bstock[good] = int(bstock.get(good, 0)) + qty
	balances[buyer] = buyer_money - cost
	balances[seller] = float(balances[seller]) + cost
	receipts[receipt_id] = trade.duplicate(true)
	return {"ok": true, "receipt_id": receipt_id}


static func snapshot(balances: Dictionary, inventories: Dictionary, receipts: Dictionary) -> Dictionary:
	return {"schema": 1, "balances": balances.duplicate(true), "inventories": inventories.duplicate(true), "receipts": receipts.duplicate(true)}


static func restore(data: Dictionary) -> Dictionary:
	if int(data.get("schema", -1)) != 1:
		return {"ok": false, "error": "unsupported_schema"}
	for key in ["balances", "inventories", "receipts"]:
		if not data.has(key) or not (data[key] is Dictionary):
			return {"ok": false, "error": "invalid_" + key}
	return {"ok": true, "balances": data["balances"].duplicate(true), "inventories": data["inventories"].duplicate(true), "receipts": data["receipts"].duplicate(true)}
