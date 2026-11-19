extends SceneTree
# Astra II-B: N39 N109/N110 policy ownership, deep-oracle and rollback.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "research_mandates": {
            "f": {"targets": ["ore"], "memory": {"history": [1]}},
            "g": {"targets": ["water"], "memory": {"history": [2]}}},
        "faction_charters": {
            "f": {"rules": {"nested": [3]}},
            "g": {"rules": {"nested": [4]}}},
        "economic_mandates": {
            "f": {"mode": "advise", "meta": {"nested": [5]}},
            "g": {"mode": "hold", "meta": {"nested": [6]}}},
        "markets": {"sol": {"supply": {"food": 10}, "meta": [7]}},
        "contract_board": {"contracts": {"old": {"meta": [8]}}}
    }

func _assert_owned(domain: String, operation: String) -> void:
    var world: Dictionary = _fixture()
    var before: Dictionary = world.duplicate(true)
    assert(N39._n110_policy_domain(operation) == domain)
    var stage: Dictionary = N39._n110_owned_policy_stage(world, domain, "f")
    assert(not stage.is_empty())
    var oracle: Dictionary = world.duplicate(true)
    stage[domain]["f"]["meta_test"] = {"nested": [10]}
    oracle[domain]["f"]["meta_test"] = {"nested": [10]}
    stage[domain]["f"]["meta_test"]["nested"].append(11)
    oracle[domain]["f"]["meta_test"]["nested"].append(11)
    assert(stage == oracle)
    assert(world == before)
    # Rejected policy: a later Schema failure must not leak nested changes.
    stage[domain]["f"].erase("meta_test")
    stage[domain]["f"]["rollback_probe"] = [99]
    assert(world == before)
    # The selected registry can remove one row without touching the source.
    var removed: Dictionary = N39._n110_owned_policy_stage(world, domain, "f")
    removed[domain].erase("f")
    assert(world == before)
    # An unrelated registry is read-only; no writes are performed there.
    assert(removed["markets"] == before["markets"])
    assert(removed["contract_board"] == before["contract_board"])
    # A second faction must be detached independently.
    var other: Dictionary = N39._n110_owned_policy_stage(world, domain, "g")
    other[domain]["g"]["new"] = {"nested": [22]}
    assert(world == before)

func _initialize() -> void:
    _assert_owned("research_mandates", "set_research_mandate")
    _assert_owned("research_mandates", "clear_research_mandate")
    _assert_owned("faction_charters", "set_faction_charter")
    _assert_owned("economic_mandates", "set_economic_mandate")
    _assert_owned("economic_mandates", "clear_economic_mandate")
    assert(N39._n110_policy_domain("invalid") == "")
    assert(N39._n110_owned_policy_stage(_fixture(), "invalid").is_empty())
    # Legacy checkpoints may omit one, two or all policy maps.
    var legacy: Dictionary = {"markets": {"sol": {"meta": [1]}}}
    var stage: Dictionary = N39._n110_owned_policy_stage(
        legacy, "research_mandates", "f")
    assert(stage.has("faction_charters") and stage.has("economic_mandates"))
    assert(stage["research_mandates"].is_empty())
    assert(not legacy.has("research_mandates"))
    # A malformed optional registry or target row fails before any write.
    var invalid: Dictionary = _fixture()
    invalid["faction_charters"] = []
    assert(N39._n110_owned_policy_stage(
        invalid, "research_mandates", "f").is_empty())
    invalid = _fixture()
    invalid["research_mandates"]["f"] = []
    assert(N39._n110_owned_policy_stage(
        invalid, "research_mandates", "f").is_empty())
    # Read-only unrelated nested rows must remain identical to the oracle.
    var unchanged: Dictionary = _fixture()
    var no_change: Dictionary = N39._n110_owned_policy_stage(
        unchanged, "economic_mandates", "f")
    assert(no_change == unchanged.duplicate(true))
    print("PASS p2_perf_a_n110_policy_owned")
    quit()
