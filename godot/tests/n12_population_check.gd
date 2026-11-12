extends SceneTree
## Run: godot --headless --path godot --script res://tests/n12_population_check.gd
const Needs = preload("res://scripts/sim/population/needs.gd")

func _initialize() -> void:
    var pop := {"id": "pop-test", "facility_location": "earth", "population_count": 1000, "total_wealth": 100, "consumption": {"food": 2.0, "water": 1.0}, "food_satisfaction": 50, "safety_satisfaction": 50, "entertainment_satisfaction": 50, "overall_sentiment": 50, "migration_pressure": 0.0}
    var market := {"facility_location": "earth", "supply": {"food": 10.0, "water": 10.0}, "prices": {"food": 10.0, "water": 5.0}, "seller_credits": 20}
    assert(Needs.consume_cycle(pop, market, 4).is_empty())
    var events := Needs.consume_cycle(pop, market, 5)
    assert(events.size() == 2)
    assert(pop["total_wealth"] == 75)
    assert(market["seller_credits"] == 45)
    assert(is_equal_approx(market["supply"]["food"], 8.0))
    assert(is_equal_approx(market["supply"]["water"], 9.0))
    assert(pop["food_satisfaction"] == 52)
    var before := JSON.stringify([pop, market])
    var wrong := Needs.purchase(pop, {"facility_location": "mars", "supply": {"food": 1.0}, "prices": {"food": 1.0}, "seller_credits": 0}, "food", 1.0, 10)
    assert(wrong["reason"] == "wrong_location")
    assert(JSON.stringify([pop, market]) == before)
    pop["total_wealth"] = 0
    events = Needs.consume_cycle(pop, market, 10)
    assert(events.size() == 2)
    assert(pop["food_satisfaction"] == 47)
    assert(market["seller_credits"] == 45)
    assert(market["supply"]["food"] == 8.0)
    print("N12 population smoke: OK")
    quit()
