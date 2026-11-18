extends SceneTree
const REPORT = preload("res://scripts/sim/phase2/n158_source_window_report.gd")

func _rows(end_tick: int, cost: int) -> Dictionary:
    var steps: Array = []
    var phases: Array = []
    for i in range(100):
        var tick: int = end_tick - 99 + i
        steps.append({"tick": tick, "elapsed_usec": cost})
        phases.append({"tick": tick, "ships": cost / 2,
            "dock_queue": cost / 4, "markets": cost / 8,
            "factions": cost / 8})
    return {"steps": steps, "phases": phases}

func _world() -> Dictionary:
    return {"ships": {"a": {}}, "facilities": {"f": {"dock_queue": ["a"]}},
        "contract_board": {"contracts": {"c": {}}},
        "dock_receipts": {"r": {}}}

func _capture(tick: int, cost: int) -> Dictionary:
    var rows: Dictionary = _rows(tick, cost)
    return REPORT.summarize(tick, rows["steps"], rows["phases"],
        _world(), 3, 2)

func _initialize() -> void:
    var early: Dictionary = _capture(100, 1000)
    var late: Dictionary = _capture(300, 1600)
    assert(early["valid"] and late["valid"])
    assert(early["source_step_wall_avg_usec"] == 1000.0)
    assert(late["source_step_wall_p95_usec"] == 1600)
    assert(early["world_sizes"]["dock_waiting"] == 1)
    assert(early["n9_receipts"] == 3 and early["source_events"] == 2)
    assert(not early["worker_request_measured"])
    var delta: Dictionary = REPORT.validate_pair(early, late)
    assert(delta["valid"] and delta["step_wall_avg_delta_usec"] == 600.0)
    assert(delta["phase_avg_delta_usec"]["ships"] == 300.0)
    assert(not REPORT.validate_pair(late, early)["valid"])
    var gap: Dictionary = _rows(300, 1600)
    gap["steps"][55]["tick"] = 1
    assert(REPORT.summarize(300, gap["steps"], gap["phases"],
        _world(), 3, 2)["reason"] == "source_clock_gap")
    var bad_phase: Dictionary = _rows(300, 1600)
    bad_phase["phases"][7]["ships"] = -1
    assert(REPORT.summarize(300, bad_phase["steps"], bad_phase["phases"],
        _world(), 3, 2)["reason"] == "incomplete_phase_window")
    var bad_duration: Dictionary = _rows(300, 1600)
    bad_duration["steps"][1]["elapsed_usec"] = -1
    assert(REPORT.summarize(300, bad_duration["steps"], bad_duration["phases"],
        _world(), 3, 2)["reason"] == "invalid_step_duration")
    assert(REPORT.summarize(300, _rows(300, 1600)["steps"],
        _rows(300, 1600)["phases"], _world(), -1, 2)["reason"] ==
        "missing_authoritative_counts")
    assert(REPORT.summarize(301, _rows(300, 1600)["steps"],
        _rows(300, 1600)["phases"], _world(), 3, 2)["reason"] ==
        "incomplete_paid_window")
    var detached: Dictionary = _world()
    var sample: Dictionary = REPORT.summarize(600,
        _rows(600, 1200)["steps"], _rows(600, 1200)["phases"], detached, 3, 2)
    detached["ships"].clear()
    assert(sample["world_sizes"]["ships"] == 1)
    print("P2_PERF_E_LIVE_BOUNDED_CAPTURE_ORACLE PASS")
    quit(0)
