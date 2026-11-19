extends SceneTree
## Independent N21 occupancy/fee oracle: cached counts must match the
## original full ship scan, including zero and stale dock ownership.
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "facilities": {
            "alpha": {"docking_capacity": 2, "condition": 0.8,
                "faction": "a", "location": "sol"},
            "beta": {"docking_capacity": 3, "condition": 1.0,
                "faction": "b", "location": "sol"}
        },
        "ships": {},
        "faction_relations": {}
    }
    for n in range(240):
        var id: String = "ship_%03d" % n
        world["ships"][id] = {
            "faction_id": "a", "docked_at": "alpha" if n % 4 == 0 else (
                "beta" if n % 7 == 0 else ""),
            "location": "sol", "credits": 100000
        }
    var counts: Dictionary = {}
    for ship in world["ships"].values():
        var fid: String = str(ship.get("docked_at", ""))
        if not fid.is_empty():
            counts[fid] = int(counts.get(fid, 0)) + 1
    for fid in ["alpha", "beta"]:
        assert(int(counts[fid]) == Dock._occupants(world, fid))
        for sid in ["ship_001", "ship_002", "ship_003"]:
            assert(Dock._fee(world, fid, sid) ==
                Dock._fee(world, fid, sid, counts))
    # A new physical dock must invalidate/update the local count.
    world["ships"]["ship_001"]["docked_at"] = "alpha"
    counts["alpha"] = int(counts["alpha"]) + 1
    assert(Dock._occupants(world, "alpha") == int(counts["alpha"]))
    assert(Dock._fee(world, "alpha", "ship_002") ==
        Dock._fee(world, "alpha", "ship_002", counts))
    # Unlisted facility must fall back to the original scan, not zero.
    assert(Dock._fee(world, "beta", "ship_002", {}) ==
        Dock._fee(world, "beta", "ship_002"))
    print("PASS p2_perf_c_n21_occupancy_fee_oracle")
    quit(0)
