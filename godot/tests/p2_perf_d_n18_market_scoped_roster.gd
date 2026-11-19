extends SceneTree
## Astra II-C D: oracle for market-scoped N18 due-cycle rosters.
const Phase = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {
            "a": {"faction": "red", "location": "earth", "type": "station"},
            "b": {"faction": "red", "location": "earth", "type": "mine"},
            "c": {"faction": "blue", "location": "mars", "type": "station"},
            "d": {"faction": "red", "location": "void", "type": "mine"}},
        "markets": {
            "earth": {"owner": "a"}, "mars": {"owner": "c"}},
        "populations": {
            "p3": {"faction": "red", "location": "void", "count": 100},
            "p2": {"faction": "red", "location": "earth", "count": 3},
            "p1": {"faction": "red", "location": "earth", "count": 2},
            "p4": {"faction": "blue", "location": "mars", "count": 5}}}
    var occupied: Dictionary = {"p1": 1, "p2": 2, "p3": 50, "p4": 1}
    _check(world, occupied)
    # A relocated facility must disappear from the old market immediately.
    world["facilities"]["b"]["location"] = "mars"
    _check(world, occupied)
    # An ownership transfer changes which market is eligible.
    world["facilities"]["a"]["faction"] = "blue"
    _check(world, occupied)
    # Market removal and installation invalidate the scoped keys.
    world["markets"].erase("mars")
    _check(world, occupied)
    world["markets"]["void"] = {"owner": "d"}
    _check(world, occupied)
    # Negative: malformed/missing market owner is not silently accepted.
    # The scope builder must not invent an eligible key; propose() retains
    # the canonical n18_missing_real_station_market_owner failure.
    world["markets"]["bad"] = {"owner": "missing"}
    var keys: Dictionary = Phase._live_market_roster_keys(world)
    assert(not keys.has("red|bad"))
    world["markets"]["bad"] = {"owner": "b"}
    keys = Phase._live_market_roster_keys(world)
    assert(not keys.has("red|bad"))
    print("PASS p2_perf_d_n18_market_scoped_roster")
    quit(0)

func _check(world: Dictionary, occupied: Dictionary) -> void:
    var keys: Dictionary = Phase._live_market_roster_keys(world)
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var actual: Dictionary = Phase._market_scoped_rosters(world, occupied, ids, keys)
    var naive_pops: Dictionary = {}
    var pids: Array = world["populations"].keys()
    pids.sort()
    for pid in pids:
        var p: Dictionary = world["populations"][pid]
        var key: String = str(p.get("faction", "")) + "|" + str(p.get("location", ""))
        if not naive_pops.has(key):
            naive_pops[key] = {"people": 0, "workforce": 0, "occupied": 0}
        var n: int = maxi(0, int(p.get("count", 0)))
        naive_pops[key]["people"] += n
        naive_pops[key]["workforce"] += int(n * 3 / 5)
        naive_pops[key]["occupied"] += int(occupied.get(pid, 0))
    var naive_facilities: Dictionary = {}
    for fid in ids:
        var f: Dictionary = world["facilities"][fid]
        var key: String = str(f.get("faction", "")) + "|" + str(f.get("location", ""))
        if not naive_facilities.has(key):
            naive_facilities[key] = []
        naive_facilities[key].append(fid)
    for key in keys:
        assert(actual["populations"].get(key, {}) == naive_pops.get(key, {}))
        assert(actual["facilities"].get(key, []) == naive_facilities.get(key, []))
    for key in actual["populations"]:
        assert(keys.has(key))
    for key in actual["facilities"]:
        assert(keys.has(key))
    # No mutable alias to the authoritative World.
    var prior: Dictionary = world.duplicate(true)
    for key in actual["facilities"]:
        actual["facilities"][key].append("fake")
    assert(world == prior)
