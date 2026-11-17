extends SceneTree
## Bounded authentic N158/N39 probe: distinguish no AI orders from no map motion.
## Do not require a fake departure. Report real N153/N84/N140 evidence.
const Data = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const MAX_TICK: int = 96

func _initialize() -> void:
    var seed: Dictionary = Data.load_current_world()
    if seed.has("error"):
        _fail("seed missing: " + str(seed["error"]))
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("boot refused: " + str(sim.boot_error()))
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 16.0):
        _fail("cannot configure paid clock")
        return
    sim.advance_frame(0.0)
    var any_flight: bool = false
    var ever_begun: bool = false
    var sample: Dictionary = {}
    var start: int = Time.get_ticks_msec()
    for expected in range(1, MAX_TICK + 1):
        if Time.get_ticks_msec() - start > 180000:
            _fail("probe exceeded bound at tick " + str(sim.tick_count))
            return
        if not sim.queue_control("step", 1):
            _fail("native paid step refused")
            return
        sim.advance_frame(0.0)
        if sim.tick_count != expected or not sim.last_phase_failure().is_empty():
            _fail("source rejected tick " + str(expected) + " " +
                JSON.stringify(sim.last_phase_failure()))
            return
        if expected not in [16, 32, 64, 96]:
            continue
        var economy: Dictionary = sim.economy_snapshot()
        var ships: Dictionary = economy.get("ships", {})
        var flying: int = 0
        var docked: int = 0
        var planned: int = 0
        var assigned: int = 0
        var goals: Dictionary = {}
        for ship in ships.values():
            if not (ship is Dictionary):
                continue
            if ship.get("transit", {}) is Dictionary and not (
                    ship.get("transit", {}) as Dictionary).is_empty():
                flying += 1
            if not str(ship.get("docked_at", "")).is_empty():
                docked += 1
            if ship.get("current_bt", null) is Dictionary and not (
                    ship.get("current_bt", {}) as Dictionary).is_empty():
                planned += 1
            if not str(ship.get("active_contract_id", "")).is_empty():
                assigned += 1
            var goal: String = str(ship.get("current_goal", "—"))
            goals[goal] = int(goals.get(goal, 0)) + 1
        var summary: Dictionary = sim.economy_summary(economy)
        var trace: Dictionary = sim.native_autonomy_diagnostics()
        var board: Dictionary = economy.get("contract_board", {})
        var contracts: Dictionary = board.get("contracts", {})
        var statuses: Dictionary = {}
        for c in contracts.values():
            if c is Dictionary:
                var stage: String = str(c.get("status", "unknown"))
                statuses[stage] = int(statuses.get(stage, 0)) + 1
        any_flight = any_flight or flying > 0
        ever_begun = ever_begun or int(summary.get("n153_departures_this_tick", 0)) > 0
        sample = {
            "tick": expected, "ships": ships.size(),
            "flying": flying, "docked": docked,
            "planned_bt": planned, "assigned": assigned,
            "goals": goals, "contract_statuses": statuses,
            "n140_fired": int(summary.get("n140_ship_fired_this_tick", -1)),
            "n153_accepted": int(summary.get("n153_accepted_this_tick", -1)),
            "n153_blocked": int(summary.get("n153_blocked_this_tick", -1)),
            "n153_first_blocker": str(summary.get("n153_first_blocker", "")),
            "n146_ship_commands": int(summary.get("n146_ship_commands", -1)),
            "n84_traces": int(summary.get("n84_active_traces", -1)),
            "n84_departures": int(summary.get("n153_departures_this_tick", -1)),
            "n84_blocked": (trace.get("n84_blocked", []) as Array).slice(0, 3),
            "n153_blocked_samples": (trace.get("n153_blocked", []) as Array).slice(0, 3)
        }
        print("REAL_SHIP_ACTIVITY_SAMPLE " + JSON.stringify(sample))
    print("REAL_SHIP_ACTIVITY_PROBE_PASS " + JSON.stringify({
        "sampled_through_tick": MAX_TICK,
        "any_sample_flying": any_flight,
        "any_sample_begin_transit": ever_begun,
        "latest": sample
    }))
    quit(0)

func _fail(msg: String) -> void:
    push_error("REAL_SHIP_ACTIVITY_PROBE_FAIL: " + msg)
    quit(1)
