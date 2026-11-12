extends SceneTree
## N46 CODE_UNVERIFIED: 24 actual frozen initial ship identities and genuine
## Rust seeder full-fuel/empty-cargo semantics. NO synthetic coordinates.
const NativeData = preload("res://scripts/native_data.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Bootstrap = preload("res://scripts/sim/ships/native_fleet_bootstrap.gd")
const Runner = preload("res://scripts/sim/ship_tick_runner.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed_loading")
        return
    var created: Dictionary = Bootstrap.build_new_game(seed)
    if not bool(created.get("ok", false)):
        _fail("bootstrap_" + str(created.get("error", "unknown")))
        return
    if int(created["ship_count"]) != 24:
        _fail("native_ship_count")
        return
    var fleet: RefCounted = created["fleet"]
    var initial_fuel: Dictionary = created["fuel_sources"]
    var initial_cargo: Dictionary = created["cargo_sources"]
    var initial_credits: Dictionary = created["credit_sources"]
    if fleet.ships.size() != 24 or initial_credits.size() != 24:
        _fail("native_fleet_size")
        return
    var classes: Dictionary = {}
    var total_credits: int = 0
    var total_fuel: float = 0.0
    var total_hold_capacity: int = 0
    var ids: Array = fleet.ships.keys()
    ids.sort()
    for id in ids:
        var ship: Dictionary = fleet.ships[id]
        var expected: Dictionary = Catalog.spec(str(ship["class"]))
        if expected.is_empty() or not (ship["cargo"] as Dictionary).is_empty():
            _fail("cargo_or_class")
            return
        if not is_equal_approx(float(ship["fuel"]), float(expected["fuel_capacity"])):
            _fail("initial_full_fuel")
            return
        if not is_equal_approx(float(initial_fuel[id]), float(ship["fuel"])) or initial_cargo[id] != ship["cargo"]:
            _fail("init_fuel_cargo_provenance")
            return
        if int(initial_credits[id]) != 40000:
            _fail("native_credits_source")
            return
        total_credits += int(initial_credits[id])
        total_fuel += float(ship["fuel"])
        total_hold_capacity += int(ship["cargo_capacity"])
        classes[str(ship["class"])] = int(classes.get(str(ship["class"]), 0)) + 1
    # Exact frozen Rust seeder totals for 3 equal eight-ship factions.
    if total_credits != 960000 or not is_equal_approx(total_fuel, 4200.0) or total_hold_capacity != 17250 or classes.size() != 6:
        _fail("native_economy_provenance")
        return
    if str(fleet.ships["@system-sol/0"]["location"]) != "earth-station":
        _fail("native_sol_ship")
        return
    var invalid_seed: Dictionary = seed.duplicate(true)
    var sol_idx: int = -1
    for i in range(invalid_seed["worlds"].size()):
        if str(invalid_seed["worlds"][i]["system"]["id"]) == "system-sol":
            sol_idx = i
            break
    if sol_idx < 0:
        _fail("missing_sol")
        return
    invalid_seed["worlds"][sol_idx]["ships"][0]["cargo"] = {"ore": 20}
    if bool(Bootstrap.build_new_game(invalid_seed).get("ok", false)):
        _fail("silently_treats_saved_ship_as_new")
        return
    invalid_seed = seed.duplicate(true)
    invalid_seed["worlds"][sol_idx]["ships"][0]["fitting"] = {"engines": "engines_t2"}
    if bool(Bootstrap.build_new_game(invalid_seed).get("ok", false)):
        _fail("unmodeled_engine_fitting_accepted")
        return
    invalid_seed = seed.duplicate(true)
    invalid_seed["worlds"][sol_idx]["ships"][0]["credits"] = -1
    if bool(Bootstrap.build_new_game(invalid_seed).get("ok", false)):
        _fail("negative_initial_credits")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed) or not runner.bootstrap_new_game_native_fleet(seed):
        _fail("runner_bootstrap")
        return
    if runner.live_fleet_snapshot().size() != 24 or runner.initial_ship_credit_sources().size() != 24:
        _fail("runner_fleet_credits")
        return
    if runner.bootstrap_new_game_native_fleet(seed):
        _fail("same_run_second_fleet_init")
        return
    if runner.implemented_phases() != PackedStringArray(["bodies", "ships"]):
        _fail("ship_phase_missing")
        return
    # Exact moving target from N43 coordinates. The ship must consume its
    # original fuel once, not gain fuel when bootstrap is attempted again.
    if not runner.depart_ship("@system-sol/0", "mine-near-earth"):
        _fail("native_route_departure")
        return
    runner._advance_one_tick()
    var after: Dictionary = runner._fleet.ships["@system-sol/0"]
    if float(after["fuel"]) >= float(Catalog.spec("miner")["fuel_capacity"]):
        _fail("ship_did_not_consume_fuel")
        return
    if runner.bootstrap_new_game_native_fleet(seed):
        _fail("inflight_refueled")
        return
    if not runner.checkpoint().is_empty():
        _fail("partial_fleet_save_accepted")
        return
    print("N46_NATIVE_FLEET_INITIALIZATION_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N46_NATIVE_FLEET_INITIALIZATION_FAIL " + reason)
    quit(1)
