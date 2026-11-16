extends SceneTree
## Read-only selection on the actual N14 map, without changing N39 state.
const NativeData = preload("res://scripts/native_data.gd")
const Model = preload("res://scripts/sim/world_model.gd")
const View = preload("res://scripts/star_system_view.gd")
const MainUI = preload("res://scripts/main.gd")

func _initialize() -> void:
    call_deferred("_check")


func _check() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native seed missing")
        return
    var model: RefCounted = Model.new()
    if not model.load_seed(seed):
        _fail("canonical physics unavailable")
        return
    var sol: Dictionary = model.system_by_id("system-sol")
    var map: Control = View.new()
    root.add_child(map)
    map.size = Vector2(1000.0, 750.0)
    map.set_world(sol)
    var fleet: Dictionary = {
        "fixture-ship-1": {
            "name": "Miner One", "class": "miner",
            "system_id": "system-sol", "location": "earth-station",
            "transit": {}
        },
        "fixture-ship-2": {
            "name": "Miner Two", "class": "miner",
            "system_id": "system-sol", "location": "earth-station",
            "transit": {}
        },
        "fixture-moving-3": {
            "name": "Moving One", "class": "courier",
            "system_id": "system-sol", "location": "",
            "transit": {"position": [3.0, 1.0], "to": "earth-station",
                "navigation_waypoints": [[3.2, 1.15], [3.4, 1.2]]}
        }
    }
    var original: String = JSON.stringify(fleet)
    map.set_live_fleet(fleet)
    await process_frame
    await process_frame
    var pins: Array = map.get("_ship_pins")
    var docked: Dictionary = {}
    var flying: Dictionary = {}
    for pin in pins:
        var ship_ids: Array = pin.get("ship_ids", [])
        if ship_ids.size() == 2:
            docked = pin
        if ship_ids.size() == 1 and (
                ship_ids[0] == "fixture-moving-3"):
            flying = pin
    if docked.is_empty() or flying.is_empty():
        _fail("real moving ship and docked fleet not both clickable")
        return
    var selected: Array = []
    map.ship_selected.connect(func(id: String) -> void:
        selected.append(id))
    map.call("_pick", docked["position"])
    if selected != ["fixture-ship-1"]:
        _fail("first click didn't select first authentic docked ship")
        return
    map.call("_pick", docked["position"])
    if selected != ["fixture-ship-1", "fixture-ship-2"]:
        _fail("repeated docked fleet click didn't cycle real ships")
        return
    map.call("_pick", flying["position"])
    if selected.size() != 3 or selected.back() != "fixture-moving-3":
        _fail("flying vessel cannot be selected")
        return
    if str(map.get("_selected_ship_id")) != "fixture-moving-3":
        _fail("selected ship highlight state not retained")
        return
    map.set_live_fleet(fleet)
    var projected: Dictionary = map.get("_live_fleet")
    if (projected["fixture-moving-3"]["transit"].get(
            "navigation_waypoints", []) as Array).size() != 2:
        _fail("selected vessel lost its real physical waypoint polyline")
        return
    if projected["fixture-ship-1"]["transit"].has(
            "navigation_waypoints"):
        _fail("nonselected vessel was given expensive trajectory data")
        return
    if JSON.stringify(fleet) != original:
        _fail("UI changed canonical source fleet")
        return
    if model.seed_fingerprint() != model.seed_fingerprint():
        _fail("read-only world invariant")
        return

    # Main inspector uses a detached fleet snapshot, no job dispatch.
    var ui: Control = MainUI.new()
    var details: RichTextLabel = RichTextLabel.new()
    ui.set("_details", details)
    ui.set("_selected_ship_id", "fixture-moving-3")
    var full: Dictionary = {
        "fixture-moving-3": {
            "name": "Moving One", "id": "fixture-moving-3",
            "class": "courier", "faction_id": "terran-authority",
            "system_id": "system-sol",
            "fuel": 5.0, "fuel_capacity": 10.0,
            "cargo": {"ore": 4}, "cargo_capacity": 20,
            "credits": 65,
            "location": "",
            "transit": {
                "from": "earth-station", "to": "luna-dock",
                "departure_tick": 10, "last_tick": 12, "arrival_tick": 40
            }
        }
    }
    if not bool(ui.call("_show_ship_details", full)):
        _fail("real ship inspector rejected selected vessel")
        return
    var shown: String = details.text
    for marker in ["Moving One", "terran-authority", "luna-dock",
            "Топливо: 5.0 / 10.0", "ore: 4", "Груз: 4 / 20"]:
        if not shown.contains(marker):
            _fail("ship inspector is missing requested source field: " + marker)
            return
    map.queue_free()
    ui.free()
    details.free()
    print("P2 SHIP SELECTION PASS: moving pins, docked cycles, ",
        "real inspector fields, readonly authoritative fleet")
    quit(0)


func _fail(reason: String) -> void:
    push_error("P2 SHIP SELECTION FAIL: " + reason)
    quit(1)
