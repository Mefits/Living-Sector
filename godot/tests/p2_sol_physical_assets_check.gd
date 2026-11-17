extends SceneTree
## Stage 1: real Sol orbital station + physically distinct Earth surface
## facilities as ONE read-only spatial projection of frozen N39 objects.
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const Assets = preload("res://scripts/sim/phase2/sol_physical_assets_projection.gd")
const N43 = preload("res://scripts/sim/ships/native_location_resolver.gd")
const View = preload("res://scripts/star_system_view.gd")
const Main = preload("res://scripts/main.gd")

func _initialize() -> void:
    call_deferred("_test")


func _test() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen source seed unavailable")
        return
    var original: String = JSON.stringify(seed)
    var model: RefCounted = Model.new()
    var resolver: RefCounted = N43.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("canonical Sol N43 missing")
        return
    var sol: Dictionary = model.system_by_id("system-sol")
    var projected: Dictionary = Assets.build(sol)
    if projected.has("error") or projected["orbital"].size() != 1 or (
            projected["surface"].size() != 4):
        _fail("five real Sol facilities not separated into orbital/surface")
        return
    var station: Dictionary = projected["orbital"][0]
    if str(station["id"]) != "facility-earth-station" or (
            str(station["location"]) != "earth-station") or (
            int(station["docking_capacity"]) != 12):
        _fail("orbit object lost original station identity or real dock")
        return
    var seen: Dictionary = {}
    for site in projected["surface"]:
        seen[str(site["id"])] = site
        if str(site["body"]) != "earth" or str(site["location"]) != (
                "earth-station"):
            _fail("real surface facility lost shared N39 location")
            return
    for required in ["facility-earth-mine-module",
            "facility-earth-refinery-module",
            "facility-earth-station-farm-module",
            "facility-earth-station-factory"]:
        if not seen.has(required):
            _fail("missing actual production facility " + required)
            return
    if Assets.build({"system": {"id": "system-alpha-centauri"},
            "facilities": []})["source_ids"].size() != 0:
        _fail("Sol-only objects spilled into other systems")
        return
    if JSON.stringify(seed) != original:
        _fail("source Rust production or economy mutated")
        return

    var view: Control = View.new()
    root.add_child(view)
    view.size = Vector2(1100, 800)
    view.set_world(sol)
    view.set("_zoom", 52.0)
    # Drive the station from the SAME native time as N43 ephemerides,
    # never a fake display orbit with its own simulation clock.
    var native_units: float = 87.5
    view.set_native_station_time(native_units)
    view.set("_station_time_started_usec", -1)
    view.set_live_facilities({
        "facility-earth-station": {
            "credits": 3456, "assigned_workers": 12,
            "work_shift": {"tick": 20, "wages": 30}
        },
        "facility-earth-mine-module": {
            "credits": 900, "assigned_workers": 7,
            "module_stock": {"stock": {"ore": 6}}
        }
    })
    await process_frame
    await process_frame
    var pins: Array = view.get("_facility_pins")
    if pins.size() != 5:
        _fail("map did not render exactly five physical source objects")
        return
    var ids: Dictionary = {}
    for pin in pins:
        ids[str(pin["id"])] = pin["position"]
    if ids.size() != 5:
        _fail("facility markers duplicate or invent N39 IDs")
        return
    var earth: Dictionary = model.body_by_id("earth").get("value", {})
    var body_screen: Vector2 = view.call("_body_position", earth,
        float(view.call("_orbit_scale")))
    var station_screen: Vector2 = ids["facility-earth-station"]
    var expected_angle: float = fposmod(float(
        N43.initial_facility_angle("earth-station")) +
        360.0 * native_units / N43.FACILITY_ORBIT_PERIOD, 360.0)
    var diff: Vector2 = station_screen - body_screen
    var target_direction: Vector2 = Vector2(cos(deg_to_rad(
        expected_angle)), -sin(deg_to_rad(expected_angle)))
    if diff.length() < 10.0 or diff.normalized().dot(
            target_direction) < 0.999:
        _fail("station not anchored to actual N43 orbital phase")
        return
    var orbital: Dictionary = resolver.ephemeris_for_location(
        "earth-station", model, native_units)
    if not orbital.get("ok", false):
        _fail("real physical docking trajectory unavailable")
        return
    var live: Dictionary = view.get("_live_facility_status")
    if not live["facility-earth-station"].get("present", false) or (
            int(live["facility-earth-station"]["credits"]) != 3456):
        _fail("orbital station is not displaying real detached N39 state")
        return
    var selected: Array[String] = []
    view.facility_selected.connect(func(id: String) -> void:
        selected.append(id))
    view.call("_pick", station_screen)
    if selected != ["facility-earth-station"]:
        _fail("real orbital station cannot be selected")
        return
    var selected_surface: String = "facility-earth-mine-module"
    view.call("_pick", ids[selected_surface])
    if selected.size() != 2 or selected.back() != selected_surface:
        _fail("real surface production district not clickable")
        return
    var ui: Control = Main.new()
    var info: RichTextLabel = RichTextLabel.new()
    ui.set("_details", info)
    ui.set("_selected_facility_id", selected_surface)
    if not bool(ui.call("_show_facility_details", sol, {
            "facilities": {
                selected_surface: {
                    "credits": 900, "assigned_workers": 7,
                    "module_stock": {"stock": {"ore": 6}},
                    "work_shift": {"tick": 20, "wages": 24}
                }
            }
        })):
        _fail("N39 source-backed surface enterprise inspector refused")
        return
    for word in ["Genesis", "900 CR", "7", "ore", "earth-station"]:
        if not info.text.contains(word):
            _fail("surface economy inspector missing source: " + word)
            return
    ui.free()
    info.free()
    view.queue_free()
    if JSON.stringify(seed) != original:
        _fail("presentation edited frozen Rust files")
        return
    print("P2 SOL PHYSICAL ASSETS PASS: 1 real N43 orbiting station, ",
        "4 real Earth enterprises, all 5 clickable, live N39 inspector, ",
        "same shared legacy logistics, untouched seed")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 SOL PHYSICAL ASSETS FAIL: " + reason)
    quit(1)
