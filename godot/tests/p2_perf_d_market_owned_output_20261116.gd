extends SceneTree
## PERF D: N150-owned result must not alias source or another market.
## Run with Godot --headless --path godot --script res://tests/p2_perf_d_market_owned_output_20261116.gd
const Phase = preload("res://scripts/sim/phase2/unified_market_phase.gd")

func _market(id: String) -> Dictionary:
    return {
        "id": id, "supply": {"ore": 4.0}, "prices": {"ore": 20.0},
        "demand": {"ore": 8.0}, "elasticity": 0.05, "spread": 0.1,
        "seed_demand": {"ore": 8.0},
        "consumption_window": {"ore": [{"tick": 0, "qty": 2.0, "meta": {"nested": [1]}}]},
        "orders": {"pending_buys": [{"agent_id": "buyer", "placed_at_tick": 0, "meta": {"nested": [2]}}],
            "pending_sells": [], "reserved": {}, "order_expiry_ticks": 50},
        "history": {"shortage_ticks": {"ore": 199}, "trend_samples": [],
            "spawned_at_tick": 0, "last_tick": 0}
    }

func _check(value: bool, message: String) -> bool:
    if not value:
        push_error(message)
    return value

func _initialize() -> void:
    var ok: bool = true
    var world: Dictionary = {"markets": {"earth": _market("m-earth"), "mars": _market("m-mars")}}
    var before: Dictionary = world.duplicate(true)
    var result: Dictionary = Phase.propose(world, 16, 1)
    ok = _check(bool(result.get("ok", false)), "market proposal failed") and ok
    if result.get("ok", false):
        var updates: Dictionary = result["updates"]
        var untouched: Dictionary = updates["mars"].duplicate(true)
        updates["earth"]["prices"]["ore"] = 400.0
        updates["earth"]["orders"]["pending_buys"][0]["meta"]["nested"].append(99)
        updates["earth"]["consumption_window"]["ore"][0]["meta"]["nested"].append(98)
        updates["earth"]["history"]["shortage_ticks"]["ore"] = 500
        ok = _check(world == before, "output aliased authoritative World") and ok
        ok = _check(updates["mars"] == untouched, "market output aliases another market") and ok
        var repeated: Dictionary = Phase.propose(world, 16, 1)
        ok = _check(bool(repeated.get("ok", false)), "repeat proposal failed") and ok
        if repeated.get("ok", false):
            ok = _check(repeated["updates"]["earth"] != updates["earth"], "repeat proposal inherited mutated output") and ok
    var invalid: Dictionary = world.duplicate(true)
    invalid["markets"]["mars"]["orders"]["pending_buys"][0]["placed_at_tick"] = "bad"
    var rejected: Dictionary = Phase.propose(invalid, 16, 1)
    ok = _check(not bool(rejected.get("ok", false)), "invalid second market accepted") and ok
    ok = _check(invalid["markets"]["earth"] == before["markets"]["earth"], "failed proposal changed another market") and ok
    print("p2_perf_d_market_owned_output_20261116: ", "PASS" if ok else "FAIL")
    quit(0 if ok else 1)
