extends "res://scripts/sim/phase1/n39_native_production_tick_runner.gd"
## N158 first executable Phase2 slice:
## one real seed -> N39 physical supply/payroll -> P1 clock/events/orbits
## -> versioned P1 save with N39 native snapshot. No second N23 production.
const GalaxySeedAdapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const MarketPhase = preload("res://scripts/sim/phase2/unified_market_phase.gd")
const StationDemand = preload("res://scripts/sim/phase2/unified_station_demand_phase.gd")
const PopulationPhase = preload("res://scripts/sim/phase2/unified_population_phase.gd")
const ShipPhase = preload("res://scripts/sim/phase2/unified_ship_phase.gd")
const FleetLogistics = preload("res://scripts/sim/phase2/unified_fleet_logistics.gd")
const N153Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const NativeAIExecution = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const NativeConstruction = preload("res://scripts/sim/phase2/unified_native_construction_phase.gd")
const N91Dispatch = preload("res://scripts/sim/phase2/unified_n91_construction_dispatch.gd")
const N134Construction = preload("res://scripts/sim/phase2/unified_n134_construction_head.gd")
const N147Colonies = preload("res://scripts/sim/phase2/unified_n147_colony_migration_observer.gd")
const N151Founding = preload("res://scripts/sim/phase2/unified_n151_colony_founding_phase.gd")
const NativeDiplomacy = preload("res://scripts/sim/phase2/unified_native_diplomacy_phase.gd")
const N91Executor = preload("res://scripts/ported/n91_construction_executor.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const NativeCommands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const ShipRoster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const NativeLocations = preload("res://scripts/sim/ships/native_location_resolver.gd")

var _boot_error: String = ""
var _source_stats: Dictionary = {}
var _last_market_result: Dictionary = {}
var _last_station_demand: Dictionary = {}
var _last_contract_admissions: Dictionary = {}
var _last_n153_result: Dictionary = {}
var _last_research_result: Dictionary = {}
var _last_construction_observation: Dictionary = {}
var _last_construction_result: Dictionary = {}
var _last_n91_result: Dictionary = {}
var _last_n134_result: Dictionary = {}
var _last_n147_result: Dictionary = {}
var _last_n151_founding: Dictionary = {}
var _last_faction_relations: Dictionary = {}
var _last_body_territory: Dictionary = {}
var _faction_sources: Dictionary = {}
var _last_population_result: Dictionary = {}
var _last_ship_result: Dictionary = {}
var _fleet_roster: RefCounted
var _fleet_resolver: RefCounted

func start_from_seed(seed: Dictionary) -> bool:
    _boot_error = ""
    _source_stats = {}
    _last_market_result = {}
    _last_station_demand = {}
    _last_contract_admissions = {}
    _last_n153_result = {}
    _last_research_result = {}
    _last_construction_observation = {}
    _last_construction_result = {}
    _last_n91_result = {}
    _last_n134_result = {}
    _last_n147_result = {}
    _last_n151_founding = {}
    _last_faction_relations = {}
    _last_body_territory = {}
    _faction_sources = {}
    _last_population_result = {}
    _last_ship_result = {}
    _fleet_roster = null
    _fleet_resolver = null
    var projected: Dictionary = GalaxySeedAdapter.from_seed(seed)
    if not projected.get("ok", false):
        _boot_error = str(projected.get("reason", "source_projection_failed"))
        return false
    if not super.start_from_seed(seed):
        _boot_error = "base_world_seed_rejected"
        return false
    if not configure_native_production(projected["world"], maxi(1, clock.tick_multiplier())):
        _boot_error = "physical_production_initialization_rejected"
        return false
    var roster = ShipRoster.new()
    var resolver = NativeLocations.new()
    if not roster.load_seed(seed) or not resolver.load_seed(seed):
        _boot_error = "native_fleet_route_or_position_boot_rejected"
        return false
    if int(projected["stats"].get("ships", -1)) != roster.keys().size():
        _boot_error = "native_fleet_identity_mismatch"
        return false
    _fleet_roster = roster
    _fleet_resolver = resolver
    for source_faction in seed.get("factions", []):
        if not (source_faction is Dictionary):
            _boot_error = "invalid_native_faction_policy"
            return false
        _faction_sources[str(source_faction.get("id", ""))] = source_faction.duplicate(true)
    _source_stats = projected["stats"].duplicate(true)
    return true

## Rust TickConfig::tick_multiplier() is dynamic across speed changes:
## default 8 TPS / 0.25 speed = 32, so 5*32 = 160 real ticks per cycle.
func _advance_one_tick() -> void:
    _tick_multiplier = maxi(1, clock.tick_multiplier())
    super._advance_one_tick()

## The original N150 market phase runs AFTER paid facilities, in the
## SAME N39 world and one clock. N131 reprice produces NO stock or cash.
func _execute_integrated_phase(phase: String, tick: int) -> bool:
    if phase == "factions":
        # Read-only counters are per-tick. Never show yesterday's funded
        # N134 commission as a new building order today.
        _last_n134_result = {"ok": true, "tick": tick,
            "commissioned": [], "blocked": [], "heads": {},
            "status": "N134_COORDINATION_NOT_DUE"}
        # Rust faction::tick_factions recalculates BodyTerritory FIRST.
        # A world-owned N39 commit, not a UI-local one-off snapshot.
        var territory_pass: Dictionary = production.apply_native_body_territory(
            tick, _tick_multiplier, world)
        if not territory_pass.get("ok", false):
            _last_body_territory = territory_pass
            return false
        if territory_pass.get("due", false):
            _last_body_territory = territory_pass.duplicate(true)
        if _fleet_roster == null or _fleet_resolver == null:
            _last_n153_result = {"ok": false, "reason": "missing_native_ship_ai_sources"}
            return false
        var canonical: Dictionary = production.world_snapshot()
        if not canonical.has("contract_board") or not canonical.has("ships"):
            return true # genuinely old save; do not fabricate a fleet or board
        var positions: Dictionary = _fleet_resolver.positions_from_world(world,
            calendar.native_time_units + clock.tick_scale(), calendar.origin_known)
        if not positions.get("ok", false):
            _last_n153_result = {"ok": false,
                "reason": str(positions.get("error", "missing_real_ship_positions"))}
            return false
        var selection: Dictionary = N153Dispatch.propose(canonical,
            _fleet_roster.registry.graph(), positions["positions"],
            _fleet_resolver, tick, clock.tick_scale(), _faction_sources)
        if not selection.get("ok", false):
            _last_n153_result = selection
            return false
        _last_n153_result = {"ok": true, "tick": tick,
            "accepted": [], "blocked": selection.get("blocked", []).duplicate(true),
            "status": "N153_ADMISSION_COMPLETE"}
        # N146 is the source command-buffer boundary between AI decision
        # and N39/N104 authoritative Apply. No direct model mutation from
        # the selector, no new ContractBoard owned by the AI.
        var ai_commands = NativeCommands.new()
        if not ai_commands.begin_phase(tick, "factions"):
            _last_n153_result = {"ok": false, "reason": "n146_faction_phase_rejected"}
            return false
        var by_id: Dictionary = {}
        for candidate in selection.get("candidates", []):
            var cid: String = str(candidate.get("contract_id", ""))
            var ship_id: String = str(candidate.get("ship_id", ""))
            if cid.is_empty() or ship_id.is_empty() or by_id.has(cid):
                _last_n153_result = {"ok": false, "reason": "duplicate_n153_accept_candidate"}
                return false
            var command: Dictionary = NativeCommands.make_command("AcceptContract", {
                "ship": ship_id, "ship_id": ship_id, "contract_id": cid})
            if command.is_empty() or not ai_commands.push(command):
                _last_n153_result = {"ok": false, "reason": "n146_invalid_contract_command"}
                return false
            by_id[cid] = candidate
        _last_n153_result["n146_accept_commands"] = ai_commands.len()
        for command in ai_commands.drain():
            var cid: String = str(command["contract_id"])
            var candidate: Dictionary = by_id[cid]
            if str(command["ship"]) != str(candidate["ship_id"]) or str(command["ship_id"]) != str(candidate["ship_id"]):
                _last_n153_result = {"ok": false, "reason": "n146_contract_actor_mismatch"}
                return false
            var admission: Dictionary = production.accept_autonomous_delivery(tick, candidate, _faction_sources)
            if admission.get("ok", false):
                _last_n153_result["accepted"].append(admission.duplicate(true))
            elif admission.get("fatal", false):
                _last_n153_result = {"ok": false,
                    "reason": str(admission.get("reason", "n153_single_world_commit_rejected"))}
                return false
            else:
                _last_n153_result["blocked"].append({
                    "contract_id": cid, "ship_id": str(candidate["ship_id"]),
                    "reason": str(admission.get("reason", "n104_acceptance_rejected"))})
        # Gate4 source N155/N143 research follows the same faction tick
        # after real N150 market data and N39 facility staffing. There is
        # no separate head clock, market, treasury or N9 ledger.
        _last_research_result = production.apply_native_research_phase(
            tick, _faction_sources, _tick_multiplier)
        if not _last_research_result.get("ok", false):
            return false
        # Source N91 chooses a paid site in the same native system.
        # The full directed N14 route, origin N21 undock and fuel are
        # preflighted before N39 atomically admits its persistent N84 BT.
        var engineer_plan: Dictionary = N91Dispatch.propose(
            production.world_snapshot(), _fleet_resolver, tick,
            production.ledger_snapshot(), _fleet_roster.registry.graph(),
            positions["positions"], clock.tick_scale())
        if not engineer_plan.get("ok", false):
            _last_n91_result = engineer_plan
            return false
        _last_n91_result = production.apply_native_construction_assignments(
            tick, engineer_plan.get("assignments", []),
            _fleet_resolver, _fleet_roster.registry.graph(),
            positions["positions"], clock.tick_scale())
        if not _last_n91_result.get("ok", false):
            return false
        _last_n91_result["blocked"] = engineer_plan.get("blocked", []).duplicate(true)
        # Original N141 paid shifts require real N84 Construct leaf,
        # engineering crew, physical N21 dock and the SAME N9 treasury.
        _last_construction_result = production.apply_native_construction_labor(
            tick, _tick_multiplier)
        if not _last_construction_result.get("ok", false):
            return false
        # N154 preview runs at the ORIGINAL construction labor cadence.
        # No N134 head-approved Execute command exists here yet: observers
        # see real offers/reasons, never fictitious funded construction.
        if tick % maxi(1, 5 * _tick_multiplier) == 0:
            var build_world: Dictionary = production.world_snapshot()
            var preview: Dictionary = {"ok": true, "tick": tick, "factions": {}}
            if build_world.has("construction_sites"):
                var faction_ids: Array = build_world.get("faction_treasuries", {}).keys()
                faction_ids.sort()
                for faction in faction_ids:
                    var seen: Dictionary = NativeConstruction.observe(build_world,
                        _faction_sources, world, _fleet_roster.registry.graph(),
                        str(faction), tick)
                    if not seen.get("ok", false):
                        preview = {"ok": false,
                            "reason": str(seen.get("reason", "n154_source_observation_failed"))}
                        break
                    preview["factions"][faction] = seen["view"].duplicate(true)
            _last_construction_observation = preview
        # A head may commission no more often than the original
        # strategic N134 subsidy check interval (60*mult). The N111
        # comparator evaluates actual source input/production forecasts.
        # An N154 offer alone is NEVER permission to debit treasury.
        if tick % maxi(1, 60 * _tick_multiplier) == 0:
            _last_n134_result = {"ok": true, "tick": tick,
                "commissioned": [], "blocked": [], "heads": {},
                "status": "N134_SOURCE_EVALUATED"}
            var head_world: Dictionary = production.world_snapshot()
            if head_world.has("construction_sites"):
                var head_factions: Array = head_world.get("faction_treasuries", {}).keys()
                head_factions.sort()
                for faction in head_factions:
                    var planned_build: Dictionary = N134Construction.choose(
                        head_world, _faction_sources, world,
                        _fleet_roster.registry.graph(),
                        str(faction), tick, _tick_multiplier)
                    if not planned_build.get("ok", false):
                        _last_n134_result["blocked"].append({
                            "faction_id": str(faction),
                            "reason": str(planned_build.get("reason", "N134_source_comparison_unavailable"))})
                        continue
                    _last_n134_result["heads"][faction] = planned_build.get("head", {}).duplicate(true)
                    if not planned_build.get("authorized", false):
                        _last_n134_result["blocked"].append({
                            "faction_id": str(faction),
                            "reason": str(planned_build.get("reason", "head_not_authorized"))})
                        continue
                    var posted_site: Dictionary = production.post_authorized_native_construction(
                        tick, planned_build["staged"])
                    if posted_site.get("ok", false):
                        _last_n134_result["commissioned"].append(posted_site.duplicate(true))
                        head_world = production.world_snapshot()
                    elif posted_site.get("fatal", false):
                        _last_n134_result = {"ok": false,
                            "reason": str(posted_site.get("reason", "N134_N154_N9_apply_failed"))}
                        return false
                    else:
                        _last_n134_result["blocked"].append({
                            "faction_id": str(faction),
                            "reason": str(posted_site.get("reason", "source_N154_unfunded"))})
        # Source N92 -> N147 workforce proposals run on the existing
        # strategic cadence. These are observable native intents ONLY.
        # N104 passenger embark/disembark has no canonical P2 Apply yet,
        # so no phantom passenger order or minted population is admitted.
        if tick == 1 or tick % maxi(1, 200 * _tick_multiplier) == 0:
            _last_n151_founding = N151Founding.scan(
                production.world_snapshot(), world,
                _fleet_roster.registry.graph(), tick, _tick_multiplier)
            if not _last_n151_founding.get("ok", false):
                return false
        if tick == 1 or tick % maxi(1, 60 * _tick_multiplier) == 0:
            _last_n147_result = N147Colonies.observe(
                production.world_snapshot(), _fleet_roster.registry.graph(),
                _fleet_resolver, positions["positions"], tick, clock.tick_scale())
            if not _last_n147_result.get("ok", false):
                return false
        # A blocked or empty N154/N147 preview is NOT a fatal tick.
        return true
    if phase == "ships":
        # The base TickRunner has ALREADY advanced real body orbits. Ship
        # targets move with that same World and original native calendar.
        var current: Dictionary = production.world_snapshot()
        if not current.has("ships"):
            return true # genuinely old checkpoints do not invent 24 ships
        if _fleet_resolver == null:
            _last_ship_result = {"ok": false, "reason": "native_fleet_resolver_missing"}
            return false
        var locations: Dictionary = _fleet_resolver.positions_from_world(world,
            calendar.native_time_units + clock.tick_scale(), calendar.origin_known)
        if not bool(locations.get("ok", false)):
            _last_ship_result = {"ok": false, "reason": str(locations.get("error", "missing_native_positions"))}
            return false
        var proposal: Dictionary = ShipPhase.advance(current,
            locations["positions"], tick, clock.tick_scale(), _fleet_resolver)
        if not proposal.get("ok", false):
            _last_ship_result = proposal
            return false
        if not production.apply_ship_phase(tick, proposal):
            _last_ship_result = {"ok": false, "reason": "single_world_ship_commit_rejected"}
            return false
        _last_ship_result = {"ok": true, "tick": tick,
            "outcomes": proposal.get("outcomes", {}).duplicate(true),
            "autonomous_departures": [], "autonomous_blocked": []}
        # The execution authority is N84 (persistent BT), which emits
        # N146 commands, checked against N14 physical transit and applied
        # ONCE through N39 World. No hand-written contract-to-route loop.
        var scheduled: Dictionary = production.world_snapshot()
        var planned: Dictionary = NativeAIExecution.propose(scheduled,
            _fleet_roster.registry.graph(), locations["positions"], tick,
            clock.tick_scale())
        if not planned.get("ok", false):
            _last_ship_result = planned
            return false
        if planned.get("changed", false):
            if not production.apply_ship_phase(tick, planned):
                _last_ship_result = {"ok": false,
                    "reason": "n84_n146_canonical_ship_commit_rejected"}
                return false
        _last_ship_result["n84_trace"] = planned.get("trace", []).duplicate(true)
        _last_ship_result["n146_command_count"] = planned.get("commands", []).size()
        _last_ship_result["n97_paid_moves"] = []
        _last_ship_result["n21_auto_dock"] = []
        for command in planned.get("commands", []):
            var kind: String = str(command.get("kind", ""))
            var ship_id: String = str(command.get("ship", ""))
            if kind == "BeginTransit":
                _last_ship_result["autonomous_departures"].append({
                    "ship_id": ship_id, "from": str(command.get("from", "")),
                    "to": str(command.get("to", "")), "tick": tick})
                continue
            if kind in ["RequestDock", "ReleaseDock"]:
                var snapshot: Dictionary = production.world_snapshot()
                var cid: String = str(command.get("contract_id", ""))
                var contract: Dictionary = snapshot.get("contract_board", {}).get("contracts", {}).get(cid, {})
                var ship: Dictionary = snapshot.get("ships", {}).get(ship_id, {})
                var operation: String = "dock" if kind == "RequestDock" else "undock"
                # After the N97 pickup the ship is STILL physically docked
                # at the source, although N104 stage is now picked_up.
                # Do not confuse contractual destination with dock location.
                var expected_loc: String = str(contract.get("source_location", "")) if str(contract.get("status", "")) == "accepted" else str(contract.get("destination_location", ""))
                if operation == "undock":
                    expected_loc = str(ship.get("location", ""))
                var source_loc: String = str(contract.get("source_location", ""))
                var dest_loc: String = str(contract.get("destination_location", ""))
                # An N91 engineer site is a noncommercial paid job:
                # authorize its N21 dock against the actual N154 site and
                # the persisted N84 Construct target, NOT an invented
                # N104 cargo contract.
                var construction_site_id: String = str(command.get("construction_site_id", ""))
                if not construction_site_id.is_empty():
                    var site: Dictionary = snapshot.get("construction_sites", {}).get(construction_site_id, {})
                    var bt: Variant = ship.get("current_bt", null)
                    var approved: bool = not site.is_empty() and bt is Dictionary and N91Executor.target(bt) == construction_site_id
                    approved = approved and str(ship.get("current_goal", "")) == "construct" and str(ship.get("active_contract_id", "")) == ""
                    approved = approved and str(site.get("faction_id", "")) == str(ship.get("faction_id", ""))
                    # A remote engineer may release the PHYSICAL origin dock
                    # before flight, while docking at the project itself
                    # still requires arrival at the paid N154 location.
                    if operation == "dock":
                        approved = approved and str(site.get("location_name", "")) == str(ship.get("location", ""))
                    else:
                        var origin_dock: Dictionary = snapshot.get("facilities", {}).get(str(ship.get("docked_at", "")), {})
                        approved = approved and not origin_dock.is_empty() and str(origin_dock.get("location", "")) == str(ship.get("location", ""))
                    approved = approved and str(command.get("facility_location", "")) == str(ship.get("location", ""))
                    if not approved:
                        _last_ship_result = {"ok": false, "reason": "n91_n146_unverified_site_dock"}
                        return false
                    var op_id: String = "n91:" + construction_site_id + ":" + ship_id + ":" + operation
                    var real_request: Dictionary = FleetLogistics.command(
                        snapshot, operation, ship_id, op_id, tick)
                    if not real_request.get("ok", false):
                        _last_ship_result["autonomous_blocked"].append({
                            "ship_id": ship_id, "site_id": construction_site_id,
                            "reason": "n91_n21_" + str(real_request.get("reason", "real_dock_unavailable"))})
                        continue
                    if not production.apply_fleet_logistics(tick, real_request, true):
                        _last_ship_result = {"ok": false, "reason": "n91_n21_atomic_dock_rejected"}
                        return false
                    _last_ship_result["n21_auto_dock"].append({
                        "ship_id": ship_id, "site_id": construction_site_id,
                        "operation": operation, "location": str(ship.get("location", ""))})
                    continue
                var valid_dock: bool = (expected_loc == source_loc or expected_loc == dest_loc)
                if operation == "dock":
                    valid_dock = expected_loc == source_loc if str(contract.get("status", "")) == "accepted" else expected_loc == dest_loc
                else:
                    # Native GOAP may begin from a ship docked at the
                    # previous delivery's station, unrelated to this job.
                    var real_dock_id: String = str(ship.get("docked_at", ""))
                    if snapshot.get("facilities", {}).has(real_dock_id):
                        valid_dock = str(snapshot["facilities"][real_dock_id].get("location", "")) == expected_loc
                if contract.is_empty() or str(ship.get("active_contract_id", "")) != cid or not valid_dock or expected_loc.is_empty() or str(command.get("facility_location", "")) != expected_loc:
                    _last_ship_result = {"ok": false, "reason": "n146_dock_contract_mismatch"}
                    return false
                var stage: String = "source" if expected_loc == source_loc else ("destination" if expected_loc == dest_loc else "origin")
                var operation_id: String = "contract:" + cid + ":" + operation + ":" + stage
                var dock_proposal: Dictionary = FleetLogistics.command(
                    snapshot, operation, ship_id, operation_id, tick)
                if not dock_proposal.get("ok", false):
                    _last_ship_result["autonomous_blocked"].append({
                        "ship_id": ship_id, "contract_id": cid,
                        "reason": "n21_" + str(dock_proposal.get("reason", "dock_not_available"))})
                    continue
                if not production.apply_fleet_logistics(tick, dock_proposal, true):
                    _last_ship_result = {"ok": false,
                        "reason": "n21_single_world_dock_apply_rejected"}
                    return false
                _last_ship_result["n21_auto_dock"].append({
                    "ship_id": ship_id, "contract_id": cid,
                    "operation": operation, "location": expected_loc})
                continue
            if kind == "RequestShipTransaction":
                var cid: String = str(command.get("contract_id", ""))
                var operation: String = str(command.get("operation", ""))
                if operation not in ["pickup", "delivery"]:
                    _last_ship_result = {"ok": false, "reason": "n146_unknown_contract_transaction"}
                    return false
                var receipt: Dictionary = production.apply_autonomous_contract_cargo(
                    tick, ship_id, cid, operation)
                if receipt.get("ok", false):
                    _last_ship_result["n97_paid_moves"].append(receipt.duplicate(true))
                elif receipt.get("fatal", false):
                    _last_ship_result = {"ok": false,
                        "reason": str(receipt.get("reason", "n97_canonical_commit_failed"))}
                    return false
                else:
                    _last_ship_result["autonomous_blocked"].append({
                        "ship_id": ship_id, "contract_id": cid,
                        "reason": "n97_" + str(receipt.get("reason", "payment_or_stock_unavailable"))})
                continue
            _last_ship_result = {"ok": false, "reason": "n146_unsupported_fleet_command"}
            return false
        for record in planned.get("trace", []):
            if str(record.get("reason", "")).begins_with("awaiting_native_paid_"):
                _last_ship_result["autonomous_blocked"].append({
                    "ship_id": str(record.get("ship_id", "")),
                    "contract_id": str(record.get("contract_id", "")),
                    "reason": str(record.get("reason", ""))})
        return true
    if phase == "populations":
        var population_plan: Dictionary = PopulationPhase.propose(
            production.world_snapshot(), tick, clock.tick_scale(), _tick_multiplier)
        if not population_plan.get("ok", false):
            _last_population_result = population_plan
            return false
        # On the sparse 200×mult migration boundary, N151 consumption
        # and demographic transfer are one phase as far as the tick runner
        # is concerned. Keep a source-authoritative rollback snapshot so
        # a rejected migration cannot leave half of this phase published.
        var migration_due: bool = bool(population_plan["native_result"].get("due", {}).get("migration", false))
        var population_before: Dictionary = production.snapshot() if migration_due else {}
        if not production.apply_population_phase(tick, population_plan["native_result"]):
            _last_population_result = {"ok": false,
                "reason": "population_single_ledger_commit_rejected"}
            return false
        # Rust population Phase 19d: after purchases and sentiment,
        # execute ONE migration transfer on the original 200*mult cadence.
        # N39 recomputes and atomically commits both households and N9.
        var native_migration: Dictionary = {"ok": true, "moved": 0,
            "wealth": 0, "events": []}
        if migration_due:
            native_migration = production.apply_native_population_migration(
                tick, _tick_multiplier)
            if not native_migration.get("ok", false):
                if not production.restore(population_before):
                    _last_population_result = {"ok": false,
                        "reason": "n151_population_phase_rollback_failed"}
                else:
                    _last_population_result = native_migration
                return false
        var population_events: Array = population_plan["native_result"].get("events", []).duplicate(true)
        population_events.append_array(native_migration.get("events", []))
        _last_population_result = {"ok": true, "tick": tick,
            "purchases": int(population_plan["purchase_count"]),
            "migration_moved": int(native_migration.get("moved", 0)),
            "migration_wealth": int(native_migration.get("wealth", 0)),
            "migration_receipt_id": str(native_migration.get("receipt_id", "")),
            "events": population_events}
        return true
    # The frozen Rust engine calls relations AFTER faction, progression
    # and colony phases. Update the existing matrix only on 200×mult.
    # Derive territorial control from real present facilities and bodies,
    # not colored UI markers or an external territory service.
    if phase == "relations":
        _last_faction_relations = production.apply_native_faction_relations(
            tick, _tick_multiplier)
        if not _last_faction_relations.get("ok", false):
            return false
        return true
    if phase != "markets":
        return true
    var proposal: Dictionary = MarketPhase.propose(
        production.world_snapshot(), tick, _tick_multiplier)
    if not proposal.get("ok", false):
        _last_market_result = proposal
        return false
    if not production.apply_market_phase(tick, proposal["updates"]):
        _last_market_result = {"ok": false, "reason": "market_world_commit_rejected"}
        return false
    _last_market_result = {"ok": true, "tick": tick,
        "market_count": int(proposal["market_count"])}
    # N135 observes actual N151 consumption after N150 price commit.
    # N39 alone admits funded N104 contracts and N9 escrow in one atomic
    # commit. Demand previews are not themselves contracts or ship orders.
    _last_station_demand = StationDemand.propose(production.world_snapshot(), tick)
    if not _last_station_demand.get("ok", false):
        return false
    _last_contract_admissions = {"ok": true, "tick": tick,
        "posted": [], "blocked": [], "status": "POSTING_COMPLETE"}
    for demand in _last_station_demand.get("proposals", []):
        if not (demand is Dictionary):
            _last_contract_admissions = {"ok": false,
                "reason": "invalid_n135_candidate", "tick": tick}
            return false
        var admission: Dictionary = production.post_funded_contract(tick, demand)
        if admission.get("ok", false):
            _last_contract_admissions["posted"].append(admission.duplicate(true))
        elif admission.get("fatal", false):
            _last_contract_admissions = {"ok": false, "tick": tick,
                "reason": str(admission.get("reason", "canonical_post_failed"))}
            return false
        else:
            # A stale allocation/occupied supplier or already funded need
            # is a normal refusal, NOT fake contract execution.
            _last_contract_admissions["blocked"].append({
                "demand_id": str(demand.get("id", "")),
                "reason": str(admission.get("reason", "rejected"))})
    return true

## Propagate the actual rejected proposal/commit reason to the sole
## authoritative tick runner. A failed paid tick remains frozen.
func _integrated_phase_failure_reason(phase: String) -> String:
    var result: Dictionary = {}
    if phase == "populations":
        result = _last_population_result
    elif phase == "ships":
        result = _last_ship_result
    elif phase == "factions":
        if not _last_body_territory.get("ok", true):
            return str(_last_body_territory.get("reason", "native_territory_phase_rejected"))
        result = _last_n147_result if not _last_n147_result.get("ok", true) else (_last_research_result if not _last_research_result.get("ok", true) else (_last_n134_result if not _last_n134_result.get("ok", true) else (_last_n91_result if not _last_n91_result.get("ok", true) else (_last_construction_result if not _last_construction_result.get("ok", true) else _last_n153_result))))
    elif phase == "relations":
        result = _last_faction_relations if not _last_faction_relations.get("ok", true) else _last_body_territory
    elif phase == "markets":
        result = _last_station_demand if not _last_station_demand.get("ok", true) else (_last_contract_admissions if not _last_contract_admissions.get("ok", true) else _last_market_result)
    var detail: String = str(result.get("reason", "integrated_phase_rejected"))
    return detail if not detail.is_empty() else "integrated_phase_rejected"

func last_market_result() -> Dictionary:
    return _last_market_result.duplicate(true)

func station_demand_snapshot() -> Dictionary:
    return _last_station_demand.duplicate(true)

## Durable N104 contracts live in N39 World; this is only a read-only view.
func funded_contracts_snapshot() -> Dictionary:
    return production.contract_snapshot() if _native_enabled else {}

func contract_admissions_snapshot() -> Dictionary:
    return _last_contract_admissions.duplicate(true)

func last_population_result() -> Dictionary:
    return _last_population_result.duplicate(true)


func last_ship_result() -> Dictionary:
    return _last_ship_result.duplicate(true)

func last_n153_result() -> Dictionary:
    return _last_n153_result.duplicate(true)

func last_native_research_result() -> Dictionary:
    return _last_research_result.duplicate(true)

func last_native_construction_observation() -> Dictionary:
    return _last_construction_observation.duplicate(true)

func last_native_construction_labor() -> Dictionary:
    return _last_construction_result.duplicate(true)

func last_native_n91_assignment() -> Dictionary:
    return _last_n91_result.duplicate(true)

func last_native_colony_migration() -> Dictionary:
    return _last_n147_result.duplicate(true)

func last_native_n134_construction() -> Dictionary:
    return _last_n134_result.duplicate(true)


## Read-only canonical ship inventory; source IDs are generated by the
## frozen N4 registry, not hidden UUIDs or a second ECS ship owner.
func fleet_snapshot() -> Dictionary:
    return production.world_snapshot().get("ships", {}).duplicate(true) if _native_enabled else {}


## A strictly controlled ship order (not fleet AI). N14 checks the real
## directed Rust route, native positions, fuel and active transit; N39 owns
## the ONLY actual world commit and persisted token cursor.
func request_ship_departure(ship_id: String, destination: String) -> Dictionary:
    if not _native_enabled or _fleet_roster == null or _fleet_resolver == null:
        return {"ok": false, "reason": "fleet_unavailable"}
    if not last_phase_failure().is_empty():
        return {"ok": false, "reason": "simulation_phase_failed"}
    var snapshot: Dictionary = production.world_snapshot()
    if not snapshot.has("ships"):
        return {"ok": false, "reason": "old_save_has_no_fleet"}
    var positions: Dictionary = _fleet_resolver.positions_from_world(world,
        calendar.native_time_units, calendar.origin_known)
    if not positions.get("ok", false):
        return {"ok": false, "reason": str(positions.get("error", "invalid_positions"))}
    var proposed: Dictionary = ShipPhase.depart(snapshot, _fleet_roster.registry.graph(),
        positions["positions"], tick_count, clock.tick_scale(), ship_id, destination)
    if not proposed.get("ok", false):
        return proposed
    if not production.apply_ship_phase(tick_count, proposed, true):
        return {"ok": false, "reason": "canonical_ship_command_rejected"}
    return {"ok": true, "ship": ship_id, "destination": destination,
        "tick": tick_count, "next_token": int(proposed["next_token"])}



## N21 dock/undock and N15 local Market warehouse load/unload. All manual
## actions create one atomic N39 World transition with durable op receipts.
## These are physical transfers, not market purchases or paid contracts.
func request_ship_dock(ship_id: String, operation_id: String) -> Dictionary:
    return _command_fleet_logistics("dock", ship_id, operation_id)

func request_ship_undock(ship_id: String, operation_id: String) -> Dictionary:
    return _command_fleet_logistics("undock", ship_id, operation_id)

func request_ship_cargo(ship_id: String, operation_id: String,
        direction: String, quantities: Dictionary) -> Dictionary:
    if direction not in ["load", "unload"]:
        return {"ok": false, "reason": "invalid_cargo_direction"}
    return _command_fleet_logistics(direction, ship_id, operation_id, quantities)

func _command_fleet_logistics(action: String, ship_id: String,
        operation_id: String, quantities: Dictionary = {}) -> Dictionary:
    if not _native_enabled or not last_phase_failure().is_empty():
        return {"ok": false, "reason": "single_world_unavailable"}
    var proposal: Dictionary = FleetLogistics.command(production.world_snapshot(),
        action, ship_id, operation_id, tick_count, quantities)
    if not proposal.get("ok", false):
        return proposal
    if not production.apply_fleet_logistics(tick_count, proposal):
        return {"ok": false, "reason": "canonical_fleet_logistics_commit_rejected"}
    return proposal["receipt"].duplicate(true)

## Advertise only phases currently wired to this one real TickRunner.
## Older checkpoints intentionally lack the N46 fleet, not refilled silently.
func implemented_phases() -> PackedStringArray:
    if not _native_enabled:
        return super.implemented_phases()
    var phases: PackedStringArray = PackedStringArray(["bodies"])
    if production.world_snapshot().has("ships"):
        phases.append("ships")
    phases.append("facilities")
    phases.append("populations")
    phases.append("markets")
    phases.append("factions")
    phases.append("relations")
    return phases


func boot_error() -> String:
    return _boot_error

func production_stats() -> Dictionary:
    return _source_stats.duplicate(true)

func economy_snapshot() -> Dictionary:
    return production.world_snapshot() if _native_enabled else {}

func _research_completion_count(current: Dictionary) -> int:
    var count: int = 0
    for completed in current.get("research", {}).values():
        if completed is Array:
            count += completed.size()
    return count

func economy_summary() -> Dictionary:
    if not _native_enabled:
        return {}
    var current: Dictionary = production.world_snapshot()
    var results: Dictionary = last_native_result()
    var paid: int = 0
    var recipes: int = 0
    var mined: int = 0
    for receipt in results.get("receipts", []):
        if not (receipt is Dictionary):
            continue
        paid += int(receipt.get("wages", 0))
        if receipt.get("kind") == "recipes":
            recipes += 1
        elif receipt.get("kind") == "mining":
            mined += 1
    # N156 self-repairs are real paid WorkShift receipts, not recipes;
    # include their wages in the live observer's single-ledger payroll.
    var repair_count: int = 0
    for repair in results.get("paid_repairs", []):
        if not (repair is Dictionary):
            continue
        paid += int(repair.get("wages", 0))
        repair_count += 1
    var restock_count: int = 0
    for transaction in results.get("service_restock", []):
        if transaction is Dictionary:
            restock_count += 1
    var n153_first_blocker: String = "—"
    var blocked: Array = _last_n153_result.get("blocked", [])
    if not blocked.is_empty() and blocked[0] is Dictionary:
        n153_first_blocker = str(blocked[0].get("reason", "unknown"))
    return {
        "tick": tick_count,
        "markets": current["markets"].size(),
        "facilities": current["facilities"].size(),
        "population_groups": current["populations"].size(),
        "last_wages_paid": paid,
        "last_recipe_facilities": recipes,
        "last_mining_facilities": mined,
        "last_paid_repairs": repair_count,
        "last_service_restock": restock_count,
        "last_repair_failures": results.get("repair_failures", {}).duplicate(true),
        "last_failures": results.get("failures", {}).duplicate(true),
        "last_result_ok": results.get("ok", true),
        "market_phase_ok": _last_market_result.get("ok", null),
        "market_phase_tick": _last_market_result.get("tick", -1),
        "station_demand_candidates": _last_station_demand.get("proposals", []).size(),
        "station_demand_blocked": _last_station_demand.get("blocked", []).size(),
        "station_demand_status": str(_last_station_demand.get("status", "NOT_EVALUATED")),
        "funded_contract_count": current.get("contract_board", {}).get("contracts", {}).size(),
        "funded_contracts_this_tick": _last_contract_admissions.get("posted", []).size(),
        "n153_accepted_this_tick": _last_n153_result.get("accepted", []).size(),
        "research_paid_shifts": _last_research_result.get("paid", []).size(),
        "research_blocked_factions": _last_research_result.get("blocked", []).size(),
        "research_total_completed": _research_completion_count(current),
        "construction_head_commissions_this_tick": _last_n134_result.get("commissioned", []).size(),
        "construction_head_blocked_this_tick": _last_n134_result.get("blocked", []).size(),
        "construction_engineers_assigned_this_tick": _last_n91_result.get("assigned", []).size(),
        "construction_paid_labor_this_tick": _last_construction_result.get("paid", []).size(),
        "construction_new_facilities_this_tick": _last_construction_result.get("materialized", []).size(),
        "construction_blocked_labor_this_tick": _last_construction_result.get("blocked", []).size(),
        "colony_founding_status": str(_last_n151_founding.get("status", "NOT_EVALUATED")),
        "colony_founding_ready_unapproved": _last_n151_founding.get("ready", []).size(),
        "colony_founding_blocked": _last_n151_founding.get("blocked", []).duplicate(true),
        "colony_migration_status": str(_last_n147_result.get("status", "NOT_EVALUATED")),
        "colony_observed_groups": _last_n147_result.get("views", []).size(),
        "colony_passenger_proposals_unposted": _last_n147_result.get("ready", []).size(),
        "colony_passenger_contracts_posted": _last_n147_result.get("posted", []).size(),
        "colony_migration_blocked_last_scan": _last_n147_result.get("blocked", []).size(),
        "colony_last_scan_tick": int(_last_n147_result.get("tick", -1)),
        "construction_sites": current.get("construction_sites", {}).size(),
        "construction_live_paid_contracts": current.get("construction_contracts", {}).size(),
        "construction_last_observation": _last_construction_observation.duplicate(true),
        "faction_treasuries": current.get("faction_treasuries", {}).duplicate(true),
        "faction_relations": current.get("faction_relations", {}).duplicate(true),
        "native_relations_last_tick": int(current.get("faction_relations_last_tick", 0)),
        "native_territory_last_tick": int(current.get("territory_last_tick", 0)),
        "native_treaty_changes_last_pass": _last_faction_relations.get("treaty_changes", []).duplicate(true),
        "native_body_controllers": _last_body_territory.get("bodies", {}).duplicate(true),
        "native_system_controllers": _last_body_territory.get("systems", {}).duplicate(true),
        "native_market_controllers": _last_body_territory.get("market_controllers", {}).duplicate(true),
        "n153_blocked_this_tick": _last_n153_result.get("blocked", []).size(),
        "n153_departures_this_tick": _last_ship_result.get("autonomous_departures", []).size(),
        "n84_active_traces": _last_ship_result.get("n84_trace", []).size(),
        "n146_accept_commands": int(_last_n153_result.get("n146_accept_commands", 0)),
        "n146_ship_commands": int(_last_ship_result.get("n146_command_count", 0)),
        "n97_paid_deliveries_this_tick": _last_ship_result.get("n97_paid_moves", []).size(),
        "n21_autonomous_dock_ops": _last_ship_result.get("n21_auto_dock", []).size(),
        "n153_first_blocker": n153_first_blocker,
        "contract_admissions_blocked": _last_contract_admissions.get("blocked", []).size(),
        "population_phase_ok": _last_population_result.get("ok", null),
        "population_purchases": _last_population_result.get("purchases", 0),
        "population_migrated_this_tick": _last_population_result.get("migration_moved", 0),
        "population_migration_credits_this_tick": _last_population_result.get("migration_wealth", 0),
        "population_last_migration": current.get("population_migration_last", {}).duplicate(true)
    }

## Godot JSON may parse integer-shaped fields as float. Normalize only
## explicitly known bounded integral native data before existing schema
## preflight; never convert fractional resource stock/market prices.
func restore_checkpoint(saved: Dictionary, seed: Dictionary) -> bool:
    if not (saved.get("native_production") is Dictionary):
        return false
    var staged: Dictionary = saved.duplicate(true)
    if not _normalize_number_at(staged, "native_production_multiplier"):
        return false
    if not _normalize_native_snapshot(staged["native_production"]):
        return false
    if not super.restore_checkpoint(staged, seed):
        return false
    # Never show stale in-transit receipts from before a successful load.
    _last_ship_result = {}
    _last_station_demand = {}
    _last_contract_admissions = {}
    _last_n153_result = {}
    _last_research_result = {}
    _last_construction_observation = {}
    _last_construction_result = {}
    _last_n91_result = {}
    _last_n134_result = {}
    return true

func _normalize_native_snapshot(saved: Dictionary) -> bool:
    var integer_fields: Array[String] = ["version", "tick"]
    if not _normalize_row(saved, integer_fields):
        return false
    if not (saved.get("world") is Dictionary) or not (saved.get("ledger") is Dictionary):
        return false
    var w: Dictionary = saved["world"]
    if not (w.get("facilities") is Dictionary) or not (w.get("markets") is Dictionary) or not (w.get("populations") is Dictionary):
        return false
    # N104 posted contracts/escrow are persisted inside the SAME N39 World.
    # JSON integer-shaped values must be restored before N39/Board preflight.
    # Older checkpoints without both fields remain valid as legacy.
    # Source-backed faction treasury + N143 director/progress are optional
    # only for truly older P2 saves. Never backfill an old save with
    # invented new money when N9 ledger lacks faction accounts.
    var finance_fields: Array[String] = [
        "faction_treasuries", "research_directors", "research_receipts"]
    var found: int = 0
    for field in finance_fields:
        if w.has(field):
            found += 1
    if found not in [0, 3]:
        return false
    if found == 3:
        for field in finance_fields:
            if not (w[field] is Dictionary):
                return false
        for fid in w["faction_treasuries"]:
            if not _normalize_number_at(w["faction_treasuries"], fid):
                return false
        for fid in w["research_directors"]:
            if not (w["research_directors"][fid] is Dictionary):
                return false
            var head: Dictionary = w["research_directors"][fid]
            if not _normalize_row(head, ["progress", "research_required"]):
                return false
            if head.get("last_research_tick") != null and not _normalize_number_at(head, "last_research_tick"):
                return false
            if head.get("last_shift") is Dictionary:
                var last_shift: Dictionary = head["last_shift"]
                if not _normalize_row(last_shift, ["tick", "wages", "input_payment", "processing_fee"]):
                    return false
                if not (last_shift.get("workers") is Array):
                    return false
                for worker in last_shift["workers"]:
                    if not (worker is Array) or worker.size() != 2 or not _normalize_number_at_worker(worker):
                        return false
            if not (head.get("history") is Array):
                return false
            for record in head["history"]:
                if not (record is Dictionary) or not _normalize_row(record, ["tick"]):
                    return false
        for receipt_id in w["research_receipts"]:
            if not (w["research_receipts"][receipt_id] is Dictionary):
                return false
            if not _normalize_row(w["research_receipts"][receipt_id],
                    ["tick", "cost", "wages"]):
                return false
    if w.has("contract_board") != w.has("escrow_balances"):
        return false
    if w.has("contract_board"):
        if not (w["contract_board"] is Dictionary) or not (w["escrow_balances"] is Dictionary):
            return false
        var board: Dictionary = w["contract_board"]
        var escrows: Dictionary = w["escrow_balances"]
        if not _normalize_row(board, ["version"]):
            return false
        if not (board.get("contracts") is Dictionary) or not (board.get("receipt_claims") is Dictionary):
            return false
        for wallet in escrows:
            if not _normalize_number_at(escrows, wallet):
                return false
        for cid in board["contracts"]:
            if not (board["contracts"][cid] is Dictionary):
                return false
            var row: Dictionary = board["contracts"][cid]
            for key in ["reserved", "agreed_payment", "quantity", "payment",
                    "initial_payment", "posted_at_tick", "expires_at_tick",
                    "accepted_at_tick", "delivered_at_tick"]:
                if not _normalize_number_at(row, key):
                    return false
    # Source N154 sites are persistent and their labor/receipt counters
    # need integral JSON normalization before N39 world validation.
    var construction_fields: Array[String] = [
        "construction_sites", "construction_contracts",
        "construction_receipts", "construction_next_db_id"]
    var construction_count: int = 0
    for key in construction_fields:
        if w.has(key):
            construction_count += 1
    if construction_count not in [0, 4]:
        return false
    if construction_count == 4:
        if not _normalize_row(w, ["construction_next_db_id"]):
            return false
        for key in ["construction_sites", "construction_contracts",
                "construction_receipts"]:
            if not (w[key] is Dictionary):
                return false
        for sid in w["construction_sites"]:
            var site: Dictionary = w["construction_sites"][sid]
            if not (site is Dictionary) or not _normalize_row(site,
                    ["progress_required", "progress_delivered", "spawned_at_tick"]):
                return false
            if not (site.get("labor") is Dictionary):
                return false
            var labor: Dictionary = site["labor"]
            if not _normalize_row(labor, ["required", "completed"]):
                return false
            if labor.get("last_shift") is Dictionary:
                var last_shift: Dictionary = labor["last_shift"]
                for key in ["tick", "wages", "input_payment", "processing_fee"]:
                    if last_shift.has(key) and not _normalize_number_at(last_shift, key):
                        return false
                if not (last_shift.get("workers") is Array):
                    return false
                for worker in last_shift["workers"]:
                    if not (worker is Array) or worker.size() != 2 or not _normalize_number_at_worker(worker):
                        return false
        for receipt_id in w["construction_receipts"]:
            var receipt: Dictionary = w["construction_receipts"][receipt_id]
            if not (receipt is Dictionary) or not _normalize_row(receipt, ["tick"]):
                return false
            for key in ["quantity", "wages", "capital"]:
                if receipt.has(key) and not _normalize_number_at(receipt, key):
                    return false
    # First N46 fleet is authoritative in THIS N39 snapshot. Old files
    # without a fleet remain valid without inventing tanks/ship credits.
    if w.has("ships"):
        if not (w["ships"] is Dictionary) or w["ships"].is_empty():
            return false
        if not _normalize_row(w, ["ship_next_token"]):
            return false
        for id in w["ships"]:
            if not (w["ships"][id] is Dictionary):
                return false
            var ship: Dictionary = w["ships"][id]
            if not _normalize_row(ship, ["credits", "cargo_capacity", "crew_size"]):
                return false
            if ship.has("last_plan_tick") and not _normalize_row(ship, ["last_plan_tick"]):
                return false
            if ship.has("max_source_cost") and not _normalize_row(ship, ["max_source_cost"]):
                return false
            if ship.has("current_bt") and ship["current_bt"] != null:
                var normalized_bt: Dictionary = NativeBt.normalize_from_json(ship["current_bt"])
                if normalized_bt.is_empty():
                    return false
                ship["current_bt"] = normalized_bt
            if not (ship.get("cargo") is Dictionary) or not (ship.get("transit") is Dictionary):
                return false
            for commodity in ship["cargo"]:
                if not _normalize_number_at(ship["cargo"], commodity):
                    return false
            if not ship["transit"].is_empty():
                var transit: Dictionary = ship["transit"]
                for number in ["token", "departure_tick", "last_tick", "arrival_tick"]:
                    if not _normalize_number_at(transit, number):
                        return false
    for receipts_key in ["dock_receipts", "cargo_receipts"]:
        if w.has(receipts_key):
            if not (w[receipts_key] is Dictionary):
                return false
            for op in w[receipts_key]:
                if not (w[receipts_key][op] is Dictionary) or not _normalize_row(w[receipts_key][op], ["tick"]):
                    return false
                if receipts_key == "cargo_receipts":
                    if not (w[receipts_key][op].get("quantities") is Dictionary):
                        return false
                    for item in w[receipts_key][op]["quantities"]:
                        if not _normalize_number_at(w[receipts_key][op]["quantities"], item):
                            return false
    for id in w["facilities"]:
        if not (w["facilities"][id] is Dictionary):
            return false
        var f: Dictionary = w["facilities"][id]
        if not _normalize_row(f, ["credits", "crew_count", "level", "xp"]):
            return false
        if f.has("docking_capacity") and not _normalize_row(f, ["docking_capacity"]):
            return false
        for key in ["lod_next_tick", "lod_divisor", "fitting_batches_bonus", "assigned_workers", "abandon_counter", "native_db_id"]:
            if f.has(key) and not _normalize_row(f, [key]):
                return false
        if f.has("work_shift") and not (f["work_shift"] is Dictionary):
            return false
        if f.has("work_shift") and not f["work_shift"].is_empty():
            var shift: Dictionary = f["work_shift"]
            if not _normalize_row(shift, ["tick", "wages", "input_payment", "processing_fee"]):
                return false
            if not (shift.get("workers") is Dictionary):
                return false
            if shift.has("last_recipe_ticks") and not (shift["last_recipe_ticks"] is Dictionary):
                return false
            for pid in shift["workers"]:
                if not _normalize_number_at(shift["workers"], pid):
                    return false
            for rid in shift.get("last_recipe_ticks", {}):
                if not _normalize_number_at(shift["last_recipe_ticks"], rid):
                    return false
    for location in w["markets"]:
        if not (w["markets"][location] is Dictionary):
            return false
        var market: Dictionary = w["markets"][location]
        if not (market.get("orders") is Dictionary) or not (market.get("history") is Dictionary):
            return false
        if not _normalize_row(market["orders"], ["order_expiry_ticks"]):
            return false
        # JSON decodes integer tick markers as floats. N150 requires TYPE_INT
        # in its rolling MarketFlow, and equality with the pre-save N151
        # purchases must survive a real save/restart without changing qty.
        if not (market.get("consumption_window") is Dictionary):
            return false
        var consumption: Dictionary = market["consumption_window"]
        for commodity in consumption:
            if not (commodity is String) or commodity.is_empty():
                return false
            if not (consumption[commodity] is Array):
                return false
            for sample in consumption[commodity]:
                if not (sample is Dictionary) or not _normalize_row(sample, ["tick"]):
                    return false
                if int(sample["tick"]) < 0 or int(sample["tick"]) > int(saved["tick"]):
                    return false
                var qty: Variant = sample.get("qty", null)
                if not (qty is int or qty is float):
                    return false
                if not is_finite(float(qty)) or float(qty) <= 0.0:
                    return false
                sample["qty"] = float(qty)
        var hist: Dictionary = market["history"]
        if not (hist.get("shortage_ticks", {}) is Dictionary) or not (hist.get("trend_samples", []) is Array):
            return false
        if not _normalize_row(hist, ["last_tick"]):
            return false
        if hist.get("spawned_at_tick") != null and not _normalize_number_at(hist, "spawned_at_tick"):
            return false
        for commodity in hist.get("shortage_ticks", {}):
            if not _normalize_number_at(hist["shortage_ticks"], commodity):
                return false
        for trend in hist.get("trend_samples", []):
            if not (trend is Dictionary) or not _normalize_row(trend, ["tick"]):
                return false
    for id in w["populations"]:
        if not (w["populations"][id] is Dictionary):
            return false
        if not _normalize_row(w["populations"][id], ["count", "wealth",
                "food_satisfaction", "safety_satisfaction", "entertainment_satisfaction",
                "overall_sentiment", "unrest"]):
            return false
    var ledger: Dictionary = saved["ledger"]
    if not _normalize_row(ledger, ["version"]):
        return false
    if not (ledger.get("balances") is Dictionary) or not (ledger.get("receipts") is Dictionary):
        return false
    for acc in ledger["balances"]:
        if not _normalize_number_at(ledger["balances"], acc):
            return false
    for op in ledger["receipts"]:
        if not (ledger["receipts"][op] is Dictionary):
            return false
        var receipt: Dictionary = ledger["receipts"][op]
        if not (receipt.get("legs", []) is Array):
            return false
        if not _normalize_row(receipt, ["tick"]):
            return false
        for leg in receipt.get("legs", []):
            if not (leg is Dictionary) or not _normalize_row(leg, ["delta"]):
                return false
    return true

func _normalize_number_at_worker(worker: Array) -> bool:
    var value: Variant = worker[1]
    if not (value is int or value is float) or not is_finite(float(value)):
        return false
    if float(value) != floor(float(value)) or float(value) < 0.0 or float(value) > 9007199254740991.0:
        return false
    worker[1] = int(value)
    return true

func _normalize_row(row: Dictionary, keys: Array) -> bool:
    for key in keys:
        if not row.has(key) or not _normalize_number_at(row, key):
            return false
    return true

func _normalize_number_at(row: Dictionary, key: Variant) -> bool:
    var v: Variant = row.get(key, null)
    if not (v is int or v is float):
        return false
    var n: float = float(v)
    if not is_finite(n) or absf(n) > 9007199254740991.0 or float(int(n)) != n:
        return false
    row[key] = int(n)
    return true
