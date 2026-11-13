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
const ShipRoster = preload("res://scripts/sim/ships/native_ship_roster.gd")
const NativeLocations = preload("res://scripts/sim/ships/native_location_resolver.gd")

var _boot_error: String = ""
var _source_stats: Dictionary = {}
var _last_market_result: Dictionary = {}
var _last_station_demand: Dictionary = {}
var _last_contract_admissions: Dictionary = {}
var _last_n153_result: Dictionary = {}
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
        for candidate in selection.get("candidates", []):
            var admission: Dictionary = production.accept_autonomous_delivery(tick, candidate, _faction_sources)
            if admission.get("ok", false):
                _last_n153_result["accepted"].append(admission.duplicate(true))
            elif admission.get("fatal", false):
                _last_n153_result = {"ok": false,
                    "reason": str(admission.get("reason", "n153_single_world_commit_rejected"))}
                return false
            else:
                _last_n153_result["blocked"].append({
                    "contract_id": str(candidate.get("contract_id", "")),
                    "ship_id": str(candidate.get("ship_id", "")),
                    "reason": str(admission.get("reason", "n104_acceptance_rejected"))})
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
        # N153 obligations are held on the real N104 board. Follow native
        # N4 directed edges through N14. No phantom cargo or teleporting.
        var scheduled: Dictionary = production.world_snapshot()
        var active_contracts: Dictionary = scheduled.get("contract_board", {}).get("contracts", {})
        var ship_ids: Array = scheduled["ships"].keys()
        ship_ids.sort()
        for sid in ship_ids:
            var ship: Dictionary = scheduled["ships"][sid]
            var cid: String = str(ship.get("active_contract_id", ""))
            if cid.is_empty() or not active_contracts.has(cid):
                continue
            var contract: Dictionary = active_contracts[cid]
            if str(contract.get("status", "")) != "accepted" or str(contract.get("fulfiller_id", "")) != str(sid):
                continue
            if not (ship.get("transit", {}) as Dictionary).is_empty() or str(ship.get("docked_at", "")) != "":
                continue
            var origin: String = str(ship.get("location", ""))
            var target: String = str(contract.get("source_location", ""))
            if origin == target:
                # The accepted N104 obligation is the ONLY reason to dock.
                # N21 checks the real station capacity/occupancy; the same
                # N39 Apply commits the dock receipt into the saved World.
                # No cargo or escrow is touched until N97 paid pickup exists.
                var dock_operation: String = "n104-source-dock:" + cid + ":" + str(sid)
                var dock_plan: Dictionary = FleetLogistics.command(scheduled,
                    "dock", str(sid), dock_operation, tick)
                if not dock_plan.get("ok", false):
                    _last_ship_result["autonomous_blocked"].append({
                        "ship_id": str(sid), "contract_id": cid,
                        "reason": "source_n21_" + str(dock_plan.get("reason", "dock_rejected"))})
                    continue
                if not production.apply_fleet_logistics(tick, dock_plan):
                    _last_ship_result = {"ok": false,
                        "reason": "autonomous_source_dock_single_world_commit_rejected",
                        "ship_id": str(sid), "contract_id": cid}
                    return false
                _last_ship_result["autonomous_departures"].append({
                    "ship_id": str(sid), "contract_id": cid,
                    "action": "n21_source_docked", "location": origin, "tick": tick})
                scheduled = production.world_snapshot()
                continue
            var path: Dictionary = _fleet_roster.registry.graph().shortest_path(origin, target)
            if not path.get("reachable", false) or path.get("locations", []).size() < 2:
                _last_ship_result["autonomous_blocked"].append({
                    "ship_id": str(sid), "contract_id": cid, "reason": "directed_source_route_lost"})
                continue
            var next_hop: String = str(path["locations"][1])
            var depart: Dictionary = ShipPhase.depart(scheduled, _fleet_roster.registry.graph(),
                locations["positions"], tick, clock.tick_scale(), str(sid), next_hop)
            if not depart.get("ok", false):
                _last_ship_result["autonomous_blocked"].append({
                    "ship_id": str(sid), "contract_id": cid,
                    "reason": str(depart.get("reason", "native_departure_blocked"))})
                continue
            if not production.apply_ship_phase(tick, depart):
                _last_ship_result = {"ok": false, "reason": "autonomous_n14_commit_rejected",
                    "ship_id": str(sid), "contract_id": cid}
                return false
            _last_ship_result["autonomous_departures"].append({
                "ship_id": str(sid), "contract_id": cid,
                "from": origin, "to": next_hop, "tick": tick})
            scheduled = production.world_snapshot()
        return true
    if phase == "populations":
        var population_plan: Dictionary = PopulationPhase.propose(
            production.world_snapshot(), tick, clock.tick_scale(), _tick_multiplier)
        if not population_plan.get("ok", false):
            _last_population_result = population_plan
            return false
        if not production.apply_population_phase(tick, population_plan["native_result"]):
            _last_population_result = {"ok": false,
                "reason": "population_single_ledger_commit_rejected"}
            return false
        _last_population_result = {"ok": true, "tick": tick,
            "purchases": int(population_plan["purchase_count"]),
            "events": population_plan["native_result"].get("events", []).duplicate(true)}
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
        result = _last_n153_result
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
    return phases


func boot_error() -> String:
    return _boot_error

func production_stats() -> Dictionary:
    return _source_stats.duplicate(true)

func economy_snapshot() -> Dictionary:
    return production.world_snapshot() if _native_enabled else {}

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
        "n153_blocked_this_tick": _last_n153_result.get("blocked", []).size(),
        "n153_departures_this_tick": _last_ship_result.get("autonomous_departures", []).size(),
        "n153_first_blocker": n153_first_blocker,
        "contract_admissions_blocked": _last_contract_admissions.get("blocked", []).size(),
        "population_phase_ok": _last_population_result.get("ok", null),
        "population_purchases": _last_population_result.get("purchases", 0)
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
        for key in ["lod_next_tick", "lod_divisor", "fitting_batches_bonus", "assigned_workers", "abandon_counter"]:
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
