extends SceneTree
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/ships/native_itinerary_runtime.gd")
const Checkpoint = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var runtime = Runtime.new()
    if not runtime.start_new(seed).get("ok", false):
        _fail("new_game")
        return
    var id: String = "@system-sol/0"
    if not runtime.assign_route(id, "n64:sol-to-barnard", "lane-barnard").get("ok", false):
        _fail("route")
        return
    var first: Dictionary = runtime.dispatch_current_tick()
    if not first.get("ok", false) or str(first["outcomes"][id]) != "departed:lane-epsilon":
        _fail("first_physical_leg")
        return
    if runtime.dispatch_current_tick().get("ok", false):
        _fail("double_dispatch_same_tick")
        return
    if runtime.intents.entry_for(id)["status"] != "flying" or str(
            runtime.engine.runner._fleet.ships[id]["transit"]["to"]) != "lane-epsilon":
        _fail("flight_intent_desync")
        return
    var first_fuel: float = float(runtime.engine.runner._fleet.ships[id]["fuel"])
    if not runtime.advance_native_tick().get("ok", false):
        _fail("native_tick")
        return
    if runtime.engine.runner.tick_count != 1:
        _fail("wrong_tick")
        return
    var saved: Dictionary = runtime.checkpoint()
    if not saved.get("ok", false):
        _fail("checkpoint")
        return
    var restored = Runtime.new()
    if not restored.restore_new(seed, JSON.parse_string(JSON.stringify(saved))).get("ok", false):
        _fail("restore_full_intent")
        return
    if restored.intents.entry_for(id)["status"] != "flying":
        _fail("saved_intent_flight")
        return
    if restored.dispatch_current_tick().get("ok", false):
        _fail("replayed_dispatch_tick")
        return
    if restored.engine.runner.bootstrap_new_game_native_fleet(seed):
        _fail("refueled_on_restore")
        return
    if float(restored.engine.runner._fleet.ships[id]["fuel"]) > first_fuel:
        _fail("fuel_inflation")
        return
    if restored.assign_route(id, "n64:second", "lane-barnard").get("ok", false):
        _fail("assigned_new_route_midflight")
        return
    var corrupt: Dictionary = saved.duplicate(true)
    corrupt["payload"]["intents"][0]["index"] = 99
    corrupt["sha256"] = Checkpoint._canonical(corrupt["payload"]).sha256_text()
    if Runtime.new().restore_new(seed, corrupt).get("ok", false):
        _fail("rehashed_invalid_progress")
        return
    corrupt = saved.duplicate(true)
    corrupt["payload"]["world"]["payload"]["ledger"]["balances"]["ship:@system-sol/0"] = 999999
    corrupt["sha256"] = Checkpoint._canonical(corrupt["payload"]).sha256_text()
    if Runtime.new().restore_new(seed, corrupt).get("ok", false):
        _fail("inner_ledger_checksum_bypassed")
        return
    print("N64_ROUTE_RUNTIME_PASS: one native leg per tick, full intent checkpoint and no replay")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N64_ROUTE_RUNTIME_FAIL " + reason)
    quit(1)
