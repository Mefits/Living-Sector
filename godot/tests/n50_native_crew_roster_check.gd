extends SceneTree
## Source: frozen Rust sim_db/spawner.rs and ShipCrewSkills::for_roles.
const NativeData = preload("res://scripts/native_data.gd")
const Bootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const Crew = preload("res://scripts/sim/ships/native_crew_roster.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var built: Dictionary = Bootstrap.build_new_game(seed)
    if not bool(built.get("ok", false)):
        _fail("fresh_fleet")
        return
    var fleet: RefCounted = built["fleet"]
    var crew = Crew.new()
    if not crew.initialize_new_game(fleet):
        _fail("init")
        return
    if crew.initialize_new_game(fleet):
        _fail("double_init")
        return
    var records: Array = crew.snapshot()
    if records.size() != 24:
        _fail("roster_count")
        return
    var total: int = 0
    for record in records:
        total += int(record["size"])
        if not is_equal_approx(float(record["hunger"]), 10.0) or not is_equal_approx(float(record["fatigue"]), 10.0):
            _fail("needs_defaults")
            return
        if not is_equal_approx(float(record["morale"]), 70.0) or not is_equal_approx(float(record["health"]), 100.0):
            _fail("health_morale")
            return
        if int(record["wages_credits"]) != 0 or str(record["current_task"]) != "idle":
            _fail("wages_task")
            return
        if not is_equal_approx(crew.efficiency(str(record["ship_id"])), 0.88):
            _fail("efficiency")
            return
    if total != 123:
        _fail("total_aggregate_crew")
        return
    var miner: Dictionary = crew.crews["@system-sol/0"]
    if int(miner["size"]) != 3 or miner["skills"] != {
        "navigation": 40, "engineering": 40, "trading": 30, "combat": 20
    }:
        _fail("miner_roles_skills")
        return
    var hauler: Dictionary = crew.crews["@system-sol/4"]
    if int(hauler["size"]) != 8 or hauler["skills"] != {
        "navigation": 50, "engineering": 50, "trading": 40, "combat": 20
    }:
        _fail("hauler_roles_skills")
        return
    var saved: Array = crew.snapshot()
    saved[0]["morale"] = 30.0
    saved[0]["wages_credits"] = 47
    saved[0]["current_task"] = "resting"
    saved[0]["skills"]["navigation"] = 99
    var restored = Crew.new()
    if not restored.restore(saved, fleet):
        _fail("restore_valid")
        return
    var after: Array = restored.snapshot()
    if JSON.stringify(after) != JSON.stringify(saved):
        _fail("restore_refilled")
        return
    if restored.initialize_new_game(fleet):
        _fail("resume_reroll")
        return
    var tampered: Array = saved.duplicate(true)
    tampered[0]["wages_credits"] = -1
    var before: String = JSON.stringify(restored.snapshot())
    if restored.restore(tampered, fleet) or before != JSON.stringify(restored.snapshot()):
        _fail("atomic_wage_rejection")
        return
    tampered = saved.duplicate(true)
    tampered[0]["skills"]["engineering"] = 101
    if restored.restore(tampered, fleet) or before != JSON.stringify(restored.snapshot()):
        _fail("invalid_skill")
        return
    tampered = saved.duplicate(true)
    tampered[0]["roles"] = ["pilot"]
    if restored.restore(tampered, fleet) or before != JSON.stringify(restored.snapshot()):
        _fail("invalid_class_roles")
        return
    tampered = saved.duplicate(true)
    tampered.pop_back()
    if restored.restore(tampered, fleet) or before != JSON.stringify(restored.snapshot()):
        _fail("partial_roster")
        return
    print("N50_NATIVE_CREW_PASS: ships=24, crew=123, initialized once, restored atomically")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N50_NATIVE_CREW_FAIL " + reason)
    quit(1)
