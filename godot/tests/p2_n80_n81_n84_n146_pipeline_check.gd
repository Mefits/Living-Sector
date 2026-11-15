extends SceneTree
## Native Rust framework integration. Run Godot 4.7 headless:
## godot --headless --path godot --script res://tests/p2_n80_n81_n84_n146_pipeline_check.gd
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Registry = preload("res://scripts/sim/ships/native_ship_roster.gd")
const Resolver = preload("res://scripts/sim/ships/native_location_resolver.gd")
const NativeBt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Planner = preload("res://scripts/sim/phase2/unified_ship_ai_planner.gd")
const Execute = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

func _initialize() -> void:
    # N84 source Rust Sequence: success advances ONE child per tick,
    # running keeps cursor; failure resets; Selector restarts from child 0.
    var seq: Dictionary = NativeBt.sequence([
        NativeBt.action({"kind": "first"}),
        NativeBt.action({"kind": "second"})])
    var calls: Array = []
    var success: Callable = func(action: Dictionary, _bb: Dictionary) -> Dictionary:
        calls.append(str(action["kind"]))
        return {"status": NativeBt.SUCCESS}
    var first: Dictionary = NativeBt.tick(seq, success)
    if not first.get("ok", false) or first["status"] != NativeBt.RUNNING or int(first["tree"]["index"]) != 1:
        _fail("N84 Rust one-child sequence semantics")
        return
    var encoded: String = JSON.stringify(first["tree"])
    var normalized: Dictionary = NativeBt.normalize_from_json(JSON.parse_string(encoded))
    if not NativeBt.validate(normalized) or int(normalized["index"]) != 1:
        _fail("N84 persisted cursor not stable over JSON")
        return
    normalized["index"] = 1.0
    normalized = NativeBt.normalize_from_json(normalized)
    if normalized.is_empty() or typeof(normalized["index"]) != TYPE_INT:
        _fail("N84 integer-shaped JSON cursor not restored")
        return
    var second: Dictionary = NativeBt.tick(normalized, success)
    if second["status"] != NativeBt.SUCCESS or int(second["tree"]["index"]) != 0:
        _fail("N84 final success must reset sequence index")
        return
    if calls != ["first", "second"]:
        _fail("N84 leaf ran more than once per tick")
        return
    var selector: Dictionary = NativeBt.selector([
        NativeBt.condition("gate"),
        NativeBt.action({"kind": "fallback"})])
    var selected: Dictionary = NativeBt.tick(selector, success, {"gate": false})
    if selected["status"] != NativeBt.SUCCESS or calls.size() != 3:
        _fail("N84 selector and condition parity")
        return
    var blocked: Dictionary = NativeBt.tick(NativeBt.sequence([
        NativeBt.action({"kind": "stuck"})]),
        func(_a: Dictionary, _b: Dictionary) -> Dictionary:
            return {"status": NativeBt.RUNNING})
    if blocked["status"] != NativeBt.RUNNING or int(blocked["tree"]["index"]) != 0:
        _fail("N84 running did not preserve active leaf")
        return

    # The NEXT checks read the ORIGINAL frozen 24-ship Galaxy JSON and
    # real directed N4 navigation, never synthesize a game world.
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("missing frozen Galaxy seed")
        return
    var runtime = Runtime.new()
    if not runtime.start_from_seed(seed):
        _fail("N39/N158 boot failed: " + runtime.boot_error())
        return
    var world: Dictionary = runtime.economy_snapshot()
    if world.get("ships", {}).size() != 24:
        _fail("not 24 frozen source ships")
        return
    var id: String = ""
    var ids: Array = world["ships"].keys()
    ids.sort()
    for sid in ids:
        var ship: Dictionary = world["ships"][sid]
        if str(ship["class"]) == "hauler" and str(ship["location"]) == "earth-station":
            id = str(sid)
            break
    if id.is_empty():
        _fail("source earth-station hauler not found")
        return
    var registry = Registry.new()
    var resolver = Resolver.new()
    if not registry.load_seed(seed) or not resolver.load_seed(seed):
        _fail("original N4 route and native location sources unavailable")
        return
    var graph: RefCounted = registry.registry.graph()
    if not graph.shortest_path("earth-station", "alpha-station").get("reachable", false):
        _fail("native directed real route not available")
        return
    var ship: Dictionary = world["ships"][id]
    var planned: Dictionary = Planner.propose(ship, {
        "contract_id": "test-only-not-posted", "source": "earth-station",
        "destination": "alpha-station", "commodity": "food",
        "quantity": 5, "profit": 5000, "ownership_priority": 1.25
    }, graph)
    if not planned.get("ok", false):
        _fail("N80 -> N81 -> N84 source planning: " + str(planned.get("reason", "?")))
        return
    if str(planned.get("goal", "")) != "fulfill_delivery" or not NativeBt.validate(planned["ai_bt"]):
        _fail("N80 did not select source delivery or N84 tree invalid")
        return
    if not (planned.get("n81_actions") is Array) or planned["n81_actions"].is_empty():
        _fail("N81 returned no real GOAP actions")
        return
    # Detached fixture to check N146 BeginTransit dispatch using real
    # native N14 coordinates and ship fuel. NEVER commit the fixture
    # contract or grant goods/credits to the live N39 world.
    var snapshot: Dictionary = world.duplicate(true)
    var marker: String = "test-only-accepted"
    snapshot["contract_board"]["contracts"][marker] = {
        "id": marker, "status": "accepted", "fulfiller_id": id}
    snapshot["ships"][id]["active_contract_id"] = marker
    snapshot["ships"][id]["current_bt"] = NativeBt.sequence([
        NativeBt.action({"kind": "Travel", "destination": "alpha-station"})])
    var positions: Dictionary = resolver.positions_from_world(runtime.world,
        runtime.calendar.native_time_units, runtime.calendar.origin_known)
    if not positions.get("ok", false):
        _fail("real native body-relative ship coordinates not available")
        return
    var motion: Dictionary = Execute.propose(snapshot, graph,
        positions["positions"], 1, runtime.clock.tick_scale())
    if not motion.get("ok", false) or motion.get("commands", []).size() != 1:
        _fail("N84 leaf did not yield one N146 command: " + str(motion))
        return
    var cmd: Dictionary = motion["commands"][0]
    if str(cmd["kind"]) != "BeginTransit" or str(cmd["ship"]) != id or str(cmd["to"]) != "alpha-station":
        _fail("N146 native ship command was not validated")
        return
    if (motion["ships"][id]["transit"] as Dictionary).is_empty() or int(motion["next_token"]) <= int(snapshot["ship_next_token"]):
        _fail("N146 command did not pass actual N14 transit")
        return
    if not world["ships"][id]["cargo"].is_empty() or world["ships"][id] != runtime.economy_snapshot()["ships"][id]:
        _fail("N84 planning mutated physical canonical World")
        return
    var in_flight: Dictionary = snapshot.duplicate(true)
    in_flight["ships"] = motion["ships"]
    in_flight["ship_next_token"] = motion["next_token"]
    var repeat: Dictionary = Execute.propose(in_flight, graph,
        positions["positions"], 1, runtime.clock.tick_scale())
    if not repeat.get("ok", false) or not repeat.get("commands", []).is_empty():
        _fail("N84 reissued transit while original ship was in flight")
        return
    print("P2_N80_N81_N84_N146_NATIVE_PIPELINE_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_NATIVE_AI_FRAMEWORKS_FAIL: " + message)
    quit(1)
