extends RefCounted
## Deterministic oracle for per-cycle station rosters; no paid simulation is mocked.
## Run with Godot 4.7.2; not yet executed in this environment.

static func run() -> Dictionary:
    var world: Dictionary = {"facilities": {}, "populations": {}}
    for i in range(180):
        var id: String = "facility_%03d" % i
        world["facilities"][id] = {"faction": "a" if i % 3 == 0 else "b",
            "location": "earth" if i % 2 == 0 else "mars"}
    for i in range(240):
        var id: String = "population_%03d" % i
        world["populations"][id] = {"faction": "a" if i % 3 == 0 else "b",
            "location": "earth" if i % 2 == 0 else "mars", "count": i}
    for step in range(8):
        var rosters: Dictionary = _build(world)
        for faction in ["a", "b"]:
            for location in ["earth", "mars"]:
                var key: String = faction + "|" + location
                for domain in ["facilities", "populations"]:
                    var indexed: Array = rosters[domain].get(key, [])
                    var naive: Array = []
                    var ids: Array = world[domain].keys()
                    ids.sort()
                    for id in ids:
                        var record: Dictionary = world[domain][id]
                        if str(record.get("faction", "")) == faction and str(record.get("location", "")) == location:
                            naive.append(id)
                    if indexed != naive:
                        return {"ok": false, "reason": "roster_mismatch", "step": step,
                            "domain": domain, "key": key}
        # Move, transfer, delete and install between complete proposal cycles.
        world["facilities"]["facility_000"]["location"] = "mars" if step % 2 == 0 else "earth"
        world["facilities"]["facility_001"]["faction"] = "a" if step % 2 == 0 else "b"
        world["populations"]["population_000"]["location"] = "mars" if step % 2 == 0 else "earth"
        world["populations"]["population_001"]["faction"] = "a" if step % 2 == 0 else "b"
        world["facilities"].erase("facility_002")
        world["populations"].erase("population_002")
        world["facilities"]["new_%d" % step] = {"faction": "a", "location": "earth"}
        world["populations"]["new_%d" % step] = {"faction": "b", "location": "mars", "count": 5}
    return {"ok": true, "cycles": 8}

static func _build(world: Dictionary) -> Dictionary:
    var result: Dictionary = {"facilities": {}, "populations": {}}
    for domain in ["facilities", "populations"]:
        var ids: Array = world[domain].keys()
        ids.sort()
        for id in ids:
            var record: Dictionary = world[domain][id]
            var key: String = str(record.get("faction", "")) + "|" + str(record.get("location", ""))
            if not result[domain].has(key):
                result[domain][key] = []
            result[domain][key].append(id)
    return result
