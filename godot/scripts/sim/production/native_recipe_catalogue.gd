extends RefCounted
## N73 CODE_UNVERIFIED. Frozen native/crates/sim_core/src/economy/recipes.rs.
## Read-only Rust recipe catalogue; no production, credits, or stock mutations.
const RECIPES := {
	"smelt_metals":{"facility":"refinery","inputs":{"ore":10,"fuel":1},"outputs":{"metals":8}},
	"process_ice":{"facility":"refinery","inputs":{"ice":8},"outputs":{"water":10,"fuel":5}},
	"crack_fuel":{"facility":"refinery","inputs":{"gas":6},"outputs":{"fuel":4}},
	"refine_polymers":{"facility":"refinery","inputs":{"gas":6},"outputs":{"polymers":5}},
	"assemble_components":{"facility":"factory","inputs":{"metals":3,"polymers":1},"outputs":{"components":5}},
	"build_electronics":{"facility":"factory","inputs":{"components":2,"metals":1},"outputs":{"electronics":3}},
	"forge_tools":{"facility":"factory","inputs":{"metals":2,"polymers":1},"outputs":{"tools":4}},
	"produce_medical":{"facility":"factory","inputs":{"water":2,"components":1},"outputs":{"medical":4}},
	"craft_luxury":{"facility":"factory","inputs":{"components":2,"polymers":1},"outputs":{"luxury":1}},
	"smelt_alloys_t2":{"facility":"alloyplant2","inputs":{"rare_ore":4,"metals":4,"fuel":2},"outputs":{"alloys":5}},
	"smelt_alloys_t2_retrofit":{"facility":"refinery","inputs":{"rare_ore":4,"metals":4,"fuel":2},"outputs":{"alloys":5}},
	"fabricate_quantum_cores_t3":{"facility":"qfab3","inputs":{"crystal_ore":3,"alloys":2,"electronics":2},"outputs":{"quantum_cores":2}},
	"fabricate_quantum_cores_t3_retrofit":{"facility":"factory","inputs":{"crystal_ore":3,"alloys":2,"electronics":2},"outputs":{"quantum_cores":2}},
	"grow_food":{"facility":"farm","inputs":{"water":3},"outputs":{"food":10}}
}
const MAX_BATCHES := 20
const MIN_MARGIN_RATIO := 0.5

func recipes_for(facility: String) -> Array:
	var result: Array = []
	var ids := RECIPES.keys()
	ids.sort()
	for id in ids:
		if RECIPES[id].facility == facility:
			result.append(id)
	return result

## This is an admission/diagnostic estimate only; authoritative N39 production
## must debit stock and pay workers in its own atomic transaction.
func evaluate(recipe_id: String, facility: String, stock: Dictionary, prices: Dictionary = {}, efficiency: float = 1.0, max_batches: int = MAX_BATCHES) -> Dictionary:
	if not RECIPES.has(recipe_id):
		return {"ok": false, "reason": "unknown_recipe"}
	var recipe: Dictionary = RECIPES[recipe_id]
	if recipe.facility != facility:
		return {"ok": false, "reason": "wrong_facility"}
	if not efficiency.is_finite() or efficiency <= 0.0 or max_batches < 1 or max_batches > MAX_BATCHES:
		return {"ok": false, "reason": "invalid_efficiency_or_batches"}
	var scale := float(max_batches)
	var missing: Dictionary = {}
	for commodity in recipe.inputs:
		var have := float(stock.get(commodity, 0.0))
		var needed := float(recipe.inputs[commodity])
		if not have.is_finite() or have < 0.0:
			return {"ok": false, "reason": "invalid_stock"}
		scale = minf(scale, have / needed)
		if have < needed:
			missing[commodity] = needed - have
	if scale <= 0.0:
		return {"ok": false, "reason": "missing_inputs", "missing": missing}
	if not prices.is_empty():
		var input_value := 0.0
		var output_value := 0.0
		for commodity in recipe.inputs:
			if not prices.has(commodity) or not float(prices[commodity]).is_finite() or float(prices[commodity]) < 0.0:
				return {"ok": false, "reason": "invalid_prices"}
			input_value += float(prices[commodity]) * float(recipe.inputs[commodity])
		for commodity in recipe.outputs:
			if not prices.has(commodity) or not float(prices[commodity]).is_finite() or float(prices[commodity]) < 0.0:
				return {"ok": false, "reason": "invalid_prices"}
			output_value += float(prices[commodity]) * float(recipe.outputs[commodity]) * efficiency
		if output_value < input_value * MIN_MARGIN_RATIO:
			return {"ok": false, "reason": "unprofitable"}
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	for commodity in recipe.inputs:
		inputs[commodity] = float(recipe.inputs[commodity]) * scale
	for commodity in recipe.outputs:
		outputs[commodity] = float(recipe.outputs[commodity]) * scale * efficiency
	return {"ok": true, "batches": scale, "inputs": inputs, "outputs": outputs, "partial": scale < 1.0}
