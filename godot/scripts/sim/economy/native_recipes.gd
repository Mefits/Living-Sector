extends RefCounted
## Exact Rust RECIPES table and fractional production operation.
## Source: native/crates/sim_core/src/economy/recipes.rs @ 6e40615.
## This is a pure supply transform; it does NOT authorize a production shift,
## employ workers, debit wages or create a physical shipment.
const Commodities = preload("res://scripts/sim/economy/commodity_catalog.gd")
const MIN_RECIPE_MARGIN_RATIO: float = 0.5
const TABLE: Array[Dictionary] = [
    {"id":"smelt_metals","facility":"refinery","in":{"ore":10,"fuel":1},"out":{"metals":8}},
    {"id":"process_ice","facility":"refinery","in":{"ice":8},"out":{"water":10,"fuel":5}},
    {"id":"crack_fuel","facility":"refinery","in":{"gas":6},"out":{"fuel":4}},
    {"id":"refine_polymers","facility":"refinery","in":{"gas":6},"out":{"polymers":5}},
    {"id":"assemble_components","facility":"factory","in":{"metals":3,"polymers":1},"out":{"components":5}},
    {"id":"build_electronics","facility":"factory","in":{"components":2,"metals":1},"out":{"electronics":3}},
    {"id":"forge_tools","facility":"factory","in":{"metals":2,"polymers":1},"out":{"tools":4}},
    {"id":"produce_medical","facility":"factory","in":{"water":2,"components":1},"out":{"medical":4}},
    {"id":"craft_luxury","facility":"factory","in":{"components":2,"polymers":1},"out":{"luxury":1}},
    {"id":"smelt_alloys_t2","facility":"alloyplant2","in":{"rare_ore":4,"metals":4,"fuel":2},"out":{"alloys":5}},
    {"id":"smelt_alloys_t2_retrofit","facility":"refinery","in":{"rare_ore":4,"metals":4,"fuel":2},"out":{"alloys":5}},
    {"id":"fabricate_quantum_cores_t3","facility":"qfab3","in":{"crystal_ore":3,"alloys":2,"electronics":2},"out":{"quantum_cores":2}},
    {"id":"fabricate_quantum_cores_t3_retrofit","facility":"factory","in":{"crystal_ore":3,"alloys":2,"electronics":2},"out":{"quantum_cores":2}},
    {"id":"grow_food","facility":"farm","in":{"water":3},"out":{"food":10}}
]

static func get_recipe(recipe_id: String) -> Dictionary:
    for recipe in TABLE:
        if recipe["id"] == recipe_id:
            return recipe.duplicate(true)
    return {}

static func for_facility(facility_type: String) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for recipe in TABLE:
        if recipe["facility"] == facility_type:
            result.append(recipe.duplicate(true))
    return result

static func validate() -> String:
    var seen: Dictionary = {}
    for recipe in TABLE:
        var id: String = recipe["id"]
        if seen.has(id) or str(recipe["facility"]).is_empty():
            return "Duplicate or malformed recipe " + id
        seen[id] = true
        for side in ["in","out"]:
            var entries: Dictionary = recipe[side]
            if entries.is_empty():
                return "Empty recipe side " + id
            for slug in entries:
                if not Commodities.contains(slug) or int(entries[slug]) <= 0:
                    return "Unknown commodity or zero amount: " + id + "/" + slug
    return "" if TABLE.size() == 14 else "Expected 14 native recipes"

## Returns produced quantities, or {} with supply unchanged. Output cap applies
## before any mutation; fractional batches preserve fractional input consumption.
## A null price map disables the optional market-profitability gate.
static func execute(recipe_id: String, supply: Dictionary, efficiency: float,
        max_batches: int, prices: Variant = null, output_cap: Variant = null,
        margin_ratio: float = MIN_RECIPE_MARGIN_RATIO) -> Dictionary:
    var recipe: Dictionary = get_recipe(recipe_id)
    if recipe.is_empty() or not is_finite(efficiency) or efficiency <= 0.0 or max_batches <= 0:
        return {}
    var inputs: Dictionary = recipe["in"]
    var outputs: Dictionary = recipe["out"]
    var scale: float = float(max_batches)
    for slug in inputs:
        var available: float = float(supply.get(slug, 0.0))
        if not is_finite(available) or available < 0.0:
            return {}
        scale = minf(scale, available / float(inputs[slug]))
    if output_cap is Dictionary:
        var cap: Dictionary = output_cap
        var slug: String = str(cap.get("commodity", ""))
        var limit: float = float(cap.get("limit", 0.0))
        var current: float = float(supply.get(slug, 0.0))
        if not is_finite(limit) or limit <= 0.0 or not is_finite(current) or current < 0.0 or current >= limit:
            return {}
        if outputs.has(slug):
            scale = minf(scale, maxf(0.0, (limit - current) / (float(outputs[slug]) * efficiency)))
    if scale <= 0.0:
        return {}
    var effective: float = scale * efficiency
    for slug in outputs:
        var current: float = float(supply.get(slug, 0.0))
        var amount: float = float(outputs[slug]) * effective
        if not is_finite(current) or current < 0.0 or not is_finite(amount) or amount <= 0.0 or not is_finite(current + amount):
            return {}
    if prices is Dictionary:
        var all_priced: bool = true
        for slug in inputs:
            if float(prices.get(slug, 0.0)) <= 0.0:
                all_priced = false
        for slug in outputs:
            if float(prices.get(slug, 0.0)) <= 0.0:
                all_priced = false
        if all_priced:
            var input_value: float = 0.0
            var output_value: float = 0.0
            for slug in inputs:
                input_value += float(prices[slug]) * float(inputs[slug]) * scale
            for slug in outputs:
                output_value += float(prices[slug]) * float(outputs[slug]) * effective
            if input_value > 0.0 and output_value < input_value * margin_ratio:
                return {}
    var produced: Dictionary = {}
    for slug in inputs:
        supply[slug] = float(supply.get(slug, 0.0)) - float(inputs[slug]) * scale
    for slug in outputs:
        var amount: float = float(outputs[slug]) * effective
        supply[slug] = float(supply.get(slug, 0.0)) + amount
        produced[slug] = amount
    return produced
