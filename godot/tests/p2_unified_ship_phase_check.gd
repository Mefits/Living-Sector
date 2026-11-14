extends SceneTree
## Local-only integrated N46+N14 fleet acceptance. NO GitHub Actions.
## godot --headless --path godot --script res://tests/p2_unified_ship_phase_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy unavailable: " + str(seed["error"]))
        return
    var a = Runtime.new()
    if not a.start_from_seed(seed):
        _fail("unified P2 boot rejected 24 frozen ships: " + a.boot_error())
        return
    var ships: Dictionary = a.fleet_snapshot()
    if ships.size() != 24 or int(a.production_stats().get("ships", -1)) != 24:
        _fail("not 24 original N46 starter ships")
        return
    var counts: Dictionary = {}
    var selected: String = ""
    var sum_ship_credits: int = 0
    for sid in ships:
        var ship: Dictionary = ships[sid]
        var faction: String = str(ship.get("faction_id", ""))
        counts[faction] = int(counts.get(faction, 0)) + 1
        if str(ship.get("class", "")) == "miner" and faction == "terran-authority":
            selected = str(sid)
        if not ship.get("cargo", {}).is_empty():
            _fail("frozen seeder cargo must start empty")
            return
        if float(ship.get("fuel", -1)) != float(ship.get("fuel_capacity", -2)):
            _fail("N46 seed tank not at actual class capacity")
            return
        sum_ship_credits += int(ship.get("credits", -1))
    if selected.is_empty() or counts != {
        "terran-authority": 8, "ceti-freeholds": 8, "pirates": 8
    }:
        _fail("wrong frozen ship distribution: " + str(counts))
        return
    var before: Dictionary = a.checkpoint()
    if not before.get("native_production", {}).get("world", {}).has("ships"):
        _fail("ships not inside the SAME persistent N39 World")
        return
    var balances: Dictionary = before["native_production"]["ledger"]["balances"]
    var actual: int = 0
    for sid in ships:
        var wallet: String = "ship:" + str(sid)
        if not balances.has(wallet) or int(balances[wallet]) != int(ships[sid]["credits"]):
            _fail("ship wallet not in the ONE real N9 ledger: " + wallet)
            return
        actual += int(balances[wallet])
    if actual != sum_ship_credits:
        _fail("starter ship credits minted or lost")
        return
    var illegal: Dictionary = a.request_ship_departure(selected, "not-a-real-native-route")
    if illegal.get("ok", false) or a.checkpoint()["native_production"]["world"]["ships"] != ships:
        _fail("rejected ship destination changed canonical fleet")
        return
    a.queue_control("pause")
    a.queue_control("speed", 8.0)
    a.advance_frame(0.0)
    var order: Dictionary = a.request_ship_departure(selected, "alpha-station")
    if not order.get("ok", false):
        _fail("directed source earth→alpha route rejected: " + str(order))
        return
    var departure: Dictionary = a.fleet_snapshot()[selected]
    if not (departure.get("transit") is Dictionary) or departure["transit"].is_empty():
        _fail("N14 departure not committed in single World")
        return
    if int(a.checkpoint()["native_production"]["world"].get("ship_next_token", -1)) != 2:
        _fail("N14 native transit cursor was not committed")
        return
    a.queue_control("step", 5)
    a.advance_frame(0.0)
    if a.tick_count != 5 or not a.last_ship_result().get("ok", false):
        _fail("real ships phase didn't execute before paid facility tick")
        return
    var moving: Dictionary = a.fleet_snapshot()
    var transit: Dictionary = moving[selected].get("transit", {})
    if transit.is_empty() or str(transit.get("to", "")) != "alpha-station":
        _fail("real N14 long-distance ship stopped unexpectedly")
        return
    if int(transit.get("last_tick", -1)) != 5:
        _fail("N14 transit wasn't advanced exactly once per game tick")
        return
    if float(moving[selected]["fuel"]) >= float(ships[selected]["fuel"]):
        _fail("moving N14 transit didn't draw class-specific fuel")
        return
    var checkpoint: Dictionary = a.checkpoint()
    var save_path: String = "user://tests/p2-unified-fleet-" + str(Time.get_ticks_usec()) + ".json"
    if SaveState.save_runner(a, save_path) != OK:
        _fail("atomic N38/N39/N46 ship checkpoint failed")
        return
    var b = Runtime.new()
    if not b.start_from_seed(seed):
        _fail("restore target cannot initialize frozen source")
        return
    var recovered: Dictionary = SaveState.load_runner(b, seed, save_path)
    if not recovered.get("ok", false):
        _fail("canonical fleet checkpoint rejected after disk serialization: " + str(recovered))
        return
    if b.tick_count != 5 or b.fleet_snapshot().size() != moving.size():
        _fail("N14 ship roster/count changed across file reload")
        return
    var restored: Dictionary = b.fleet_snapshot()
    for sid in moving:
        if not restored.has(sid):
            _fail("N46 original ship ID lost in checkpoint: " + str(sid))
            return
        var original: Dictionary = moving[sid]
        var after: Dictionary = restored[sid]
        for field in ["id", "name", "class", "faction_id", "system_id",
                "location", "credits", "cargo", "cargo_capacity"]:
            if original.get(field, null) != after.get(field, null):
                _fail("saved ship immutable field changed: " + str(sid) + "/" + field)
                return
        if absf(float(original["fuel"]) - float(after["fuel"])) > 0.000001:
            _fail("saved ship Fuel changed during restart: " + str(sid))
            return
        var pre_transit: Dictionary = original["transit"]
        var post_transit: Dictionary = after["transit"]
        if pre_transit.is_empty() != post_transit.is_empty():
            _fail("N14 transit presence changed after restart")
            return
        if not pre_transit.is_empty():
            for field in ["token", "departure_tick", "last_tick",
                    "from", "to"]:
                if pre_transit.get(field, null) != post_transit.get(field, null):
                    _fail("N14 persisted transit metadata changed: " + field)
                    return
            for index in range(2):
                if absf(float(pre_transit["position"][index]) -
                        float(post_transit["position"][index])) > 0.00001:
                    _fail("N14 physical transit coordinate changed after restart")
                    return
    if b.checkpoint()["native_production"]["ledger"]["balances"] != checkpoint["native_production"]["ledger"]["balances"]:
        _fail("ship wallets or paid economy wallet changed across N9 reload")
        return
    if int(b.checkpoint()["native_production"]["world"]["ship_next_token"]) != 2:
        _fail("N14 transit cursor was lost after save/load")
        return
    b.queue_control("step", 5)
    b.advance_frame(0.0)
    if b.tick_count != 10 or not b.last_ship_result().get("ok", false):
        _fail("N14 transit did not resume after restart")
        return
    if int(b.fleet_snapshot()[selected]["transit"].get("last_tick", -1)) != 10:
        _fail("N14 transit repeated or skipped a tick after restart")
        return
    var absolute: String = ProjectSettings.globalize_path(save_path)
    DirAccess.remove_absolute(absolute)
    DirAccess.remove_absolute(absolute + ".bak")
    print("P2_CANONICAL_FLEET_ACCEPTANCE_PASS: 24 N46 real ships, 1 N9 ledger, N14 native route movement, source coordinates, signed nonce and persisted restart")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_CANONICAL_FLEET_ACCEPTANCE_FAIL: " + reason)
    quit(1)
