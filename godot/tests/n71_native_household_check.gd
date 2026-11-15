extends SceneTree
const Model = preload("res://scripts/sim/population/native_household_consumption.gd")
func _initialize() -> void:
	var model = Model.new()
	var p = {"p": {"location":"earth", "count":1000, "wallet":100, "consumption":{"food":2.0}, "food_satisfaction":60, "safety_satisfaction":70, "entertainment_satisfaction":70, "overall_sentiment":60}}
	var m = {"earth":{"stock":{"food":10.0}, "prices":{"food":5.0}, "seller_credits":50}}
	assert(model.import_state(p,m))
	assert(model.step(5,1,1.0).ok)
	var s = model.snapshot()
	assert(is_equal_approx(s.markets.earth.stock.food,8.0))
	assert(s.populations.p.wallet == 90 and s.markets.earth.seller_credits == 60)
	assert(not model.step(5,1,1.0).ok)
	var restored = Model.new()
	assert(restored.restore(s))
	assert(not restored.step(5,1,1.0).ok)
	assert(restored.step(10,1,1.0).ok)
	print("N71 PASS")
	quit()
