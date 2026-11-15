extends SceneTree
## N61: frozen directed route planning -> N60 itinerary admission -> N57
## single physical departure, without route-autopilot or phantom travel.
const NativeData = preload("res://scripts/native_data.gd")
const Live = preload("res://scripts/sim/live_native_fleet_engine.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native_seed")
        return
    var engine = Live.new()
    var started: Dictionary = engine.start_new_game(seed)
    if not bool(started.get("ok", false)):
        _fail("start_" + str(started.get("reason", "")))
        return
    var miner: String = "@system-sol/0"
    var initial_fuel: float = float(engine.runner._fleet.ships[miner]["fuel"])
    var credits: int = engine.ledger.total()
    var path: Dictionary = engine.plan_ship_itinerary(miner, "lane-barnard")
    if not bool(path.get("ok", false)):
        _fail("route_planning_" + str(path.get("reason", "")))
        return
    var locations: Array = path["locations"]
    # Graph distances: earth->lane-epsilon 115, epsilon->tau 150,
    # tau->barnard 200. Alternative via alpha: 120+155+200.
    if locations != ["earth-station", "lane-epsilon", "lane-tau", "lane-barnard"]:
        _fail("native_shortest_directed_path")
        return
    if int(path["hop_count"]) != 3 or not is_equal_approx(float(path["distance"]), 465.0):
        _fail("route_cost")
        return
    if not is_equal_approx(float(engine.runner._fleet.ships[miner]["fuel"]), initial_fuel) or engine.ledger.total() != credits:
        _fail("read_only_planning_mutated_world")
        return
    if engine.plan_ship_itinerary(miner, "mine-nadir-black-belt").get("ok", false) == false:
        _fail("reachability_to_nadir")
        return
    var bad: Dictionary = path.duplicate(true)
    bad["distance"] = 464.0
    if engine.depart_itinerary_hop(miner, bad).get("ok", false):
        _fail("stale_cost_admitted")
        return
    bad = path.duplicate(true)
    bad["locations"][1] = "alpha-station"
    if engine.depart_itinerary_hop(miner, bad).get("ok", false):
        _fail("changed_hop_with_old_total_admitted")
        return
    bad = path.duplicate(true)
    bad["locations"][2] = "earth-station"
    if engine.depart_itinerary_hop(miner, bad).get("ok", false):
        _fail("route_loop_admitted")
        return
    bad = path.duplicate(true)
    bad["locations"].pop_front()
    if engine.depart_itinerary_hop(miner, bad).get("ok", false):
        _fail("stale_ship_origin_admitted")
        return
    if engine.depart_itinerary_hop(miner, {"origin": "earth-station", "destination": "not-real",
        "locations": ["earth-station", "not-real"], "distance": 1.0}).get("ok", false):
        _fail("unknown_endpoint_admitted")
        return
    if not is_equal_approx(float(engine.runner._fleet.ships[miner]["fuel"]), initial_fuel) or engine.ledger.total() != credits:
        _fail("invalid_paths_mutated_world")
        return
    var action: Dictionary = engine.depart_itinerary_hop(miner, path)
    if not bool(action.get("ok", false)):
        _fail("physical_first_leg_" + str(action.get("reason", "")))
        return
    if str(action.get("departed_to", "")) != "lane-epsilon" or int(action.get("remaining_hops", -1)) != 2:
        _fail("first_hop_or_tail")
        return
    var remaining: Dictionary = action["remaining_itinerary"]
    if remaining.get("locations", []) != ["lane-epsilon", "lane-tau", "lane-barnard"]:
        _fail("remaining_route")
        return
    if (not bool(engine.docking.ships[miner]["in_transit"]) or (engine.runner._fleet.ships[miner]["transit"] as Dictionary).is_empty()):
        _fail("not_physically_in_transit")
        return
    if engine.depart_itinerary_hop(miner, remaining).get("ok", false):
        _fail("continued_before_arrival")
        return
    if engine.plan_ship_itinerary(miner, "lane-barnard").get("ok", false):
        _fail("replanned_midflight")
        return
    if not engine.advance_one_native_tick():
        _fail("tick_" + engine.halt_reason())
        return
    if engine.runner.tick_count != 1 or engine.ledger.total() != credits:
        _fail("tick_or_credit_conservation")
        return
    var snap: Dictionary = engine.checkpoint()
    if not bool(snap.get("ok", false)):
        _fail("midflight_save")
        return
    var restored = Live.new()
    var result: Dictionary = restored.restore_complete(seed,
        JSON.parse_string(JSON.stringify(snap)))
    if not bool(result.get("ok", false)):
        _fail("restore_" + str(result.get("reason", "")))
        return
    if restored.depart_itinerary_hop(miner, remaining).get("ok", false):
        _fail("restore_skipped_physical_leg")
        return
    if restored.ledger.total() != credits:
        _fail("restored_credits")
        return
    if not is_equal_approx(float(restored.runner._fleet.ships[miner]["fuel"]),
            float(engine.runner._fleet.ships[miner]["fuel"])):
        _fail("restored_fuel")
        return
    print("N61_LIVE_ITINERARY_PASS: route=earth->epsilon->tau->barnard, first hop physical, no teleport")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N61_LIVE_ITINERARY_FAIL " + reason)
    quit(1)
