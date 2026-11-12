extends SceneTree
## Run: godot --headless --path godot --script res://tests/n25_order_settlement_smoke.gd
const Market = preload("res://scripts/sim/economy/native_order_settlement.gd")

func _initialize() -> void:
	var bids := [{"id": 1, "agent_id": "buyer", "commodity": "ore", "quantity": 200, "price": 50.0}]
	var asks := [{"id": 2, "agent_id": "seller", "commodity": "ore", "quantity": 80, "price": 40.0}]
	var matched: Dictionary = Market.match_orders(bids, asks, 0.10)
	assert(matched["ok"])
	assert(matched["trades"].size() == 1)
	assert(matched["trades"][0]["quantity"] == 80)
	assert(absf(matched["trades"][0]["price"] - 42.75) < 0.0001)
	assert(matched["remaining_buys"][0]["quantity"] == 120)
	assert(matched["remaining_sells"].is_empty())
	assert(bids[0]["quantity"] == 200) # pure matching
	var funds := {"buyer": 5000.0, "seller": 100.0}
	var goods := {"buyer": {"ore": 0}, "seller": {"ore": 100}}
	var receipts := {}
	var loc := {"buyer": "sol", "seller": "sol"}
	var trade: Dictionary = matched["trades"][0]
	var paid: Dictionary = Market.settle(trade, funds, goods, receipts, "t1", loc)
	assert(paid["ok"])
	assert(funds["buyer"] == 1580.0 and funds["seller"] == 3520.0)
	assert(goods["buyer"]["ore"] == 80 and goods["seller"]["ore"] == 20)
	assert(not Market.settle(trade, funds, goods, receipts, "t1", loc)["ok"])
	var snap := Market.snapshot(funds, goods, receipts)
	var restored: Dictionary = Market.restore(snap)
	assert(restored["ok"])
	assert(restored["balances"] == funds and restored["inventories"] == goods)
	var before := JSON.stringify(Market.snapshot(funds, goods, receipts))
	var broke := trade.duplicate(true)
	broke["quantity"] = 1000
	assert(not Market.settle(broke, funds, goods, receipts, "t2", loc)["ok"])
	broke["quantity"] = 80
	broke["total_cost"] = 999999.0
	assert(not Market.settle(broke, funds, goods, receipts, "t3", loc)["ok"])
	loc["seller"] = "alpha"
	assert(not Market.settle(trade, funds, goods, receipts, "t4", loc)["ok"])
	assert(JSON.stringify(Market.snapshot(funds, goods, receipts)) == before)
	var no_cross := Market.match_orders([{"id": 3, "agent_id": "b", "commodity": "ore", "quantity": 1, "price": 30.0}], [{"id": 4, "agent_id": "s", "commodity": "ore", "quantity": 1, "price": 40.0}], 0.0)
	assert(no_cross["trades"].is_empty())
	print("N25 PASS: Rust price, partial fill, conservation, idempotence, no overdraft, co-location, restore")
	quit(0)
