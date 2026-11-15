extends SceneTree
## N40 CODE_UNVERIFIED: real frozen Sol ship identity + explicit simulated
## authoritative initial fuel/hold/positions as TEST FIXTURES, not native facts.
const NativeData = preload("res://scripts/native_data.gd")
const Ships = preload("res://scripts/sim/ship_state.gd")
const Runner = preload("res://scripts/sim/ship_tick_runner.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")
var due_events: Array[String] = []

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native_seed")
        return
    var roster = Roster.new()
    if not roster.load_seed(seed) or not roster.keys().has("@system-sol/0"):
        _fail("native_idless_ship_roster")
        return
    var meta: Dictionary = roster.metadata("@system-sol/0")
    if meta.get("class") != "miner" or meta.get("location") != "earth-station":
        _fail("wrong_native_ship_identity")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("start")
        return
    if runner.implemented_phases() != PackedStringArray(["bodies"]):
        _fail("unconfigured_fleet_advertised")
        return
    var state = Ships.new()
    var id := "@system-sol/0"
    if not state.add_ship(id, "miner", "terran-authority", "system-sol"):
        _fail("ship_state")
        return
    state.ships[id]["location"] = "earth-station"
    if not state.set_fuel_from_authoritative_result(id, 12.0):
        _fail("fixture_fuel")
        return
    # Not native positional truth: local controlled fixtures ONLY.
    var positions := {"earth-station": Vector2.ZERO, "mine-near-earth": Vector2(0.2, 0.0)}
    if runner.configure_fleet(seed, state, positions, {}, {id: {}}):
        _fail("invented_fuel_was_accepted")
        return
    if runner.configure_fleet(seed, state, positions, {id: 12.0}, {}):
        _fail("invented_cargo_was_accepted")
        return
    if runner.configure_fleet(seed, state, {"earth-station": Vector2.ZERO, "mine-near-earth": Vector2(INF, 0)}, {id: 12.0}, {id: {}}):
        _fail("nonfinite_world_position")
        return
    if not runner.configure_fleet(seed, state, positions, {id: 12.0}, {id: {}}):
        _fail("explicit_fleet_not_accepted")
        return
    if runner.configure_fleet(seed, state, positions, {id: 12.0}, {id: {}}):
        _fail("double_configuration")
        return
    if runner.implemented_phases() != PackedStringArray(["bodies", "ships"]):
        _fail("ship_phase_missing")
        return
    if not runner.queue_control("speed", 16.0):
        _fail("speed")
        return
    runner.advance_frame(0.0)
    if runner.depart_ship(id, "pirate-outpost"):
        _fail("nonadjacent_teleport")
        return
    if not runner.depart_ship(id, "mine-near-earth"):
        _fail("depart")
        return
    if runner.depart_ship(id, "mine-near-earth"):
        _fail("double_depart")
        return
    var orbit_before: Dictionary = runner.world.orbital_snapshot()
    if not runner.schedule_event("e40", 2, "dock_queue", id, "test_event"):
        _fail("event_schedule")
        return
    runner.scheduled_event_due.connect(_on_event)
    runner._advance_one_tick()
    if runner.tick_count != 1 or state.ships[id]["location"] != "":
        _fail("first_tick")
        return
    if runner.last_ship_results().get(id) != "moving" or absf(float(state.ships[id]["fuel"]) - 11.92) > 0.0001:
        _fail("physical_fuel")
        return
    if runner.world.orbital_snapshot() == orbit_before:
        _fail("orbit_phase_lost")
        return
    var before_duplicate: String = JSON.stringify(state.snapshot())
    runner._advance_fleet(1, 2.0)
    if JSON.stringify(state.snapshot()) != before_duplicate:
        _fail("duplicate_ship_tick_mutated")
        return
    runner._advance_one_tick()
    if due_events != ["e40"] or state.ships[id]["location"] != "":
        _fail("event_phase_or_midflight_teleport")
        return
    runner._advance_one_tick()
    if state.ships[id]["location"] != "mine-near-earth" or not (state.ships[id]["transit"] as Dictionary).is_empty():
        _fail("arrival")
        return
    if not runner.checkpoint().is_empty() or runner.restore_checkpoint({}, seed):
        _fail("unsafe_orbital_only_save")
        return
    if runner.live_fleet_snapshot().size() != 1:
        _fail("fleet_visibility")
        return
    print("N40_SHIP_PHASE_STATIC_FIXTURE_PASS")
    quit(0)

func _on_event(event: Dictionary) -> void:
    due_events.append(str(event.get("id", "")))

func _fail(reason: String) -> void:
    push_error("N40_SHIP_PHASE_FAIL " + reason)
    quit(1)
