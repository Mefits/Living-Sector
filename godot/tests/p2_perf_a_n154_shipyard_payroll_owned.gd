extends SceneTree
# Astra II-B: actual N39 N154 paid shipyard staging boundary vs full-deep oracle.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")

func _fixture() -> Dictionary:
    return {
        "facilities": {
            "yard": {"id": "yard", "type": "shipyard", "location": "sol",
                "faction": "f", "credits": 100, "crew_count": 2,
                "work_shift": {}, "work_blocked_reason": "",
                "module_stock": {"stock": {"m": 0}, "dirty": false}},
            "owner": {"id": "owner", "location": "sol", "faction": "f",
                "credits": 50, "work_shift": {}, "work_blocked_reason": "",
                "meta": {"nested": [3]}},
            "other": {"id": "other", "location": "alpha", "faction": "g",
                "credits": 25, "meta": {"nested": [4]}}},
        "populations": {
            "p": {"id": "p", "location": "sol", "faction": "f",
                "count": 10, "wealth": 0, "employed_fraction": 0.0,
                "meta": {"nested": [5]}},
            "unrelated": {"id": "unrelated", "location": "alpha",
                "faction": "g", "count": 10, "wealth": 10,
                "meta": {"nested": [6]}}},
        "markets": {
            "sol": {"id": "sol", "owner": "owner", "supply": {"ore": 9},
                "history": {"dirty": false, "nested": [7]}},
            "alpha": {"id": "alpha", "owner": "other",
                "supply": {"ore": 8}, "history": {"nested": [8]}}},
        "construction_receipts": {"old": {"nested": [9]}},
        "contract_board": {"contracts": {"old": {"nested": [10]}}}
    }

func _mutate_paid_targets(stage: Dictionary) -> void:
    stage["facilities"]["yard"]["credits"] -= 2
    stage["facilities"]["yard"]["work_shift"] = {"tick": 15, "workers": {"p": 2}}
    stage["facilities"]["yard"]["module_stock"]["stock"]["m"] += 1
    stage["facilities"]["owner"]["credits"] += 2
    stage["populations"]["p"]["wealth"] += 2
    stage["populations"]["p"]["employed_fraction"] = 0.3
    stage["markets"]["sol"]["supply"]["ore"] -= 1
    stage["markets"]["sol"]["history"]["dirty"] = true

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var baseline: Dictionary = world.duplicate(true)
    var stage: Dictionary = N39._n154_owned_shipyard_payroll_stage(
        world, "yard", "owner", "sol")
    assert(not stage.is_empty())
    var legacy: Dictionary = world.duplicate(true)
    _mutate_paid_targets(stage)
    _mutate_paid_targets(legacy)
    assert(stage == legacy)
    assert(world == baseline)
    # Nested alias isolation for every actual writable domain.
    stage["facilities"]["owner"]["meta"]["nested"].append(99)
    stage["populations"]["p"]["meta"]["nested"].append(99)
    stage["markets"]["sol"]["history"]["nested"].append(99)
    assert(world == baseline)
    # Rejected wage path writes work_blocked_reason; it must never leak.
    var rejected: Dictionary = N39._n154_owned_shipyard_payroll_stage(
        world, "yard", "owner", "sol")
    var rejected_oracle: Dictionary = world.duplicate(true)
    var blocked: Dictionary = Payroll._blocked(
        rejected, "yard", "insufficient_payroll_budget")
    Payroll._blocked(rejected_oracle, "yard", "insufficient_payroll_budget")
    assert(not blocked["ok"])
    assert(rejected == rejected_oracle)
    assert(world == baseline)
    # Rollback on later Schema/N9 mismatch leaves authoritative World intact.
    rejected["markets"]["sol"]["supply"]["ore"] = -999
    assert(world == baseline)
    # Invalid/missing ownership cannot return a partially writable stage.
    assert(N39._n154_owned_shipyard_payroll_stage(
        world, "absent", "owner", "sol").is_empty())
    assert(N39._n154_owned_shipyard_payroll_stage(
        world, "yard", "absent", "sol").is_empty())
    assert(N39._n154_owned_shipyard_payroll_stage(
        world, "yard", "owner", "alpha").is_empty())
    var malformed: Dictionary = _fixture()
    malformed["populations"]["p"] = []
    assert(N39._n154_owned_shipyard_payroll_stage(
        malformed, "yard", "owner", "sol").is_empty())
    malformed = _fixture()
    malformed["markets"]["sol"] = []
    assert(N39._n154_owned_shipyard_payroll_stage(
        malformed, "yard", "owner", "sol").is_empty())
    # No-op stages and unrelated rows are unchanged; never mutate them.
    var clean: Dictionary = N39._n154_owned_shipyard_payroll_stage(
        world, "yard", "owner", "sol")
    assert(clean == baseline)
    assert(world == baseline)
    print("PASS p2_perf_a_n154_shipyard_payroll_owned")
    quit()
