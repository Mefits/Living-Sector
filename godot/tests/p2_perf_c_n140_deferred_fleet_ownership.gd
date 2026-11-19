extends SceneTree
## N140 deferred cursor staging: full legacy SourceLod oracle and negative
## preflight/ownership cases. Run with Godot --headless --script.
const Stage = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")
const SourceLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")

func _legacy(world: Dictionary, positions: Dictionary, observers: Array,
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
            if p is Array and p.size() == 2:
                entry["position"] = Vector2(float(p[0]), float(p[1]))
        else:
            var pos: Variant = positions.get(str(row.get("location", "")), null)
            if pos is Vector2:
                entry["position"] = pos
        agents[str(sid)] = entry
    var recomputed: bool = SourceLod.should_recompute(tick, multiplier)
    var stats: Dictionary = {}
    if recomputed:
        var rec: Dictionary = SourceLod.recompute(agents, observers, tick)
        assert(rec["ok"])
        agents = rec["agents"]
        stats = rec["stats"]
    var gate: Dictionary = SourceLod.ship_gate(agents, ids, tick)
    assert(gate["ok"])
    var out: Dictionary = world["ships"].duplicate(true)
    var changed: bool = false
    for sid in ids:
        if out[sid].has("lod"):
            var cursor: Dictionary = gate["agents"][str(sid)]["lod"]
            if out[sid]["lod"] != cursor:
                changed = true
            out[sid]["lod"] = cursor.duplicate(true)
    return {"ships": out, "changed": changed, "fired": gate["fires"],
        "fired_count": gate["fires"].size(),
        "skipped_count": ids.size() - gate["fires"].size(),
        "recomputed": recomputed, "stats": stats, "tick": tick}

func _initialize() -> void:
    var ships: Dictionary = {}
    for i in range(500):
        var sid: String = "s%04d" % i
        var row: Dictionary = {"id": sid, "location": "home",
            "transit": {}, "cargo": {"ore": [i, {"nested": [i]}]},
            "bt": {"stack": [{"step": i}]}, "memory": {"seen": [i]}}
        if i % 4 != 0:
            row["lod"] = {"divisor": [1, 2, 5, 10, 20, 50][i % 6],
                "next_tick": i % 19}
        if i % 9 == 0:
            row["transit"] = {"position": [float(i), float(i / 2)]}
        if i % 13 == 0:
            row["location"] = "unmapped"
        ships[sid] = row
    var world: Dictionary = {"ships": ships}
    var positions: Dictionary = {"home": Vector2(2, 3)}
    var observers: Array = [{"position": Vector2(0, 0), "radius": 7.0},
        {"position": Vector2(300, 0), "radius": 40.0}]
    var original: Dictionary = world.duplicate(true)
    for obs in [[], observers]:
        for tick in [1, 7, 49, 50, 51, 100, 150, 200]:
            for multiplier in [1, 2]:
                var actual: Dictionary = Stage.stage(world, positions, tick, multiplier, obs)
                var expected: Dictionary = _legacy(world, positions, obs, tick, multiplier)
                assert(actual.get("ok", false))
                for field in ["ships", "changed", "fired", "fired_count",
                        "skipped_count", "recomputed", "stats", "tick"]:
                    assert(actual[field] == expected[field],
                        "N140 deferred cursor mismatch: %s/%d/%d" % [field, tick, multiplier])
                actual["ships"]["s0001"]["cargo"]["ore"][1]["nested"][0] = -1
                actual["ships"]["s0002"]["bt"]["stack"][0]["step"] = -1
                actual["ships"]["s0003"]["memory"]["seen"][0] = -1
                assert(world == original, "stage leaked owned row to source World")
    # Late malformed row must fail without mutating any previously staged cursor.
    var bad: Dictionary = world.duplicate(true)
    bad["ships"]["s0499"]["lod"] = {"divisor": -1, "next_tick": 0}
    var before: Dictionary = bad.duplicate(true)
    assert(not Stage.stage(bad, positions, 50, 1, observers).get("ok", true))
    assert(bad == before, "failed cursor preflight mutated authoritative fleet")
    bad = world.duplicate(true)
    bad["ships"]["s0499"]["transit"] = null
    before = bad.duplicate(true)
    assert(not Stage.stage(bad, positions, 51, 1, observers).get("ok", true))
    assert(bad == before, "invalid transit changed authoritative fleet")
    # A sleeping LOD cursor remains byte-identical, with no fabricated fire.
    var sleeping: Dictionary = {"ships": {"idle": {"id": "idle",
        "location": "home", "transit": {},
        "lod": {"divisor": 50, "next_tick": 500},
        "cargo": {"ore": [1]}}}}
    var skipped: Dictionary = Stage.stage(sleeping, positions, 3, 1, [])
    assert(skipped.get("ok", false))
    assert(skipped["fired"].is_empty() and not skipped["changed"])
    assert(skipped["ships"]["idle"]["lod"] == sleeping["ships"]["idle"]["lod"])
    print("PASS p2_perf_c_n140_deferred_fleet_ownership")
    quit()
