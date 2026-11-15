extends SceneTree
## Frozen Rust DB seeder creates ships at location_name, NOT docked_at.
## N53 requires an explicit N21 RequestDock before occupancy.
const NativeData = preload("res://scripts/native_data.gd")
const FleetBootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const DockBootstrap = preload("res://scripts/sim/ships/native_dock_bootstrap.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var initial: Dictionary = FleetBootstrap.build_new_game(seed)
    if not bool(initial.get("ok", false)):
        _fail("fresh_fleet")
        return
    var fleet: RefCounted = initial["fleet"]
    var before_fleet: String = JSON.stringify(fleet.snapshot())
    var built: Dictionary = DockBootstrap.build_new_game(seed, fleet)
    if not bool(built.get("ok", false)):
        _fail("native_docking")
        return
    if int(built["ships"]) != 24 or int(built["facilities"]) != 15 or int(built["total_slots"]) != 60:
        _fail("source_capacity_counts")
        return
    var d: RefCounted = built["registry"]
    var snap: Dictionary = d.snapshot()
    for ship in snap["ships"].values():
        if not str(ship["docked_at"]).is_empty() or bool(ship["in_transit"]):
            _fail("phantom_docked_at")
            return
    for members in snap["occupants"].values():
        if not (members as Array).is_empty():
            _fail("phantom_dock_occupancy")
            return
    var id: String = "@system-sol/0"
    var first: Dictionary = d.request_dock(id, "n53:request-1", "station")
    if not bool(first.get("ok", false)) or str(first.get("facility_id", "")) != "facility-earth-station":
        _fail("explicit_dock")
        return
    if d.request_dock(id, "n53:request-1", "station") != first:
        _fail("replay_receipt")
        return
    if d.begin_transit(id):
        _fail("docked_ship_departed_without_undock")
        return
    var after: Dictionary = d.snapshot()
    if (after["occupants"]["facility-earth-station"] as Array).size() != 1:
        _fail("double_occupied_on_replay")
        return
    if not bool(d.undock(id, "n53:undock-1").get("ok", false)):
        _fail("undock")
        return
    if not d.begin_transit(id):
        _fail("depart_after_undock")
        return
    if d.request_dock(id, "n53:request-2").get("ok", false):
        _fail("docked_during_transit")
        return
    if JSON.stringify(fleet.snapshot()) != before_fleet:
        _fail("bootstrap_mutated_source_fleet")
        return
    var altered: Dictionary = seed.duplicate(true)
    var sol_index: int = -1
    for i in range((altered["worlds"] as Array).size()):
        if str(altered["worlds"][i]["system"]["id"]) == "system-sol":
            sol_index = i
            break
    if sol_index < 0:
        _fail("missing_sol")
        return
    altered["worlds"][sol_index]["ships"][0]["docked_at"] = "facility-earth-station"
    if DockBootstrap.build_new_game(altered, fleet).get("ok", false):
        _fail("saved_dock_claim_accepted_as_fresh")
        return
    if JSON.stringify(fleet.snapshot()) != before_fleet:
        _fail("rejected_bootstrap_mutated_fleet")
        return
    print("N53_NATIVE_DOCK_PASS: ships=24, facilities=15, capacity=60, no phantom docks")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N53_NATIVE_DOCK_FAIL " + reason)
    quit(1)
