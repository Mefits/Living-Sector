extends SceneTree
const ORACLE = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")

func _initialize() -> void:
    var direct: Dictionary = {
        "tick": 360,
        "clock": {"paused": true, "speed": 8.0},
        "world": {"ships": [{"id": "s1", "fuel": 2.5, "cargo": {"ore": 3}}]},
        "n9": {"balances": {"a": 100}, "receipts": [{"id": "r1", "amount": 5}]},
        "bt": {"s1": ["travel", 2]},
        "rng": [42, 7],
        "contracts": [{"id": "c1", "status": "paid"}]
    }
    var owner: Dictionary = direct.duplicate(true)
    assert(ORACLE.compare(direct, owner)["equal"])
    owner["world"]["ships"][0]["cargo"]["ore"] = 4
    var result: Dictionary = ORACLE.compare(direct, owner)
    assert(not result["equal"])
    assert(result["difference"]["path"] == "$[world][ships][0][cargo][ore]")
    owner = direct.duplicate(true)
    owner["n9"]["receipts"][0]["amount"] = 6
    assert(not ORACLE.compare(direct, owner)["equal"])
    owner = direct.duplicate(true)
    owner["rng"][1] = 8
    assert(not ORACLE.compare(direct, owner)["equal"])
    owner = direct.duplicate(true)
    owner["bt"].erase("s1")
    assert(not ORACLE.compare(direct, owner)["equal"])
    owner = direct.duplicate(true)
    owner["clock"]["speed"] = 8
    assert(not ORACLE.compare(direct, owner)["equal"])
    assert(not ORACLE.compare({"unsafe": RefCounted.new()}, {"unsafe": RefCounted.new()})["equal"])
    assert(not ORACLE.compare({"a": 1}, {"a": 1, "b": 2})["equal"])
    print("P2_PERF_E_CHECKPOINT_PARITY_ORACLE_PASS")
    quit()
