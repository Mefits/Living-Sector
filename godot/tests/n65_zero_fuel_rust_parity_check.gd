extends SceneTree
## Frozen Rust 0.6.7 moves even when tank has reached zero;
## this MUST NOT be silently replaced by an "out_of_fuel" hard stop.
const NativeData = preload("res://scripts/native_data.gd")
const Live = preload("res://scripts/sim/live_native_fleet_engine.gd")
const Fuel = preload("res://scripts/sim/ships/native_fuel_diagnostics.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var live = Live.new()
    if not live.start_new_game(seed).get("ok", false):
        _fail("start")
        return
    var id: String = "@system-sol/0"
    var ship: Dictionary = live.runner._fleet.ships[id]
    ship["fuel"] = 0.0 # Explicit test state after 0.6.7 spending; not a native starting value.
    var before: Dictionary = Fuel.inspect(ship)
    if not before.get("ok", false) or before["state"] != "depleted_at_location":
        _fail("zero_fuel_diagnostic")
        return
    if not live.depart(id, "mine-near-earth").get("ok", false):
        _fail("reference_zero_fuel_departure")
        return
    var flight: Dictionary = ship["transit"]
    var start_position: Array = (flight["position"] as Array).duplicate()
    if not live.advance_one_native_tick():
        _fail("zero_fuel_tick")
        return
    var new_flight: Dictionary = ship["transit"]
    if new_flight.is_empty():
        if str(ship["location"]) != "mine-near-earth":
            _fail("wrong_arrival")
            return
    elif new_flight.get("position", []) == start_position:
        _fail("zero_fuel_froze_ship")
        return
    if not is_zero_approx(float(ship["fuel"])):
        _fail("fuel_minted")
        return
    var diagnostics: Dictionary = Fuel.snapshot(live.runner._fleet)
    if not diagnostics.get("ok", false) or diagnostics["ships"].size() != 24:
        _fail("fleet_fuel_snapshot")
        return
    var envelope: Dictionary = live.checkpoint()
    if not envelope.get("ok", false):
        _fail("checkpoint")
        return
    var restored = Live.new()
    if not restored.restore_complete(seed, JSON.parse_string(JSON.stringify(envelope))).get("ok", false):
        _fail("restore_zero_fuel_ship")
        return
    if float(restored.runner._fleet.ships[id]["fuel"]) != 0.0:
        _fail("refueled_on_restore")
        return
    print("N65_ZERO_FUEL_RUST_PARITY_PASS: zero fuel does not interrupt native flight")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N65_ZERO_FUEL_RUST_PARITY_FAIL " + reason)
    quit(1)
