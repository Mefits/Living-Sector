extends SceneTree
# Astra II-B: N108 gate pair / paid jump owned publication vs deep-copy oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _source() -> Dictionary:
    return {
        "facilities": {
            "ga": {"credits": 10, "dirty": false, "gate_link": {"to": "", "history": [1]}},
            "gb": {"credits": 20, "dirty": false, "gate_link": {"to": "", "history": [2]}},
            "other": {"credits": 30, "meta": {"history": [3]}}},
        "ships": {
            "ship": {"credits": 100, "location": "a",
                "memory": {"recent_systems": ["a"]}, "position": [0, 0]},
            "idle": {"credits": 50, "memory": {"recent_systems": ["b"]}}},
        "native_gate_pair_receipts": {"oldpair": {"history": [1]}},
        "native_gate_jump_receipts": {"oldjump": {"history": [2]}},
        "markets": {"a": {"stock": {"ore": 5}}}
    }

func _initialize() -> void:
    var source: Dictionary = _source()
    var baseline: Dictionary = source.duplicate(true)
    var pair: Dictionary = source.duplicate(true)
    pair["facilities"]["ga"]["gate_link"]["to"] = "gb"
    pair["facilities"]["gb"]["gate_link"]["to"] = "ga"
    pair["facilities"]["ga"]["dirty"] = true
    pair["facilities"]["gb"]["dirty"] = true
    pair["native_gate_pair_receipts"]["pair2"] = {"kind": "pair", "history": [4]}
    var owned_pair: Dictionary = N39._n108_owned_gate_publication(
        source, pair, ["ga", "gb"], "", "native_gate_pair_receipts", "pair2")
    assert(not owned_pair.is_empty())
    assert(owned_pair == pair)
    assert(source == baseline)
    owned_pair["facilities"]["ga"]["gate_link"]["history"].append(99)
    owned_pair["native_gate_pair_receipts"]["pair2"]["history"].append(99)
    assert(source == baseline)
    assert(pair["facilities"]["ga"]["gate_link"]["history"] == [1])
    assert(pair["native_gate_pair_receipts"]["pair2"]["history"] == [4])
    var jump: Dictionary = source.duplicate(true)
    jump["ships"]["ship"]["credits"] = 93
    jump["ships"]["ship"]["location"] = "b"
    jump["ships"]["ship"]["position"] = [10, 20]
    jump["ships"]["ship"]["memory"]["recent_systems"].append("b")
    jump["facilities"]["ga"]["credits"] = 17
    jump["native_gate_jump_receipts"]["jump2"] = {"fee": 7, "meta": [6]}
    var owned_jump: Dictionary = N39._n108_owned_gate_publication(
        source, jump, ["ga"], "ship", "native_gate_jump_receipts", "jump2")
    assert(not owned_jump.is_empty())
    assert(owned_jump == jump)
    assert(source == baseline)
    owned_jump["ships"]["ship"]["memory"]["recent_systems"].append("x")
    owned_jump["facilities"]["ga"]["gate_link"]["history"].append(99)
    owned_jump["native_gate_jump_receipts"]["jump2"]["meta"].append(99)
    assert(source == baseline)
    assert(jump["ships"]["ship"]["memory"]["recent_systems"] == ["a", "b"])
    assert(jump["native_gate_jump_receipts"]["jump2"]["meta"] == [6])
    # Rejected proposals cannot publish unrelated writes or historical edits.
    var bad: Dictionary = jump.duplicate(true)
    bad["ships"]["idle"]["credits"] = 999
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    bad = jump.duplicate(true)
    bad["markets"]["a"]["stock"]["ore"] = 0
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    bad = jump.duplicate(true)
    bad["native_gate_jump_receipts"]["oldjump"]["history"].append(99)
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    bad = jump.duplicate(true)
    bad["facilities"]["gb"]["credits"] = 0
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    bad = jump.duplicate(true)
    bad["native_gate_jump_receipts"].erase("oldjump")
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    bad = jump.duplicate(true)
    bad["native_gate_jump_receipts"]["jump2"] = []
    assert(N39._n108_owned_gate_publication(source, bad,
        ["ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    assert(N39._n108_owned_gate_publication(source, jump,
        ["ga", "ga"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    assert(N39._n108_owned_gate_publication(source, jump,
        ["missing"], "ship", "native_gate_jump_receipts", "jump2").is_empty())
    assert(N39._n108_owned_gate_publication(source, jump,
        ["ga"], "missing", "native_gate_jump_receipts", "jump2").is_empty())
    assert(N39._n108_owned_gate_publication(source, jump,
        ["ga"], "ship", "native_gate_jump_receipts", "oldjump").is_empty())
    assert(source == baseline)
    print("PASS p2_perf_a_n108_gate_owned_publication")
    quit()
