extends SceneTree
## Compare faction-only sorted roster against original global-sort/filter semantics.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 10000},
        "facilities": {}, "markets": {}, "ships": {},
        "populations": {}, "contract_board": {"contracts": {}},
        "research": {"alpha": []}
    }
    for i in range(180):
        var fid: String = "facility-%03d" % (179 - i)
        world["facilities"][fid] = {"faction": "alpha" if i % 7 == 0 else "beta",
            "location": "loc-%d" % i, "type": "mine"}
        var sid: String = "ship-%03d" % (179 - i)
        world["ships"][sid] = {"faction_id": "alpha" if i % 9 == 0 else "beta",
            "cargo": {"ore": i % 3}, "cargo_capacity": 10, "fuel": 12.0,
            "transit": {}, "location": "loc-%d" % i, "class": "miner"}
    _check(world)
    # Negative ownership transitions: both additions and removals must be
    # visible on the next capture; no stale per-faction roster is permitted.
    world["facilities"]["facility-001"]["faction"] = "alpha"
    world["ships"]["ship-001"]["faction_id"] = "alpha"
    _check(world)
    world["facilities"].erase("facility-001")
    world["ships"].erase("ship-001")
    _check(world)
    print("PASS p2_perf_d_head_owned_roster_oracle_20261117")
    quit(0)

func _check(world: Dictionary) -> void:
    var expected_facilities: Array = []
    var fids: Array = world["facilities"].keys()
    fids.sort()
    for fid in fids:
        if str(world["facilities"][fid].get("faction", "")) == "alpha":
            expected_facilities.append(str(fid))
    var expected_ships: Array = []
    var sids: Array = world["ships"].keys()
    sids.sort()
    for sid in sids:
        if str(world["ships"][sid].get("faction_id", "")) == "alpha":
            expected_ships.append(str(sid))
    var result: Dictionary = Head.capture(world, "alpha", 1)
    assert(result.get("ok", false), "capture must accept valid world")
    var got_facilities: Array = []
    for f in result["snapshot"]["facilities"]:
        got_facilities.append(f["facility_id"])
    var got_ships: Array = []
    for s in result["snapshot"]["ships"]:
        got_ships.append(s["ship_id"])
    assert(got_facilities == expected_facilities, "facility order/ownership changed")
    assert(got_ships == expected_ships, "ship order/ownership changed")
    # Snapshot cannot mutate authoritative World.
    if not result["snapshot"]["facilities"].is_empty():
        result["snapshot"]["facilities"][0]["facility_type"] = "tampered"
        assert(world["facilities"][expected_facilities[0]]["type"] == "mine")
