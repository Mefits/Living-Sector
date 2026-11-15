extends SceneTree
const Catalog = preload("res://scripts/sim/production/native_recipe_catalogue.gd")
func _initialize() -> void:
	var c = Catalog.new()
	assert(c.RECIPES.size() == 14)
	assert(c.recipes_for("farm") == ["grow_food"])
	var stock = {"water":6.0}
	var r = c.evaluate("grow_food","farm",stock)
	assert(r.ok and r.batches == 2.0 and r.outputs.food == 20.0)
	assert(stock.water == 6.0)
	assert(not c.evaluate("grow_food","factory",stock).ok)
	assert(not c.evaluate("grow_food","farm",{"water":0.0}).ok)
	assert(not c.evaluate("grow_food","farm",stock,{"water":100.0,"food":1.0}).ok)
	assert(c.evaluate("grow_food","farm",{"water":1.5}).batches == 0.5)
	print("N73 PASS")
	quit()
