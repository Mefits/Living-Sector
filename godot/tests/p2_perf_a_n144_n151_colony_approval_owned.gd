extends SceneTree
# Astra II-B: actual N39 approval stage vs former full-domain deep copy.
# This is a stage/alias oracle, NOT a complete colony tick or Schema fixture.
const N39 = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _fixture() -> Dictionary:
    return {
        "construction_sites": {
            "old": {"labor": {"workers": [1]}, "materials": {"ore": [2]}}},
        "construction_receipts": {
            "old": {"proof": {"history": [3]}}},
        "research_directors": {
            "alpha": {"strategic": {"goals": [4]}, "history": [5]},
            "beta": {"strategic": {"goals": [6]}, "history": [7]}},
        "markets": {"loc": {"stocks": {"ore": [8]}}},
        "ships": {"ship": {"cargo": {"ore": [9]}}},
        "faction_treasuries": {"alpha": 100, "beta": 200}
    }

func _oracle(world: Dictionary, director: String) -> Dictionary:
    var stage: Dictionary = world.duplicate(false)
    stage["construction_sites"] = world["construction_sites"].duplicate(true)
    stage["construction_receipts"] = world["construction_receipts"].duplicate(true)
    if not director.is_empty():
        stage["research_directors"] = world["research_directors"].duplicate(true)
    return stage

func _approval(stage: Dictionary, director: String, site_id: String) -> bool:
    var receipt_id: String = "n151_colony_approved:" + site_id
    # Same duplicate rejection boundary as the live N144/N151 paths.
    if stage["construction_sites"].has(site_id) or (
            stage["construction_receipts"].has(receipt_id)):
        return false
    stage["construction_sites"][site_id] = {
        "id": site_id, "materials": {"ore": [10]}}
    stage["construction_receipts"][receipt_id] = {
        "id": receipt_id, "proof": {"history": [11]}}
    if not director.is_empty():
        if not stage["research_directors"].has(director):
            return false
        stage["research_directors"][director]["strategic"] = {
            "goals": [12], "last_approved": site_id}
    return true

func _initialize() -> void:
    var world: Dictionary = _fixture()
    var original: Dictionary = world.duplicate(true)
    for director in ["alpha", ""]:
        var owned: Dictionary = N39._colony_approval_owned_stage(world, director)
        var oracle: Dictionary = _oracle(world, director)
        assert(_approval(owned, director, "new"))
        assert(_approval(oracle, director, "new"))
        assert(owned == oracle)
        assert(world == original)
        # A second approved colony is a distinct append, not a rewrite of
        # a previously published site or receipt.
        assert(_approval(owned, director, "new2"))
        assert(_approval(oracle, director, "new2"))
        assert(owned == oracle)
        assert(world == original)
        # Mutable newly created rows and the modified director are isolated.
        owned["construction_sites"]["new"]["materials"]["ore"].append(13)
        owned["construction_receipts"]["n151_colony_approved:new"]["proof"]["history"].append(14)
        if not director.is_empty():
            owned["research_directors"][director]["history"].append(15)
            owned["research_directors"][director]["strategic"]["goals"].append(16)
        assert(world == original)
        # No N9 or unrelated market/ship domain may change on approval.
        assert(owned["faction_treasuries"] == original["faction_treasuries"])
        assert(owned["markets"] == original["markets"])
        assert(owned["ships"] == original["ships"])
    # Negative duplicate after staging must not mutate authoritative World.
    var rejected: Dictionary = N39._colony_approval_owned_stage(world, "alpha")
    assert(not _approval(rejected, "alpha", "old"))
    assert(world == original)
    # Negative missing director after an append is a discarded stage.
    var missing: Dictionary = N39._colony_approval_owned_stage(world, "ghost")
    assert(not _approval(missing, "ghost", "new"))
    assert(world == original)
    # Simulate late full-Schema rejection after two staged writes: the
    # original root and its nested rows remain unchanged.
    var invalid: Dictionary = N39._colony_approval_owned_stage(world, "alpha")
    assert(_approval(invalid, "alpha", "new"))
    invalid["construction_sites"]["new"]["id"] = ""
    assert(invalid != original)
    assert(world == original)
    # The unchanged historical rows are deliberately shared read-only.
    # Only registry append and the selected director's memory may be written.
    var no_memory: Dictionary = N39._colony_approval_owned_stage(world)
    assert(no_memory["research_directors"] == world["research_directors"])
    assert(no_memory["construction_sites"] == world["construction_sites"])
    assert(no_memory["construction_receipts"] == world["construction_receipts"])
    assert(world == original)
    print("PASS p2_perf_a_n144_n151_colony_approval_owned")
    quit()
