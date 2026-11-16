extends SceneTree
## Negative regression: an unsolicited restore cannot silently pass as N38 parity.
const TRACE = preload("res://scripts/sim/phase2/n158_parity_checkpoint_trace.gd")

func _snapshot(tick: int) -> Dictionary:
    return {"tick": tick, "world": {"cargo": [1]}, "n9": {"receipts": []},
        "clock": {"tick": tick}, "rng": {"draws": tick}, "bt": {"state": "idle"}}

func _initialize() -> void:
    var trace = TRACE.new()
    assert(trace.accept_pair(360, _snapshot(360), _snapshot(360)))
    assert(not trace.verify_restart(360, _snapshot(360)))
    assert(trace.status()["failure"]["reason"] == "restart_not_requested")
    assert(not trace.accept_pair(361, _snapshot(361), _snapshot(361)))
    assert(not trace.require_restart_verification())

    trace = TRACE.new()
    assert(trace.accept_pair(360, _snapshot(360), _snapshot(360)))
    assert(trace.require_restart_verification())
    assert(trace.verify_restart(360, _snapshot(360)))
    assert(trace.accept_pair(361, _snapshot(361), _snapshot(361)))
    print("P2_PERF_E_RESTART_REQUIRES_ARM_PASS")
    quit()
