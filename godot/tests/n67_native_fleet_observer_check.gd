extends SceneTree
## N67 observer is read-only: neither display nor snapshots may mutate tick,
## N11 money, ship fuel/cargo, command receipts, or route intentions.
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/ships/native_itinerary_runtime.gd")
const Observer = preload("res://scripts/sim/ships/native_fleet_observer.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var live = Runtime.new()
    if not live.start_new(seed).get("ok", false):
        _fail("new_game")
        return
    var before_fleet: String = JSON.stringify(live.engine.runner.live_fleet_snapshot())
    var before_money: int = live.engine.ledger.total()
    var initial: Dictionary = Observer.snapshot(live)
    if (not initial.get("ok", false) or initial["ship_count"] != 24 or initial["in_transit"] != 0 or initial["docked"] != 0):
        _fail("native_24_ships")
        return
    var actual_ids: Array = []
    for entry in initial["ships"]:
        actual_ids.append(str(entry["ship_id"]))
    var sorted_ids: Array = actual_ids.duplicate()
    sorted_ids.sort()
    if actual_ids != sorted_ids:
        _fail("unstable_identity_order")
        return
    var sol: Dictionary = {}
    for entry in initial["ships"]:
        if str(entry["ship_id"]) == "@system-sol/0":
            sol = entry
            break
    if (sol.is_empty() or sol["location"] != "earth-station" or int(sol["credits"]) != 40000 or sol["crew_current_morale"] != "—"):
        _fail("source_and_missing_fields")
        return
    if sol["status"] != "at_location" or sol["docked_at"] != "—":
        _fail("not_initially_undocked")
        return
    if (before_money != 2760000 or live.engine.ledger.total() != before_money or JSON.stringify(live.engine.runner.live_fleet_snapshot()) != before_fleet):
        _fail("snapshot_mutated_world")
        return
    var id: String = "@system-sol/0"
    if not live.execute_command("n67:dock", "dock", id,
            {"preferred_type": "station"}).get("ok", false):
        _fail("physical_dock")
        return
    var docked: Dictionary = Observer.snapshot(live)
    var dock_row: Dictionary = _find(docked["ships"], id)
    if dock_row["status"] != "docked" or not dock_row["blocked_reasons"].has("undock_required_before_departure"):
        _fail("docking_reason")
        return
    if not live.execute_command("n67:undock", "undock", id).get("ok", false):
        _fail("undock")
        return
    if not live.execute_command("n67:departure", "depart", id,
            {"destination": "mine-near-earth"}).get("ok", false):
        _fail("departure")
        return
    var flying: Dictionary = Observer.snapshot(live)
    var flight_row: Dictionary = _find(flying["ships"], id)
    if (flying["in_transit"] != 1 or flight_row["status"] != "in_transit" or flight_row["destination"] != "mine-near-earth"):
        _fail("flight_inspector")
        return
    if not flight_row["blocked_reasons"].has("in_transit_until_actual_arrival"):
        _fail("blocked_reasons")
        return
    if JSON.stringify(Observer.snapshot(live)) != JSON.stringify(Observer.snapshot(live)):
        _fail("not_deterministic")
        return
    print("N67_FLEET_OBSERVER_PASS: 24 ship source-backed states, no guessed economy/crew stats")
    quit(0)

func _find(rows: Array, ship_id: String) -> Dictionary:
    for row in rows:
        if str(row.get("ship_id", "")) == ship_id:
            return row
    return {}

func _fail(reason: String) -> void:
    push_error("N67_FLEET_OBSERVER_FAIL " + reason)
    quit(1)
