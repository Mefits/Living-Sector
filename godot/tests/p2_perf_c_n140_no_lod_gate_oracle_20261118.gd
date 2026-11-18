extends SceneTree
## Independent N140 SourceLod oracle for the no-AgentLod hot path.
const Stage = preload("res://scripts/sim/phase2/unified_n140_ship_lod_phase.gd")
const SourceLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")

func _initialize() -> void:
    var ships: Dictionary = {}
    for i in range(100):
        ships["ship_%03d" % i] = {
            "id": "ship_%03d" % i, "location": "home",
            "transit": {}, "cargo": {"ore": i},
            "bt": {"memory": [i, {"nested": i}]}}
    var world: Dictionary = {"ships": ships, "ship_next_token": 101}
    var positions: Dictionary = {"home": Vector2(0, 0)}
    for tick in [1, 50, 100]:
        var result: Dictionary = Stage.stage(world, positions, tick, 1, [])
        assert(result.get("ok", false), "no-LOD stage rejected")
        var ids: Array = ships.keys()
        ids.sort()
        var agents: Dictionary = {}
        for sid in ids:
            agents[sid] = {}
        var recomputed: bool = SourceLod.should_recompute(tick, 1)
        if recomputed:
            var rec: Dictionary = SourceLod.recompute(agents, [], tick)
            assert(rec.get("ok", false))
            agents = rec["agents"]
            assert(result["stats"] == rec["stats"], "recompute stats changed")
        var oracle: Dictionary = SourceLod.ship_gate(agents, ids, tick)
        assert(oracle.get("ok", false))
        assert(result["fired"] == oracle["fires"], "source firing/order mismatch")
        assert(result["fired_count"] == 100 and result["skipped_count"] == 0)
        assert(result["recomputed"] == recomputed and not result["changed"])
        assert(result["ships"] == ships)
        result["ships"]["ship_000"]["bt"]["memory"][1]["nested"] = -1
        assert(ships["ship_000"]["bt"]["memory"][1]["nested"] == 0,
            "returned fleet aliases authoritative World")
    var bad: Dictionary = world.duplicate(true)
    bad["ships"]["ship_050"]["transit"] = null
    assert(not Stage.stage(bad, positions, 1, 1, []).get("ok", true),
        "malformed transit must fail, even on fast path")
    bad = world.duplicate(true)
    bad["ships"]["ship_050"]["lod"] = {"divisor": 2, "next_tick": 4}
    var mixed: Dictionary = Stage.stage(bad, positions, 1, 1, [])
    assert(mixed.get("ok", false), "mixed LOD must retain original gate")
    assert(not mixed["fired"].has("ship_050"), "sleeping LOD ship fired")
    print("PASS p2_perf_c_n140_no_lod_gate_oracle_20261118")
    quit()
