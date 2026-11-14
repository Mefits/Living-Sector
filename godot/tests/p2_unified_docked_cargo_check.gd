extends SceneTree
## P2 Gate2 one-World N21/N15 integration acceptance (requires Godot 4.7.2).
## godot --headless --path godot --script res://tests/p2_unified_docked_cargo_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native frozen Galaxy data unavailable: " + str(seed["error"]))
        return
    var a = Runtime.new()
    if not a.start_from_seed(seed):
        _fail("N39 world seed rejected: " + a.boot_error())
        return
    var start: Dictionary = a.economy_snapshot()
    var selected_ship: String = ""
    var selected_location: String = ""
    var selected_commodity: String = ""
    # Use ONLY actual native market/fleet locations, source seller and stock.
    var locations: Array = start["markets"].keys()
    locations.sort()
    for location in locations:
        var market: Dictionary = start["markets"][location]
        var owner_id: String = str(market["owner"])
        if not start["facilities"].has(owner_id):
            continue
        if int(start["facilities"][owner_id].get("docking_capacity", 0)) <= 0:
            continue
        var commodities: Array = market["supply"].keys()
        commodities.sort()
        for commodity in commodities:
            if float(market["supply"][commodity]) < 2.0:
                continue
            var ship_ids: Array = start["ships"].keys()
            ship_ids.sort()
            for sid in ship_ids:
                var ship: Dictionary = start["ships"][sid]
                if str(ship["location"]) == str(location) and int(ship["cargo_capacity"]) >= 2 and str(ship["faction_id"]) == str(start["facilities"][owner_id]["faction"]):
                    selected_ship = str(sid)
                    selected_location = str(location)
                    selected_commodity = str(commodity)
                    break
            if not selected_ship.is_empty():
                break
        if not selected_ship.is_empty():
            break
    if selected_ship.is_empty():
        _fail("native seed offers no dockable loaded market and nearby ship")
        return
    var original_balance: Dictionary = a.checkpoint()["native_production"]["ledger"]["balances"].duplicate(true)
    var original_stock: float = float(start["markets"][selected_location]["supply"][selected_commodity])
    if a.request_ship_cargo(selected_ship, "n15-before-dock", "load", {selected_commodity: 2}).get("ok", false):
        _fail("ship moved cargo without docking")
        return
    if a.economy_snapshot() != start:
        _fail("rejected cargo changed canonical stock")
        return
    var dock_receipt: Dictionary = a.request_ship_dock(selected_ship, "n21-dock")
    if not dock_receipt.get("ok", false):
        _fail("N21 dock request failed: " + str(dock_receipt))
        return
    var blocked_departure: Dictionary = a.request_ship_departure(selected_ship, "alpha-station")
    if str(blocked_departure.get("reason", "")) != "ship_must_undock_first":
        _fail("N21 did not block docked departure: " + str(blocked_departure))
        return
    var loaded: Dictionary = a.request_ship_cargo(selected_ship, "n15-load", "load", {selected_commodity: 2})
    if not loaded.get("ok", false):
        _fail("N15 real market load rejected: " + str(loaded))
        return
    var after_load: Dictionary = a.economy_snapshot()
    if float(after_load["markets"][selected_location]["supply"][selected_commodity]) != original_stock - 2.0:
        _fail("market source stock not debited")
        return
    if int(after_load["ships"][selected_ship]["cargo"].get(selected_commodity, 0)) != 2:
        _fail("ship hold not credited with same real cargo")
        return
    if a.checkpoint()["native_production"]["ledger"]["balances"] != original_balance:
        _fail("N15 physical load minted or debited money")
        return
    if a.request_ship_cargo(selected_ship, "n15-load", "load", {selected_commodity: 2}).get("ok", false):
        _fail("duplicate N15 receipt replayed")
        return
    if a.economy_snapshot() != after_load:
        _fail("duplicate N15 changed physical stock")
        return
    var filepath: String = "user://tests/p2-docked-cargo-" + str(Time.get_ticks_usec()) + ".json"
    if SaveState.save_runner(a, filepath) != OK:
        _fail("N38 N39 checkpoint did not write")
        return
    var b = Runtime.new()
    if not b.start_from_seed(seed):
        _fail("fresh runtime did not boot")
        return
    var loaded_save: Dictionary = SaveState.load_runner(b, seed, filepath)
    if not loaded_save.get("ok", false):
        _fail("file save/restart rejected: " + str(loaded_save))
        return
    if b.economy_snapshot() != after_load or b.checkpoint()["native_production"]["ledger"]["balances"] != original_balance:
        _fail("docked cargo and real market did not survive restart")
        return
    if b.request_ship_cargo(selected_ship, "n15-load", "load", {selected_commodity: 2}).get("ok", false):
        _fail("saved N15 receipt not idempotent")
        return
    var unloaded: Dictionary = b.request_ship_cargo(selected_ship, "n15-unload", "unload", {selected_commodity: 2})
    if not unloaded.get("ok", false):
        _fail("N15 unload failed after restore: " + str(unloaded))
        return
    var restored: Dictionary = b.economy_snapshot()
    if float(restored["markets"][selected_location]["supply"][selected_commodity]) != original_stock:
        _fail("unloading did not restore exact market inventory")
        return
    if int(restored["ships"][selected_ship]["cargo"].get(selected_commodity, 0)) != 0:
        _fail("unloading did not empty real ship hold")
        return
    if not b.request_ship_undock(selected_ship, "n21-undock").get("ok", false):
        _fail("N21 undock failed")
        return
    if not str(b.fleet_snapshot()[selected_ship].get("docked_at", "")).is_empty():
        _fail("N21 dock slot persisted after undock")
        return
    if b.checkpoint()["native_production"]["ledger"]["balances"] != original_balance:
        _fail("physical logistics modified N9 ledger")
        return
    print("P2_N21_N15_SINGLE_WORLD_DOCKED_CARGO_PASS")
    quit(0)

func _fail(reason: String) -> void:
    printerr("P2_N21_N15_SINGLE_WORLD_DOCKED_CARGO_FAIL: ", reason)
    quit(1)
