extends SceneTree
## Sol-only regression: physical N43 station and N14 ship at the SAME
## canonical coordinate must share one screen pixel. No fake route,
## economic mutation, simulated UI clock or change to source Rust seed.
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const View = preload("res://scripts/star_system_view.gd")
const ScreenProjection = preload("res://scripts/ui_station_ship_projection.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")
const Avoidance = preload("res://scripts/sim/ships/native_avoidance.gd")

class DirectedFlight:
    extends RefCounted
    func outgoing(location: String) -> Array:
        if location == "earth-station":
            return [{"from": location, "to": "outward-test"}]
        return []



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
    # At zoom 52 the Earth orbit is outside the default viewport. Center
    # the same existing orbital camera (no invented closer native world).
    var earth: Dictionary = model.body_by_id("earth").get("value", {})
    var raw_earth_screen: Vector2 = screen.call(
        "_body_position", earth, float(screen.call("_orbit_scale")))
    screen.set("_pan", screen.size * 0.5 - raw_earth_screen)
    screen.set("_draw_body_positions", {})
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
        _fail("Sol station/industry/vessel missing: " +
            str(stations.size()) + "/" + str(station_pins.size()) +
            "/" + str(ship_pins.size()))
        return
    var icon: Vector2 = stations[0]["screen"]
    var native: Vector2 = stations[0]["native"]
    if icon.distance_to(ship_pins[0]["position"]) > 0.05:
        _fail("native ship at real N43 dock not on station glyph")
        return
    if native.distance_to(original) > 0.000005:
        _fail("station visual native pose differs from authoritative N43")
        return
    var correction: Vector2 = ScreenProjection.corrected_screen(
        native, stations[0]["native_global_screen"], stations)
    if correction.distance_to(icon) > 0.00001:
        _fail("pure native-screen correction failed at exact dock")
        return
    var distant: Vector2 = native + Vector2(0.2, 0.0)
    var original_global: Vector2 = Vector2(120, 150)
    if ScreenProjection.corrected_screen(distant, original_global,
            stations) != original_global:
        _fail("station projection contaminated deep-space vessels")
        return

    # Actual BUG REPORT: when the visual Earth disc is hundreds of
    # pixels across, an N14 vessel that has just departed the 800-km
    # station must NEVER dive toward the enlarged planet center as
    # a former dock screen-offset correction fades away.
    screen.set("_zoom", 512.0)
    screen.queue_redraw()
    await process_frame
    await process_frame
    var close_records: Array = screen.get("_station_draw_records")
    if close_records.size() != 1:
        _fail("maximum-zoom physical station record missing")
        return
    var dock_record: Dictionary = close_records[0]
    var globe_px: Vector2 = dock_record["body_screen"]
    var drawn_ring: float = float(dock_record["screen_orbit_radius"])
    var globe_radius: float = float(screen.call("_body_size", earth))
    if drawn_ring < globe_radius + 108.0:
        _fail("max zoom station still hugs inflated Earth disc")
        return
    var native_center: Vector2 = dock_record["body_native"]
    var outward_native: Vector2 = (
        original - native_center).normalized()
    var offset: Vector2 = Vector2.ZERO
    var raw_source: Variant = sol.get(
        "system", {}).get("universe_offset", [0.0, 0.0])
    if raw_source is Array and raw_source.size() == 2:
        offset = Vector2(float(raw_source[0]), float(raw_source[1]))
    var orbit_scale: float = float(screen.call("_orbit_scale"))
    var last_radius: float = -1.0
    for dist in [0.0001, 0.001, 0.008, 0.025, 0.05, 0.09, 0.14]:
        var native_point: Vector2 = native_center + (
            outward_native * float(dist))
        var raw_screen: Vector2 = screen.call(
            "_native_screen_global", native_point, offset, orbit_scale)
        var corrected: Vector2 = ScreenProjection.corrected_screen(
            native_point, raw_screen, close_records)
        var radial: float = corrected.distance_to(globe_px)
        if radial < globe_radius + 5.0:
            _fail("departing ship reentered schematic planet disc")
            return
        if last_radius >= 0.0 and radial < last_radius - 1.0:
            _fail("departing ship made an inward loop at max zoom: " +
                str(dist) + " native, screen radial=" +
                str(radial) + " previous=" + str(last_radius) +
                " body_offset=" + str((dock_record["body_screen"] as Vector2
                    ).distance_to(dock_record["body_global_screen"])))
            return
        last_radius = radial
    var canonical: RefCounted = ShipState.new()
    if not canonical.add_ship(
            "launch-probe", "courier", "test-faction",
            "system-sol", "small"):
        _fail("could not instantiate authentic N14 launch")
        return
    canonical.ships["launch-probe"]["location"] = "earth-station"
    var navigation: RefCounted = Transit.new()
    var destinations: Dictionary = {
        "earth-station": original,
        "outward-test": native_center + outward_native * 0.30}
    if not navigation.depart(
            canonical, DirectedFlight.new(), "launch-probe",
            "outward-test", destinations, 0, 1.0):
        _fail("real N14 departure ignored N43 station origin")
        return
    var stored_origin: Array = canonical.ships[
        "launch-probe"]["transit"]["departure_position"]
    if Vector2(float(stored_origin[0]), float(stored_origin[1])
            ).distance_to(original) > 0.00000001:
        _fail("N14 actually launched from Earth center, not station")
        return
    var last_native: Vector2 = original
    for tick in range(1, 6):
        var outcome: String = navigation.advance(canonical,
            "launch-probe", destinations, tick, 1.0, 1, false,
            {}, 0.00001, {}, [{
                "id": "earth", "center": native_center,
                "radius": 6371.0 * 2.0 / 149597870.7 * 1.03
            }])
        if outcome != "moving" and outcome != "arrived":
            _fail("native outbound ship was blocked by own planet: " +
                outcome)
            return
        if outcome == "arrived":
            break
        var committed: Array = canonical.ships[
            "launch-probe"]["transit"]["position"]
        var current: Vector2 = Vector2(
            float(committed[0]), float(committed[1]))
        if Avoidance.segment_crosses(last_native, current,
                native_center, 6371.0 * 2.0 / 149597870.7 * 1.03):
            _fail("N14 physically crossed Earth's surface on launch")
            return
        last_native = current

    # Restore the original UI zoom before the earlier dock/undock
    # assertions, whose saved icon coordinate belongs to zoom 52.
    screen.set("_zoom", 52.0)
    screen.queue_redraw()
    await process_frame
    await process_frame
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
                (pin["position"] as Vector2).distance_to(icon) < 26.0):
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
