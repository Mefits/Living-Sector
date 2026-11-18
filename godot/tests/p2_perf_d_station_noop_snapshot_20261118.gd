extends RefCounted
## N18 non-due paid-tick regression: do not copy or expose persisted memory.
## N39 only consumes the returned snapshots on due staffing cycles.
const Station = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")

static func run() -> Dictionary:
    var memory: Dictionary = {"faction|earth": {
        "retained": {"factory-1": true},
        "history": [{"tick": 5, "priority": ["ore", "food"]}]}}
    var original: Dictionary = memory.duplicate(true)
    var world: Dictionary = {
        "facilities": {}, "markets": {}, "populations": {},
        "station_administration": memory,
        "station_administration_last_tick": 5}
    var ledger: RefCounted = RefCounted.new()
    for tick in [6, 7, 8, 9, 11, 12, 13, 14]:
        var idle: Dictionary = Station.propose(world, ledger, tick, 1)
        if not idle.get("ok", false) or idle.get("due", true):
            return {"ok": false, "reason": "idle_clock", "tick": tick}
        if idle.get("assignments") != {} or idle.get("views") != []:
            return {"ok": false, "reason": "idle_proposal_changed", "tick": tick}
        if idle.get("snapshots") != {}:
            return {"ok": false, "reason": "idle_copied_unused_history", "tick": tick}
        idle["snapshots"]["injected"] = {"retained": {"factory-1": false}}
        if world["station_administration"] != original:
            return {"ok": false, "reason": "idle_alias_mutated_world", "tick": tick}
    # Preserve validation precedence on invalid clocks and invalid persisted memory.
    var bad_clock: Dictionary = Station.propose(world, ledger, 0, 1)
    if bad_clock.get("ok", true) or bad_clock.get("reason") != "n18_invalid_native_station_clock":
        return {"ok": false, "reason": "clock_guard"}
    world["station_administration"] = []
    var invalid: Dictionary = Station.propose(world, ledger, 6, 1)
    if invalid.get("ok", true) or invalid.get("reason") != "n18_invalid_persisted_administrator":
        return {"ok": false, "reason": "memory_guard"}
    return {"ok": true, "idle_ticks": 8, "world_unchanged": true}
