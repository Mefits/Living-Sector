extends SceneTree
## Living Sector: clean-seed, headless, NO player/mandates or artificial need.
## Uses only canonical N158/N39 World, native N9 Ledger, original 8/3 seed.
## A read-only observability test, NOT proof of every late-game mechanic.
## godot --headless --path godot --script res://tests/p2_autonomous_world_observer_check.gd
## Optional: LS_AUTONOMY_TICKS=10000, LS_AUTONOMY_REPORT=/absolute/path/report.json
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

const DEFAULT_TICKS: int = 420
const MAX_TICKS: int = 30000
var _report: Dictionary = {}
var _started_ms: int = 0
var _last_supply: Dictionary = {}
var _last_receipt_count: int = 0
var _first_receipt_count: int = 0
var _market_changes: int = 0
var _first_facilities: int = 0
var _first_populations: int = 0
var _first_research: int = 0
var _latest_ships_in_transit: int = 0
var _observed_transit: bool = false
var _observed_contract: bool = false
var _observed_picked_up: bool = false
var _observed_paid: bool = false
var _n153_block_reasons: Dictionary = {}
var _n153_ship_causes: Dictionary = {}
var _n84_block_reasons: Dictionary = {}
var _n153_accept_total: int = 0
var _n84_departures_total: int = 0
var _n140_fired_total: int = 0
var _tick_usec_total: int = 0
var _tick_timing_buckets: Array[Dictionary] = []
var _ticks_in_bucket: int = 0
var _bucket_usec: int = 0

func _initialize() -> void:
    _started_ms = Time.get_ticks_msec()
    var requested: String = OS.get_environment("LS_AUTONOMY_TICKS")
    var ticks: int = DEFAULT_TICKS
    if not requested.is_empty():
        if not requested.is_valid_int():
            _finish(false, "LS_AUTONOMY_TICKS must be an integer")
            return
        ticks = int(requested)
    if ticks < 1 or ticks > MAX_TICKS:
        _finish(false, "Requested ticks outside 1..30000")
        return
    _report = {
        "schema_version": 1,
        "mode": "clean_original_galaxy_observer_no_player",
        "target_ticks": ticks,
        "observed_ticks": 0,
        "samples": [],
        "injected_orders": 0,
        "injected_goods": 0,
        "manual_ship_commands": 0,
        "runtime": "N158_one_world",
        "result": "PENDING"
    }
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _finish(false, "Frozen Rust galaxy seed unavailable: " +
            str(seed.get("error", "")))
        return
    var sim = Runtime.new()
    if not sim.start_from_seed(seed):
        _finish(false, "Canonical N158 cannot boot: " + sim.boot_error())
        return
    var initial: Dictionary = sim.checkpoint()
    if not (initial.get("native_production") is Dictionary):
        _finish(false, "Seed lacks canonical N39 physical World")
        return
    var start_world: Dictionary = initial["native_production"]["world"]
    var start_bank: Dictionary = initial["native_production"]["ledger"]
    _report["initial_ship_count"] = start_world.get("ships", {}).size()
    _report["initial_market_count"] = start_world.get("markets", {}).size()
    _report["initial_faction_count"] = start_world.get(
        "faction_treasuries", {}).size()
    _first_facilities = start_world.get("facilities", {}).size()
    _first_populations = start_world.get("populations", {}).size()
    _first_research = start_world.get("research_receipts", {}).size()
    _last_receipt_count = start_bank.get("receipts", {}).size()
    _first_receipt_count = _last_receipt_count
    _last_supply = _stock_snapshot(start_world)
    if _report["initial_ship_count"] != 24 or _report[
            "initial_market_count"] != 3:
        _finish(false, "Original clean seed has unexpected 24 ships/3 markets")
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _finish(false, "Original N1 cannot prepare deterministic x8 steps")
        return
    sim.advance_frame(0.0)
    if not sim.clock.paused or sim.clock.tick_multiplier() != 1:
        _finish(false, "Clock was not paused or x8 multiplier not one")
        return
    var interval: int = maxi(25, mini(250,
        int(ceil(float(ticks) / 24.0))))
    for n in range(1, ticks + 1):
        var step_started_us: int = Time.get_ticks_usec()
        if not sim.queue_control("step", 1):
            _finish(false, "N1 refused to advance at tick " + str(n))
            return
        sim.advance_frame(0.0)
        var fault: Dictionary = sim.last_phase_failure()
        if not fault.is_empty() or sim.tick_count != n:
            _report["phase_failure"] = fault
            _finish(false, "Native phase stopped at " + str(n) +
                "; actual=" + str(sim.tick_count) +
                "; source=" + str(fault))
            return
        _report["observed_ticks"] = n
        # These are original N153/N84 phase results, not synthetic
        # predictions. Record even one-tick departures that a sparse
        # 25-tick ship snapshot could otherwise miss.
        var ai: Dictionary = sim.native_autonomy_diagnostics()
        _n153_accept_total += int(ai.get("n153_accepted", 0))
        _n84_departures_total += ai.get("n84_departures", []).size()
        _n140_fired_total += int(ai.get("n140_fired", 0))
        for blocked in ai.get("n153_blocked", []):
            if blocked is Dictionary:
                var reason: String = str(blocked.get("reason", "unknown"))
                _n153_block_reasons[reason] = int(
                    _n153_block_reasons.get(reason, 0)) + 1
                for ship_reason in blocked.get("ship_rejection_counts", {}):
                    var copies: int = int(
                        blocked["ship_rejection_counts"][ship_reason])
                    _n153_ship_causes[str(ship_reason)] = int(
                        _n153_ship_causes.get(str(ship_reason), 0)) + copies
        for blocked in ai.get("n84_blocked", []):
            if blocked is Dictionary:
                var reason: String = str(blocked.get("reason", "unknown"))
                _n84_block_reasons[reason] = int(
                    _n84_block_reasons.get(reason, 0)) + 1
        if not ai.get("n84_departures", []).is_empty():
            _observed_transit = true
        var elapsed_step_us: int = maxi(0,
            Time.get_ticks_usec() - step_started_us)
        _tick_usec_total += elapsed_step_us
        _bucket_usec += elapsed_step_us
        _ticks_in_bucket += 1
        if n % 60 == 0 or n == ticks:
            _tick_timing_buckets.append({
                "until_tick": n, "ticks": _ticks_in_bucket,
                "total_usec": _bucket_usec,
                "average_ms": float(_bucket_usec) / (
                    1000.0 * float(maxi(1, _ticks_in_bucket)))})
            _bucket_usec = 0
            _ticks_in_bucket = 0
        if n != 1 and n != ticks and n % interval != 0:
            continue
        var frame: Dictionary = sim.checkpoint()
        if not (frame.get("native_production") is Dictionary):
            _finish(false, "N38 frame missing at tick " + str(n))
            return
        var world: Dictionary = frame["native_production"]["world"]
        var bank: Dictionary = frame["native_production"]["ledger"]
        var invalid: String = Schema.validate(world)
        if not invalid.is_empty():
            _finish(false, "Canonical World invalid at " + str(n) +
                ": " + invalid)
            return
        # Source N9 owns all wallets. A one-sided wage write-off can
        # legitimately reduce TOTAL money; never assert a fixed total.
        var expected: Dictionary = Schema.accounts(world)
        if bank.get("balances", {}) != expected:
            _finish(false, "N39 balances diverged from N9 at " + str(n))
            return
        var count: int = bank.get("receipts", {}).size()
        if count < _last_receipt_count:
            _finish(false, "Native payment history shrank at " + str(n))
            return
        _last_receipt_count = count
        var supplies: Dictionary = _stock_snapshot(world)
        if supplies != _last_supply:
            _market_changes += 1
        _last_supply = supplies
        var transit_count: int = 0
        for ship in world.get("ships", {}).values():
            if ship is Dictionary and not ship.get("transit", {}).is_empty():
                transit_count += 1
        _latest_ships_in_transit = transit_count
        if transit_count > 0:
            _observed_transit = true
        var status_totals: Dictionary = {}
        for contract in world.get("contract_board", {}).get(
                "contracts", {}).values():
            if not (contract is Dictionary):
                continue
            var status: String = str(contract.get("status", ""))
            status_totals[status] = int(status_totals.get(status, 0)) + 1
            _observed_contract = true
            if status in ["picked_up", "paid", "completed"]:
                _observed_picked_up = true
            if status in ["paid", "completed"]:
                _observed_paid = true
        var sample: Dictionary = {
            "tick": n,
            "world_ships": world.get("ships", {}).size(),
            "in_transit_now": transit_count,
            "facilities": world.get("facilities", {}).size(),
            "population_groups": world.get("populations", {}).size(),
            "physical_cargo_receipts": world.get("cargo_receipts", {}).size(),
            "physical_dock_receipts": world.get("dock_receipts", {}).size(),
            "construction_receipts": world.get(
                "construction_receipts", {}).size(),
            "research_receipts": world.get("research_receipts", {}).size(),
            "n9_receipts": count,
            "n104_contract_statuses": status_totals,
            "money_remaining": _account_total(expected),
            "market_supply": supplies,
            "static_memory_bytes": int(Performance.get_monitor(
                Performance.MEMORY_STATIC)),
            "elapsed_ms": Time.get_ticks_msec() - _started_ms
        }
        _report["samples"].append(sample)
    _report["native_n153_accepted_total"] = _n153_accept_total
    _report["native_n153_block_reasons"] = _n153_block_reasons
    _report["native_n153_ship_causes"] = _n153_ship_causes
    _report["native_n84_block_reasons"] = _n84_block_reasons
    _report["native_n84_departures_total"] = _n84_departures_total
    _report["native_n140_fired_total"] = _n140_fired_total
    _report["actual_tick_usec"] = _tick_usec_total
    _report["tick_speed_buckets"] = _tick_timing_buckets
    _report["native_phase_profile"] = sim.profile_native_phases()
    _report["n39_world_copy_profile"] = sim.production.world_copy_profile()
    _report["physical_market_change_samples"] = _market_changes
    _report["n9_new_receipts"] = _last_receipt_count - _first_receipt_count
    _report["observed_n104_board"] = _observed_contract
    _report["observed_n104_cargo_pickup"] = _observed_picked_up
    _report["observed_n104_payout"] = _observed_paid
    _report["observed_any_flight"] = _observed_transit
    _report["ships_in_transit_at_end"] = _latest_ships_in_transit
    var final_sample: Dictionary = _report["samples"][-1]
    _report["new_facilities"] = int(final_sample["facilities"]) - (
        _first_facilities)
    _report["new_population_groups"] = int(
        final_sample["population_groups"]) - _first_populations
    _report["new_research_receipts"] = int(
        final_sample["research_receipts"]) - _first_research
    _report["elapsed_ms"] = Time.get_ticks_msec() - _started_ms
    _report["actual_tps"] = float(ticks) * 1000.0 / float(maxi(
        1, int(_report["elapsed_ms"])))
    # Pure clean seed can legitimately have NO N135 shortage: no
    # invented demand, no fabricated deliveries and no false pass for
    # trading/colony milestones. These remain visible zero counts.
    if _market_changes == 0 or _last_receipt_count <= _first_receipt_count:
        _finish(false, "Clean World advanced but had no physical market " +
            "change or N9 payment activity")
        return
    _finish(true, "Clean N158 World ran without player commands; " +
        "autonomous freight/colonization are observations, not asserted PASS")

func _stock_snapshot(world: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for market_id in world.get("markets", {}):
        var market: Dictionary = world["markets"][market_id]
        out[str(market_id)] = market.get("supply", {}).duplicate(true)
    return out

func _account_total(accounts: Dictionary) -> int:
    var sum: int = 0
    for amount in accounts.values():
        sum += int(amount)
    return sum

func _finish(success: bool, reason: String) -> void:
    _report["result"] = "PASS" if success else "FAIL"
    _report["reason"] = reason
    _report["elapsed_ms"] = Time.get_ticks_msec() - _started_ms
    var target: String = OS.get_environment("LS_AUTONOMY_REPORT")
    if target.is_empty():
        target = "user://tests/autonomous-world-report.json"
    var directory: String = ProjectSettings.globalize_path(
        target.get_base_dir())
    DirAccess.make_dir_recursive_absolute(directory)
    var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
    if file == null:
        push_error("Could not write autonomy report: " + target)
        quit(1)
        return
    file.store_string(JSON.stringify(_report, "\t", false, true) + "\n")
    file.close()
    print("LS_AUTONOMY_WORLD_" + str(_report["result"]) +
        ": " + reason + " report=" + target +
        " tick=" + str(_report.get("observed_ticks", 0)))
    if not success:
        push_error("LS_AUTONOMY_WORLD_FAILURE: " + reason)
    quit(0 if success else 1)
