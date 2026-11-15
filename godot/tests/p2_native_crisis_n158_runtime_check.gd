extends SceneTree
## Deferred full Godot acceptance of source Rust Bundle(S) in real N158.
## This modifies ONLY isolated test runner's physical source checkpoint,
## not the frozen seed, game balance or any production save.
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Saves = preload("res://scripts/sim/save_state.gd")

var _events: Array[Dictionary] = []

func _capture(event: Dictionary) -> void:
    _events.append(event.duplicate(true))

func _count(kind: String) -> int:
    var count: int = 0
    for event in _events:
        if str(event.get("kind", "")) == kind:
            count += 1
    return count

func _fail(reason: String) -> void:
    push_error("P2_RUST_CRISIS_LIVE: " + reason)
    quit(1)

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy source seed unavailable")
        return
    var a = Runner.new()
    if not a.start_from_seed(seed):
        _fail("canonical N158 source boot rejected: " + a.boot_error())
        return
    if not a.economy_snapshot().get("markets", {}).has("earth-station"):
        _fail("real source Earth market missing")
        return
    var checkpoint: Dictionary = a.production.snapshot()
    var physical: Dictionary = checkpoint["world"]
    var m: Dictionary = physical["markets"]["earth-station"]
    if not (m.get("history") is Dictionary) or not (
            m["history"].get("shortage_ticks") is Dictionary):
        _fail("N150 MarketHistory absent from source physical world")
        return
    # Market shortage normally accrues over many frozen Rust game-seconds.
    # Prime only the isolated test market to the exact entry boundary.
    m["history"]["shortage_ticks"]["food"] = 200
    m["history"]["crisis_notified"] = {"food": false}
    var facility_id: String = ""
    var ids: Array = physical["facilities"].keys()
    ids.sort()
    for id in ids:
        if physical["facilities"][id].has("condition"):
            facility_id = str(id)
            break
    if facility_id.is_empty():
        _fail("no real source FacilityOperations available for test")
        return
    var facility: Dictionary = physical["facilities"][facility_id]
    facility["condition"] = 0.01
    facility["starving_notified"] = false
    # Prevent an unrelated N156 Tools repair from crossing 0.3
    # before the Rust crisis phase, without changing any production rule.
    if facility.get("reserves") is Dictionary:
        facility["reserves"]["tools"] = 0.0
    if not a.production.restore(checkpoint):
        _fail("source N39 refused isolated valid warning threshold fixture")
        return
    var bank_before: Dictionary = a.production.ledger_snapshot()
    if bank_before.is_empty():
        _fail("source N9 ledger not initialized")
        return
    a.scheduled_event_due.connect(_capture)
    a.queue_control("pause")
    a.advance_frame(0.0)
    a.queue_control("step", 1)
    a.advance_frame(0.0)
    if a.tick_count != 1:
        _fail("single tick failed before original Rust crisis phase: " +
            str(a.last_phase_failure()))
        return
    var result: Dictionary = a.last_crisis_result()
    var live: Dictionary = a.economy_snapshot()
    if not result.get("ok", false):
        _fail("real N39 crisis Apply failed: " + str(result))
        return
    if not live["markets"]["earth-station"]["history"][
            "crisis_notified"].get("food", false):
        _fail("N150 market hysteresis not persisted in actual N39 World")
        return
    if not live["facilities"][facility_id].get("starving_notified", false):
        _fail("facility warning not committed to real N39 FacilityOperations")
        return
    if _count("market_crisis") != 1 or _count("facility_starving") != 1:
        _fail("original source events not emitted exactly once after commit: " +
            str(_events))
        return
    for event in result.get("events", []):
        if not _events.has(event):
            _fail("N39 source event differs from N1 existing signal payload")
            return
    a.queue_control("step", 1)
    a.advance_frame(0.0)
    if a.tick_count != 2 or _count("market_crisis") != 1 or _count(
            "facility_starving") != 1:
        _fail("persisted warning flags did not suppress repeated event")
        return
    var committed: Dictionary = a.checkpoint()
    if committed.get("native_production", {}).get(
            "world", {}).get("facilities", {}).get(
            facility_id, {}).get("starving_notified", null) != true:
        _fail("N38 checkpoint lost canonical facility warning flag")
        return
    var path: String = "user://tests/p2-crisis-bundle-s-" + str(
        Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(a, path) != OK:
        _fail("actual N38 saved economic World failed")
        return
    var b = Runner.new()
    if not b.start_from_seed(seed):
        _fail("second frozen seed runtime initialization failed")
        return
    b.scheduled_event_due.connect(_capture)
    var loaded: Dictionary = Saves.load_runner(b, seed, path)
    if not loaded.get("ok", false) or b.tick_count != 2:
        _fail("native Rust warning flags not restored from N38: " +
            str(loaded))
        return
    if not b.economy_snapshot()["facilities"][facility_id].get(
            "starving_notified", false) or not b.economy_snapshot()["markets"][
            "earth-station"]["history"]["crisis_notified"].get("food", false):
        _fail("N38 reload lost native market or facility hysteresis")
        return
    if not b.last_crisis_result().is_empty():
        _fail("N38 reload replayed transient pre-save crisis events")
        return
    b.queue_control("pause")
    b.advance_frame(0.0)
    b.queue_control("step", 1)
    b.advance_frame(0.0)
    if b.tick_count != 3 or _count("market_crisis") != 1 or _count(
            "facility_starving") != 1:
        _fail("saved/resumed real Rust crisis warning replayed on next tick")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_RUST_CRISIS_LIVE_N39_N158_N38_SOURCE_PASS")
    quit(0)
