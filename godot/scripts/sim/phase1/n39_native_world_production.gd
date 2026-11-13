extends RefCounted
## N39 — opt-in physical production WorldBridge, frozen Rust 0.6.7.
## Rust: agents/facility/mod.rs::tick_recipes_and_mining, workforce.rs.
## Uses N73 Recipes.execute, N9 Inventory/CreditLedger: NO new goods/money.
## Source phase1 component. Not connected to the complete ECS until Phase2.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")
const Inventory = preload("res://scripts/sim/economy/inventory_store.gd")
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

const RECIPE_INTERVAL_BASE: int = 5
const MINING_INTERVAL_BASE: int = 5
const RECIPE_MAX_BATCHES: int = 20
const STARTER_FOOD_STORAGE_CAP: float = 5000.0
const MINING_YIELD_PER_CYCLE: float = 80.0
const SALVAGE_SPEED_DIVISOR: float = 3.0
const SALVAGE_UNITS_PER_RICHNESS: float = 8000.0

var _world: Dictionary = {}
var _ledger: RefCounted = Ledger.new()
var _last_tick: int = -1
var _ready: bool = false

func initialize(physical_world: Dictionary) -> bool:
    if _ready or Schema.validate(physical_world) != "":
        return false
    var money = Ledger.new()
    if not money.import_accounts(Schema.accounts(physical_world)):
        return false
    _world = physical_world.duplicate(true)
    _ledger = money
    _last_tick = 0
    _ready = true
    return true

func world_snapshot() -> Dictionary:
    return _world.duplicate(true) if _ready else {}

func balance_of_facility(facility_id: String) -> int:
    return _ledger.balance(Schema.facility_account(facility_id)) if _ready else -1

func balance_of_population(population_id: String) -> int:
    return _ledger.balance(Schema.household_account(population_id)) if _ready else -1

## Supply external_workers from authoritative N141 construction/N143 Director
## shift receipts for THIS tick. No hidden employee registry.
func run_tick(tick: int, tick_multiplier: int = 1,
        external_workers: Dictionary = {}) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "invalid_or_replayed_tick"}
    if tick_multiplier < 1 or tick_multiplier > 10000:
        return {"ok": false, "reason": "invalid_tick_multiplier"}
    var labor_error: String = Payroll.validate_reservations(_world, external_workers)
    if not labor_error.is_empty():
        return {"ok": false, "reason": labor_error}
    var ids: Array = _world["facilities"].keys()
    ids.sort()
    var lod_fired: Dictionary = {}
    for id in ids:
        var f: Dictionary = _world["facilities"][id]
        # Rust AgentLod::try_fire advances every tick, not just work cadence.
        if not f.has("lod_divisor") or int(f["lod_divisor"]) <= 1:
            lod_fired[id] = true
        elif tick >= int(f.get("lod_next_tick", 0)):
            lod_fired[id] = true
            f["lod_next_tick"] = tick + int(f["lod_divisor"])
    var receipts: Array = []
    var failures: Dictionary = {}
    var recipe_due: bool = tick % (RECIPE_INTERVAL_BASE * tick_multiplier) == 0
    var mining_due: bool = tick % (MINING_INTERVAL_BASE * tick_multiplier) == 0
    if recipe_due:
        Payroll.refresh_employment(_world, tick, external_workers)
        for id in ids:
            if lod_fired.has(id):
                var result: Dictionary = _run_recipes(str(id), tick, external_workers)
                if result.get("ok", false):
                    receipts.append(result)
                elif result.has("reason"):
                    failures[id] = result["reason"]
    if mining_due:
        for id in ids:
            if lod_fired.has(id):
                var result: Dictionary = _run_mining(str(id), tick, external_workers)
                if result.get("ok", false):
                    receipts.append(result)
                elif result.has("reason"):
                    failures[id] = result["reason"]
    # Rust allows per-facility failures without rolling back other facilities.
    _last_tick = tick
    return {"ok": true, "tick": tick, "receipts": receipts, "failures": failures}

## P2 single-market commit boundary: N150 may change price, demand,
## flow/history/orders but NEVER physical stock, source owner or accounts.
## Validation of all markets precedes one atomic in-memory swap.
func apply_market_phase(tick: int, updates: Dictionary) -> bool:
    if not _ready or tick != _last_tick or tick < 1:
        return false
    if updates.size() != _world["markets"].size():
        return false
    var staged: Dictionary = _world.duplicate(true)
    for location in updates:
        if not staged["markets"].has(location) or not (updates[location] is Dictionary):
            return false
        var m: Dictionary = staged["markets"][location]
        var proposed: Dictionary = updates[location]
        if str(proposed.get("id", "")) != str(m.get("id", "")):
            return false
        for field in ["prices", "demand", "seed_demand", "consumption_window",
                "orders", "history"]:
            if not (proposed.get(field) is Dictionary):
                return false
            m[field] = proposed[field].duplicate(true)
        # At this boundary the original shared inventory and all physical
        # facility/population balances are untouched by the market phase.
    if Schema.validate(staged) != "":
        return false
    _world = staged
    return true

func _run_recipes(id: String, tick: int, external: Dictionary) -> Dictionary:
    var f: Dictionary = _world["facilities"][id]
    if bool(f["abandoned"]):
        return {}
    var ftype: String = str(f["type"])
    if ftype == "alloyplant2" and not Schema.has_tech(_world, str(f["faction"]), "alloytech2"):
        return _blocked(id, "research_required")
    if ftype == "qfab3" and not Schema.has_tech(_world, str(f["faction"]), "quantumtech3"):
        return _blocked(id, "research_required")
    var recipes: Array[Dictionary] = Recipes.for_facility(ftype)
    if recipes.is_empty():
        return {}
    var location: String = str(f["location"])
    var market: Dictionary = _world["markets"].get(location, {})
    if market.is_empty():
        return {}
    var proposed: Dictionary = market["supply"].duplicate(true)
    var original: Dictionary = market["supply"]
    var prices: Dictionary = market["prices"]
    var cap: Variant = null
    if ftype == "farm":
        if float(original.get("food", 0.0)) >= STARTER_FOOD_STORAGE_CAP:
            return _blocked(id, "food_storage_full")
        cap = {"commodity": "food", "limit": STARTER_FOOD_STORAGE_CAP}
    var output_mult: float = _output_multiplier(f)
    var max_batches: int = _batch_capacity(f)
    if not is_finite(output_mult) or output_mult <= 0.0 or max_batches <= 0:
        return _blocked(id, "invalid_production_efficiency")
    var ran: int = 0
    var produced: Dictionary = {}
    for recipe in recipes:
        var recipe_id: String = str(recipe["id"])
        if recipe_id == "smelt_alloys_t2_retrofit" and not Schema.has_tech(_world, str(f["faction"]), "alloytech2"):
            continue
        if recipe_id == "fabricate_quantum_cores_t3_retrofit":
            if not Schema.has_tech(_world, str(f["faction"]), "quantumtech3"):
                continue
            if Schema.tier_at(_world, str(f["faction"]), location) < 2:
                continue
        # The native farm deliberately disables the profitability gate.
        var chosen_prices: Variant = null if ftype == "farm" else prices
        var produced_one: Dictionary = Recipes.execute(recipe_id, proposed,
            output_mult, max_batches, chosen_prices, cap)
        if not produced_one.is_empty():
            ran += 1
            produced[recipe_id] = produced_one.duplicate(true)
    if ran == 0:
        return _blocked(id, "no_viable_recipe")
    var limits: Dictionary = market.get("limits", {})
    if Inventory.validate(proposed, limits) != "":
        return _blocked(id, "invalid_resulting_market_stock")
    var owner: String = str(market["owner"])
    var paid: Dictionary = Payroll.pay_shift(_world, _ledger, id, owner, tick, external)
    if not paid.get("ok", false):
        return paid
    # Financial transfer and physical input/output occur in one synchronous
    # production commit. No recipe ever runs without its paid shift.
    market["supply"] = proposed
    var work_shift: Dictionary = f["work_shift"]
    var last_recipe_ticks: Dictionary = work_shift["last_recipe_ticks"]
    var output_totals: Dictionary = work_shift["produced_outputs"]
    for recipe_id in produced:
        last_recipe_ticks[recipe_id] = tick
        var counter: Dictionary = output_totals.get(recipe_id, {})
        for commodity in produced[recipe_id]:
            counter[commodity] = float(counter.get(commodity, 0.0)) + float(produced[recipe_id][commodity])
        output_totals[recipe_id] = counter
    _grant_xp(f, ran)
    return {"ok": true, "kind": "recipes", "facility": id,
        "recipes": produced.duplicate(true), "wages": paid["wages"],
        "receipt": paid["receipt"], "new_level": f["level"]}

func _run_mining(id: String, tick: int, external: Dictionary) -> Dictionary:
    var f: Dictionary = _world["facilities"][id]
    var ftype: String = str(f["type"])
    if bool(f["abandoned"]) or (ftype != "mining_rig" and ftype != "salvage_field"):
        return {}
    var location: String = str(f["location"])
    var body_id: String = str(f["body_id"])
    if not _world["markets"].has(location) or not _world["bodies"].has(body_id):
        return {}
    var market: Dictionary = _world["markets"][location]
    var body: Dictionary = _world["bodies"][body_id]
    var proposed: Dictionary = market["supply"].duplicate(true)
    var depleted: Dictionary = {}
    var extracted: Dictionary = {}
    var fitting: float = float(f.get("fitting_output_mult", 1.0))
    var multiplier: float = fitting * _crew_efficiency(f)
    if not is_finite(multiplier) or multiplier <= 0.0:
        return _blocked(id, "invalid_mining_efficiency")
    var materials: Array = body["resources"].keys()
    materials.sort()
    for commodity in materials:
        var richness: float = float(body["resources"][commodity])
        if richness <= 0.0:
            continue
        if str(commodity) == "rare_ore":
            if not (Schema.has_tech(_world, str(f["faction"]), "survey2") and
                    Schema.has_tech(_world, str(f["faction"]), "drilltech2")):
                continue
        if str(commodity) == "crystal_ore":
            if not (Schema.has_tech(_world, str(f["faction"]), "survey3") and
                    Schema.has_tech(_world, str(f["faction"]), "drill3")):
                continue
        var amount: float = MINING_YIELD_PER_CYCLE * richness * multiplier
        if ftype == "salvage_field":
            var available: float = clampf(richness, 0.0, 1.0) * SALVAGE_UNITS_PER_RICHNESS
            amount = minf((MINING_YIELD_PER_CYCLE / SALVAGE_SPEED_DIVISOR) *
                maxf(richness, 0.0) * multiplier, available)
            if available - amount < 1.0:
                amount = available
            depleted[commodity] = maxf(0.0, (available - amount) / SALVAGE_UNITS_PER_RICHNESS)
        if not is_finite(amount) or amount < 0.0:
            return _blocked(id, "invalid_extraction")
        if amount == 0.0:
            continue
        var next_stock: float = float(proposed.get(commodity, 0.0)) + amount
        if not is_finite(next_stock):
            return _blocked(id, "invalid_extraction")
        proposed[commodity] = next_stock
        extracted[commodity] = amount
    if extracted.is_empty():
        return _blocked(id, "no_extractable_resource")
    if Inventory.validate(proposed, market.get("limits", {})) != "":
        return _blocked(id, "invalid_resulting_market_stock")
    var paid: Dictionary = Payroll.pay_shift(_world, _ledger, id,
        str(market["owner"]), tick, external)
    if not paid.get("ok", false):
        return paid
    market["supply"] = proposed
    if ftype == "salvage_field":
        for commodity in depleted:
            # A salvage field is a finite cache; ordinary mines do not deplete.
            body["resources"][commodity] = minf(
                float(body["resources"][commodity]), float(depleted[commodity]))
    return {"ok": true, "kind": "mining", "facility": id,
        "extracted": extracted, "wages": paid["wages"], "receipt": paid["receipt"]}

func _crew_efficiency(fac: Dictionary) -> float:
    if int(fac["crew_count"]) == 0:
        return 0.5
    return 0.5 + 0.5 * (float(fac["morale"]) / 100.0)

func _output_multiplier(fac: Dictionary) -> float:
    return float(fac.get("fitting_output_mult", 1.0)) * _crew_efficiency(fac)

func _batch_capacity(fac: Dictionary) -> int:
    var level: int = clampi(int(fac["level"]), 1, 10)
    var base: int = roundi(float(RECIPE_MAX_BATCHES) * (1.0 + float(level - 1) * 0.2))
    var bonus: int = int(fac.get("fitting_batches_bonus", 0))
    var faction: String = str(fac["faction"])
    bonus += 1 if Schema.has_tech(_world, faction, "industrial_methods") else 0
    bonus += 1 if Schema.has_tech(_world, faction, "automation") else 0
    return base + bonus

func _grant_xp(fac: Dictionary, recipes_run: int) -> void:
    if bool(fac["abandoned"]):
        return
    fac["xp"] = int(fac["xp"]) + recipes_run
    while int(fac["level"]) < 10 and int(fac["xp"]) >= int(fac["level"]) * 100:
        fac["xp"] = int(fac["xp"]) - int(fac["level"]) * 100
        fac["level"] = int(fac["level"]) + 1

func _blocked(id: String, reason: String) -> Dictionary:
    _world["facilities"][id]["work_blocked_reason"] = reason
    return {"ok": false, "reason": reason}

## Complete physical checkpoint including N9 balances and receipts, labor
## reservations, lifecycle XP, LOD cursors and finite salvage depletion.
func snapshot() -> Dictionary:
    if not _ready:
        return {}
    return {"version": 1, "tick": _last_tick,
        "world": _world.duplicate(true), "ledger": _ledger.snapshot()}

func restore(saved: Dictionary) -> bool:
    if saved.get("version") != 1 or typeof(saved.get("tick")) != TYPE_INT or int(saved["tick"]) < 0:
        return false
    if not (saved.get("world") is Dictionary) or not (saved.get("ledger") is Dictionary):
        return false
    var staged_world: Dictionary = saved["world"].duplicate(true)
    if Schema.validate(staged_world) != "":
        return false
    var staged_ledger = Ledger.new()
    if not staged_ledger.restore(saved["ledger"]):
        return false
    var expected: Dictionary = Schema.accounts(staged_world)
    for id in expected:
        if staged_ledger.balance(str(id)) != int(expected[id]):
            return false
    for id in staged_world["facilities"]:
        var shift: Dictionary = staged_world["facilities"][id].get("work_shift", {})
        if not shift.is_empty() and int(shift["tick"]) > int(saved["tick"]):
            return false
    _world = staged_world
    _ledger = staged_ledger
    _last_tick = int(saved["tick"])
    _ready = true
    return true
