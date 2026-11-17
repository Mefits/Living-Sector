extends SceneTree
## Oracle: global sorted market scan vs faction-only sorted scan, including owner changes.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 10000},
        "facilities": {}, "markets": {}, "ships": {},
        "populations": {}, "contract_board": {"contracts": {}},
        "research": {"alpha": []}
    }
    for i in range(240):
        var loc: String = "loc-%03d" % (239 - i)
        var fid: String = "facility-%03d" % i
        world["facilities"][fid] = {"faction": "alpha" if i % 11 == 0 else "beta",
            "location": loc, "type": "mine"}
        world["markets"][loc] = {"id": "market-%03d" % i, "owner": fid,
            "supply": {"ore": i}, "demand": {"ore": 2}, "prices": {"ore": 5}}
    _check(world)
    world["facilities"]["facility-001"]["faction"] = "alpha"
    _check(world)
    world["facilities"]["facility-000"]["faction"] = "beta"
    _check(world)
    world["facilities"].erase("facility-001")
    _check(world)
    # Wrong-location owner must still be rejected, not silently skipped.
    world["facilities"]["facility-011"]["faction"] = "alpha"
    world["facilities"]["facility-011"]["location"] = "wrong-location"
    var invalid: Dictionary = Head.capture(world, "alpha", 1)
    assert(not invalid.get("ok", true))
    assert(invalid.get("reason", "") == "n100_wrong_source_market_owner")
    print("PASS p2_perf_d_head_market_subset_oracle_20261117")
    quit(0)

func _check(world: Dictionary) -> void:
    var expected: Array = []
    var locations: Array = world["markets"].keys()
    locations.sort()
    for loc in locations:
        var m: Dictionary = world["markets"][loc]
        var owner: String = str(m.get("owner", ""))
        if world["facilities"].has(owner) and str(
                world["facilities"][owner].get("faction", "")) == "alpha":
            expected.append({"market_id": m["id"], "facility_id": owner,
                "location_id": loc, "stock": m["supply"],
                "demand": m["demand"], "prices": m["prices"]})
    var result: Dictionary = Head.capture(world, "alpha", 1)
    assert(result.get("ok", false), "valid capture rejected")
    assert(result["snapshot"]["owned_markets"] == expected,
        "global-sort oracle differs from owned-subset sorting")
    if not expected.is_empty():
        result["snapshot"]["owned_markets"][0]["stock"]["ore"] = -100
        assert(world["markets"][expected[0]["location_id"]]["supply"]["ore"] >= 0,
            "snapshot must not alias World")
