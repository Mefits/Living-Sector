extends SceneTree
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/ships/native_itinerary_runtime.gd")
const Save = preload("res://scripts/sim/ships/native_fleet_checkpoint.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var runtime = Runtime.new()
    if not runtime.start_new(seed).get("ok", false):
        _fail("start")
        return
    var id: String = "@system-sol/0"
    var dock: Dictionary = runtime.execute_command("n66:op-dock", "dock", id,
        {"preferred_type": "station"})
    if not dock.get("ok", false):
        _fail("real_docking")
        return
    var repeated: Dictionary = runtime.execute_command("n66:op-dock", "dock", id,
        {"preferred_type": "station"})
    if not repeated.get("replayed", false) or not repeated.get("ok", false):
        _fail("replay")
        return
    if runtime.execute_command("n66:op-dock", "undock", id).get("ok", false):
        _fail("same_id_conflicting_payload")
        return
    var undock: Dictionary = runtime.execute_command("n66:op-undock", "undock", id)
    if not undock.get("ok", false):
        _fail("undock")
        return
    var departed: Dictionary = runtime.execute_command("n66:op-depart", "depart", id,
        {"destination": "mine-near-earth"})
    if not departed.get("ok", false):
        _fail("first_departure")
        return
    if not runtime.execute_command("n66:op-depart", "depart", id,
            {"destination": "mine-near-earth"}).get("replayed", false):
        _fail("transit_replay_not_idempotent")
        return
    if runtime.engine.runner._transit.next_token() != 2:
        _fail("departure_token_reused")
        return
    var saved: Dictionary = runtime.checkpoint()
    if not saved.get("ok", false):
        _fail("capture")
        return
    var resume = Runtime.new()
    if not resume.restore_new(seed, JSON.parse_string(JSON.stringify(saved))).get("ok", false):
        _fail("resume")
        return
    if resume.commands.snapshot().size() != 3:
        _fail("lost_command_history")
        return
    if not resume.execute_command("n66:op-depart", "depart", id,
            {"destination": "mine-near-earth"}).get("replayed", false):
        _fail("lost_replay_guard")
        return
    if resume.engine.runner._transit.next_token() != 2:
        _fail("double_transit_on_resume")
        return
    var forged: Dictionary = saved.duplicate(true)
    forged["payload"]["command_receipts"][0]["request"]["kind"] = "undock"
    forged["sha256"] = Save._canonical(forged["payload"]).sha256_text()
    if Runtime.new().restore_new(seed, forged).get("ok", false):
        _fail("forged_request_history")
        return
    print("N66_COMMAND_RECEIPTS_PASS: exactly-once dock/undock/transit across in-memory restore")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N66_COMMAND_RECEIPTS_FAIL " + reason)
    quit(1)
