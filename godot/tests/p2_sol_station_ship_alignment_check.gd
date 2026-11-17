extends SceneTree
## Sol-only regression: physical N43 station and N14 ship at the SAME
## canonical coordinate must share one screen pixel. No fake route,
## economic mutation, simulated UI clock or change to source Rust seed.
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const View = preload("res://scripts/star_system_view.gd")
const Projection = preload("res://scripts/ui_station_ship_projection.gd")


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("canonical native seed missing")
        return
    var frozen: String = JSON.stringify(seed)
    var model: RefCounted = Model.new()
    var resolver: RefCounted = Resolver.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("canonical World/N43 cannot resolve real Sol station")
        return
    var sol: Dictionary = model.system_by_id("system-sol")
    var station: Dictionary = resolver.positions_from_world(
        model, 0.0)
    if not station.get("ok", false):
        _fail("station real native position missing")
        return
    var original: Vector2 = station["positions"]["earth-station"]
    var screen: Control = View.new()
    root.add_child(screen)
    screen.size = Vector2(1100, 800)
    screen.set_world(sol)
    screen.set_native_station_time(0.0)
    screen.set("_zoom", 52.0)
    var ship: Dictionary = {
        "id": "physical-probe", "class": "courier",
        "location": "", "system_id": "system-sol",
        "transit": {
            "from": "earth-station", "to": "mars-station",
            "departure_position": [original.x, original.y],
            "position": [original.x, original.y],
            "last_tick": 0
        }
    }
    screen.set_live_fleet({"physical-probe": ship})
    await process_frame
    await process_frame
    var stations: Array = screen.get("_station_draw_records")
    var ship_pins: Array = screen.get("_ship_pins")
    var station_pins: Array = screen.get("_facility_pins")
    if stations.size() != 1 or ship_pins.size() != 1 or (
            station_pins.size() != 5):
        _fail("Sol 1 station + 4 enterprises + 1 physical vessel missing")
        return
    var icon: Vector2 = stations[0]["screen"]
    var native: Vector2 = stations[0]["native"]
    if icon.distance_to(ship_pins[0]["position"]) > 0.05:
        _fail("native ship at real N43 dock not on station glyph")
        return
    if native.distance_to(original) > 0.000005:
        _fail("station visual native pose differs from authoritative N43")
        return
    var correction: Vector2 = Projection.corrected_screen(
        native, stations[0]["native_global_screen"], stations)
    if correction.distance_to(icon) > 0.00001:
        _fail("pure native-screen correction failed at exact dock")
        return
    var distant: Vector2 = native + Vector2(0.2, 0.0)
    var original_global: Vector2 = Vector2(120, 150)
    if Projection.corrected_screen(distant, original_global,
            stations) != original_global:
        _fail("station projection contaminated deep-space vessels")
        return

    var docked: Dictionary = ship.duplicate(true)
    docked["location"] = "earth-station"
    docked["transit"] = {}
    screen.set_live_fleet({"physical-probe": docked})
    if (screen.get("_recent_arrivals") as Dictionary).is_empty():
        _fail("genuine N14 arrival did not transition to station marker")
        return
    screen.queue_redraw()
    await process_frame
    var actual_docked: Array = screen.get("_ship_pins")
    if actual_docked.is_empty():
        _fail("canonical arrived ship cannot be picked at station")
        return
    var has_stable_dock: bool = false
    for pin in actual_docked:
        if pin.get("ship_ids", []).has("physical-probe") and (
                (pin["position"] as Vector2).distance_to(icon) < 18.0):
            has_stable_dock = true
    if not has_stable_dock:
        _fail("arrived ship marker reappeared at planet center")
        return
    var departing: Dictionary = ship.duplicate(true)
    departing["transit"]["position"] = [
        original.x + 0.01, original.y + 0.002]
    screen.set_live_fleet({"physical-probe": departing})
    var launch_origins: Dictionary = screen.get("_ship_motion_from")
    if not launch_origins.has("physical-probe") or (
            launch_origins["physical-probe"] != [
                original.x, original.y]):
        _fail("departure has no genuine receipt position for easing")
        return
    screen.queue_redraw()
    await process_frame
    # Corrected projection is local to this one station; it must not
    # invoke N14 aim_point or create economic movement.
    if JSON.stringify(seed) != frozen:
        _fail("visual docking projection mutated Rust seed")
        return
    screen.queue_free()
    print("P2 SOL STATION SHIP ALIGNMENT PASS: exact native N43 dock ",
        "pixel=real N14 vessel, native launch interpolation, ",
        "canonical arrival with station pickup; distant ships unmodified")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 SOL STATION SHIP ALIGNMENT FAIL: " + reason)
    quit(1)
