extends SceneTree
## Positive/negative regression for the E live periodic full-state parity mode.
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
var _left: int = 0
var _right: int = 0
var _fault: String = ""

func _initialize() -> void:
    for fault in ["", "missing_gate", "extra_checkpoint", "divergent_gate",
            "wrong_clock", "failed_paid_tick"]:
        _fault = fault
        _left = 0
        _right = 0
        var report: Dictionary = AB.run_pair(1, 10, Callable(self, "_step_left"),
            Callable(self, "_step_right"), Callable(self, "_exact"), 5)
        if fault.is_empty():
            if not report.get("accepted", false) or (
                    report.get("parity_gates", 0) != 2 or
                    report.get("checkpoint_stride", 0) != 5 or
                    _left != 10 or _right != 10):
                _fail("valid bounded periodic gates rejected: " + str(report))
                return
        elif report.get("accepted", false):
            _fail("invalid periodic pair accepted: " + fault)
            return
    _fault = ""
    _left = 0
    _right = 0
    if AB.run_pair(1, 10, Callable(self, "_step_left"),
            Callable(self, "_step_right"), Callable(self, "_exact"), 11).get("accepted", false):
        _fail("stride beyond paid window accepted")
        return
    var early: Dictionary = {"accepted": true, "order": "alternating",
        "time_kind": "elapsed_wall_not_cpu", "from_tick": 1, "to_tick": 10,
        "paid_ticks": 10, "checkpoint_stride": 5, "parity_gates": 2,
        "plain_total_usec": 100, "profiled_total_usec": 120,
        "measured_instrumentation_total_usec": 0, "observed_delta_total_usec": 20}
    var late: Dictionary = early.duplicate(true)
    late["from_tick"] = 21
    late["to_tick"] = 30
    if not AB.compare_windows(early, late).get("accepted", false):
        _fail("valid periodic report rejected")
        return
    late["parity_gates"] = 1
    if AB.compare_windows(early, late).get("accepted", false):
        _fail("forged parity coverage accepted")
        return
    print("P2_PERF_E_AB_PERIODIC_CHECKPOINT_ORACLE_PASS")
    quit(0)

func _step_left(tick: int) -> Dictionary:
    _left += 1
    return _sample(tick, false)

func _step_right(tick: int) -> Dictionary:
    _right += 1
    return _sample(tick, true)

func _sample(tick: int, right: bool) -> Dictionary:
    var row: Dictionary = {"ok": true, "tick": tick, "elapsed_usec": 10,
        "instrumentation_usec": 0}
    if right and _fault == "wrong_clock" and tick == 3:
        row["tick"] = tick - 1
    if right and _fault == "failed_paid_tick" and tick == 3:
        row["ok"] = false
    var gate: bool = tick % 5 == 0
    if right and _fault == "extra_checkpoint" and tick == 2:
        gate = true
    if right and _fault == "missing_gate" and tick == 5:
        gate = false
    if gate:
        row["checkpoint"] = {"tick": tick, "world": {"cargo": 10},
            "ledger": {"receipts": []}, "rng": [3, tick], "bt": {"action": "mine"}}
        if right and _fault == "divergent_gate" and tick == 10:
            row["checkpoint"]["world"]["cargo"] = 99
    return row

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return Oracle.compare(a, b).get("equal", false) == true

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_AB_PERIODIC_CHECKPOINT_ORACLE_FAIL " + reason)
    quit(1)
