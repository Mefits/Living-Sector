extends SceneTree
const Metrics = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var counts: Dictionary = {"receipts": 20, "contracts": 5, "dock": 2, "events": 7, "ships": 24}
    var base: Dictionary = {
        "from_tick": 801, "to_tick": 900,
        "observed_paid_ticks": 100, "expected_paid_ticks": 100,
        "complete": true, "source_fingerprint": "n38-bt-rng-same",
        "time_kind": "elapsed_wall_not_cpu",
        "counts": counts.duplicate(true),
        "advance_wall_avg_usec": 800.0,
        "projection_wall_avg_usec": 50.0,
        "request_wall_avg_usec": 850.0
    }
    var faster: Dictionary = base.duplicate(true)
    faster["advance_wall_avg_usec"] = 600.0
    faster["request_wall_avg_usec"] = 650.0
    var good: Dictionary = Metrics.compare_checkpoint_pair(base, faster)
    assert(good["accepted"] and good["improved"])
    assert(good["advance_wall_delta_usec"] == -200.0)
    assert(good["advance_wall_ratio"] == 0.75)
    var changed: Dictionary = faster.duplicate(true)
    changed["source_fingerprint"] = "different-rng"
    assert(not Metrics.compare_checkpoint_pair(base, changed)["accepted"])
    changed = faster.duplicate(true)
    changed["counts"]["receipts"] = 21
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "mismatch_count_receipts")
    changed = faster.duplicate(true)
    changed["complete"] = false
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "incomplete_window")
    changed = faster.duplicate(true)
    changed["observed_paid_ticks"] = 99
    assert(not Metrics.compare_checkpoint_pair(base, changed)["accepted"])
    changed = faster.duplicate(true)
    changed["request_wall_avg_usec"] = 640.0
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "invalid_attribution")
    changed = faster.duplicate(true)
    changed["advance_wall_avg_usec"] = -1.0
    assert(not Metrics.compare_checkpoint_pair(base, changed)["accepted"])
    changed = faster.duplicate(true)
    changed.erase("counts")
    assert(not Metrics.compare_checkpoint_pair(base, changed)["accepted"])
    changed = faster.duplicate(true)
    changed["source_fingerprint"] = ""
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "invalid_source_fingerprint")
    changed = faster.duplicate(true)
    changed["time_kind"] = "cpu"
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "invalid_time_kind")
    changed = faster.duplicate(true)
    changed["from_tick"] = 800
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "invalid_tick_window")
    changed = faster.duplicate(true)
    changed["to_tick"] = 899
    assert(Metrics.compare_checkpoint_pair(base, changed)["reason"] == "invalid_tick_window")
    print("P2_PERF_E_SAME_SEED_CHECKPOINT_COMPARATOR PASS")
    quit(0)
