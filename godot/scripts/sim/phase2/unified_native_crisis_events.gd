extends RefCounted
## Phase2 V2: frozen Rust sim_server::engine::scan_crisis_events.
## Pure, deterministic warning projection. NO stock, credits, prices, morale,
## repairs, jobs, ledger, facility lifecycle or parallel World mutations.
## Actual Rust invokes the scan AFTER markets on every server tick.
## WorldTuning::default values (native/crates/sim_core/src/simulation/tuning.rs).
const MARKET_CRISIS_SHORTAGE_TICKS: int = 200
const MARKET_CRISIS_RECOVERY_TICKS: int = 50
const FACILITY_STARVING_CONDITION: float = 0.3
const FACILITY_STARVING_RECOVERY: float = 0.5

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

## N150 updates shortage_ticks first; this computes the original warning
## hysteresis against that POST-market snapshot. The returned history is
## committed by the EXISTING N39 market apply, not by this helper.
## Old P2 seeds did not expose crisis_notified; {} is the Rust serde default.
static func stage_market_history(market_id: String, location: String,
        history: Dictionary) -> Dictionary:
    if market_id.is_empty() or location.is_empty():
        return _fail("missing_real_market_identity")
    if not (history.get("shortage_ticks") is Dictionary):
        return _fail("missing_real_shortage_history")
    var raw_flags: Variant = history.get("crisis_notified", {})
    if not (raw_flags is Dictionary):
        return _fail("invalid_market_crisis_flags")
    var next_flags: Dictionary = raw_flags.duplicate(true)
    for commodity in next_flags:
        if not (commodity is String) or typeof(next_flags[commodity]) != TYPE_BOOL:
            return _fail("invalid_market_crisis_flag")
    var counters: Dictionary = history["shortage_ticks"]
    var commodities: Array = counters.keys()
    commodities.sort()
    var events: Array[Dictionary] = []
    for commodity in commodities:
        if not (commodity is String) or commodity.is_empty():
            return _fail("invalid_real_commodity")
        var raw_count: Variant = counters[commodity]
        if typeof(raw_count) != TYPE_INT or int(raw_count) < 0 or int(raw_count) > 4294967295:
            return _fail("invalid_real_shortage_counter")
        var count: int = int(raw_count)
        var notified: bool = bool(next_flags.get(commodity, false))
        if count >= MARKET_CRISIS_SHORTAGE_TICKS and not notified:
            events.append({"kind": "market_crisis", "market_id": market_id,
                "location": location, "commodity": commodity,
                "shortage_ticks": count})
            next_flags[commodity] = true
        elif count <= MARKET_CRISIS_RECOVERY_TICKS and notified:
            events.append({"kind": "market_recovered", "market_id": market_id,
                "location": location, "commodity": commodity})
            next_flags[commodity] = false
    var next_history: Dictionary = history.duplicate(true)
    next_history["crisis_notified"] = next_flags
    return {"ok": true, "history": next_history, "events": events}

## Rust also scans FacilityOperations.condition after the market phase.
## This stage is intentionally NOT applied yet: N39/N158 shared authority is
## reserved by chat #1. Call site must atomically persist starving_notified
## on the SAME physical facility, not keep a second independent flag cache.
## This source bridge does not turn on the dormant director.rs N133 accident.
static func propose_facility_warnings(facilities: Dictionary) -> Dictionary:
    var ids: Array = facilities.keys()
    ids.sort()
    var updates: Dictionary = {}
    var events: Array[Dictionary] = []
    for facility_id in ids:
        if not (facility_id is String) or facility_id.is_empty():
            return _fail("invalid_real_facility_id")
        if not (facilities[facility_id] is Dictionary):
            return _fail("invalid_real_facility")
        var facility: Dictionary = facilities[facility_id]
        var raw_condition: Variant = facility.get("condition", null)
        if typeof(raw_condition) not in [TYPE_INT, TYPE_FLOAT]:
            return _fail("missing_real_facility_condition")
        var condition: float = float(raw_condition)
        if not is_finite(condition) or condition < 0.0 or condition > 1.0:
            return _fail("invalid_real_facility_condition")
        var raw_notified: Variant = facility.get("starving_notified", false)
        if typeof(raw_notified) != TYPE_BOOL:
            return _fail("invalid_real_facility_warning_flag")
        var notified: bool = bool(raw_notified)
        if condition < FACILITY_STARVING_CONDITION and not notified:
            updates[facility_id] = true
            events.append({"kind": "facility_starving",
                "facility_id": facility_id, "condition": condition})
        elif condition > FACILITY_STARVING_RECOVERY and notified:
            updates[facility_id] = false
            events.append({"kind": "facility_recovered",
                "facility_id": facility_id, "condition": condition})
    return {"ok": true, "flag_updates": updates, "events": events}
