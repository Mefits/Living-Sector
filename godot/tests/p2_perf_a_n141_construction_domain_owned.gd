extends SceneTree
# Astra II-B: exercise the real N39 construction-domain staging helper.
# Compare the legacy deep-copy stage for paid ordinary N141 mutations and
# prove rejected/late operations cannot modify authoritative nested rows.

const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "construction_sites": {
            "a": {"labor": {"hours": 1, "notes": [1]}},
            "b": {"labor": {"hours": 2, "notes": [2]}},
            "idle": {"labor": {"hours": 0, "notes": [3]}}},
        "construction_receipts": {"old": {"history": [1]}},
        "construction_contracts": {"c-a": "a", "c-b": "b"},
        "faction_treasuries": {"f": 100, "other": 20},
        "facilities": {"old": {"credits": 7, "nested": {"cargo": [1]}}},
        "markets": {"loc": {"supply": {"ore": 5}, "history": [1]}},
        "populations": {"worker": {"wealth": 10, "nested": {"items": [2]}},
            "idle": {"wealth": 8, "nested": {"items": [3]}}},
        "ships": {"s": {"cargo": {"ore": 2}}}
    }

func _apply_paid(stage: Dictionary) -> void:
    # Same write shapes as N141: detached paid household, site replacement,
    # scalar treasury, new receipt, key erasure and new facility insertion.
    stage["populations"]["worker"] = stage["populations"]["worker"].duplicate(true)
    stage["populations"]["worker"]["wealth"] += 3
    var site: Dictionary = stage["construction_sites"]["a"].duplicate(true)
    site["labor"]["hours"] += 1
    stage["construction_sites"]["a"] = site
    stage["faction_treasuries"]["f"] -= 3
    stage["construction_receipts"]["new"] = {"kind": "labor", "wages": 3}
    stage["construction_contracts"].erase("c-a")
    stage["facilities"]["new"] = {"credits": 0, "nested": {"cargo": []}}
    stage["construction_sites"].erase("a")

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var original: Dictionary = world.duplicate(true)
    var legacy: Dictionary = world.duplicate(true)
    var owned: Dictionary = N39._n141_owned_construction_domains(world, false)
    _apply_paid(legacy)
    _apply_paid(owned)
    assert(owned == legacy)
    assert(world == original)
    # A later rejected transaction may mutate only its detached paid rows.
    owned["populations"]["worker"]["nested"]["items"].append(9)
    owned["facilities"]["new"]["nested"]["cargo"].append(4)
    assert(world == original)
    # Existing, unpaid nested rows are shared read-only; verify no writes
    # occur to them in the actual N141 write shapes above.
    assert(owned["construction_sites"]["idle"] == original["construction_sites"]["idle"])
    assert(owned["markets"] == original["markets"])
    assert(owned["facilities"]["old"] == original["facilities"]["old"])
    # Multiple paid sites targeting the same household must detach once;
    # the second operation updates only the owned row.
    owned["populations"]["worker"]["wealth"] += 2
    assert(world["populations"]["worker"]["wealth"] == 10)
    # B3 fallback must own every nested row, including otherwise idle actors.
    var colony: Dictionary = N39._n141_owned_construction_domains(world, true)
    assert(colony == original)
    colony["construction_sites"]["idle"]["labor"]["notes"].append(10)
    colony["markets"]["loc"]["history"].append(11)
    colony["facilities"]["old"]["nested"]["cargo"].append(12)
    colony["populations"]["idle"]["nested"]["items"].append(13)
    assert(world == original)
    # Negative: simulate invalid paid proposal after one successful staged
    # write. Discarding the stage must preserve the original World exactly.
    var rejected: Dictionary = N39._n141_owned_construction_domains(world, false)
    _apply_paid(rejected)
    assert(not rejected["construction_sites"].has("missing"))
    assert(world == original)
    print("PASS p2_perf_a_n141_construction_domain_owned")
    quit()
