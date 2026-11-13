extends "res://scripts/sim/phase1/n39_native_production_tick_runner.gd"
## N158 first executable Phase2 slice:
## one real seed -> N39 physical supply/payroll -> P1 clock/events/orbits
## -> versioned P1 save with N39 native snapshot. No second N23 production.
const GalaxySeedAdapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const MarketPhase = preload("res://scripts/sim/phase2/unified_market_phase.gd")
const PopulationPhase = preload("res://scripts/sim/phase2/unified_population_phase.gd")

var _boot_error: String = ""
var _source_stats: Dictionary = {}
var _last_market_result: Dictionary = {}
var _last_population_result: Dictionary = {}

func start_from_seed(seed: Dictionary) -> bool:
    _boot_error = ""
    _source_stats = {}
    _last_market_result = {}
    _last_population_result = {}
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
    return true

func last_market_result() -> Dictionary:
    return _last_market_result.duplicate(true)

func last_population_result() -> Dictionary:
    return _last_population_result.duplicate(true)

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
    return {
        "tick": tick_count,
        "markets": current["markets"].size(),
        "facilities": current["facilities"].size(),
        "population_groups": current["populations"].size(),
        "last_wages_paid": paid,
        "last_recipe_facilities": recipes,
        "last_mining_facilities": mined,
        "last_failures": results.get("failures", {}).duplicate(true),
        "last_result_ok": results.get("ok", true),
        "market_phase_ok": _last_market_result.get("ok", null),
        "market_phase_tick": _last_market_result.get("tick", -1),
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
    return super.restore_checkpoint(staged, seed)

func _normalize_native_snapshot(saved: Dictionary) -> bool:
    var integer_fields: Array[String] = ["version", "tick"]
    if not _normalize_row(saved, integer_fields):
        return false
    if not (saved.get("world") is Dictionary) or not (saved.get("ledger") is Dictionary):
        return false
    var w: Dictionary = saved["world"]
    for id in w.get("facilities", {}):
        var f: Dictionary = w["facilities"][id]
        if not _normalize_row(f, ["credits", "crew_count", "level", "xp"]):
            return false
        for key in ["lod_next_tick", "lod_divisor", "fitting_batches_bonus", "assigned_workers"]:
            if f.has(key) and not _normalize_row(f, [key]):
                return false
        if f.has("work_shift") and not f["work_shift"].is_empty():
            var shift: Dictionary = f["work_shift"]
            if not _normalize_row(shift, ["tick", "wages", "input_payment", "processing_fee"]):
                return false
            if not (shift.get("workers") is Dictionary):
                return false
            for pid in shift["workers"]:
                if not _normalize_number_at(shift["workers"], pid):
                    return false
            for rid in shift.get("last_recipe_ticks", {}):
                if not _normalize_number_at(shift["last_recipe_ticks"], rid):
                    return false
    for location in w.get("markets", {}):
        var market: Dictionary = w["markets"][location]
        if not (market.get("orders") is Dictionary) or not (market.get("history") is Dictionary):
            return false
        if not _normalize_row(market["orders"], ["order_expiry_ticks"]):
            return false
        var hist: Dictionary = market["history"]
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
    for id in w.get("populations", {}):
        if not _normalize_row(w["populations"][id], ["count", "wealth",
                "food_satisfaction", "safety_satisfaction", "entertainment_satisfaction",
                "overall_sentiment", "unrest"]):
            return false
    var ledger: Dictionary = saved["ledger"]
    if not _normalize_row(ledger, ["version"]):
        return false
    for acc in ledger.get("balances", {}):
        if not _normalize_number_at(ledger["balances"], acc):
            return false
    for op in ledger.get("receipts", {}):
        var receipt: Dictionary = ledger["receipts"][op]
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
