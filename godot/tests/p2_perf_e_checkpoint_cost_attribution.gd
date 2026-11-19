extends SceneTree
## E: checkpoint wall-time is measured separately from paid N158 time.
## Rejects absent, negative, forged and non-gate cost; compares two modes.
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")
var _fault: String = ""

func _initialize() -> void:
    for fault in ["", "missing", "negative", "overflow", "non_gate", "wrong_clock"]:
        _fault = fault
        var report: Dictionary = AB.run_pair(1, 10,
            Callable(self, "_plain"), Callable(self, "_profile"),
            Callable(self, "_exact"), 5)
        if fault.is_empty():
            if not report.get("accepted", false) or (
                    report.get("parity_gates", -1) != 2 or
                    report.get("checkpoint_plain_total_usec", -1) != 14 or
                    report.get("checkpoint_profiled_total_usec", -1) != 22 or
                    report.get("checkpoint_total_usec", -1) != 36 or
                    report.get("plain_total_usec", -1) != 100 or
                    report.get("profiled_total_usec", -1) != 120):
                _fail("positive independent cost accounting " + str(report))
                return
            var late: Dictionary = report.duplicate(true)
            late["from_tick"] = 21
            late["to_tick"] = 30
            if not AB.compare_windows(report, late).get("accepted", false):
                _fail("valid disjoint window rejected")
                return
            late["checkpoint_total_usec"] += 1
            if AB.compare_windows(report, late).get("accepted", false):
                _fail("forged checkpoint sum accepted")
                return
        elif report.get("accepted", false):
            _fail("invalid checkpoint cost accepted: " + fault)
            return
    _fault = ""
    _stride = 1
    var strict: Dictionary = AB.run_pair(1, 10,
        Callable(self, "_plain"), Callable(self, "_profile"),
        Callable(self, "_exact"), 1)
    _stride = 5
    var periodic: Dictionary = AB.run_pair(1, 10,
        Callable(self, "_plain"), Callable(self, "_profile"),
        Callable(self, "_exact"), 5)
    if not strict.get("accepted", false) or not periodic.get("accepted", false):
        _fail("mode source reports rejected")
        return
    var modes: Dictionary = AB.compare_checkpoint_modes([strict], [periodic])
    if not modes.get("accepted", false) or (
            modes.get("strict_checkpoint_wall_usec", -1) != 180 or
            modes.get("periodic_checkpoint_wall_usec", -1) != 36 or
            modes.get("checkpoint_wall_difference_usec", -1) != 144 or
            modes.get("paid_wall_difference_usec", -1) != 0):
        _fail("strict/periodic cost attribution " + str(modes))
        return
    var forged: Dictionary = periodic.duplicate(true)
    forged["checkpoint_plain_total_usec"] += 1
    if AB.compare_checkpoint_modes([strict], [forged]).get("accepted", false):
        _fail("forged mode cost accepted")
        return
    print("P2_PERF_E_CHECKPOINT_COST_ATTRIBUTION_PASS")
    quit(0)

func _plain(tick: int) -> Dictionary:
    return _sample(tick, false)

func _profile(tick: int) -> Dictionary:
    return _sample(tick, true)

func _sample(tick: int, profiled: bool) -> Dictionary:
    var row: Dictionary = {"ok": true, "tick": tick,
        "elapsed_usec": 12 if profiled else 10, "instrumentation_usec": 0}
    if _fault == "wrong_clock" and profiled and tick == 3:
        row["tick"] = 2
    # Strict uses every tick, periodic uses ticks 5 and 10.
    # For the mode comparator fixture, the callback is informed via _stride.
    var gate: bool = tick % _stride == 0
    if _fault == "non_gate" and profiled and tick == 2:
        row["checkpoint_usec"] = 11
    if gate:
        row["checkpoint"] = {"tick": tick, "world": {"cargo": 10},
            "ledger": {"receipts": []}, "rng": [4, tick], "bt": {"job": "mine"}}
        row["checkpoint_usec"] = 11 if profiled else 7
        if _fault == "missing" and profiled and tick == 5:
            row.erase("checkpoint_usec")
        if _fault == "negative" and profiled and tick == 5:
            row["checkpoint_usec"] = -1
        if _fault == "overflow" and profiled and tick == 5:
            row["checkpoint_usec"] = 60000001
    return row

var _stride: int = 5

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return a == b

func _fail(message: String) -> void:
    push_error("P2_PERF_E_CHECKPOINT_COST_ATTRIBUTION_FAIL " + message)
    quit(1)
