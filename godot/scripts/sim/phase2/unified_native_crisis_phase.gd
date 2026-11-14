extends RefCounted
## Frozen Rust sim_server::engine::scan_crisis_events, composed after the
## real N150 Market tick and BEFORE apply2. This is ONLY an immutable plan:
## N39 owns World/flags and N158 emits events AFTER N39 commit succeeds.
## No market repricing, payroll, N9, ContractBoard, clock or event cache.
const Warnings = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _flags(history: Dictionary) -> Dictionary:
    var raw: Variant = history.get("crisis_notified", {})
    return raw if raw is Dictionary else {}

## Validate the exact market transitions already staged by MarketPhase.
## Until N39 can own the whole 'crisis' phase, N150's market proposal
## persists flags in its existing history apply. We must NOT fabricate a
## second event by simply reading the flagged post-market snapshot.
static func _market_transitions(before: Dictionary, after: Dictionary,
        expected_events: Variant) -> Dictionary:
    if not (before.get("markets") is Dictionary) or not (
            after.get("markets") is Dictionary):
        return _fail("missing_single_market_world")
    if not (expected_events is Array):
        return _fail("missing_n150_crisis_transition_receipts")
    var old_markets: Dictionary = before["markets"]
    var markets: Dictionary = after["markets"]
    if old_markets.size() != markets.size():
        return _fail("market_registry_changed_inside_n150")
    var locations: Array = markets.keys()
    locations.sort()
    var entries: Dictionary = {}
    for location in locations:
        if not (location is String) or not old_markets.has(location) or not (
                markets[location] is Dictionary) or not (
                old_markets[location] is Dictionary):
            return _fail("market_identity_mismatch_inside_n150")
        var now: Dictionary = markets[location]
        var was: Dictionary = old_markets[location]
        var market_id: String = str(now.get("id", ""))
        if market_id.is_empty() or market_id != str(was.get("id", "")):
            return _fail("market_id_changed_inside_n150")
        if not (now.get("history") is Dictionary) or not (
                was.get("history") is Dictionary):
            return _fail("missing_real_market_history")
        var history: Dictionary = now["history"]
        var previous: Dictionary = was["history"]
        if not (history.get("shortage_ticks") is Dictionary) or not (
                previous.get("shortage_ticks") is Dictionary):
            return _fail("missing_original_shortage_counters")
        var raw_old: Variant = previous.get("crisis_notified", {})
        var raw_new: Variant = history.get("crisis_notified", {})
        if not (raw_old is Dictionary) or not (raw_new is Dictionary):
            return _fail("invalid_native_market_crisis_flags")
        var older: Dictionary = raw_old
        var newer: Dictionary = raw_new
        for slug in older:
            if not (slug is String) or typeof(older[slug]) != TYPE_BOOL:
                return _fail("invalid_original_market_flag")
        for slug in newer:
            if not (slug is String) or typeof(newer[slug]) != TYPE_BOOL:
                return _fail("invalid_committed_market_flag")
        var counters: Dictionary = history["shortage_ticks"]
        for slug in older:
            if not counters.has(slug) and bool(older[slug]) != bool(
                    newer.get(slug, false)):
                return _fail("market_flag_changed_without_source_counter")
        for slug in newer:
            if not counters.has(slug) and bool(newer[slug]) != bool(
                    older.get(slug, false)):
                return _fail("market_flag_changed_without_source_counter")
        var commodities: Array = counters.keys()
        commodities.sort()
        for commodity in commodities:
            if not (commodity is String) or commodity.is_empty():
                return _fail("invalid_source_commodity")
            var raw_count: Variant = counters[commodity]
            if typeof(raw_count) != TYPE_INT or int(raw_count) < 0 or int(
                    raw_count) > 4294967295:
                return _fail("invalid_source_shortage_tick")
            var count: int = int(raw_count)
            var previously: bool = bool(older.get(commodity, false))
            var afterwards: bool = bool(newer.get(commodity, false))
            var event: Dictionary = {}
            if count >= Warnings.MARKET_CRISIS_SHORTAGE_TICKS and not previously:
                if not afterwards:
                    return _fail("n150_did_not_persist_market_crisis_flag")
                event = {"kind": "market_crisis", "market_id": market_id,
                    "location": location, "commodity": commodity,
                    "shortage_ticks": count}
            elif count <= Warnings.MARKET_CRISIS_RECOVERY_TICKS and previously:
                if afterwards:
                    return _fail("n150_did_not_persist_market_recovery_flag")
                event = {"kind": "market_recovered", "market_id": market_id,
                    "location": location, "commodity": commodity}
            elif previously != afterwards:
                return _fail("market_flag_flipped_between_hysteresis_thresholds")
            if not event.is_empty():
                # A stable source key permits exactly one event on each
                # crossing, without inventing a parallel receipt registry.
                var key: String = JSON.stringify([market_id, location, commodity])
                if entries.has(key):
                    return _fail("duplicated_native_market_identity")
                entries[key] = event
    var consumed: Dictionary = {}
    var sorted_events: Array[Dictionary] = []
    for supplied in expected_events:
        if not (supplied is Dictionary):
            return _fail("invalid_n150_crisis_event")
        var key: String = JSON.stringify([
            supplied.get("market_id"), supplied.get("location"),
            supplied.get("commodity")])
        if consumed.has(key) or not entries.has(key) or supplied != entries[key]:
            return _fail("unbacked_or_replayed_n150_crisis_event")
        consumed[key] = true
    if consumed.size() != entries.size():
        return _fail("unreported_original_n150_market_transition")
    var ids: Array = entries.keys()
    ids.sort()
    for key in ids:
        sorted_events.append(entries[key].duplicate(true))
    return {"ok": true, "events": sorted_events}

## The original Rust Bundle(S) scans markets, THEN facilities, on
## every tick. The returned events are NOT emitted until N39 has
## atomically persisted every facility starving_notified change.
static func propose(before_market_world: Dictionary,
        committed_market_world: Dictionary, market_proposal: Dictionary,
        tick: int) -> Dictionary:
    if tick < 1 or not market_proposal.get("ok", false) or (
            typeof(market_proposal.get("tick", null)) != TYPE_INT) or (
            int(market_proposal["tick"]) != tick):
        return _fail("missing_real_committed_n150_tick")
    if not (committed_market_world.get("facilities") is Dictionary) or not (
            before_market_world.get("facilities") is Dictionary):
        return _fail("missing_single_facility_registry")
    if committed_market_world["facilities"] != before_market_world["facilities"]:
        return _fail("n150_market_phase_mutated_facilities")
    var markets: Dictionary = _market_transitions(
        before_market_world, committed_market_world,
        market_proposal.get("crisis_events", null))
    if not markets.get("ok", false):
        return markets
    var facilities: Dictionary = Warnings.propose_facility_warnings(
        committed_market_world["facilities"])
    if not facilities.get("ok", false):
        return _fail("native_facility_scan_rejected:" +
            str(facilities.get("reason", "invalid")))
    var facility_events: Array[Dictionary] = facilities["events"]
    var original_market_events: Array[Dictionary] = markets["events"]
    var ordered: Array[Dictionary] = original_market_events.duplicate(true)
    ordered.append_array(facility_events)
    return {"ok": true, "tick": tick,
        "facility_flag_updates": facilities["flag_updates"].duplicate(true),
        "market_events": original_market_events.duplicate(true),
        "facility_events": facility_events.duplicate(true),
        "events_after_n39_commit": ordered,
        "market_count": original_market_events.size(),
        "facility_count": facility_events.size(),
        "authority": "original_market_hysteresis_plus_single_N39_facility_apply"}

## Detached commit preflight for N39: only a changed
## FacilityOperations.starving_notified is allowed, never an invented
## condition change, a new facility, credit, inventory or market.
static func expected_facility_flag_world(canonical: Dictionary,
        proposal: Dictionary) -> Dictionary:
    if not proposal.get("ok", false) or not (
            proposal.get("facility_flag_updates") is Dictionary) or not (
            canonical.get("facilities") is Dictionary):
        return _fail("invalid_canonical_crisis_commit_input")
    var stage: Dictionary = canonical.duplicate(true)
    for facility_id in proposal["facility_flag_updates"]:
        if not (facility_id is String) or not stage["facilities"].has(
                facility_id) or typeof(proposal["facility_flag_updates"][facility_id]) != TYPE_BOOL:
            return _fail("unknown_original_facility_warning")
        var item: Dictionary = stage["facilities"][facility_id]
        var raw: Variant = item.get("starving_notified", false)
        if typeof(raw) != TYPE_BOOL or bool(raw) == bool(
                proposal["facility_flag_updates"][facility_id]):
            return _fail("stale_or_replayed_original_facility_warning")
        item["starving_notified"] = bool(
            proposal["facility_flag_updates"][facility_id])
    return {"ok": true, "world": stage, "updates": proposal[
        "facility_flag_updates"].size()}
