extends RefCounted
## N39 — opt-in physical production WorldBridge, frozen Rust 0.6.7.
## Rust: agents/facility/mod.rs::tick_recipes_and_mining, workforce.rs.
## Uses N73 Recipes.execute, N9 Inventory/CreditLedger: NO new goods/money.
## Source phase1 component. Not connected to the complete ECS until Phase2.
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const MarketObservationValidator = preload("res://scripts/sim/phase1/n39_market_observation_validator.gd")
const DockDeltaValidator = preload("res://scripts/sim/phase1/n39_dock_delta_validator.gd")
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
const OriginalResearchMandate = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const OriginalFactionCharter = preload("res://scripts/native_port/n109_charter.gd")
const OriginalEconomicMandate = preload("res://scripts/simulation/strategy/native_mandate_policy.gd")
const OriginalTechnology = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const OriginalPolicyCheckpoint = preload("res://scripts/sim/phase2/unified_n109_n110_policy_checkpoint.gd")
const NativeConstructionMaterial = preload("res://scripts/sim/phase1/n154_native_construction_materialize.gd")
const NativeConstructionLabor = preload("res://scripts/sim/phase2/unified_native_construction_labor.gd")
const N91Executor = preload("res://scripts/ported/n91_construction_executor.gd")
const ShipCatalog = preload("res://scripts/sim/ship_catalog.gd")
const N91SourceDispatch = preload("res://scripts/sim/phase2/unified_n91_construction_dispatch.gd")
const NativeColonyFounding = preload("res://scripts/sim/phase2/unified_n151_colony_founding_phase.gd")
const NativeColonyOrders = preload("res://scripts/sim/phase2/unified_n144_colony_contracts.gd")
const NativeB4ColonyAftercare = preload("res://scripts/sim/phase2/unified_n92_colony_aftercare.gd")
const NativeColonyMetals = preload("res://scripts/sim/phase2/unified_n144_colony_metals.gd")
const NativeColonyMetalAssignment = preload("res://scripts/sim/phase2/unified_n144_colony_metal_assignment.gd")
const NativeNewColonyHead = preload("res://scripts/sim/phase2/unified_n144_new_colony_head.gd")
const SourceN134Construction = preload("res://scripts/sim/phase2/unified_n134_construction_head.gd")
const NativeColonyDocks = preload("res://scripts/sim/phase2/unified_n151_colony_dock_phase.gd")
const NativeColonyEstablish = preload("res://scripts/sim/phase2/unified_n151_colony_establish.gd")
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
const NativeAdminN152 = preload("res://scripts/sim/phase2/unified_n152_admin_cleanup.gd")
const NativeN148 = preload("res://scripts/sim/phase2/unified_n148_ship_retirement_phase.gd")
const NativePassengers = preload("res://scripts/sim/phase2/unified_n104_passenger_transit.gd")
const NativeN147 = preload("res://scripts/sim/phase2/unified_n147_colony_migration_observer.gd")
const NativeN147Head = preload("res://scripts/sim/phase2/unified_n147_colony_head_grant.gd")
const NativeShipLifecycle = preload("res://scripts/sim/phase1/n148_native_ship_lifecycle.gd")
const NativeN149Crew = preload("res://scripts/sim/phase2/unified_n149_ship_crew_phase.gd")
const NativeShipPrices = preload("res://scripts/sim/phase2/unified_native_ship_price_observation.gd")
const NativeCrewXp = preload("res://scripts/sim/ship_crew_skills_n128.gd")
const N146Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const NativeFreeTrade = preload("res://scripts/sim/phase2/unified_n83_free_trade_apply.gd")
const NativeShipServices = preload("res://scripts/sim/phase2/unified_n97_ship_service_stage.gd")
const N21Source = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const NativeN104Release = preload("res://scripts/sim/phase2/unified_n104_release_stage.gd")
const NativeGateJump = preload("res://scripts/sim/phase2/unified_n108_gate_jump_stage.gd")
const NativeGatePair = preload("res://scripts/sim/phase2/unified_n108_gate_pair_stage.gd")
const NativeCrisisPhase = preload("res://scripts/sim/phase2/unified_native_crisis_phase.gd")
const NativeCrisisWarnings = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")
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
    if _ready or _measured_schema_validate("L92", physical_world) != "":
        return false
    var money = Ledger.new()
    if not money.import_accounts(_measured_schema_accounts("L95", physical_world)):
        return false
    _world = physical_world.duplicate(true)
    _ledger = money
    _last_tick = 0
    _ready = true
    return true

## Profiling counters are strictly outside N39 snapshot and are never
## saved or consumed by game decisions. Opt in with LS_PROFILE_NATIVE_PHASES=1.
var _profile_copy_enabled: bool = OS.get_environment(
    "LS_PROFILE_NATIVE_PHASES") == "1"
var _profile_world_copy_calls: int = 0
var _profile_world_copy_usec: int = 0
var _profile_ship_copy_calls: int = 0
var _profile_ship_copy_usec: int = 0
var _profile_n21_commit_calls: int = 0
var _profile_n21_commit_usec: int = 0
## Runtime-only statistics. Not part of save snapshots or authoritative World.
var _profile_schema_sites: Dictionary = {}
var _profile_copy_sites: Dictionary = {}
## This generation covers ONLY N150 observation writes, NOT physical markets.
## No cache may rely on it to validate mutable stocks or money.
var _market_observation_version: int = 0
var _market_observation_restored: bool = false
## N21 proposal-generation contract, with a separate negative namespace for
## N38-restored owners. No new persisted field or financial authority.
var _n21_commit_generation: int = 0
var _n21_restored: bool = false
var _n21_shadow_checks: int = 0
var _n21_shadow_false_rejections: int = 0
var _n21_shadow_last_error: String = ""

func n21_write_version() -> int:
    return -1 - _n21_commit_generation if _n21_restored else _n21_commit_generation

func n21_shadow_profile() -> Dictionary:
    return {"enabled": _profile_copy_enabled, "checks": _n21_shadow_checks,
        "false_rejections": _n21_shadow_false_rejections,
        "last_error": _n21_shadow_last_error,
        "write_version": n21_write_version()}

func market_observation_version() -> int:
    return (-1 - _market_observation_version if _market_observation_restored
        else _market_observation_version)

func native_schema_profile() -> Dictionary:
    return {"enabled": _profile_copy_enabled,
        "schema": _cost_percentiles(_profile_schema_sites),
        "copies": _cost_percentiles(_profile_copy_sites),
        "market_observation_version": market_observation_version()}

func _cost_percentiles(measured: Dictionary) -> Dictionary:
    var published: Dictionary = {}
    for site in measured:
        var row: Dictionary = measured[site].duplicate()
        var samples: Array = row.get("samples_usec", []).duplicate()
        row.erase("samples_usec")
        if not samples.is_empty():
            samples.sort()
            for p in [50, 95, 99]:
                var offset: int = clampi(ceili(
                    float(samples.size()) * float(p) / 100.0) - 1,
                    0, samples.size() - 1)
                row["p" + str(p) + "_usec"] = int(samples[offset])
        published[site] = row
    return published

func _record_timing(bucket: Dictionary, site: String, elapsed: int) -> void:
    var row: Dictionary = bucket.get(site, {"calls": 0, "total_usec": 0,
        "max_usec": 0, "min_usec": 9223372036854775807,
        "samples_usec": []})
    row["calls"] = int(row["calls"]) + 1
    row["total_usec"] = int(row["total_usec"]) + elapsed
    row["max_usec"] = maxi(int(row["max_usec"]), elapsed)
    row["min_usec"] = mini(int(row["min_usec"]), elapsed)
    var samples: Array = row["samples_usec"]
    samples.append(elapsed)
    # Diagnostic-only rolling window: exact lifetime totals remain in row.
    # Bound retention and percentile sorting independently of tick count.
    if samples.size() > 256:
        samples.pop_front()
    bucket[site] = row

func _measured_schema_validate(site: String, world: Dictionary) -> String:
    if not _profile_copy_enabled:
        return Schema.validate(world)
    var began: int = Time.get_ticks_usec()
    var result: String = Schema.validate(world)
    _record_timing(_profile_schema_sites, "validate:" + site,
        maxi(0, Time.get_ticks_usec() - began))
    return result

func _measured_schema_accounts(site: String, world: Dictionary) -> Dictionary:
    if not _profile_copy_enabled:
        return Schema.accounts(world)
    var began: int = Time.get_ticks_usec()
    var result: Dictionary = Schema.accounts(world)
    _record_timing(_profile_schema_sites, "accounts:" + site,
        maxi(0, Time.get_ticks_usec() - began))
    return result

func _copy_world(site: String, deep: bool) -> Dictionary:
    if not _profile_copy_enabled:
        return _world.duplicate(true) if deep else _world.duplicate()
    var began: int = Time.get_ticks_usec()
    var copied: Dictionary = _world.duplicate(true) if deep else _world.duplicate()
    _record_timing(_profile_copy_sites,
        ("deep:" if deep else "shallow:") + site,
        maxi(0, Time.get_ticks_usec() - began))
    return copied


func world_copy_profile() -> Dictionary:
    return {"enabled": _profile_copy_enabled,
        "world_copy_calls": _profile_world_copy_calls,
        "world_copy_usec": _profile_world_copy_usec,
        "ship_copy_calls": _profile_ship_copy_calls,
        "ship_copy_usec": _profile_ship_copy_usec,
        "n21_commit_calls": _profile_n21_commit_calls,
        "n21_commit_usec": _profile_n21_commit_usec}

func world_snapshot() -> Dictionary:
    if not _ready:
        return {}
    if not _profile_copy_enabled:
        return _copy_world("L127", true)
    var start_us: int = Time.get_ticks_usec()
    var copy: Dictionary = _copy_world("L129", true)
    _profile_world_copy_calls += 1
    _profile_world_copy_usec += maxi(0, Time.get_ticks_usec() - start_us)
    return copy

## Read-only fleet projection from the SAME authoritative N39 World.
## The GUI should not duplicate the entire market/receipts/history graph
## merely to draw a few ship markers. No new owner or independent state.
func ships_snapshot() -> Dictionary:
    if not _ready:
        return {}
    if not _profile_copy_enabled:
        return _world.get("ships", {}).duplicate(true)
    var start_us: int = Time.get_ticks_usec()
    var copy: Dictionary = _world.get("ships", {}).duplicate(true)
    _profile_ship_copy_calls += 1
    _profile_ship_copy_usec += maxi(0, Time.get_ticks_usec() - start_us)
    return copy


## Owned projections used by the hot N158 loop. Each allocates only fresh
## scalar data: no nested Dictionary from authoritative _world escapes.
## These are NOT cross-tick caches and need no save/N38 version.
func native_ship_identity_snapshot() -> Dictionary:
    if not _ready:
        return {}
    var identities: Dictionary = {}
    for ship_id in _world.get("ships", {}):
        var ship: Dictionary = _world["ships"][ship_id]
        identities[str(ship_id)] = {"ship_id": str(ship_id),
            "faction_id": str(ship.get("faction_id", ""))}
    return identities

func native_has_ship(ship_id: String) -> bool:
    return _ready and _world.get("ships", {}).has(ship_id)

func native_contract_kind(contract_id: String) -> Dictionary:
    if not _ready:
        return {}
    var board: Dictionary = _world.get("contract_board", {}).get("contracts", {})
    if not board.has(contract_id):
        return {}
    var contract: Dictionary = board[contract_id]
    return {"contract_type": str(contract.get("contract_type", "")),
        "mission_category": str(contract.get("mission_category", ""))}

func native_has_ship_domain() -> bool:
    return _ready and _world.has("ships")

## Read-only values needed by N158's per-tick empty-queue fast path.
## Reading these scalars in N39 does NOT publish _world or permit
## any mutation, unlike a whole World snapshot of growing N9 history.
func native_dock_queue_presence() -> Dictionary:
    if not _ready or not _world.has("ships"):
        return {"has_ships": false, "queued": false}
    for physical_port in _world.get("facilities", {}).values():
        if physical_port is Dictionary and (
                physical_port.get("dock_queue", []) is Array) and (
                not physical_port.get("dock_queue", []).is_empty()):
            return {"has_ships": true, "queued": true}
    return {"has_ships": true, "queued": false}

func native_planner_mode() -> String:
    return str(_world.get("native_planner_mode", "legacy")) if _ready else "legacy"


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
    # N156/N130 stage owns only facilities, markets and populations.
    # Payroll.pay_shift may update household wealth, while N130 restock
    # updates market supply; all three must be detached BEFORE any writes.
    # Other World domains are read-only here and remain authoritative.
    var lifecycle_world: Dictionary = _copy_world("L196_owned_root", false)
    # N130 can write arbitrary buyer/seller rows in stable ID order, so its
    # paid cadence retains a fully detached facilities domain. On ordinary
    # N156 ticks only repair candidates and lifecycle deltas may be written.
    # Copy the registry, then detach each row BEFORE Payroll._blocked,
    # Payroll.pay_shift or lifecycle condition/reserves writes touch it.
    var restock_due: bool = bool(initial["due"]["restock"])
    var lifecycle_owned_rows: Dictionary = {}
    # Even on N130 cadence, N156 only changes repair candidates and its
    # lifecycle deltas. N130 buyers/sellers are detached AFTER those changes,
    # so eligibility reflects the actual post-repair, post-abandonment World.
    lifecycle_world["facilities"] = _world["facilities"].duplicate(false)
    for candidate in initial["repair_candidates"]:
        var repair_id: String = str(candidate.get("facility_id", ""))
        if lifecycle_world["facilities"].has(repair_id) and not lifecycle_owned_rows.has(repair_id):
            lifecycle_world["facilities"][repair_id] = _world["facilities"][repair_id].duplicate(true)
            lifecycle_owned_rows[repair_id] = true
    # N130 only writes markets on its 20x cadence; N156 Payroll only
    # writes populations when a paid repair candidate exists. The
    # off-cadence stages are read-only for these authoritative domains.
    # Detach before either writer, never expose a mutable canonical alias.
    # N130 market rows are detached just before ServiceRestock.apply, after
    # lifecycle has established the final eligible set.
    if not initial["repair_candidates"].is_empty():
        # Payroll.pay_shift selects households by the producer's faction and
        # location, in sorted population-ID order. Only those households can
        # receive wages/employment writes; unrelated colonies are read-only.
        # Build the complete union BEFORE the first payment, since an earlier
        # paid repair changes occupied() and later assignments. Do not filter
        # by available workers or wallet: those values can change mid-stage.
        var payroll_locations: Dictionary = {}
        for candidate in initial["repair_candidates"]:
            var repair_id: String = str(candidate.get("facility_id", ""))
            if not _world["facilities"].has(repair_id):
                return {"ok": false, "reason": "unknown_repair_candidate"}
            var employer: Dictionary = _world["facilities"][repair_id]
            var faction: String = str(employer.get("faction", ""))
            var location: String = str(employer.get("location", ""))
            if not payroll_locations.has(faction):
                payroll_locations[faction] = {}
            payroll_locations[faction][location] = true
        var payroll_populations: Dictionary = _world["populations"].duplicate(false)
        for population_id in _world["populations"]:
            var household: Dictionary = _world["populations"][population_id]
            var faction: String = str(household.get("faction", ""))
            var location: String = str(household.get("location", ""))
            if payroll_locations.has(faction) and payroll_locations[faction].has(location):
                payroll_populations[population_id] = household.duplicate(true)
        lifecycle_world["populations"] = payroll_populations
    # Receipts accumulate indefinitely; cloning the whole N9 history on
    # every no-op orbit tick would make long-term simulation quadratic.
    # No new maintenance payments are possible unless there is a paid
    # repair candidate or the actual Rust 20×multiplier restock cadence.
    var money_phase_due: bool = not initial["repair_candidates"].is_empty() or bool(initial["due"]["restock"])
    var lifecycle_ledger: RefCounted = _ledger
    if money_phase_due:
        lifecycle_ledger = _ledger.fork()
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
        # The second proposal can differ after a paid repair. Detach any
        # newly affected row before writing; do not mutate the canonical
        # World if a later Schema/ledger/restock guard rejects this stage.
        if not lifecycle_owned_rows.has(facility_id):
            lifecycle_world["facilities"][facility_id] = _world["facilities"][facility_id].duplicate(true)
            lifecycle_owned_rows[facility_id] = true
        var updated: Dictionary = lifecycle_world["facilities"][facility_id]
        var delta: Dictionary = lifecycle["changes"][facility_id]
        updated["condition"] = float(delta["condition"])
        updated["abandoned"] = bool(delta["abandoned"])
        updated["abandon_counter"] = int(delta["abandon_counter"])
        updated["reserves"] = delta["reserves"].duplicate(true)
        # N156 household-derived crew morale doesn't debit Food a second time.
        if delta.has("morale"):
            updated["morale"] = float(delta["morale"])
    if restock_due:
        # ServiceRestock.apply iterates all facilities in sorted ID order and
        # can mutate ONLY a same-faction, live buyer and its market owner.
        # Compute this conservative union from the POST-lifecycle stage,
        # before the first N9 payment. All changed rows are detached before
        # any restock mutation, including a later failed payment/guard.
        var restock_markets: Dictionary = lifecycle_world["markets"].duplicate()
        var restock_owned_markets: Dictionary = {}
        var restock_ids: Array = lifecycle_world["facilities"].keys()
        restock_ids.sort()
        for buyer_id in restock_ids:
            var buyer_view: Dictionary = lifecycle_world["facilities"][buyer_id]
            if bool(buyer_view.get("abandoned", false)):
                continue
            var market_id: String = str(buyer_view.get("location", ""))
            if not restock_markets.has(market_id):
                # Let the original N130 validation reject an absent market
                # (or skip a valid construction dock) without any writes.
                continue
            var market_view: Dictionary = restock_markets[market_id]
            var seller_id: String = str(market_view.get("owner", ""))
            if not lifecycle_world["facilities"].has(seller_id):
                continue
            var seller_view: Dictionary = lifecycle_world["facilities"][seller_id]
            if str(buyer_view.get("faction", "")) != str(seller_view.get("faction", "")) or (
                    bool(seller_view.get("abandoned", false))) or (
                    str(seller_view.get("location", "")) != market_id):
                continue
            for owner_id in [buyer_id, seller_id]:
                if not lifecycle_owned_rows.has(owner_id):
                    lifecycle_world["facilities"][owner_id] = lifecycle_world["facilities"][owner_id].duplicate(true)
                    lifecycle_owned_rows[owner_id] = true
            if not restock_owned_markets.has(market_id):
                restock_markets[market_id] = market_view.duplicate(true)
                restock_owned_markets[market_id] = true
        lifecycle_world["markets"] = restock_markets
    var restocked: Dictionary = ServiceRestock.apply(
        lifecycle_world, lifecycle_ledger, tick, tick_multiplier)
    if not restocked.get("ok", false):
        return {"ok": false, "reason": "service_restock_" + str(restocked.get("reason", "rejected"))}
    if _measured_schema_validate("L255", lifecycle_world) != "":
        return {"ok": false, "reason": "lifecycle_restock_schema_rejected"}
    var accounts: Dictionary = _measured_schema_accounts("L257", lifecycle_world)
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
            # Only facilities and the administration projection are written here.
            # Detach facilities before staffing; every other World domain is
            # read-only during this stage and the full Schema oracle remains.
            # Validate the complete assignment read-set before allocating any
            # mutable rows. N18 never writes facility money, inventory or crew
            # state: only assigned_workers can differ from the previous World.
            var assignments: Dictionary = station_admin["assignments"]
            var previous_facilities: Dictionary = _world["facilities"]
            if assignments.size() != previous_facilities.size():
                return {"ok": false, "reason": "n18_incomplete_station_staffing"}
            for facility_id in previous_facilities:
                if not assignments.has(facility_id) or (
                        typeof(assignments[facility_id]) != TYPE_INT):
                    return {"ok": false, "reason": "n18_incomplete_station_staffing"}
            # The root and facilities map are new. Unchanged facility rows
            # are read-only through this stage and may safely be shared with
            # the old World; changed rows detach their complete nested graph.
            # This avoids cloning every market-sized reserves/dock_queue graph
            # on a staffing tick when only a few worker counts change.
            var staffed: Dictionary = _copy_world("n18_staffing_root", false)
            var staffed_facilities: Dictionary = previous_facilities.duplicate()
            for facility_id in previous_facilities:
                var assigned: int = int(assignments[facility_id])
                var previous_row: Dictionary = previous_facilities[facility_id]
                if assigned == int(previous_row.get("assigned_workers", 0)) and (
                        previous_row.has("assigned_workers")):
                    continue
                var owned_row: Dictionary = previous_row.duplicate(true)
                owned_row["assigned_workers"] = assigned
                staffed_facilities[facility_id] = owned_row
            staffed["facilities"] = staffed_facilities
            staffed["station_administration"] = station_admin["snapshots"].duplicate(true)
            staffed["station_administration_last_tick"] = tick
            var staffing_error: String = _measured_schema_validate("L285", staffed)
            if not staffing_error.is_empty():
                return {"ok": false, "reason": "n18_invalid_native_workforce_state:" +
                    staffing_error}
            if _measured_schema_accounts("L289", staffed) != _measured_schema_accounts("L289", _world):
                return {"ok": false, "reason": "n18_administrator_invented_money"}
            _world = staffed
    var ids: Array = _world["facilities"].keys()
    ids.sort()
    var lod_fired: Dictionary = {}
    # N18 may have published a row-owned facilities map: unchanged rows can
    # still be shared with its pre-staffing World. LOD is the next writer.
    # Decide all due firings from the unchanged read view first, then detach
    # ONLY the rows whose cursor advances. This preserves source iteration
    # and prevents an in-place LOD write from escaping across an owned stage.
    var lod_cursor_updates: Dictionary = {}
    for id in ids:
        var f: Dictionary = _world["facilities"][id]
        # Rust AgentLod::try_fire advances every tick, not just work cadence.
        if not f.has("lod_divisor") or int(f["lod_divisor"]) <= 1:
            lod_fired[id] = true
        elif tick >= int(f.get("lod_next_tick", 0)):
            lod_fired[id] = true
            lod_cursor_updates[id] = tick + int(f["lod_divisor"])
    if not lod_cursor_updates.is_empty():
        var lod_world: Dictionary = _copy_world("n39_lod_cursor_root", false)
        var lod_facilities: Dictionary = _world["facilities"].duplicate()
        for id in ids:
            if not lod_cursor_updates.has(id):
                continue
            var detached: Dictionary = lod_facilities[id].duplicate(true)
            detached["lod_next_tick"] = int(lod_cursor_updates[id])
            lod_facilities[id] = detached
        lod_world["facilities"] = lod_facilities
        # This cursor transition is money-neutral; retain the complete
        # production Schema oracle before publishing any owned row.
        if _measured_schema_validate("n39_lod_cursor_owned", lod_world) != "":
            return {"ok": false, "reason": "n39_lod_cursor_schema_rejected"}
        _world = lod_world
    var receipts: Array = []
    var failures: Dictionary = {}
    var recipe_due: bool = tick % (RECIPE_INTERVAL_BASE * tick_multiplier) == 0
    var mining_due: bool = tick % (MINING_INTERVAL_BASE * tick_multiplier) == 0
    if recipe_due:
        # Payroll.refresh_employment writes every household in place. The
        # authoritative World must not be mutated before validation: a later
        # failed recipe/Schema guard must not leak employment changes through
        # shared population rows. Compute the exact source occupied() view
        # once, then detach only households whose employed_fraction changes.
        # Do not change the recipe cadence, occupancy order or wage rules.
        var occupied_workers: Dictionary = Payroll.occupied(_world, tick, external_workers)
        var employment_world: Dictionary = _copy_world("n39_employment_root", false)
        var employment_populations: Dictionary = _world["populations"].duplicate()
        var employment_changed: bool = false
        for population_id in _world["populations"]:
            var previous_household: Dictionary = _world["populations"][population_id]
            var capacity: float = maxf(1.0, float(previous_household["count"]) * 0.6)
            var fraction: float = clampf(
                float(occupied_workers.get(population_id, 0)) / capacity, 0.0, 1.0)
            if previous_household.has("employed_fraction") and (
                    float(previous_household["employed_fraction"]) == fraction):
                continue
            var detached_household: Dictionary = previous_household.duplicate(true)
            detached_household["employed_fraction"] = fraction
            employment_populations[population_id] = detached_household
            employment_changed = true
        if employment_changed:
            employment_world["populations"] = employment_populations
            var employment_error: String = _measured_schema_validate(
                "n39_employment_owned", employment_world)
            if not employment_error.is_empty():
                return {"ok": false, "reason":
                    "n39_employment_invalid_world:" + employment_error}
            _world = employment_world
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
    var staged_money: RefCounted = _ledger.fork()
    var receipt_id: String = "n108:refit:" + ship_id + ":" + slot + ":" + str(tick)
    var receipt: Dictionary = staged_money.transfer(receipt_id,
        Schema.ship_account(ship_id), Schema.facility_account(dock_id),
        cost, tick, "native_paid_shipyard_refit")
    if not receipt.get("ok", false):
        return {"ok": false, "reason": "n108_n9_paid_refit_rejected:" +
            str(receipt.get("reason", "unknown"))}
    if staged_money.balance(Schema.ship_account(ship_id)) != int(stage["ships"][ship_id]["credits"]) or staged_money.balance(Schema.facility_account(dock_id)) != int(stage["facilities"][dock_id]["credits"]):
        return {"ok": false, "fatal": true, "reason": "n108_inconsistent_paid_refit_accounts"}
    var invalid: String = _measured_schema_validate("L420", stage)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n108_invalid_native_ship_after_refit:" + invalid}
    var accounts: Dictionary = _measured_schema_accounts("L423", stage)
    var balances: Dictionary = staged_money.balances_snapshot()
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


## N14 owned publication: all mutable rows are detached, unchanged rows
## are read-only aliases. Validation happens before constructing the stage.
## The full Schema and N9 account oracles remain in apply_ship_phase.
static func _n14_owned_ship_phase_stage(world: Dictionary,
        proposed_ships: Dictionary, next_token: int) -> Dictionary:
    if not (world.get("ships") is Dictionary):
        return {}
    var previous: Dictionary = world["ships"]
    if proposed_ships.size() != previous.size():
        return {}
    var frozen_fields: Array[String] = ["id", "name", "class",
        "faction_id", "size", "cargo_capacity", "fuel_capacity",
        "crew_size", "crew_roles", "cargo", "credits", "docked_at"]
    var owned: Dictionary = previous.duplicate()
    for ship_id in previous:
        if not proposed_ships.has(ship_id) or not (previous[ship_id] is Dictionary) or (
                not (proposed_ships[ship_id] is Dictionary)):
            return {}
        var old: Dictionary = previous[ship_id]
        var candidate: Dictionary = proposed_ships[ship_id]
        for field in frozen_fields:
            if candidate.get(field, null) != old.get(field, null):
                return {}
        if candidate != old:
            owned[ship_id] = candidate.duplicate(true)
    var staged: Dictionary = world.duplicate()
    staged["ships"] = owned
    staged["ship_next_token"] = next_token
    return staged

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
    # N14 may advance only a small subset of ships per paid tick. Preserve
    # frozen physical fields and detach every changed nested ship row; never
    # deep-copy the entire fleet or mutate the source proposal in place.
    var staged: Dictionary = _n14_owned_ship_phase_stage(
        _world, new_ships, int(proposal["next_token"]))
    if staged.is_empty():
        return false
    if _measured_schema_validate("L475", staged) != "":
        return false
    # No fleet transition is allowed to mint or move cash; all 24 source
    # ship wallets remain in the SAME N9 balances as the existing economy.
    var expected: Dictionary = _measured_schema_accounts("L479", staged)
    for account in expected:
        if _ledger.balance(str(account)) != int(expected[account]):
            return false
    _world = staged
    return true



## II-B N108: stage publication with owned rows, not copied historical World.
## Called only after the complete proposal Schema/N9 validation. Recheck
## equality with the proposal so a changed/unexpected domain cannot vanish.
static func _n108_owned_gate_publication(source: Dictionary,
        proposed: Dictionary, changed_facilities: Array,
        changed_ship: String, receipt_domain: String,
        receipt_id: String) -> Dictionary:
    if receipt_id.is_empty() or not (source.get("facilities") is Dictionary) or (
            not (proposed.get("facilities") is Dictionary)) or (
            not (proposed.get(receipt_domain) is Dictionary)) or (
            not (source.get(receipt_domain, {}) is Dictionary)):
        return {}
    if proposed.size() != source.size() + (0 if source.has(receipt_domain) else 1):
        return {}
    var old_receipts: Dictionary = source.get(receipt_domain, {})
    var new_receipts: Dictionary = proposed[receipt_domain]
    if old_receipts.has(receipt_id) or not new_receipts.has(receipt_id) or (
            new_receipts.size() != old_receipts.size() + 1) or (
            not (new_receipts[receipt_id] is Dictionary)):
        return {}
    var owned: Dictionary = source.duplicate()
    var facilities: Dictionary = source["facilities"].duplicate()
    var selected: Dictionary = {}
    for fid in changed_facilities:
        if selected.has(fid) or not source["facilities"].has(fid) or (
                not proposed["facilities"].has(fid)) or (
                not (proposed["facilities"][fid] is Dictionary)):
            return {}
        selected[fid] = true
        facilities[fid] = proposed["facilities"][fid].duplicate(true)
    owned["facilities"] = facilities
    if not changed_ship.is_empty():
        if not (source.get("ships") is Dictionary) or (
                not (proposed.get("ships") is Dictionary)) or (
                not source["ships"].has(changed_ship)) or (
                not proposed["ships"].has(changed_ship)) or (
                not (proposed["ships"][changed_ship] is Dictionary)):
            return {}
        var ships: Dictionary = source["ships"].duplicate()
        ships[changed_ship] = proposed["ships"][changed_ship].duplicate(true)
        owned["ships"] = ships
    var receipts: Dictionary = old_receipts.duplicate()
    receipts[receipt_id] = new_receipts[receipt_id].duplicate(true)
    owned[receipt_domain] = receipts
    if owned != proposed:
        return {}
    return owned


## Explicit native admin pairing of two ALREADY REAL N154/seed gates.
## Rust spawner reads paired_gate_id from existing facilities; it never
## chooses the destination system or creates a gate for the player.
## No N9 money, ship, construction material or tech state is changed.
## Caller must be an explicitly approved external admin action, never
## speculative N80/N134 AI or a guessed market shortage.
func apply_native_n108_gate_pair(tick: int, gate_a: String,
        gate_b: String, resolver: RefCounted) -> Dictionary:
    if not _ready or tick < 0 or tick != _last_tick or (
            gate_a.is_empty() or gate_b.is_empty() or resolver == null):
        return {"ok": false, "reason": "n108_pair_invalid_admin_boundary"}
    var previous_money: Dictionary = _ledger.snapshot()
    var proposal: Dictionary = NativeGatePair.stage(_world,
        resolver, gate_a, gate_b, tick)
    if not proposal.get("ok", false):
        return proposal
    var future: Dictionary = proposal.get("world", {})
    var id: String = str(proposal.get("pair_id", ""))
    if id.is_empty() or future.size() != _world.size() + (
            0 if _world.has("native_gate_pair_receipts") else 1):
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_unauthorized_new_world_domain"}
    for domain in _world:
        if domain not in ["facilities", "native_gate_pair_receipts"] and (
                future.get(domain, null) != _world[domain]):
            return {"ok": false, "fatal": true,
                "reason": "n108_pair_changed_unrelated_canonical_source"}
    var ids: Array = [gate_a, gate_b]
    for fid in _world["facilities"]:
        if not future["facilities"].has(fid) or (
                str(fid) not in ids and future["facilities"][fid] !=
                _world["facilities"][fid]):
            return {"ok": false, "fatal": true,
                "reason": "n108_pair_modified_other_physical_facility"}
    if future["facilities"].size() != _world["facilities"].size():
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_created_fictitious_gate"}
    for selected in ids:
        var before: Dictionary = _world["facilities"][selected]
        var after: Dictionary = future["facilities"][selected]
        var expected: Dictionary = before.duplicate(true)
        expected["gate_link"] = after.get("gate_link", {}).duplicate(true)
        expected["dirty"] = true
        if after != expected or int(after.get("credits", -1)) != int(
                before.get("credits", -2)):
            return {"ok": false, "fatal": true,
                "reason": "n108_pair_modified_credits_or_facility_lifecycle"}
    var receipts: Dictionary = future.get("native_gate_pair_receipts", {})
    if not receipts.has(id) or receipts.size() != _world.get(
            "native_gate_pair_receipts", {}).size() + 1 or str(
            receipts[id].get("kind", "")) != "native_n108_explicit_gate_pair":
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_missing_unique_source_receipt"}
    for prior in _world.get("native_gate_pair_receipts", {}):
        if receipts.get(prior, null) != _world["native_gate_pair_receipts"][prior]:
            return {"ok": false, "fatal": true,
                "reason": "n108_pair_changed_existing_source_history"}
    var schema_reason: String = _measured_schema_validate("L545", future)
    if not schema_reason.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_schema_" + schema_reason}
    if _measured_schema_accounts("L549", future) != _measured_schema_accounts("L549", _world) or (
            _ledger.snapshot() != previous_money):
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_minted_or_moved_real_n9_money"}
    var owned_pair: Dictionary = _n108_owned_gate_publication(_world,
        future, ids, "", "native_gate_pair_receipts", id)
    if owned_pair.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_owned_publication_rejected"}
    var owned_pair_error: String = _measured_schema_validate("L545", owned_pair)
    if not owned_pair_error.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n108_pair_owned_schema_" + owned_pair_error}
    _world = owned_pair
    return {"ok": true, "status": "N108_REAL_EXPLICIT_GATE_PAIR",
        "pair_id": id, "receipt": proposal.get("receipt", {}).duplicate(true),
        "tick": tick}


## Rust N108 RequestGateJump: original linked GateLink, actual position,
## and one source gate fee. This is the ONLY canonical publisher:
## N84/N146 request never moves the ship or changes money itself.
func apply_native_n108_gate_jump(tick: int, ship_id: String,
        from_loc: String, to_loc: String, resolver: RefCounted,
        original_orbits: RefCounted = null) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1 or (
            ship_id.is_empty() or from_loc.is_empty() or to_loc.is_empty()):
        return {"ok": false, "reason": "n108_not_real_ships_apply"}
    if not _world.get("ships", {}).has(ship_id):
        return {"ok": false, "reason": "n108_missing_real_ship"}
    var live: Dictionary = _world["ships"][ship_id]
    if not (live.get("current_bt", null) is Dictionary) or (
            NativeBt.current_action(live["current_bt"]) != "GateJump"):
        return {"ok": false, "reason": "n108_no_current_source_gate_bt"}
    var before_bank: Dictionary = _ledger.snapshot()
    var staged: Dictionary = NativeGateJump.stage(
        _world, before_bank, resolver, ship_id, from_loc, to_loc,
        tick, original_orbits)
    if not staged.get("ok", false):
        return staged
    var future: Dictionary = staged.get("world", {})
    var money: Dictionary = staged.get("ledger_snapshot", {})
    var receipt: Dictionary = staged.get("receipt", {})
    var fee: int = int(staged.get("fee", -1))
    var old_size: int = _world.size()
    if future.size() != old_size + (0 if _world.has(
            "native_gate_jump_receipts") else 1):
        return {"ok": false, "fatal": true, "reason": "n108_unexpected_world_domain"}
    for domain in _world:
        if domain not in ["ships", "facilities", "native_gate_jump_receipts"] and (
                future.get(domain, null) != _world[domain]):
            return {"ok": false, "fatal": true, "reason": "n108_modified_unrelated_world"}
    for sid in _world["ships"]:
        if not future["ships"].has(sid) or (
                str(sid) != ship_id and future["ships"][sid] != _world["ships"][sid]):
            return {"ok": false, "fatal": true, "reason": "n108_moved_other_ship"}
    if future["ships"].size() != _world["ships"].size() or (
            future["facilities"].size() != _world["facilities"].size()):
        return {"ok": false, "fatal": true, "reason": "n108_created_ghost_ship_or_gate"}
    var source_gate: String = str(receipt.get("source_gate_id", ""))
    var destination_gate: String = str(receipt.get("destination_gate_id", ""))
    if not _world["facilities"].has(source_gate) or not (
            _world["facilities"].has(destination_gate)) or source_gate == destination_gate:
        return {"ok": false, "fatal": true, "reason": "n108_fee_has_no_real_gate"}
    for fid in _world["facilities"]:
        if not future["facilities"].has(fid) or (
                str(fid) != source_gate and future["facilities"][fid] != _world["facilities"][fid]):
            return {"ok": false, "fatal": true, "reason": "n108_changed_other_gate_or_station"}
    var old_ship: Dictionary = _world["ships"][ship_id]
    var new_ship: Dictionary = future["ships"][ship_id]
    var allowed_fields: Array = ["credits", "location", "docked_at",
        "position", "system_id", "memory"]
    for field in old_ship:
        if field not in allowed_fields and new_ship.get(field, null) != old_ship[field]:
            return {"ok": false, "fatal": true, "reason": "n108_mutated_other_ship_field"}
    for field in new_ship:
        if not old_ship.has(field) and field not in allowed_fields:
            return {"ok": false, "fatal": true, "reason": "n108_added_fake_ship_component"}
    var expected_memory: Dictionary = old_ship.get("memory", {}).duplicate(true)
    if not (expected_memory.get("recent_systems", null) is Array) or (
            not (new_ship.get("memory", null) is Dictionary)):
        return {"ok": false, "fatal": true, "reason": "n108_invalid_real_gate_memory"}
    expected_memory["recent_systems"] = new_ship["memory"].get(
        "recent_systems", []).duplicate(true)
    if expected_memory != new_ship["memory"] or (
            new_ship["transit"] != old_ship["transit"]):
        return {"ok": false, "fatal": true, "reason": "n108_fabricated_ship_history_or_transit"}
    if str(old_ship.get("location", "")) != from_loc or str(
            new_ship.get("location", "")) != to_loc or str(
            new_ship.get("system_id", "")) != str(receipt.get(
            "destination_system", "")):
        return {"ok": false, "fatal": true, "reason": "n108_unverified_destination"}
    if not (new_ship.get("position", null) is Array) or (
            new_ship["position"] != receipt.get("position", null)):
        return {"ok": false, "fatal": true, "reason": "n108_missing_exact_source_exit_position"}
    if fee < 0 or int(old_ship["credits"]) - int(
            new_ship["credits"]) != fee or int(
            future["facilities"][source_gate]["credits"]) - int(
            _world["facilities"][source_gate]["credits"]) != fee:
        return {"ok": false, "fatal": true, "reason": "n108_source_gate_fee_not_conserved"}
    var op: String = str(receipt.get("operation_id", ""))
    if op.is_empty() or not future.get("native_gate_jump_receipts", {}).has(op) or (
            future["native_gate_jump_receipts"].size() != _world.get(
            "native_gate_jump_receipts", {}).size() + 1):
        return {"ok": false, "fatal": true, "reason": "n108_source_gate_receipt_not_unique"}
    for prior in _world.get("native_gate_jump_receipts", {}):
        if future["native_gate_jump_receipts"].get(prior, null) != _world[
                "native_gate_jump_receipts"][prior]:
            return {"ok": false, "fatal": true, "reason": "n108_rewrote_prior_jump"}
    var required_money_receipt: int = 1 if fee > 0 else 0
    if money.get("receipts", {}).size() != before_bank.get(
            "receipts", {}).size() + required_money_receipt:
        return {"ok": false, "fatal": true, "reason": "n108_wrong_n9_fee_receipt_count"}
    if fee > 0 and not money["receipts"].has(op):
        return {"ok": false, "fatal": true, "reason": "n108_missing_source_gate_paid_receipt"}
    for prior_id in before_bank["receipts"]:
        if money["receipts"].get(prior_id, null) != before_bank["receipts"][prior_id]:
            return {"ok": false, "fatal": true, "reason": "n108_modified_old_bank_history"}
    var original_bank := Ledger.new()
    if not original_bank.restore(money) or original_bank.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n108_real_n9_money_created_or_lost"}
    var err: String = _measured_schema_validate("L661", future)
    if not err.is_empty():
        return {"ok": false, "fatal": true, "reason": "n108_gate_world_" + err}
    var accounts: Dictionary = _measured_schema_accounts("L664", future)
    if accounts.size() != money.get("balances", {}).size():
        return {"ok": false, "fatal": true, "reason": "n108_different_original_n9_wallets"}
    for account in accounts:
        if money["balances"].get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n108_wallet_not_backed_by_real_n9"}
    var owned_jump: Dictionary = _n108_owned_gate_publication(_world,
        future, [source_gate], ship_id, "native_gate_jump_receipts", op)
    if owned_jump.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n108_jump_owned_publication_rejected"}
    var owned_jump_error: String = _measured_schema_validate("L661", owned_jump)
    if not owned_jump_error.is_empty() or (
            _measured_schema_accounts("L664", owned_jump) != accounts):
        return {"ok": false, "fatal": true,
            "reason": "n108_jump_owned_schema_or_accounts_" + owned_jump_error}
    _world = owned_jump
    _ledger = original_bank
    return {"ok": true, "tick": tick, "ship_id": ship_id,
        "source": from_loc, "destination": to_loc, "fee": fee,
        "receipt": receipt.duplicate(true)}


## II-B: publish only detached rows written by N97/N83, never a full
## historical fleet/market/receipt copy. The source proposal has already
## passed the complete Schema/N9 oracle before this function is called.
## Empty result means a rejected ownership boundary, not a no-op World.
static func _n97_n83_owned_physical_publication(original: Dictionary,
        proposed: Dictionary, ship_id: String, changed_rows: Dictionary,
        receipt_id: String, applied: bool) -> Dictionary:
    if proposed.size() != original.size() or not original.get("ships", {}).has(ship_id):
        return {}
    var published: Dictionary = original.duplicate()
    for domain in ["ships", "facilities", "markets", "bodies", "cargo_receipts"]:
        if not (original.get(domain) is Dictionary) or not (proposed.get(domain) is Dictionary):
            return {}
        var old_rows: Dictionary = original[domain]
        var new_rows: Dictionary = proposed[domain]
        var is_receipts: bool = domain == "cargo_receipts"
        if new_rows.size() != old_rows.size() + (1 if is_receipts and applied else 0):
            return {}
        var permitted: Dictionary = changed_rows.get(domain, {})
        var owned: Dictionary = old_rows.duplicate()
        for key in old_rows:
            if not new_rows.has(key) or not (old_rows[key] is Dictionary) or not (new_rows[key] is Dictionary):
                return {}
            if new_rows[key] != old_rows[key]:
                if not permitted.has(str(key)) or is_receipts:
                    return {}
                owned[key] = (new_rows[key] as Dictionary).duplicate(true)
        if is_receipts and applied:
            if old_rows.has(receipt_id) or not new_rows.has(receipt_id) or not (new_rows[receipt_id] is Dictionary):
                return {}
            owned[receipt_id] = (new_rows[receipt_id] as Dictionary).duplicate(true)
        published[domain] = owned
    for domain in original:
        if domain not in ["ships", "facilities", "markets", "bodies", "cargo_receipts"]:
            if not proposed.has(domain) or proposed[domain] != original[domain]:
                return {}
    return published


## Frozen Rust N97 Refuel/Mine single-owner Apply. A genuine N90
## request is processed on detached P1 physical authority; only its
## verified delta may enter this existing N39 World and N9 Ledger.
## Refuel consumes REAL facility private Fuel reserves and optionally
## current Market Fuel with paid credits. Mine consumes ORIGINAL
## celestial body ice richness and adds exactly the mined ship cargo.
## Both persist the ONE N90 result; rejection never creates assets.
func apply_native_n97_ship_service(tick: int, ship_id: String,
        request_id: int, resolver: RefCounted) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1 or (
            ship_id.is_empty() or request_id < 1):
        return {"ok": false, "reason": "n97_service_not_native_ships_phase"}
    var old_world: Dictionary = _world
    var old_bank: Dictionary = _ledger.snapshot()
    var proposal: Dictionary = NativeShipServices.stage(
        old_world, old_bank, resolver, ship_id, request_id, tick)
    if not proposal.get("ok", false):
        return proposal
    var staged: Dictionary = proposal.get("world", {})
    var money: Dictionary = proposal.get("ledger_snapshot", {})
    if not (staged.get("ships") is Dictionary) or not (
            old_world["ships"].has(ship_id)) or (
            staged["ships"].size() != old_world["ships"].size()):
        return {"ok": false, "fatal": true, "reason": "n97_service_changed_fleet"}
    var affected: Array[String] = ["ships", "bodies", "facilities",
        "markets", "cargo_receipts"]
    for key in old_world:
        if key not in affected and staged.get(key, null) != old_world[key]:
            return {"ok": false, "fatal": true, "reason": "n97_service_modified_unrelated_world"}
    var before: Dictionary = old_world["ships"][ship_id]
    var after: Dictionary = staged["ships"][ship_id]
    for sid in old_world["ships"]:
        if not staged["ships"].has(sid) or (
                str(sid) != ship_id and staged["ships"][sid] != old_world["ships"][sid]):
            return {"ok": false, "fatal": true, "reason": "n97_service_mutated_other_ship"}
    var source_kind: String = str(proposal.get("kind", ""))
    var source_status: String = str(proposal.get("status", ""))
    if source_kind not in ["mine", "refuel"] or source_status not in [
            "applied", "rejected"]:
        return {"ok": false, "fatal": true, "reason": "n97_service_invalid_native_outcome"}
    var paid: bool = source_status == "applied" and source_kind == "refuel"
    var mined: bool = source_status == "applied" and source_kind == "mine"
    var receipt_id: String = "n97:service:" + ship_id + ":" + str(request_id)
    if source_status == "rejected":
        if money != old_bank:
            return {"ok": false, "fatal": true, "reason": "n97_rejected_money_modified"}
        for key in ["facilities", "markets", "bodies", "cargo_receipts"]:
            if staged[key] != old_world[key]:
                return {"ok": false, "fatal": true, "reason": "n97_rejected_physics_modified"}
        var accepted_cursor: Dictionary = before.duplicate(true)
        accepted_cursor["transaction"] = after["transaction"].duplicate(true)
        if accepted_cursor != after:
            return {"ok": false, "fatal": true, "reason": "n97_rejected_ship_modified"}
    else:
        if not staged.get("cargo_receipts", {}).has(receipt_id) or (
                staged["cargo_receipts"].size() != old_world.get(
                "cargo_receipts", {}).size() + 1):
            return {"ok": false, "fatal": true, "reason": "n97_missing_unique_physical_receipt"}
        var receipt: Dictionary = staged["cargo_receipts"][receipt_id]
        if str(receipt.get("kind", "")) != "native_n97_" + source_kind or (
                str(receipt.get("ship_id", "")) != ship_id or int(
                receipt.get("request_id", -1)) != request_id):
            return {"ok": false, "fatal": true, "reason": "n97_wrong_original_service_receipt"}
        var permitted: Array[String] = ["transaction", "fuel", "credits",
            "cargo", "cargo_age", "crew_skills", "crew"]
        for field in before:
            if field not in permitted and after.get(field, null) != before[field]:
                return {"ok": false, "fatal": true, "reason": "n97_changed_other_ship_component"}
        for field in after:
            if not before.has(field) and field not in permitted:
                return {"ok": false, "fatal": true, "reason": "n97_added_unauthorized_ship_state"}
        if paid:
            if staged["bodies"] != old_world["bodies"] or (
                    staged["facilities"].size() != old_world["facilities"].size() or
                    staged["markets"].size() != old_world["markets"].size()):
                return {"ok": false, "fatal": true, "reason": "n97_refuel_changed_original_topology"}
            if not (after["cargo"] == before["cargo"]) or (
                    int(after["credits"]) != int(before["credits"]) - int(
                    receipt.get("payment", -1))):
                return {"ok": false, "fatal": true, "reason": "n97_refuel_changed_ice_or_money"}
            for fid in old_world["facilities"]:
                if not staged["facilities"].has(fid):
                    return {"ok": false, "fatal": true, "reason": "n97_refuel_erased_operator"}
                if str(fid) != str(receipt.get("facility_id", "")) and (
                        staged["facilities"][fid] != old_world["facilities"][fid]):
                    return {"ok": false, "fatal": true, "reason": "n97_refuel_changed_other_owner"}
            for loc in old_world["markets"]:
                if not staged["markets"].has(loc) or (
                        str(loc) != str(receipt.get("location", "")) and
                        staged["markets"][loc] != old_world["markets"][loc]):
                    return {"ok": false, "fatal": true, "reason": "n97_refuel_changed_other_market"}
        if mined:
            if staged["facilities"] != old_world["facilities"] or (
                    staged["markets"] != old_world["markets"]) or (
                    int(after["credits"]) != int(before["credits"])):
                return {"ok": false, "fatal": true, "reason": "n97_mine_changed_cash_or_stations"}
            if staged["bodies"].size() != old_world["bodies"].size():
                return {"ok": false, "fatal": true, "reason": "n97_mine_created_celestial_body"}
            for bid in old_world["bodies"]:
                if not staged["bodies"].has(bid) or (
                        str(bid) != str(receipt.get("body_id", "")) and
                        staged["bodies"][bid] != old_world["bodies"][bid]):
                    return {"ok": false, "fatal": true, "reason": "n97_mine_modified_other_deposit"}
            if int(after["cargo"].get("ice", 0)) - int(
                    before["cargo"].get("ice", 0)) != int(
                    receipt.get("quantity", -1)):
                return {"ok": false, "fatal": true, "reason": "n97_mine_created_unbacked_ice"}
    for prior_receipt in old_world.get("cargo_receipts", {}):
        if staged["cargo_receipts"].get(prior_receipt, null) != old_world["cargo_receipts"][prior_receipt]:
            return {"ok": false, "fatal": true, "reason": "n97_edited_prior_physical_receipt"}
    var receipt_delta: int = 1 if paid else 0
    if money.get("receipts", {}).size() != old_bank.get(
            "receipts", {}).size() + receipt_delta:
        return {"ok": false, "fatal": true, "reason": "n97_wrong_n9_payment_receipts"}
    if paid and not money["receipts"].has(receipt_id):
        return {"ok": false, "fatal": true, "reason": "n97_missing_paid_fuel_receipt"}
    for prior_id in old_bank["receipts"]:
        if money["receipts"].get(prior_id, null) != old_bank["receipts"][prior_id]:
            return {"ok": false, "fatal": true, "reason": "n97_tampered_original_n9_receipts"}
    var canonical := Ledger.new()
    if not canonical.restore(money) or canonical.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n97_did_not_conserve_original_n9_cash"}
    var invalid: String = _measured_schema_validate("L799", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n97_schema_" + invalid}
    var accounts: Dictionary = _measured_schema_accounts("L802", staged)
    if accounts.size() != money["balances"].size():
        return {"ok": false, "fatal": true, "reason": "n97_created_or_erased_real_wallet"}
    for account in accounts:
        if money["balances"].get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n97_service_real_n9_wallet_disagreed"}
    var n97_rows: Dictionary = {"ships": {ship_id: true},
        "facilities": {}, "markets": {}, "bodies": {}}
    if paid:
        n97_rows["facilities"][str(staged["cargo_receipts"][receipt_id].get("facility_id", ""))] = true
        n97_rows["markets"][str(staged["cargo_receipts"][receipt_id].get("location", ""))] = true
    if mined:
        n97_rows["bodies"][str(staged["cargo_receipts"][receipt_id].get("body_id", ""))] = true
    var owned_n97: Dictionary = _n97_n83_owned_physical_publication(
        old_world, staged, ship_id, n97_rows, receipt_id, source_status == "applied")
    if owned_n97.is_empty():
        return {"ok": false, "fatal": true, "reason": "n97_owned_publication_rejected"}
    var owned_n97_error: String = _measured_schema_validate("L799-owned", owned_n97)
    if not owned_n97_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n97_owned_schema_" + owned_n97_error}
    _world = owned_n97
    _ledger = canonical
    return {"ok": true, "tick": tick, "status": source_status,
        "ship_id": ship_id, "request_id": request_id, "kind": source_kind,
        "receipt": proposal.get("receipt", {}).duplicate(true),
        "reason": str(proposal.get("reason", ""))}


## Original Rust engine/transactions.rs::buy/sell without a N104
## obligation. Only a genuinely pending N90 RequestShipTransaction
## can pass this guarded N39/N9 single-owner Apply boundary. P1 N97
## performs the authoritative physical market settlement on a staged
## adapter; its result is then reconciled with N9 and N15 receipts.
func apply_native_n83_free_trade(tick: int, ship_id: String,
        request_id: int) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1 or (
            ship_id.is_empty() or request_id < 1):
        return {"ok": false, "reason": "n83_not_real_native_ships_tick"}
    var before_world: Dictionary = _world
    var before_bank: Dictionary = _ledger.snapshot()
    var result: Dictionary = NativeFreeTrade.stage(
        before_world, before_bank, ship_id, request_id, tick)
    if not result.get("ok", false):
        return result
    var next_world: Dictionary = result.get("world", {})
    var next_bank: Dictionary = result.get("ledger_snapshot", {})
    if next_world.size() != before_world.size() or (
            not next_world.get("ships") is Dictionary or
            next_world["ships"].size() != before_world["ships"].size()):
        return {"ok": false, "fatal": true,
            "reason": "n83_changed_single_world_topology"}
    var domains: Array[String] = ["ships", "markets", "facilities", "cargo_receipts"]
    for domain in before_world:
        if domain not in domains and next_world.get(domain, null) != before_world[domain]:
            return {"ok": false, "fatal": true,
                "reason": "n83_changed_unrelated_native_domain"}
    for sid in before_world["ships"]:
        if not next_world["ships"].has(sid):
            return {"ok": false, "fatal": true, "reason": "n83_removed_real_ship"}
        if str(sid) != ship_id and next_world["ships"][sid] != before_world["ships"][sid]:
            return {"ok": false, "fatal": true,
                "reason": "n83_modified_someone_else_ship"}
    var prior: Dictionary = before_world["ships"][ship_id]
    var after: Dictionary = next_world["ships"][ship_id]
    var allowed_ship: Array[String] = ["transaction", "cargo", "cargo_age",
        "cargo_origin", "credits", "crew_skills", "crew", "lifecycle",
        "memory"]
    for field in prior:
        if field not in allowed_ship and after.get(field, null) != prior[field]:
            return {"ok": false, "fatal": true,
                "reason": "n83_changed_unrelated_ship_state"}
    for field in after:
        if not prior.has(field) and field not in allowed_ship:
            return {"ok": false, "fatal": true,
                "reason": "n83_added_phantom_ship_component"}
    var status: String = str(result.get("status", ""))
    var paid: bool = status == "applied"
    if not paid and status != "rejected":
        return {"ok": false, "fatal": true, "reason": "n83_unrecognized_source_result"}
    var receipt_id: String = "n83:ship:" + ship_id + ":" + str(request_id)
    if paid:
        if not next_world.get("cargo_receipts", {}).has(receipt_id) or (
                next_world["cargo_receipts"].size() !=
                before_world.get("cargo_receipts", {}).size() + 1):
            return {"ok": false, "fatal": true,
                "reason": "n83_missing_original_physical_n15_receipt"}
        var detail: Dictionary = next_world["cargo_receipts"][receipt_id]
        var location: String = str(detail.get("location", ""))
        var fid: String = str(detail.get("facility_id", ""))
        if not before_world["markets"].has(location) or not before_world["facilities"].has(fid):
            return {"ok": false, "fatal": true,
                "reason": "n83_paid_unregistered_facility_or_market"}
        var commodity: String = str(detail.get("commodity", ""))
        var direction: int = 1 if str(detail.get("kind", "")) == "native_n97_free_buy" else -1
        var quantity: int = int(detail.get("quantity", 0))
        if quantity < 1 or str(detail.get("kind", "")) not in [
                "native_n97_free_buy", "native_n97_free_sell"]:
            return {"ok": false, "fatal": true,
                "reason": "n83_invalid_original_trade_quantity"}
        if int(after["cargo"].get(commodity, 0)) - int(prior["cargo"].get(commodity, 0)) != direction * quantity:
            return {"ok": false, "fatal": true,
                "reason": "n83_n15_physical_hold_mismatch"}
        if not is_equal_approx(float(next_world["markets"][location]["supply"].get(
                commodity, 0.0)) - float(before_world["markets"][location]["supply"].get(
                commodity, 0.0)), float(-direction * quantity)):
            return {"ok": false, "fatal": true,
                "reason": "n83_unbacked_market_stock_delta"}
        for m in before_world["markets"]:
            if str(m) != location and next_world["markets"].get(m, null) != before_world["markets"][m]:
                return {"ok": false, "fatal": true,
                    "reason": "n83_modified_other_market"}
        for f in before_world["facilities"]:
            if str(f) != fid and next_world["facilities"].get(f, null) != before_world["facilities"][f]:
                return {"ok": false, "fatal": true,
                    "reason": "n83_modified_other_station"}
        var buyer_delta: int = int(next_world["facilities"][fid]["credits"]) - int(
            before_world["facilities"][fid]["credits"])
        var ship_delta: int = int(after["credits"]) - int(prior["credits"])
        if buyer_delta != -ship_delta or absi(ship_delta) != int(detail["payment"]):
            return {"ok": false, "fatal": true,
                "reason": "n83_source_market_money_not_conservative"}
    else:
        for key in ["markets", "facilities", "cargo_receipts"]:
            if next_world[key] != before_world[key]:
                return {"ok": false, "fatal": true,
                    "reason": "n83_rejected_trade_changed_actual_world"}
        var source_copy: Dictionary = prior.duplicate(true)
        source_copy["transaction"] = after.get("transaction", {})
        if source_copy != after:
            return {"ok": false, "fatal": true,
                "reason": "n83_rejection_changed_actual_ship"}
    for existing in before_world.get("cargo_receipts", {}):
        if next_world["cargo_receipts"].get(existing, null) != before_world["cargo_receipts"][existing]:
            return {"ok": false, "fatal": true,
                "reason": "n83_changed_existing_n15_receipt"}
    var restored := Ledger.new()
    if not restored.restore(next_bank) or restored.total() != _ledger.total():
        return {"ok": false, "fatal": true,
            "reason": "n83_original_n9_created_or_lost_money"}
    if next_bank["receipts"].size() != before_bank["receipts"].size() + (1 if paid else 0):
        return {"ok": false, "fatal": true,
            "reason": "n83_wrong_paid_receipt_cardinality"}
    if paid and not next_bank["receipts"].has(receipt_id):
        return {"ok": false, "fatal": true,
            "reason": "n83_no_actual_n9_trade_receipt"}
    for old_receipt in before_bank["receipts"]:
        if next_bank["receipts"].get(old_receipt, null) != before_bank["receipts"][old_receipt]:
            return {"ok": false, "fatal": true,
                "reason": "n83_tampered_original_n9_history"}
    var schema_error: String = _measured_schema_validate("L937", next_world)
    if not schema_error.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n83_single_world_schema_" + schema_error}
    var accounts: Dictionary = _measured_schema_accounts("L941", next_world)
    if accounts.size() != next_bank["balances"].size():
        return {"ok": false, "fatal": true,
            "reason": "n83_fabricated_native_wallet"}
    for account in accounts:
        if next_bank["balances"].get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true,
                "reason": "n83_true_n9_balance_mismatch"}
    var n83_rows: Dictionary = {"ships": {ship_id: true},
        "facilities": {}, "markets": {}, "bodies": {}}
    if paid:
        n83_rows["facilities"][str(next_world["cargo_receipts"][receipt_id].get("facility_id", ""))] = true
        n83_rows["markets"][str(next_world["cargo_receipts"][receipt_id].get("location", ""))] = true
    var owned_n83: Dictionary = _n97_n83_owned_physical_publication(
        before_world, next_world, ship_id, n83_rows, receipt_id, paid)
    if owned_n83.is_empty():
        return {"ok": false, "fatal": true, "reason": "n83_owned_publication_rejected"}
    var owned_n83_error: String = _measured_schema_validate("L937-owned", owned_n83)
    if not owned_n83_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n83_owned_schema_" + owned_n83_error}
    _world = owned_n83
    _ledger = restored
    return {"ok": true, "status": status, "tick": tick,
        "ship_id": ship_id, "request_id": request_id,
        "receipt": result.get("receipt", {}).duplicate(true),
        "reason": str(result.get("reason", ""))}


## Rust N148 behavior.rs lifecycle runs once on the EXISTING N158 ships
## phase after N14 and N84 planning, but BEFORE their paid N97 Apply. This stage
## cannot alter money, cargo, BT, goals, stations or the ship roster.
## N146 DecommissionShip commands are returned to the sole N158 Apply,
## never executed from this state transition.
func apply_native_n148_ship_lifecycle(tick: int, multiplier: int,
        n140_fired: Dictionary) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or multiplier < 1:
        return {"ok": false, "reason": "n148_not_authoritative_ships_phase"}
    if not (_world.get("ships") is Dictionary):
        return {"ok": true, "changed": false, "commands": [],
            "advanced": [], "tick": tick}
    var candidate: Dictionary = NativeN148.stage(_world, tick, multiplier, n140_fired)
    if not candidate.get("ok", false):
        return candidate
    var new_ships: Dictionary = candidate["ships"]
    var before: Dictionary = _world["ships"]
    if before.size() != new_ships.size():
        return {"ok": false, "fatal": true, "reason": "n148_ship_cardinality_modified"}
    var allowed: Dictionary = {}
    for sid in before:
        if not new_ships.has(sid):
            return {"ok": false, "fatal": true, "reason": "n148_removed_ship_in_lifecycle"}
        var prior: Dictionary = before[sid]
        var next: Dictionary = new_ships[sid]
        var copy: Dictionary = prior.duplicate(true)
        if not (next.get("lifecycle", null) is Dictionary):
            return {"ok": false, "fatal": true, "reason": "n148_missing_real_lifecycle"}
        if not NativeShipLifecycle._valid_lifecycle(next["lifecycle"]):
            return {"ok": false, "fatal": true, "reason": "n148_invalid_strike_change"}
        copy["lifecycle"] = next["lifecycle"].duplicate(true)
        if copy != next:
            return {"ok": false, "fatal": true, "reason": "n148_changed_non_lifecycle_field"}
        allowed[sid] = copy
    # Lifecycle preview rebuilt each ship independently, so the owned
    # fleet is detached; copy the World header, not unrelated histories.
    var updated: Dictionary = _copy_world("L993", false)
    updated["ships"] = allowed
    var validation: String = _measured_schema_validate("L995", updated)
    if not validation.is_empty():
        return {"ok": false, "fatal": true, "reason": "n148_world_" + validation}
    var balances: Dictionary = _measured_schema_accounts("L998", updated)
    var old_bank: Dictionary = _ledger.balances_snapshot()
    if balances.size() != old_bank.size():
        return {"ok": false, "fatal": true, "reason": "n148_changed_wallet_count"}
    for account in balances:
        if old_bank.get(account, null) != balances[account]:
            return {"ok": false, "fatal": true, "reason": "n148_changed_source_money"}
    # Mutating exactly one physical ship domain, with immutable N9
    # balances and unchanged native BT, respects one World authority.
    _world = updated
    return {"ok": true, "tick": tick,
        "changed": candidate.get("changed", false),
        "commands": candidate.get("commands", []).duplicate(true),
        "advanced": candidate.get("advanced", []).duplicate(true)}


## Rust ship/mod.rs::observe_prices (Pass 2, after N14 motion and
## before N149 crew). Only the real per-ship ShipMemory may change;
## actual markets/price history, N104, N9 wallets and N14 remain frozen.
## II-B: stage only changed ship rows. A candidate from a source module is
## not authoritative until Schema and N9 accept it; deep-detach every changed
## row so nested memory/crew/cargo cannot alias the source proposal or World.
## Unchanged rows remain read-only shared entries in the unpublished stage.
static func _owned_fleet_publication_stage(world: Dictionary,
        proposed_ships: Dictionary, allowed: Dictionary) -> Dictionary:
    if not (world.get("ships") is Dictionary):
        return {}
    var current: Dictionary = world["ships"]
    if proposed_ships.size() != current.size():
        return {}
    var staged: Dictionary = world.duplicate()
    var owned_ships: Dictionary = current.duplicate()
    for sid in current:
        if not proposed_ships.has(sid) or not (current[sid] is Dictionary) or not (proposed_ships[sid] is Dictionary):
            return {}
        if proposed_ships[sid] != current[sid]:
            if not allowed.has(sid):
                return {}
            owned_ships[sid] = (proposed_ships[sid] as Dictionary).duplicate(true)
    staged["ships"] = owned_ships
    return staged


func apply_native_ship_price_observation(tick: int, resolver: RefCounted,
        fired: Dictionary) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick + 1:
        return {"ok": false, "reason": "n150_price_observation_not_ship_phase"}
    var candidate: Dictionary = NativeShipPrices.stage(_world, resolver, tick, fired)
    if not candidate.get("ok", false):
        return candidate
    var updated_ships: Dictionary = candidate.get("ships", {})
    if updated_ships.size() != _world.get("ships", {}).size():
        return {"ok": false, "fatal": true, "reason": "n150_price_changed_ship_roster"}
    for sid in _world["ships"]:
        if not updated_ships.has(sid):
            return {"ok": false, "fatal": true, "reason": "n150_price_removed_ship"}
        var original: Dictionary = _world["ships"][sid]
        var observed: Dictionary = updated_ships[sid]
        if not fired.has(sid):
            if original != observed:
                return {"ok": false, "fatal": true, "reason": "n150_changed_sleeping_ship"}
            continue
        var permitted: Dictionary = original.duplicate(true)
        if observed.has("memory"):
            permitted["memory"] = observed["memory"].duplicate(true)
        if observed != permitted:
            return {"ok": false, "fatal": true, "reason": "n150_modified_nonmemory_ship_component"}
    if not candidate.get("changed", false):
        return {"ok": true, "tick": tick, "changed": false,
            "observed": candidate.get("observed", []).duplicate(true),
            "active_count": int(candidate.get("active_count", 0))}
    # N150 touches only ShipMemory; other domains are read-only and the
    # proposed fleet is detached before the authoritative validation.
    var next_world: Dictionary = _owned_fleet_publication_stage(_world, updated_ships, fired)
    if next_world.is_empty():
        return {"ok": false, "fatal": true, "reason": "n150_invalid_owned_fleet_stage"}
    var invalid: String = _measured_schema_validate("L1049", next_world)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n150_invalid_native_memory_" + invalid}
    # Price observation cannot add a receipt or change N9. Inspect only
    # detached wallet balances, not the entire growing immutable journal.
    var bank: Dictionary = _ledger.balances_snapshot()
    var accounts: Dictionary = _measured_schema_accounts("L1055", next_world)
    if accounts.size() != bank.size():
        return {"ok": false, "fatal": true, "reason": "n150_modified_n9_wallet_roster"}
    for account in accounts:
        if bank.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n150_modified_actual_credit_balance"}
    _world = next_world
    return {"ok": true, "tick": tick, "changed": true,
        "observed": candidate.get("observed", []).duplicate(true),
        "active_count": int(candidate.get("active_count", 0))}


## Frozen Rust engine/apply.rs::SimCommand::GrantCrewXp. This
## privileged call requires a genuine typed N146 command from the
## existing N84 executor. No unconditional per-tick XP or fake mission.
## The original ShipCrewSkills is in the one N39 ship record; immutable
## receipt keeps N38 replay deterministic without a second XP wallet.
## N128 append-only receipt stage. Do not mutate existing receipt rows:
## they remain shared until the full Schema/accounts oracle accepts the stage.
## The caller must not publish the stage or leak its registries on rejection.
static func _n128_owned_grant_stage(world: Dictionary, ship_id: String,
        skills: Dictionary) -> Dictionary:
    var stage: Dictionary = world.duplicate()
    stage["ships"] = world["ships"].duplicate()
    var ship: Dictionary = world["ships"][ship_id].duplicate(true)
    ship["crew_skills"] = skills.duplicate(true)
    stage["ships"][ship_id] = ship
    stage["native_crew_xp_receipts"] = world.get(
        "native_crew_xp_receipts", {}).duplicate()
    return stage


func apply_native_n128_crew_xp(tick: int, source_command: Dictionary,
        command_ordinal: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick + 1 or command_ordinal < 1:
        return {"ok": false, "reason": "n128_not_native_ship_apply"}
    if str(source_command.get("kind", "")) != "GrantCrewXp":
        return {"ok": false, "reason": "n128_not_source_skill_command"}
    var ship_id: String = str(source_command.get("ship", ""))
    var skill: String = str(source_command.get("skill", ""))
    var amount: Variant = source_command.get("amount", null)
    if N146Commands.make_command("GrantCrewXp", source_command).is_empty() or (
            ship_id.is_empty() or not _world.get("ships", {}).has(ship_id) or
            typeof(amount) != TYPE_INT or int(amount) < 0 or int(amount) > 255):
        return {"ok": false, "reason": "n128_invalid_real_skill_actor"}
    if not NativeCrewXp.DEFAULTS.has(skill):
        # Native Rust ShipCrewSkills::grant unknown skill is a no-op.
        return {"ok": true, "status": "source_unknown_skill_noop",
            "ship_id": ship_id, "skill": skill, "amount": 0}
    var before: Dictionary = _world["ships"][ship_id]
    if not (before.get("crew_skills") is Dictionary):
        return {"ok": false, "reason": "n128_missing_original_ship_crew_skills"}
    var receipt_id: String = "n128:crew:" + str(tick) + ":" + str(command_ordinal)
    if _world.get("native_crew_xp_receipts", {}).has(receipt_id):
        return {"ok": false, "reason": "n128_duplicate_real_n146_command"}
    var outcome: Dictionary = NativeCrewXp.grant(
        before["crew_skills"], skill, int(amount))
    if not outcome.get("ok", false):
        return {"ok": false, "reason": "n128_source_grant_refused"}
    var credited: int = int(outcome["skills"][skill]) - int(before["crew_skills"][skill])
    if credited < 0 or credited > int(amount):
        return {"ok": false, "fatal": true, "reason": "n128_skill_grant_overflow"}
    # N128 owns only the ship skill record and its immutable receipt map.
    # Detach both domains before mutation; unrelated World history stays shared
    # only inside this private, unpublished stage (never returned to callers).
    if _world.has("native_crew_xp_receipts") and (
            not (_world["native_crew_xp_receipts"] is Dictionary)):
        return {"ok": false, "fatal": true, "reason": "n128_corrupt_prior_receipts"}
    # Existing receipt rows are immutable append-only provenance. Detach the
    # registry root, not its entire growing history; the new receipt is owned
    # by this unpublished stage. Ship data is independently row-detached.
    var stage: Dictionary = _n128_owned_grant_stage(
        _world, ship_id, outcome["skills"])
    stage["native_crew_xp_receipts"][receipt_id] = {
        "id": receipt_id, "tick": tick, "ship_id": ship_id,
        "skill": skill, "amount": int(amount), "applied": credited,
        "source": "N146:GrantCrewXp"}
    var invalid: String = _measured_schema_validate("L1112", stage)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n128_world_" + invalid}
    var accounts: Dictionary = _measured_schema_accounts("L1115", stage)
    var bank: Dictionary = _ledger.balances_snapshot()
    if accounts.size() != bank.size():
        return {"ok": false, "fatal": true, "reason": "n128_changed_n9_wallet_roster"}
    for account in accounts:
        if bank.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n128_changed_n9_credit"}
    _world = stage
    return {"ok": true, "ship_id": ship_id, "skill": skill,
        "amount": int(amount), "applied": credited, "receipt": receipt_id}


## Rust ship/mod.rs::tick_ships Pass 3, once per actual N140 fire.
## ShipCrew welfare, real N15 hold Food and actual N9 wage outflow
## settle in ONE N39 atomic commit, before N84 BT/command execution.
## Native Crew.wages_credits is nonspendable historical savings, NOT a
## wallet that could mint or spend a second set of credits.
func apply_native_n149_ship_crew(tick: int, tick_scale: float,
        multiplier: int, n140_fired: Dictionary) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "n149_not_native_ship_phase"}
    var before_world: Dictionary = _world
    var legacy: bool = OS.get_environment("LS_LATE_CREW_LEGACY") == "1"
    var before_bank: Dictionary = _ledger.snapshot() if legacy else {}
    var result: Dictionary
    if legacy:
        result = NativeN149Crew.stage(before_world, before_bank,
            tick, tick_scale, multiplier, n140_fired)
    else:
        result = NativeN149Crew.stage_owned(before_world, _ledger,
            tick, tick_scale, multiplier, n140_fired)
    if not result.get("ok", false):
        return result
    var after_ships: Dictionary = result["ships"]
    if after_ships.size() != before_world.get("ships", {}).size():
        return {"ok": false, "fatal": true, "reason": "n149_changed_native_ship_roster"}
    for sid in before_world["ships"]:
        if not after_ships.has(sid):
            return {"ok": false, "fatal": true, "reason": "n149_removed_actual_ship"}
        var original: Dictionary = before_world["ships"][sid]
        var updated: Dictionary = after_ships[sid]
        if not n140_fired.has(sid):
            if updated != original:
                return {"ok": false, "fatal": true, "reason": "n149_mutated_sleeping_ship"}
            continue
        var compare: Dictionary = original.duplicate(true)
        for field in ["crew", "credits", "cargo", "cargo_age",
                "crew_efficiency"]:
            if updated.has(field):
                compare[field] = updated[field]
            else:
                compare.erase(field)
        if compare != updated:
            return {"ok": false, "fatal": true, "reason": "n149_changed_unrelated_ship_field"}
    # Crew wages settle in a separate staged Ledger, while the World
    # proposal modifies only ships. No unrelated World domain is written
    # before Schema and N9 consistency checks complete.
    var next_world: Dictionary = _owned_fleet_publication_stage(before_world, after_ships, n140_fired)
    if next_world.is_empty():
        return {"ok": false, "fatal": true, "reason": "n149_invalid_owned_fleet_stage"}
    var invalid: String = _measured_schema_validate("L1168", next_world)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n149_schema_" + invalid}
    var staged_ledger: RefCounted
    if legacy:
        staged_ledger = Ledger.new()
        if not staged_ledger.restore(result["ledger_snapshot"]):
            return {"ok": false, "fatal": true, "reason": "n149_invalid_single_n9_receipts"}
    else:
        staged_ledger = result["owned_ledger"]
    var new_balances: Dictionary = staged_ledger.balances_snapshot()
    var wages: int = int(result.get("wages_total", -1))
    if wages < 0 or staged_ledger.total() != _ledger.total() - wages:
        return {"ok": false, "fatal": true, "reason": "n149_wage_total_not_source_accrual"}
    var due_receipts: int = 0
    for record in result.get("records", []):
        if int(record.get("wages", 0)) > 0:
            due_receipts += 1
            var wage_id: String = "n149:crew:" + str(record["ship_id"]) + ":" + str(tick)
            var receipt: Variant = staged_ledger.receipt_copy(wage_id)
            if not (receipt is Dictionary) or str(receipt.get("kind", "")) != "native_ship_crew_wages" or int(receipt.get("wages_credits_accrued", -1)) != int(record["wages"]):
                return {"ok": false, "fatal": true, "reason": "n149_missing_native_paid_crew_evidence"}
    if staged_ledger.receipt_count() != _ledger.receipt_count() + due_receipts:
        return {"ok": false, "fatal": true, "reason": "n149_expected_wage_receipts_missing"}
    if legacy:
        if not _ledger.retains_receipts(result["ledger_snapshot"]["receipts"]):
            return {"ok": false, "fatal": true, "reason": "n149_mutated_existing_n9_receipt"}
    elif not staged_ledger.retains_owned_receipts(_ledger):
        return {"ok": false, "fatal": true, "reason": "n149_mutated_existing_n9_receipt"}
    var accounts: Dictionary = _measured_schema_accounts("L1191", next_world)
    if accounts.size() != new_balances.size():
        return {"ok": false, "fatal": true, "reason": "n149_added_unauthorized_wallet"}
    for account in accounts:
        if new_balances.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n149_n9_ship_wallet_mismatch"}
    _world = next_world
    _ledger = staged_ledger
    return {"ok": true, "tick": tick,
        "fired_count": int(result.get("fired_count", 0)),
        "wages_total": wages,
        "food_consumed": int(result.get("food_consumed", 0)),
        "records": result.get("records", []).duplicate(true)}


## Original Rust N21: source FIFO FacilityStorage dock_queue + dock fee.
## This is the ONLY paid N21 Apply. A source proposal cannot publish
## facilities, ships or N9 by itself. N38 owns snapshot of these fields.
## Optional diagnostic only; no timing work or branching of native
## economy when LS_PROFILE_NATIVE_PHASES is disabled.
func _commit_native_n21(proposal: Dictionary, owned: RefCounted = null) -> Dictionary:
    # Explicit callers may opt into stale-proposal prevention; the original
    # Rust N21 staged apply (without expected_n21_version) is untouched.
    if proposal.has("expected_n21_version") and (
            typeof(proposal["expected_n21_version"]) != TYPE_INT or
            int(proposal["expected_n21_version"]) != n21_write_version()):
        return {"ok": false, "reason": "n21_stale_write_version"}
    if not _profile_copy_enabled:
        var original: Dictionary = _commit_native_n21_unprofiled(proposal, owned)
        if original.get("ok", false):
            _n21_commit_generation += 1
        return original
    var shadow_error: String = ""
    if proposal.get("ok", false) and proposal.get("world") is Dictionary and (
            proposal.get("ledger_snapshot") is Dictionary):
        shadow_error = DockDeltaValidator.validate_delta(
            _world, proposal["world"], proposal["ledger_snapshot"])
        _n21_shadow_checks += 1
    var began: int = Time.get_ticks_usec()
    var outcome: Dictionary = _commit_native_n21_unprofiled(proposal, owned)
    _profile_n21_commit_calls += 1
    _profile_n21_commit_usec += maxi(0, Time.get_ticks_usec() - began)
    # A local validator is never allowed to change original N21 refusal
    # reasons. An oracle-approved stage rejected by local rules is recorded
    # as a shadow mismatch, not refused.
    if outcome.get("ok", false):
        if not shadow_error.is_empty():
            _n21_shadow_false_rejections += 1
            _n21_shadow_last_error = shadow_error
        _n21_commit_generation += 1
    return outcome

## Called ONLY after the complete N21 Schema, N9 and dock delta oracles.
## Copy roots and changed rows; retain authoritative unchanged rows rather
## than cloning the ever-growing fleet, facilities and paid receipt archive.
## New/changed proposal rows are detached recursively before publication.
static func _n21_owned_commit_rows(source: Dictionary,
        proposed: Dictionary) -> Dictionary:
    for domain in ["ships", "facilities", "dock_receipts"]:
        if not (source.get(domain) is Dictionary) or not (
                proposed.get(domain) is Dictionary):
            return {}
    if source["ships"].size() != proposed["ships"].size() or (
            source["facilities"].size() != proposed["facilities"].size()) or (
            proposed["dock_receipts"].size() < source["dock_receipts"].size()):
        return {}
    var committed: Dictionary = source.duplicate()
    for domain in ["ships", "facilities"]:
        var rows: Dictionary = source[domain].duplicate()
        for id in source[domain]:
            if not proposed[domain].has(id) or not (
                    source[domain][id] is Dictionary) or not (
                    proposed[domain][id] is Dictionary):
                return {}
            if proposed[domain][id] != source[domain][id]:
                rows[id] = proposed[domain][id].duplicate(true)
        committed[domain] = rows
    var receipts: Dictionary = source["dock_receipts"].duplicate()
    for id in source["dock_receipts"]:
        if not proposed["dock_receipts"].has(id) or (
                proposed["dock_receipts"][id] != source["dock_receipts"][id]):
            return {}
    for id in proposed["dock_receipts"]:
        if not source["dock_receipts"].has(id):
            if not (proposed["dock_receipts"][id] is Dictionary):
                return {}
            receipts[id] = proposed["dock_receipts"][id].duplicate(true)
    committed["dock_receipts"] = receipts
    return committed

func _commit_native_n21_unprofiled(proposal: Dictionary, owned: RefCounted = null) -> Dictionary:
    if not proposal.get("ok", false) or not (proposal.get("world") is Dictionary) or (
            (owned == null and not (proposal.get("ledger_snapshot") is Dictionary))):
        return {"ok": false, "reason": "n21_invalid_staged_source_world"}
    if owned != null and not is_same(proposal.get("ledger_snapshot"), owned):
        return {"ok": false, "reason": "n21_invalid_owned_transaction"}
    var future: Dictionary = proposal["world"]
    var money: Dictionary = proposal["ledger_snapshot"] if owned == null else {
        "balances": owned.balances_snapshot(), "receipts": {}}
    if owned != null:
        # The provenance validator needs only NEW dock payment IDs. Existing
        # N9 history is proved independently by immutable COW retention below.
        for op in future.get("dock_receipts", {}):
            if not _world.get("dock_receipts", {}).has(op) and owned.has_receipt(str(op)):
                money["receipts"][op] = owned.receipt_copy(str(op))
    if future.size() != _world.size():
        return {"ok": false, "reason": "n21_changed_world_domain"}
    for key in _world:
        if key not in ["ships", "facilities", "dock_receipts"] and (
                future.get(key, null) != _world[key]):
            return {"ok": false, "reason": "n21_modified_unrelated_domain"}
    if future.get("ships", {}).size() != _world.get("ships", {}).size() or (
            future.get("facilities", {}).size() != _world.get("facilities", {}).size()):
        return {"ok": false, "reason": "n21_modified_canonical_entities"}
    for ship_id in _world["ships"]:
        var before: Dictionary = _world["ships"][ship_id]
        var after: Dictionary = future["ships"].get(ship_id, {})
        if after.is_empty():
            return {"ok": false, "reason": "n21_removed_original_ship"}
        # Only three top-level ship fields are permitted. A shallow
        # comparison mask is sufficient: never edit any nested component.
        var expected: Dictionary = before.duplicate()
        for field in ["credits", "docked_at", "dock_attempt_start_tick"]:
            if after.has(field):
                expected[field] = after[field]
            elif field == "dock_attempt_start_tick" and before.has(field):
                return {"ok": false, "reason": "n21_erased_attempt_cursor"}
        if after != expected:
            return {"ok": false, "reason": "n21_mutated_other_ship_component"}
    for fid in _world["facilities"]:
        var previous: Dictionary = _world["facilities"][fid]
        var next: Dictionary = future["facilities"].get(fid, {})
        if next.is_empty():
            return {"ok": false, "reason": "n21_removed_original_facility"}
        # FIFO is a replacement value, not mutated through this mask.
        var allowed: Dictionary = previous.duplicate()
        for field in ["credits", "dirty", "dock_queue"]:
            if next.has(field):
                allowed[field] = next[field]
            elif field == "dock_queue" and previous.has(field):
                return {"ok": false, "reason": "n21_erased_original_fifo"}
        if next != allowed:
            return {"ok": false, "reason": "n21_modified_other_facility_component"}
    if not (future.get("dock_receipts") is Dictionary) or (
            future["dock_receipts"].size() < _world.get("dock_receipts", {}).size()):
        return {"ok": false, "reason": "n21_lost_original_dock_receipts"}
    for op in _world.get("dock_receipts", {}):
        if future["dock_receipts"].get(op, null) != _world["dock_receipts"][op]:
            return {"ok": false, "reason": "n21_rewrote_paid_dock_receipt"}
    var checked: RefCounted = Ledger.new() if owned == null else owned
    if (owned == null and not checked.restore(money)) or checked.total() != _ledger.total():
        return {"ok": false, "reason": "n21_ledger_money_not_conservative"}
    # The external proposal is still validated by checked.restore().
    # Compare EVERY previous immutable N9 receipt in-place instead of
    # duplicating the old history only to inspect it for equality.
    if not (money.get("receipts") is Dictionary) or checked.receipt_count() < _ledger.receipt_count():
        return {"ok": false, "reason": "n21_paid_receipt_missing"}
    if (owned == null and not _ledger.retains_receipts(money["receipts"])) or (
            owned != null and not checked.retains_owned_receipts(_ledger)):
        return {"ok": false, "reason": "n21_replayed_or_edited_n9_receipt"}
    var schema_error: String = _measured_schema_validate("L1281", future)
    if not schema_error.is_empty():
        return {"ok": false, "reason": "n21_schema_" + schema_error}
    var expected_balances: Dictionary = _measured_schema_accounts("L1284", future)
    if expected_balances.size() != money.get("balances", {}).size():
        return {"ok": false, "reason": "n21_noncanonical_account_count"}
    for key in expected_balances:
        if money["balances"].get(key, null) != expected_balances[key]:
            return {"ok": false, "reason": "n21_wallet_did_not_match_source_n9"}
    # Narrow additional proof only AFTER original Schema, complete ledger
    # restore/retention and exact account audits. Thus every refusal that
    # the previous source rejected still keeps its original reason. Only
    # forged previously-unchecked new N21 receipt provenance is rejected.
    # N21's old Schema/ledger checks have already proved occupancy,
    # FIFO and retention. The new narrow proof is only required if this
    # transition actually ADDS a dock receipt: scanning the old append-only
    # archive again on the common no-new-receipt path adds quadratic work.
    if future["dock_receipts"].size() > _world.get("dock_receipts", {}).size():
        var n21_proof: String = DockDeltaValidator.validate_delta(_world,
            future, money)
        if not n21_proof.is_empty():
            return {"ok": false, "reason": "n21_local_" + n21_proof}
    # Explicit N21 write set: only ships/facilities/paid dock receipts
    # can change. The full future has already passed every old domain,
    # FIFO/receipt and N39/N9 guard above. Retain canonical references
    # for unrelated domains, and deep-detach every changed domain from
    # the external proposal before atomic World + Ledger publication.
    var committed: Dictionary = _n21_owned_commit_rows(_world, future)
    if committed.is_empty():
        return {"ok": false, "reason": "n21_invalid_owned_publication"}
    _world = committed
    _ledger = checked.fork() if owned != null else checked
    return {"ok": true, "status": str(proposal.get("status", "")),
        "changed": bool(proposal.get("changed", false)),
        "receipt": proposal.get("receipt", {}).duplicate(true),
        "events": proposal.get("events", []).duplicate(true)}

func apply_native_n21_request(tick: int, ship_id: String,
        location: String, operation: String,
        preferred_type: String = "", preferred_id: String = "") -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "n21_not_current_single_ship_phase"}
    var owned: RefCounted = null if OS.get_environment("LS_LATE_DOCK_LEGACY") == "1" else _ledger.fork()
    var bank: Variant = _ledger.snapshot() if owned == null else owned
    var proposed: Dictionary = {}
    if operation == "dock":
        proposed = N21Source.request(_world, bank, ship_id,
            location, tick, preferred_type, preferred_id)
    elif operation == "undock":
        proposed = N21Source.release(_world, bank,
            ship_id, location, tick)
    else:
        return {"ok": false, "reason": "n21_unknown_source_dock_action"}
    # An ordinary N21 source refusal is not a malformed or half-published
    # World. Preserve the original reason for N84 replan/diagnostics and
    # do not pass an unsuccessful proposal into the paid commit gate.
    if not proposed.get("ok", false):
        return proposed
    return _commit_native_n21(proposed, owned)

## Manual UI Dock is an explicit command in the current committed
## native tick, not an arbitrary N15 cargo transfer. No free port may
## bypass N9; an occupied FIFO line cannot be skipped by an out-of-tick
## UI click. Unlike N84, a manual caller has no persisted Dock BT, so
## a full port REJECTS instead of inserting a phantom waiting ship.
func apply_native_n21_manual_dock(tick: int, ship_id: String,
        location: String) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick:
        return {"ok": false, "reason": "n21_manual_not_a_committed_native_tick"}
    var source: Dictionary = N21Source.request(
        _world, _ledger.snapshot(), ship_id, location, tick)
    if not source.get("ok", false):
        return source
    if str(source.get("status", "")) != "docked" or (
            not (source.get("receipt", null) is Dictionary)):
        # No second persistent manual queue or invented dock BT.
        # A paid N21 slot is required on THIS committed tick.
        return {"ok": false, "reason": "n21_manual_no_free_paid_slot",
            "status": str(source.get("status", "blocked"))}
    return _commit_native_n21(source)

func apply_native_n21_dock_queue(tick: int) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "n21_not_original_dock_queue_phase"}
    var owned: RefCounted = null if OS.get_environment("LS_LATE_DOCK_LEGACY") == "1" else _ledger.fork()
    var bank: Variant = _ledger.snapshot() if owned == null else owned
    return _commit_native_n21(N21Source.advance(_world, bank, tick), owned)


## Frozen Rust SimCommand::ReleaseContract (N146) is applied AFTER
## N84 ship intent was saved. Only accepted+matching fulfiller may
## return to Posted; N9 reserved escrow and all real N15 cargo remain.
## N39 is the ONLY publisher. No parallel Board/ledger/ship registry.
## N104 release is a bounded mutation: only the releasing ship, one paid
## contract, and changed diplomatic rows may be published. Keep untouched
## growing registries read-only; detach all changed nested containers.
## Called only AFTER the full source Schema/N9/contract write-set oracle.
static func _n104_owned_release_publication(before: Dictionary,
        proposed: Dictionary, ship_id: String, contract_id: String) -> Dictionary:
    for domain in ["ships", "contract_board", "faction_relations"]:
        if not (before.get(domain) is Dictionary) or not (
                proposed.get(domain) is Dictionary):
            return {}
    var old_ships: Dictionary = before["ships"]
    var new_ships: Dictionary = proposed["ships"]
    if not old_ships.has(ship_id) or not new_ships.has(ship_id) or (
            not (new_ships[ship_id] is Dictionary)) or (
            old_ships.size() != new_ships.size()):
        return {}
    for id in old_ships:
        if not new_ships.has(id) or not (new_ships[id] is Dictionary) or (
                str(id) != ship_id and new_ships[id] != old_ships[id]):
            return {}
    var old_board: Dictionary = before["contract_board"]
    var new_board: Dictionary = proposed["contract_board"]
    if not (old_board.get("contracts") is Dictionary) or not (
            new_board.get("contracts") is Dictionary):
        return {}
    var old_contracts: Dictionary = old_board["contracts"]
    var new_contracts: Dictionary = new_board["contracts"]
    if not old_contracts.has(contract_id) or not (
            new_contracts.get(contract_id) is Dictionary) or (
            old_contracts.size() != new_contracts.size()):
        return {}
    for id in old_contracts:
        if not new_contracts.has(id) or not (new_contracts[id] is Dictionary) or (
                str(id) != contract_id and new_contracts[id] != old_contracts[id]):
            return {}
    if old_board.size() != new_board.size():
        return {}
    for key in old_board:
        if not new_board.has(key):
            return {}
    var published: Dictionary = before.duplicate()
    var ships: Dictionary = old_ships.duplicate()
    ships[ship_id] = (new_ships[ship_id] as Dictionary).duplicate(true)
    published["ships"] = ships
    var board: Dictionary = old_board.duplicate()
    var contracts: Dictionary = old_contracts.duplicate()
    contracts[contract_id] = (new_contracts[contract_id] as Dictionary).duplicate(true)
    board["contracts"] = contracts
    for key in old_board:
        if key != "contracts" and new_board[key] != old_board[key]:
            if new_board[key] is Dictionary or new_board[key] is Array:
                board[key] = new_board[key].duplicate(true)
            else:
                board[key] = new_board[key]
    published["contract_board"] = board
    var old_relations: Dictionary = before["faction_relations"]
    var new_relations: Dictionary = proposed["faction_relations"]
    var relations: Dictionary = old_relations.duplicate()
    for key in old_relations:
        if not new_relations.has(key):
            return {}
    for key in new_relations:
        if not old_relations.has(key) or new_relations[key] != old_relations[key]:
            if new_relations[key] is Dictionary or new_relations[key] is Array:
                relations[key] = new_relations[key].duplicate(true)
            else:
                relations[key] = new_relations[key]
    published["faction_relations"] = relations
    return published


func apply_native_n104_release_contract(tick: int, ship_id: String,
        contract_id: String, reason: String) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "fatal": true,
            "reason": "n104_release_not_native_ship_phase"}
    if not _world.get("ships", {}).has(ship_id) or str(_world[
            "ships"][ship_id].get("planning_source", "")) != (
            "n104_pending_release_on_bt_failure"):
        return {"ok": false, "fatal": true,
            "reason": "n104_release_not_from_real_n84_failure"}
    var candidate: Dictionary = NativeN104Release.stage(
        _world, tick, ship_id, contract_id, reason)
    if not candidate.get("ok", false):
        return {"ok": false, "fatal": true,
            "reason": str(candidate.get("reason", "n104_source_release_rejected"))}
    if not candidate.get("changed", false):
        return {"ok": true, "status": "GUARDED_NO_OP", "changed": false}
    var next: Dictionary = candidate["world"]
    if next.size() != _world.size():
        return {"ok": false, "fatal": true,
            "reason": "n104_release_changed_world_domain"}
    for key in _world:
        if key not in ["ships", "contract_board", "faction_relations"] and (
                next.get(key, null) != _world[key]):
            return {"ok": false, "fatal": true,
                "reason": "n104_release_modified_unrelated_domain"}
    var old_board: Dictionary = _world["contract_board"]
    var updated: Dictionary = next["contract_board"]
    if updated.get("version") != old_board.get("version") or (
            updated.get("receipt_claims") != old_board.get("receipt_claims") or
            updated.get("contracts", {}).size() != old_board.get(
                "contracts", {}).size()):
        return {"ok": false, "fatal": true,
            "reason": "n104_release_changed_historical_contracts"}
    for id in old_board["contracts"]:
        if str(id) != contract_id and updated["contracts"].get(id, null) != (
                old_board["contracts"][id]):
            return {"ok": false, "fatal": true,
                "reason": "n104_release_modified_other_paid_contract"}
    for id in _world["ships"]:
        if str(id) != ship_id and next["ships"].get(id, null) != (
                _world["ships"][id]):
            return {"ok": false, "fatal": true,
                "reason": "n104_release_modified_other_ship"}
    var old_ship: Dictionary = _world["ships"][ship_id]
    var new_ship: Dictionary = next["ships"][ship_id]
    var permitted: Dictionary = old_ship.duplicate(true)
    for key in ["active_contract_id", "current_goal", "current_bt",
            "current_goal_score", "dock_attempt_start_tick",
            "planning_source", "faction_reputation"]:
        if new_ship.has(key):
            permitted[key] = new_ship[key]
    if new_ship != permitted:
        return {"ok": false, "fatal": true,
            "reason": "n104_release_modified_physical_ship"}
    if _measured_schema_validate("L1413", next) != "":
        return {"ok": false, "fatal": true,
            "reason": "n104_release_source_schema_invalid"}
    var expected_accounts: Dictionary = _measured_schema_accounts("L1416", next)
    var actual_money: Dictionary = _ledger.snapshot()
    if expected_accounts != actual_money.get("balances", {}):
        return {"ok": false, "fatal": true,
            "reason": "n104_release_changed_prepaid_n9_escrow"}
    # The source stage has passed full Schema and the explicit N104 write-set
    # check above. Reuse authoritative untouched domains rather than cloning
    # the entire growing World; detach every domain the stage may own/write.
    # Never publish a mutable container borrowed from candidate["world"].
    var committed: Dictionary = _n104_owned_release_publication(
        _world, next, ship_id, contract_id)
    if committed.is_empty() or _measured_schema_validate(
            "L1413_owned", committed) != "":
        return {"ok": false, "fatal": true,
            "reason": "n104_release_owned_publication_invalid"}
    _world = committed
    return {"ok": true, "changed": true, "tick": tick,
        "contract_id": contract_id, "ship_id": ship_id,
        "status": "N104_SOURCE_REPOSTED_FOR_N153",
        "event": candidate.get("event", {}).duplicate(true)}


## Legacy N15 physical cargo and free Undock helper ONLY. Paid N21 Dock
## is handled exclusively above through N21Source/N9, even from the UI.
## No second wallet, source stock, arrival process or dock occupancy.
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
    # Legacy N15 warehouse logistics must NEVER create a free N21
    # Dock. Native N84 and the explicit user Dock use the same paid
    # N21Source -> N9 -> _commit_native_n21 authority above.
    if action == "dock":
        return false
    if not (action in ["undock", "load", "unload"]) or op_id.is_empty() or ship_id.is_empty():
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
        if real_kind not in ["station", "shipyard", "construction_dock"]:
            return false
        if real_kind == "construction_dock":
            # A marketless N151 dock exists ONLY for an original
            # active site. Authorize boarding/landing under the ship's
            # real colony N104 mission, or N91 assigned engineer.
            var dock_fac: Dictionary = _world["facilities"][dock_id]
            var site_id: String = str(dock_fac.get("construction_source_site_id", ""))
            var site: Dictionary = _world.get("construction_sites", {}).get(site_id, {})
            if site.is_empty() or str(site.get("location_name", "")) != str(dock_fac.get("location", "")) or str(site.get("faction_id", "")) != str(before_ship.get("faction_id", "")):
                return false
            if action == "dock":
                var active_id: String = str(before_ship.get("active_contract_id", ""))
                var active: Dictionary = _world.get("contract_board", {}).get("contracts", {}).get(active_id, {})
                var passenger: bool = str(active.get("contract_type", "")) == "passenger" and str(active.get("mission_category", "")) == "strategy.colony.v1" and str(active.get("destination_location", "")) == str(dock_fac.get("location", ""))
                var material: bool = str(active.get("contract_type", "")) == "construction" and (
                    str(active.get("mission_category", "")) == "strategy.colony.v1" and
                    str(active.get("destination_location", "")) == str(dock_fac.get("location", "")) and
                    str(active.get("colony_site_id", "")) == site_id and
                    str(_world.get("construction_contracts", {}).get(active_id, "")) == site_id)
                var engineer: bool = str(before_ship.get("current_goal", "")) == "construct" and (
                    str(before_ship.get("active_contract_id", "")).is_empty() and
                    before_ship.get("current_bt") is Dictionary and
                    N91Executor.target(before_ship["current_bt"]) == site_id)
                if not passenger and not material and not engineer:
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
    if _measured_schema_validate("L1588", staged) != "":
        return false
    var balances: Dictionary = _measured_schema_accounts("L1590", staged)
    for account in balances:
        if _ledger.balance(str(account)) != int(balances[account]):
            return false
    # Publish the N15 write set, not the entire growing ship/market/receipt
    # history. The source proposal remains caller-owned and cannot alias a
    # published mutable ship, market or new receipt.
    var committed: Dictionary = _n15_owned_logistics_publication(
        _world, staged, ship_id, str(r.get("location_id", "")),
        action, receipt_key, op_id)
    if committed.is_empty():
        return false
    _world = committed
    return true


## Only call after the full N15 delta checks, Schema and N9 account oracle.
## Existing untouched rows are authoritative; staged rows are untrusted.
## Deep-detach the one mutable ship, one affected market, and new receipt.
## No full-history duplicate on each paid cargo operation.
static func _n15_owned_logistics_publication(source: Dictionary,
        proposed: Dictionary, ship_id: String, location: String,
        action: String, receipt_domain: String, op_id: String) -> Dictionary:
    if action not in ["load", "unload", "undock"] or (
            receipt_domain not in ["dock_receipts", "cargo_receipts"]):
        return {}
    if (receipt_domain == "cargo_receipts") != (action in ["load", "unload"]):
        return {}
    if not (source.get("ships") is Dictionary) or not (
            proposed.get("ships") is Dictionary) or not (
            source.get("markets") is Dictionary) or not (
            proposed.get("markets") is Dictionary):
        return {}
    if not (source.get(receipt_domain) is Dictionary) or not (
            proposed.get(receipt_domain) is Dictionary):
        return {}
    if not source["ships"].has(ship_id) or not (
            proposed["ships"].get(ship_id) is Dictionary):
        return {}
    if source[receipt_domain].has(op_id) or not (
            proposed[receipt_domain].get(op_id) is Dictionary):
        return {}
    if proposed["ships"].size() != source["ships"].size() or (
            proposed["markets"].size() != source["markets"].size()) or (
            proposed[receipt_domain].size() != source[receipt_domain].size() + 1):
        return {}
    if action in ["load", "unload"] and (
            not source["markets"].has(location) or not (
            proposed["markets"].get(location) is Dictionary)):
        return {}
    var committed: Dictionary = source.duplicate()
    committed["ships"] = source["ships"].duplicate()
    committed["ships"][ship_id] = proposed["ships"][ship_id].duplicate(true)
    if action in ["load", "unload"]:
        committed["markets"] = source["markets"].duplicate()
        committed["markets"][location] = proposed["markets"][location].duplicate(true)
    # For undock, no market mutation is permitted by the caller's oracle.
    committed[receipt_domain] = source[receipt_domain].duplicate()
    committed[receipt_domain][op_id] = proposed[receipt_domain][op_id].duplicate(true)
    return committed



## N147/N104 passengers run in the SAME N39 World/N9/N104 transaction.
## The stage is source-driven; only this method can publish its World/ledger.
func _publish_native_passenger_stage(proposed: Dictionary, phase: String,
        tick: int) -> Dictionary:
    if not proposed.get("ok", false):
        return proposed
    var staged: Dictionary = proposed.get("world", {})
    var bank: Dictionary = proposed.get("ledger_snapshot", {})
    var cid: String = str(proposed.get("contract_id", ""))
    var sid: String = str(proposed.get("ship_id", ""))
    if staged.is_empty() or bank.is_empty() or cid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n104_missing_authoritative_staged_result"}
    var allowed: Array[String] = ["contract_board", "escrow_balances",
        "faction_treasuries", "ships", "populations", "passenger_manifests",
        "passenger_receipts"]
    # Rust N92::commission may follow a real N134 Head grant. Only that
    # exact single-faction N113 StrategicMemory is allowed alongside
    # the paid N147 contract; no other Director field is writable.
    if phase == "post" and proposed.has("n147_head_grant"):
        var grant: Dictionary = proposed["n147_head_grant"]
        var faction: String = str(grant.get("faction_id", ""))
        var directors: Dictionary = staged.get("research_directors", {})
        var originals: Dictionary = _world.get("research_directors", {})
        if faction.is_empty() or not directors.has(faction) or (
                not originals.has(faction)) or not (
                grant.get("strategy") is Dictionary):
            return {"ok": false, "fatal": true,
                "reason": "n147_missing_real_single_faction_head"}
        for fid in originals:
            if not directors.has(fid):
                return {"ok": false, "fatal": true,
                    "reason": "n147_director_removed_on_passenger_post"}
            var old_director: Dictionary = originals[fid]
            var next_director: Dictionary = directors[fid]
            var restored: Dictionary = next_director.duplicate(true)
            if str(fid) == faction:
                if restored.get("strategic", null) != grant["strategy"]:
                    return {"ok": false, "fatal": true,
                        "reason": "n147_strategic_grant_not_committed"}
                restored["strategic"] = old_director.get("strategic", {})
                if not old_director.has("strategic"):
                    restored.erase("strategic")
            if restored != old_director:
                return {"ok": false, "fatal": true,
                    "reason": "n147_rewrote_unrelated_native_director"}
        if directors.size() != originals.size():
            return {"ok": false, "fatal": true,
                "reason": "n147_fabricated_native_director"}
        allowed.append("research_directors")
    if staged.size() < _world.size() or not staged.get("contract_board", {}).get("contracts", {}).has(cid):
        return {"ok": false, "fatal": true, "reason": "n104_passenger_world_cardinality"}
    for domain in _world:
        if not staged.has(domain):
            return {"ok": false, "fatal": true, "reason": "n104_passenger_world_field_removed"}
        if domain not in allowed and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true, "reason": "n104_passenger_unrelated_world_write"}
    for domain in staged:
        if not _world.has(domain) and domain not in ["passenger_manifests", "passenger_receipts"]:
            return {"ok": false, "fatal": true, "reason": "n104_passenger_fake_domain"}
    if staged.get("markets", {}) != _world.get("markets", {}) or staged.get("facilities", {}) != _world.get("facilities", {}):
        return {"ok": false, "fatal": true, "reason": "n104_passenger_market_or_facility_changed"}
    if staged.get("ships", {}).size() != _world.get("ships", {}).size() or staged.get("populations", {}).size() != _world.get("populations", {}).size():
        return {"ok": false, "fatal": true, "reason": "n104_passenger_ghost_actor"}
    if phase in ["post", "accept"] and staged["populations"] != _world["populations"]:
        return {"ok": false, "fatal": true, "reason": "n104_passenger_moved_without_flight"}
    if phase == "post" and staged["ships"] != _world["ships"]:
        return {"ok": false, "fatal": true, "reason": "n147_funded_offer_modified_ship"}
    if phase in ["accept", "move"]:
        if not staged["ships"].has(sid):
            return {"ok": false, "fatal": true, "reason": "n104_missing_real_ship"}
        for other in _world["ships"]:
            if str(other) != sid and staged["ships"][other] != _world["ships"][other]:
                return {"ok": false, "fatal": true, "reason": "n104_passenger_changed_other_ship"}
    if phase == "move":
        for pid in _world["populations"]:
            if staged["populations"][pid] != _world["populations"][pid]:
                var target: String = str(_world["contract_board"]["contracts"][cid]["source_location"]) if str(proposed.get("status", "")) == "N104_REAL_PASSENGERS_EMBARKED" else str(_world["contract_board"]["contracts"][cid]["destination_location"])
                if str(_world["populations"][pid].get("location", "")) != target:
                    return {"ok": false, "fatal": true, "reason": "n104_moved_foreign_household"}
    if phase != "move" and (staged.get("passenger_manifests", {}) != _world.get("passenger_manifests", {}) or staged.get("passenger_receipts", {}) != _world.get("passenger_receipts", {})):
        return {"ok": false, "fatal": true, "reason": "n104_fake_embark_without_physical_phase"}
    var err: String = _measured_schema_validate("L1680", staged)
    if not err.is_empty():
        return {"ok": false, "fatal": true, "reason": "n104_passenger_schema_" + err}
    var ledger := Ledger.new()
    if not ledger.restore(bank) or ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n104_passenger_money_not_conserved"}
    var accounts: Dictionary = _measured_schema_accounts("L1686", staged)
    if accounts.size() != bank.get("balances", {}).size():
        return {"ok": false, "fatal": true, "reason": "n104_passenger_wallets_disagree"}
    for wallet in accounts:
        if bank["balances"].get(wallet, null) != accounts[wallet]:
            return {"ok": false, "fatal": true, "reason": "n104_passenger_account_divergence"}
    _world = staged
    _ledger = ledger
    var receipt: Dictionary = proposed.duplicate()
    receipt.erase("world")
    receipt.erase("ledger_snapshot")
    receipt["tick"] = tick
    return receipt

## Actual source N147 offer; independently rerun the same native N92/N147
## planner, hull/route/fuel and treasury gates against CURRENT World.
func post_native_passenger_migration(tick: int, ready: Dictionary,
        multiplier: int, graph: RefCounted, resolver: RefCounted,
        positions: Dictionary, scale: float, original: RefCounted = null,
        sources: Dictionary = {}, baseline: Dictionary = {}) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1 or multiplier < 1:
        return {"ok": false, "reason": "n147_not_canonical_faction_tick"}
    # The source N113 vote exists ONLY once on Rust coordination's
    # 60*mult boundary, not on tick 1 or arbitrary NPC frames. A fake
    # intermediate call cannot accelerate a two-cycle confirmation.
    if tick % (60 * multiplier) != 0:
        return {"ok": false, "reason": "n113_not_original_decision_cycle"}
    var scan: Dictionary = NativeN147.observe(_world, graph, resolver,
        positions, tick, scale)
    if not scan.get("ok", false):
        return scan
    var matched: bool = false
    for p in scan.get("ready", []):
        if p == ready:
            matched = true
            break
    if not matched:
        return {"ok": false, "reason": "n147_unapproved_or_stale_source_offer"}
    # Now that the only N158 caller supplies its original N134 vote,
    # legacy callers WITHOUT that proof must NOT debit N104/N9.
    if original == null:
        return {"ok": false, "reason": "n147_original_head_grant_required"}
    var faction: String = str(ready.get("faction_id", ""))
    # Independently re-derive the actual Head on current N39 World. The
    # caller cannot fabricate an approval or race another paid N134 grant.
    var head_source: Dictionary = SourceN134Construction.choose(
        _world, sources, original, graph, faction, tick, multiplier)
    if not head_source.get("ok", false) or (
            head_source.get("head", {}) != baseline):
        return {"ok": false, "reason": "n147_stale_or_forged_n134_decision"}
    var grant: Dictionary = NativeN147Head.authorize(
        _world, faction, ready, baseline, tick,
        sources, original, graph, multiplier)
    if not grant.get("ok", false):
        return grant
    if not grant.get("authorized", false):
        # Frozen Rust N113 persists a first-cycle pending strategy in
        # Director::strategic but DOES NOT post a paid passenger order.
        # Stage ONLY that original per-faction memory in the same N39 World.
        if grant.get("strategy") is Dictionary:
            var current: Dictionary = _world.get(
                "research_directors", {}).get(faction, {})
            if current.is_empty():
                return {"ok": false, "fatal": true,
                    "reason": "n113_pending_missing_original_director"}
            # Only the Director memory is written on the unpaid N113 path.
            # Detach that domain before mutation; no mutable World value is
            # returned to the caller and the full Schema/accounts oracle stays.
            var next_world: Dictionary = _copy_world("L1751", false)
            next_world["research_directors"] = _world[
                "research_directors"].duplicate(true)
            next_world["research_directors"][faction][
                "strategic"] = grant["strategy"].duplicate(true)
            var invalid: String = _measured_schema_validate("L1754", next_world)
            if not invalid.is_empty() or _measured_schema_accounts("L1755", 
                    next_world) != _measured_schema_accounts("L1756", _world):
                return {"ok": false, "fatal": true,
                    "reason": "n113_pending_changed_canonical_source:" +
                        invalid}
            _world = next_world
            return {"ok": true, "authorized": false,
                "status": "N113_REAL_STRATEGY_NO_N104_CONTRACT",
                "reason": str(grant.get("reason", "")),
                "tick": tick, "faction_id": faction,
                "pending": bool(grant.get("pending", false)),
                "memory": grant["strategy"].duplicate(true),
                "money_spent": 0}
        return grant
    var plan: Dictionary = NativePassengers.post_migration(_world,
        _ledger.snapshot(), ready, tick, multiplier, graph)
    if not plan.get("ok", false):
        return plan
    # Stage the source strategic vote and original N104 escrow debit in
    # the SAME one N39 World/ledger commit, never before paid admission.
    var staged: Dictionary = plan.get("world", {})
    if not (staged.get("research_directors") is Dictionary) or not (
            staged["research_directors"].get(faction) is Dictionary):
        return {"ok": false, "fatal": true,
            "reason": "n147_source_director_dropped_during_post"}
    staged["research_directors"][faction]["strategic"] = grant[
        "strategy"].duplicate(true)
    plan["n147_head_grant"] = grant.duplicate(true)
    var posted: Dictionary = _publish_native_passenger_stage(
        plan, "post", tick)
    if posted.get("ok", false):
        posted["head"] = grant["head"].duplicate(true)
        posted["source_grant"] = "original_n134_migrate_colony"
    return posted

## Only a real, preflighted N153 passenger ship gets the source N81/N84
## tree; original Board.accept and potential Comms escrow top-up are real.
func accept_native_passenger(tick: int, candidate: Dictionary,
        graph: RefCounted, resolver: RefCounted,
        positions: Dictionary, scale: float) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 1:
        return {"ok": false, "reason": "n104_not_canonical_accept_tick"}
    var proposed: Dictionary = NativePassengers.propose_assignment(
        _world, graph, resolver, positions, tick, scale)
    if not proposed.get("ok", false) or not proposed.get("assigned", false):
        return {"ok": false, "reason": "n153_no_authoritative_passenger_assignment"}
    if candidate.get("contract_id", null) != proposed["contract_id"] or candidate.get("ship_id", null) != proposed["ship_id"] or candidate.get("ai_bt", null) != proposed["ai_bt"]:
        return {"ok": false, "reason": "n153_stale_passenger_ai_selection"}
    var taken: Dictionary = NativePassengers.accept(_world, _ledger.snapshot(),
        str(proposed["contract_id"]), str(proposed["ship_id"]),
        proposed["ai_bt"], tick)
    return _publish_native_passenger_stage(taken, "accept", tick)

## Invoked ONLY by N84->N146 RequestShipTransaction after actual N21
## source/destination docking, full N14 flight and unchanged contract ID.
func apply_native_passenger_move(tick: int, ship_id: String,
        contract_id: String, operation: String) -> Dictionary:
    if not _ready or tick != _last_tick + 1 or tick < 1:
        return {"ok": false, "reason": "n104_not_canonical_physical_ship_tick"}
    if operation not in ["passenger_embark", "passenger_delivery"]:
        return {"ok": false, "reason": "n104_unknown_passenger_command"}
    var ship: Dictionary = _world.get("ships", {}).get(ship_id, {})
    if str(ship.get("active_contract_id", "")) != contract_id or not (ship.get("current_bt") is Dictionary):
        return {"ok": false, "reason": "n104_no_active_native_passenger_bt"}
    var action: String = NativeBt.current_action(ship["current_bt"])
    if (operation == "passenger_embark" and action != "EmbarkPassengers") or (operation == "passenger_delivery" and action not in ["DeliverCargo", "DeliverPassengers"]):
        return {"ok": false, "reason": "n104_passenger_command_wrong_native_leaf"}
    var movement: Dictionary = NativePassengers.move(_world, _ledger.snapshot(),
        contract_id, ship_id, operation, tick)
    return _publish_native_passenger_stage(movement, "move", tick)

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
            "current_bt", "max_source_cost", "progression", "lifecycle"])
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
    # Rust engine/apply.rs: successful, REAL N97/N104 PAID delivery
    # resets hoard strikes (never broke strikes or idle ticks).
    # This mutation is inside the SAME original physical+financial
    # settlement, after both source receipts and before N39 publication.
    if operation == "delivery":
        var previous_life: Variant = changed_ship.get("lifecycle", null)
        if previous_life is Dictionary:
            var reset: Dictionary = NativeShipLifecycle.after_confirmed_delivery(
                previous_life, {"trusted_internal_apply": true,
                    "delivery_succeeded": true, "ship_entity": ship_id})
            if not reset.get("ok", false):
                return {"ok": false, "fatal": true, "reason": "n148_paid_delivery_reset_rejected"}
            changed_ship["lifecycle"] = reset["lifecycle"].duplicate(true)
    var error: String = _measured_schema_validate("L1978", staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "paid_delivery_invalid_world_" + error}
    var accounts: Dictionary = _measured_schema_accounts("L1981", staged)
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
    # N91 has no write-set when the source selector supplies no proposals.
    # Avoid copying growing World histories and running Schema/accounts on
    # every idle tick. The authoritative World was validated at its last
    # commit; no mutable reference escapes and no N9 receipt is produced.
    # Preserve the source success payload, including tick and status.
    if proposals.is_empty():
        return {"ok": true, "status": "N91_NATIVE_ENGINEERS_ASSIGNED",
            "tick": tick, "assigned": []}
    # Only selected ship planning fields are writable in this stage.
    # Unrelated growing histories remain canonical and read-only.
    var staged: Dictionary = _copy_world("L2008", false)
    staged["ships"] = _world["ships"].duplicate()
    var funding: Dictionary = native_construction_funding_snapshot()
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
        var ship: Dictionary = staged["ships"][ship_id].duplicate(true)
        staged["ships"][ship_id] = ship
        if not N91SourceDispatch.physical_site_funded(staged, funding, site_id):
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
        # Rust ConstructionSite has no Market of its own. An approved
        # N151 colony project is dockable ONLY at its receipted physical
        # construction_dock; ordinary N154 sites retain real station rules.
        var port: Dictionary = N91SourceDispatch.physical_site_dock(staged,
            site_id)
        if not port.get("ok", false):
            return {"ok": false, "fatal": true,
                "reason": str(port.get("reason", "n91_unverified_original_site_dock"))}
        var dock: Dictionary = staged.get("facilities", {}).get(
            str(port["facility_id"]), {})
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
    var issue: String = _measured_schema_validate("L2079", staged)
    if not issue.is_empty():
        return {"ok": false, "fatal": true, "reason": "n91_invalid_world_" + issue}
    var balances: Dictionary = _measured_schema_accounts("L2082", staged)
    if balances.size() != _ledger.balances_snapshot().size():
        return {"ok": false, "fatal": true, "reason": "n91_wallet_count_changed"}
    for account in balances:
        if _ledger.balance(str(account)) != int(balances[account]):
            return {"ok": false, "fatal": true, "reason": "n91_wallet_modified"}
    if not updated.is_empty():
        _world = staged
    return {"ok": true, "status": "N91_NATIVE_ENGINEERS_ASSIGNED",
        "tick": tick, "assigned": updated}


## N144/N151 approvals append only a site and its receipt. The two
## registries are owned at the root, while all existing nested rows remain
## read-only. N144 additionally updates exactly one director's strategic
## memory, so only that director is detached. This must not be reused for
## edits to an existing construction site or receipt.
static func _colony_approval_owned_stage(world: Dictionary,
        director_id: String = "") -> Dictionary:
    var staged: Dictionary = world.duplicate(false)
    staged["construction_sites"] = world["construction_sites"].duplicate(false)
    staged["construction_receipts"] = world["construction_receipts"].duplicate(false)
    if not director_id.is_empty():
        staged["research_directors"] = world["research_directors"].duplicate(false)
        if staged["research_directors"].has(director_id):
            staged["research_directors"][director_id] = (
                world["research_directors"][director_id].duplicate(true))
    return staged


## Miro B1 — the REAL frozen N134/N144 "found_colony" HeadDecision
## over a source-scored original planet. Approval and subsequent N151
## zero-cost site materialization happen in ONE canonical N39 commit.
## A read-only N151 scan alone NEVER authorizes a new colony.
func apply_native_n144_found_colony(tick: int, faction: String,
        baseline: Dictionary, original: RefCounted, graph: RefCounted,
        sources: Dictionary, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or (
            original == null or graph == null or multiplier < 1):
        return {"ok": false, "reason": "b1_not_live_original_head_tick"}
    if not _world.get("faction_treasuries", {}).has(faction):
        return {"ok": false, "reason": "b1_not_original_faction"}
    # The central World, not the caller's cached preview, re-evaluates
    # the same real market/shortage N111 and N134 construction comparison.
    var baseline_live: Dictionary = SourceN134Construction.choose(
        _world, sources, original, graph, faction, tick, multiplier)
    if not baseline_live.get("ok", false):
        return {"ok": false, "reason": str(baseline_live.get(
            "reason", "b1_source_n134_comparator_missing"))}
    if baseline_live.get("head", {}) != baseline.get("head", {}):
        return {"ok": false, "reason": "b1_stale_original_n134_head"}
    var source: Dictionary = NativeNewColonyHead.propose(
        _world, original, graph, faction, tick, multiplier)
    if not source.get("ok", false):
        return source
    if not source.get("ready", false):
        return {"ok": true, "founded": false, "due": true,
            "status": str(source.get("reason", "b1_no_viable_original_colony")),
            "blocked": source.get("blocked", []).duplicate(true),
            "faction_id": faction, "tick": tick, "head": {}}
    var grant: Dictionary = NativeColonyOrders.approval(
        _world, baseline_live, source, faction, tick, multiplier)
    if not grant.get("ok", false):
        return grant
    # N144 writes only these three domains. Detach them before any mutation;
    # unrelated growing World history remains read-only and unmodified.
    var memory: Dictionary = grant.get("memory", {})
    var staged: Dictionary = _colony_approval_owned_stage(
        _world, faction if not memory.is_empty() else "")
    var authorized: bool = bool(grant.get("authorized", false))
    var candidate: Dictionary = source.get("candidate", {})
    var site: Dictionary = candidate.get("site", {})
    var site_id: String = str(site.get("id", ""))
    var receipt_id: String = "n151_colony_approved:" + site_id
    if authorized:
        # Verify exact source proposal against current original N151 rules
        # once more. No rogue planet, location or ship can be injected.
        var rechecked: Dictionary = NativeColonyFounding.proposal(
            _world, original, graph, faction,
            str(source["plan"]["body_id"]),
            str(source["plan"]["source"]), tick, multiplier, true)
        if not rechecked.get("ok", false) or rechecked.get("site", {}) != site:
            return {"ok": false, "fatal": true,
                "reason": "b1_colony_proposal_changed_before_apply"}
        if site_id.is_empty() or staged["construction_sites"].has(site_id) or (
                staged["construction_receipts"].has(receipt_id) or
                _ledger.has_receipt(receipt_id)):
            return {"ok": false, "fatal": true,
                "reason": "b1_duplicate_original_colony_approval"}
        staged["construction_sites"][site_id] = site.duplicate(true)
        staged["construction_receipts"][receipt_id] = {
            "id": receipt_id, "kind": "colony_approved",
            "site_id": site_id, "tick": tick, "faction_id": faction,
            "source_location": str(source["plan"]["source"]),
            "destination_location": str(source["plan"]["destination"]),
            "body_id": str(source["plan"]["body_id"]),
            "capital": 0, "n9_receipt_id": ""}
    if not memory.is_empty():
        if not staged.get("research_directors", {}).has(faction):
            return {"ok": false, "fatal": true,
                "reason": "b1_missing_single_n113_director"}
        staged["research_directors"][faction]["strategic"] = memory.duplicate(true)
    var allowed: Array[String] = ["construction_sites",
        "construction_receipts", "research_directors"]
    if staged.size() != _world.size():
        return {"ok": false, "fatal": true,
            "reason": "b1_cannot_create_parallel_world_domain"}
    for domain in _world:
        if domain not in allowed and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true,
                "reason": "b1_changed_unrelated_world_domain:" + str(domain)}
    for other in _world.get("research_directors", {}):
        if str(other) != faction and staged["research_directors"][other] != _world["research_directors"][other]:
            return {"ok": false, "fatal": true,
                "reason": "b1_modified_other_faction_head"}
    var growth: int = 1 if authorized else 0
    if staged["construction_sites"].size() != _world["construction_sites"].size() + growth or (
            staged["construction_receipts"].size() != _world["construction_receipts"].size() + growth):
        return {"ok": false, "fatal": true,
            "reason": "b1_not_exactly_one_new_original_site"}
    var validity: String = _measured_schema_validate("L2181", staged)
    if not validity.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "b1_source_schema_rejected:" + validity}
    if _measured_schema_accounts("L2185", staged) != _measured_schema_accounts("L2185", _world):
        return {"ok": false, "fatal": true,
            "reason": "b1_created_money_or_wallet_without_source"}
    # N9 remains unchanged: Rust colony::commission initially spawns
    # a ConstructionSite costing ZERO; only the subsequent N104 posts
    # reserve 80 CR per passenger / 10k CR per material shipment.
    var bank_before: Dictionary = _ledger.snapshot()
    if staged != _world:
        _world = staged
    if _ledger.snapshot() != bank_before:
        return {"ok": false, "fatal": true,
            "reason": "b1_changed_original_n9_credits"}
    return {"ok": true, "due": true, "founded": authorized,
        "status": "N144_SOURCE_HEAD_FOUNDED_REAL_N151_SITE" if authorized else "N144_SOURCE_HEAD_DID_NOT_APPROVE_FOUNDING",
        "faction_id": faction, "site_id": site_id if authorized else "",
        "receipt_id": receipt_id if authorized else "",
        "body_id": str(source["plan"]["body_id"]),
        "source": str(source["plan"]["source"]),
        "destination": str(source["plan"]["destination"]),
        "score": float(source["plan"]["goal"]["score"]),
        "money_debited": 0, "population_created": 0,
        "metals_created": 0, "dock_created": 0,
        "head": grant.get("head", {}).duplicate(true), "tick": tick}

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
    # N151 approval writes only the site registry and its receipt registry.
    # Detach both nested domains before mutation; other World domains stay read-only.
    var staged: Dictionary = _colony_approval_owned_stage(_world)
    staged["construction_sites"][site_id] = site.duplicate(true)
    staged["construction_receipts"][receipt_id] = {
        "id": receipt_id, "kind": "colony_approved",
        "site_id": site_id, "tick": tick,
        "faction_id": faction, "source_location": source,
        "destination_location": str(site["location_name"]),
        "body_id": body_id, "capital": 0, "n9_receipt_id": ""}
    var validation: String = _measured_schema_validate("L2240", staged)
    if not validation.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n151_native_site_world_" + validation}
    if _ledger.snapshot() != original_money or _measured_schema_accounts("L2244", staged) != _measured_schema_accounts("L2244", _world):
        return {"ok": false, "fatal": true, "reason": "n151_colony_spawn_invented_funds"}
    # Sole authority: N39 World; N9 Ledger untouched as original Rust
    # colony::commission's initial site approval has zero monetary cost.
    _world = staged
    return {"ok": true, "status": "N151_PHYSICAL_COLONY_SITE_CREATED",
        "tick": tick, "site_id": site_id, "receipt_id": receipt_id,
        "faction_id": faction, "body_id": body_id,
        "passengers": 0, "metals_delivered": 0,
        "money_debited": 0}


## Frozen Rust strategy/colony.rs::commission: live N134 head approval
## of an ALREADY approved N151 ConstructionSite posts exactly one prepaid
## real Passenger contract; the source cargo route for 200 Metals remains
## separate and is never replaced by a phantom warehouse.
func apply_native_n144_colony_passengers(tick: int, faction: String,
        baseline: Dictionary, original: RefCounted, graph: RefCounted,
        sources: Dictionary, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or (
            original == null or graph == null or multiplier < 1):
        return {"ok": false, "reason": "n144_not_canonical_head_tick"}
    if not _world.get("faction_treasuries", {}).has(faction):
        return {"ok": false, "reason": "n144_unknown_original_faction"}
    # Never trust N158's proposed HeadDecision. Recompute the source
    # N111/N134 comparator against the CURRENT canonical N39 World.
    var verified: Dictionary = SourceN134Construction.choose(
        _world, sources, original, graph, faction, tick, multiplier)
    if not verified.get("ok", false):
        return {"ok": false, "reason": str(verified.get("reason", "n134_missing_real_head"))}
    if verified.get("head", {}) != baseline.get("head", {}):
        return {"ok": false, "reason": "n144_stale_n134_head"}
    var active: Dictionary = NativeColonyOrders.active_site(
        _world, graph, faction, tick, multiplier)
    if not active.get("ok", false):
        return active
    if not active.get("ready", false):
        return {"ok": true, "due": true, "posted": false,
            "status": str(active.get("reason", "n144_no_prepaid_passenger_plan")),
            "faction_id": faction, "tick": tick}
    var approved: Dictionary = NativeColonyOrders.approval(
        _world, verified, active, faction, tick, multiplier)
    if not approved.get("ok", false):
        return approved
    var head_memory: Dictionary = approved.get("memory", {})
    # The authorized branch replaces this stage with the detached paid proposal.
    # On a head-only tick only this faction director may change; never clone
    # the growing ships/markets/contract history just to store head memory.
    var staged: Dictionary = _copy_world("L2289_head_root", false)
    var ledger: RefCounted = _ledger.fork()
    var posted: Dictionary = {}
    if approved.get("authorized", false):
        posted = NativeColonyOrders.stage_paid_passengers(
            _world, _ledger.snapshot(), active, faction, tick,
            multiplier, graph) if bool(active.get("plan", {}).get("passenger", false)) else NativeColonyMetals.post(
            _world, _ledger.snapshot(),
            str(active.get("plan", {}).get("site_id", "")),
            tick, multiplier, graph)
        if not posted.get("ok", false):
            return posted
        staged = posted["world"]
        var funded := Ledger.new()
        if not funded.restore(posted["ledger_snapshot"]):
            return {"ok": false, "fatal": true, "reason": "n144_invalid_paid_n9"}
        ledger = funded
        var cid: String = str(posted.get("contract_id", ""))
        var site_id: String = str(active.get("plan", {}).get("site_id", ""))
        var c: Dictionary = staged.get("contract_board", {}).get("contracts", {}).get(cid, {})
        if cid.is_empty() or str(c.get("colony_site_id", "")) != site_id or (
                str(c.get("mission_category", "")) != NativeColonyOrders.PROJECT_TAG):
            return {"ok": false, "fatal": true, "reason": "n144_forged_source_colony_contract"}
    if not head_memory.is_empty() and staged.get("research_directors", {}).has(faction):
        if not posted.get("ok", false):
            staged["research_directors"] = _world["research_directors"].duplicate()
            staged["research_directors"][faction] = _world["research_directors"][faction].duplicate(true)
        staged["research_directors"][faction]["strategic"] = head_memory.duplicate(true)
    if staged.size() != _world.size():
        return {"ok": false, "fatal": true, "reason": "n144_added_noncanonical_world_domain"}
    for domain in _world:
        if domain not in ["contract_board", "escrow_balances",
                "faction_treasuries", "research_directors",
                "construction_contracts"] and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true, "reason": "n144_edited_unrelated_world_domain"}
    for other in _world.get("faction_treasuries", {}):
        if str(other) != faction and staged["faction_treasuries"][other] != _world["faction_treasuries"][other]:
            return {"ok": false, "fatal": true, "reason": "n144_forged_foreign_funds"}
    for other in _world.get("research_directors", {}):
        if str(other) != faction and staged["research_directors"][other] != _world["research_directors"][other]:
            return {"ok": false, "fatal": true, "reason": "n144_tampered_foreign_director"}
    var old_board: Dictionary = _world.get("contract_board", {}).get("contracts", {})
    var new_board: Dictionary = staged.get("contract_board", {}).get("contracts", {})
    if posted.get("ok", false):
        if new_board.size() != old_board.size() + 1 or (
                staged["escrow_balances"].size() != _world["escrow_balances"].size() + 1):
            return {"ok": false, "fatal": true, "reason": "n144_not_exactly_one_paid_order"}
        for old_id in old_board:
            if new_board.get(old_id, null) != old_board[old_id]:
                return {"ok": false, "fatal": true, "reason": "n144_existing_contract_changed"}
        # A Metals commission adds EXACTLY one original N154 Site mapping;
        # passenger commission never touches the construction registry.
        var metal_order: bool = not bool(active.get("plan", {}).get("passenger", false))
        var old_maps: Dictionary = _world.get("construction_contracts", {})
        var new_maps: Dictionary = staged.get("construction_contracts", {})
        if new_maps.size() != old_maps.size() + (1 if metal_order else 0):
            return {"ok": false, "fatal": true, "reason": "n144_wrong_colony_site_contract_count"}
        for earlier in old_maps:
            if new_maps.get(earlier, null) != old_maps[earlier]:
                return {"ok": false, "fatal": true, "reason": "n144_rewrote_old_construction_commitment"}
        if metal_order and str(new_maps.get(str(posted["contract_id"]), "")) != str(active["plan"]["site_id"]):
            return {"ok": false, "fatal": true, "reason": "n144_unverified_real_construction_site"}
    elif staged["contract_board"] != _world["contract_board"] or staged["escrow_balances"] != _world["escrow_balances"] or staged.get("construction_contracts", {}) != _world.get("construction_contracts", {}):
        return {"ok": false, "fatal": true, "reason": "n144_unapproved_contract_created"}
    if _measured_schema_validate("L2350", staged) != "":
        return {"ok": false, "fatal": true, "reason": "n144_invalid_world_" + _measured_schema_validate("L2351", staged)}
    if ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n144_original_money_supply_changed"}
    # Source N104 Board.post MUST leave one immutable N9 transfer from
    # real faction treasury to that order's new escrow. No extra pays
    # and no invented financial receipt on the unapproved/head-only path.
    var prior_money: Dictionary = _ledger.snapshot()
    var new_money: Dictionary = ledger.snapshot()
    var prior_receipts: Dictionary = prior_money.get("receipts", {})
    var new_receipts: Dictionary = new_money.get("receipts", {})
    if posted.get("ok", false):
        var posted_cid: String = str(posted.get("contract_id", ""))
        var original_post: String = "contract:" + posted_cid + ":post"
        if new_receipts.size() != prior_receipts.size() + 1 or not new_receipts.has(original_post):
            return {"ok": false, "fatal": true, "reason": "n144_missing_exact_prepaid_n9_receipt"}
        var before_treasury: int = int(_world["faction_treasuries"][faction])
        var paid_amount: int = int(posted.get("money_debited", -1))
        if paid_amount <= 0 or int(staged["faction_treasuries"][faction]) != before_treasury - paid_amount or int(staged["escrow_balances"].get("escrow:" + posted_cid, -1)) != paid_amount:
            return {"ok": false, "fatal": true, "reason": "n144_treasury_escrow_not_conserved"}
    elif new_receipts != prior_receipts:
        return {"ok": false, "fatal": true, "reason": "n144_head_memory_minted_payment"}
    for receipt_id in prior_receipts:
        if new_receipts.get(receipt_id, null) != prior_receipts[receipt_id]:
            return {"ok": false, "fatal": true, "reason": "n144_modified_existing_payment"}
    var expected: Dictionary = _measured_schema_accounts("L2375", staged)
    var actual: Dictionary = ledger.balances_snapshot()
    if expected.size() != actual.size():
        return {"ok": false, "fatal": true, "reason": "n144_n9_wrong_wallet_count"}
    for wallet in expected:
        if not actual.has(wallet) or actual[wallet] != expected[wallet]:
            return {"ok": false, "fatal": true, "reason": "n144_n9_balance_diverged"}
    if staged != _world:
        _world = staged
        _ledger = ledger
    return {"ok": true, "due": true, "posted": bool(posted.get("ok", false)),
        "status": str(posted.get("status", approved.get("reason", "n144_head_wait"))),
        "contract_id": str(posted.get("contract_id", "")),
        "money_debited": int(posted.get("money_debited", 0)),
        "site_id": str(active["plan"]["site_id"]),
        "faction_id": faction, "tick": tick,
        "head": approved.get("head", {}).duplicate(true)}

## Miro B2: original N153 contract AI accepts ONE prepaid N144
## Construction offer, with real 200-Metals ship/route, full fuel
## preflight and source N97 purchase quote. Exactly the canonical
## N104 Board + N9 top-up, no other ship/market mutation.
func accept_native_b2_colony_metals(tick: int, bid: Dictionary,
        graph: RefCounted, positions: Dictionary,
        resolver: RefCounted, scale: float) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or (
            graph == null or resolver == null):
        return {"ok": false, "reason": "b2_not_live_original_n153_faction_tick"}
    var result: Dictionary = NativeColonyMetalAssignment.accept(
        _world, _ledger.snapshot(), bid, graph, positions,
        resolver, tick, scale)
    if not result.get("ok", false):
        return result
    var staged: Dictionary = result.get("world", {})
    var money: Dictionary = result.get("ledger_snapshot", {})
    var cid: String = str(result.get("contract_id", ""))
    var sid: String = str(result.get("ship_id", ""))
    if not _world.get("ships", {}).has(sid) or (
            not _world.get("contract_board", {}).get("contracts", {}).has(cid)):
        return {"ok": false, "fatal": true, "reason": "b2_accept_missing_canonical_contract"}
    if staged.size() != _world.size() or staged.get("markets", {}) != _world.get("markets", {}):
        return {"ok": false, "fatal": true, "reason": "b2_accept_created_fake_world_or_market"}
    for domain in _world:
        if domain not in ["ships", "contract_board", "escrow_balances",
                "faction_treasuries"] and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true,
                "reason": "b2_accept_modified_unrelated_domain:" + str(domain)}
    if staged["ships"].size() != _world["ships"].size():
        return {"ok": false, "fatal": true, "reason": "b2_accept_invented_real_hull"}
    for other in _world["ships"]:
        if str(other) != sid and staged["ships"][other] != _world["ships"][other]:
            return {"ok": false, "fatal": true, "reason": "b2_accept_modified_other_ship"}
    var old_contracts: Dictionary = _world["contract_board"]["contracts"]
    var new_contracts: Dictionary = staged["contract_board"]["contracts"]
    if old_contracts.size() != new_contracts.size() or (
            str(new_contracts[cid].get("status", "")) != "accepted" or
            str(new_contracts[cid].get("fulfiller_id", "")) != sid):
        return {"ok": false, "fatal": true, "reason": "b2_accept_fake_n104_contract"}
    for old_id in old_contracts:
        if str(old_id) != cid and new_contracts[old_id] != old_contracts[old_id]:
            return {"ok": false, "fatal": true, "reason": "b2_accept_changed_foreign_contract"}
    var payer_faction: String = str(old_contracts[cid].get("faction_id", ""))
    for other in _world.get("faction_treasuries", {}):
        if str(other) != payer_faction and staged["faction_treasuries"][other] != _world["faction_treasuries"][other]:
            return {"ok": false, "fatal": true, "reason": "b2_accept_changed_foreign_treasury"}
    var next_ledger := Ledger.new()
    if not next_ledger.restore(money) or next_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "b2_accept_minted_n9_money"}
    var prior: Dictionary = _ledger.snapshot()
    var old_receipts: Dictionary = prior["receipts"]
    var new_receipts: Dictionary = money["receipts"]
    var top_up: int = int(result.get("top_up", -1))
    var topup_id: String = "contract:" + cid + ":topup"
    if top_up < 0 or new_receipts.size() != old_receipts.size() + (1 if top_up > 0 else 0):
        return {"ok": false, "fatal": true, "reason": "b2_accept_wrong_n9_topup_count"}
    if top_up > 0 and not new_receipts.has(topup_id):
        return {"ok": false, "fatal": true, "reason": "b2_accept_missing_paid_n9_topup"}
    for old_id in old_receipts:
        if new_receipts.get(old_id, null) != old_receipts[old_id]:
            return {"ok": false, "fatal": true, "reason": "b2_accept_modified_old_escrow_receipt"}
    var schema_error: String = _measured_schema_validate("L2455", staged)
    if not schema_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "b2_accept_schema_" + schema_error}
    var accounts: Dictionary = _measured_schema_accounts("L2458", staged)
    if accounts.size() != money["balances"].size():
        return {"ok": false, "fatal": true, "reason": "b2_accept_n9_account_count"}
    for wallet in accounts:
        if money["balances"].get(wallet, null) != accounts[wallet]:
            return {"ok": false, "fatal": true, "reason": "b2_accept_n9_account_diverged"}
    _world = staged
    _ledger = next_ledger
    return {"ok": true, "status": "B2_REAL_N153_N104_CONSTRUCTION_ACCEPTED",
        "contract_id": cid, "ship_id": sid, "site_id": str(result["site_id"]),
        "top_up": top_up, "tick": tick}

## Miro B2 original Rust engine/apply.rs construction delivery:
## after actual N14 flight and N21 dock, move physical Metals directly
## from the same N15 ship hold into N154 Site progress. The marketless
## destination NEVER owns a fake warehouse. N104 escrow payout is ONE
## immutable real N9 transfer in the SAME authoritative commit.
func apply_native_b2_colony_metals_delivery(tick: int, sid: String,
        cid: String) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick + 1:
        return {"ok": false, "reason": "b2_not_live_original_n84_ship_phase"}
    var ship: Dictionary = _world.get("ships", {}).get(sid, {})
    if not (ship.get("current_bt") is Dictionary) or (
            NativeBt.current_action(ship["current_bt"]) != "DeliverCargo"):
        return {"ok": false, "reason": "b2_unapproved_native_n84_delivery_leaf"}
    var stage: Dictionary = NativeColonyMetals.deliver(
        _world, _ledger.snapshot(), cid, sid, tick)
    if not stage.get("ok", false):
        return stage
    var staged: Dictionary = stage.get("world", {})
    var money: Dictionary = stage.get("ledger_snapshot", {})
    var site_id: String = str(stage.get("site_id", ""))
    var count: int = int(stage.get("quantity", 0))
    var old_site: Dictionary = _world.get("construction_sites", {}).get(site_id, {})
    var new_site: Dictionary = staged.get("construction_sites", {}).get(site_id, {})
    if old_site.is_empty() or count <= 0 or new_site.is_empty() or (
            int(new_site.get("progress_delivered", -1)) != int(old_site.get("progress_delivered", 0)) + count):
        return {"ok": false, "fatal": true, "reason": "b2_no_real_original_200_metal_progress"}
    if staged.size() != _world.size() or staged.get("markets", {}) != _world.get("markets", {}) or (
            staged.get("facilities", {}) != _world.get("facilities", {}) or
            staged.get("populations", {}) != _world.get("populations", {})):
        return {"ok": false, "fatal": true, "reason": "b2_delivery_fabricated_market_or_population"}
    for domain in _world:
        if domain not in ["ships", "contract_board", "escrow_balances",
                "construction_sites", "construction_receipts",
                "cargo_receipts"] and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true,
                "reason": "b2_delivery_modified_unrelated_world:" + str(domain)}
    if staged["ships"].size() != _world["ships"].size():
        return {"ok": false, "fatal": true, "reason": "b2_delivery_invented_ship"}
    for other in _world["ships"]:
        if str(other) != sid and staged["ships"][other] != _world["ships"][other]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_modified_other_ship"}
    if int(staged["ships"][sid]["cargo"].get("metals", 0)) != int(ship["cargo"].get("metals", 0)) - count:
        return {"ok": false, "fatal": true, "reason": "b2_delivery_no_physical_ship_hold_debit"}
    for other in _world["construction_sites"]:
        if str(other) != site_id and staged["construction_sites"][other] != _world["construction_sites"][other]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_changed_another_site"}
    var original_contracts: Dictionary = _world["contract_board"]["contracts"]
    var completed: Dictionary = staged["contract_board"]["contracts"]
    if completed.size() != original_contracts.size() or (
            str(completed.get(cid, {}).get("status", "")) != "paid"):
        return {"ok": false, "fatal": true, "reason": "b2_delivery_unsettled_original_n104"}
    for other in original_contracts:
        if str(other) != cid and completed[other] != original_contracts[other]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_modified_other_n104"}
    var cargo_id: String = str(stage.get("n15_receipt", ""))
    var site_receipt: String = str(stage.get("construction_receipt", ""))
    if staged["cargo_receipts"].size() != _world["cargo_receipts"].size() + 1 or (
            staged["construction_receipts"].size() != _world["construction_receipts"].size() + 1 or
            not staged["cargo_receipts"].has(cargo_id) or
            not staged["construction_receipts"].has(site_receipt)):
        return {"ok": false, "fatal": true, "reason": "b2_delivery_missing_n15_or_n154_receipt"}
    for old_id in _world["cargo_receipts"]:
        if staged["cargo_receipts"].get(old_id, null) != _world["cargo_receipts"][old_id]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_rewrote_physical_receipt"}
    for old_id in _world["construction_receipts"]:
        if staged["construction_receipts"].get(old_id, null) != _world["construction_receipts"][old_id]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_rewrote_paid_material_proof"}
    var ledger := Ledger.new()
    if not ledger.restore(money) or ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "b2_delivery_fabricated_money"}
    var prior_bank: Dictionary = _ledger.snapshot()
    var old_money: Dictionary = prior_bank["receipts"]
    var new_money: Dictionary = money["receipts"]
    var payment_id: String = "contract:" + cid + ":payout"
    if new_money.size() != old_money.size() + 1 or not new_money.has(payment_id):
        return {"ok": false, "fatal": true, "reason": "b2_delivery_missing_real_n9_payout"}
    for old_id in old_money:
        if new_money.get(old_id, null) != old_money[old_id]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_modified_historical_n9"}
    var err: String = _measured_schema_validate("L2549", staged)
    if not err.is_empty():
        return {"ok": false, "fatal": true, "reason": "b2_delivery_schema_" + err}
    var expected_accounts: Dictionary = _measured_schema_accounts("L2552", staged)
    if expected_accounts.size() != money.get("balances", {}).size():
        return {"ok": false, "fatal": true, "reason": "b2_delivery_n9_account_count"}
    for wallet in expected_accounts:
        if money["balances"].get(wallet, null) != expected_accounts[wallet]:
            return {"ok": false, "fatal": true, "reason": "b2_delivery_n9_account_diverged"}
    _world = staged
    _ledger = ledger
    return {"ok": true, "status": "B2_NATIVE_RUST_200_METALS_DELIVERED_PAID",
        "contract_id": cid, "ship_id": sid, "site_id": site_id,
        "quantity": count, "payout": int(stage.get("payout", 0)),
        "n15_receipt": cargo_id, "n9_receipt": payment_id,
        "construction_receipt": site_receipt, "tick": tick}

## Native Rust engine/colony.rs::prepare_docks, AFTER a real N144
## founder authorization: one empty temporary N21 dock and one zero-
## resident household, NOT a free colony, market or passenger.
## N39 is the sole actor/credit authority, preserving original N9 totals.
func apply_native_colony_prepare_docks(tick: int, graph: RefCounted) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or graph == null:
        return {"ok": false, "reason": "n151_not_canonical_colony_dock_tick"}
    var proposed: Dictionary = NativeColonyDocks.stage(_world, tick, graph)
    if not proposed.get("ok", false):
        return proposed
    var created: Array = proposed.get("created", [])
    if created.is_empty():
        return {"ok": true, "status": "N151_NO_NEW_DOCKS",
            "created": [], "tick": tick}
    var staged: Dictionary = proposed.get("world", {})
    if staged.is_empty() or staged.get("markets", {}) != _world.get("markets", {}):
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_cannot_create_market"}
    var immutable_domains: Array[String] = [
        "ships", "faction_treasuries", "contract_board",
        "escrow_balances", "bodies", "research"]
    for domain in _world:
        if not staged.has(domain):
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_removed_canonical_domain"}
        if domain not in ["facilities", "populations", "construction_receipts",
                "construction_next_db_id"] and staged[domain] != _world[domain]:
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_modified_unrelated_domain:" + str(domain)}
    if staged.size() != _world.size():
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_invented_canonical_domain"}
    if staged["facilities"].size() != _world["facilities"].size() + created.size() or (
            staged["populations"].size() != _world["populations"].size() + created.size() or
            staged["construction_receipts"].size() != _world["construction_receipts"].size() + created.size()):
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_actor_receipt_cardinality"}
    for existing in _world["facilities"]:
        if staged["facilities"].get(existing, null) != _world["facilities"][existing]:
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_edited_existing_facility"}
    for existing in _world["populations"]:
        if staged["populations"].get(existing, null) != _world["populations"][existing]:
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_edited_existing_household"}
    for existing in _world["construction_receipts"]:
        if staged["construction_receipts"].get(existing, null) != _world["construction_receipts"][existing]:
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_rewrote_construction_receipt"}
    if int(staged["construction_next_db_id"]) != int(_world["construction_next_db_id"]) - created.size():
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_allocator_not_source_monotonic"}
    var staged_ledger: RefCounted = _ledger.fork()
    for made in created:
        var dock_id: String = str(made.get("facility_id", ""))
        var pop_id: String = str(made.get("population_id", ""))
        if not staged_ledger.register_empty_account(Schema.facility_account(dock_id)) or (
                not staged_ledger.register_empty_account(Schema.household_account(pop_id))):
            return {"ok": false, "fatal": true, "reason": "n151_double_or_forged_n9_actor"}
        if int(staged["facilities"][dock_id]["credits"]) != 0 or (
                int(staged["populations"][pop_id]["wealth"]) != 0 or
                int(staged["populations"][pop_id]["count"]) != 0):
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_minted_credits_or_residents"}
    var invalid: String = _measured_schema_validate("L2630", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n151_invalid_original_temporary_dock:" + invalid}
    if staged_ledger.total() != _ledger.total() or (
            staged_ledger.snapshot().get("receipts", {}) != _ledger.snapshot().get("receipts", {})):
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_changed_real_economy"}
    var accounts: Dictionary = _measured_schema_accounts("L2638", staged)
    var balances: Dictionary = staged_ledger.balances_snapshot()
    if accounts.size() != balances.size():
        return {"ok": false, "fatal": true,
            "reason": "n151_dock_money_account_cardinality"}
    for account in accounts:
        if not balances.has(account) or int(balances[account]) != int(accounts[account]):
            return {"ok": false, "fatal": true,
                "reason": "n151_dock_money_account_mismatch"}
    _world = staged
    _ledger = staged_ledger
    return {"ok": true, "status": "N151_SOURCE_COLONY_DOCK_AND_EMPTY_HOUSEHOLD",
        "created": created.duplicate(true), "tick": tick}

## N141: real docked-engineer physical construction shift + one N9 payroll.
## Source N141 WorkShift chooses existing households and excludes labor
## already employed by N39 facilities, N143 Director and other N141 sites.
## This phase does not invent completed facilities: N154 materialization and
## builder AI authorization are separate gated native operations.
## Ordinary N141 only replaces paid site rows, appends receipts, removes
## completed site/contract keys, inserts new facilities and changes scalar
## treasuries. None of those writes mutates a pre-existing nested row.
## B3 colony establishment is different: its source stage can inspect and
## update nested facility/site/market graphs, so retain the deep oracle path.
## This is also the ownership boundary exercised by the N141 regression.
static func _n141_owned_construction_domains(source: Dictionary,
        colony_stage: bool) -> Dictionary:
    var staged: Dictionary = source.duplicate(false)
    for domain in ["construction_sites", "construction_receipts",
            "construction_contracts", "faction_treasuries",
            "facilities", "markets"]:
        staged[domain] = source[domain].duplicate(colony_stage)
    staged["populations"] = source["populations"].duplicate(colony_stage)
    return staged


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
    # N141 writes only these owned domains. Keep all other registries as
    # read-only inputs to labor/colony proposals and strict Schema oracle.
    # B3 colony establishment performs its own detached full proposal.
    # B3 colony establishment inspects the entire population graph.
    # Retain the original deep-owned path whenever any site can establish
    # a colony; ordinary N141 shifts only write the paid household rows.
    var colony_stage: bool = false
    for site_id in site_ids:
        var site_view: Dictionary = _world["construction_sites"][site_id]
        if site_view.get("labor", {}).get("colony_source", null) != null:
            colony_stage = true
            break
    staged = _n141_owned_construction_domains(_world, colony_stage)
    var owned_households: Dictionary = {}
    var ledger: RefCounted = _ledger.fork()
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
            # The proposal is read-only; detach a household before its first
            # authoritative write, even if a later site/receipt is rejected.
            # Multiple paid sites share the same detached row in this stage.
            if not colony_stage and not owned_households.has(pid):
                staged["populations"][pid] = staged["populations"][pid].duplicate(true)
                owned_households[pid] = true
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
    var established: Array = []
    var blocked_site_written: bool = false
    for site_id in completed_sites:
        var site: Dictionary = staged["construction_sites"][site_id]
        if site.get("labor", {}).get("colony_source", null) != null:
            # Rust apply::tick_construction_labor invokes native
            # colony::establish IN THIS SAME successful N141 WorkShift.
            # B3 never creates another dock, household or facility wallet:
            # it upgrades the genuine N151 temporary physical dock,
            # transfers exactly 20k N9 and creates its first Market.
            var original_bank: Dictionary = ledger.snapshot()
            var native_b3: Dictionary = NativeColonyEstablish.stage(
                staged, original_bank, str(site_id), tick, multiplier)
            if not native_b3.get("ok", false):
                var reason: String = str(native_b3.get("reason", "n151_source_establish_rejected"))
                if reason == "insufficient_startup_capital":
                    # Frozen Rust leaves the actual paid site alive and
                    # records its blocked_reason, retrying on a later paid
                    # source WorkShift rather than gifting working capital.
                    staged["construction_sites"][site_id]["labor"]["blocked_reason"] = reason
                    blocked_site_written = true
                    blocked.append({"site_id": str(site_id), "reason": reason})
                    continue
                return {"ok": false, "fatal": true,
                    "reason": "b3_original_rust_establish_" + reason}
            var before: Dictionary = staged
            var next_world: Dictionary = native_b3["world"]
            var next_money: Dictionary = native_b3["ledger_snapshot"]
            var dock_id: String = str(native_b3["facility_id"])
            var location: String = str(native_b3["location"])
            var faction_id: String = str(before["construction_sites"][site_id]["faction_id"])
            if next_world.size() != before.size() or (
                    next_world["facilities"].size() != before["facilities"].size() or
                    next_world["populations"] != before["populations"] or
                    next_world["ships"] != before["ships"] or
                    next_world["contract_board"] != before["contract_board"] or
                    next_world["escrow_balances"] != before["escrow_balances"] or
                    next_world["cargo_receipts"] != before["cargo_receipts"] or
                    next_world["dock_receipts"] != before["dock_receipts"] or
                    next_world["markets"].size() != before["markets"].size() + 1 or
                    next_world["construction_sites"].size() != before["construction_sites"].size() - 1 or
                    next_world["construction_receipts"].size() != before["construction_receipts"].size() + 1):
                return {"ok": false, "fatal": true,
                    "reason": "b3_cannot_create_second_world_or_ghost_colony_actor"}
            for domain in before:
                if domain not in ["facilities", "markets", "faction_treasuries",
                        "construction_sites", "construction_contracts",
                        "construction_receipts"] and next_world[domain] != before[domain]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_mutated_unrelated_canonical_domain:" + str(domain)}
            for old_dock in before["facilities"]:
                if str(old_dock) != dock_id and next_world["facilities"][old_dock] != before["facilities"][old_dock]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_changed_unrelated_station"}
            for previous_market in before["markets"]:
                if next_world["markets"].get(previous_market, null) != before["markets"][previous_market]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_forged_existing_market"}
            if before["markets"].has(location) or not next_world["markets"].has(location) or (
                    str(before["facilities"][dock_id].get("type", "")) != "construction_dock" or
                    str(next_world["facilities"][dock_id].get("type", "")) != "station" or
                    str(next_world["facilities"][dock_id].get("location", "")) != location or
                    int(next_world["facilities"][dock_id].get("native_db_id", 0)) !=
                        int(before["facilities"][dock_id].get("native_db_id", 1)) or
                    str(next_world["markets"][location].get("owner", "")) != dock_id):
                return {"ok": false, "fatal": true,
                    "reason": "b3_did_not_upgrade_original_n151_dock"}
            for other_faction in before.get("faction_treasuries", {}):
                if str(other_faction) != faction_id and next_world["faction_treasuries"][other_faction] != before["faction_treasuries"][other_faction]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_forged_other_faction_credits"}
            var bank_stage := Ledger.new()
            if not bank_stage.restore(next_money) or bank_stage.total() != ledger.total():
                return {"ok": false, "fatal": true,
                    "reason": "b3_original_n9_supply_not_conserved"}
            var capital_receipt: String = str(native_b3.get("n9_receipt_id", ""))
            if next_money["receipts"].size() != original_bank["receipts"].size() + 1 or (
                    not next_money["receipts"].has(capital_receipt) or
                    str(next_money["receipts"][capital_receipt].get("kind", "")) !=
                        "native_n151_colony_startup_capital" or
                    int(next_world["faction_treasuries"][faction_id]) !=
                        int(before["faction_treasuries"][faction_id]) - 20000 or
                    int(next_world["facilities"][dock_id]["credits"]) !=
                        int(before["facilities"][dock_id]["credits"]) + 20000):
                return {"ok": false, "fatal": true,
                    "reason": "b3_missing_exact_real_n9_20000_transfer"}
            for receipt_key in original_bank["receipts"]:
                if next_money["receipts"].get(receipt_key, null) != original_bank["receipts"][receipt_key]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_rewrote_original_paid_history"}
            for remaining_site in before["construction_sites"]:
                if str(remaining_site) != str(site_id) and next_world["construction_sites"][remaining_site] != before["construction_sites"][remaining_site]:
                    return {"ok": false, "fatal": true,
                        "reason": "b3_changed_unrelated_construction_site"}
            staged = next_world
            ledger = bank_stage
            established.append(native_b3.duplicate(true))
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
        if kind == "gate":
            # Original paid N154 site is a real physical facility
            # source, not a newly invented world object. The site
            # position is durable commissioning provenance; N108
            # recomputes the *current* Rust facility-id orbital exit
            # from BodyOrbit at each actual jump. Link stays UNPAIRED
            # until a separate explicit two-gate admin operation.
            var original_site_position: Variant = site.get("position", null)
            if not (original_site_position is Dictionary) or not (
                    original_site_position.get("x") is float or
                    original_site_position.get("x") is int) or not (
                    original_site_position.get("y") is float or
                    original_site_position.get("y") is int) or not is_finite(
                    float(original_site_position["x"])) or not is_finite(
                    float(original_site_position["y"])):
                return {"ok": false, "fatal": true,
                    "reason": "n108_paid_gate_missing_real_source_site_position"}
            staged["facilities"][new_id]["position"] = original_site_position.duplicate(true)
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
    var error: String = _measured_schema_validate("L2940", staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n141_invalid_world_" + error}
    var expected: Dictionary = _measured_schema_accounts("L2943", staged)
    var wallet_values: Dictionary = ledger.balances_snapshot()
    if wallet_values.size() != expected.size() or ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n141_money_supply_modified"}
    for id in expected:
        if expected[id] != wallet_values.get(id, null):
            return {"ok": false, "fatal": true, "reason": "n141_n9_wallet_mismatch"}
    if not paid.is_empty() or not materialized.is_empty() or (
            not established.is_empty() or blocked_site_written):
        _world = staged
        _ledger = ledger
    return {"ok": true, "status": "N141_N154_N151_NATIVE_PAID_CONSTRUCTION",
        "tick": tick, "paid": paid, "materialized": materialized,
        "established": established, "blocked": blocked}


## Frozen Rust governance::set_mandate/clear_mandate and
## charter::set_charter. Only the canonical N39 World may hold policy:
## no second Director resource, no default player mandate, no money.
## This adapter is available for the eventual source command gateway;
## untrusted UI data must still arrive through an explicit caller action.
## N109/N110 optional policy maps are independent. Clone only the root
## selected by the command and its target row. The other two maps remain
## immutable aliases until publication; Schema and N9 still validate ALL.
static func _n110_policy_domain(operation: String) -> String:
    match operation:
        "set_research_mandate", "clear_research_mandate":
            return "research_mandates"
        "set_faction_charter":
            return "faction_charters"
        "set_economic_mandate", "clear_economic_mandate":
            return "economic_mandates"
    return ""


static func _n110_owned_policy_stage(world: Dictionary,
        active_domain: String, faction: String = "") -> Dictionary:
    if active_domain not in ["research_mandates", "faction_charters",
            "economic_mandates"]:
        return {}
    for key in ["research_mandates", "faction_charters",
            "economic_mandates"]:
        if world.has(key) and not (world[key] is Dictionary):
            return {}
    var staged: Dictionary = world.duplicate()
    for key in ["research_mandates", "faction_charters",
            "economic_mandates"]:
        if not staged.has(key):
            staged[key] = {}
    staged[active_domain] = staged[active_domain].duplicate()
    if not faction.is_empty() and staged[active_domain].has(faction):
        if not (staged[active_domain][faction] is Dictionary):
            return {}
        staged[active_domain][faction] = staged[active_domain][faction].duplicate(true)
    return staged


func apply_native_player_research_policy(tick: int, faction: String,
        operation: String, incoming: Dictionary = {}) -> Dictionary:
    if not _ready or tick != _last_tick or tick < 0:
        return {"ok": false, "reason": "n110_policy_not_live_world_tick"}
    if not _world.get("research_directors", {}).has(faction) or (
            not _world.get("faction_treasuries", {}).has(faction)):
        return {"ok": false, "reason": "n110_unknown_actual_faction"}
    if operation not in ["set_research_mandate", "clear_research_mandate",
            "set_faction_charter", "set_economic_mandate",
            "clear_economic_mandate"]:
        return {"ok": false, "reason": "n110_invalid_original_policy_action"}
    if operation == "clear_research_mandate" and not _world.get(
            "research_mandates", {}).has(faction):
        # Rust clear_mandate on an absent directive is a pure no-op,
        # not a reason to materialize a new policy map in an old save.
        return {"ok": true, "tick": tick, "faction_id": faction,
            "operation": operation, "changed": false,
            "status": "N110_ORIGINAL_DIRECTIVE_ALREADY_ABSENT"}
    if operation == "clear_economic_mandate" and not _world.get(
            "economic_mandates", {}).has(faction):
        return {"ok": true, "tick": tick, "faction_id": faction,
            "operation": operation, "changed": false,
            "status": "N110_ECONOMIC_DIRECTIVE_ALREADY_ABSENT"}
    # One policy command owns exactly one optional registry. The other
    # two registries are read-only through the full Schema/N9 oracle.
    # No existing nested policy row may be mutated through an alias.
    var policy_key: String = _n110_policy_domain(operation)
    var next_world: Dictionary = _n110_owned_policy_stage(_world, policy_key, faction)
    if next_world.is_empty():
        return {"ok": false, "reason": "invalid_original_policy_map"}
    var operation_result: Dictionary = {}
    match operation:
        "set_research_mandate":
            var old: Dictionary = next_world["research_mandates"].get(
                faction, {})
            operation_result = OriginalResearchMandate.update_mandate(
                old, incoming, tick, OriginalResearchMandate.catalogue_map(
                    OriginalTechnology.all()))
            if not operation_result.get("ok", false):
                return operation_result
            next_world["research_mandates"][faction] = operation_result[
                "mandate"].duplicate(true)
        "clear_research_mandate":
            operation_result = OriginalResearchMandate.clear_mandate(
                next_world["research_mandates"], faction)
            if not operation_result.get("ok", false):
                return operation_result
            next_world["research_mandates"] = operation_result[
                "mandates"].duplicate(true)
        "set_economic_mandate":
            var incoming_policy: Dictionary = incoming.duplicate(true)
            var error: String = OriginalEconomicMandate.validate_economic(
                incoming_policy)
            if not error.is_empty() or str(incoming_policy.get(
                    "mode", "")) not in ["delegated", "advise", "hold"]:
                return {"ok": false, "reason": "invalid_original_economic_policy:" +
                    error}
            var owned_location: String = str(incoming_policy["location"])
            var location_market: Dictionary = next_world.get(
                "markets", {}).get(owned_location, {})
            var station_id: String = str(location_market.get("owner", ""))
            var actual_station: Dictionary = next_world.get(
                "facilities", {}).get(station_id, {})
            if str(actual_station.get("type", "")) != "station" or (
                    str(actual_station.get("faction", "")) != faction) or (
                    str(actual_station.get("location", "")) != owned_location):
                return {"ok": false, "reason": "station_not_owned_by_faction"}
            var prior: Dictionary = next_world["economic_mandates"].get(
                faction, {})
            var same: bool = (not prior.is_empty() and
                str(prior.get("location", "")) == owned_location and
                str(prior.get("commodity", "")) == str(
                    incoming_policy.get("commodity", "")) and
                str(prior.get("kind", "")) == str(
                    incoming_policy.get("kind", "")))
            incoming_policy["spent_cr"] = int(prior.get(
                "spent_cr", 0)) if same else 0
            incoming_policy["created_tick"] = int(prior.get(
                "created_tick", tick)) if same else tick
            incoming_policy["last_commitment_tick"] = prior.get(
                "last_commitment_tick", null) if same else null
            incoming_policy["last_reason"] = "approved_native_governance"
            error = OriginalEconomicMandate.validate_economic(
                incoming_policy)
            if not error.is_empty():
                return {"ok": false, "reason": error}
            next_world["economic_mandates"][faction] = incoming_policy
            operation_result = {"ok": true}
        "clear_economic_mandate":
            next_world["economic_mandates"].erase(faction)
            operation_result = {"ok": true}
        "set_faction_charter":
            operation_result = OriginalFactionCharter.install(
                next_world["faction_charters"], faction, incoming,
                next_world["research_directors"].keys(), tick)
            if operation_result.has("error") or not operation_result.has(
                    "charter"):
                return {"ok": false, "reason": str(operation_result.get(
                    "error", "n109_invalid_original_charter"))}
            next_world["faction_charters"][faction] = operation_result[
                "charter"].duplicate(true)
    var reason: String = _measured_schema_validate("L3068", next_world)
    if not reason.is_empty() or _measured_schema_accounts("L3069", next_world) != _measured_schema_accounts("L3069", 
            _world):
        return {"ok": false, "reason": "n109_n110_policy_invalid_single_world:" +
            reason}
    var changed: bool = next_world != _world
    if changed:
        _world = next_world
    return {"ok": true, "tick": tick, "faction_id": faction,
        "operation": operation, "status": "N109_N110_ORIGINAL_DIRECTOR_POLICY",
        "changed": changed}


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
    # N143 replaces director/research/receipt/policy rows, and treasury
    # values are scalar. Only paid market/facility/household rows are mutated
    # in place. Own their roots and detach each actor once, before first write.
    # No nested reference to the authoritative World may be modified on a
    # rejected late shift. The full Schema/accounts and N9 oracle remain below.
    var staged: Dictionary = _copy_world("L3098_owned_root", false)
    for domain in ["research_directors", "research", "research_receipts",
            "research_mandates", "faction_charters", "faction_treasuries",
            "facilities", "populations", "markets"]:
        staged[domain] = _world[domain].duplicate(false)
    var owned_research_markets: Dictionary = {}
    var owned_research_facilities: Dictionary = {}
    var owned_research_households: Dictionary = {}
    if proposed["heads"].size() != staged["research_directors"].size():
        return {"ok": false, "fatal": true, "reason": "missing_native_research_head"}
    for fid in proposed["heads"]:
        if not staged["research_directors"].has(fid):
            return {"ok": false, "fatal": true, "reason": "extra_native_research_head"}
        staged["research_directors"][fid] = proposed["heads"][fid].duplicate(true)
    var staged_ledger: RefCounted = _ledger.fork()
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
        # Real Rust N110/N109 player policy is part of the original
        # Director checkpoint. No shift can spend a newer/altered
        # mandate with a stale previous grant.
        var live_mandate: Dictionary = staged.get(
            "research_mandates", {}).get(fid, {})
        var live_charter: Dictionary = staged.get(
            "faction_charters", {}).get(fid, {})
        if intent.get("mandate_preconditions", null) != live_mandate or (
                intent.get("charter_preconditions", null) != live_charter):
            return {"ok": false, "fatal": true,
                "reason": "stale_original_n109_n110_paid_policy"}
        if bool(intent.get("mandated_shift", false)) and (
                live_mandate.is_empty() or str(
                live_mandate.get("mode", "")) != "delegated"):
            return {"ok": false, "fatal": true,
                "reason": "unbacked_original_research_mandate"}
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
        # Commit has succeeded and receipt verification passed. Detach all
        # mutable rows before the first write; repeated paid shifts reuse the
        # same owned row and see the previous shift's updated balances/stock.
        if not owned_research_markets.has(location):
            market = market.duplicate(true)
            staged["markets"][location] = market
            owned_research_markets[location] = true
        if not owned_research_facilities.has(facility_id):
            facility = facility.duplicate(true)
            staged["facilities"][facility_id] = facility
            owned_research_facilities[facility_id] = true
        if not owned_research_households.has(population_id):
            person = person.duplicate(true)
            staged["populations"][population_id] = person
            owned_research_households[population_id] = true
        market["supply"]["electronics"] = float(market["supply"]["electronics"]) - 1.0
        staged["faction_treasuries"][fid] = staged_ledger.balance(faction_account)
        facility["credits"] = staged_ledger.balance(facility_account)
        person["wealth"] = staged_ledger.balance(population_account)
        staged["research_directors"][fid] = validated["commander"].duplicate(true)
        staged["research"][fid] = validated["commander"].get("technologies", []).duplicate(true)
        # Rust governance::paid_research + charter::record_paid occur
        # ONLY AFTER the actual native money/electronics/wage commit.
        # The counters are SOURCE receipts, not extra N9 charges.
        var paid_mandate: Dictionary = validated.get("mandate", {})
        var paid_charter: Dictionary = validated.get("charter", {})
        if not (paid_mandate is Dictionary) or not (paid_charter is Dictionary):
            return {"ok": false, "fatal": true,
                "reason": "invalid_source_n109_n110_paid_policy_result"}
        if bool(intent.get("mandated_shift", false)):
            if not staged.get("research_mandates", {}).has(fid):
                return {"ok": false, "fatal": true,
                    "reason": "missing_original_n110_directive_at_commit"}
            staged["research_mandates"][fid] = paid_mandate.duplicate(true)
            if staged.get("faction_charters", {}).has(fid):
                staged["faction_charters"][fid] = paid_charter.duplicate(true)
            elif not paid_charter.is_empty():
                return {"ok": false, "fatal": true,
                    "reason": "unexpected_original_charter_was_created"}
        elif paid_mandate != live_mandate or paid_charter != live_charter:
            return {"ok": false, "fatal": true,
                "reason": "autonomous_research_mutated_player_policy"}
        staged["research_receipts"][receipt_id] = {
            "receipt_id": receipt_id, "faction_id": fid, "tick": tick,
            "facility_id": facility_id, "population_id": population_id,
            "technology": str(intent["technology"]),
            "cost": cost, "wages": payroll, "electronics": 1.0,
            "mandated_shift": bool(intent.get("mandated_shift", false)),
            "completed_technology": intent.get("completed_technology", null),
            "n9_receipt_id": receipt_id
        }
        paid.append(staged["research_receipts"][receipt_id].duplicate(true))
    var error: String = _measured_schema_validate("L3219", staged)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "research_world_" + error}
    var expected: Dictionary = _measured_schema_accounts("L3222", staged)
    var actual: Dictionary = staged_ledger.balances_snapshot()
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
    var next_money: RefCounted = _ledger.fork()
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
    # N154 commission writes only six owned registries. Keep the canonical
    # ships/markets/facilities and growing history read-only; publishing a
    # whole deep World here scales with unrelated accumulated state.
    # Each writable registry is detached recursively before the first write.
    var after: Dictionary = _n154_owned_commission_stage(
        _world, id, site, new_site, contract_id, faction, escrow,
        next_money.balance(payer), next_money.balance(escrow),
        board.snapshot())
    if after.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "construction_owned_commission_stage_invalid"}
    var receipt_id: String = "native_site_commission:" + contract_id
    after["construction_receipts"][receipt_id] = {
        "id": receipt_id, "tick": tick, "kind": "commission",
        "site_id": id, "contract_id": contract_id, "quantity": quantity,
        "n9_receipt_id": "contract:" + contract_id + ":post"}
    var reason: String = _measured_schema_validate("L3363", after)
    if not reason.is_empty():
        return {"ok": false, "fatal": true, "reason": "construction_world_" + reason}
    var expected: Dictionary = _measured_schema_accounts("L3366", after)
    var balances: Dictionary = next_money.balances_snapshot()
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


# N154 commission is append-only for sites/contracts/receipts and changes
# scalar balances in treasuries/escrows. Existing nested rows are read-only.
# Own only the six registry roots, and detach the replacement board snapshot
# because ContractBoard's snapshot may contain mutable nested contract rows.
# A rejected stage never mutates source; Schema/N9 oracle stays at the caller.
static func _n154_owned_commission_stage(source: Dictionary,
        site_id: String, site: Dictionary, new_site: bool,
        contract_id: String, faction: String, escrow: String,
        treasury_after: int, escrow_after: int,
        board_after: Dictionary) -> Dictionary:
    var domains: Array = ["construction_sites", "construction_contracts",
        "faction_treasuries", "contract_board", "escrow_balances",
        "construction_receipts"]
    if site_id.is_empty() or contract_id.is_empty() or faction.is_empty() or escrow.is_empty():
        return {}
    if not (board_after.get("contracts") is Dictionary):
        return {}
    if not board_after["contracts"].has(contract_id):
        return {}
    for domain in domains:
        if not (source.get(domain) is Dictionary):
            return {}
    if source["construction_contracts"].has(contract_id) or source["construction_receipts"].has("native_site_commission:" + contract_id) or source["escrow_balances"].has(escrow):
        return {}
    if not source["faction_treasuries"].has(faction):
        return {}
    if new_site:
        if source["construction_sites"].has(site_id) or site.is_empty():
            return {}
    elif not source["construction_sites"].has(site_id) or source["construction_sites"][site_id] != site:
        return {}
    var staged: Dictionary = source.duplicate()
    for domain in domains:
        staged[domain] = source[domain].duplicate()
    if new_site:
        staged["construction_sites"][site_id] = site.duplicate(true)
    staged["construction_contracts"][contract_id] = site_id
    staged["faction_treasuries"][faction] = treasury_after
    staged["contract_board"] = board_after.duplicate(true)
    staged["escrow_balances"][escrow] = escrow_after
    return staged


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
    # N135 owns only board, escrow and the payer facility row. Never clone
    # unrelated growing ships/markets/history for a single funded posting.
    # Detach each writable container before validation; failed postings must
    # not mutate the authoritative World or leak a proposed board alias.
    var world_next: Dictionary = _copy_world("L3452_owned_root", false)
    world_next["contract_board"] = next_board.duplicate(true)
    world_next["escrow_balances"] = escrows_before.duplicate(true)
    world_next["escrow_balances"][escrow] = int(next_money["balances"][escrow])
    world_next["facilities"] = _world["facilities"].duplicate()
    world_next["facilities"][buyer] = _world["facilities"][buyer].duplicate(true)
    world_next["facilities"][buyer]["credits"] = int(next_money["balances"][payer])
    var world_error: String = _measured_schema_validate("L3457", world_next)
    if not world_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "funded_world_" + world_error}
    var account_rows: Dictionary = _measured_schema_accounts("L3460", world_next)
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
# N152 refund wallets are scalar fields inside mutable facility/household rows.
# Detach the registry roots once, then only each actually credited payer row.
# All original rows remain read-only until the full Schema/N9 publication gate.
static func _n152_owned_refund_wallet_stage(world: Dictionary) -> Dictionary:
    var staged: Dictionary = world.duplicate()
    for domain in ["escrow_balances", "facilities", "populations"]:
        staged[domain] = world[domain].duplicate()
    staged["faction_treasuries"] = world.get("faction_treasuries", {}).duplicate()
    return staged


static func _n152_detach_refund_wallet_row(staged: Dictionary,
        original: Dictionary, domain: String, row_id: String,
        detached: Dictionary) -> void:
    var key: String = domain + "/" + row_id
    if detached.has(key):
        return
    staged[domain][row_id] = original[domain][row_id].duplicate(true)
    detached[key] = true


func apply_native_n152_contract_lifecycle(tick: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick:
        return {"ok": false, "reason": "n152_not_the_canonical_post_facility_tick"}
    if not _world.has("contract_board") and not _world.has("escrow_balances"):
        return {"ok": true, "tick": tick, "expired": [], "renewed": [], "refunded": [],
            "blocked": [], "status": "LEGACY_NO_CONTRACT_BOARD"}
    if not _world.has("contract_board") or not _world.has("escrow_balances"):
        return {"ok": false, "fatal": true, "reason": "n152_partial_contract_authority"}
    var legacy: bool = OS.get_environment("LS_LATE_CONTRACT_LEGACY") == "1"
    var old_bank: Dictionary = _ledger.snapshot() if legacy else {}
    var proposal: Dictionary = (NativeN152.stage(_world, old_bank, tick) if legacy
        else NativeN152.stage_owned(_world, _ledger, tick))
    if not proposal.get("ok", false):
        return {"ok": false, "fatal": true, "reason": "n152_" + str(proposal.get("reason", "stage_rejected"))}
    if not bool(proposal.get("changed", false)):
        return {"ok": true, "tick": tick, "expired": [], "renewed": [],
            "refunded": [], "blocked": proposal.get("blocked", []).duplicate(true),
            "status": "NO_DUE_CONTRACT_CLOSURES"}
    # No-change ticks above do not export or restore historical receipts.
    # Actual changes still pass every original complete publication guard.
    if not legacy:
        old_bank = _ledger.snapshot()
        proposal["ledger_snapshot"] = proposal["owned_ledger"].snapshot()
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
    # N152 owns only the contract board and refunded wallet domains.  A full
    # World clone here grows with unrelated ships, markets and history.
    # Detach wallet domains before any writes, including rejected refunds.
    var staged: Dictionary = _copy_world("L3596_owned_root", false)
    staged["contract_board"] = next_board.duplicate(true)
    var detached_refund_payers: Dictionary = {}
    if not proposal["refunded"].is_empty():
        staged = _n152_owned_refund_wallet_stage(staged)
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
            _n152_detach_refund_wallet_row(staged, _world, "facilities", facility_id, detached_refund_payers)
            staged["facilities"][facility_id]["credits"] = payer_balance
        elif payer.begins_with("population/"):
            var population_id: String = payer.substr(11)
            if not staged["populations"].has(population_id):
                return {"ok": false, "fatal": true, "reason": "n152_refund_missing_household"}
            _n152_detach_refund_wallet_row(staged, _world, "populations", population_id, detached_refund_payers)
            staged["populations"][population_id]["wealth"] = payer_balance
        elif payer.begins_with("faction/"):
            var faction_id: String = payer.substr(8)
            if not staged.get("faction_treasuries", {}).has(faction_id):
                return {"ok": false, "fatal": true, "reason": "n152_refund_missing_treasury"}
            staged["faction_treasuries"][faction_id] = payer_balance
        else:
            return {"ok": false, "fatal": true, "reason": "n152_refund_noncanonical_beneficiary"}
    var valid: String = _measured_schema_validate("L3621", staged)
    if not valid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n152_invalid_world_" + valid}
    var expected: Dictionary = _measured_schema_accounts("L3624", staged)
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


## Frozen Rust admin_remove_ship/admin_remove_facility is a DISTINCT
## administrative boundary, not a planner action. This is the only
## N39 authoritative commit: one real actor deletion, the existing N104
## N152 cascade, one auditable N9 actor write-off, and source history.
## A missing payer's contract escrow stays held for later recovery.
func apply_native_admin_removal(tick: int, kind: String,
        actor_id: String, reason: String = "admin",
        in_native_ships_phase: bool = false) -> Dictionary:
    if not _ready or tick < 0 or tick != _last_tick + (1 if in_native_ships_phase else 0):
        return {"ok": false, "reason": "admin_not_at_authoritative_tick"}
    if not kind in ["ship", "facility"] or actor_id.is_empty():
        return {"ok": false, "reason": "invalid_admin_actor"}
    var old_bank: Dictionary = _ledger.snapshot()
    var old_world: Dictionary = _world
    var proposal: Dictionary = NativeAdminN152.stage(_world, old_bank,
        tick, kind, actor_id, reason)
    if not proposal.get("ok", false):
        return proposal
    var next_world: Dictionary = proposal["world"]
    var next_bank: Dictionary = proposal["ledger_snapshot"]
    var closed_account: String = (Schema.ship_account(actor_id)
        if kind == "ship" else Schema.facility_account(actor_id))
    var receipt_id: String = str(proposal["receipt_id"])
    var lost: int = int(proposal["credits_lost"])
    if old_bank.get("balances", {}).get(closed_account, null) != lost:
        return {"ok": false, "fatal": true, "reason": "admin_deleted_unfunded_actor"}
    if next_bank.get("balances", {}).has(closed_account) or next_bank.get("balances", {}).size() != old_bank.get("balances", {}).size() - 1:
        return {"ok": false, "fatal": true, "reason": "admin_wallet_was_not_removed_exactly_once"}
    for account in old_bank["balances"]:
        if str(account) != closed_account and old_bank["balances"][account] != next_bank.get("balances", {}).get(account, null):
            return {"ok": false, "fatal": true, "reason": "admin_changed_unrelated_n9_balance"}
    if next_bank.get("receipts", {}).size() != old_bank.get("receipts", {}).size() + 1:
        return {"ok": false, "fatal": true, "reason": "admin_wrong_n9_receipt_count"}
    for old_receipt in old_bank["receipts"]:
        if old_bank["receipts"][old_receipt] != next_bank.get("receipts", {}).get(old_receipt, null):
            return {"ok": false, "fatal": true, "reason": "admin_changed_prior_n9_receipt"}
    var writeoff: Dictionary = next_bank.get("receipts", {}).get(receipt_id, {})
    if writeoff.get("id") != receipt_id or writeoff.get("tick") != tick or writeoff.get("account_closed") != closed_account or writeoff.get("credits_lost") != lost:
        return {"ok": false, "fatal": true, "reason": "admin_missing_real_financial_writeoff"}
    if writeoff.get("kind") != ("ship_decommissioned" if kind == "ship" else "facility_removed") or writeoff.get("legs") != [{"account": closed_account, "delta": -lost}]:
        return {"ok": false, "fatal": true, "reason": "admin_writeoff_not_source_destruct"}
    var later := Ledger.new()
    if not later.restore(next_bank) or later.total() != _ledger.total() - lost:
        return {"ok": false, "fatal": true, "reason": "admin_source_money_loss_mismatch"}
    var board := ContractBoard.new(later)
    if not board.restore(next_world.get("contract_board", {})):
        return {"ok": false, "fatal": true, "reason": "admin_real_board_restore_rejected"}
    var before_board: Dictionary = old_world["contract_board"]
    var after_board: Dictionary = next_world["contract_board"]
    if before_board.get("receipt_claims") != after_board.get("receipt_claims") or before_board.get("contracts", {}).size() != after_board.get("contracts", {}).size():
        return {"ok": false, "fatal": true, "reason": "admin_deleted_cargo_history"}
    for cid in before_board["contracts"]:
        if not after_board["contracts"].has(cid):
            return {"ok": false, "fatal": true, "reason": "admin_deleted_original_contract"}
        var before: Dictionary = before_board["contracts"][cid]
        var after: Dictionary = after_board["contracts"][cid]
        if before == after:
            continue
        var expected: Dictionary = before.duplicate(true)
        if kind == "ship" and str(before.get("fulfiller_id", "")) == actor_id:
            if str(before.get("status", "")) == "accepted":
                expected["status"] = "posted"
                expected["fulfiller_id"] = ""
                expected["accepted_at_tick"] = -1
                expected["agreed_payment"] = -1
            elif str(before.get("status", "")) == "picked_up":
                expected["status"] = "expired"
        elif kind == "facility" and str(before.get("status", "")) not in ["paid", "expired"]:
            var location: String = str(old_world["facilities"][actor_id]["location"])
            var matches_owner: bool = str(before.get("requestor_id", "")) in [
                actor_id, Schema.facility_account(actor_id)]
            var matches_endpoint: bool = bool(proposal["last_at_location"]) and (
                str(before.get("source_location", "")) == location or
                str(before.get("destination_location", "")) == location)
            if matches_owner or matches_endpoint:
                expected["status"] = "expired"
        if after != expected:
            return {"ok": false, "fatal": true, "reason": "admin_changed_unrelated_contract_terms"}
    if next_world.size() != old_world.size() and not (
            next_world.size() == old_world.size() + 1 and not old_world.has("native_admin_removals")):
        return {"ok": false, "fatal": true, "reason": "admin_changed_world_structure"}
    for domain in old_world:
        if domain not in ["ships", "facilities", "contract_board",
                "native_admin_removals", "station_administration"] and (
                old_world[domain] != next_world.get(domain, null)):
            return {"ok": false, "fatal": true, "reason": "admin_changed_other_world_domain_" + str(domain)}
    if kind == "ship":
        if not old_world["ships"].has(actor_id) or next_world["ships"].has(actor_id) or next_world["ships"].size() != old_world["ships"].size() - 1 or next_world["facilities"] != old_world["facilities"] or next_world.get("station_administration") != old_world.get("station_administration"):
            return {"ok": false, "fatal": true, "reason": "admin_wrong_ship_removal_domain"}
        for sid in old_world["ships"]:
            if str(sid) != actor_id and next_world["ships"].get(sid, null) != old_world["ships"][sid]:
                return {"ok": false, "fatal": true, "reason": "admin_changed_surviving_ship"}
    else:
        if not old_world["facilities"].has(actor_id) or next_world["facilities"].has(actor_id) or next_world["facilities"].size() != old_world["facilities"].size() - 1:
            return {"ok": false, "fatal": true, "reason": "admin_wrong_facility_removal_domain"}
        for facility_id in old_world["facilities"]:
            if str(facility_id) != actor_id and next_world["facilities"].get(facility_id, null) != old_world["facilities"][facility_id]:
                return {"ok": false, "fatal": true, "reason": "admin_changed_surviving_facility"}
    var history: Dictionary = next_world.get("native_admin_removals", {})
    var original_history: Dictionary = old_world.get("native_admin_removals", {})
    if history.size() != original_history.size() + 1 or not history.has(receipt_id):
        return {"ok": false, "fatal": true, "reason": "admin_history_not_append_only"}
    for old_id in original_history:
        if history.get(old_id, null) != original_history[old_id]:
            return {"ok": false, "fatal": true, "reason": "admin_modified_prior_removal"}
    var error: String = _measured_schema_validate("L3744", next_world)
    if not error.is_empty():
        return {"ok": false, "fatal": true, "reason": "admin_invalid_world_" + error}
    var accounts: Dictionary = _measured_schema_accounts("L3747", next_world)
    if accounts.size() != next_bank["balances"].size():
        return {"ok": false, "fatal": true, "reason": "admin_wallet_count_diverged"}
    for account in accounts:
        if next_bank["balances"].get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "admin_wallet_world_diverged"}
    _world = next_world
    _ledger = later
    var events: Array = []
    for cid in proposal["released"]:
        events.append({"kind": "contract_released", "id": cid,
            "ship_id": actor_id, "reason": "ship_destroyed"})
    for cid in proposal["cancelled"]:
        events.append({"kind": "contract_expired", "id": cid,
            "reason": "ship_destroyed_with_cargo" if kind == "ship" else "facility_destroyed"})
    for sid in proposal["kicked"]:
        events.append({"kind": "ship_undocked", "id": sid,
            "reason": "facility_destroyed", "facility_id": actor_id})
    events.append({"kind": "ship_decommissioned" if kind == "ship" else "facility_removed",
        "id": actor_id, "reason": reason, "credits_lost": lost, "tick": tick})
    return {"ok": true, "kind": kind, "id": actor_id, "tick": tick,
        "receipt_id": receipt_id, "credits_lost": lost,
        "released": proposal["released"].duplicate(true),
        "cancelled": proposal["cancelled"].duplicate(true),
        "kicked": proposal["kicked"].duplicate(true),
        "retirement": proposal["retirement"].duplicate(true),
        "events": events}


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
    var staged_ledger: RefCounted = _ledger.fork()
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
## N104 acceptance changes exactly one ship, one escrow scalar and one
## payer wallet. The other rows are shared READ-ONLY until the atomic commit.
## Never mutate nested authoritative rows before Schema and N9 agree.
func _n104_owned_accept_stage(source: Dictionary, escrow: String,
        faction_id: String, facility_id: String, ship_id: String,
        faction_payer: bool) -> Dictionary:
    for domain in ["escrow_balances", "faction_treasuries", "facilities", "ships"]:
        if not (source.get(domain) is Dictionary):
            return {}
    if not source["escrow_balances"].has(escrow) or (
            not source["ships"].has(ship_id)) or (
            not (source["ships"][ship_id] is Dictionary)):
        return {}
    if faction_payer:
        if not source["faction_treasuries"].has(faction_id):
            return {}
    elif not source["facilities"].has(facility_id) or (
            not (source["facilities"][facility_id] is Dictionary)):
        return {}
    var stage: Dictionary = source.duplicate()
    stage["escrow_balances"] = source["escrow_balances"].duplicate()
    stage["faction_treasuries"] = source["faction_treasuries"].duplicate()
    stage["facilities"] = source["facilities"].duplicate()
    stage["ships"] = source["ships"].duplicate()
    stage["ships"][ship_id] = source["ships"][ship_id].duplicate(true)
    if not faction_payer:
        stage["facilities"][facility_id] = source["facilities"][facility_id].duplicate(true)
    return stage


    # N104 accept owns only these domains. Detach each mutable write-set
    # before editing; all other World domains remain untouched. Keep the
    # full Schema and N9 account oracles below before the atomic publish.
    var staged: Dictionary = _n104_owned_accept_stage(
        _world, escrow, buyer_faction, str(buyer_market["owner"]),
        sid, native_site_contract)
    if staged.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n104_accept_invalid_owned_write_set"}
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
    var err: String = _measured_schema_validate("L3903", staged)
    if not err.is_empty():
        return {"ok": false, "fatal": true, "reason": "assignment_schema_" + err}
    var accounts: Dictionary = _measured_schema_accounts("L3906", staged)
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
static func _n151_owned_migration_stage(world: Dictionary, source_id: String,
        destination_id: String) -> Dictionary:
    # Only two household records can change in an N151 migration. Keep the
    # registry shallow, but detach both nested records before ANY write.
    # A failed ledger/Schema check discards this stage without touching World.
    if source_id == destination_id or not (world.get("populations") is Dictionary):
        return {}
    var populations: Dictionary = world["populations"]
    if not populations.has(source_id) or not populations.has(destination_id):
        return {}
    if not (populations[source_id] is Dictionary) or not (
            populations[destination_id] is Dictionary):
        return {}
    var stage: Dictionary = world.duplicate()
    var rows: Dictionary = populations.duplicate()
    rows[source_id] = populations[source_id].duplicate(true)
    rows[destination_id] = populations[destination_id].duplicate(true)
    stage["populations"] = rows
    return stage

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
    # Preserve the authoritative rollback boundary while avoiding a full
    # deep copy of every household on the 200*mult paid migration cadence.
    var next_world: Dictionary = _n151_owned_migration_stage(_world, from, to)
    if next_world.is_empty():
        return {"ok": false, "fatal": true, "reason": "n151_invalid_owned_migration_stage"}
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
    var schema_error: String = _measured_schema_validate("L3999", next_world)
    if not schema_error.is_empty():
        return {"ok": false, "fatal": true, "reason": "n151_invalid_committed_world_" + schema_error}
    if next_ledger.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n151_unbalanced_migration_money"}
    var accounts: Dictionary = _measured_schema_accounts("L4004", next_world)
    if accounts.size() != next_ledger.balances_snapshot().size():
        return {"ok": false, "fatal": true, "reason": "n151_new_or_missing_migration_accounts"}
    for account in accounts:
        if int(accounts[account]) != next_ledger.balance(str(account)):
            return {"ok": false, "fatal": true, "reason": "n151_migration_ledger_world_divergence"}
    _world = next_world
    _ledger = next_ledger
    return {"ok": true, "tick": tick, "moved": moved, "wealth": amount,
        "receipt_id": op, "events": [event]}


## Rust engine.rs::scan_crisis_events, AFTER N150 and before apply2.
## Only N39 may persist FacilityOperations.starving_notified. N150 already
## committed MarketHistory.crisis_notified through apply_market_phase.
## Source warning events are returned only AFTER this single World commit.
func apply_native_crisis_phase(tick: int, proposed: Dictionary) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick:
        return {"ok": false, "reason": "crisis_wrong_authoritative_tick"}
    if not proposed.get("ok", false) or typeof(
            proposed.get("tick", null)) != TYPE_INT or int(
            proposed["tick"]) != tick:
        return {"ok": false, "reason": "crisis_missing_native_market_commit"}
    for key in ["market_events", "facility_events",
            "events_after_n39_commit"]:
        if not (proposed.get(key) is Array):
            return {"ok": false, "reason": "invalid_native_crisis_" + key}
    var expected_events: Array = proposed["market_events"].duplicate(true)
    expected_events.append_array(proposed["facility_events"])
    if expected_events != proposed["events_after_n39_commit"]:
        return {"ok": false, "reason": "crisis_event_order_or_contents_changed"}
    # N152 funded contract activity may have happened after N150 on this
    # P2 tick, but it must NEVER silently roll back the persisted market
    # notification bit or fake a different physical shortage count.
    for item in proposed["market_events"]:
        if not (item is Dictionary):
            return {"ok": false, "reason": "invalid_native_market_event"}
        var location: String = str(item.get("location", ""))
        var commodity: String = str(item.get("commodity", ""))
        var market: Dictionary = _world.get("markets", {}).get(location, {})
        if location.is_empty() or commodity.is_empty() or market.is_empty() or (
                str(market.get("id", "")) != str(item.get("market_id", ""))) or (
                not (market.get("history") is Dictionary)):
            return {"ok": false, "reason": "crisis_market_provenance_missing"}
        var history: Dictionary = market["history"]
        if not (history.get("crisis_notified") is Dictionary) or not (
                history.get("shortage_ticks") is Dictionary):
            return {"ok": false, "reason": "crisis_market_flags_not_committed"}
        var flagged: bool = bool(history["crisis_notified"].get(commodity, false))
        var kind: String = str(item.get("kind", ""))
        if kind == "market_crisis":
            if not flagged or typeof(item.get("shortage_ticks", null)) != TYPE_INT or (
                    history["shortage_ticks"].get(commodity, null) != item[
                        "shortage_ticks"]):
                return {"ok": false, "reason": "crisis_market_shortage_mismatch"}
        elif kind == "market_recovered":
            if flagged or history["shortage_ticks"].get(commodity, null) == null:
                return {"ok": false, "reason": "crisis_market_recovery_mismatch"}
        else:
            return {"ok": false, "reason": "unknown_native_market_warning"}
    var live_facilities: Dictionary = NativeCrisisWarnings.propose_facility_warnings(
        _world.get("facilities", {}))
    if not live_facilities.get("ok", false):
        return {"ok": false, "reason": "crisis_live_facilities_rejected:" +
            str(live_facilities.get("reason", ""))}
    if live_facilities["flag_updates"] != proposed.get(
            "facility_flag_updates", {}) or live_facilities["events"] != proposed[
            "facility_events"]:
        return {"ok": false, "reason": "stale_or_replayed_facility_crisis_proposal"}
    if not (proposed.get("facility_flag_updates") is Dictionary):
        return {"ok": false, "reason": "invalid_native_facility_crisis_flags"}
    if not proposed["facility_flag_updates"].is_empty():
        var staged: Dictionary = NativeCrisisPhase.expected_facility_flag_world(
            _world, proposed)
        if not staged.get("ok", false):
            return {"ok": false, "reason": str(staged.get("reason", "crisis_flag_stage_failed"))}
        var next_world: Dictionary = staged["world"]
        var problem: String = _measured_schema_validate("L4081", next_world)
        if not problem.is_empty() or _measured_schema_accounts("L4082", next_world) != _measured_schema_accounts("L4082", _world):
            return {"ok": false, "reason": "crisis_changed_source_economy_or_schema:" +
                problem}
        _world = next_world
    # Not a scheduled future EventQueue. The N158 single TickRunner
    # broadcasts source transitions once immediately after this commit.
    return {"ok": true, "tick": tick,
        "market_count": proposed["market_events"].size(),
        "facility_count": proposed["facility_events"].size(),
        "changed_flags": proposed["facility_flag_updates"].size(),
        "events": expected_events.duplicate(true)}


func apply_market_phase(tick: int, updates: Dictionary,
        expected_version: int = -1) -> bool:
    if not _ready or tick != _last_tick or tick < 1:
        return false
    # Read-set/version preflight rejects malformed N150 observations
    # without allocating a staged World. Full Schema.validate remains the
    # mandatory final oracle before publishing any successful proposal.
    if MarketObservationValidator.validate_observation_proposal(
            _world, updates, expected_version,
            market_observation_version()) != "":
        return false
    if updates.size() != _world["markets"].size():
        return false
    # N150 write set: only six market observation fields are writable.
    # Keep read-only physical supply and every unrelated World domain
    # from the authoritative owner; detach the outer maps and each row
    # before writing. This preserves atomic rejection and the complete
    # source Schema.validate oracle below.
    var staged: Dictionary = _copy_world("L4105", false)
    staged["markets"] = _world["markets"].duplicate()
    for location in updates:
        if not staged["markets"].has(location) or not (updates[location] is Dictionary):
            return false
        var m: Dictionary = staged["markets"][location].duplicate()
        var proposed: Dictionary = updates[location]
        if str(proposed.get("id", "")) != str(m.get("id", "")):
            return false
        for field in ["prices", "demand", "seed_demand", "consumption_window",
                "orders", "history"]:
            if not (proposed.get(field) is Dictionary):
                return false
            # Identical observation dictionaries already belong to N39.
            # Keep the canonical immutable-for-this-phase reference rather
            # than deep-cloning six unchanged fields on every N150 tick.
            # Changed proposals MUST detach before publication; external
            # mutations cannot alias canonical N39.
            if proposed[field] != m.get(field, null):
                m[field] = proposed[field].duplicate(true)
        staged["markets"][location] = m
        # Supply/owner remain the previous canonical physical inventory.
    if _measured_schema_validate("L4121", staged) != "":
        return false
    _world = staged
    _market_observation_version += 1
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
    # N151 writes only paid buyers/sellers/markets and changed sentiment rows.
    # Detach registry maps first, then rows immediately before their first write.
    # A failed ticket cannot mutate any nested authoritative World container.
    var staged: Dictionary = _copy_world("L4144_owned_root", false)
    for domain in ["populations", "facilities", "markets"]:
        staged[domain] = _world[domain].duplicate()
    var owned_populations: Dictionary = {}
    var owned_facilities: Dictionary = {}
    var owned_markets: Dictionary = {}
    var ledger_next: RefCounted = _ledger.fork()
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
        # All preflight checks above are read-only. Copy each row once, so
        # repeated purchases observe earlier staged stock and ledger balances.
        if not owned_populations.has(pid):
            staged["populations"][pid] = pop.duplicate(true)
            owned_populations[pid] = true
        if not owned_facilities.has(fid):
            staged["facilities"][fid] = staged["facilities"][fid].duplicate(true)
            owned_facilities[fid] = true
        if not owned_markets.has(location):
            staged["markets"][location] = market.duplicate(true)
            owned_markets[location] = true
        pop = staged["populations"][pid]
        market = staged["markets"][location]
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
        var next_window: Variant = pm.get("consumption_window", {})
        if real_market.get("consumption_window", {}) != next_window:
            if not owned_markets.has(location):
                staged["markets"][location] = real_market.duplicate(true)
                owned_markets[location] = true
                real_market = staged["markets"][location]
            real_market["consumption_window"] = next_window.duplicate(true)
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
            if real_pop.get(field) != projected_pop[field]:
                if not owned_populations.has(id):
                    staged["populations"][id] = real_pop.duplicate(true)
                    owned_populations[id] = true
                    real_pop = staged["populations"][id]
                real_pop[field] = projected_pop[field]
    for fid in staged["facilities"]:
        if not proposed["facilities"].has(fid) or int(proposed["facilities"][fid].get("credits", -1)) != int(staged["facilities"][fid]["credits"]):
            return false
    if _measured_schema_validate("L4223", staged) != "":
        return false
    # World is unchanged during this account audit. Rebuilding the
    # canonical account table for every account was quadratic in wallets.
    var expected_accounts: Dictionary = _measured_schema_accounts("L4227", staged)
    for account in expected_accounts:
        if ledger_next.balance(str(account)) != int(expected_accounts[account]):
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

## N154 Payroll.pay_shift may mutate both facility rows (including _blocked),
## and only households in the producer faction/location. Manufacturing later
## changes the local market history/supply. Detach all possible write targets
## before calling either routine, even when the wage payment is rejected.
## Keep the remaining growing registries shared and read-only for Schema.
static func _n154_owned_shipyard_payroll_stage(source: Dictionary,
        producer_id: String, owner_id: String, location: String) -> Dictionary:
    for domain in ["facilities", "populations", "markets"]:
        if not (source.get(domain) is Dictionary):
            return {}
    var facilities: Dictionary = source["facilities"]
    var populations: Dictionary = source["populations"]
    var markets: Dictionary = source["markets"]
    if not facilities.has(producer_id) or not facilities.has(owner_id):
        return {}
    if not markets.has(location) or not (markets[location] is Dictionary):
        return {}
    if not (facilities[producer_id] is Dictionary) or not (facilities[owner_id] is Dictionary):
        return {}
    var producer: Dictionary = facilities[producer_id]
    if str(producer.get("location", "")) != location:
        return {}
    var staged: Dictionary = source.duplicate()
    staged["facilities"] = facilities.duplicate()
    staged["populations"] = populations.duplicate()
    staged["markets"] = markets.duplicate()
    staged["facilities"][producer_id] = facilities[producer_id].duplicate(true)
    if owner_id != producer_id:
        staged["facilities"][owner_id] = facilities[owner_id].duplicate(true)
    staged["markets"][location] = markets[location].duplicate(true)
    for pid in populations:
        if not (populations[pid] is Dictionary):
            return {}
        var person: Dictionary = populations[pid]
        if str(person.get("faction", "")) == str(producer.get("faction", "")) and str(person.get("location", "")) == location:
            staged["populations"][pid] = person.duplicate(true)
    return staged


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
        # N154 paid module write set: payroll touches facility shifts/credits
        # and household wealth/employment; manufacturing touches the local
        # market supply/history. Keep every other authoritative domain shared
        # for read-only Schema inspection, never expose mutable aliases to pay_shift.
        var staged: Dictionary = _n154_owned_shipyard_payroll_stage(
            _world, str(id), owner, location)
        if staged.is_empty():
            return {"ok": false, "reason": "n154_invalid_owned_payroll_stage"}
        var ledger_copy: RefCounted = _ledger.fork()
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
        var error: String = _measured_schema_validate("L4476", staged)
        if not error.is_empty():
            return {"ok": false, "reason": "n154_paid_module_invalid_world:" + error}
        var accounts: Dictionary = _measured_schema_accounts("L4479", staged)
        var balances: Dictionary = ledger_copy.balances_snapshot()
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
    # N98 prepare/acknowledge mutate the pending ledger. Detach it from
    # authoritative native_execution before ANY potentially rejected step.
    pending = pending.duplicate(true)
    var gate: Dictionary = NativeN98.next_gate(pending["ledger"])
    var kind: String = str(gate.get("kind", ""))
    var ledger_next: RefCounted = _ledger.fork()
    # N121 may publish only its execution/planner state and, on paid
    # delivery, the N104 contract/escrow/treasury registries. No other
    # World domain is writable. Keep full Schema and N9 oracles below.
    var staged: Dictionary = _copy_world("L4542_owned_root", false)
    for domain in ["native_execution", "native_planner_records",
            "contract_board", "escrow_balances", "faction_treasuries",
            "native_htn_contracts"]:
        staged[domain] = _world[domain].duplicate(true)
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
                    var invalid_block: String = _measured_schema_validate("L4575", staged)
                    if not invalid_block.is_empty() or _measured_schema_accounts("L4576", staged) != _measured_schema_accounts("L4576", _world):
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
    var invalid: String = _measured_schema_validate("L4764", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n121_canonical_n39_schema_" + invalid}
    var accounts: Dictionary = _measured_schema_accounts("L4768", staged)
    var balances: Dictionary = ledger_next.balances_snapshot()
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
    # N100 only publishes one planner record and its tick marker.
    # Detach the owned registry before writing; all other World domains
    # remain read-only and retain their authoritative identity.
    var staged: Dictionary = _copy_world("L4822_owned_root", false)
    staged["native_planner_records"] = _world["native_planner_records"].duplicate(true)
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
    var invalid: String = _measured_schema_validate("L4836", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n100_source_planning_invalid_world:" + invalid}
    if _measured_schema_accounts("L4840", staged) != _measured_schema_accounts("L4840", _world):
        return {"ok": false, "fatal": true, "reason": "n100_forecast_modified_wallets"}
    _world = staged
    return {"ok": true, "due": true, "faction_id": faction,
        "status": record["status"], "reason": record["reason"],
        "native_dispatch_authorized": false,
        "planned_steps": record.get("ledger", {}).get("steps", []).size()}


## Chat2 B4: frozen Rust coordination.rs gives an established starving
## colony's ACTUAL N92 market-stock goal priority before speculative
## Head grants. N100/N98 is still PURE planning; only N121 can create
## the real N104/N9 prepaid supply contract and N14/N15 flight.
## N39 recomputes both N134 baseline and N92 from its current World;
## caller cannot inject a fictitious shortage/alternative/recipient.
func apply_native_b4_colony_aftercare(tick: int, faction: String,
        baseline: Dictionary, original: RefCounted, graph: RefCounted,
        sources: Dictionary, multiplier: int) -> Dictionary:
    if not _ready or tick < 1 or tick != _last_tick or (
            original == null or graph == null or multiplier < 1):
        return {"ok": false, "reason": "b4_not_single_native_faction_tick"}
    if not _world.get("faction_treasuries", {}).has(faction):
        return {"ok": false, "reason": "b4_missing_actual_faction"}
    var live_head: Dictionary = SourceN134Construction.choose(
        _world, sources, original, graph, faction, tick, multiplier)
    if not live_head.get("ok", false):
        return live_head
    if live_head.get("head", {}) != baseline.get("head", {}):
        return {"ok": false, "reason": "b4_stale_or_forged_n134_head"}
    var observed: Dictionary = NativeB4ColonyAftercare.observe(_world)
    if not observed.get("ok", false):
        return observed
    var proposed: Dictionary = NativeB4ColonyAftercare.stock_head(
        _world, observed, faction, live_head.get("head", {}))
    if not proposed.get("ok", false):
        return proposed
    if not proposed.get("promoted", false):
        return {"ok": true, "due": true, "promoted": false,
            "accepted": false, "faction_id": faction, "tick": tick,
            "status": str(proposed.get("reason", "b4_no_actual_colony_goal"))}
    # N100 owns only native_planner_records + its scalar tick. It publishes a
    # detached registry via an owned root, never mutating previous World rows.
    # Keep the prior root for rollback without copying growing histories.
    var prior: Dictionary = _copy_world("b4_n100_prior_owned_root", false)
    var money: Dictionary = _ledger.snapshot()
    var planned: Dictionary = apply_native_hybrid_planning(
        tick, faction, proposed["head"], multiplier)
    if not planned.get("ok", false):
        return planned
    # This is the SAME original N100/N98 state owner and no new World.
    # Fail closed if any non-planner domain or N9 money was altered.
    if _ledger.snapshot() != money or _world.size() != prior.size():
        _world = prior
        return {"ok": false, "fatal": true,
            "reason": "b4_n92_planner_modified_real_money_or_world"}
    for key in prior:
        if key not in ["native_planner_records", "native_planner_last_tick"] and (
                _world[key] != prior[key]):
            _world = prior
            return {"ok": false, "fatal": true,
                "reason": "b4_n92_planner_changed_canonical_domain:" + str(key)}
    var verified: Dictionary = NativeB4ColonyAftercare.verify_promoted_plan(
        _world, faction, proposed, planned)
    if not verified.get("ok", false):
        _world = prior
        return {"ok": false, "fatal": true,
            "reason": str(verified.get("reason", "b4_n98_stock_goal_not_receipted"))}
    return {"ok": true, "due": true, "promoted": true,
        "accepted": bool(verified.get("accepted", false)),
        "status": str(verified.get("status", verified.get(
            "reason", "b4_no_source_native_plan"))),
        "faction_id": faction, "tick": tick,
        "goal": proposed.get("goal", {}).duplicate(true),
        "plan": planned.duplicate(true),
        "fallback_head": proposed.get("fallback_head", {}).duplicate(true),
        "money_spent": 0,
        "actual_dispatch_owner": "n121_one_n104_board_one_n9_ledger"}

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
    # N129 owns only the three wallet-backed domains. Preserve the full
    # Schema/N9 oracle, but do not clone unrelated growing ship/contract data.
    # Every nested facility/household row written below is detached first.
    var staged: Dictionary = _copy_world("L4930_owned_root", false)
    # Treasury entries are scalar credits; shallow copy is fully detached.
    # Facility/household rows are immutable during transfer validation and
    # detached individually below, only when their wallet balance changes.
    # Deep-copying both entire registries here made the row detach below a
    # second deep copy of every paid wallet, including unrelated nested data.
    staged["faction_treasuries"] = _world["faction_treasuries"].duplicate(false)
    staged["facilities"] = _world["facilities"].duplicate(false)
    staged["populations"] = _world["populations"].duplicate(false)
    var wallets: RefCounted = _ledger.fork()
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
    # Detach each changed wallet row before any mutation. The shallow domain
    # dictionaries retain untouched rows as read-only references; rejected
    # transfers and failed Schema/N9 checks cannot leak writes into _world.
    # An unchanged wallet retains its existing dirty/sentiment flags.
    for id in staged["facilities"]:
        if not proposed_facilities.has(id):
            return {"ok": false, "fatal": true, "reason": "n129_missing_native_facility"}
        var next_credits: int = int(proposed_facilities[id])
        var original_facility: Dictionary = _world["facilities"][id]
        if next_credits != int(original_facility["credits"]):
            var owned_facility: Dictionary = original_facility.duplicate(true)
            owned_facility["dirty"] = true
            owned_facility["credits"] = next_credits
            staged["facilities"][id] = owned_facility
    for id in staged["populations"]:
        if not proposed_households.has(id):
            return {"ok": false, "fatal": true, "reason": "n129_missing_native_household"}
        var next_wealth: int = int(proposed_households[id])
        var original_household: Dictionary = _world["populations"][id]
        if next_wealth != int(original_household["wealth"]):
            var owned_household: Dictionary = original_household.duplicate(true)
            # Rust relief.rs marks PopSentiment dirty on actual support.
            owned_household["sentiment_dirty"] = true
            owned_household["wealth"] = next_wealth
            staged["populations"][id] = owned_household
    staged["faction_finance_last_tick"] = tick
    var invalid: String = _measured_schema_validate("L4994", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true, "reason": "n129_world_schema:" + invalid}
    var accounts: Dictionary = _measured_schema_accounts("L4997", staged)
    var actual: Dictionary = wallets.balances_snapshot()
    if accounts.size() != actual.size() or wallets.total() != _ledger.total():
        return {"ok": false, "fatal": true, "reason": "n129_native_total_not_conserved"}
    for account in accounts:
        if int(actual.get(account, -1)) != int(accounts[account]):
            return {"ok": false, "fatal": true,
                "reason": "n129_wallet_world_divergence",
                "account": str(account), "tick": tick,
                "ledger_credits": int(actual.get(account, -1)),
                "world_credits": int(accounts[account])}
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
    # Only the detached territory map and scalar cadence are written. Other
    # domains remain read-only throughout validation and atomic publication.
    var staged: Dictionary = _copy_world("L5034", false)
    staged["body_territory"] = native["bodies"].duplicate(true)
    staged["territory_last_tick"] = tick
    var invalid: String = _measured_schema_validate("L5037", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n150_native_body_territory_invalid:" + invalid}
    if _measured_schema_accounts("L5041", staged) != _measured_schema_accounts("L5041", _world):
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
    # The proposal is detached before publication; Schema and accounts
    # inspect shared domains but never mutate them. No World-wide deep copy.
    var staged: Dictionary = _copy_world("L5070", false)
    staged["faction_relations"] = plan["pairs"].duplicate(true)
    staged["faction_relations_last_tick"] = tick
    var invalid: String = _measured_schema_validate("L5073", staged)
    if not invalid.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "n150_native_relations_invalid_world:" + invalid}
    # This pass changes neither treasury nor market stock. The N9 owner
    # and its immutable transaction history are unchanged by treaties.
    if _measured_schema_accounts("L5079", staged) != _measured_schema_accounts("L5079", _world):
        return {"ok": false, "fatal": true, "reason": "n150_treaties_changed_real_wallets"}
    _world = staged
    return {"ok": true, "due": true, "tick": tick,
        "treaty_changes": plan.get("treaty_changes", []).duplicate(true),
        "pairs": staged["faction_relations"].size(),
        "authority": "n39_one_faction_relations_matrix"}


## Shared by recipe and extraction failure paths. A blocked attempt is a
## physical facility-status transition, never permission to mutate a row
## still reachable from the previous authoritative World generation.
## Keep this stage independent of payroll and market stock: a rejected
## recipe/mining attempt must not publish any proposed inventory or N9 leg.
func _stage_blocked_facility(source: Dictionary, id: String,
        reason: String) -> Dictionary:
    if not source.has("facilities") or not (source["facilities"] is Dictionary):
        return {}
    if not source["facilities"].has(id) or not (source["facilities"][id] is Dictionary):
        return {}
    var before: Dictionary = source["facilities"][id]
    if str(before.get("work_blocked_reason", "")) == reason:
        return source
    var staged: Dictionary = source.duplicate()
    staged["facilities"] = source["facilities"].duplicate()
    var owned: Dictionary = before.duplicate(true)
    owned["work_blocked_reason"] = reason
    staged["facilities"][id] = owned
    return staged

func _blocked(id: String, reason: String) -> Dictionary:
    var staged: Dictionary = _stage_blocked_facility(_world, id, reason)
    if staged.is_empty():
        return {"ok": false, "fatal": true,
            "reason": "blocked_facility_missing:" + id}
    if not is_same(staged, _world):
        var invalid: String = _measured_schema_validate("blocked_production", staged)
        if not invalid.is_empty():
            return {"ok": false, "fatal": true,
                "reason": "blocked_production_invalid_world:" + invalid}
        # No wallet or market delta is permitted on the failure path.
        # Full Schema validation is retained; the stage owns only one row.
        _world = staged
    return {"ok": false, "reason": reason}

## Complete physical checkpoint including N9 balances and receipts, labor
## reservations, lifecycle XP, LOD cursors and finite salvage depletion.
func snapshot() -> Dictionary:
    if not _ready:
        return {}
    return {"version": 1, "tick": _last_tick,
        "world": _copy_world("L5098", true), "ledger": _ledger.snapshot()}

func restore(saved: Dictionary) -> bool:
    if saved.get("version") != 1 or typeof(saved.get("tick")) != TYPE_INT or int(saved["tick"]) < 0:
        return false
    if not (saved.get("world") is Dictionary) or not (saved.get("ledger") is Dictionary):
        return false
    var staged_world: Dictionary = saved["world"].duplicate(true)
    # Godot JSON may materialize exact Rust u64/i64 as floats.
    # Normalize ONLY proven integral N109/N110 fields on a detached copy;
    # never coerce fractional budgets or invent a default policy.
    var normalized_policy: Dictionary = OriginalPolicyCheckpoint.normalize(
        staged_world, int(saved["tick"]))
    if not normalized_policy.get("ok", false):
        return false
    staged_world = normalized_policy["world"]
    if _measured_schema_validate("L5114", staged_world) != "":
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
    # A retired actor's source credits physically disappear, with
    # one explicit N9 destruction receipt. Saving may NOT resurrect a
    # vanished wallet or silently invent a different retirement amount.
    var restored_bank: Dictionary = staged_ledger.snapshot()
    for operation_id in staged_world.get("native_admin_removals", {}):
        var removal: Dictionary = staged_world["native_admin_removals"][operation_id]
        if int(removal.get("tick", -1)) > int(saved["tick"]):
            return false
        var kind: String = str(removal.get("kind", ""))
        var actor_id: String = str(removal.get("id", ""))
        var account: String = (Schema.ship_account(actor_id)
            if kind == "ship" else Schema.facility_account(actor_id))
        var lost: int = int(removal.get("credits_lost", -1))
        var record: Dictionary = restored_bank.get("receipts", {}).get(operation_id, {})
        if restored_bank.get("balances", {}).has(account):
            return false
        if record.get("id") != operation_id or record.get("kind") != (
                "ship_decommissioned" if kind == "ship" else "facility_removed"):
            return false
        if record.get("tick") != removal.get("tick") or record.get("account_closed") != account or record.get("credits_lost") != lost or record.get("legs") != [{"account": account, "delta": -lost}]:
            return false
    var expected: Dictionary = _measured_schema_accounts("L5164", staged_world)
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
    if staged_ledger.balances_snapshot().size() != expected.size():
        return false
    for id in staged_world["facilities"]:
        var shift: Dictionary = staged_world["facilities"][id].get("work_shift", {})
        if not shift.is_empty() and int(shift["tick"]) > int(saved["tick"]):
            return false
    _world = staged_world
    _ledger = staged_ledger
    # Distinct deterministic negative generation namespace after N38:
    # an in-flight pre-restart observation can never alias a new owner.
    _market_observation_version = 0
    _market_observation_restored = true
    _n21_restored = true
    _n21_commit_generation = 0
    _last_tick = int(saved["tick"])
    _ready = true
    return true

## N91 needs only original N9 receipts named by current construction
## deliveries. Missing evidence stays missing; the source funding predicate
## still performs all N15/contract/quantity checks on the same World.
func native_construction_funding_snapshot() -> Dictionary:
    if OS.get_environment("LS_LATE_FUNDING_LEGACY") == "1":
        return ledger_snapshot()
    var receipts: Dictionary = {}
    for row in _world.get("construction_receipts", {}).values():
        if str(row.get("kind", "")) != "delivery" or not _world.get("construction_sites", {}).has(str(row.get("site_id", ""))):
            continue
        var id: String = str(row.get("n9_receipt_id", ""))
        if not receipts.has(id) and _ledger.has_receipt(id):
            receipts[id] = _ledger.receipt_copy(id)
    return {"receipts": receipts}

## Fresh detached runtime projections. No cache, no cross-commit reuse,
## and no reference into canonical World escapes. Unknown/malformed rows
## are preserved for the same downstream validators, not repaired here.
## LS_RUNTIME_FULL_WORLD_READS=1 is the full-copy oracle for replay tests.
func native_runtime_read_snapshot(kind: String) -> Dictionary:
    if not _ready:
        return {}
    if OS.get_environment("LS_RUNTIME_FULL_WORLD_READS") == "1":
        return world_snapshot()
    var domains: Array = []
    var row_fields: Dictionary = {}
    match kind:
        "ship_motion":
            domains = ["ships", "ship_next_token"]
        "market_tick", "market_crisis":
            domains = ["markets", "facilities"]
        "population":
            domains = ["populations", "markets", "facilities"]
            row_fields = {
                "markets": ["id", "owner", "supply", "prices", "consumption_window"],
                "facilities": ["credits"]}
        "station_demand":
            domains = ["markets", "facilities"]
            row_fields = {
                "markets": ["owner", "supply", "prices", "consumption_window"],
                "facilities": ["location", "credits", "faction"]}
        "engineer_dispatch":
            domains = ["ships", "construction_sites", "construction_receipts",
                "cargo_receipts", "contract_board", "facilities", "markets"]
        "faction_ids":
            domains = ["faction_treasuries"]
        _:
            # An unrecognized caller cannot silently receive an empty World.
            return world_snapshot()
    var began: int = Time.get_ticks_usec() if _profile_copy_enabled else 0
    var result: Dictionary = {}
    for domain in domains:
        if not _world.has(domain):
            continue
        var value: Variant = _world[domain]
        if row_fields.has(domain) and value is Dictionary:
            var rows: Dictionary = {}
            for id in value:
                rows[id] = _runtime_read_row(value[id], row_fields[domain])
            result[domain] = rows
        else:
            result[domain] = _runtime_read_copy(value)
    if _profile_copy_enabled:
        _record_timing(_profile_copy_sites, "runtime_read:" + kind,
            maxi(0, Time.get_ticks_usec() - began))
    return result

func _runtime_read_copy(value: Variant) -> Variant:
    if value is Dictionary or value is Array:
        return value.duplicate(true)
    return value

func _runtime_read_row(value: Variant, fields: Array) -> Variant:
    if not (value is Dictionary):
        return _runtime_read_copy(value)
    # Keep malformed/incomplete rows intact, including nonempty-row checks.
    for field in fields:
        if not value.has(field):
            return value.duplicate(true)
    var row: Dictionary = {}
    for field in fields:
        if value.has(field):
            row[field] = _runtime_read_copy(value[field])
    return row

## N146 checks one ship/contract plus physical dock facts, not every
## historical market sample, cargo receipt and unrelated ship memory.
## Called anew for EACH command, including after earlier command commits.
func native_dock_read_snapshot(ship_id: String, contract_id: String) -> Dictionary:
    if not _ready:
        return {}
    if OS.get_environment("LS_RUNTIME_FULL_WORLD_READS") == "1":
        return world_snapshot()
    var began: int = Time.get_ticks_usec() if _profile_copy_enabled else 0
    var result: Dictionary = {}
    if _world.has("ships"):
        result["ships"] = {}
        if _world["ships"].has(ship_id):
            result["ships"][ship_id] = _world["ships"][ship_id].duplicate(true)
    var contracts: Dictionary = _world.get("contract_board", {}).get("contracts", {})
    result["contract_board"] = {"contracts": {}}
    if contracts.has(contract_id):
        result["contract_board"]["contracts"][contract_id] = contracts[contract_id].duplicate(true)
    for domain in ["facilities", "markets"]:
        if not _world.has(domain):
            continue
        var rows: Dictionary = {}
        var fields: Array = (["owner"] if domain == "markets"
            else ["location", "type", "docking_capacity", "abandoned"])
        for id in _world[domain]:
            rows[id] = _runtime_read_row(_world[domain][id], fields)
        result[domain] = rows
    # Passenger colony docking scans all current sites; retain that scan
    # and its exact named construction-dock receipts, without the archive.
    if _world.has("construction_sites"):
        result["construction_sites"] = _world["construction_sites"].duplicate(true)
    var evidence: Dictionary = {}
    var receipts: Dictionary = _world.get("construction_receipts", {})
    for site_id in _world.get("construction_sites", {}):
        var proof_id: String = "n151_colony_dock:" + str(site_id)
        if receipts.has(proof_id):
            evidence[proof_id] = _runtime_read_copy(receipts[proof_id])
    result["construction_receipts"] = evidence
    if _profile_copy_enabled:
        _record_timing(_profile_copy_sites, "runtime_read:dock_command",
            maxi(0, Time.get_ticks_usec() - began))
    return result
