extends RefCounted
## N18 per-cycle population aggregate vs the original sorted per-market scan.
## This test is independent of N39 and never changes the authoritative World.

static func run() -> Dictionary:
    var world: Dictionary = {"populations": {}}
    var occupied: Dictionary = {}
    for i in range(360):
        var id: String = "pop_%04d" % i
        world["populations"][id] = {
            "faction": "f" + str(i % 4), "location": "loc" + str(i % 7),
            "count": i % 13 - 2}
        occupied[id] = i % 5
    for cycle in range(12):
        var cached: Dictionary = _aggregate(world, occupied)
        for faction in range(4):
            for location in range(7):
                var key: String = "f" + str(faction) + "|loc" + str(location)
                var expected: Dictionary = _naive(world, occupied,
                    "f" + str(faction), "loc" + str(location))
                if cached.get(key, {"people": 0, "workforce": 0,
                        "occupied": 0}) != expected:
                    return {"ok": false, "cycle": cycle, "key": key,
                        "expected": expected, "actual": cached.get(key, {})}
        world["populations"]["pop_0000"]["location"] = "loc" + str(cycle % 7)
        world["populations"]["pop_0001"]["faction"] = "f" + str(cycle % 4)
        world["populations"].erase("pop_0002")
        occupied.erase("pop_0002")
        var added: String = "new_%d" % cycle
        world["populations"][added] = {"faction": "f1",
            "location": "loc3", "count": cycle - 3}
        occupied[added] = cycle % 4
    return {"ok": true, "cycles": 12}

static func _aggregate(world: Dictionary, occupied: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    var ids: Array = world["populations"].keys()
    ids.sort()
    for id in ids:
        var p: Dictionary = world["populations"][id]
        var key: String = str(p.get("faction", "")) + "|" + str(p.get("location", ""))
        var people: int = maxi(0, int(p.get("count", 0)))
        if not result.has(key):
            result[key] = {"people": 0, "workforce": 0, "occupied": 0}
        var row: Dictionary = result[key]
        row["people"] = int(row["people"]) + people
        row["workforce"] = int(row["workforce"]) + int(people * 3 / 5)
        row["occupied"] = int(row["occupied"]) + int(occupied.get(id, 0))
    return result

static func _naive(world: Dictionary, occupied: Dictionary,
        faction: String, location: String) -> Dictionary:
    var result: Dictionary = {"people": 0, "workforce": 0, "occupied": 0}
    var ids: Array = world["populations"].keys()
    ids.sort()
    for id in ids:
        var p: Dictionary = world["populations"][id]
        if str(p.get("faction", "")) != faction or str(p.get("location", "")) != location:
            continue
        var people: int = maxi(0, int(p.get("count", 0)))
        result["people"] += people
        result["workforce"] += int(people * 3 / 5)
        result["occupied"] += int(occupied.get(id, 0))
    return result
