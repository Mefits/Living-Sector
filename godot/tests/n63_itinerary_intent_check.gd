extends SceneTree
const NativeData = preload("res://scripts/native_data.gd")
const Live = preload("res://scripts/sim/live_native_fleet_engine.gd")
const Registry = preload("res://scripts/sim/ships/itinerary_intent_registry.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("seed")
        return
    var live = Live.new()
    if not live.start_new_game(seed).get("ok", false):
        _fail("new_game")
        return
    var ship_id: String = "@system-sol/0"
    var planned: Dictionary = live.plan_ship_itinerary(ship_id, "lane-barnard")
    if not planned.get("ok", false):
        _fail("route")
        return
    var registry = Registry.new()
    var graph: RefCounted = live.runner._roster.registry.graph()
    var first: Dictionary = registry.register(ship_id, "intent:sol-barnard:1",
        planned, graph, live.runner._fleet.ships)
    if not first.get("ok", false):
        _fail("register_" + str(first.get("reason", "")))
        return
    if not registry.register(ship_id, "intent:sol-barnard:1",
            planned, graph, live.runner._fleet.ships).get("duplicate", false):
        _fail("duplicate_replay")
        return
    if registry.register(ship_id, "intent:sol-barnard:2",
            planned, graph, live.runner._fleet.ships).get("ok", false):
        _fail("competing_intent")
        return
    var next: Dictionary = registry.command_for_next_leg(ship_id,
        live.runner._fleet.ships, graph)
    if not next.get("ok", false) or str(next["next"]) != "lane-epsilon":
        _fail("first_direction")
        return
    var snap: Array = registry.snapshot()
    var restored = Registry.new()
    if not restored.restore(snap, live.runner._fleet.ships, graph):
        _fail("ready_restore")
        return
    if not live.depart_itinerary_hop(ship_id, planned).get("ok", false):
        _fail("physical_departure")
        return
    if not registry.confirm_departure(ship_id, live.runner._fleet.ships):
        _fail("physical_confirmation")
        return
    if registry.command_for_next_leg(ship_id, live.runner._fleet.ships, graph).get("ok", false):
        _fail("double_departure")
        return
    var flying: Array = registry.snapshot()
    if not restored.restore(flying, live.runner._fleet.ships, graph):
        _fail("flying_restore")
        return
    if restored.confirm_arrival(ship_id, live.runner._fleet.ships):
        _fail("premature_arrival")
        return
    var bad: Array = flying.duplicate(true)
    bad[0]["index"] = 2
    var old: String = JSON.stringify(restored.snapshot())
    if restored.restore(bad, live.runner._fleet.ships, graph) or old != JSON.stringify(restored.snapshot()):
        _fail("atomic_restore_drift")
        return
    bad = flying.duplicate(true)
    bad[0]["locations"][1] = "alpha-station"
    if restored.restore(bad, live.runner._fleet.ships, graph):
        _fail("route_tamper")
        return
    print("N63_INTENT_PASS: replay, ready/flying restoration, no phantom arrival")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N63_INTENT_FAIL " + reason)
    quit(1)
