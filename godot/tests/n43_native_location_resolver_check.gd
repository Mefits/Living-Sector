extends SceneTree
## N43 CODE_UNVERIFIED: frozen JSON geometry and moving destination smoke.
## Fuel/hold used for active flight are explicit TEST fixtures, not native seed.
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const Locations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Ships = preload("res://scripts/sim/ship_state.gd")
const ShipRunner = preload("res://scripts/sim/ship_tick_runner.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native_seed")
        return
    var model = WorldModel.new()
    var resolver = Locations.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("load_frozen_seed")
        return
    if Locations.initial_facility_angle("earth-station") != 106:
        _fail("Rust_FNV_1a_phase")
        return
    var initial: Dictionary = resolver.positions_from_world(model, 0.0)
    if not bool(initial.get("ok", false)):
        _fail("initial_positions")
        return
    var coords: Dictionary = initial["positions"]
    if not coords.has("earth-station") or not coords.has("mine-near-earth"):
        _fail("Sol_route_coordinates")
        return
    if coords.has("unknown-route-only-without-body"):
        _fail("fabricated_route_coordinate")
        return
    # Earth at x=2, y=0 on frozen Sol seed; station orbit radius = .55.
    var earth_at_seed: Vector2 = Vector2(2.0, 0.0)
    if absf(coords["earth-station"].distance_to(earth_at_seed) - 0.55) > 0.0001:
        _fail("station_orbit_radius")
        return
    # Nav site must be at its actual body center, not route.distance=12.
    var near_earth_center := Vector2(2.4 * cos(deg_to_rad(300.0)),
        2.4 * sin(deg_to_rad(300.0)))
    if coords["mine-near-earth"].distance_to(near_earth_center) > 0.0001:
        _fail("nav_at_body_center")
        return
    if resolver.positions_from_world(model, 0.0, false).get("ok", false):
        _fail("unknown_historic_clock_origin")
        return
    if resolver.positions_from_world(model, NAN).get("ok", false):
        _fail("nan_elapsed_native_time")
        return
    var corrupt: Dictionary = seed.duplicate(true)
    for world in corrupt["worlds"]:
        if world["system"]["id"] == "system-sol":
            world["nav_sites"].append({"name": "earth-station", "body": "mars"})
            break
    var bad_resolver = Locations.new()
    if bad_resolver.load_seed(corrupt):
        _fail("ambiguous_location_not_rejected")
        return
    # Position changes depend on native orbit progression, not wall clock.
    model.advance_orbits(1.0)
    var evolved: Dictionary = resolver.positions_from_world(model, 1.0)
    if not bool(evolved.get("ok", false)):
        _fail("advanced_positions")
        return
    if evolved["positions"]["earth-station"].distance_to(coords["earth-station"]) <= 0.00001:
        _fail("station_moving_target_static")
        return
    if evolved["positions"]["mine-near-earth"].distance_to(coords["mine-near-earth"]) <= 0.00001:
        _fail("mining_body_orbit_static")
        return
    var flight = ShipRunner.new()
    if not flight.start_from_seed(seed):
        _fail("ship_runner_seed")
        return
    var state = Ships.new()
    var id: String = "@system-sol/0"
    if not state.add_ship(id, "miner", "terran-authority", "system-sol"):
        _fail("native_miner_identity")
        return
    state.ships[id]["location"] = "earth-station"
    if not state.set_fuel_from_authoritative_result(id, 12.0):
        _fail("test_fixture_fuel")
        return
    if flight.configure_fleet_from_native(seed, state, {}, {id: {}}):
        _fail("missing_fuel_provenance")
        return
    if not flight.configure_fleet_from_native(seed, state, {id: 12.0}, {id: {}}):
        _fail("native_geometry_binding")
        return
    if flight.implemented_phases() != PackedStringArray(["bodies", "ships"]):
        _fail("ships_phase_not_active")
        return
    var initial_target: Vector2 = flight.native_positions_snapshot()["mine-near-earth"]
    if flight.depart_ship(id, "unknown-destination"):
        _fail("unknown_destination_departed")
        return
    if not flight.depart_ship(id, "mine-near-earth"):
        _fail("native_route_departure")
        return
    if not flight.queue_control("speed", 16.0):
        _fail("speed_control")
        return
    flight.advance_frame(0.0)
    flight._advance_one_tick()
    if flight.tick_count != 1 or str(flight.last_ship_results().get(id, "")) != "moving":
        _fail("real_ship_tick")
        return
    var moved_target: Vector2 = flight.native_positions_snapshot()["mine-near-earth"]
    if moved_target.distance_to(initial_target) <= 0.00001:
        _fail("ship_target_was_stale")
        return
    if float(state.ships[id]["fuel"]) >= 12.0 or float(state.ships[id]["fuel"]) < 0.0:
        _fail("fuel_not_consumed")
        return
    if not flight.checkpoint().is_empty():
        _fail("unsaved_fleet_checkpoint_allowed")
        return
    print("N43_NATIVE_LOCATION_PASS: FNV station, moving body/nav, provenance, ship tick")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N43_NATIVE_LOCATION_FAIL " + reason)
    quit(1)
