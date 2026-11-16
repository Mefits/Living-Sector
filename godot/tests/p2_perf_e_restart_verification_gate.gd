extends SceneTree
## Negative regression: N38 restart must be checked before accepting new ticks.
const TRACE = preload("res://scripts/sim/phase2/n158_parity_checkpoint_trace.gd")

func snapshot(tick: int) -> Dictionary:
    return {"tick": tick, "world": {"cargo": [1, 2]}, "n9": {"receipts": []},
        "clock": {"tick": tick}, "rng": {"draws": tick}, "bt": {"state": "idle"}}

func _initialize() -> void:
    var trace = TRACE.new()
    assert(not trace.require_restart_verification())
    assert(trace.accept_pair(360, snapshot(360), snapshot(360)))
    assert(trace.require_restart_verification())
    assert(not trace.require_restart_verification())
    assert(trace.status()["restart_pending"])
    assert(trace.verify_restart(360, snapshot(360)))
    assert(not trace.status()["restart_pending"])
    assert(trace.accept_pair(361, snapshot(361), snapshot(361)))

    trace = TRACE.new()
    assert(trace.accept_pair(360, snapshot(360), snapshot(360)))
    assert(trace.require_restart_verification())
    assert(not trace.accept_pair(361, snapshot(361), snapshot(361)))
    assert(trace.status()["failure"]["reason"] == "restart_not_verified")
    assert(not trace.verify_restart(360, snapshot(360)))

    trace = TRACE.new()
    assert(trace.accept_pair(360, snapshot(360), snapshot(360)))
    assert(trace.require_restart_verification())
    var altered = snapshot(360)
    altered["rng"]["draws"] = 99
    assert(not trace.verify_restart(360, altered))
    assert(trace.status()["failure"]["reason"] == "restart_mismatch")
    assert(trace.status()["restart_pending"])
    print("P2_PERF_E_RESTART_VERIFICATION_GATE_PASS")
    quit()
