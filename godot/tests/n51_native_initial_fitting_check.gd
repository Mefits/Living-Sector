extends SceneTree
## Frozen Rust modules/mod.rs + ShipFitting::new_for_size() parity.
const NativeData = preload("res://scripts/native_data.gd")
const Bootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const Fitting = preload("res://scripts/sim/ships/native_initial_fitting.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var boot: Dictionary = Bootstrap.build_new_game(seed)
    if not bool(boot.get("ok", false)):
        _fail("bootstrap")
        return
    var fleet: RefCounted = boot["fleet"]
    var result: Dictionary = Fitting.project_native_seed(seed, fleet)
    if not bool(result.get("ok", false)) or int(result.get("ship_count", -1)) != 24:
        _fail("native_fittings")
        return
    var records: Dictionary = result["records"]
    var t2_sensors: int = 0
    for id in records:
        var record: Dictionary = records[id]
        var slots: Dictionary = record["slots"]
        var effects: Dictionary = record["effects"]
        if str(slots["comms"]) != "comms_t2" or not is_equal_approx(float(effects["comms_bonus"]), 0.05):
            _fail("comms_t2")
            return
        if int(effects["power_cap"]) != 10 or not bool(effects["power_ok"]):
            _fail("reactor_budget")
            return
        if str(slots["sensors"]) == "sensors_t2":
            t2_sensors += 1
            if not is_equal_approx(float(effects["sensor_range_au"]), 2.0) or int(effects["power_use"]) != 6:
                _fail("sensor_t2_stats")
                return
        else:
            if str(slots["sensors"]) != "sensors_t1" or not is_equal_approx(float(effects["sensor_range_au"]), 1.0) or int(effects["power_use"]) != 5:
                _fail("sensor_t1_stats")
                return
        if not is_equal_approx(float(effects["speed_mult"]), 1.0) or not is_equal_approx(float(effects["cargo_mult"]), 1.0):
            _fail("unexpected_default_fitting_stat")
            return
    if t2_sensors != 3:
        _fail("huge_sensors_count")
        return
    var tanker: Dictionary = records["@system-sol/5"]
    if str(tanker["rust_ship_id"]) != "ship-terran-authority-tanker-6" or str(tanker["slots"]["sensors"]) != "sensors_t1":
        _fail("rust_tanker_id_hash")
        return
    var hauler: Dictionary = records["@system-sol/4"]
    if str(hauler["slots"]["sensors"]) != "sensors_t2" or not is_equal_approx(float(hauler["native_effective_speed"]), 0.48):
        _fail("huge_hauler_size")
        return
    var invalid: Dictionary = seed.duplicate(true)
    var sol_index: int = -1
    for i in range((invalid["worlds"] as Array).size()):
        if str(invalid["worlds"][i]["system"]["id"]) == "system-sol":
            sol_index = i
            break
    if sol_index < 0:
        _fail("sol_index")
        return
    invalid["worlds"][sol_index]["ships"][0]["fitting"] = {"engine": "engine_t2"}
    if bool(Fitting.project_native_seed(invalid, fleet).get("ok", false)):
        _fail("missing_engine_stat_application")
        return
    invalid = seed.duplicate(true)
    invalid["worlds"][sol_index]["ships"][0]["fitting"] = {"sensors": "comms_t2"}
    if bool(Fitting.project_native_seed(invalid, fleet).get("ok", false)):
        _fail("invalid_module_in_wrong_slot")
        return
    var again: Dictionary = Fitting.project_native_seed(seed, fleet)
    if JSON.stringify(again.get("records", {})) != JSON.stringify(records):
        _fail("not_deterministic")
        return
    print("N51_INITIAL_FITTING_PASS: 24 ships, 3 Huge sensor-t2, comms-t2, no phantom speed")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N51_INITIAL_FITTING_FAIL " + reason)
    quit(1)
