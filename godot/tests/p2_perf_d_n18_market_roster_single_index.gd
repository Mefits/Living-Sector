extends SceneTree
## Astra II-C: compare the due-cycle ordered-market reuse and selected-only
## population sort against the original full population sort oracle.
const Phase = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {"facilities": {}, "markets": {}, "populations": {}}
    for i in range(120):
        var fid: String = "f%03d" % i
        var loc: String = "loc%03d" % i
        world["facilities"][fid] = {"type": "station", "faction": "red" if i % 2 == 0 else "blue", "location": loc}
        if i % 6 == 0:
            world["markets"][loc] = {"owner": fid}
    for i in range(1200):
        var pid: String = "p%04d" % (1199 - i)
        world["populations"][pid] = {"faction": "red" if i % 2 == 0 else "blue",
            "location": "loc%03d" % (i % 120), "count": i % 17}
    _oracle(world)
    # Invalidate every due cycle, including changes to market membership,
    # faction, station type and population location. No cache survives.
    world["facilities"]["f000"]["faction"] = "blue"
    _oracle(world)
    world["facilities"]["f006"]["location"] = "loc090"
    _oracle(world)
    world["facilities"]["f012"]["type"] = "mine"
    _oracle(world)
    world["populations"]["p1199"]["location"] = "loc018"
    _oracle(world)
    world["markets"].erase("loc018")
    _oracle(world)
    world["markets"]["loc018"] = {"owner": "missing"}
    _oracle(world)
    # Negative owner: invalid markets cannot create a valid roster key.
    var keys: Dictionary = Phase._live_market_roster_keys(world)
    assert(not keys.has("red|loc018"))
    # Read-only results must not alias any source population or facility.
    var before: Dictionary = world.duplicate(true)
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var rosters: Dictionary = Phase._market_scoped_rosters(world, {}, ids, keys)
    for key in rosters["facilities"]:
        rosters["facilities"][key].append("bogus")
    assert(world == before)
    print("PASS p2_perf_d_n18_market_roster_single_index")
    quit(0)

func _oracle(world: Dictionary) -> void:
    var locations: Array = world["markets"].keys()
    locations.sort()
    var keys: Dictionary = Phase._live_market_roster_keys(world, locations)
    var legacy_keys: Dictionary = {}
    for loc in world["markets"]:
        var owner: String = str(world["markets"][loc].get("owner", ""))
        var station: Dictionary = world["facilities"].get(owner, {})
        if str(station.get("type", "")) != "station":
            continue
        var faction: String = str(station.get("faction", ""))
        if not faction.is_empty():
            legacy_keys[faction + "|" + str(loc)] = true
    assert(keys == legacy_keys)
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var actual: Dictionary = Phase._market_scoped_rosters(world, {}, ids, keys)
    var all_ids: Array = world["populations"].keys()
    all_ids.sort()
    var expected: Dictionary = {}
    for pid in all_ids:
        var pop: Dictionary = world["populations"][pid]
        var key: String = str(pop.get("faction", "")) + "|" + str(pop.get("location", ""))
        if not keys.has(key):
            continue
        if not expected.has(key):
            expected[key] = {"people": 0, "workforce": 0, "occupied": 0}
        var count: int = maxi(0, int(pop.get("count", 0)))
        expected[key]["people"] += count
        expected[key]["workforce"] += int(count * 3 / 5)
    assert(actual["populations"] == expected)
    var expected_facilities: Dictionary = {}
    for fid in ids:
        var f: Dictionary = world["facilities"][fid]
        var key: String = str(f.get("faction", "")) + "|" + str(f.get("location", ""))
        if keys.has(key):
            if not expected_facilities.has(key):
                expected_facilities[key] = []
            expected_facilities[key].append(fid)
    assert(actual["facilities"] == expected_facilities)
