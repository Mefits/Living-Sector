extends SceneTree
## Independent original SourceLod recompute + ship_gate oracle for mixed N140.
const Stage = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")
const SourceLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")

func _oracle(world: Dictionary, positions: Dictionary, observers: Array,
        tick: int, multiplier: int) -> Dictionary:
    var ids: Array = world["ships"].keys()
    ids.sort()
    var agents: Dictionary = {}
    for sid in ids:
        var row: Dictionary = world["ships"][sid]
        var entry: Dictionary = {}
        if row.has("lod"):
            entry["lod"] = row["lod"].duplicate(true)
        var transit: Dictionary = row["transit"]
        if not transit.is_empty():
            var p: Variant = transit.get("position", null)
            if p is Array and p.size() == 2 and (p[0] is int or p[0] is float) and (p[1] is int or p[1] is float) and is_finite(float(p[0])) and is_finite(float(p[1])):
                entry["position"] = Vector2(float(p[0]), float(p[1]))
        else:
            var pos: Variant = positions.get(str(row.get("location", "")), null)
            if pos is Vector2 and is_finite(pos.x) and is_finite(pos.y):
                entry["position"] = pos
        agents[str(sid)] = entry
    var recomputed: bool = SourceLod.should_recompute(tick, multiplier)
    var stats: Dictionary = {}
    if recomputed:
        var rec: Dictionary = SourceLod.recompute(agents, observers, tick)
        assert(rec.get("ok", false))
        agents = rec["agents"]
        stats = rec["stats"]
    var gate: Dictionary = SourceLod.ship_gate(agents, ids, tick)
    assert(gate.get("ok", false))
    var out: Dictionary = world["ships"].duplicate(true)
    var changed: bool = false
    for sid in ids:
        if out[sid].has("lod"):
            var old_lod: Dictionary = out[sid]["lod"]
            var new_lod: Dictionary = gate["agents"][str(sid)]["lod"]
            if old_lod != new_lod:
                changed = true
            out[sid]["lod"] = new_lod.duplicate(true)
    return {"ships": out, "changed": changed, "fired": gate["fires"],
        "fired_count": gate["fires"].size(),
        "skipped_count": ids.size() - gate["fires"].size(),
        "recomputed": recomputed, "stats": stats, "tick": tick}

func _initialize() -> void:
    var ships: Dictionary = {}
    for i in range(120):
        var sid: String = "ship_%03d" % i
        var ship: Dictionary = {"id": sid, "location": "home",
            "transit": {}, "cargo": {"ore": i, "nested": [i]},
            "bt": {"memory": [{"counter": i}]}}
        if i % 3 != 0:
            ship["lod"] = {"divisor": [1, 2, 5, 10][i % 4],
                "next_tick": i % 7}
        if i % 5 == 0:
            ship["transit"] = {"position": [float(i * 4), float(i * 2)],
                "route": ["home", "far"]}
        if i % 11 == 0:
            ship["location"] = "unknown" # no position: keep divisor
        ships[sid] = ship
    var world: Dictionary = {"ships": ships}
    var positions: Dictionary = {"home": Vector2(1, 2)}
    var observers: Array = [
        {"position": Vector2(0, 0), "radius": 5.0},
        {"position": Vector2(500, 0), "radius": 50.0}]
    for obs in [[], observers]:
        for tick in [1, 2, 7, 50, 100, 150]:
            for multiplier in [1, 2]:
                var actual: Dictionary = Stage.stage(world, positions, tick, multiplier, obs)
                assert(actual.get("ok", false), "optimized mixed gate rejected")
                var expected: Dictionary = _oracle(world, positions, obs, tick, multiplier)
                for field in ["ships", "changed", "fired", "fired_count",
                        "skipped_count", "recomputed", "stats", "tick"]:
                    assert(actual[field] == expected[field],
                        "N140 mismatch: %s tick %d multiplier %d" % [field, tick, multiplier])
                actual["ships"]["ship_001"]["bt"]["memory"][0]["counter"] = -1
                actual["ships"]["ship_002"]["lod"]["next_tick"] = -1
                assert(world["ships"]["ship_001"]["bt"]["memory"][0]["counter"] == 1,
                    "owned fleet aliases BT")
                assert(world["ships"]["ship_002"]["lod"]["next_tick"] >= 0,
                    "owned fleet aliases cursor")
    var bad: Dictionary = world.duplicate(true)
    bad["ships"]["ship_001"]["lod"] = {"divisor": -1, "next_tick": 0}
    assert(not Stage.stage(bad, positions, 50, 1, observers).get("ok", true),
        "bad LOD must reject")
    bad = world.duplicate(true)
    bad["ships"]["ship_001"]["transit"] = null
    assert(not Stage.stage(bad, positions, 1, 1, observers).get("ok", true),
        "invalid transit must reject")
    bad = world.duplicate(true)
    bad["ships"]["ship_001"]["lod"] = null
    assert(not Stage.stage(bad, positions, 1, 1, observers).get("ok", true),
        "null LOD must reject")
    print("PASS p2_perf_c_n140_mixed_owned_gate_oracle_20261118")
    quit()
