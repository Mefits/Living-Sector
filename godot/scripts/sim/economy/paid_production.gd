extends RefCounted
## N6 paid self-owned production: Rust workforce.rs + recipes.rs.
## CODE_UNVERIFIED. No facility Nodes, no phantom money or stock.
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")

var _last_ticks: Dictionary = {}
var _output_totals: Dictionary = {}

## The caller supplies real local population and an existing household account.
## This slice deliberately rejects foreign stock ownership and processing fees:
## those require the full Rust pay_shift counterparty/assignment implementation.
func run_shift(facility_id: String, recipe_id: String, facility_type: String,
        tick: int, workers: int, population_count: int,
        stock: Dictionary, limits: Dictionary, ledger: RefCounted,
        employer_account: String, household_account: String,
        efficiency: float = 1.0, max_batches: int = 1,
        prices: Variant = null) -> Dictionary:
    if facility_id.is_empty() or tick < 0 or workers <= 0 or population_count < 0:
        return _failure("invalid_shift")
    if workers > int(population_count * 3 / 5):
        return _failure("insufficient_workers")
    if employer_account.is_empty() or household_account.is_empty() or employer_account == household_account:
        return _failure("invalid_accounts")
    if _last_ticks.has(facility_id) and int(_last_ticks[facility_id]) >= tick:
        return _failure("already_worked_this_tick")
    var recipe: Dictionary = Recipes.get_recipe(recipe_id)
    if recipe.is_empty() or str(recipe["facility"]) != facility_type:
        return _failure("invalid_facility_recipe")
    if Inventory.validate(stock, limits) != "":
        return _failure("invalid_inventory")
    if not is_finite(efficiency) or efficiency <= 0.0 or max_batches <= 0:
        return _failure("invalid_recipe_parameters")
    # Dry run on a detached copy; no wages for an unproductive shift.
    var next_stock: Dictionary = stock.duplicate(true)
    var output_cap: Variant = null
    # Full warehouse caps are enforced on the complete candidate below.
    var produced: Dictionary = Recipes.execute(recipe_id, next_stock, efficiency, max_batches, prices, output_cap)
    if produced.is_empty():
        return _failure("no_production")
    if Inventory.validate(next_stock, limits) != "":
        return _failure("warehouse_full")
    var wages: int = workers # Rust WAGE_PER_SHIFT = 1 CR per worker.
    if ledger.balance(employer_account) < wages or ledger.balance(household_account) < 0:
        return _failure("insufficient_payroll_budget")
    var operation_id: String = "production/%s/%d" % [facility_id, tick]
    if ledger.has_receipt(operation_id):
        return _failure("duplicate_operation")
    # The ledger is the final fallible operation; inventory is swapped only
    # after balanced payment succeeds. No awaits, external callbacks or Nodes.
    var payment: Dictionary = ledger.transfer(operation_id, employer_account,
            household_account, wages, tick, "production_wages")
    if not payment.get("ok", false):
        return _failure(str(payment.get("reason", "payment_failed")))
    stock.clear()
    for slug in next_stock:
        stock[slug] = next_stock[slug]
    _last_ticks[facility_id] = tick
    if not _output_totals.has(facility_id):
        _output_totals[facility_id] = {}
    var totals: Dictionary = _output_totals[facility_id]
    for slug in produced:
        totals[slug] = float(totals.get(slug, 0.0)) + float(produced[slug])
    return {"ok": true, "tick": tick, "wages": wages,
        "produced": produced.duplicate(true), "receipt": operation_id}

func snapshot() -> Dictionary:
    return {"version": 1, "last_ticks": _last_ticks.duplicate(true),
        "produced_outputs": _output_totals.duplicate(true)}

func restore(data: Dictionary) -> bool:
    if data.get("version") != 1 or not (data.get("last_ticks") is Dictionary) or not (data.get("produced_outputs") is Dictionary):
        return false
    for facility in data["last_ticks"]:
        if not (facility is String) or facility.is_empty() or typeof(data["last_ticks"][facility]) != TYPE_INT or int(data["last_ticks"][facility]) < 0:
            return false
    for facility in data["produced_outputs"]:
        if not (facility is String) or not (data["produced_outputs"][facility] is Dictionary):
            return false
        for slug in data["produced_outputs"][facility]:
            if not Inventory.valid_amount(data["produced_outputs"][facility][slug]):
                return false
    _last_ticks = data["last_ticks"].duplicate(true)
    _output_totals = data["produced_outputs"].duplicate(true)
    return true

func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
