extends SceneTree
const ACCEPT = preload("res://scripts/sim/phase2/n158_paid_tick_acceptance.gd")

func _rows(end_tick: int, advance: int) -> Dictionary:
    var phases: Array = []
    var requests: Array = []
    for i in range(100):
        var tick: int = end_tick - 99 + i
        phases.append({"tick": tick, "ships": advance / 2,
            "dock_queue": advance / 4, "markets": advance / 8,
            "factions": advance / 8})
        requests.append({"valid": true, "paid_ticks": 1, "after_tick": tick,
            "advance_wall_usec": advance, "projection_wall_usec": 20,
            "request_wall_usec": advance + 20})
    return {"phases": phases, "requests": requests}

func _capture(end_tick: int, advance: int, checkpoint: Dictionary) -> Dictionary:
    var data: Dictionary = _rows(end_tick, advance)
    var counts: Dictionary = {"receipts": 10, "contracts": 3,
        "dock": 2, "events": 7, "ships": 24}
    return ACCEPT.capture(end_tick, data["phases"], data["requests"],
        counts, checkpoint)

func _initialize() -> void:
    var state: Dictionary = {"paid_tick": 300, "world": {"ships": {"a": {"cargo": 4}}},
        "n9": {"receipts": [1, 2]}, "bt": [1, 3], "rng": 17, "n38": "digest"}
    var direct: Dictionary = _capture(300, 800, state)
    var worker: Dictionary = _capture(300, 600, state)
    assert(direct["valid"] and worker["valid"])
    var result: Dictionary = ACCEPT.compare(direct, worker)
    assert(result["accepted"])
    assert(result["advance_wall_delta_usec"] == -200.0)
    assert(result["time_kind"] == "elapsed_wall_not_cpu")
    assert(not result["performance_measured"])
    # No caller alias survives capture.
    state["world"]["ships"]["a"]["cargo"] = 99
    assert(direct["checkpoint"]["world"]["ships"]["a"]["cargo"] == 4)
    # Exact oracle catches differences in cargo, N9, BT, RNG, or N38.
    for domain in ["n9", "bt", "rng", "n38"]:
        var corrupted: Dictionary = worker.duplicate(true)
        corrupted["checkpoint"][domain] = "corrupted"
        assert(not ACCEPT.compare(direct, corrupted)["accepted"])
    var cargo: Dictionary = worker.duplicate(true)
    cargo["checkpoint"]["world"]["ships"]["a"]["cargo"] = 0
    assert(ACCEPT.compare(direct, cargo)["reason"] == "checkpoint_divergence")
    var sizes: Dictionary = worker.duplicate(true)
    sizes["sizes"]["contracts"] = 9
    assert(ACCEPT.compare(direct, sizes)["reason"] == "size_divergence")
    var partial: Dictionary = worker.duplicate(true)
    partial["requests"]["observed_paid_ticks"] = 99
    assert(not ACCEPT.compare(direct, partial)["accepted"])
    var source: Dictionary = _rows(300, 600)
    source["requests"][40]["after_tick"] = 260
    assert(not ACCEPT.capture(300, source["phases"], source["requests"],
        {"receipts": 10, "contracts": 3, "dock": 2, "events": 7, "ships": 24},
        {"paid_tick": 300})["valid"])
    source = _rows(300, 600)
    source["requests"][1]["paid_ticks"] = 2
    assert(not ACCEPT.capture(300, source["phases"], source["requests"],
        {"receipts": 10, "contracts": 3, "dock": 2, "events": 7, "ships": 24},
        {"paid_tick": 300})["valid"])
    assert(not _capture(300, 600, {"paid_tick": 299})["valid"])
    assert(not _capture(301, 600, {"paid_tick": 301})["valid"])
    print("P2_PERF_E_PAID_TICK_ACCEPTANCE_BUNDLE PASS")
    quit(0)
