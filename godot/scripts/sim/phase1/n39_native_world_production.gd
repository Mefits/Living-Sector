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
const ResearchShift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")
const EscrowStage = preload("res://scripts/sim/phase2/unified_contract_escrow_staging.gd")
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
        if str(_world["facilities"][dock_id].get("type", "")) != "station":
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
        ship_fields.append_array(["active_contract_id", "current_goal", "current_bt", "max_source_cost"])
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
    if payer != Schema.facility_account(str(buyer_market["owner"])):
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
