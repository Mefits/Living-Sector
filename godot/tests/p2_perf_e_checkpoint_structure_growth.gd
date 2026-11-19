extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_checkpoint_structure_growth.gd")
const Oracle = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")

func _initialize() -> void:
    var world: Dictionary = {"world": {"ships": [{"id": "a"}, {"id": "b"}],
        "dock": [1, 2]}, "n9": {"receipts": [3]}, "rng": 42}
    var same: Dictionary = world.duplicate(true)
    var exact: Dictionary = Oracle.compare(world, same)
    var a: Dictionary = Probe.capture(100, world)
    var b: Dictionary = Probe.capture(100, same)
    assert(a.get("accepted", false))
    assert(a["nodes"] == a["dictionaries"] + a["arrays"] + a["leaves"])
    var paired: Dictionary = Probe.pair(a, b, exact)
    assert(paired.get("accepted", false))
    assert(paired["tick"] == 100)
    # Scalar-only result cannot alias a later mutable World.
    world["world"]["ships"].append({"id": "c"})
    assert(paired["nodes"] == a["nodes"])
    var late: Dictionary = Probe.pair(Probe.capture(300, world),
        Probe.capture(300, world.duplicate(true)), Oracle.compare(world, world.duplicate(true)))
    assert(late.get("accepted", false))
    var drift: Dictionary = Probe.growth(paired, late)
    assert(drift.get("accepted", false))
    assert(drift["delta"]["nodes"] > 0)
    assert(not Probe.growth(late, paired).get("accepted", false))
    assert(not Probe.pair(a, Probe.capture(101, same), exact).get("accepted", false))
    assert(not Probe.pair(a, b, {"equal": false, "difference": {"path": "$.rng"}}).get("accepted", false))
    var forged: Dictionary = a.duplicate(true)
    forged["nodes"] += 1
    assert(not Probe.pair(forged, b, exact).get("accepted", false))
    var wrong: Dictionary = same.duplicate(true)
    wrong["rng"] = 999
    assert(not Probe.pair(a, b, Oracle.compare(same, wrong)).get("accepted", false))
    assert(not Probe.capture(100, {"object": RefCounted.new()}).get("accepted", false))
    assert(not Probe.capture(100, {"bad": Callable(self, "_initialize")}).get("accepted", false))
    assert(not Probe.capture(0, {}).get("accepted", false))
    print("P2_PERF_E_CHECKPOINT_STRUCTURE_GROWTH PASS")
    quit(0)
