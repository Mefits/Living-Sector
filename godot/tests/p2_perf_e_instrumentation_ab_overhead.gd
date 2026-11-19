extends SceneTree
const AB = preload("res://scripts/sim/phase2/n158_instrumentation_ab_acceptance.gd")
var plain_clock: int = 0
var profile_clock: int = 0
var broken: String = ""

func _initialize() -> void:
    var result: Dictionary = AB.run_pair(1, 100,
        Callable(self, "_plain"), Callable(self, "_profile"),
        Callable(self, "_exact"))
    if not result.get("accepted", false) or result["paid_ticks"] != 100 or (
            result["observed_delta_total_usec"] != 300 or
            result["measured_instrumentation_total_usec"] != 100 or
            result["delta_p95_usec"] != 3):
        _fail("positive paired accounting " + str(result))
        return
    if plain_clock != 100 or profile_clock != 100:
        _fail("not exactly 100 calls per arm")
        return
    var late: Dictionary = result.duplicate(true)
    late["from_tick"] = 201
    late["to_tick"] = 300
    if not AB.compare_windows(result, late).get("accepted", false):
        _fail("valid independent windows")
        return
    var forged: Dictionary = late.duplicate(true)
    forged["observed_delta_total_usec"] += 1
    if AB.compare_windows(result, forged).get("accepted", false):
        _fail("forged total accepted")
        return
    forged = late.duplicate(true)
    forged["from_tick"] = 50
    forged["to_tick"] = 149
    if AB.compare_windows(result, forged).get("accepted", false):
        _fail("overlap accepted")
        return
    for failure in ["clock", "state", "cost", "negative", "failed"]:
        broken = failure
        plain_clock = 0
        profile_clock = 0
        var invalid: Dictionary = AB.run_pair(1, 3,
            Callable(self, "_plain"), Callable(self, "_profile"),
            Callable(self, "_exact"))
        if invalid.get("accepted", false):
            _fail("accepted negative fixture " + failure)
            return
    print("P2_PERF_E_INSTRUMENTATION_AB_OVERHEAD_PASS")
    quit(0)

func _plain(tick: int) -> Dictionary:
    plain_clock += 1
    return {"ok": true, "tick": tick, "elapsed_usec": 10,
        "instrumentation_usec": 0, "checkpoint": _state(tick)}

func _profile(tick: int) -> Dictionary:
    profile_clock += 1
    var checkpoint: Dictionary = _state(tick)
    if broken == "state":
        checkpoint["cargo"]["ore"] += 1
    return {"ok": broken != "failed",
        "tick": tick - (1 if broken == "clock" else 0),
        "elapsed_usec": -1 if broken == "negative" else 13,
        "instrumentation_usec": 14 if broken == "cost" else 1,
        "checkpoint": checkpoint}

func _state(tick: int) -> Dictionary:
    return {"tick": tick, "world": {"ships": [{"id": "s", "fuel": 8}]},
        "cargo": {"ore": 5}, "ledger": {"receipts": [{"id": "r"}]},
        "rng": [42, tick], "bt": {"task": "mine"}}

func _exact(a: Dictionary, b: Dictionary) -> bool:
    return a == b

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_INSTRUMENTATION_AB_OVERHEAD_FAIL " + reason)
    quit(1)
