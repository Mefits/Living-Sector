extends SceneTree
const METRICS = preload("res://scripts/sim/phase2/n158_worker_request_metrics.gd")

func _initialize() -> void:
    var early: Dictionary = METRICS.checkpoint_counts(100, {
        "receipts": 12, "contracts": 8, "dock": 4, "events": 20, "ships": 24})
    var late: Dictionary = METRICS.checkpoint_counts(300, {
        "receipts": 30, "contracts": 3, "dock": 6, "events": 10, "ships": 24})
    assert(early["paid_tick"] == 100)
    assert(METRICS.checkpoint_counts(101, {
        "receipts": 1, "contracts": 1, "dock": 1, "events": 1, "ships": 1}).is_empty())
    assert(METRICS.checkpoint_counts(600, {
        "receipts": -1, "contracts": 1, "dock": 1, "events": 1, "ships": 1}).is_empty())
    assert(METRICS.checkpoint_counts(900, {
        "receipts": 1, "contracts": 1, "dock": 1, "events": 1}).is_empty())
    var delta: Dictionary = METRICS.count_delta(early, late)
    assert(delta["receipts"] == 18)
    assert(delta["contracts"] == -5)
    assert(delta["events"] == -10)
    assert(delta["ships"] == 0)
    assert(METRICS.count_delta(late, early).is_empty())
    var no_ticks: Dictionary = METRICS.summarize(100, 100, 1000, 1200, 1300)
    assert(no_ticks["paid_ticks"] == 0)
    assert(no_ticks["advance_wall_usec_per_paid_tick"] == -1.0)
    print("P2_PERF_E_PAID_TICK_SIZE_CHECKPOINT PASS")
    quit(0)
