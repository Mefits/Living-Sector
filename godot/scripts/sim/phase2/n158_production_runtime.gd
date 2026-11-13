extends "res://scripts/sim/phase1/n39_native_production_tick_runner.gd"
## N158 first executable Phase2 slice:
## one real seed -> N39 physical supply/payroll -> P1 clock/events/orbits
## -> versioned P1 save with N39 native snapshot. No second N23 production.
const Projection = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")

var _boot_error: String = ""
var _source_stats: Dictionary = {}

func start_from_seed(seed: Dictionary) -> bool:
    _boot_error = ""
    _source_stats = {}
    var projected: Dictionary = Projection.from_seed(seed)
    if not projected.get("ok", false):
        _boot_error = str(projected.get("reason", "source_projection_failed"))
        return false
    if not super.start_from_seed(seed):
        _boot_error = "base_world_seed_rejected"
        return false
    if not configure_native_production(projected["world"], 1):
        _boot_error = "physical_production_initialization_rejected"
        return false
    _source_stats = projected["stats"].duplicate(true)
    return true

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
        "last_result_ok": results.get("ok", true)
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
    for id in w.get("populations", {}):
        if not _normalize_row(w["populations"][id], ["count", "wealth"]):
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
