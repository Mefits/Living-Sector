extends SceneTree
# N151 founding approval owned-write parity and negative alias regression.
# godot --headless --path godot --script res://tests/p2_perf_a_n151_foundation_owned_stage.gd

func _initialize() -> void:
    var authority: Dictionary = {
        "construction_sites": {"old": {"materials": {"metals": 12}}},
        "construction_receipts": {"old": {"proof": ["approved"]}},
        "ships": {"ship": {"cargo": {"metals": 7}}},
        "markets": {"station": {"stock": {"water": 20}}},
        "contract_board": {"contracts": [{"id": "c1"}]}
    }
    var before: Dictionary = authority.duplicate(true)
    var site: Dictionary = {"id": "new", "materials": {"metals": 0}}
    var receipt: Dictionary = {"id": "n151_colony_approved:new", "capital": 0}
    var oracle: Dictionary = authority.duplicate(true)
    oracle["construction_sites"]["new"] = site.duplicate(true)
    oracle["construction_receipts"][receipt["id"]] = receipt.duplicate(true)

    var staged: Dictionary = authority.duplicate()
    staged["construction_sites"] = authority["construction_sites"].duplicate(true)
    staged["construction_receipts"] = authority["construction_receipts"].duplicate(true)
    staged["construction_sites"]["new"] = site.duplicate(true)
    staged["construction_receipts"][receipt["id"]] = receipt.duplicate(true)
    assert(staged == oracle, "N151 owned stage differs from full World oracle")
    assert(authority == before, "N151 stage mutated authoritative World")

    # A failed validation must not mutate either authoritative nested domain.
    var rejected: Dictionary = authority.duplicate()
    rejected["construction_sites"] = authority["construction_sites"].duplicate(true)
    rejected["construction_receipts"] = authority["construction_receipts"].duplicate(true)
    rejected["construction_sites"]["old"]["materials"]["metals"] = -5
    rejected["construction_receipts"]["old"]["proof"].append("invalid")
    assert(authority == before, "rejected N151 approval leaked into authority")

    # A caller may mutate its proposal after commit; the stored site stays detached.
    site["materials"]["metals"] = 99
    receipt["capital"] = 99
    assert(staged["construction_sites"]["new"]["materials"]["metals"] == 0)
    assert(staged["construction_receipts"]["n151_colony_approved:new"]["capital"] == 0)

    # Negative control: shallow-copying either domain leaks nested writes.
    var unsafe: Dictionary = authority.duplicate()
    unsafe["construction_sites"] = authority["construction_sites"].duplicate()
    unsafe["construction_sites"]["old"]["materials"]["metals"] = -1
    assert(authority["construction_sites"]["old"]["materials"]["metals"] == -1,
        "negative fixture must demonstrate mutable alias")
    quit(0)
