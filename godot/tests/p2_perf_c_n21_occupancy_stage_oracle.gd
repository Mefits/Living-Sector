extends SceneTree
## II-C N21: queued-facility subset must match legacy full roster and
## full ship occupancy, including stale IDs, missing docks and paid FIFO.
const Dock = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const Paid = preload("res://tests/p2_n21_fifo_paid_source_check.gd")

func _legacy_keys(world: Dictionary) -> Array:
    var keys: Array = world["facilities"].keys()
    keys.sort()
    var selected: Array = []
    for fid in keys:
        var fac: Dictionary = world["facilities"][fid]
        if not fac.get("dock_queue", []).is_empty():
            selected.append(str(fid))
    return selected

func _indexed_keys(world: Dictionary) -> Array:
    var selected: Array = []
    for fid in world["facilities"]:
        var fac: Variant = world["facilities"][fid]
        if fac is Dictionary and fac.get("dock_queue", []) is Array and (
                not fac.get("dock_queue", []).is_empty()):
            selected.append(str(fid))
    selected.sort()
    return selected

func _compare(world: Dictionary) -> void:
    var selected: Array = _indexed_keys(world)
    assert(selected == _legacy_keys(world))
    var indexed: Dictionary = {}
    for fid in selected:
        indexed[fid] = 0
    for ship in world["ships"].values():
        var dock: String = str(ship.get("docked_at", ""))
        if indexed.has(dock):
            indexed[dock] = int(indexed[dock]) + 1
    for fid in selected:
        assert(int(indexed[fid]) == Dock._occupants(world, fid))
        assert(Dock._fee(world, fid, "ship_001", indexed) ==
            Dock._fee(world, fid, "ship_001"))

func _initialize() -> void:
    var world: Dictionary = {"facilities": {}, "ships": {},
        "faction_relations": {}}
    for n in range(2000):
        world["facilities"]["dock_%04d" % n] = {
            "location": "sol", "faction": "a",
            "docking_capacity": 100, "condition": 0.8, "dock_queue": []}
    for n in range(500):
        world["ships"]["ship_%03d" % n] = {
            "location": "sol", "faction_id": "a", "credits": 1000,
            "docked_at": "dock_%04d" % (n % 37) if n % 3 == 0 else ""}
    world["facilities"]["dock_0011"]["dock_queue"] = ["ship_010"]
    world["facilities"]["dock_0003"]["dock_queue"] = ["ship_011"]
    world["facilities"]["dock_1500"]["dock_queue"] = ["ship_012"]
    _compare(world)
    # Changing the queue owner must rebuild the invocation-local roster.
    world["facilities"]["dock_0003"]["dock_queue"].clear()
    world["facilities"]["dock_1999"]["dock_queue"] = ["ship_013"]
    world["ships"]["ship_001"]["docked_at"] = "dock_1999"
    _compare(world)
    # Empty and stale physical occupancy are not a cached admission.
    for fid in _indexed_keys(world):
        world["facilities"][fid]["dock_queue"].clear()
    assert(_indexed_keys(world).is_empty())
    assert(Dock.advance(world, {}, 1).get("status") ==
        "SOURCE_N21_FIFO_EMPTY")
    # Real N9 paid transfer, oldest-head FIFO, insolvent/stale negatives,
    # repeated paid tick and snapshot boundary remain executable.
    var paid: Dictionary = Paid.run_checks()
    assert(paid.get("ok", false), str(paid))
    print("P2_PERF_C_N21_OCCUPANCY_STAGE_ORACLE_PASS")
    quit(0)
