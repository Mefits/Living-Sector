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
const FacilityLifecycle = preload("res://scripts/sim/phase2/unified_facility_lifecycle_phase.gd")
const ServiceRestock = preload("res://scripts/sim/phase2/unified_service_restock_phase.gd")

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
        external_workers: Dictionary = {}, tick_scale: float = 1.0) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "invalid_or_replayed_tick"}
    if tick_multiplier < 1 or tick_multiplier > 10000:
        return {"ok": false, "reason": "invalid_tick_multiplier"}
    var labor_error: String = Payroll.validate_reservations(_world, external_workers)
    if not labor_error.is_empty():
        return {"ok": false, "reason": labor_error}
    # Stage the WHOLE native N156/N130 maintenance interval in isolation.
    # Nothing touches the one canonical World/N9 Ledger until every paid
    # repair, local stock move and account balance has passed validation.
    var initial: Dictionary = FacilityLifecycle.propose(
        _world, tick, tick_scale, tick_multiplier)
    if not initial.get("ok", false):
        return {"ok": false, "reason": "facility_lifecycle_" + str(initial.get("reason", "rejected"))}
    var lifecycle_world: Dictionary = _world.duplicate(true)
    var lifecycle_ledger = Ledger.new()
    if not lifecycle_ledger.restore(_ledger.snapshot()):
        return {"ok": false, "reason": "lifecycle_ledger_clone_rejected"}
    var committed_repairs: Dictionary = {}
    var paid_credits: Dictionary = {}
    var repairs: Array = []
    var repair_failures: Dictionary = {}
    # Rust lifecycle order: decay, self-repair after real paid WorkShift,
    # abandonment, THEN purchase service Fuel/Tools from the local market.
    for candidate in initial["repair_candidates"]:
        var fid: String = str(candidate.get("facility_id", ""))
        if not lifecycle_world["facilities"].has(fid):
            return {"ok": false, "reason": "unknown_repair_candidate"}
        var paid: Dictionary = Payroll.pay_shift(lifecycle_world, lifecycle_ledger,
            fid, fid, tick, external_workers, 0)
        if not paid.get("ok", false):
            # Native Rust skips a repair if staffing or funds cannot pay.
            # Never consume a Tool or bump condition without the wages.
            repair_failures[fid] = str(paid.get("reason", "paid_repair_rejected"))
            continue
        committed_repairs[fid] = {
            "paid_shift_committed": true, "trusted_internal_apply": true,
            "facility_id": fid, "tick": tick
        }
        paid_credits[fid] = int(lifecycle_world["facilities"][fid]["credits"])
        repairs.append({"facility": fid, "tick": tick,
            "receipt": paid["receipt"], "wages": int(paid["wages"]),
            "tools_used": 1.0})
    # The proposal reads the PRE-repair shift for native crew morale, while
    # repair receipts/post-wage credits come from the STAGED N9 ledger only.
    var lifecycle: Dictionary = FacilityLifecycle.propose(
        _world, tick, tick_scale, tick_multiplier, {},
        committed_repairs, paid_credits)
    if not lifecycle.get("ok", false):
        return {"ok": false, "reason": "facility_lifecycle_" + str(lifecycle.get("reason", "rejected"))}
    for facility_id in lifecycle["changes"]:
        if not lifecycle_world["facilities"].has(facility_id):
            return {"ok": false, "reason": "lifecycle_unknown_facility"}
        var updated: Dictionary = lifecycle_world["facilities"][facility_id]
        var delta: Dictionary = lifecycle["changes"][facility_id]
        updated["condition"] = float(delta["condition"])
        updated["abandoned"] = bool(delta["abandoned"])
        updated["abandon_counter"] = int(delta["abandon_counter"])
        updated["reserves"] = delta["reserves"].duplicate(true)
        # N156 household-derived crew morale doesn't debit Food a second time.
        if delta.has("morale"):
            updated["morale"] = float(delta["morale"])
    var restocked: Dictionary = ServiceRestock.apply(
        lifecycle_world, lifecycle_ledger, tick, tick_multiplier)
    if not restocked.get("ok", false):
        return {"ok": false, "reason": "service_restock_" + str(restocked.get("reason", "rejected"))}
    if Schema.validate(lifecycle_world) != "":
        return {"ok": false, "reason": "lifecycle_restock_schema_rejected"}
    var accounts: Dictionary = Schema.accounts(lifecycle_world)
    for account in accounts:
        if lifecycle_ledger.balance(str(account)) != int(accounts[account]):
            return {"ok": false, "reason": "lifecycle_restock_account_mismatch"}
    _world = lifecycle_world
    _ledger = lifecycle_ledger
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
    return {"ok": true, "tick": tick, "receipts": receipts, "failures": failures,
        "lifecycle_changes": lifecycle["changes"].duplicate(true),
        "lifecycle_events": lifecycle["events"].duplicate(true),
        "paid_repairs": repairs,
        "repair_failures": repair_failures,
        "service_restock": restocked.get("purchases", []).duplicate(true)}

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

## P2 N151: the pure source population phase produces a plan, not money.
## Replay every paid N151 purchase into the SAME authoritative N9 ledger.
## Ledger and World are both staged and swapped together after validating all
## source receipts, source stock/locations and the proposed sentiment state.
func apply_population_phase(tick: int, native_result: Dictionary) -> bool:
    if not _ready or tick != _last_tick or tick < 1:
        return false
    if not native_result.get("ok", false):
        return false
    if native_result.get("skipped", false):
        return native_result.get("purchases", []).is_empty()
    if not (native_result.get("world") is Dictionary) or not (native_result.get("purchases") is Array):
        return false
    var proposed: Dictionary = native_result["world"]
    if not (proposed.get("populations") is Array) or not (proposed.get("markets") is Dictionary) or not (proposed.get("facilities") is Dictionary):
        return false
    if proposed["populations"].size() != _world["populations"].size():
        return false
    var staged: Dictionary = _world.duplicate(true)
    var ledger_next = Ledger.new()
    if not ledger_next.restore(_ledger.snapshot()):
        return false
    var purchases: Array = native_result["purchases"]
    for index in range(purchases.size()):
        var ticket: Variant = purchases[index]
        if not (ticket is Dictionary):
            return false
        var pid: String = str(ticket.get("population_id", ""))
        var fid: String = str(ticket.get("facility_id", ""))
        var commodity: String = str(ticket.get("commodity", ""))
        var mid: String = str(ticket.get("market_id", ""))
        if not staged["populations"].has(pid) or not staged["facilities"].has(fid):
            return false
        var pop: Dictionary = staged["populations"][pid]
        var location: String = str(pop["location"])
        if not staged["markets"].has(location):
            return false
        var market: Dictionary = staged["markets"][location]
        if str(market["id"]) != mid or str(market["owner"]) != fid or str(staged["facilities"][fid]["location"]) != location:
            return false
        if not (ticket.get("preconditions") is Dictionary) or not (ticket.get("after") is Dictionary):
            return false
        var pre: Dictionary = ticket["preconditions"]
        var after: Dictionary = ticket["after"]
        var price: float = float(market["prices"].get(commodity, 0.0))
        var current_stock: float = float(market["supply"].get(commodity, 0.0))
        var quantity: float = float(ticket.get("quantity", -1.0))
        var payment: int = int(ticket.get("payment", -1))
        if not is_finite(quantity) or quantity <= 0.0 or quantity > current_stock + 0.00001:
            return false
        if payment <= 0 or payment > int(pop["wealth"]) or price <= 0.0:
            return false
        if int(pre.get("population_wealth", -1)) != int(pop["wealth"]) or int(pre.get("seller_credits", -1)) != int(staged["facilities"][fid]["credits"]):
            return false
        if not is_equal_approx(float(pre.get("market_supply", -1.0)), current_stock) or not is_equal_approx(float(pre.get("market_posted_price", -1.0)), price):
            return false
        var new_stock: float = float(after.get("market_supply", -1.0))
        if new_stock < 0.0 or not is_finite(new_stock) or absf((current_stock - quantity) - new_stock) > maxf(0.0005, absf(current_stock) * 0.000001):
            return false
        var receipt_id: String = "n151/consumption/%d/%d/%s/%s" % [tick, index, pid, commodity]
        var receipt: Dictionary = ledger_next.transfer(receipt_id,
            Schema.household_account(pid), Schema.facility_account(fid),
            payment, tick, "native_population_consumption")
        if not receipt.get("ok", false):
            return false
        pop["wealth"] = ledger_next.balance(Schema.household_account(pid))
        staged["facilities"][fid]["credits"] = ledger_next.balance(Schema.facility_account(fid))
        if pop["wealth"] != int(after.get("population_wealth", -1)) or int(staged["facilities"][fid]["credits"]) != int(after.get("facility_credits", -1)):
            return false
        market["supply"][commodity] = new_stock
    # Source world is the reference for FINAL stock, account, sentiment and
    # rolling consumption history, never a second writable market/ledger.
    for location in staged["markets"]:
        if not proposed["markets"].has(location):
            return false
        var pm: Dictionary = proposed["markets"][location]
        var real_market: Dictionary = staged["markets"][location]
        if pm.get("id") != real_market.get("id") or pm.get("supply") != real_market["supply"] or pm.get("prices") != real_market["prices"]:
            return false
        real_market["consumption_window"] = pm.get("consumption_window", {}).duplicate(true)
    var matched: Dictionary = {}
    for projected_pop in proposed["populations"]:
        if not (projected_pop is Dictionary):
            return false
        var id: String = str(projected_pop.get("id", ""))
        if matched.has(id) or not staged["populations"].has(id):
            return false
        matched[id] = true
        var real_pop: Dictionary = staged["populations"][id]
        if str(projected_pop.get("facility_location", "")) != str(real_pop["location"]) or int(projected_pop.get("population_count", -1)) != int(real_pop["count"]) or int(projected_pop.get("total_wealth", -1)) != int(real_pop["wealth"]):
            return false
        for field in ["food_satisfaction", "safety_satisfaction", "entertainment_satisfaction",
                "overall_sentiment", "unrest", "migration_pressure"]:
            if not projected_pop.has(field):
                return false
            real_pop[field] = projected_pop[field]
    for fid in staged["facilities"]:
        if not proposed["facilities"].has(fid) or int(proposed["facilities"][fid].get("credits", -1)) != int(staged["facilities"][fid]["credits"]):
            return false
    if Schema.validate(staged) != "":
        return false
    for account in Schema.accounts(staged):
        if ledger_next.balance(str(account)) != int(Schema.accounts(staged)[account]):
            return false
    _world = staged
    _ledger = ledger_next
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
