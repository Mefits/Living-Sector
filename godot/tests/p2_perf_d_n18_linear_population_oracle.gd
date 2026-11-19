extends SceneTree
## N18 D oracle: exact original sorted population aggregation vs linear path.
const Phase = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")

func _initialize() -> void:
    var world: Dictionary = {"markets": {
        "earth": {"owner": "station-a"},
        "mars": {"owner": "station-b"},
        "invalid": {"owner": "missing"}},
        "facilities": {
            "station-a": {"type": "station", "faction": "alpha", "location": "earth"},
            "station-b": {"type": "station", "faction": "beta", "location": "mars"},
            "mine-a": {"type": "mine", "faction": "alpha", "location": "earth"},
            "mine-b": {"type": "mine", "faction": "beta", "location": "mars"}},
        "populations": {}}
    var occupied: Dictionary = {}
    for i in range(1500):
        var id: String = "pop-%04d" % (1499 - i)
        var faction: String = ["alpha", "beta", "outsider"][i % 3]
        var location: String = ["earth", "mars", "unused"][i % 3]
        world["populations"][id] = {"faction": faction,
            "location": location, "count": (i * 7) % 13}
        occupied[id] = i % 5
    _compare(world, occupied, "baseline")
    # Negative/edge cases: owner transfer, relocation, removed market,
    # missing station owner, and independent per-row workforce truncation.
    world["populations"]["pop-0000"]["faction"] = "beta"
    world["populations"]["pop-0000"]["location"] = "mars"
    world["facilities"]["mine-a"]["faction"] = "beta"
    world["facilities"]["mine-a"]["location"] = "mars"
    _compare(world, occupied, "transfer")
    world["markets"].erase("mars")
    _compare(world, occupied, "removed-market")
    world["markets"]["earth"]["owner"] = "missing"
    _compare(world, occupied, "invalid-owner")
    world["markets"]["earth"]["owner"] = "station-a"
    world["populations"]["extra"] = {"faction": "alpha",
        "location": "earth", "count": 1}
    _compare(world, occupied, "fractional-workforce")
    # Ensure neither returned map mutates the authoritative population rows.
    var original: Dictionary = world.duplicate(true)
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var keys: Dictionary = Phase._live_market_roster_keys(world)
    var actual: Dictionary = Phase._market_scoped_rosters(world, occupied, ids, keys)
    actual["populations"]["alpha|earth"]["people"] = -900
    assert(world == original, "N18 aggregate leaked World alias")
    print("PASS p2_perf_d_n18_linear_population_oracle")
    quit(0)

func _compare(world: Dictionary, occupied: Dictionary, label: String) -> void:
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var keys: Dictionary = Phase._live_market_roster_keys(world)
    var actual: Dictionary = Phase._market_scoped_rosters(world, occupied, ids, keys)
    var expected: Dictionary = _old_sorted_oracle(world, occupied, ids, keys)
    assert(actual == expected, "N18 population oracle mismatch: " + label)

func _old_sorted_oracle(world: Dictionary, occupied: Dictionary,
        facility_ids: Array, keys: Dictionary) -> Dictionary:
    var populations: Dictionary = {}
    var population_ids: Array = []
    for pop_id in world["populations"]:
        var candidate: Dictionary = world["populations"][pop_id]
        var key: String = str(candidate.get("faction", "")) + "|" + str(candidate.get("location", ""))
        if keys.has(key):
            population_ids.append(pop_id)
    population_ids.sort()
    for pop_id in population_ids:
        var pop: Dictionary = world["populations"][pop_id]
        var key: String = str(pop.get("faction", "")) + "|" + str(pop.get("location", ""))
        var people: int = maxi(0, int(pop.get("count", 0)))
        if not populations.has(key):
            populations[key] = {"people": 0, "workforce": 0, "occupied": 0}
        var totals: Dictionary = populations[key]
        totals["people"] = int(totals["people"]) + people
        totals["workforce"] = int(totals["workforce"]) + int(people * 3 / 5)
        totals["occupied"] = int(totals["occupied"]) + int(occupied.get(pop_id, 0))
    var facilities: Dictionary = {}
    for fid in facility_ids:
        var facility: Dictionary = world["facilities"][fid]
        var key: String = str(facility.get("faction", "")) + "|" + str(facility.get("location", ""))
        if not keys.has(key):
            continue
        if not facilities.has(key):
            facilities[key] = []
        facilities[key].append(fid)
    return {"populations": populations, "facilities": facilities}
