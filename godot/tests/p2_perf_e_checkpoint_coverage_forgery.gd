extends SceneTree
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var baseline: Dictionary = {
        "from_tick": 801, "to_tick": 900,
        "observed_paid_ticks": 100, "expected_paid_ticks": 100,
        "complete": true, "source_fingerprint": "authoritative-checkpoint",
        "time_kind": "elapsed_wall_not_cpu",
        "counts": {"receipts": 10, "contracts": 2, "dock": 1, "events": 4, "ships": 24},
        "advance_wall_avg_usec": 900.0,
        "projection_wall_avg_usec": 50.0,
        "request_wall_avg_usec": 950.0
    }
    var candidate: Dictionary = baseline.duplicate(true)
    candidate["advance_wall_avg_usec"] = 700.0
    candidate["request_wall_avg_usec"] = 750.0
    assert(METRICS.compare_checkpoint_pair(baseline, candidate)["accepted"])
    for fake_count in [0, 1, 99, 101]:
        var forged: Dictionary = candidate.duplicate(true)
        forged["observed_paid_ticks"] = fake_count
        forged["expected_paid_ticks"] = fake_count
        forged["complete"] = true
        var verdict: Dictionary = METRICS.compare_checkpoint_pair(baseline, forged)
        assert(not verdict["accepted"])
    var both_forged: Dictionary = baseline.duplicate(true)
    both_forged["observed_paid_ticks"] = 0
    both_forged["expected_paid_ticks"] = 0
    assert(METRICS.compare_checkpoint_pair(both_forged, both_forged)["reason"] == "invalid_expected_coverage")
    print("P2_PERF_E_CHECKPOINT_COVERAGE_FORGERY PASS")
    quit(0)
