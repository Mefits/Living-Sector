extends SceneTree
## Astra II-C: capture-local owner lookup must match naive global owner scan
## after every World mutation. No persistent cache or mutable World alias.
const Head = preload("res://scripts/sim/phase2/unified_native_hybrid_planning.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "faction_treasuries": {"alpha": 10000, "beta": 10000},
        "facilities": {}, "markets": {}, "ships": {},
        "populations": {}, "contract_board": {"contracts": {}},
        "research": {"alpha": [], "beta": []}
    }
    for i in range(80):
        var fid: String = "f-%03d" % i
        var loc: String = "l-%03d" % i
        world["facilities"][fid] = {
            "faction": "alpha" if i % 3 == 0 else "beta",
            "location": loc, "type": "mine"}
        world["markets"][loc] = {
            "owner": fid, "id": "m-%03d" % i,
            "supply": {"ore": i}, "demand": {"ore": i + 1},
            "prices": {"ore": 10.0}}
    _check(world)
    # Change owner, add a facility, remove one and move another.
    world["facilities"]["f-001"]["faction"] = "alpha"
    _check(world)
    world["facilities"]["new"] = {
        "faction": "alpha", "location": "l-new", "type": "farm"}
    world["markets"]["l-new"] = {"owner": "new", "id": "m-new",
        "supply": {"food": 8}, "demand": {}, "prices": {"food": 5.0}}
    _check(world)
    world["facilities"].erase("f-000")
    _check(world)
    world["facilities"]["f-003"]["location"] = "moved"
    var invalid: Dictionary = Head.capture(world, "alpha", 1)
    assert(not invalid.get("ok", false))
    assert(invalid.get("reason") == "n100_wrong_source_market_owner")
    world["markets"].erase("l-003")
    world["markets"]["moved"] = {"owner": "f-003", "id": "m-003",
        "supply": {"ore": 3}, "demand": {}, "prices": {"ore": 10.0}}
    _check(world)
    print("PASS p2_perf_d_head_capture_local_market_roster_20261118")
    quit(0)

func _check(world: Dictionary) -> void:
    var expected: Array = []
    var locs: Array = world["markets"].keys()
    locs.sort()
    for loc in locs:
        var m: Dictionary = world["markets"][loc]
        var owner: String = str(m.get("owner", ""))
        if world["facilities"].has(owner) and str(
                world["facilities"][owner].get("faction", "")) == "alpha":
            expected.append({"market_id": str(m.get("id", "")),
                "facility_id": owner, "location_id": str(loc),
                "stock": m["supply"].duplicate(true),
                "demand": m["demand"].duplicate(true),
                "prices": m["prices"].duplicate(true)})
    var result: Dictionary = Head.capture(world, "alpha", 1)
    assert(result.get("ok", false), "valid capture failed")
    assert(result["snapshot"]["owned_markets"] == expected,
        "owner lookup differs from original global sorted scan")
    if not expected.is_empty():
        result["snapshot"]["owned_markets"][0]["stock"]["ore"] = -999
        var first_loc: String = str(expected[0]["location_id"])
        assert(world["markets"][first_loc]["supply"] !=
            result["snapshot"]["owned_markets"][0]["stock"],
            "capture must not alias World supply")
