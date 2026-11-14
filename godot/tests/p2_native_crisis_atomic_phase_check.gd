extends SceneTree
## Frozen Rust engine.rs::scan_crisis_events unit composition.
## Deferred until full unified runtime acceptance; no Actions in source pass.
const Crisis = preload("res://scripts/sim/phase2/unified_native_crisis_phase.gd")

func _fail(reason: String) -> void:
    push_error("P2_RUST_BUNDLE_S_ATOMIC: " + reason)
    quit(1)

func _world(shortage: int, flagged: bool, facility_condition: float,
        facility_flag: bool) -> Dictionary:
    return {
        "markets": {"earth-station": {
            "id": "market-earth", "owner": "facility-station",
            "supply": {"food": 12.0},
            "history": {"shortage_ticks": {"food": shortage},
                "crisis_notified": {"food": flagged}}}},
        "facilities": {
            "facility-refinery": {"condition": facility_condition,
                "starving_notified": facility_flag, "credits": 900,
                "reserves": {"tools": 6}},
            "facility-station": {"condition": 0.99,
                "starving_notified": false, "credits": 1000}},
        "ledger": {"version": 1, "balances": {
            "facility/facility-refinery": 900, "facility/facility-station": 1000}},
        "ships": {"ship-a": {"credits": 50, "cargo": {"metals": 4}}}
    }

func _market(before: Dictionary, after: Dictionary,
        events: Array, tick: int) -> Dictionary:
    return {"ok": true, "tick": tick,
        "crisis_events": events.duplicate(true)}

func _crossing(before: Dictionary, after: Dictionary,
        events: Array, tick: int) -> Dictionary:
    return Crisis.propose(before, after, _market(before, after, events, tick), tick)

func _expect_no_mutation(before: Dictionary, after: Dictionary,
        original_before: Dictionary, original_after: Dictionary) -> bool:
    if before != original_before or after != original_after:
        _fail("pure Rust crisis plan mutated original N39 snapshots")
        return false
    return true

func _initialize() -> void:
    var before: Dictionary = _world(199, false, 0.3, false)
    var after: Dictionary = _world(200, true, 0.3, false)
    var prior: Dictionary = before.duplicate(true)
    var committed: Dictionary = after.duplicate(true)
    var market_event: Dictionary = {
        "kind": "market_crisis", "market_id": "market-earth",
        "location": "earth-station", "commodity": "food",
        "shortage_ticks": 200}
    var result: Dictionary = _crossing(before, after, [market_event], 200)
    if not result.get("ok", false) or result.get("market_count", -1) != 1 or (
            result.get("facility_count", -1) != 0) or result.get(
            "events_after_n39_commit", []) != [market_event]:
        _fail("200 shortage threshold or exact source event receipt failed: " +
            str(result))
        return
    if not _expect_no_mutation(before, after, prior, committed):
        return
    if _crossing(before, after, [market_event, market_event], 200).get(
            "ok", false):
        _fail("duplicate market crisis receipt admitted")
        return
    if _crossing(before, after, [], 200).get("ok", false):
        _fail("market flag flipped but transition receipt silently lost")
        return
    var forged: Dictionary = market_event.duplicate(true)
    forged["shortage_ticks"] = 201
    if _crossing(before, after, [forged], 200).get("ok", false):
        _fail("market warning event not backed by exact N150 count")
        return
    var no_flag: Dictionary = _world(200, false, 0.3, false)
    if _crossing(before, no_flag, [], 200).get("ok", false):
        _fail("N150 failed to persist market crisis flag but event was accepted")
        return

    # Exactly-once source hysteresis: 201 while notified -> no event.
    var steady: Dictionary = _world(201, true, 0.3, false)
    result = _crossing(after, steady, [], 201)
    if not result.get("ok", false) or not result[
            "events_after_n39_commit"].is_empty():
        _fail("market crisis emitted twice on adjacent ticks")
        return
    # Recovery at <=50; between threshold values no new event.
    var midpoint: Dictionary = _world(51, true, 0.3, false)
    result = _crossing(steady, midpoint, [], 250)
    if not result.get("ok", false) or result[
            "market_count"] != 0:
        _fail("market hysteresis cleared before frozen Rust boundary")
        return
    var recovery: Dictionary = _world(50, false, 0.3, false)
    var recovered: Dictionary = {"kind": "market_recovered",
        "market_id": "market-earth", "location": "earth-station",
        "commodity": "food"}
    result = _crossing(midpoint, recovery, [recovered], 251)
    if not result.get("ok", false) or result[
            "events_after_n39_commit"] != [recovered]:
        _fail("market recovery at <=50 not recorded exactly once")
        return
    var post_recovery: Dictionary = _world(49, false, 0.3, false)
    result = _crossing(recovery, post_recovery, [], 252)
    if not result.get("ok", false) or not result[
            "events_after_n39_commit"].is_empty():
        _fail("market recovery re-emitted without state crossing")
        return

    # Rust facility strictly <0.3 enters starvation; >0.5 exits.
    var base: Dictionary = _world(0, false, 0.299, false)
    var same: Dictionary = base.duplicate(true)
    var next_tick: int = 300
    result = _crossing(base, same, [], next_tick)
    var starving: Dictionary = {"kind": "facility_starving",
        "facility_id": "facility-refinery", "condition": 0.299}
    if not result.get("ok", false) or result.get("facility_count", -1) != 1 or (
            result.get("events_after_n39_commit", []) != [starving]) or (
            result.get("facility_flag_updates", {}) != {
                "facility-refinery": true}):
        _fail("original Rust starving threshold failed: " + str(result))
        return
    var commit: Dictionary = Crisis.expected_facility_flag_world(same, result)
    if not commit.get("ok", false) or bool(commit["world"]["facilities"][
            "facility-refinery"].get("starving_notified", false)) != true:
        _fail("pure N39 facility flag proposal malformed")
        return
    if same["facilities"]["facility-refinery"]["starving_notified"] != false or (
            commit["world"]["ledger"] != same["ledger"]) or (
            commit["world"]["ships"] != same["ships"]) or (
            commit["world"]["markets"] != same["markets"]) or (
            commit["world"]["facilities"]["facility-refinery"]["credits"] != 900):
        _fail("crisis staging changed cargo, market, wallet or source world")
        return
    if Crisis.expected_facility_flag_world(commit["world"], result).get(
            "ok", false):
        _fail("replayed N39 facility warning commit accepted")
        return
    result = _crossing(commit["world"], commit["world"], [], next_tick + 1)
    if not result.get("ok", false) or result.get("facility_count", -1) != 0:
        _fail("persisted facility warning re-emitted on next tick")
        return
    var at_half: Dictionary = commit["world"].duplicate(true)
    at_half["facilities"]["facility-refinery"]["condition"] = 0.5
    result = _crossing(at_half, at_half, [], next_tick + 2)
    if not result.get("ok", false) or result.get("facility_count", -1) != 0:
        _fail("exactly 0.5 caused early facility recovery")
        return
    var healed: Dictionary = at_half.duplicate(true)
    healed["facilities"]["facility-refinery"]["condition"] = 0.501
    result = _crossing(healed, healed, [], next_tick + 3)
    var recovery_fac: Dictionary = {"kind": "facility_recovered",
        "facility_id": "facility-refinery", "condition": 0.501}
    if not result.get("ok", false) or result.get("facility_count", -1) != 1 or (
            result["events_after_n39_commit"] != [recovery_fac]):
        _fail("frozen facility recovery boundary not preserved: " + str(result))
        return
    commit = Crisis.expected_facility_flag_world(healed, result)
    if not commit.get("ok", false) or bool(commit["world"]["facilities"][
            "facility-refinery"]["starving_notified"]):
        _fail("source facility recovery flag not persisted in same World")
        return
    result = _crossing(commit["world"], commit["world"], [], next_tick + 4)
    if not result.get("ok", false) or result["events_after_n39_commit"].size() != 0:
        _fail("facility recovery crossed twice")
        return

    # A crisis may happen on both a market and a facility on the same
    # tick; frozen scan order is MARKETS then FACILITIES.
    var mixed_before: Dictionary = _world(199, false, 0.299, false)
    var mixed_after: Dictionary = _world(200, true, 0.299, false)
    result = _crossing(mixed_before, mixed_after, [market_event], 400)
    if not result.get("ok", false) or result[
            "events_after_n39_commit"] != [market_event, starving]:
        _fail("Rust Bundle(S) market->facility order or combined receipt failed")
        return
    mixed_before["facilities"]["facility-refinery"]["credits"] += 1
    if _crossing(mixed_before, mixed_after, [market_event], 400).get(
            "ok", false):
        _fail("market stage changed a real facility ledger account unnoticed")
        return
    var invalid: Dictionary = _world(0, false, -1.0, false)
    if _crossing(invalid, invalid, [], 400).get("ok", false):
        _fail("negative facility condition admitted to original source scan")
        return

    # Flags survive JSON without creating a secondary event registry.
    var restored: Variant = JSON.parse_string(JSON.stringify(
        commit["world"]))
    if not (restored is Dictionary) or typeof(restored["facilities"][
            "facility-refinery"]["starving_notified"]) != TYPE_BOOL or (
            restored["facilities"]["facility-refinery"][
                "starving_notified"] != false):
        _fail("original Rust persisted warning flag not preserved over JSON")
        return
    print("P2_RUST_CRISIS_ATOMIC_STAGE_SOURCE_PASS")
    quit(0)
