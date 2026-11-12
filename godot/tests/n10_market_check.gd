extends SceneTree
const Price = preload("res://scripts/sim/economy/native_price_engine.gd")
const Book = preload("res://scripts/sim/economy/native_order_book.gd")

func _initialize() -> void:
    var errors := 0
    errors += _check(Price.recalculate(100.0, 5.0, 10.0, 0.02, 0) == 101.8, "shortage curve at coverage 0.5")
    errors += _check(Price.recalculate(50.0, 500.0, 10.0, 0.02, 0) == 50.0, "stable coverage")
    errors += _check(Price.recalculate(100.0, 1000.0, 1.0, 0.02, 0) == 99.6, "oversupply drift")
    errors += _check(Price.urgency_multiplier(20) == 1.0 and Price.urgency_multiplier(1000) == 2.5, "urgency bounds")
    errors += _check(Price.recalculate(499.0, 0.0, 1000.0, 0.99, 100) == 500.0, "ceiling")
    errors += _check(Price.recalculate(2.0, 100000.0, 1.0, 0.99, 0) >= 1.0, "floor")
    var quote := Price.apply_spread(100.0, 0.1)
    errors += _check(quote.get("buy") == 105.0 and quote.get("sell") == 95.0, "spread")
    var prices := {"ore": 100.0, "ice": 10.0}
    var before := prices.duplicate(true)
    errors += _check(not Price.reprice_market(prices, {"ore": 0.0}, {"ore": 10.0}, 0.02, {"ice": -1}), "invalid reprice rejects")
    errors += _check(prices == before, "atomic market reprice")
    var buy := {"id": 1, "agent_id": "buyer", "order_type": "buy", "commodity": "ore", "quantity": 100, "price": 50.0, "placed_at_tick": 1}
    var sell := {"id": 2, "agent_id": "miner", "order_type": "sell", "commodity": "ore", "quantity": 80, "price": 40.0, "placed_at_tick": 1}
    var matched := Book.match_orders([buy], [sell], 0.1)
    errors += _check(matched["trades"].size() == 1 and matched["trades"][0]["quantity"] == 80, "partial fill")
    errors += _check(is_equal_approx(matched["trades"][0]["price"], 42.75), "native midpoint-spread")
    errors += _check(matched["remaining_buys"][0]["quantity"] == 20 and matched["remaining_sells"].is_empty(), "remainders")
    errors += _check(buy["quantity"] == 100 and sell["quantity"] == 80, "pure matching leaves orders intact")
    sell["price"] = 60.0
    errors += _check(Book.match_orders([buy], [sell], 0.0)["trades"].is_empty(), "non-crossing orders")
    print("N10 market smoke: ", "PASS" if errors == 0 else "%d FAILURES" % errors)
    quit(0 if errors == 0 else 1)

func _check(condition: bool, name: String) -> int:
    if not condition:
        push_error("N10: " + name)
        return 1
    return 0
