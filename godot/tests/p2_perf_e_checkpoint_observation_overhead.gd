extends SceneTree
## E checkpoint observation accounting: detached real checkpoint fixtures.
const Acceptance = preload("res://scripts/sim/phase2/n158_direct_threaded_acceptance.gd")

func _initialize() -> void:
    var checkpoint: Dictionary = {"tick": 100, "native_production": {
        "rng": [7, 8], "ledger": {"receipts": [1]},
        "ships": [{"cargo": 4}]}}
    var worker: Dictionary = {"ok": true, "tick": 100,
        "checkpoint": checkpoint.duplicate(true)}
    var row: Dictionary = Acceptance.checkpoint_observation_sample(
        100, 120, 340, checkpoint, worker)
    if not row.get("accepted", false):
        _fail("valid detached boundary rejected")
        return
    var next_checkpoint: Dictionary = checkpoint.duplicate(true)
    next_checkpoint["tick"] = 300
    var next_worker: Dictionary = {"ok": true, "tick": 300,
        "checkpoint": next_checkpoint.duplicate(true)}
    var next_row: Dictionary = Acceptance.checkpoint_observation_sample(
        300, 80, 200, next_checkpoint, next_worker)
    var report: Dictionary = Acceptance.summarize_checkpoint_observations(
        [row, next_row], [100, 300])
    if not report.get("accepted", false) or (
            int(report.get("direct_total_wall_usec", -1)) != 200 or
            int(report.get("worker_request_total_wall_usec", -1)) != 540 or
            report.get("included_in_paid_tick_window", true) != false):
        _fail("valid milestone attribution")
        return
    checkpoint["native_production"]["ships"][0]["cargo"] = 999
    if report["milestones"][0]["direct_usec"] != 120:
        _fail("report retained live checkpoint alias")
        return
    var corrupted: Dictionary = worker.duplicate(true)
    corrupted["checkpoint"]["native_production"]["rng"][0] = 10
    if Acceptance.checkpoint_observation_sample(
            100, 120, 340, worker["checkpoint"], corrupted).get("accepted", false):
        _fail("RNG divergence accepted")
        return
    corrupted = worker.duplicate(true)
    corrupted["tick"] = 101
    if Acceptance.checkpoint_observation_sample(
            100, 120, 340, worker["checkpoint"], corrupted).get("accepted", false):
        _fail("wrong worker source tick accepted")
        return
    if Acceptance.checkpoint_observation_sample(
            100, -1, 340, worker["checkpoint"], worker).get("accepted", false):
        _fail("negative elapsed time accepted")
        return
    if Acceptance.summarize_checkpoint_observations(
            [row], [100, 300]).get("accepted", false):
        _fail("missing milestone accepted")
        return
    if Acceptance.summarize_checkpoint_observations(
            [row, row], [100, 300]).get("accepted", false):
        _fail("duplicate milestone accepted")
        return
    if Acceptance.summarize_checkpoint_observations(
            [next_row, row], [300, 100]).get("accepted", false):
        _fail("reversed milestone accepted")
        return
    var forged: Dictionary = row.duplicate(true)
    forged["included_in_paid_tick_window"] = true
    if Acceptance.summarize_checkpoint_observations(
            [forged], [100]).get("accepted", false):
        _fail("misattributed observation accepted")
        return
    forged = row.duplicate(true)
    forged["worker_checkpoint_request_wall_usec"] = -20
    if Acceptance.summarize_checkpoint_observations(
            [forged], [100]).get("accepted", false):
        _fail("invalid worker request timing accepted")
        return
    print("P2_PERF_E_CHECKPOINT_OBSERVATION_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PERF_E_CHECKPOINT_OBSERVATION_FAIL " + message)
    quit(1)
