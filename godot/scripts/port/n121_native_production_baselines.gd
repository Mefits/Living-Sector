extends RefCounted
## N121 frozen Rust native_execution.rs::native_production_baselines.
## Every paid recipe output has a product-qualified cumulative counter.
## No speculative base stock, no invented shift. Required on new plans
## so repeated Produce actions cannot claim the same physical output.
const State = preload("res://scripts/port/n121_native_execution_state.gd")
const Receipts = preload("res://scripts/port/n121_native_receipts.gd")

## Requires source-authoritative producer pins created via
## native_catalogue::pinned_producer_recipe, and FacilityCrew paid
## produced_outputs counters from N116 production shift.
static func capture(world: Dictionary, snapshot: Dictionary,
        actions: Array) -> Dictionary:
    var output: Dictionary = {}
    if not (world.get("producer_recipe_pins", null) is Dictionary):
        return {"ok": false, "reason": "missing_authoritative_recipe_pins"}
    if not (world.get("facilities", null) is Dictionary):
        return {"ok": false, "reason": "missing_native_facilities"}
    for action in actions:
        if not (action is Dictionary):
            return {"ok": false, "reason": "invalid_action_spec"}
        if str(action.get("kind", "")) != "produce":
            continue
        var action_id: String = str(action.get("action_id", ""))
        var pin: Variant = world["producer_recipe_pins"].get(action_id, null)
        if not (pin is Dictionary):
            # Rust skips unverifiable baseline; receipt falls back only
            # when actual paid output and visible every output exist.
            continue
        var facility_id: String = str(pin.get("facility_id", ""))
        var recipe_id: String = str(pin.get("recipe_id", ""))
        var dest: String = str(action.get("destination_id", ""))
        if (facility_id.is_empty() or recipe_id.is_empty()
                or facility_id != str(action.get("source_id", ""))):
            continue
        var owner: Dictionary = Receipts.unique_owned_market(snapshot, dest)
        if not bool(owner.get("ok", false)):
            continue
        if not Receipts.unique_global_market(world, dest,
                str(owner["market"].get("market_id", ""))):
            continue
        var facility: Variant = world["facilities"].get(facility_id, null)
        if not (facility is Dictionary):
            continue
        var shift: Variant = facility.get("work_shift", null)
        if not (shift is Dictionary):
            continue
        var totals: Variant = shift.get("produced_outputs", {})
        if not (totals is Dictionary):
            continue
        var per_recipe: Variant = totals.get(recipe_id, {})
        if not (per_recipe is Dictionary):
            continue
        for raw_product in action.get("outputs", []):
            var product: Dictionary = State.output_spec(raw_product)
            if product.is_empty():
                return {"ok": false, "reason": "invalid_original_recipe_output"}
            var commodity: String = str(product["commodity"])
            var units: int = int(product["quantity"])
            if commodity.is_empty() or units <= 0:
                continue
            var total: Variant = per_recipe.get(commodity, 0.0)
            if not (total is int or total is float):
                continue
            if not is_finite(float(total)) or float(total) < 0.0:
                continue
            output[State.output_key(action, commodity)] = float(total)
    return {"ok": true, "production_baselines": output}
