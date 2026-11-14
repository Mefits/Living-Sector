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
const ContractBoard = preload("res://scripts/sim/economy/contract_board.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")
const PaidCargo = preload("res://scripts/sim/phase2/unified_autonomous_paid_cargo.gd")
const NativeResearch = preload("res://scripts/sim/phase2/unified_native_research_phase.gd")
const NativePopulation = preload("res://scripts/sim/phase2/unified_population_phase.gd")
const ResearchShift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")
const NativeConstructionMaterial = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const NativeConstructionLabor = preload("res://scripts/sim/phase2/unified_native_construction_labor.gd")
const N91Executor = preload("res://scripts/ported/n91_construction_executor.gd")
const ShipCatalog = preload("res://scripts/sim/ship_catalog.gd")
const N91SourceDispatch = preload("res://scripts/sim/phase2/unified_n91_construction_dispatch.gd")
const NativeColonyFounding = preload("res://scripts/sim/phase2/unified_n151_colony_founding_phase.gd")
const EscrowStage = preload("res://scripts/sim/phase2/unified_contract_escrow_staging.gd")
const FacilityLifecycle = preload("res://scripts/sim/phase2/unified_facility_lifecycle_phase.gd")
const ServiceRestock = preload("res://scripts/sim/phase2/unified_service_restock_phase.gd")
const NativeDiplomacy = preload("res://scripts/sim/phase2/unified_native_diplomacy_phase.gd")
const NativeFactionFinance = preload("res://scripts/sim/phase2/unified_native_faction_finance_phase.gd")
const NativeShipyardModules = preload("res://scripts/sim/phase1/n154_native_shipyard_module_tick.gd")
const NativeModuleRecipes = preload("res://scripts/sim/shipyard/native_module_recipes_n132.gd")
const CommodityCatalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const NativeShipyardRefit = preload("res://scripts/port/n108_shipyard_refit_apply.gd")
const NativeStationAdministration = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")
const NativeHybridPlanning = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")
const NativeN121 = preload("res://scripts/sim/phase2/unified_n121_native_execution_phase.gd")
const NativeN152 = preload("res://scripts/sim/phase2/unified_n152_contract_lifecycle.gd")
const NativeN98 = preload("res://scripts/sim/phase1/n98_plan_ledger.gd")
const N121State = preload("res://scripts/port/n121_native_execution_state.gd")
const N121Baselines = preload("res://scripts/port/n121_native_production_baselines.gd")
const N121Receipts = preload("res://scripts/port/n121_native_receipts.gd")

const GalaxyConstructionCrew: Dictionary = {
    "station": 20, "shipyard": 16, "refinery": 12, "factory": 12,
    "farm": 6, "mining_rig": 8, "outpost": 6,
    "gate": 0, "construction_dock": 0}
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

## Read-only canonical money + contracts for tests, checkpoint and observer.
func ledger_snapshot() -> Dictionary:
    return _ledger.snapshot() if _ready else {}

func contract_snapshot() -> Dictionary:
    return _world.get("contract_board", {}).duplicate(true) if _ready else {}

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
    # Receipts accumulate indefinitely; cloning the whole N9 history on
    # every no-op orbit tick would make long-term simulation quadratic.
    # No new maintenance payments are possible unless there is a paid
    # repair candidate or the actual Rust 20×multiplier restock cadence.
    var money_phase_due: bool = not initial["repair_candidates"].is_empty() or bool(initial["due"]["restock"])
    var lifecycle_ledger: RefCounted = _ledger
    if money_phase_due:
        lifecycle_ledger = Ledger.new()
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
    var lifecycle: Dictionary = initial
    if not committed_repairs.is_empty():
        lifecycle = FacilityLifecycle.propose(
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
    # Frozen Rust station::plan occurs AFTER real N156 repair and N130
    # restock, BEFORE N6 recipe/mining paid work on the 5×mult cadence.
    # The original administrator only allocates WORKERS: the sole N39
    # payroll/recipe writers below still independently enforce N9 money,
    # physical stock, crew availability and all shift receipts.
    var station_admin: Dictionary = {"ok": true, "due": false,
        "views": [], "assignments": {}}
    if bool(_world.get("station_executing", false)):
        station_admin = NativeStationAdministration.propose(
            _world, _ledger, tick, tick_multiplier, external_workers)
        if not station_admin.get("ok", false):
            return {"ok": false, "reason": "n18_station_administration_" +
                str(station_admin.get("reason", "rejected"))}
        if station_admin.get("due", false):
            var staffed: Dictionary = _world.duplicate(true)
            for facility_id in staffed["facilities"]:
                if not station_admin["assignments"].has(facility_id):
                    return {"ok": false, "reason": "n18_incomplete_station_staffing"}
                staffed["facilities"][facility_id]["assigned_workers"] = int(
                    station_admin["assignments"][facility_id])
            staffed["station_administration"] = station_admin["snapshots"].duplicate(true)
            staffed["station_administration_last_tick"] = tick
            var staffing_error: String = Schema.validate(staffed)
            if not staffing_error.is_empty():
                return {"ok": false, "reason": "n18_invalid_native_workforce_state:" +
                    staffing_error}
            if Schema.accounts(staffed) != Schema.accounts(_world):
                return {"ok": false, "reason": "n18_administrator_invented_money"}
            _world = staffed
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
    # Frozen N154: genuine shipyard modules only after paid
    # FacilityWorkforce shift and physical N132 input consumption.
    var shipyard_modules: Dictionary = _run_shipyard_modules(
        tick, tick_multiplier, external_workers)
    if not shipyard_modules.get("ok", false):
        return {"ok": false, "reason": str(shipyard_modules.get(
            "reason", "native_shipyard_module_failed"))}
    for made in shipyard_modules.get("paid", []):
        receipts.append(made.duplicate(true))
        failures.erase(str(made.get("facility", "")))
    for refused in shipyard_modules.get("blocked", []):
        if refused is Dictionary:
            failures[str(refused.get("facility", ""))] = str(refused.get("reason", "module_blocked"))
    # Rust allows per-facility failures without rolling back other facilities.
    _last_tick = tick
    return {"ok": true, "tick": tick, "receipts": receipts, "failures": failures,
        "lifecycle_changes": lifecycle["changes"].duplicate(true),
        "lifecycle_events": lifecycle["events"].duplicate(true),
        "paid_repairs": repairs,
        "repair_failures": repair_failures,
        "service_restock": restocked.get("purchases", []).duplicate(true),
        "shipyard_modules": shipyard_modules.get("paid", []).duplicate(true),
        "shipyard_module_blocked": shipyard_modules.get("blocked", []).duplicate(true),
        "native_station_administration": station_admin.get("views", []).duplicate(true),
        "native_station_staffing_due": bool(station_admin.get("due", false))}

## Native N108/N154 agent RequestRefit. A real N84 ship must be at a
## real paid shipyard dock; inventory, N101 retrofit point and ship wallet
## are consumed together with one N9 transfer. No admin override here.
func apply_native_shipyard_refit(tick: int, ship_id: String,
        slot: String, slug: String) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "n108_not_the_live_ship_phase"}
    if not _world.get("ships", {}).has(ship_id):
        return {"ok": false, "reason": "n108_unknown_real_ship"}
    var ship: Dictionary = _world["ships"][ship_id]
    if not str(ship.get("active_contract_id", "")).is_empty() or not (
            ship.get("transit", {}) as Dictionary).is_empty():
        return {"ok": false, "reason": "n108_ship_busy_on_native_obligation"}
    var bt: Variant = ship.get("current_bt", null)
    if not (bt is Dictionary) or not NativeBt.validate(bt) or NativeBt.current_action(bt) != "Refit":
        return {"ok": false, "reason": "n108_no_persisted_native_refit_order"}
    var dock_id: String = str(ship.get("docked_at", ""))
    if dock_id.is_empty() or not _world["facilities"].has(dock_id):
        return {"ok": false, "reason": "n108_not_docked_at_physical_yard"}
    var yard: Dictionary = _world["facilities"][dock_id]
    if str(yard.get("type", "")) != "shipyard" or bool(yard.get("abandoned", false)):
        return {"ok": false, "reason": "n108_real_paid_shipyard_absent"}
    if str(ship.get("location", "")) != str(yard.get("location", "")):
        return {"ok": false, "reason": "n108_wrong_native_shipyard_dock"}
    var next: Dictionary = NativeShipyardRefit.agent_refit(
        _world, ship_id, slot, slug)
    if not next.get("ok", false):
        return next
    var stage: Dictionary = next.get("world", {})
    if stage.size() != _world.size() or stage["ships"].size() != _world["ships"].size() or stage["facilities"].size() != _world["facilities"].size():
        return {"ok": false, "fatal": true, "reason": "n108_invalid_single_world_shape"}
    for domain in _world:
        if domain not in ["ships", "facilities"] and stage.get(domain, null) != _world[domain]:
            return {"ok": false, "fatal": true, "reason": "n108_modified_unrelated_domain"}
    for other in _world["ships"]:
        if str(other) != ship_id and stage["ships"][other] != _world["ships"][other]:
            return {"ok": false, "fatal": true, "reason": "n108_modified_other_ship"}
    for other in _world["facilities"]:
        if str(other) != dock_id and stage["facilities"][other] != _world["facilities"][other]:
            return {"ok": false, "fatal": true, "reason": "n108_modified_other_facility"}
    var ship_fields: Array[String] = ["credits", "fitting", "cargo_capacity",
        "speed_modifier", "fuel_efficiency_mult", "comms_bonus",
        "progression", "lifecycle_dirty"]
    for field in ship:
        if field not in ship_fields and stage["ships"][ship_id].get(field, null) != ship[field]:
            return {"ok": false, "fatal": true, "reason": "n108_invalid_physical_ship_change"}
    var original_yard: Dictionary = _world["facilities"][dock_id]
    for field in original_yard:
        if field not in ["credits", "module_stock", "dirty"] and stage["facilities"][dock_id].get(field, null) != original_yard[field]:
            return {"ok": false, "fatal": true, "reason": "n108_invalid_native_shipyard_change"}
    var original_stock: Dictionary = original_yard.get("module_stock", {}).get("stock", {})
    var new_stock: Dictionary = stage["facilities"][dock_id].get("module_stock", {}).get("stock", {})
    if int(original_stock.get(slug, 0)) < 1 or int(new_stock.get(slug, -1)) != int(original_stock[slug]) - 1:
        return {"ok": false, "fatal": true, "reason": "n108_unpaid_module_stock_delta"}
    for module_slug in original_stock:
        if module_slug != slug and new_stock.get(module_slug, null) != original_stock[module_slug]:
            return {"ok": false, "fatal": true, "reason": "n108_modified_unrelated_module_stock"}
    var cost: int = int(next.get("cost", -1))
    if cost <= 0 or int(ship["credits"]) - int(stage["ships"][ship_id]["credits"]) != cost or int(stage["facilities"][dock_id]["credits"]) - int(original_yard["credits"]) != cost:
        return {"ok": false, "fatal": true, "reason": "n108_invalid_original_module_price"}
    var staged_money = Ledger.new()
    if not staged_money.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "n108_n9_ledger_unavailable"}
    var receipt_id: String = "n108:refit:" + ship_id + ":" + slot + ":" + str(tick)
    var receipt: Dictionary = staged_money.transfer(receipt_id,
        Schema.ship_account(ship_id), Schema.facility_account(dock_id),
        cost, tick, "native_paid_shipyard_refit")
    if not receipt.get("ok", false):
        return {"ok": false, "reason": "n108_n9_paid_refit_rejected:" +
            str(receipt.get("reason", "unknown"))}
    if staged_money.balance(Schema.ship_account(ship_id)) != int(stage["ships"][ship_id]["credits"]) or staged_money.balance(Schema.facility_account(dock_id)) != int(stage["facilities"][dock_id]["credits"]):
        return {"ok": false, "fatal": true, "reason": "n108_inconsistent_paid_refit_accounts"}
    var invalid: String = Schema.validate(stage)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n108_invalid_native_ship_after_refit:" + invalid}
    var accounts: Dictionary = Schema.accounts(stage)
    var balances: Dictionary = staged_money.snapshot().get("balances", {})
    if accounts.size() != balances.size() or staged_money.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n108_native_money_was_created"}
    for account in accounts:
        if balances.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n108_n39_n9_wallet_diverged"}
    _world = stage
    _ledger = staged_money
    return {"ok": true, "ship_id": ship_id, "shipyard_id": dock_id,
        "tick": tick, "slug": slug, "slot": slot, "cost": cost,
        "receipt": receipt_id, "event": next.get("events", []).duplicate(true),
        "authority": "one_native_n39_n9_refit_apply"}


## Single authoritative fleet commit. Called by the N158 ships phase
## (before facilities), or by a validated explicit departure command between
## ticks. No second ship runner and no additional wallet authority.
func apply_ship_phase(tick: int, proposal: Dictionary,
        command: bool = false) -> bool:
    if not _ready or not (_world.get("ships") is Dictionary):
        return false
    if (command and tick != _last_tick) or (not command and tick != _last_tick + 1):
        return false
    if not bool(proposal.get("ok", false)):
        return false
    if not bool(proposal.get("changed", false)):
        return true
    if not (proposal.get("ships") is Dictionary):
        return false
    var new_ships: Dictionary = proposal["ships"]
    if new_ships.size() != _world["ships"].size() or typeof(proposal.get("next_token", null)) != TYPE_INT:
        return false
    var previous: Dictionary = _world["ships"]
    var frozen_fields: Array[String] = ["id", "name", "class",
        "faction_id", "size", "cargo_capacity", "fuel_capacity",
        "crew_size", "crew_roles", "cargo", "credits", "docked_at"]
    for ship_id in previous:
        if not new_ships.has(ship_id) or not (new_ships[ship_id] is Dictionary):
            return false
        var old: Dictionary = previous[ship_id]
        var candidate: Dictionary = new_ships[ship_id]
        for field in frozen_fields:
            if candidate.get(field, null) != old.get(field, null):
                return false
    var staged: Dictionary = _world.duplicate(true)
    staged["ships"] = new_ships.duplicate(true)
    staged["ship_next_token"] = int(proposal["next_token"])
    if Schema.validate(staged) != "":
        return false
    # No fleet transition is allowed to mint or move cash; all 24 source
    # ship wallets remain in the SAME N9 balances as the existing economy.
    var expected: Dictionary = Schema.accounts(staged)
    for account in expected:
        if _ledger.balance(str(account)) != int(expected[account]):
            return false
    _world = staged
    return true



## N21+N15 one-World dock/cargo command commit. N15 is physical inventory
## transfer only; trade/escrow/payment belongs to a later contract phase.
## No separate wallet, source stock, arrival process or hidden dock occupancy.
func apply_fleet_logistics(tick: int, proposal: Dictionary,
        in_native_ship_phase: bool = false) -> bool:
    if not _ready or tick != _last_tick + (1 if in_native_ship_phase else 0) or not bool(proposal.get("ok", false)):
        return false
    if not (proposal.get("world") is Dictionary) or not (proposal.get("receipt") is Dictionary):
        return false
    var staged: Dictionary = proposal["world"]
    var r: Dictionary = proposal["receipt"]
    var action: String = str(r.get("action", ""))
    var ship_id: String = str(r.get("ship_id", ""))
    var dock_id: String = str(r.get("facility_id", ""))
    var op_id: String = str(r.get("operation_id", ""))
    if not (action in ["dock", "undock", "load", "unload"]) or op_id.is_empty() or ship_id.is_empty():
        return false
    if int(r.get("tick", -1)) != tick or not _world["ships"].has(ship_id):
        return false
    if not (staged.get("ships") is Dictionary) or not (staged.get("markets") is Dictionary):
        return false
    if staged["ships"].size() != _world["ships"].size() or staged["markets"].size() != _world["markets"].size():
        return false
    # The proposal is not allowed to modify any other authoritative domain.
    for key in _world:
        if key not in ["ships", "markets", "dock_receipts", "cargo_receipts"]:
            if not staged.has(key) or staged[key] != _world[key]:
                return false
    if staged.size() != _world.size():
        return false
    var receipt_key: String = "cargo_receipts" if action in ["load", "unload"] else "dock_receipts"
    var other_key: String = "dock_receipts" if receipt_key == "cargo_receipts" else "cargo_receipts"
    if not (staged.get(receipt_key) is Dictionary) or not (staged.get(other_key) is Dictionary):
        return false
    if not (_world.get(receipt_key) is Dictionary) or not (_world.get(other_key) is Dictionary):
        return false
    if _world[receipt_key].has(op_id) or _world[other_key].has(op_id):
        return false
    if staged[other_key] != _world[other_key] or staged[receipt_key].size() != _world[receipt_key].size() + 1:
        return false
    if staged[receipt_key].get(op_id, null) != r:
        return false
    for old_op in _world[receipt_key]:
        if staged[receipt_key].get(old_op, null) != _world[receipt_key][old_op]:
            return false
    var before_ship: Dictionary = _world["ships"][ship_id]
    var after_ship: Dictionary = staged["ships"].get(ship_id, {})
    var variable_fields: Array[String] = ["cargo", "docked_at"]
    for sid in _world["ships"]:
        if not (staged["ships"].get(sid) is Dictionary):
            return false
        var before: Dictionary = _world["ships"][sid]
        var after: Dictionary = staged["ships"][sid]
        for field in before:
            if field not in variable_fields or str(sid) != ship_id:
                if after.get(field, null) != before[field]:
                    return false
        for field in after:
            if not before.has(field) and field != "docked_at":
                return false
    for location in _world["markets"]:
        if not (staged["markets"].get(location) is Dictionary):
            return false
        var old_market: Dictionary = _world["markets"][location]
        var new_market: Dictionary = staged["markets"][location]
        for field in old_market:
            if field != "supply" or action in ["dock", "undock"] or location != r.get("location_id", ""):
                if new_market.get(field, null) != old_market[field]:
                    return false
        if new_market.size() != old_market.size():
            return false
    if action in ["dock", "undock"]:
        if after_ship.get("cargo", {}) != before_ship.get("cargo", {}):
            return false
        if not _world["facilities"].has(dock_id):
            return false
        var real_kind: String = str(_world["facilities"][dock_id].get("type", ""))
        if real_kind not in ["station", "shipyard"]:
            return false
        if real_kind == "shipyard":
            # N108: stations cannot stand in for actual paid shipyards.
            # A real N84 ship refit mission must own this dock/undock;
            # manual contract delivery may never request a shipyard slot.
            var tree: Variant = before_ship.get("current_bt", null)
            if str(before_ship.get("current_goal", "")) not in ["retrofit", "refit"] or not (tree is Dictionary) or not NativeBt.validate(tree):
                return false
        if str(before_ship.get("location", "")) != str(_world["facilities"][dock_id]["location"]):
            return false
        if action == "dock" and (not str(before_ship.get("docked_at", "")).is_empty() or str(after_ship.get("docked_at", "")) != dock_id):
            return false
        if action == "undock" and (str(before_ship.get("docked_at", "")) != dock_id or not str(after_ship.get("docked_at", "")).is_empty()):
            return false
    else:
        if str(before_ship.get("docked_at", "")) != dock_id or str(after_ship.get("docked_at", "")) != dock_id:
            return false
        var location: String = str(r.get("location_id", ""))
        if not _world["markets"].has(location) or str(_world["markets"][location].get("owner", "")) != dock_id:
            return false
        # N15 manual transfers are internal to the owner faction until
        # N104 paid contract settlement and inter-faction trade are wired.
        if not _world["facilities"].has(dock_id) or str(_world["facilities"][dock_id]["faction"]) != str(before_ship["faction_id"]):
            return false
        if not (r.get("quantities") is Dictionary) or r["quantities"].is_empty():
            return false
        var old_stock: Dictionary = _world["markets"][location]["supply"]
        var new_stock: Dictionary = staged["markets"][location]["supply"]
        var old_hold: Dictionary = before_ship["cargo"]
        var new_hold: Dictionary = after_ship["cargo"]
        var delta: float = 1.0 if action == "load" else -1.0
        var commodities: Dictionary = {}
        for commodity in old_stock:
            commodities[commodity] = true
        for commodity in new_stock:
            commodities[commodity] = true
        for commodity in old_hold:
            commodities[commodity] = true
        for commodity in new_hold:
            commodities[commodity] = true
        for commodity in r["quantities"]:
            commodities[commodity] = true
        for commodity in commodities:
            var quantity: Variant = r["quantities"].get(commodity, 0)
            if typeof(quantity) != TYPE_INT or int(quantity) < 0:
                return false
            var expected: float = delta * float(quantity)
            if not is_equal_approx(float(new_hold.get(commodity, 0)) - float(old_hold.get(commodity, 0)), expected):
                return false
            if not is_equal_approx(float(new_stock.get(commodity, 0)) - float(old_stock.get(commodity, 0)), -expected):
                return false
    # Staged schema validates source docks, occupancy/capacity, stock and
    # cargo limits. Existing N9 ledger must still match EVERY account.
    if Schema.validate(staged) != "":
        return false
    var balances: Dictionary = Schema.accounts(staged)
    for account in balances:
        if _ledger.balance(str(account)) != int(balances[account]):
            return false
    _world = staged.duplicate(true)
    return true



## N84/N146 ship execution during the native SHIPS phase. This is the
## ONLY atomic publishing authority for N15 stock, N97 purchase/credits,
## N104 verified delivery status and N9 escrow transfer. The paid cargo
## adapter stages a deep copy; rejecting leaves ALL World/ledger unchanged.
func apply_autonomous_contract_cargo(tick: int, ship_id: String,
        contract_id: String, operation: String) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "not_the_live_ship_phase"}
    if operation not in ["pickup", "delivery"]:
        return {"ok": false, "reason": "unknown_native_paid_ship_action"}
    var proposed: Dictionary = PaidCargo.propose(_world, _ledger.snapshot(),
        ship_id, contract_id, operation, tick)
    if not proposed.get("ok", false):
        return proposed
    var staged: Dictionary = proposed["world"]
    var money: Dictionary = proposed["ledger_snapshot"]
    var receipt_id: String = str(proposed["receipt_id"])
    var money_id: String = str(proposed["money_receipt"])
    if not _world["ships"].has(ship_id) or not _world["contract_board"]["contracts"].has(contract_id):
        return {"ok": false, "fatal": true, "reason": "canonical_contract_disappeared"}
    var original_contract: Dictionary = _world["contract_board"]["contracts"][contract_id]
    var location: String = str(original_contract["source_location"]) if operation == "pickup" else str(original_contract["destination_location"])
    var station: String = str(_world["markets"][location]["owner"])
    var original_ship: Dictionary = _world["ships"][ship_id]
    var changed_ship: Dictionary = staged["ships"][ship_id]
    if staged.size() != _world.size() or staged["ships"].size() != _world["ships"].size():
        return {"ok": false, "fatal": true, "reason": "unexpected_native_world_shape"}
    for domain in _world:
        if domain not in ["ships", "markets", "facilities", "contract_board",
                "escrow_balances", "cargo_receipts"] and staged.get(domain, null) != _world[domain]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_altered_unrelated_domain"}
    for id in _world["ships"]:
        if str(id) != ship_id and staged["ships"][id] != _world["ships"][id]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_altered_other_ship"}
    var ship_fields: Array[String] = ["cargo", "credits"]
    if operation == "delivery":
        # Native N101 ship XP/retrofit points are credited ONLY by the
        # same actual N97/N104 paid delivery receipt.
        ship_fields.append_array(["active_contract_id", "current_goal",
            "current_bt", "max_source_cost", "progression"])
    for field in original_ship:
        if field not in ship_fields and changed_ship.get(field, null) != original_ship[field]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_changed_ship_state"}
    for key in changed_ship:
        if not original_ship.has(key):
            return {"ok": false, "fatal": true, "reason": "paid_delivery_added_ship_field"}
    for m in _world["markets"]:
        if str(m) != location and staged["markets"][m] != _world["markets"][m]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_changed_other_market"}
        if str(m) == location:
            var old_market: Dictionary = _world["markets"][m]
            var new_market: Dictionary = staged["markets"][m]
            for field in old_market:
                if field != "supply" and new_market.get(field, null) != old_market[field]:
                    return {"ok": false, "fatal": true, "reason": "paid_delivery_changed_market_rules"}
    for f in _world["facilities"]:
        if str(f) != station and staged["facilities"][f] != _world["facilities"][f]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_changed_other_facility"}
        if str(f) == station:
            var before_facility: Dictionary = _world["facilities"][f]
            var after_facility: Dictionary = staged["facilities"][f]
            for field in before_facility:
                if field != "credits" and before_facility[field] != after_facility.get(field, null):
                    return {"ok": false, "fatal": true, "reason": "paid_delivery_changed_station_state"}
    var old_stock: Dictionary = _world["markets"][location]["supply"]
    var new_stock: Dictionary = staged["markets"][location]["supply"]
    var old_hold: Dictionary = original_ship["cargo"]
    var new_hold: Dictionary = changed_ship["cargo"]
    var good: String = str(original_contract["commodity"])
    var count: int = int(original_contract["quantity"])
    var delta: int = count if operation == "pickup" else -count
    if not is_equal_approx(float(new_stock.get(good, 0.0)) - float(old_stock.get(good, 0.0)), float(-delta)):
        return {"ok": false, "fatal": true, "reason": "paid_delivery_wrong_market_quantity"}
    if int(new_hold.get(good, 0)) - int(old_hold.get(good, 0)) != delta:
        return {"ok": false, "fatal": true, "reason": "paid_delivery_wrong_ship_quantity"}
    for item in old_stock:
        if str(item) != good and new_stock.get(item, null) != old_stock[item]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_moved_other_commodity"}
    for item in old_hold:
        if str(item) != good and new_hold.get(item, null) != old_hold[item]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_moved_other_hold_goods"}
    if staged["cargo_receipts"].size() != _world["cargo_receipts"].size() + 1 or not staged["cargo_receipts"].has(receipt_id):
        return {"ok": false, "fatal": true, "reason": "paid_delivery_missing_one_physical_receipt"}
    for previous in _world["cargo_receipts"]:
        if staged["cargo_receipts"].get(previous, null) != _world["cargo_receipts"][previous]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_modified_old_receipt"}
    if staged["contract_board"]["contracts"].size() != _world["contract_board"]["contracts"].size():
        return {"ok": false, "fatal": true, "reason": "paid_delivery_fabricated_contract"}
    for cid in _world["contract_board"]["contracts"]:
        if str(cid) != contract_id and staged["contract_board"]["contracts"].get(cid, null) != _world["contract_board"]["contracts"][cid]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_mutated_other_contract"}
    var expected_status: String = "picked_up" if operation == "pickup" else "paid"
    if str(staged["contract_board"]["contracts"][contract_id].get("status", "")) != expected_status:
        return {"ok": false, "fatal": true, "reason": "paid_delivery_not_confirmed_in_n104"}
    var old_bank: Dictionary = _ledger.snapshot()
    var staged_ledger := Ledger.new()
    if not staged_ledger.restore(money) or staged_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "paid_delivery_money_not_conserved"}
    if money["receipts"].size() != old_bank["receipts"].size() + 1 or not money["receipts"].has(money_id):
        return {"ok": false, "fatal": true, "reason": "paid_delivery_missing_one_money_receipt"}
    for old_id in old_bank["receipts"]:
        if money["receipts"].get(old_id, null) != old_bank["receipts"][old_id]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_tampered_financial_receipt"}
    var staged_board := ContractBoard.new(staged_ledger)
    if not staged_board.restore(staged["contract_board"]):
        return {"ok": false, "fatal": true, "reason": "paid_delivery_invalid_original_board"}
    # The original N15 physical ship unload has ALREADY deposited goods
    # into the destination market. Native N154 apply_construction_delivery
    # consumes those REAL goods into site.progress after proven N104 payout,
    # within this SAME N39 World+Ledger commit. No second market credit.
    if operation == "delivery" and staged.get("construction_contracts", {}).has(contract_id):
        var site_id: String = str(staged["construction_contracts"][contract_id])
        if not staged.get("construction_sites", {}).has(site_id):
            return {"ok": false, "fatal": true, "reason": "construction_site_missing_at_paid_delivery"}
        var material_receipt_id: String = "native_construction_delivery:" + contract_id
        if staged.get("construction_receipts", {}).has(material_receipt_id):
            return {"ok": false, "fatal": true, "reason": "construction_material_receipt_replayed"}
        var site_before: Dictionary = staged["construction_sites"][site_id]
        if bool(site_before.get("completed", false)) or str(site_before.get("location_name", "")) != location or str(site_before.get("commodity", "")) != good:
            return {"ok": false, "fatal": true, "reason": "construction_paid_site_mismatch"}
        var attached: Dictionary = NativeConstructionMaterial.material_delivery(
            [site_before], staged["markets"], location, good, count)
        if not attached.get("ok", false) or bool(attached.get("fallback_to_market", true)):
            return {"ok": false, "fatal": true, "reason": "native_construction_delivery_rejected"}
        var consumed: int = int(attached.get("admitted_units", -1))
        if consumed != count or consumed <= 0:
            # Don't publish a partly consumed paid shipment without the
            # explicit original market fallback for the surplus.
            return {"ok": false, "fatal": true, "reason": "construction_paid_quantity_overflows_site"}
        var stock_after_ship: float = float(staged["markets"][location]["supply"].get(good, 0.0))
        if stock_after_ship < float(consumed):
            return {"ok": false, "fatal": true, "reason": "construction_materials_not_physically_delivered"}
        staged["markets"][location]["supply"][good] = stock_after_ship - float(consumed)
        staged["construction_sites"][site_id] = (attached["sites"][0] as Dictionary).duplicate(true)
        staged["construction_receipts"][material_receipt_id] = {
            "id": material_receipt_id, "kind": "delivery",
            "site_id": site_id, "contract_id": contract_id,
            "quantity": consumed, "tick": tick,
            "n15_receipt_id": receipt_id, "n9_receipt_id": money_id}
    var error: String = Schema.validate(staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "paid_delivery_invalid_world_" + error}
    var accounts: Dictionary = Schema.accounts(staged)
    if accounts.size() != money["balances"].size():
        return {"ok": false, "fatal": true, "reason": "paid_delivery_wallet_count"}
    for wallet in accounts:
        if money["balances"].get(wallet, null) != accounts[wallet]:
            return {"ok": false, "fatal": true, "reason": "paid_delivery_account_divergence"}
    _world = staged
    _ledger = staged_ledger
    return {"ok": true, "status": str(proposed["status"]),
        "contract_id": contract_id, "ship_id": ship_id,
        "receipt_id": receipt_id, "money_receipt": money_id,
        "credits": int(proposed["credits"]), "tick": tick}




## Native N91 engineer dispatch is ONE live N39 ship mutation only.
## The original N91 choose() supplies a candidate; actual ownership,
## physical site completion and idle ship are checked AGAIN before commit.
## No money, materials, position, building or dock status is altered here.
func apply_native_construction_assignments(tick: int, proposals: Array,
        resolver: RefCounted = null, graph: RefCounted = null,
        positions: Dictionary = {}, scale: float = 1.0) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1:
        return {"ok": false, "reason": "n91_not_canonical_faction_tick"}
    if not _world.has("construction_sites"):
        return {"ok": true, "status": "N91_LEGACY_DISABLED", "assigned": []}
    var staged: Dictionary = _world.duplicate(true)
    var updated: Array = []
    var used_sites: Dictionary = {}
    var used_ships: Dictionary = {}
    for raw in proposals:
        if not (raw is Dictionary):
            return {"ok": false, "fatal": true, "reason": "n91_invalid_native_proposal"}
        var site_id: String = str(raw.get("site_id", ""))
        var ship_id: String = str(raw.get("ship_id", ""))
        if ship_id.is_empty() or site_id.is_empty() or used_sites.has(site_id) or used_ships.has(ship_id):
            return {"ok": false, "fatal": true, "reason": "n91_duplicate_site_or_ship"}
        if not staged["ships"].has(ship_id) or not staged["construction_sites"].has(site_id):
            return {"ok": false, "fatal": true, "reason": "n91_phantom_actor_or_site"}
        var site: Dictionary = staged["construction_sites"][site_id]
        var ship: Dictionary = staged["ships"][ship_id]
        if not N91SourceDispatch.physical_site_funded(staged, _ledger.snapshot(), site_id):
            return {"ok": false, "fatal": true, "reason": "n91_unpaid_site_materials_cannot_dispatch"}
        var loc: String = str(site.get("location_name", ""))
        if bool(site.get("completed", false)) or int(site.get("progress_delivered", 0)) != int(site.get("progress_required", -1)) or int(site.get("labor", {}).get("completed", 0)) >= int(site.get("labor", {}).get("required", 0)):
            return {"ok": false, "fatal": true, "reason": "n91_site_not_paid_and_ready"}
        if str(site.get("faction_id", "")) != str(ship.get("faction_id", "")) or str(ship.get("location", "")).is_empty() or not ship.get("transit", {}).is_empty():
            return {"ok": false, "fatal": true, "reason": "n91_engineer_not_in_real_system"}
        if str(ship.get("current_goal", "")) not in ["", "idle"] or not str(ship.get("active_contract_id", "")).is_empty() or not ship.get("cargo", {}).is_empty():
            return {"ok": false, "fatal": true, "reason": "n91_ship_has_existing_obligation"}
        if not N91Executor.capable(str(ship.get("class", "")), ShipCatalog.CLASSES):
            return {"ok": false, "fatal": true, "reason": "n91_ship_has_no_native_engineer"}
        var market: Dictionary = staged.get("markets", {}).get(loc, {})
        var dock: Dictionary = staged.get("facilities", {}).get(str(market.get("owner", "")), {})
        if dock.is_empty() or str(dock.get("faction", "")) != str(site["faction_id"]) or int(dock.get("docking_capacity", -1)) < 1:
            return {"ok": false, "fatal": true, "reason": "n91_no_real_site_warehouse"}
        var claimed: bool = false
        for other_id in staged["ships"]:
            if str(other_id) == ship_id:
                continue
            var other: Dictionary = staged["ships"][other_id]
            if str(other.get("current_goal", "")) == "construct" and other.get("current_bt") is Dictionary and N91Executor.target(other["current_bt"]) == site_id:
                claimed = true
                break
        if claimed:
            return {"ok": false, "fatal": true, "reason": "n91_construction_site_already_assigned"}
        # Regenerate the ONLY allowed N84 sequence from canonical World
        # and the original N4 graph, including real fuel and N21 origin dock.
        # The selector's proposed route/BT is NEVER trusted as authority.
        var expected: Dictionary = N91SourceDispatch.plan_for(staged, resolver,
            graph, positions, ship_id, site_id, scale)
        if not expected.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": str(expected.get("reason", "n91_unverified_remote_route"))}
        var plan: Dictionary = raw.get("bt", {})
        if not NativeBt.validate(plan) or plan != expected["bt"] or raw.get("route", expected["route"]) != expected["route"]:
            return {"ok": false, "fatal": true, "reason": "n91_untrusted_goal_tree"}
        var loyalty: float = N91SourceDispatch._loyalty(ship)
        var priority: float = N91Executor.utility(loyalty)
        if not is_finite(priority) or not is_equal_approx(float(raw.get("score", -1.0)), priority):
            return {"ok": false, "fatal": true, "reason": "n91_source_utility_mismatch"}
        ship["current_goal"] = "construct"
        ship["current_bt"] = plan.duplicate(true)
        ship["current_goal_score"] = priority
        ship["last_plan_tick"] = tick
        ship["planning_source"] = "source_n91_same_system_engineer"
        used_sites[site_id] = true
        used_ships[ship_id] = true
        updated.append({"ship_id": ship_id, "site_id": site_id})
    var issue: String = Schema.validate(staged)
    if not issue.is_empty():
        return {"ok": false, "fatal": true, "reason": "n91_invalid_world_" + issue}
    var balances: Dictionary = Schema.accounts(staged)
    if balances.size() != _ledger.snapshot().get("balances", {}).size():
        return {"ok": false, "fatal": true, "reason": "n91_wallet_count_changed"}
    for account in balances:
        if _ledger.balance(str(account)) != int(balances[account]):
            return {"ok": false, "fatal": true, "reason": "n91_wallet_modified"}
    if not updated.is_empty():
        _world = staged
    return {"ok": true, "status": "N91_NATIVE_ENGINEERS_ASSIGNED",
        "tick": tick, "assigned": updated}


## Stage a native N151 founding expedition as a real but UNBUILT N39
## ConstructionSite. No N9 charge: the frozen Rust commission creates the
## site first, and only later posts paid passenger/metals contracts.
## A live N134 colony-head grant (not a GUI instruction) is required.
func apply_native_colony_foundation(tick: int, faction: String,
        body_id: String, source: String, original: RefCounted,
        graph: RefCounted, head_authorized: bool) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or not head_authorized:
        return {"ok": false, "reason": "n151_colony_head_or_native_tick_missing"}
    if not (_world.get("construction_sites") is Dictionary):
        return {"ok": false, "reason": "n151_no_canonical_site_registry"}
    var candidate: Dictionary = NativeColonyFounding.proposal(_world,
        original, graph, faction, body_id, source, tick, 1, true)
    if not candidate.get("ok", false):
        return candidate
    var site: Dictionary = candidate["site"]
    var site_id: String = str(site.get("id", ""))
    if site_id.is_empty() or _world["construction_sites"].has(site_id):
        return {"ok": false, "reason": "n151_colony_site_duplicate"}
    var receipt_id: String = "n151_colony_approved:" + site_id
    if _world["construction_receipts"].has(receipt_id) or _ledger.has_receipt(receipt_id):
        return {"ok": false, "reason": "n151_colony_approval_replayed"}
    var original_money: Dictionary = _ledger.snapshot()
    var staged: Dictionary = _world.duplicate(true)
    staged["construction_sites"][site_id] = site.duplicate(true)
    staged["construction_receipts"][receipt_id] = {
        "id": receipt_id, "kind": "colony_approved",
        "site_id": site_id, "tick": tick,
        "faction_id": faction, "source_location": source,
        "destination_location": str(site["location_name"]),
        "body_id": body_id, "capital": 0, "n9_receipt_id": ""}
    var validation: String = Schema.validate(staged)
    if not validation.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n151_native_site_world_" + validation}
    if _ledger.snapshot() != original_money or Schema.accounts(staged) != Schema.accounts(_world):
        return {"ok": false, "fatal": true, "reason": "n151_colony_spawn_invented_funds"}
    # Sole authority: N39 World; N9 Ledger untouched as original Rust
    # colony::commission's initial site approval has zero monetary cost.
    _world = staged
    return {"ok": true, "status": "N151_PHYSICAL_COLONY_SITE_CREATED",
        "tick": tick, "site_id": site_id, "receipt_id": receipt_id,
        "faction_id": faction, "body_id": body_id,
        "passengers": 0, "metals_delivered": 0,
        "money_debited": 0}


## N141: real docked-engineer physical construction shift + one N9 payroll.
## Source N141 WorkShift chooses existing households and excludes labor
## already employed by N39 facilities, N143 Director and other N141 sites.
## This phase does not invent completed facilities: N154 materialization and
## builder AI authorization are separate gated native operations.
func apply_native_construction_labor(tick: int, multiplier: int) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1:
        return {"ok": false, "reason": "not_current_native_construction_tick"}
    if not _world.has("construction_sites"):
        return {"ok": true, "status": "LEGACY_CONSTRUCTION_UNAVAILABLE",
            "paid": [], "blocked": []}
    if not NativeConstructionMaterial.labor_tick_due(tick, multiplier):
        return {"ok": true, "status": "N141_NOT_DUE",
            "paid": [], "blocked": []}
    var site_ids: Array = _world["construction_sites"].keys()
    site_ids.sort()
    if site_ids.is_empty():
        return {"ok": true, "status": "N141_NO_ACTIVE_SITES",
            "paid": [], "blocked": []}
    var staged: Dictionary = _world.duplicate(true)
    var ledger := Ledger.new()
    if not ledger.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "n141_cannot_stage_n9"}
    var paid: Array = []
    var blocked: Array = []
    var completed_sites: Array = []
    for site_id in site_ids:
        var proposed: Dictionary = NativeConstructionLabor.paid_shift(
            staged, str(site_id), tick, multiplier)
        if not proposed.get("ok", false):
            blocked.append({"site_id": str(site_id),
                "reason": str(proposed.get("reason", "native_builder_unavailable"))})
            continue
        var source_state: Dictionary = proposed["state"]
        var workers: int = int(proposed.get("workers", 0))
        var site: Dictionary = source_state["site"]
        var faction: String = str(proposed["faction_id"])
        if workers <= 0:
            # Native N141 allows successful zero-worker work once all
            # labor is already complete; N154 may now materialize.
            if NativeConstructionMaterial.ready_for_materialization(site):
                completed_sites.append(str(site_id))
            continue
        var receipt_id: String = "native_construction_labor:" + str(site_id) + ":" + str(tick)
        if staged["construction_receipts"].has(receipt_id) or ledger.has_receipt(receipt_id):
            return {"ok": false, "fatal": true, "reason": "n141_duplicate_paid_shift"}
        var source_shift: Dictionary = proposed.get("shift", {})
        var wages: int = int(source_shift.get("wages", -1))
        var worker_rows: Variant = source_shift.get("workers", null)
        if wages != workers or wages <= 0 or not (worker_rows is Array):
            return {"ok": false, "fatal": true, "reason": "n141_native_wages_mismatch"}
        var legs: Array = [{"account": Schema.faction_account(faction), "delta": -wages}]
        var seen: Dictionary = {}
        var assigned_total: int = 0
        for pair in worker_rows:
            if not (pair is Array) or pair.size() != 2:
                return {"ok": false, "fatal": true, "reason": "n141_malformed_labor_workers"}
            var pid: String = str(pair[0])
            var count: int = int(pair[1])
            if not staged["populations"].has(pid) or seen.has(pid) or count <= 0:
                return {"ok": false, "fatal": true, "reason": "n141_nonexistent_or_reused_worker"}
            seen[pid] = true
            assigned_total += count
            legs.append({"account": Schema.household_account(pid), "delta": count})
        if assigned_total != workers:
            return {"ok": false, "fatal": true, "reason": "n141_ledger_labor_count_mismatch"}
        if ledger.balance(Schema.faction_account(faction)) != int(staged["faction_treasuries"][faction]):
            return {"ok": false, "fatal": true, "reason": "n141_treasury_divergence"}
        var result: Dictionary = ledger.commit(receipt_id, legs, tick,
            "n141_native_paid_construction_work")
        if not result.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": "n141_n9_wage_" + str(result.get("reason", "rejected"))}
        if int(source_state["faction"]["treasury"]) != ledger.balance(Schema.faction_account(faction)):
            return {"ok": false, "fatal": true, "reason": "n141_native_treasury_receipt_mismatch"}
        staged["faction_treasuries"][faction] = ledger.balance(Schema.faction_account(faction))
        for source_household in source_state["households"]:
            var pid: String = str(source_household["id"])
            if not staged["populations"].has(pid):
                return {"ok": false, "fatal": true, "reason": "n141_original_household_missing"}
            if int(source_household["total_wealth"]) != ledger.balance(Schema.household_account(pid)):
                return {"ok": false, "fatal": true, "reason": "n141_household_receipt_mismatch"}
            staged["populations"][pid]["wealth"] = ledger.balance(Schema.household_account(pid))
            staged["populations"][pid]["employed_fraction"] = float(source_household["employed_fraction"])
        staged["construction_sites"][site_id] = site.duplicate(true)
        staged["construction_receipts"][receipt_id] = {
            "id": receipt_id, "kind": "labor",
            "tick": tick, "site_id": str(site_id),
            "executor_id": str(proposed["executor_id"]),
            "wages": wages, "n9_receipt_id": receipt_id}
        paid.append(staged["construction_receipts"][receipt_id].duplicate(true))
        if NativeConstructionMaterial.ready_for_materialization(site):
            completed_sites.append(str(site_id))
    # Native N154 materialization is gated by a successful N141 work()
    # this SAME tick, including source-allowed zero-worker completion.
    # Initial working capital is a REAL transfer from the faction N9
    # account to the new facility's zero balance, not minted currency.
    var materialized: Array = []
    for site_id in completed_sites:
        var site: Dictionary = staged["construction_sites"][site_id]
        if site.get("labor", {}).get("colony_source", null) != null:
            # Colony formation belongs to N151's dock+market bridge.
            blocked.append({"site_id": str(site_id), "reason": "native_N151_colony_establish_required"})
            continue
        var faction: String = str(site["faction_id"])
        var kind: String = str(site["facility_type"])
        var crew_count: int = int(GalaxyConstructionCrew.get(kind, 6))
        # Use Rust FacilityFitting.new_default/FacilityCrew::new_for_type:
        # production_t1 + automation_t1, morale=80, no fresh workforce.
        var fitting: Dictionary = {
            "slots": ["production_t1", "automation_t1"],
            "derived": {"recipe_output_mult": 1.0, "max_batches_bonus": 0},
            "dirty": false}
        var crew: Dictionary = {"work_shift": null, "crew_count": crew_count,
            "morale": 80.0, "hunger": 0.0, "food_debt": 0.0,
            "work_blocked_reason": null, "dirty": false}
        var native_facs: Array = []
        for fid in staged["facilities"]:
            var f: Dictionary = staged["facilities"][fid]
            native_facs.append({"id": str(fid),
                "location_name": str(f["location"]), "location_id": 0})
        var original: Dictionary = {
            "factions": {faction: {"treasury": int(staged["faction_treasuries"][faction])}},
            "facilities": native_facs}
        var source_receipt: Dictionary = {
            "trusted_internal_apply": true, "labor_work_succeeded": true,
            "site_id": str(site_id), "tick": tick}
        var native: Dictionary = NativeConstructionMaterial.materialize_after_paid_labor(
            site, original, source_receipt,
            int(staged["construction_next_db_id"]), null,
            fitting, crew, tick)
        if not native.get("ok", false) or str(native.get("kind", "")) != "materialize_native_facility":
            return {"ok": false, "fatal": true, "reason": "n154_native_materialization_" + str(native.get("reason", native.get("kind", "rejected")))}
        var raw: Dictionary = native["facility"]
        var new_id: String = str(raw.get("id", ""))
        var capital: int = int(raw.get("credits", -1))
        var new_account: String = Schema.facility_account(new_id)
        if new_id.is_empty() or staged["facilities"].has(new_id) or capital < 0 or not ledger.register_empty_account(new_account):
            return {"ok": false, "fatal": true, "reason": "n154_phantom_or_duplicate_facility"}
        var receipt_id: String = "native_construction_materialize:" + str(site_id) + ":" + str(tick)
        if staged["construction_receipts"].has(receipt_id) or ledger.has_receipt(receipt_id):
            return {"ok": false, "fatal": true, "reason": "n154_repeated_facility_materialization"}
        if capital > 0:
            var transfer: Dictionary = ledger.transfer(receipt_id,
                Schema.faction_account(faction), new_account,
                capital, tick, "n154_native_working_capital")
            if not transfer.get("ok", false):
                return {"ok": false, "fatal": true,
                    "reason": "n154_ledger_capital_" + str(transfer.get("reason", "failed"))}
        if int(native["world"]["factions"][faction]["treasury"]) != ledger.balance(Schema.faction_account(faction)):
            return {"ok": false, "fatal": true, "reason": "n154_native_source_capital_mismatch"}
        staged["faction_treasuries"][faction] = ledger.balance(Schema.faction_account(faction))
        staged["facilities"][new_id] = {
            "type": kind, "faction": faction,
            "location": str(site["location_name"]),
            "body_id": str(site["body_id"]),
            "credits": ledger.balance(new_account),
            "crew_count": crew_count, "docking_capacity": 4,
            "morale": 80.0, "level": 1, "xp": 0,
            "abandoned": false, "condition": 1.0,
            "reserves": {}, "fitting_output_mult": 1.0,
            "fitting_batches_bonus": 0,
            "native_db_id": int(staged["construction_next_db_id"]),
            "construction_source_site_id": str(site_id)}
        staged["construction_next_db_id"] = int(staged["construction_next_db_id"]) - 1
        # Physical site and its active materials orders are retired in
        # the SAME transaction as the new facility's N9 account.
        for cid in staged["construction_contracts"].keys():
            if str(staged["construction_contracts"][cid]) == str(site_id):
                var c: Dictionary = staged["contract_board"].get("contracts", {}).get(cid, {})
                if str(c.get("status", "")) not in ["paid", "expired"]:
                    return {"ok": false, "fatal": true, "reason": "n154_unfinished_physical_material_contract"}
                staged["construction_contracts"].erase(cid)
        staged["construction_sites"].erase(site_id)
        staged["construction_receipts"][receipt_id] = {
            "id": receipt_id, "kind": "materialize",
            "tick": tick, "site_id": str(site_id), "facility_id": new_id,
            "capital": capital, "n9_receipt_id": receipt_id if capital > 0 else ""}
        materialized.append({"site_id": str(site_id), "facility_id": new_id,
            "capital": capital})
    var error: String = Schema.validate(staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n141_invalid_world_" + error}
    var expected: Dictionary = Schema.accounts(staged)
    var wallet_values: Dictionary = ledger.snapshot()["balances"]
    if wallet_values.size() != expected.size() or ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n141_money_supply_modified"}
    for id in expected:
        if expected[id] != wallet_values.get(id, null):
            return {"ok": false, "fatal": true, "reason": "n141_n9_wallet_mismatch"}
    if not paid.is_empty() or not materialized.is_empty():
        _world = staged
        _ledger = ledger
    return {"ok": true, "status": "N141_N154_NATIVE_PAID_CONSTRUCTION",
        "tick": tick, "paid": paid, "materialized": materialized,
        "blocked": blocked}


## Gate4: N155 observed head → N143 paid research, with ONLY the N9
## authoritative money and N39 World as the final atomic commit.
## All candidates are rebuilt from current live markets/work shifts,
## never trusted merely because an AI proposal claims that it paid.
func apply_native_research_phase(tick: int, source_factions: Dictionary,
        multiplier: int) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1:
        return {"ok": false, "reason": "research_outside_live_faction_phase"}
    var proposed: Dictionary = NativeResearch.propose(_world,
        source_factions, tick, multiplier)
    if not proposed.get("ok", false):
        return proposed
    if str(proposed.get("status", "")) == "LEGACY_RESEARCH_COMPONENT_ABSENT":
        return {"ok": true, "status": "LEGACY_RESEARCH_UNFUNDED",
            "tick": tick, "paid": [], "blocked": []}
    if not (proposed.get("heads") is Dictionary) or not (proposed.get("shifts") is Array):
        return {"ok": false, "fatal": true, "reason": "invalid_n143_source_intents"}
    var staged: Dictionary = _world.duplicate(true)
    if proposed["heads"].size() != staged["research_directors"].size():
        return {"ok": false, "fatal": true, "reason": "missing_native_research_head"}
    for fid in proposed["heads"]:
        if not staged["research_directors"].has(fid):
            return {"ok": false, "fatal": true, "reason": "extra_native_research_head"}
        staged["research_directors"][fid] = proposed["heads"][fid].duplicate(true)
    var staged_ledger = Ledger.new()
    if not staged_ledger.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "research_ledger_staging_failed"}
    var paid: Array = []
    for intent in proposed["shifts"]:
        if not (intent is Dictionary) or not intent.get("ok", false):
            return {"ok": false, "fatal": true, "reason": "invalid_native_paid_intent"}
        var fid: String = str(intent.get("faction_id", ""))
        var facility_id: String = str(intent.get("facility_id", ""))
        var population_id: String = str(intent.get("population_id", ""))
        var location: String = str(intent.get("location", ""))
        var receipt_id: String = str(intent.get("receipt_id", ""))
        var stock: Dictionary = {}
        if fid.is_empty() or not staged["faction_treasuries"].has(fid) or not staged["facilities"].has(facility_id) or not staged["populations"].has(population_id) or not staged["markets"].has(location):
            return {"ok": false, "fatal": true, "reason": "research_missing_world_actor"}
        if staged["research_receipts"].has(receipt_id) or staged_ledger.has_receipt(receipt_id):
            return {"ok": false, "fatal": true, "reason": "research_repeated_paid_receipt"}
        var market: Dictionary = staged["markets"][location]
        var facility: Dictionary = staged["facilities"][facility_id]
        var person: Dictionary = staged["populations"][population_id]
        var head: Dictionary = staged["research_directors"][fid]
        if str(market.get("owner", "")) != facility_id or str(facility.get("type", "")) != "station" or str(facility.get("faction", "")) != fid or str(person.get("faction", "")) != fid or str(person.get("location", "")) != location:
            return {"ok": false, "fatal": true, "reason": "research_source_ownership_changed"}
        if intent.get("preconditions") != {
            "treasury": int(staged["faction_treasuries"][fid]),
            "market_electronics": float(market.get("supply", {}).get("electronics", 0.0)),
            "facility_credits": int(facility["credits"]),
            "population_wealth": int(person["wealth"]),
            "last_research_tick": head.get("last_research_tick", null),
            "research": head.get("research", null)
        }:
            return {"ok": false, "fatal": true, "reason": "stale_native_research_preconditions"}
        var cost: int = int(intent.get("cost", 0))
        var payroll: int = int(intent.get("payroll", 0))
        if cost < 11 or payroll != 10 or float(market["supply"].get("electronics", 0.0)) < 1.0:
            return {"ok": false, "fatal": true, "reason": "research_missing_paid_input"}
        var faction_account: String = Schema.faction_account(fid)
        var facility_account: String = Schema.facility_account(facility_id)
        var population_account: String = Schema.household_account(population_id)
        var transaction: Dictionary = staged_ledger.commit(receipt_id, [
            {"account": faction_account, "delta": -cost},
            {"account": facility_account, "delta": cost - payroll},
            {"account": population_account, "delta": payroll}
        ], tick, "n143_native_research_shift")
        if not transaction.get("ok", false):
            # Rust skips shifts when the actual treasury cannot pay;
            # source AI never turns an unfunded preview into free science.
            return {"ok": false, "fatal": true,
                "reason": "research_paid_commit_" + str(transaction.get("reason", "rejected"))}
        var receipt: Dictionary = {
            "authoritative": true, "receipt_id": receipt_id,
            "faction_id": fid, "tick": tick,
            "market_id": str(market.get("id", "")),
            "facility_id": facility_id, "population_id": population_id,
            "effects": intent["effects"].duplicate(true),
            "technology": str(intent["technology"])
        }
        if not staged_ledger.has_receipt(receipt_id):
            return {"ok": false, "fatal": true, "reason": "research_receipt_not_in_n9"}
        var validated: Dictionary = ResearchShift.verify_authoritative_receipt(intent, receipt)
        if not validated.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": "n143_receipt_" + str(validated.get("reason", "invalid"))}
        market["supply"]["electronics"] = float(market["supply"]["electronics"]) - 1.0
        staged["faction_treasuries"][fid] = staged_ledger.balance(faction_account)
        facility["credits"] = staged_ledger.balance(facility_account)
        person["wealth"] = staged_ledger.balance(population_account)
        staged["research_directors"][fid] = validated["commander"].duplicate(true)
        staged["research"][fid] = validated["commander"].get("technologies", []).duplicate(true)
        staged["research_receipts"][receipt_id] = {
            "receipt_id": receipt_id, "faction_id": fid, "tick": tick,
            "facility_id": facility_id, "population_id": population_id,
            "technology": str(intent["technology"]),
            "cost": cost, "wages": payroll, "electronics": 1.0,
            "completed_technology": intent.get("completed_technology", null),
            "n9_receipt_id": receipt_id
        }
        paid.append(staged["research_receipts"][receipt_id].duplicate(true))
    var error: String = Schema.validate(staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "research_world_" + error}
    var expected: Dictionary = Schema.accounts(staged)
    var actual: Dictionary = staged_ledger.snapshot().get("balances", {})
    if expected.size() != actual.size() or staged_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "research_money_not_conserved"}
    for account in expected:
        if actual.get(account, null) != expected[account]:
            return {"ok": false, "fatal": true, "reason": "research_wallet_divergence"}
    if staged["research_receipts"].size() != _world["research_receipts"].size() + paid.size():
        return {"ok": false, "fatal": true, "reason": "research_not_once_per_shift"}
    _world = staged
    _ledger = staged_ledger
    return {"ok": true, "status": "N143_PAID_CANONICAL",
        "tick": tick, "paid": paid,
        "blocked": proposed.get("blocked", []).duplicate(true)}



## Gate4: N134 must have first authorized source N154's evaluated offer.
## The caller is the integrated head-command owner (not raw GUI input).
## Only the N39 world + existing N9 ledger + N104 Board may post paid
## construction material orders; site creation has NO free inventory.
func post_authorized_native_construction(tick: int, staged_native: Dictionary) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick:
        return {"ok": false, "reason": "not_current_live_construction_tick"}
    if staged_native.get("status") != "N154_AUTHORIZED_STAGED_NOT_APPLIED":
        return {"ok": false, "reason": "n134_authorized_n154_proposal_required"}
    if not _world.has("construction_sites") or not _world.has("faction_treasuries"):
        return {"ok": false, "reason": "legacy_construction_world_unavailable"}
    if not (staged_native.get("site") is Dictionary) or not (staged_native.get("post") is Dictionary):
        return {"ok": false, "reason": "missing_native_site_and_offer"}
    var site: Dictionary = staged_native["site"]
    var offer: Dictionary = staged_native["post"]
    var id: String = str(site.get("id", ""))
    var faction: String = str(site.get("faction_id", ""))
    var source: String = str(offer.get("source_location", ""))
    var destination: String = str(offer.get("destination_location", ""))
    var commodity: String = str(offer.get("commodity", ""))
    var quantity: int = int(offer.get("quantity", 0))
    var payer: String = Schema.faction_account(faction)
    if id.is_empty() or faction.is_empty() or source.is_empty() or destination.is_empty():
        return {"ok": false, "reason": "construction_missing_real_identity"}
    if not _world["faction_treasuries"].has(faction) or not _world["markets"].has(source) or not _world["markets"].has(destination):
        return {"ok": false, "reason": "construction_source_destination_missing"}
    if str(site.get("location_name", "")) != destination or str(site.get("commodity", "")) != commodity:
        return {"ok": false, "reason": "construction_site_material_mismatch"}
    if quantity <= 0 or quantity > 200 or str(offer.get("faction_id", "")) != faction or str(offer.get("contract_type", "")) != "construction":
        return {"ok": false, "reason": "construction_source_terms_mismatch"}
    if int(offer.get("payment", 0)) != 10000 or int(offer.get("posted_at_tick", -1)) != tick or str(offer.get("mission_category", "")) != "strategy.construction.v1":
        return {"ok": false, "reason": "construction_source_payment_mismatch"}
    if staged_native.get("effects") != {
        "faction_treasury_delta": -10000, "contract_board_reserved_delta": 10000
    } or int(staged_native.get("treasury_before", -1)) != int(_world["faction_treasuries"][faction]):
        return {"ok": false, "reason": "stale_construction_faction_treasury"}
    if _ledger.balance(payer) != int(_world["faction_treasuries"][faction]):
        return {"ok": false, "fatal": true, "reason": "construction_faction_n9_divergence"}
    if _ledger.balance(payer) < 30000 or _ledger.balance(payer) - 10000 < 5000:
        return {"ok": false, "reason": "construction_native_budget_reserve"}
    var source_market: Dictionary = _world["markets"][source]
    var dest_market: Dictionary = _world["markets"][destination]
    if not (source_market.get("supply") is Dictionary) or not _world["facilities"].has(str(dest_market.get("owner", ""))):
        return {"ok": false, "reason": "construction_not_a_real_market"}
    var dest_owner: Dictionary = _world["facilities"][str(dest_market["owner"])]
    if str(dest_owner.get("faction", "")) != faction:
        return {"ok": false, "reason": "construction_not_a_faction_station"}
    if source == destination:
        return {"ok": false, "reason": "native_construction_requires_remote_sourcing"}
    if float(source_market["supply"].get(commodity, 0.0)) < float(quantity):
        return {"ok": false, "reason": "construction_unavailable_physical_source"}
    var real_seller: Dictionary = _world["facilities"][str(source_market.get("owner", ""))] if _world["facilities"].has(str(source_market.get("owner", ""))) else {}
    if real_seller.is_empty():
        return {"ok": false, "reason": "construction_real_seller_missing"}
    var source_price: float = float(source_market.get("prices", {}).get(commodity, -1.0))
    var seller_faction: String = str(real_seller.get("faction", ""))
    if not is_finite(source_price) or source_price <= 0.0:
        return {"ok": false, "reason": "construction_source_price_unavailable"}
    # Only frozen Neutral commerce is currently authoritative; do not
    # silently open pirate-to-regular trade before native N150 diplomacy.
    if seller_faction != faction and (faction == "pirates" or seller_faction == "pirates"):
        return {"ok": false, "reason": "construction_outlaw_commerce_unintegrated"}
    var quote: Dictionary = MarketRules.posture({}, faction, seller_faction, 0)
    if not quote.get("ok", false):
        return {"ok": false, "reason": "construction_source_n97_posture_invalid"}
    var cost_float: float = ceil(float(quantity) * source_price * float(quote["multiplier"]))
    if not is_finite(cost_float) or cost_float <= 0.0 or cost_float >= 10000.0:
        return {"ok": false, "reason": "construction_source_not_profitable"}
    # No two open construction material orders at the same physical site.
    for old_cid in _world["construction_contracts"]:
        if str(_world["construction_contracts"][old_cid]) != id:
            continue
        var c: Dictionary = _world["contract_board"].get("contracts", {}).get(old_cid, {})
        if str(c.get("status", "")) in ["posted", "accepted", "picked_up", "delivered"]:
            return {"ok": false, "reason": "construction_material_order_already_open"}
    var new_site: bool = not _world["construction_sites"].has(id)
    if new_site:
        if not (staged_native.get("site_spawn") is Dictionary) or int(site.get("progress_delivered", -1)) != 0:
            return {"ok": false, "reason": "source_site_spawn_not_verified"}
        if not _world["bodies"].has(str(site.get("body_id", ""))):
            return {"ok": false, "reason": "source_construction_body_missing"}
        for sid in _world["construction_sites"]:
            var prev: Dictionary = _world["construction_sites"][sid]
            if not bool(prev.get("completed", false)) and str(prev.get("location_name", "")) == destination and str(prev.get("commodity", "")) == commodity:
                return {"ok": false, "reason": "duplicate_native_site_material"}
    else:
        if site != _world["construction_sites"][id]:
            return {"ok": false, "reason": "native_site_changed_since_offer"}
        if int(site.get("progress_required", 0)) - int(site.get("progress_delivered", 0)) < quantity:
            return {"ok": false, "reason": "native_site_material_overpromised"}
    var contract_id: String = "construction:" + id + ":" + str(tick)
    var escrow: String = "escrow:" + contract_id
    if _world["contract_board"]["contracts"].has(contract_id):
        return {"ok": false, "reason": "construction_contract_already_posted"}
    var next_money := Ledger.new()
    if not next_money.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "construction_ledger_restore_failed"}
    if not next_money.register_empty_account(escrow):
        return {"ok": false, "fatal": true, "reason": "construction_escrow_not_fresh"}
    var board := ContractBoard.new(next_money)
    if not board.restore(_world["contract_board"]):
        return {"ok": false, "fatal": true, "reason": "construction_contract_board_corrupt"}
    var expiry: int = tick + int(offer.get("lifespan_ticks", 0))
    if expiry <= tick:
        return {"ok": false, "reason": "construction_expiration_invalid"}
    # Native N104 physical delivery implementation currently handles
    # kind=delivery. Persist the N154 strategy.construction.v1 provenance
    # separately in construction_contracts, NEVER pretend construction
    # can be settled without the N15 physical pickup+unload receipts.
    var posted: Dictionary = board.post(contract_id, "delivery", payer,
        escrow, commodity, quantity, source, destination, 10000,
        tick, expiry, "faction")
    if not posted.get("ok", false):
        return posted
    var after: Dictionary = _world.duplicate(true)
    if new_site:
        after["construction_sites"][id] = site.duplicate(true)
    after["construction_contracts"][contract_id] = id
    after["faction_treasuries"][faction] = next_money.balance(payer)
    after["contract_board"] = board.snapshot()
    after["escrow_balances"][escrow] = next_money.balance(escrow)
    var receipt_id: String = "native_site_commission:" + contract_id
    after["construction_receipts"][receipt_id] = {
        "id": receipt_id, "tick": tick, "kind": "commission",
        "site_id": id, "contract_id": contract_id, "quantity": quantity,
        "n9_receipt_id": "contract:" + contract_id + ":post"}
    var reason: String = Schema.validate(after)
    if not reason.is_empty():
        return {"ok": false, "fatal": true, "reason": "construction_world_" + reason}
    var expected: Dictionary = Schema.accounts(after)
    var balances: Dictionary = next_money.snapshot()["balances"]
    if expected.size() != balances.size() or next_money.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "construction_money_not_conserved"}
    for acc in expected:
        if expected[acc] != balances.get(acc, null):
            return {"ok": false, "fatal": true, "reason": "construction_wallet_mismatch"}
    # One atomic N154/N104/N9 transaction publishes site, board and money.
    _world = after
    _ledger = next_money
    return {"ok": true, "status": "N154_REAL_FUNDED_SITE_AND_N104_DELIVERY",
        "site_id": id, "contract_id": contract_id, "tick": tick,
        "n9_receipt_id": "contract:" + contract_id + ":post",
        "payer": payer, "payment": 10000}


## P2 Gate 3: atomic N135 live need -> N104 prepaid delivery.
## EscrowStage only PROPOSES a detached N9+N104 snapshot. This method is
## the one and only authority that publishes both, plus facility balances,
## into the same N39 World in one validated swap. No second ContractBoard.
func post_funded_contract(tick: int, demand: Dictionary) -> Dictionary:
    if not _ready or tick < 0 or tick != _last_tick:
        return {"ok": false, "reason": "noncanonical_contract_tick"}
    var board_before: Dictionary = _world.get("contract_board",
        {"version": 1, "contracts": {}, "receipt_claims": {}})
    var escrows_before: Dictionary = _world.get("escrow_balances", {})
    if not (board_before.get("contracts") is Dictionary) or not (escrows_before is Dictionary):
        return {"ok": false, "fatal": true, "reason": "broken_existing_contract_authority"}
    var open_source: int = 0
    for id in board_before["contracts"]:
        var c: Dictionary = board_before["contracts"][id]
        var status: String = str(c.get("status", ""))
        # Never post the same destination/commodity demand twice while one
        # paid order is outstanding. Source inventory is not yet picked up.
        if status in ["posted", "accepted", "picked_up", "delivered"]:
            if str(c.get("destination_location", "")) == str(demand.get("location", "")) and str(c.get("commodity", "")) == str(demand.get("commodity", "")):
                return {"ok": false, "reason": "open_delivery_demand_already_funded"}
        if status in ["posted", "accepted"] and str(c.get("source_location", "")) == str(demand.get("source_location", "")) and str(c.get("commodity", "")) == str(demand.get("commodity", "")):
            open_source += int(c.get("quantity", 0))
    if not (_world.get("markets") is Dictionary) or not _world["markets"].has(str(demand.get("source_location", ""))):
        return {"ok": false, "reason": "missing_source_market"}
    var source_market: Dictionary = _world["markets"][str(demand.get("source_location", ""))]
    if not (source_market.get("supply") is Dictionary):
        return {"ok": false, "reason": "invalid_supplier_inventory"}
    var source_stock: Dictionary = source_market["supply"]
    var available: float = float(source_stock.get(str(demand.get("commodity", "")), 0.0))
    if not is_finite(available) or open_source + int(demand.get("quantity", 0)) > int(floor(available)):
        return {"ok": false, "reason": "source_stock_already_promised"}
    var previous_money: Dictionary = _ledger.snapshot()
    var proposed: Dictionary = EscrowStage.stage(_world, previous_money,
        board_before, demand, tick)
    if not proposed.get("ok", false):
        return proposed
    if proposed.get("status") != "STAGED_NOT_APPLIED":
        return {"ok": false, "fatal": true, "reason": "uncommitted_escrow_candidate"}
    var next_money: Dictionary = proposed.get("ledger_snapshot", {})
    var next_board: Dictionary = proposed.get("board_snapshot", {})
    var id: String = str(proposed.get("contract_id", ""))
    var escrow: String = str(proposed.get("escrow_account", ""))
    var buyer: String = str(demand.get("station_id", ""))
    var payer: String = Schema.facility_account(buyer)
    if id.is_empty() or escrow != "escrow:" + id or not _world["facilities"].has(buyer):
        return {"ok": false, "fatal": true, "reason": "funded_candidate_identity_mismatch"}
    if not (next_money.get("balances") is Dictionary) or not (next_board.get("contracts") is Dictionary):
        return {"ok": false, "fatal": true, "reason": "invalid_staged_money_or_contract"}
    var ledger_next := Ledger.new()
    if not ledger_next.restore(next_money) or ledger_next.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "escrow_money_not_conserved"}
    if next_money["balances"].size() != previous_money["balances"].size() + 1:
        return {"ok": false, "fatal": true, "reason": "unexpected_escrow_account_count"}
    if next_board["contracts"].size() != board_before["contracts"].size() + 1:
        return {"ok": false, "fatal": true, "reason": "unexpected_contract_count"}
    # Every previous wallet except the payer must be unchanged; the new
    # escrow is the ONLY new account. No other operation can be smuggled in.
    for account in previous_money["balances"]:
        if not next_money["balances"].has(account):
            return {"ok": false, "fatal": true, "reason": "existing_wallet_missing"}
        if str(account) != payer and next_money["balances"][account] != previous_money["balances"][account]:
            return {"ok": false, "fatal": true, "reason": "unrelated_wallet_modified"}
    if int(next_money["balances"].get(escrow, -1)) != int(demand.get("estimated_cost", -2)):
        return {"ok": false, "fatal": true, "reason": "escrow_funding_mismatch"}
    if int(next_money["balances"].get(payer, -1)) != int(previous_money["balances"].get(payer, -2)) - int(next_money["balances"][escrow]):
        return {"ok": false, "fatal": true, "reason": "payer_debit_mismatch"}
    var board_next := ContractBoard.new(ledger_next)
    if not board_next.restore(next_board):
        return {"ok": false, "fatal": true, "reason": "staged_contract_board_rejected"}
    var world_next: Dictionary = _world.duplicate(true)
    world_next["contract_board"] = next_board.duplicate(true)
    world_next["escrow_balances"] = escrows_before.duplicate(true)
    world_next["escrow_balances"][escrow] = int(next_money["balances"][escrow])
    world_next["facilities"][buyer]["credits"] = int(next_money["balances"][payer])
    var world_error: String = Schema.validate(world_next)
    if not world_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "funded_world_" + world_error}
    var account_rows: Dictionary = Schema.accounts(world_next)
    if account_rows.size() != next_money["balances"].size():
        return {"ok": false, "fatal": true, "reason": "unexpected_contract_wallets"}
    for account in account_rows:
        if next_money["balances"].get(account, null) != account_rows[account]:
            return {"ok": false, "fatal": true, "reason": "contract_ledger_world_diverged"}
    # The COMMIT POINT: neither the economic World nor N9 can be published
    # unless the other is ready and all original balances are conserved.
    _world = world_next
    _ledger = ledger_next
    return {"ok": true, "status": "POSTED_FUNDED", "tick": tick,
        "contract_id": id, "escrow_account": escrow,
        "payment": int(next_money["balances"][escrow]),
        "receipt_id": str(proposed["receipt_id"])}


## N152 canonical close/refund. This is the ONLY live owner of N104
## posted expiry and PAID/EXPIRED N9 residual escrow returns. Old history,
## N15 receipts and N121 dispatch keys remain stored for reconciliation.
## A detached quote is published ONLY if every wallet, Board and World
## invariant succeeds together; no second ledger and no magic refund.
func apply_native_n152_contract_lifecycle(tick: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick:
        return {"ok": false, "reason": "n152_not_the_canonical_post_facility_tick"}
    if not _world.has("contract_board") and not _world.has("escrow_balances"):
        return {"ok": true, "tick": tick, "expired": [], "renewed": [], "refunded": [],
            "blocked": [], "status": "LEGACY_NO_CONTRACT_BOARD"}
    if not _world.has("contract_board") or not _world.has("escrow_balances"):
        return {"ok": false, "fatal": true, "reason": "n152_partial_contract_authority"}
    var old_bank: Dictionary = _ledger.snapshot()
    var proposal: Dictionary = NativeN152.stage(_world, old_bank, tick)
    if not proposal.get("ok", false):
        return {"ok": false, "fatal": true, "reason": "n152_" + str(proposal.get("reason", "stage_rejected"))}
    if not bool(proposal.get("changed", false)):
        return {"ok": true, "tick": tick, "expired": [], "renewed": [],
            "refunded": [], "blocked": proposal.get("blocked", []).duplicate(true),
            "status": "NO_DUE_CONTRACT_CLOSURES"}
    var next_board: Dictionary = proposal["board_snapshot"]
    var next_bank: Dictionary = proposal["ledger_snapshot"]
    var old_board: Dictionary = _world["contract_board"]
    if next_board.get("version") != old_board.get("version") or next_board.get("receipt_claims") != old_board.get("receipt_claims"):
        return {"ok": false, "fatal": true, "reason": "n152_board_history_or_receipts_mutated"}
    if next_board.get("contracts", {}).size() != old_board.get("contracts", {}).size():
        return {"ok": false, "fatal": true, "reason": "n152_deleted_historical_contract"}
    var expirations: Dictionary = {}
    for expired_id in proposal["expired"]:
        if expirations.has(expired_id):
            return {"ok": false, "fatal": true, "reason": "n152_duplicate_expiry"}
        expirations[expired_id] = true
    var renewals: Dictionary = {}
    for renewal in proposal.get("renewed", []):
        var renewal_id: String = str(renewal.get("id", ""))
        if renewal_id.is_empty() or renewals.has(renewal_id) or not old_board["contracts"].has(renewal_id):
            return {"ok": false, "fatal": true, "reason": "n152_invalid_source_renewal_id"}
        renewals[renewal_id] = true
    var authorized_accounts: Dictionary = {}
    var refunded_ids: Dictionary = {}
    var expected_money_receipts: Dictionary = {}
    for refunded in proposal["refunded"]:
        var id: String = str(refunded.get("contract_id", ""))
        var payer: String = str(refunded.get("payer", ""))
        var escrow: String = str(refunded.get("escrow", ""))
        var amount: int = int(refunded.get("amount", 0))
        var receipt_id: String = "contract:" + id + ":refund"
        if refunded_ids.has(id) or amount <= 0 or receipt_id != str(refunded.get("receipt_id", "")):
            return {"ok": false, "fatal": true, "reason": "n152_invalid_duplicate_refund"}
        if escrow != "escrow:" + id or not old_board["contracts"].has(id):
            return {"ok": false, "fatal": true, "reason": "n152_refund_orphaned_escrow"}
        var before_contract: Dictionary = old_board["contracts"][id]
        if str(before_contract.get("requestor_id", "")) != payer or int(before_contract.get("reserved", -1)) != amount:
            return {"ok": false, "fatal": true, "reason": "n152_refund_payer_or_reserve_mismatch"}
        if str(before_contract.get("status", "")) not in ["paid", "expired", "posted"] or (str(before_contract.get("status", "")) == "posted" and not expirations.has(id)):
            return {"ok": false, "fatal": true, "reason": "n152_refunded_active_delivery"}
        if old_bank.get("balances", {}).get(escrow, null) != amount:
            return {"ok": false, "fatal": true, "reason": "n152_refund_escrow_not_funded"}
        var receipt: Dictionary = next_bank.get("receipts", {}).get(receipt_id, {})
        var expected_legs: Array = [
            {"account": escrow, "delta": -amount},
            {"account": payer, "delta": amount}]
        if receipt.get("id") != receipt_id or receipt.get("kind") != "contract_refund" or receipt.get("tick") != tick or receipt.get("legs") != expected_legs:
            return {"ok": false, "fatal": true, "reason": "n152_unverified_real_n9_refund"}
        authorized_accounts[escrow] = true
        authorized_accounts[payer] = true
        refunded_ids[id] = true
        expected_money_receipts[receipt_id] = true
    if old_board["contracts"].keys().size() != next_board["contracts"].keys().size():
        return {"ok": false, "fatal": true, "reason": "n152_contract_identity_changed"}
    for id in old_board["contracts"]:
        if not next_board["contracts"].has(id):
            return {"ok": false, "fatal": true, "reason": "n152_missing_original_contract"}
        var old_contract: Dictionary = old_board["contracts"][id]
        var new_contract: Dictionary = next_board["contracts"][id]
        var allowed: Dictionary = old_contract.duplicate(true)
        # Frozen N145 changes only these OFFER terms for Posted records.
        # Do not admit an aged contract with arbitrary cargo, ship,
        # funding, destination or physical receipt mutations.
        if str(old_contract.get("status", "")) == "posted":
            for aged_field in ["payment", "min_reputation"]:
                if new_contract.has(aged_field):
                    allowed[aged_field] = new_contract[aged_field]
            if renewals.has(id):
                var old_count: int = int(old_contract.get("renewal_count", 0))
                var new_count: int = int(new_contract.get("renewal_count", -1))
                if new_count != old_count + 1 or new_count > 3 or str(new_contract.get("status", "")) != "posted" or int(new_contract.get("expires_at_tick", -1)) <= tick:
                    return {"ok": false, "fatal": true, "reason": "n152_invalid_source_renewal"}
                allowed["expires_at_tick"] = new_contract["expires_at_tick"]
                allowed["renewal_count"] = new_contract["renewal_count"]
        if expirations.has(id):
            if str(old_contract.get("status", "")) != "posted" or str(new_contract.get("status", "")) != "expired" or tick < int(old_contract.get("expires_at_tick", 9223372036854775807)):
                return {"ok": false, "fatal": true, "reason": "n152_invalid_posted_expiry"}
            allowed["status"] = "expired"
        if refunded_ids.has(id):
            if int(new_contract.get("reserved", -1)) != 0:
                return {"ok": false, "fatal": true, "reason": "n152_unclosed_funded_contract"}
            allowed["reserved"] = 0
        if allowed != new_contract:
            return {"ok": false, "fatal": true, "reason": "n152_mutated_unrelated_contract_terms"}
    if old_bank.get("balances", {}).size() != next_bank.get("balances", {}).size() or next_bank.get("receipts", {}).size() != old_bank.get("receipts", {}).size() + expected_money_receipts.size():
        return {"ok": false, "fatal": true, "reason": "n152_changed_ledger_account_or_receipt_count"}
    for receipt_id in old_bank["receipts"]:
        if next_bank["receipts"].get(receipt_id, null) != old_bank["receipts"][receipt_id]:
            return {"ok": false, "fatal": true, "reason": "n152_changed_existing_money_receipt"}
    for receipt_id in next_bank["receipts"]:
        if not old_bank["receipts"].has(receipt_id) and not expected_money_receipts.has(receipt_id):
            return {"ok": false, "fatal": true, "reason": "n152_unexpected_money_receipt"}
    for account in old_bank["balances"]:
        if not next_bank["balances"].has(account):
            return {"ok": false, "fatal": true, "reason": "n152_lost_account"}
        if next_bank["balances"][account] != old_bank["balances"][account] and not authorized_accounts.has(account):
            return {"ok": false, "fatal": true, "reason": "n152_modified_unrelated_wallet"}
    var ledger_next := Ledger.new()
    if not ledger_next.restore(next_bank) or ledger_next.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n152_money_not_conserved"}
    var board_next := ContractBoard.new(ledger_next)
    if not board_next.restore(next_board):
        return {"ok": false, "fatal": true, "reason": "n152_board_restore_rejected"}
    var staged: Dictionary = _world.duplicate(true)
    staged["contract_board"] = next_board.duplicate(true)
    for item in proposal["refunded"]:
        var id: String = str(item["contract_id"])
        var escrow: String = str(item["escrow"])
        var payer: String = str(item["payer"])
        staged["escrow_balances"][escrow] = ledger_next.balance(escrow)
        var payer_balance: int = ledger_next.balance(payer)
        if payer.begins_with("facility/"):
            var facility_id: String = payer.substr(9)
            if not staged["facilities"].has(facility_id):
                return {"ok": false, "fatal": true, "reason": "n152_refund_missing_facility"}
            staged["facilities"][facility_id]["credits"] = payer_balance
        elif payer.begins_with("population/"):
            var population_id: String = payer.substr(11)
            if not staged["populations"].has(population_id):
                return {"ok": false, "fatal": true, "reason": "n152_refund_missing_household"}
            staged["populations"][population_id]["wealth"] = payer_balance
        elif payer.begins_with("faction/"):
            var faction_id: String = payer.substr(8)
            if not staged.get("faction_treasuries", {}).has(faction_id):
                return {"ok": false, "fatal": true, "reason": "n152_refund_missing_treasury"}
            staged["faction_treasuries"][faction_id] = payer_balance
        else:
            return {"ok": false, "fatal": true, "reason": "n152_refund_noncanonical_beneficiary"}
    var valid: String = Schema.validate(staged)
    if not valid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n152_invalid_world_" + valid}
    var expected: Dictionary = Schema.accounts(staged)
    if expected.size() != next_bank["balances"].size():
        return {"ok": false, "fatal": true, "reason": "n152_wallet_cardinality_mismatch"}
    for account in expected:
        if next_bank["balances"].get(account, null) != expected[account]:
            return {"ok": false, "fatal": true, "reason": "n152_ledger_world_balance_divergence"}
    _world = staged
    _ledger = ledger_next
    return {"ok": true, "tick": tick, "status": "N152_CLOSED_WITH_REAL_N9_RECEIPTS",
        "expired": proposal["expired"].duplicate(true),
        "renewed": proposal.get("renewed", []).duplicate(true),
        "refunded": proposal["refunded"].duplicate(true),
        "blocked": proposal.get("blocked", []).duplicate(true)}


## N153 accepted assignment COMMIT: same N104 Board, N9 Ledger and N39
## authoritative ship row. The source selector is read-only; this method
## checks its financial/physical assumptions AGAIN before publication.
## Pickup, trade and payment remain other explicit native phases.
func accept_autonomous_delivery(tick: int, proposal: Dictionary, source_factions: Dictionary = {}) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1:
        return {"ok": false, "reason": "invalid_autonomous_accept_tick"}
    var cid: String = str(proposal.get("contract_id", ""))
    var sid: String = str(proposal.get("ship_id", ""))
    if cid.is_empty() or sid.is_empty() or not (_world.get("ships") is Dictionary):
        return {"ok": false, "reason": "invalid_autonomous_assignment"}
    if not (_world.get("contract_board") is Dictionary):
        return {"ok": false, "reason": "missing_live_contract_board"}
    var board_before: Dictionary = _world["contract_board"]
    if not (board_before.get("contracts") is Dictionary) or not board_before["contracts"].has(cid) or not _world["ships"].has(sid):
        return {"ok": false, "reason": "missing_real_offer_or_ship"}
    var c: Dictionary = board_before["contracts"][cid]
    var ship: Dictionary = _world["ships"][sid]
    if str(c.get("contract_type", "")) != "delivery" or str(c.get("status", "")) != "posted" or tick > int(c.get("expires_at_tick", -1)):
        return {"ok": false, "reason": "offer_no_longer_posted"}
    if not str(ship.get("active_contract_id", "")).is_empty() or not (ship.get("transit", {}) as Dictionary).is_empty():
        return {"ok": false, "reason": "ship_not_idle"}
    if not (proposal.get("ai_bt") is Dictionary) or not NativeBt.validate(proposal["ai_bt"]):
        return {"ok": false, "reason": "n84_unplanned_ship_assignment"}
    if str(ship.get("location", "")).is_empty():
        return {"ok": false, "reason": "ship_not_at_source_location"}
    var dock_id: String = str(ship.get("docked_at", ""))
    if not dock_id.is_empty() and (not _world["facilities"].has(dock_id) or str(_world["facilities"][dock_id].get("location", "")) != str(ship["location"])):
        return {"ok": false, "reason": "invalid_existing_n21_dock"}
    if not (ship.get("cargo") is Dictionary) or not ship["cargo"].is_empty():
        return {"ok": false, "reason": "ship_hold_not_empty"}
    var qty: int = int(c.get("quantity", 0))
    if qty <= 0 or qty > int(ship.get("cargo_capacity", 0)):
        return {"ok": false, "reason": "insufficient_ship_capacity"}
    var src: String = str(c.get("source_location", ""))
    var dst: String = str(c.get("destination_location", ""))
    if not _world["markets"].has(src) or not _world["markets"].has(dst):
        return {"ok": false, "reason": "market_missing"}
    var source_market: Dictionary = _world["markets"][src]
    var buyer_market: Dictionary = _world["markets"][dst]
    if not _world["facilities"].has(str(source_market.get("owner", ""))) or not _world["facilities"].has(str(buyer_market.get("owner", ""))):
        return {"ok": false, "reason": "market_owner_missing"}
    var seller: Dictionary = _world["facilities"][str(source_market["owner"])]
    var buyer: Dictionary = _world["facilities"][str(buyer_market["owner"])]
    var faction: String = str(ship.get("faction_id", ""))
    var buyer_faction: String = str(buyer.get("faction", ""))
    var seller_faction: String = str(seller.get("faction", ""))
    if not source_factions.has(faction) or not source_factions.has(buyer_faction) or not source_factions.has(seller_faction):
        return {"ok": false, "reason": "faction_source_missing"}
    if (str(source_factions[faction].get("type", "")) == "outlaw" or str(source_factions[buyer_faction].get("type", "")) == "outlaw" or str(source_factions[seller_faction].get("type", "")) == "outlaw") and not (faction == buyer_faction and faction == seller_faction):
        return {"ok": false, "reason": "unintegrated_outlaw_trade"}
    # Default Neutral commerce is original FactionRelations::state_or_default.
    # ContractBoard.post(kind=delivery, funding_source=facility) is public.
    # Active War/Hostile transitions must be integrated before diplomacy runs.
    var good: String = str(c.get("commodity", ""))
    if not (source_market.get("supply") is Dictionary) or not (source_market.get("prices") is Dictionary):
        return {"ok": false, "reason": "invalid_source_stock"}
    var stock: float = float(source_market["supply"].get(good, 0.0))
    var price: float = float(source_market["prices"].get(good, 0.0))
    if not is_finite(stock) or stock < float(qty) or not is_finite(price) or price <= 0.0:
        return {"ok": false, "reason": "source_stock_or_price_changed"}
    var reputation: Dictionary = ship.get("faction_reputation", {})
    var posture: Dictionary = MarketRules.posture({}, faction,
        str(seller.get("faction", "")), int(reputation.get(str(seller.get("faction", "")), 0)))
    if not posture.get("ok", false):
        return {"ok": false, "reason": "missing_rust_n97_market_posture"}
    var raw_purchase: float = ceil(float(qty) * price * float(posture["multiplier"]))
    if not is_finite(raw_purchase) or raw_purchase <= 0.0 or raw_purchase > 9007199254740991.0:
        return {"ok": false, "reason": "n97_purchase_quote_overflow"}
    var cost: int = int(raw_purchase)
    var payment: int = int(c.get("payment", 0))
    if cost <= 0 or cost >= payment or cost > int(ship.get("credits", 0)):
        return {"ok": false, "reason": "not_profitable_or_unfunded"}
    if int(proposal.get("source_purchase_cost", -1)) != cost:
        return {"ok": false, "reason": "stale_ship_purchase_quote"}
    var staged_ledger := Ledger.new()
    if not staged_ledger.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "canonical_ledger_corrupt"}
    var board := ContractBoard.new(staged_ledger)
    if not board.restore(board_before):
        return {"ok": false, "fatal": true, "reason": "canonical_board_corrupt"}
    # Frozen Rust CATALOG: comms_t2 = +5% on acceptance. Treaty defaults
    # Neutral => x1, so the buyer must fund the REAL N104 escrow top-up.
    var comms_bonus: float = float(ship.get("comms_bonus", 0.0))
    if not is_finite(comms_bonus) or comms_bonus < 0.0 or comms_bonus > 0.10:
        return {"ok": false, "reason": "invalid_native_ship_comms"}
    var accepted: Dictionary = board.accept(cid, sid, faction, comms_bonus, 1.0, tick)
    if not accepted.get("ok", false):
        return accepted
    var top_up: int = int(accepted.get("top_up", -1))
    if top_up < 0:
        return {"ok": false, "fatal": true, "reason": "invalid_native_accept_topup"}
    var after_money: Dictionary = staged_ledger.snapshot()
    var original_money: Dictionary = _ledger.snapshot()
    if staged_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n104_accept_money_not_conserved"}
    var payer: String = str(c.get("requestor_id", ""))
    var escrow: String = str(c.get("escrow_account", ""))
    var native_site_contract: bool = (_world.get(
        "construction_contracts", {}).has(cid) or _world.get(
        "native_htn_contracts", {}).has(cid))
    var expected_payer: String = Schema.faction_account(buyer_faction) if native_site_contract else Schema.facility_account(str(buyer_market["owner"]))
    if payer != expected_payer or (native_site_contract and str(c.get("funding_source", "")) != "faction") or (not native_site_contract and str(c.get("funding_source", "")) != "facility"):
        return {"ok": false, "fatal": true, "reason": "n104_payer_changed"}
    for account in original_money["balances"]:
        if not after_money["balances"].has(account):
            return {"ok": false, "fatal": true, "reason": "n104_missing_account"}
        var before_balance: int = int(original_money["balances"][account])
        var expected_balance: int = before_balance - top_up if str(account) == payer else (before_balance + top_up if str(account) == escrow else before_balance)
        if int(after_money["balances"][account]) != expected_balance:
            return {"ok": false, "fatal": true, "reason": "n104_unrelated_balance_changed"}
    var staged: Dictionary = _world.duplicate(true)
    staged["contract_board"] = board.snapshot()
    staged["escrow_balances"][escrow] = staged_ledger.balance(escrow)
    if native_site_contract:
        staged["faction_treasuries"][buyer_faction] = staged_ledger.balance(payer)
    else:
        staged["facilities"][str(buyer_market["owner"])]["credits"] = staged_ledger.balance(payer)
    staged["ships"][sid]["active_contract_id"] = cid
    staged["ships"][sid]["current_goal"] = "fulfill_delivery"
    staged["ships"][sid]["last_plan_tick"] = tick
    staged["ships"][sid]["current_bt"] = proposal["ai_bt"].duplicate(true)
    # N97 Buy accepts at most the N153 priced amount. A future market
    # repricing cannot make the captain silently buy at a worse quote.
    staged["ships"][sid]["max_source_cost"] = int(proposal.get("source_purchase_cost", 0))
    staged["ships"][sid]["current_goal_score"] = float(proposal.get("n80_score", 0.0))
    staged["ships"][sid]["planning_source"] = str(proposal.get("personality_source", ""))
    # Only the source N104 Comms payout top-up moves credits here; never
    # any physical goods. N9 + N104 + facility balance still match.
    var err: String = Schema.validate(staged)
    if not err.is_empty():
        return {"ok": false, "fatal": true, "reason": "assignment_schema_" + err}
    var accounts: Dictionary = Schema.accounts(staged)
    for account in accounts:
        if staged_ledger.balance(str(account)) != int(accounts[account]):
            return {"ok": false, "fatal": true, "reason": "assignment_account_divergence"}
    _world = staged
    _ledger = staged_ledger
    return {"ok": true, "status": "N153_ACCEPTED_AWAITING_PICKUP",
        "contract_id": cid, "ship_id": sid, "tick": tick,
        "source": src, "destination": dst,
        "top_up": top_up, "agreed_payment": int(accepted["agreed_payment"])}

## P2 single-market commit boundary: N150 may change price, demand,
## flow/history/orders but NEVER physical stock, source owner or accounts.
## Validation of all markets precedes one atomic in-memory swap.
## Native Phase 19d: ONE abstract population movement on its true
## 200*mult cadence. N147 interplanetary passenger missions are unrelated.
## No new households, ships, contracts, or credits can be fabricated here.
## N39 recomputes N151 from its current World; N9 transfers real household
## wealth in the SAME validated commit, with N38 persistent receipt.
func apply_native_population_migration(tick: int, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or multiplier < 1 or multiplier > 10000:
        return {"ok": false, "reason": "n151_noncanonical_migration_tick"}
    if tick % (200 * multiplier) != 0:
        return {"ok": false, "reason": "n151_migration_interval_not_due"}
    var old_event: Dictionary = _world.get("population_migration_last", {})
    if int(old_event.get("tick", -1)) == tick:
        return {"ok": false, "reason": "n151_duplicate_migration_tick"}
    var candidate: Dictionary = NativePopulation.migration_proposal(
        _world, tick, multiplier)
    if not candidate.get("ok", false):
        return {"ok": false, "fatal": true,
            "reason": str(candidate.get("reason", "n151_migration_projection_failed"))}
    if not candidate.get("due", false):
        return {"ok": false, "fatal": true, "reason": "n151_interval_proposal_mismatch"}
    var moved: int = int(candidate.get("moved", -1))
    if moved == 0:
        return {"ok": true, "tick": tick, "moved": 0, "events": []}
    if moved < 0 or moved > 100 or not (candidate.get("after") is Array):
        return {"ok": false, "fatal": true, "reason": "n151_invalid_population_migration"}
    var from: String = str(candidate.get("from", ""))
    var to: String = str(candidate.get("to", ""))
    var amount: int = int(candidate.get("wealth", -1))
    if amount < 0 or from.is_empty() or to.is_empty() or from == to or not _world["populations"].has(from) or not _world["populations"].has(to):
        return {"ok": false, "fatal": true, "reason": "n151_invalid_migrant_economy"}
    var next_world: Dictionary = _world.duplicate(true)
    var next_ledger = Ledger.new()
    var before_money: Dictionary = _ledger.snapshot()
    if not next_ledger.restore(before_money):
        return {"ok": false, "fatal": true, "reason": "n151_canonical_ledger_copy_failed"}
    var op: String = ""
    if amount > 0:
        op = "n151/migration/%d/%s/%s" % [tick, from, to]
        var transferred: Dictionary = next_ledger.transfer(op,
            Schema.household_account(from), Schema.household_account(to),
            amount, tick, "native_population_migration")
        if not transferred.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": "n151_household_wealth_transfer_" + str(transferred.get("reason", "rejected"))}
    var before_src: Dictionary = _world["populations"][from]
    var before_dst: Dictionary = _world["populations"][to]
    var after_rows: Dictionary = {}
    for row in candidate["after"]:
        if not (row is Dictionary):
            return {"ok": false, "fatal": true, "reason": "n151_invalid_population_after_row"}
        var id: String = str(row.get("id", ""))
        if not _world["populations"].has(id) or after_rows.has(id):
            return {"ok": false, "fatal": true, "reason": "n151_untrusted_population_after"}
        after_rows[id] = row
    if after_rows.size() != _world["populations"].size():
        return {"ok": false, "fatal": true, "reason": "n151_population_identity_changed"}
    for id in after_rows:
        var next_row: Dictionary = after_rows[id]
        var actual: Dictionary = _world["populations"][id]
        var new_count: int = int(next_row.get("population_count", -1))
        var new_wealth: int = int(next_row.get("total_wealth", -1))
        if str(next_row.get("facility_location", "")) != str(actual.get("location", "")) or new_count < 0 or new_wealth < 0:
            return {"ok": false, "fatal": true, "reason": "n151_population_location_or_balance_mismatch"}
        if id not in [from, to] and (new_count != int(actual["count"]) or new_wealth != int(actual["wealth"])):
            return {"ok": false, "fatal": true, "reason": "n151_unrelated_population_changed"}
        if id in [from, to]:
            if next_ledger.balance(Schema.household_account(str(id))) != new_wealth:
                return {"ok": false, "fatal": true, "reason": "n151_migration_receipt_balance_mismatch"}
            next_world["populations"][id]["count"] = new_count
            next_world["populations"][id]["wealth"] = new_wealth
            next_world["populations"][id]["migration_pressure"] = float(next_row.get("migration_pressure", 0.0))
            next_world["populations"][id]["sentiment_dirty"] = true
    if int(next_world["populations"][from]["count"]) != int(before_src["count"]) - moved or int(next_world["populations"][to]["count"]) != int(before_dst["count"]) + moved or int(next_world["populations"][from]["wealth"]) != int(before_src["wealth"]) - amount or int(next_world["populations"][to]["wealth"]) != int(before_dst["wealth"]) + amount:
        return {"ok": false, "fatal": true, "reason": "n151_migration_conservation_mismatch"}
    var event: Dictionary = candidate.get("event", {}).duplicate(true)
    event["tick"] = tick
    event["wealth_transferred"] = amount
    event["receipt_id"] = op
    next_world["population_migration_last"] = event.duplicate(true)
    var schema_error: String = Schema.validate(next_world)
    if not schema_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n151_invalid_committed_world_" + schema_error}
    if next_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n151_unbalanced_migration_money"}
    var accounts: Dictionary = Schema.accounts(next_world)
    if accounts.size() != next_ledger.snapshot()["balances"].size():
        return {"ok": false, "fatal": true, "reason": "n151_new_or_missing_migration_accounts"}
    for account in accounts:
        if int(accounts[account]) != next_ledger.balance(str(account)):
            return {"ok": false, "fatal": true, "reason": "n151_migration_ledger_world_divergence"}
    _world = next_world
    _ledger = next_ledger
    return {"ok": true, "tick": tick, "moved": moved, "wealth": amount,
        "receipt_id": op, "events": [event]}


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

## Native facility/mod.rs: produce exactly one N132 T2/T3 module per
## real shipyard per 15×mult cycle. Same physical markets, shifts, and N9.
## There are NO shipyards in the clean frozen 0.6.7 starting seed;
## this activates once an actually funded N154 shipyard exists.
func _run_shipyard_modules(tick: int, multiplier: int,
        external_workers: Dictionary) -> Dictionary:
    var paid_modules: Array = []
    var blocked: Array = []
    if tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "invalid_native_shipyard_clock"}
    if tick % (NativeShipyardModules.INTERVAL_BASE * multiplier) != 0:
        return {"ok": true, "paid": paid_modules, "blocked": blocked}
    var base_prices: Dictionary = {}
    for commodity in CommodityCatalog.ORDER:
        base_prices[commodity] = CommodityCatalog.base_price(str(commodity))
    var ids: Array = _world["facilities"].keys()
    ids.sort()
    for id in ids:
        var fac: Dictionary = _world["facilities"][id]
        if str(fac.get("type", "")) != "shipyard" or bool(fac.get("abandoned", false)):
            continue
        var location: String = str(fac.get("location", ""))
        if not _world["markets"].has(location):
            blocked.append({"facility": str(id), "reason": "no_actual_local_market"})
            continue
        var warehouse: Dictionary = _world["markets"][location]
        var owner: String = str(warehouse.get("owner", ""))
        if not _world["facilities"].has(owner):
            return {"ok": false, "reason": "native_shipyard_market_owner_missing"}
        var yard: Dictionary = {"id": str(id),
            "facility_type": str(fac["type"]),
            "location_name": location,
            "abandoned": bool(fac["abandoned"]),
            "module_stock": fac.get("module_stock",
                {"stock": {}, "dirty": false}).duplicate(true)}
        var local_market: Dictionary = {
            "id": str(warehouse["id"]),
            "facility_location": location, "owner_facility_id": owner,
            "supply": warehouse["supply"].duplicate(true),
            "prices": warehouse["prices"].duplicate(true)}
        var candidate: Dictionary = NativeShipyardModules.plan_one(
            yard, local_market, NativeModuleRecipes.RECIPES,
            tick, multiplier, base_prices)
        if not candidate.get("ok", false):
            return {"ok": false, "reason": "n154_source_plan:" +
                str(candidate.get("reason", "invalid_module"))}
        if candidate.get("plan", null) == null:
            continue
        var plan: Dictionary = candidate["plan"]
        # The source checks stock and input prices BEFORE paying workers.
        # Never deduct goods or award a module on an unfunded wage shift.
        var staged: Dictionary = _world.duplicate(true)
        var ledger_copy = Ledger.new()
        if not ledger_copy.restore(_ledger.snapshot()):
            return {"ok": false, "reason": "n154_canonical_ledger_clone_failed"}
        var shift: Dictionary = Payroll.pay_shift(staged, ledger_copy,
            str(id), owner, tick, external_workers,
            int(plan["input_payment"]))
        if not shift.get("ok", false):
            blocked.append({"facility": str(id),
                "reason": str(shift.get("reason", "unpaid_module_shift"))})
            continue
        var acknowledged: Dictionary = {
            "trusted_internal_apply": true,
            "paid_shift_committed": ledger_copy.has_receipt(
                str(shift.get("receipt", ""))),
            "producer_id": str(id), "stock_owner_id": owner,
            "tick": tick, "wages": int(shift["wages"]),
            "input_payment": int(shift.get("input_payment", 0))}
        var manufactured: Dictionary = NativeShipyardModules.after_paid_shift(
            plan, yard, local_market, acknowledged)
        if not manufactured.get("ok", false):
            return {"ok": false, "reason": "n154_paid_module_stage_failed:" +
                str(manufactured.get("reason", "unknown"))}
        staged["facilities"][id]["module_stock"] = (
            manufactured["yard"]["module_stock"] as Dictionary).duplicate(true)
        staged["markets"][location]["supply"] = (
            manufactured["market"]["supply"] as Dictionary).duplicate(true)
        if staged["markets"][location].get("history") is Dictionary:
            staged["markets"][location]["history"]["dirty"] = true
        var error: String = Schema.validate(staged)
        if not error.is_empty():
            return {"ok": false, "reason": "n154_paid_module_invalid_world:" + error}
        var accounts: Dictionary = Schema.accounts(staged)
        var balances: Dictionary = ledger_copy.snapshot().get("balances", {})
        if balances.size() != accounts.size() or ledger_copy.total() != _ledger.total():
            return {"ok": false, "reason": "n154_module_wages_destroyed_money"}
        for account in accounts:
            if balances.get(account, null) != accounts[account]:
                return {"ok": false, "reason": "n154_module_ledger_mismatch"}
        # Commit once only after the real wages/inputs/stock all agree.
        _world = staged
        _ledger = ledger_copy
        paid_modules.append({
            "kind": "shipyard_module",
            "facility": str(id), "tick": tick,
            "module": str(plan["module_slug"]),
            "inputs": plan["inputs"].duplicate(true),
            "wages": int(shift["wages"]),
            "receipt": str(shift["receipt"]),
            "input_payment": int(shift.get("input_payment", 0))})
    return {"ok": true, "paid": paid_modules, "blocked": blocked}


## N121 is the ONLY source-authorized executor of opt-in N100/N98
## plans. This function re-checks source N121 preflight against current N39
## and posts to the EXISTING N104 board using its ONE N9 ledger.
## No second ContractBoard/treasury, no invented cargo or paid receipt.
func apply_native_n121_execution(tick: int, faction: String,
        multiplier: int, graph: RefCounted) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or multiplier < 1:
        return {"ok": false, "reason": "n121_not_current_faction_tick"}
    var mode: String = str(_world.get("native_planner_mode", "legacy"))
    if mode == "legacy":
        return {"ok": true, "due": false, "status": "source_legacy_director"}
    if not _world.has("native_execution") or not _world.has("native_planner_records"):
        return {"ok": false, "reason": "n121_missing_canonical_execution_state"}
    var record: Dictionary = _world["native_planner_records"].get(faction, {})
    var state: Dictionary = _world["native_execution"]
    if not N121State.validate(state):
        return {"ok": false, "fatal": true, "reason": "n121_invalid_source_execution_memory"}
    if record.is_empty() and not state["active"].has(faction):
        return {"ok": true, "due": false, "status": "no_source_head_plan"}
    if record.is_empty():
        return {"ok": false, "fatal": true, "reason": "n121_orphaned_active_plan"}
    var pending: Dictionary = state["active"].get(faction, {})
    if pending.is_empty():
        if str(record.get("status", "")) != "n98_planned_not_dispatched":
            return {"ok": true, "due": false,
                "status": str(record.get("status", "no_native_plan"))}
        pending = {"ledger": record.get("ledger", {}).duplicate(true),
            "goal": record.get("goal", {}).duplicate(true),
            "actions": record.get("actions", []).duplicate(true),
            "production_goal": bool(record.get("production_goal", false)),
            "production_target_delta": int(record.get("production_target_delta", 0)),
            "production_baselines": record.get("production_baselines", {}).duplicate(true),
            "production_accounted": {}, "production_started_tick": null,
            "last_reason": "source_n100_admitted",
            "planner_rationale": str(record.get("reason", ""))}
    if not (pending.get("ledger") is Dictionary):
        return {"ok": false, "fatal": true, "reason": "n121_pending_without_n98_ledger"}
    if str(pending["ledger"].get("faction_id", "")) != faction:
        return {"ok": false, "fatal": true, "reason": "n121_mismatched_planner_faction"}
    var gate: Dictionary = NativeN98.next_gate(pending["ledger"])
    var kind: String = str(gate.get("kind", ""))
    var ledger_next = Ledger.new()
    if not ledger_next.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "n121_canonical_bank_missing"}
    var staged: Dictionary = _world.duplicate(true)
    var next_state: Dictionary = state.duplicate(true)
    var event: Dictionary = {"ok": true, "due": true, "tick": tick,
        "faction_id": faction, "kind": kind, "status": "awaiting_source_step",
        "committed_credits": 0}
    match kind:
        "ready":
            var chosen: Dictionary = NativeN121.action_for_step(pending, gate)
            if not chosen.get("ok", false):
                return {"ok": false, "reason": "n121_source_action_missing"}
            var action: Dictionary = chosen["action"]
            var step_id: String = str(gate.get("step_id", ""))
            var dispatch_key: String = str(gate.get("dispatch_key", ""))
            if str(action.get("kind", "")) == "deliver":
                var priced: Dictionary = NativeN121.paid_delivery_quote(
                    _world, faction, action, dispatch_key, tick, multiplier, graph)
                if not priced.get("ok", false):
                    # Original native_execution.rs: a failed paid source
                    # preflight RELEASES the old attempt and retains only
                    # its goal with bounded cooldown. Never resubmit its
                    # old dispatch_key/quote on the next strategic tick.
                    var failed_reason: String = str(priced.get(
                        "reason", "source_preflight_failed"))
                    var ended: Dictionary = N121State.record_terminal(
                        next_state, faction, pending, "blocked",
                        failed_reason, tick, multiplier, null)
                    if not ended.get("ok", false):
                        return {"ok": false, "fatal": true,
                            "reason": "n121_unfunded_terminal_state_rejected"}
                    staged["native_execution"] = ended["state"].duplicate(true)
                    staged["native_planner_records"][faction]["status"] = "n121_closed_blocked"
                    staged["native_planner_records"][faction]["last_source_execution_tick"] = tick
                    staged["native_planner_records"][faction]["last_source_execution_kind"] = "blocked"
                    var invalid_block: String = Schema.validate(staged)
                    if not invalid_block.is_empty() or Schema.accounts(staged) != Schema.accounts(_world):
                        return {"ok": false, "fatal": true,
                            "reason": "n121_blocked_source_state_modified_world"}
                    _world = staged
                    event["status"] = "native_source_delivery_blocked"
                    event["reason"] = failed_reason
                    return event
                if int(staged.get("native_htn_next_id", 0)) < 1:
                    return {"ok": false, "fatal": true,
                        "reason": "n121_missing_original_order_serial"}
                var order_id: String = "n121-" + str(staged["native_htn_next_id"])
                var escrow: String = "escrow:" + order_id
                if staged.get("contract_board", {}).get("contracts", {}).has(order_id):
                    return {"ok": false, "fatal": true,
                        "reason": "n121_canonical_contract_id_reused"}
                var source_quote: Dictionary = priced["quote"]
                var reward: int = int(source_quote["reward"])
                var payer: String = Schema.faction_account(faction)
                var balance: int = int(staged["faction_treasuries"].get(faction, -1))
                if balance < reward or balance - reward < 5000:
                    return {"ok": false, "reason": "n121_original_faction_reserve"}
                if not ledger_next.register_empty_account(escrow):
                    return {"ok": false, "fatal": true, "reason": "n121_duplicate_escrow"}
                var board = ContractBoard.new(ledger_next)
                if not board.restore(staged["contract_board"]):
                    return {"ok": false, "fatal": true, "reason": "n121_real_n104_board_corrupt"}
                var ready: Dictionary = NativeN98.prepare(pending["ledger"],
                    step_id, tick)
                if ready.has("error") or str(ready.get("dispatch_key", "")) != dispatch_key:
                    return {"ok": false, "fatal": true,
                        "reason": "n121_nonready_original_n98_step"}
                var posted: Dictionary = board.post(order_id, "delivery",
                    payer, escrow, str(source_quote["commodity"]),
                    int(source_quote["units"]), str(source_quote["source"]),
                    str(source_quote["destination"]), reward, tick,
                    tick + int(source_quote["lifespan_ticks"]), "faction")
                if not posted.get("ok", false):
                    return {"ok": false, "reason": "n121_real_n104_" +
                        str(posted.get("reason", "post_rejected"))}
                var acknowledged: String = NativeN98.acknowledge(
                    pending["ledger"], step_id, dispatch_key, order_id, tick)
                if not acknowledged.is_empty():
                    return {"ok": false, "fatal": true,
                        "reason": "n121_source_acknowledge_" + acknowledged}
                staged["contract_board"] = board.snapshot()
                staged["contract_board"]["contracts"][order_id]["mission_category"] = "strategy.logistics.v1"
                staged["contract_board"]["contracts"][order_id]["native_htn_key"] = dispatch_key
                staged["escrow_balances"][escrow] = ledger_next.balance(escrow)
                staged["faction_treasuries"][faction] = ledger_next.balance(payer)
                staged["native_htn_next_id"] = int(staged["native_htn_next_id"]) + 1
                staged["native_htn_contracts"][order_id] = {
                    "faction_id": faction, "plan_id": str(pending["ledger"]["plan_id"]),
                    "step_id": step_id, "dispatch_key": dispatch_key,
                    "tick": tick}
                event["status"] = "submitted_paid_n104_delivery"
                event["contract_id"] = order_id
                event["n9_receipt"] = "contract:" + order_id + ":post"
                event["committed_credits"] = reward
            elif str(action.get("kind", "")) == "produce":
                # Rust N121 only observes an already-running native
                # FacilityCrew. It must NOT start another factory, grant
                # materials or debit a second workforce account.
                var observation: Dictionary = NativeN121.production_context(
                    _world, faction, action, tick)
                if not observation.get("ok", false):
                    event["status"] = "native_source_producer_unverifiable"
                    event["reason"] = str(observation.get("reason", "missing_source_producer"))
                    return event
                var baselines: Dictionary = N121Baselines.capture(
                    observation["source_world"], observation["snapshot"],
                    pending["actions"])
                if not baselines.get("ok", false):
                    return {"ok": false, "fatal": true,
                        "reason": "n121_invalid_paid_production_baselines"}
                var readied: Dictionary = NativeN98.prepare(
                    pending["ledger"], step_id, tick)
                if readied.has("error") or str(readied.get("dispatch_key", "")) != dispatch_key:
                    return {"ok": false, "fatal": true,
                        "reason": "n121_producer_source_step_not_ready"}
                var native_producer: String = "facility:" + str(
                    observation["pin"]["facility_id"])
                var ack: String = NativeN98.acknowledge(pending["ledger"],
                    step_id, dispatch_key, native_producer, tick)
                if not ack.is_empty():
                    return {"ok": false, "fatal": true,
                        "reason": "n121_producer_ack_" + ack}
                pending["production_started_tick"] = tick
                # Keep the FIRST paid producer baseline across repeated
                # steps using the same source recipe/action identity.
                for output_key in baselines["production_baselines"]:
                    if not pending["production_baselines"].has(output_key):
                        pending["production_baselines"][output_key] = (
                            baselines["production_baselines"][output_key])
                event["status"] = "n121_observe_existing_paid_production"
                event["facility_id"] = str(observation["pin"]["facility_id"])
                event["recipe_id"] = str(observation["pin"]["recipe_id"])
            else:
                event["status"] = "n121_unsupported_source_action"
                event["reason"] = str(action.get("kind", ""))
                return event
        "await_native":
            var evidence: Dictionary = {}
            var native_id: String = str(gate.get("native_order_id", ""))
            if native_id.begins_with("facility:"):
                var source_action: Dictionary = N121Receipts.action_for_step(
                    pending, str(gate.get("step_id", "")))
                if not source_action.get("ok", false):
                    return {"ok": false, "fatal": true,
                        "reason": "n121_paid_production_action_lost"}
                var source_producer: Dictionary = NativeN121.production_context(
                    _world, faction, source_action["action"], tick)
                if not source_producer.get("ok", false):
                    event["status"] = "n121_producer_receipt_unavailable"
                    event["reason"] = str(source_producer.get("reason", "producer_missing"))
                    return event
                if native_id != "facility:" + str(source_producer["pin"]["facility_id"]):
                    return {"ok": false, "fatal": true,
                        "reason": "n121_source_producer_identity_changed"}
                evidence = N121Receipts.production_receipt(
                    source_producer["source_world"],
                    source_producer["snapshot"], pending,
                    str(gate["step_id"]), native_id, tick, multiplier)
            else:
                evidence = NativeN121.native_delivery_receipt(
                    _world, _ledger.snapshot(), faction, pending, gate, tick)
            if not evidence.get("ok", false):
                return {"ok": false, "fatal": true,
                    "reason": str(evidence.get("reason", "n121_invalid_native_receipt"))}
            event["status"] = str(evidence.get("reason", "n121_wait_native_receipt"))
            if evidence.get("receipt", null) is Dictionary:
                var apply_error: String = NativeN98.apply_receipt(
                    pending["ledger"], evidence["receipt"])
                if not apply_error.is_empty():
                    return {"ok": false, "fatal": true,
                        "reason": "n121_n98_receipt_" + apply_error}
                event["native_receipt"] = evidence["receipt"].duplicate(true)
                if evidence.get("accounted_after_ack", null) is Dictionary:
                    pending["production_accounted"] = evidence[
                        "accounted_after_ack"].duplicate(true)
        "reconcile_prepared":
            # This state must survive a crash between a prepared source
            # key and an N104 receipt. Never blindly repost an order.
            var actual_id: String = ""
            for cid in staged.get("native_htn_contracts", {}):
                var meta: Dictionary = staged["native_htn_contracts"][cid]
                if str(meta.get("dispatch_key", "")) == str(gate.get("dispatch_key", "")) and str(meta.get("faction_id", "")) == faction:
                    actual_id = str(cid)
                    break
            if actual_id.is_empty():
                event["status"] = "prepared_wait_real_n104_reconcile"
                return event
            var error: String = NativeN98.acknowledge(
                pending["ledger"], str(gate["step_id"]),
                str(gate["dispatch_key"]), actual_id, tick)
            if not error.is_empty():
                return {"ok": false, "fatal": true,
                    "reason": "n121_prepared_reconcile_" + error}
            event["status"] = "reconciled_real_native_order"
        "completed", "needs_replan":
            var chosen_goal: Dictionary = pending.get("goal", {})
            var dest: String = str(chosen_goal.get("destination_id", ""))
            var commodity: String = str(chosen_goal.get("commodity", ""))
            var stock: float = float(staged.get("markets", {}).get(
                dest, {}).get("supply", {}).get(commodity, -1.0))
            var completed: bool = kind == "completed" and stock >= float(
                chosen_goal.get("target_units", 0))
            var terminal: Dictionary = N121State.record_terminal(next_state,
                faction, pending, "completed" if completed else "needs_replan",
                "n121_real_paid_goal_stock" if completed else
                    "n121_native_final_stock_short", tick, multiplier, stock)
            if not terminal.get("ok", false):
                return {"ok": false, "fatal": true,
                    "reason": "n121_terminal_state_rejected"}
            next_state = terminal["state"]
            event["status"] = "completed" if completed else "needs_replan"
        "await_dependencies":
            event["status"] = "await_native_dependencies"
        _:
            return {"ok": false, "fatal": true, "reason": "n121_invalid_original_n98_gate"}
    if kind not in ["completed", "needs_replan"]:
        next_state["active"][faction] = pending.duplicate(true)
    var updated: Dictionary = staged["native_planner_records"][faction]
    updated["status"] = ("n121_closed_" + str(event["status"])
        if kind in ["completed", "needs_replan"] else "n121_active")
    updated["last_source_execution_tick"] = tick
    updated["last_source_execution_kind"] = kind
    updated["ledger"] = pending["ledger"].duplicate(true)
    staged["native_execution"] = next_state
    var invalid: String = Schema.validate(staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n121_canonical_n39_schema_" + invalid}
    var accounts: Dictionary = Schema.accounts(staged)
    var balances: Dictionary = ledger_next.snapshot().get("balances", {})
    if accounts.size() != balances.size() or ledger_next.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n121_fabricated_n9_wallet"}
    for account in accounts:
        if balances.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true,
                "reason": "n121_n104_n9_account_divergence"}
    _world = staged
    _ledger = ledger_next
    return event


## Original strategy/planning/hybrid.rs is PURE: the native source
## head owns the goal, N155 builds the physical-action catalogue and N98
## owns step identity. A new N121 native command/receipt must authorize
## every later paid action. This does NOT post a contract or spend money.
func apply_native_hybrid_planning(tick: int, faction: String,
        head: Dictionary, multiplier: int) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "n100_wrong_native_faction_phase"}
    var mode: String = str(_world.get("native_planner_mode", "legacy"))
    if mode == "legacy":
        return {"ok": true, "status": "source_legacy_director",
            "due": false, "faction_id": faction}
    if mode not in ["htn", "hybrid"] or not _world.has(
            "native_planner_records"):
        return {"ok": false, "reason": "n100_invalid_native_planner_state"}
    if tick % (60 * multiplier) != 0:
        return {"ok": true, "due": false, "faction_id": faction}
    if not _world["faction_treasuries"].has(faction):
        return {"ok": false, "reason": "n100_missing_canonical_faction"}
    var existing: Dictionary = _world["native_planner_records"].get(
        faction, {})
    if int(existing.get("tick", -1)) == tick:
        return {"ok": false, "reason": "n100_duplicate_faction_planning_pass"}
    # Until the N121 receipt-driven execution bridge admits this plan,
    # NEVER discard/reissue its unique N98 dispatch keys.
    if str(existing.get("status", "")) in ["n98_planned_not_dispatched",
            "n121_active"]:
        return {"ok": true, "due": false, "faction_id": faction,
            "status": "awaiting_n121_canonical_execution"}
    # Frozen N121::blocked_until ensures no repeated plan/quote storm
    # while the ORIGINAL failed head stock goal is awaiting retry.
    var source_cooldown: int = int(_world.get("native_execution", {}).get(
        "blocked_until", {}).get(faction, 0))
    if tick < source_cooldown:
        return {"ok": true, "due": false, "faction_id": faction,
            "status": "source_n121_retry_cooldown",
            "retry_after_tick": source_cooldown}
    var candidate: Dictionary = NativeHybridPlanning.propose(
        _world, faction, head, tick, mode)
    if not candidate.get("ok", false):
        return candidate
    var staged: Dictionary = _world.duplicate(true)
    var record: Dictionary = {
        "faction_id": faction, "tick": tick,
        "status": str(candidate.get("status", "")),
        "reason": str(candidate.get("reason", "")),
        "source_snapshot_tick": int(candidate.get("source_snapshot_tick", tick))}
    if str(candidate.get("status", "")) == "n98_planned_not_dispatched":
        for key in ["goal", "actions", "plan", "ledger", "roles"]:
            record[key] = candidate.get(key, {}).duplicate(true)
        record["production_goal"] = bool(candidate.get("production_goal", false))
        record["production_target_delta"] = int(candidate.get(
            "production_target_delta", 0))
    staged["native_planner_records"][faction] = record
    staged["native_planner_last_tick"] = tick
    var invalid: String = Schema.validate(staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n100_source_planning_invalid_world:" + invalid}
    if Schema.accounts(staged) != Schema.accounts(_world):
        return {"ok": false, "fatal": true, "reason": "n100_forecast_modified_wallets"}
    _world = staged
    return {"ok": true, "due": true, "faction_id": faction,
        "status": record["status"], "reason": record["reason"],
        "native_dispatch_authorized": false,
        "planned_steps": record.get("ledger", {}).get("steps", []).size()}


## Rust source: in one faction tick, taxes -> bailouts -> relief.
## All receipts are immutable transfers of EXISTING N9 wallets, never a
## second treasury, market account or direct mutation from a planner.
func apply_native_faction_finance(tick: int, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or multiplier < 1:
        return {"ok": false, "reason": "n129_invalid_faction_accounting_tick"}
    if not _world.has("faction_finance_last_tick"):
        return {"ok": true, "due": false, "status": "legacy_no_native_finance"}
    var plan: Dictionary = NativeFactionFinance.propose(_world, tick, multiplier)
    if not plan.get("ok", false):
        return plan
    if not plan.get("due", false):
        return {"ok": true, "due": false, "tick": tick, "transfers": []}
    if tick <= int(_world["faction_finance_last_tick"]):
        return {"ok": false, "reason": "n129_duplicate_faction_accounting_tick"}
    var staged: Dictionary = _world.duplicate(true)
    var wallets = Ledger.new()
    if not wallets.restore(_ledger.snapshot()):
        return {"ok": false, "fatal": true, "reason": "n129_original_n9_ledger_unavailable"}
    var records: Array = plan.get("transfers", [])
    if records.size() > 10000:
        return {"ok": false, "fatal": true, "reason": "n129_unbounded_transfers"}
    var receipts: Array = []
    var sequence: int = 0
    for move in records:
        if not (move is Dictionary):
            return {"ok": false, "fatal": true, "reason": "n129_invalid_transfer"}
        var money: int = int(move.get("amount", 0))
        var source: String = str(move.get("source", ""))
        var destination: String = str(move.get("destination", ""))
        var kind: String = str(move.get("kind", ""))
        if money < 1 or source == destination or kind not in [
                "native_faction_tax", "native_facility_bailout",
                "native_faction_relief"]:
            return {"ok": false, "fatal": true, "reason": "n129_forbidden_finance_transfer"}
        var origin_ok: bool = false
        var target_ok: bool = false
        if kind == "native_faction_tax":
            origin_ok = source.begins_with("facility/")
            target_ok = destination.begins_with("faction/")
        else:
            origin_ok = source.begins_with("faction/")
            target_ok = destination.begins_with("population/") if (
                kind == "native_faction_relief" and
                str(move.get("recipient_kind", "")) == "household") else destination.begins_with("facility/")
        if not origin_ok or not target_ok:
            return {"ok": false, "fatal": true, "reason": "n129_wrong_source_account_type"}
        var operation_id: String = "n129:%d:%04d:%s" % [tick, sequence, kind]
        sequence += 1
        var posted: Dictionary = wallets.transfer(operation_id, source,
            destination, money, tick, kind)
        if not posted.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": "n129_native_account_transfer_rejected:" +
                    str(posted.get("reason", "unknown"))}
        receipts.append({"id": operation_id, "source": source,
            "destination": destination, "amount": money, "kind": kind})
    var proposed_treasuries: Dictionary = plan.get("faction_treasuries", {})
    var proposed_facilities: Dictionary = plan.get("facility_credits", {})
    var proposed_households: Dictionary = plan.get("population_wealth", {})
    if proposed_treasuries.size() != staged["faction_treasuries"].size() or proposed_facilities.size() != staged["facilities"].size() or proposed_households.size() != staged["populations"].size():
        return {"ok": false, "fatal": true, "reason": "n129_native_account_roster_changed"}
    for id in staged["faction_treasuries"]:
        if not proposed_treasuries.has(id):
            return {"ok": false, "fatal": true, "reason": "n129_unknown_source_faction"}
        staged["faction_treasuries"][id] = int(proposed_treasuries[id])
    for id in staged["facilities"]:
        if not proposed_facilities.has(id):
            return {"ok": false, "fatal": true, "reason": "n129_missing_native_facility"}
        if int(proposed_facilities[id]) != int(_world["facilities"][id]["credits"]):
            staged["facilities"][id]["dirty"] = true
        staged["facilities"][id]["credits"] = int(proposed_facilities[id])
    for id in staged["populations"]:
        if not proposed_households.has(id):
            return {"ok": false, "fatal": true, "reason": "n129_missing_native_household"}
        if int(proposed_households[id]) != int(_world["populations"][id]["wealth"]):
            # Rust relief.rs marks PopSentiment dirty when giving an
            # actual household wallet support transfer.
            staged["populations"][id]["sentiment_dirty"] = true
        staged["populations"][id]["wealth"] = int(proposed_households[id])
    staged["faction_finance_last_tick"] = tick
    var invalid: String = Schema.validate(staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n129_world_schema:" + invalid}
    var accounts: Dictionary = Schema.accounts(staged)
    var actual: Dictionary = wallets.snapshot().get("balances", {})
    if accounts.size() != actual.size() or wallets.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n129_native_total_not_conserved"}
    for account in accounts:
        if int(actual.get(account, -1)) != int(accounts[account]):
            return {"ok": false, "fatal": true, "reason": "n129_wallet_world_divergence"}
    _world = staged
    _ledger = wallets
    return {"ok": true, "due": true, "tick": tick,
        "receipts": receipts, "tax_due": plan["tax_due"],
        "relief_due": plan["relief_due"], "authority": "one_n39_world_n9"}


## Rust agents/faction.rs::tick_factions calls BodyTerritory derivation
## at its ORIGINAL 50×tick_multiplier cadence, before the other faction
## decisions. Only finished physical facilities can vote on ownership.
## Body control is a persisted ECS component; system control is derived
## alongside it, not a second mutable faction ownership database.
func apply_native_body_territory(tick: int, multiplier: int,
        orbits: RefCounted) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or multiplier < 1:
        return {"ok": false, "reason": "n150_invalid_native_territory_tick"}
    if not _world.has("body_territory"):
        return {"ok": true, "due": false,
            "status": "legacy_checkpoint_without_territory"}
    if tick % (50 * multiplier) != 0:
        return {"ok": true, "due": false, "tick": tick}
    if tick <= int(_world.get("territory_last_tick", 0)):
        return {"ok": false, "reason": "n150_duplicate_native_territory_tick"}
    var native: Dictionary = NativeDiplomacy.territory(_world, orbits)
    if not native.get("ok", false):
        return native
    var staged: Dictionary = _world.duplicate(true)
    staged["body_territory"] = native["bodies"].duplicate(true)
    staged["territory_last_tick"] = tick
    var invalid: String = Schema.validate(staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n150_native_body_territory_invalid:" + invalid}
    if Schema.accounts(staged) != Schema.accounts(_world):
        return {"ok": false, "fatal": true,
            "reason": "n150_territory_changed_canonical_funds"}
    _world = staged
    return {"ok": true, "due": true, "tick": tick,
        "bodies": native["bodies"].duplicate(true),
        "systems": native["systems"].duplicate(true),
        "market_controllers": native["market_controllers"].duplicate(true),
        "ambiguous_rust_ties": native.get("ambiguous_rust_ties", []).duplicate(true)}


## Rust engine.rs "relations" phase: source N150 scheduled treaty changes.
## Only THIS N39 owner commits the matrix. No extra ledger or faction clock.
## Old saves lacking the matrix intentionally keep it absent: no invented
## diplomatic history is injected into an already-running checkpoint.
func apply_native_faction_relations(tick: int, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or multiplier < 1:
        return {"ok": false, "reason": "n150_invalid_canonical_relations_phase"}
    if not _world.has("faction_relations") or not _world.has("faction_relations_last_tick"):
        return {"ok": true, "tick": tick, "due": false,
            "status": "legacy_checkpoint_no_native_diplomacy", "treaty_changes": []}
    var plan: Dictionary = NativeDiplomacy.propose_pass(_world, tick, multiplier)
    if not plan.get("ok", false):
        return plan
    if not plan.get("due", false):
        return {"ok": true, "tick": tick, "due": false, "treaty_changes": []}
    var last: int = int(_world["faction_relations_last_tick"])
    if tick <= last:
        return {"ok": false, "reason": "n150_duplicate_or_replayed_relations_pass"}
    var staged: Dictionary = _world.duplicate(true)
    staged["faction_relations"] = plan["pairs"].duplicate(true)
    staged["faction_relations_last_tick"] = tick
    var invalid: String = Schema.validate(staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n150_native_relations_invalid_world:" + invalid}
    # This pass changes neither treasury nor market stock. The N9 owner
    # and its immutable transaction history are unchanged by treaties.
    if Schema.accounts(staged) != Schema.accounts(_world):
        return {"ok": false, "fatal": true, "reason": "n150_treaties_changed_real_wallets"}
    _world = staged
    return {"ok": true, "due": true, "tick": tick,
        "treaty_changes": plan.get("treaty_changes", []).duplicate(true),
        "pairs": staged["faction_relations"].size(),
        "authority": "n39_one_faction_relations_matrix"}


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
    # N150 phase cursors and pair timestamps cannot point beyond the
    # physical World tick restored from disk. Source Rust stores treaties
    # persistently; body system control is re-derived from live facilities.
    for clock_key in ["faction_relations_last_tick", "territory_last_tick",
            "faction_finance_last_tick", "station_administration_last_tick",
            "native_planner_last_tick"]:
        if int(staged_world.get(clock_key, 0)) > int(saved["tick"]):
            return false
    for relation in staged_world.get("faction_relations", {}).values():
        if int(relation.get("since_tick", -1)) > int(saved["tick"]) or int(relation.get("last_event_tick", -1)) > int(saved["tick"]):
            return false
    # The original N121 prepared/acknowledged and N98 step timestamps
    # must not outlive the actual World tick. Never replay a future
    # dispatch or resurrect credits from a rewritten N38 checkpoint.
    for record in staged_world.get("native_planner_records", {}).values():
        if int(record.get("last_source_execution_tick", 0)) > int(saved["tick"]):
            return false
    for meta in staged_world.get("native_htn_contracts", {}).values():
        if int(meta.get("tick", -1)) > int(saved["tick"]):
            return false
    for plan in staged_world.get("native_execution", {}).get("active", {}).values():
        for step in plan.get("ledger", {}).get("steps", []):
            if int(step.get("updated_tick", -1)) > int(saved["tick"]):
                return false
    var staged_ledger = Ledger.new()
    if not staged_ledger.restore(saved["ledger"]):
        return false
    var expected: Dictionary = Schema.accounts(staged_world)
    for id in expected:
        if staged_ledger.balance(str(id)) != int(expected[id]):
            return false
    if staged_world.has("contract_board"):
        var contract_check := ContractBoard.new(staged_ledger)
        if not contract_check.restore(staged_world["contract_board"]):
            return false
    # N143 paid research receipts must retain their original N9 transfer
    # across disk reload; a head cannot manufacture paid work by editing
    # research progress without the ledger receipt.
    for receipt_id in staged_world.get("research_receipts", {}):
        if not staged_ledger.has_receipt(str(receipt_id)):
            return false
        var research_receipt: Dictionary = staged_world["research_receipts"][receipt_id]
        if int(research_receipt.get("tick", -1)) > int(saved["tick"]):
            return false
    # N38: verify last N151 migration against the exact immutable N9
    # receipt on disk. No invented passengers or stale wealth transfer.
    var last_migration: Dictionary = staged_world.get("population_migration_last", {})
    if not last_migration.is_empty():
        if int(last_migration.get("tick", -1)) > int(saved["tick"]):
            return false
        var transfer_id: String = str(last_migration.get("receipt_id", ""))
        if not transfer_id.is_empty():
            var receipt: Dictionary = staged_ledger.snapshot().get("receipts", {}).get(transfer_id, {})
            var from: String = str(last_migration.get("source_id", ""))
            var to: String = str(last_migration.get("destination_id", ""))
            var quantity: int = int(last_migration.get("wealth_transferred", 0))
            var expected_legs: Array = [
                {"account": Schema.household_account(from), "delta": -quantity},
                {"account": Schema.household_account(to), "delta": quantity}]
            if str(receipt.get("id", "")) != transfer_id or int(receipt.get("tick", -1)) != int(last_migration["tick"]) or str(receipt.get("kind", "")) != "native_population_migration" or receipt.get("legs", []) != expected_legs:
                return false
    if staged_ledger.snapshot()["balances"].size() != expected.size():
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
