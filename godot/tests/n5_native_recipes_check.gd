extends SceneTree
const Commodities = preload("res://scripts/sim/economy/commodity_catalog.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")

func _initialize() -> void:
    var errors: Array[String] = []
    if Commodities.validate() != "":
        errors.append(Commodities.validate())
    if Recipes.validate() != "":
        errors.append(Recipes.validate())
    if Commodities.catalog().size() != 17 or Recipes.TABLE.size() != 14:
        errors.append("catalog counts")
    if Commodities.base_price("quantum_cores") != 320.0 or Commodities.tier("rare_ore") != 1:
        errors.append("Rust catalog metadata")
    if Recipes.for_facility("refinery").size() != 5:
        errors.append("refinery recipe count")
    var supply: Dictionary = {"ore":4.0,"fuel":0.4}
    var output: Dictionary = Recipes.execute("smelt_metals", supply, 1.0, 5)
    if absf(float(output.get("metals",0.0)) - 3.2) > 0.00001:
        errors.append("fractional metals output")
    if absf(float(supply["ore"])) > 0.00001 or absf(float(supply["fuel"])) > 0.00001:
        errors.append("fractional input consumption")
    var before: Dictionary = supply.duplicate(true)
    if not Recipes.execute("smelt_metals", supply, 1.0, 5).is_empty() or supply != before:
        errors.append("no free output after depletion")
    supply = {"ore":100.0,"fuel":50.0}
    output = Recipes.execute("smelt_metals", supply, 1.0, 5)
    if output.get("metals") != 40.0 or supply["ore"] != 50.0 or supply["fuel"] != 45.0:
        errors.append("five full batches")
    supply = {"ore":100.0,"fuel":50.0}
    before = supply.duplicate(true)
    output = Recipes.execute("smelt_metals", supply, 1.0, 5, {"ore":100.0,"fuel":500.0,"metals":1.0})
    if not output.is_empty() or supply != before:
        errors.append("unprofitable recipe must not mutate supply")
    supply = {"ice":8.0}
    output = Recipes.execute("process_ice", supply, 1.0, 1)
    if output.get("water") != 10.0 or output.get("fuel") != 5.0 or supply["ice"] != 0.0:
        errors.append("multiple outputs")
    supply = {"ore":100.0,"fuel":10.0,"metals":7.0}
    output = Recipes.execute("smelt_metals", supply, 1.0, 5, null, {"commodity":"metals","limit":15.0})
    if output.get("metals") != 8.0 or supply["metals"] != 15.0 or supply["ore"] != 90.0:
        errors.append("output cap")
    if errors.is_empty():
        print("N5 PASS: 17 commodities, 14 recipes, fractional inputs, gates, caps")
        quit(0)
    else:
        for error in errors:
            push_error("N5 FAIL: " + error)
        quit(1)
