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

## Read-only Observer projection from the SAME N39 World. These are source
## warning FLAGS, not newly-emitted events. Missing facility flags are
## reported separately as pending until the canonical N39 writer is wired.
## Both dictionaries are snapshots; this function must never repair them.
static func current_warning_state(world: Dictionary) -> Dictionary:
    if not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return _fail("missing_canonical_market_or_facilities")
    var active_markets: Array[Dictionary] = []
    var active_facilities: Array[Dictionary] = []
    var pending_facilities: Array[Dictionary] = []
    var locations: Array = world["markets"].keys()
    locations.sort()
    for location in locations:
        var raw_market: Variant = world["markets"][location]
        if not (location is String) or not (raw_market is Dictionary):
            return _fail("invalid_real_market")
        var market: Dictionary = raw_market
        if not (market.get("history") is Dictionary):
            return _fail("missing_real_market_history")
        var history: Dictionary = market["history"]
        if not (history.get("shortage_ticks") is Dictionary):
            return _fail("missing_real_shortage_history")
        var flags: Variant = history.get("crisis_notified", {})
        if not (flags is Dictionary):
            return _fail("invalid_real_market_warning_flags")
        var slugs: Array = flags.keys()
        slugs.sort()
        for commodity in slugs:
            if not (commodity is String) or typeof(flags[commodity]) != TYPE_BOOL:
                return _fail("invalid_real_market_warning_flag")
            if bool(flags[commodity]):
                var raw_count: Variant = history["shortage_ticks"].get(commodity, 0)
                if typeof(raw_count) != TYPE_INT or int(raw_count) < 0:
                    return _fail("invalid_real_market_shortage_counter")
                active_markets.append({
                    "market_id": str(market.get("id", "")),
                    "location": location, "commodity": commodity,
                    "shortage_ticks": int(raw_count)})
    var ids: Array = world["facilities"].keys()
    ids.sort()
    for facility_id in ids:
        var raw_facility: Variant = world["facilities"][facility_id]
        if not (facility_id is String) or not (raw_facility is Dictionary):
            return _fail("invalid_real_facility")
        var facility: Dictionary = raw_facility
        # N156 optional component is absent in older P2 seeds; do not
        # invent a condition value or report an active warning for it.
        if not facility.has("condition"):
            continue
        var raw_condition: Variant = facility["condition"]
        if typeof(raw_condition) not in [TYPE_INT, TYPE_FLOAT]:
            return _fail("invalid_real_facility_condition")
        var condition: float = float(raw_condition)
        if not is_finite(condition) or condition < 0.0 or condition > 1.0:
            return _fail("invalid_real_facility_condition")
        var flag: Variant = facility.get("starving_notified", false)
        if typeof(flag) != TYPE_BOOL:
            return _fail("invalid_real_facility_warning_flag")
        var row: Dictionary = {"facility_id": facility_id, "condition": condition}
        if bool(flag):
            # Rust hysteresis: flagged facilities can remain under warning
            # between the 0.3 entry and 0.5 recovery boundary.
            active_facilities.append(row)
        elif condition < FACILITY_STARVING_CONDITION:
            # This is not a emitted event: the N39 writer is still missing.
            pending_facilities.append(row)
    return {"ok": true,
        "active_markets": active_markets,
        "active_facilities": active_facilities,
        "pending_facilities": pending_facilities,
        "market_count": active_markets.size(),
        "facility_count": active_facilities.size(),
        "pending_facility_count": pending_facilities.size()}
