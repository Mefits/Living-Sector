extends SceneTree
const TRACE = preload("res://scripts/sim/phase2/n158_parity_checkpoint_trace.gd")

func checkpoint(tick: int) -> Dictionary:
    return {"tick": tick, "world": {"ships": [{"id": "ship", "fuel": 3.5,
        "cargo": {"ore": 2}}], "contracts": [{"id": "c", "paid": true}]},
        "n9": {"balances": {"a": 12}, "receipts": [{"id": "r", "amount": 5}]},
        "clock": {"tick": tick, "paused": true}, "bt": {"ship": ["travel", 1]},
        "rng": {"seed": 42, "draws": tick}}

func _initialize() -> void:
    var trace = TRACE.new()
    for tick in range(360, 363):
        var direct = checkpoint(tick)
        var candidate = direct.duplicate(true)
        assert(trace.accept_pair(tick, direct, candidate))
        candidate["world"]["ships"][0]["cargo"]["ore"] = 999
        assert(trace.status()["ok"])
    assert(trace.status()["pairs"] == 3)
    assert(trace.verify_restart(362, checkpoint(362)))
    assert(trace.accept_pair(363, checkpoint(363), checkpoint(363)))
    assert(trace.status()["last_tick"] == 363)

    trace = TRACE.new()
    assert(trace.accept_pair(1, checkpoint(1), checkpoint(1)))
    assert(not trace.accept_pair(3, checkpoint(3), checkpoint(3)))
    assert(trace.status()["failure"]["reason"] == "non_contiguous_tick")
    assert(not trace.accept_pair(2, checkpoint(2), checkpoint(2)))

    trace = TRACE.new()
    var mismatched = checkpoint(1)
    mismatched["n9"]["receipts"][0]["amount"] = 6
    assert(not trace.accept_pair(1, checkpoint(1), mismatched))
    assert(trace.status()["failure"]["reason"] == "checkpoint_mismatch")
    assert(trace.status()["failure"]["difference"]["path"] == "$[n9][receipts][0][amount]")

    trace = TRACE.new()
    var unsafe = checkpoint(1)
    unsafe["world"]["live"] = RefCounted.new()
    assert(not trace.accept_pair(1, checkpoint(1), unsafe))
    assert(trace.status()["failure"]["reason"] == "unsafe_checkpoint")

    trace = TRACE.new()
    assert(not trace.accept_pair(1, checkpoint(1), checkpoint(2)))
    assert(trace.status()["failure"]["reason"] == "checkpoint_tick_mismatch")

    trace = TRACE.new()
    assert(trace.accept_pair(1, checkpoint(1), checkpoint(1)))
    var changed = checkpoint(1)
    changed["rng"]["draws"] += 1
    assert(not trace.verify_restart(1, changed))
    assert(trace.status()["failure"]["reason"] == "restart_mismatch")

    trace = TRACE.new()
    assert(trace.accept_pair(1, checkpoint(1), checkpoint(1)))
    assert(not trace.verify_restart(0, checkpoint(0)))
    assert(trace.status()["failure"]["reason"] == "restart_boundary_mismatch")

    print("P2_PERF_E_PARITY_CHECKPOINT_TRACE_PASS")
    quit()
