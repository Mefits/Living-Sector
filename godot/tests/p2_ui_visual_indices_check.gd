extends SceneTree
## No fabricated economy: visual indices alone on a tiny read-only world.
const Map = preload("res://scripts/system_map.gd")
const Star = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    var sys: Dictionary = {"system": {"id": "system-sol",
        "name": "Sol", "star_type": "G", "universe_offset": [10.0, 20.0]},
        "bodies": [
            {"id": "earth", "name": "Earth", "type": "planet",
             "biome": "terrestrial", "orbit_radius": 10.0, "current_angle": 0.0},
            {"id": "luna", "name": "Moon", "type": "moon",
             "biome": "lifeless", "orbit_radius": 10.1, "current_angle": 90.0}],
        "facilities": [{"id": "dock-a", "body": "earth", "location": "Earth-port"}]}
    var sector = Map.new()
    root.add_child(sector)
    sector.set_worlds([sys])
    if sector._source_positions.size() != 1 or (
            sector._source_positions[0] != Vector2(10.0, -20.0)):
        _fail("sector projection altered original physical universe_offset")
        return
    var visual = Star.new()
    root.add_child(visual)
    visual.set_world(sys)
    if visual._facility_count("earth") != 1 or (
            visual._facility_count("luna") != 0):
        _fail("indexed facility-to-body mapping diverged")
        return
    var fleet: Dictionary = {"actual-source-ship": {
        "location": "Earth-port", "system_id": "system-sol",
        "class": "miner", "transit": {}, "cargo": {"ore": 4}}}
    visual.set_live_fleet(fleet)
    if visual._live_ship_count("earth") != 1 or (
            visual._live_ship_count("luna") != 0):
        _fail("fleet marker does not reflect original physical location")
        return
    # Untrusted caller retains mutable dictionaries. A visual-only
    # projection must not share references with either source object.
    fleet["actual-source-ship"]["location"] = "forged"
    fleet["actual-source-ship"]["cargo"]["ore"] = 999
    sys["bodies"][0]["current_angle"] = 40.0
    if visual._live_ship_count("earth") != 1 or (
            visual._body_by_id("earth")["current_angle"] != 0.0):
        _fail("visual indices retained mutable external proposal aliases")
        return
    visual.update_world(sys)
    if visual._body_by_id("earth")["current_angle"] != 40.0:
        _fail("live native orbit angle not reflected")
        return
    # Facility mutations are real visual invalidation events; indices
    # must rebuild only then, without any new simulated economic facility.
    var changed: Dictionary = sys.duplicate(true)
    changed["facilities"].append({"id": "dock-b", "body": "earth",
        "location": "Moon-port"})
    visual.update_world(changed)
    if visual._facility_count("earth") != 2:
        _fail("facility-to-body index was not invalidated on a real view change")
        return
    var traveling: Dictionary = {"actual-source-ship": {
        "location": "Earth-port", "system_id": "system-sol",
        "class": "miner", "transit": {"position": [20.0, 30.0]}}}
    visual.set_live_fleet(traveling)
    if visual._live_ship_count("earth") != 0:
        _fail("in-flight ship shown as physically docked on a body")
        return
    # This input value differs from the cached source system; the sector
    # map changes only after set_worlds(), never by source dictionary alias.
    sys["system"]["universe_offset"] = [1000.0, -60.0]
    if sector.worlds[0]["system"]["universe_offset"] != [10.0, 20.0]:
        _fail("sector source coordinate cache was mutated by source")
        return
    sector.set_worlds([sys])
    if sector._source_positions[0] != Vector2(1000.0, 60.0):
        _fail("explicit sector geometry invalidation failed")
        return
    print("P2_UI_VISUAL_INDICES_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_UI_VISUAL_INDICES_FAIL: " + reason)
    quit(1)
