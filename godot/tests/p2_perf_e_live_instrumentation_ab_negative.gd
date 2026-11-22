extends SceneTree
## Negative/oracle contract for the live N158 A/B adapter. No simulated
## economic ticks are claimed as performance evidence by this fixture.
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
var _left_tick: int = 0
var _right_tick: int = 0
var _fault: String = ""

func _initialize() -> void:
    for fault in ["", "clock", "cargo", "ledger", "rng", "bt", "world",
            "missing_checkpoint", "partial", "bad_timing"]:
        _left_tick = 0
        _right_tick = 0
        _fault = fault
        var result: Dictionary = AB.run_pair(1, 4,
            Callable(self, "_left"), Callable(self, "_right"),
            Callable(self, "_exact"))
        if fault.is_empty():
            if not result.get("accepted", false) or (
                    _left_tick != 4 or _right_tick != 4):
                _fail("positive complete pair refused " + str(result))
                return
        elif result.get("accepted", false):
            _fail("negative accepted: " + fault)
            return
    # Verify acceptance never treats a reused mutable checkpoint as a
    # trustworthy state if one arm mutates cargo before exact comparison.
    _fault = "cargo"
    _left_tick = 0
    _right_tick = 0
    if AB.run_pair(1, 1, Callable(self, "_left"),
            Callable(self, "_right"), Callable(self, "_exact")).get("accepted", false):
        _fail("mutated cargo accepted")
        return
    var sample: Dictionary = {"accepted": true, "from_tick": 1,
        "to_tick": 100, "paid_ticks": 100, "order": "alternating",
        "time_kind": "elapsed_wall_not_cpu", "plain_total_usec": 100,
        "profiled_total_usec": 120, "measured_instrumentation_total_usec": 0,
        "observed_delta_total_usec": 20,
        "checkpoint_plain_total_usec": 2, "checkpoint_profiled_total_usec": 3,
        "checkpoint_total_usec": 5, "checkpoint_time_excluded": true}
    var late: Dictionary = sample.duplicate(true)
    late["from_tick"] = 201
    late["to_tick"] = 300
    if not AB.compare_windows(sample, late).get("accepted", false):
        _fail("valid disjoint windows rejected")
        return
    var forged: Dictionary = late.duplicate(true)
    forged["observed_delta_total_usec"] = 21
    if AB.compare_windows(sample, forged).get("accepted", false):
        _fail("forged overhead accepted")
        return
    print("P2_PERF_E_LIVE_INSTRUMENTATION_AB_NEGATIVE_PASS")
    quit(0)

func _left(tick: int) -> Dictionary:
    _left_tick += 1
    return {"ok": true, "tick": _left_tick, "elapsed_usec": 10,
        "instrumentation_usec": 0, "checkpoint_usec": 2, "checkpoint": _checkpoint(tick)}

func _right(tick: int) -> Dictionary:
    _right_tick += 1
    var checkpoint: Dictionary = _checkpoint(tick)
    match _fault:
        "cargo":
            checkpoint["cargo"]["ore"] = 999
        "ledger":
            checkpoint["ledger"]["receipts"].append({"id": "forged"})
        "rng":
            checkpoint["rng"][0] = 999
        "bt":
            checkpoint["bt"]["task"] = "different"
        "world":
            checkpoint["world"]["ships"][0]["fuel"] = 0
        "missing_checkpoint":
            return {"ok": true, "tick": tick, "elapsed_usec": 12,
                "instrumentation_usec": 0}
    return {"ok": _fault != "partial",
        "tick": tick - (1 if _fault == "clock" else 0),
        "elapsed_usec": -1 if _fault == "bad_timing" else 12,
        "instrumentation_usec": 0, "checkpoint_usec": 2, "checkpoint_usec": 3, "checkpoint": checkpoint}

func _checkpoint(tick: int) -> Dictionary:
    return {"tick": tick, "world": {"ships": [{"id": "s", "fuel": 5}]},
        "cargo": {"ore": 4}, "ledger": {"receipts": [{"id": "r"}]},
        "rng": [42, tick], "bt": {"task": "mine"}}

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return Oracle.compare(a, b).get("equal", false) == true

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_LIVE_INSTRUMENTATION_AB_NEGATIVE_FAIL " + reason)
    quit(1)
