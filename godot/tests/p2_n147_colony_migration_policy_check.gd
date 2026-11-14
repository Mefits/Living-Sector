extends SceneTree
## N147 source policy test: actual seed remains untouched, separate
## constructed fixture verifies colony policy only. NOT a physical
## passenger transfer or a funded colony construction acceptance test.
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Colonies = preload("res://scripts/sim/phase2/unified_n147_colony_migration_observer.gd")
const Locations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const SourceWorld = preload("res://scripts/sim/world_model.gd")
const Roster = preload("res://scripts/sim/ships/native_ship_roster.gd")

class FixtureGraph extends RefCounted:
    var allow: bool = true
    func shortest_path(origin: String, destination: String) -> Dictionary:
        if origin == destination and origin in ["earth-station", "mars-colony"]:
            return {"reachable": true, "locations": [origin], "distance": 0.0}
        if allow and origin == "earth-station" and destination == "mars-colony":
            return {"reachable": true, "locations": [origin, destination], "distance": 10.0}
        return {"reachable": false, "reason": "no_native_directed_edge"}
    func outgoing(origin: String) -> Array:
        return [{"to": "mars-colony", "distance": 10.0}] if allow and origin == "earth-station" else []

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("frozen Galaxy data unavailable")
        return
    var runner = Runner.new()
    if not runner.start_from_seed(seed):
        _fail("source N39 world unavailable: " + runner.boot_error())
        return
    var original: Dictionary = runner.checkpoint()
    var physical: Dictionary = runner.economy_snapshot()
    var model = SourceWorld.new()
    var roster = Roster.new()
    var resolver = Locations.new()
    if not model.load_seed(seed) or not roster.load_seed(seed) or not resolver.load_seed(seed):
        _fail("native N4/N43 route bootstrap failed")
        return
    var positions: Dictionary = resolver.positions_from_world(model, 0.0, true)
    if not positions.get("ok", false):
        _fail("native physical orbital positions unavailable")
        return
    var clean: Dictionary = Colonies.observe(physical, roster.registry.graph(),
        resolver, positions["positions"], 1, 1.0)
    if not clean.get("ok", false) or clean.get("status") != "N147_NO_ESTABLISHED_COLONIES" or not clean.get("ready", []).is_empty() or not clean.get("posted", []).is_empty():
        _fail("N147 fabricated real colonies or passenger missions on clean source")
        return
    if runner.checkpoint() != original:
        _fail("N147 read-only policy altered canonical world/ledger")
        return

    # Synthetic but structurally grounded future established colony. THIS
    # NEVER enters the authoritative N39 runner, SAVE or ContractBoard.
    var fixture: Dictionary = physical.duplicate(true)
    var home: String = "earth-station"
    if not fixture["markets"].has(home) or not fixture["faction_treasuries"].has("terran-authority"):
        _fail("Sol source market or original treasury absent")
        return
    var source_population_ok: bool = false
    for p in fixture["populations"].values():
        if str(p.get("location", "")) == home and str(p.get("faction", "")) == "terran-authority" and int(p.get("count", 0)) >= 40:
            source_population_ok = true
    if not source_population_ok:
        _fail("source Sol founding household does not satisfy original reserve")
        return
    fixture["facilities"]["fixture-colony-station"] = {
        "type": "station", "faction": "terran-authority",
        "location": "mars-colony", "crew_count": 20}
    for kind in ["mining_rig", "refinery", "farm"]:
        fixture["facilities"]["fixture-" + kind] = {
            "type": kind, "faction": "terran-authority",
            "location": "mars-colony",
            "crew_count": {"mining_rig": 8, "refinery": 12, "farm": 6}[kind]}
    var market: Dictionary = fixture["markets"][home].duplicate(true)
    market["owner"] = "fixture-colony-station"
    market["supply"]["food"] = 2000.0
    market["supply"]["water"] = 2000.0
    market["demand"]["food"] = 5.0
    market["demand"]["water"] = 3.0
    fixture["markets"]["mars-colony"] = market
    fixture["populations"]["fixture-residents"] = {
        "faction": "terran-authority", "location": "mars-colony",
        "count": 10, "wealth": 0,
        "consumption": {"food": 1.0, "water": 0.6}}
    var graph = FixtureGraph.new()
    var points: Dictionary = {"earth-station": Vector2(0.0, 0.0),
        "mars-colony": Vector2(0.1, 0.0)}
    var before: Dictionary = fixture.duplicate(true)
    var selected: Dictionary = Colonies.observe(fixture, graph,
        resolver, points, 200, 1.0)
    if not selected.get("ok", false) or selected.get("views", []).size() != 1 or selected.get("ready", []).size() != 1:
        _fail("N92/N147 missed source migration offer in detached future colony")
        return
    var order: Dictionary = selected["ready"][0]
    if int(order["quantity"]) != 20 or int(order["payment"]) != 1600 or str(order.get("status", "")) != "N147_PREPARED_NOT_POSTED":
        _fail("N147 source workers/escrow quotation differs or claims actual post")
        return
    if not selected["posted"].is_empty() or fixture != before:
        _fail("N147 invented money/passengers or mutated detached read-only fixture")
        return
    graph.allow = false
    if not Colonies.observe(fixture, graph, resolver, points,
            201, 1.0).get("ready", []).is_empty():
        _fail("N147 accepted passenger voyage without a directed physical path")
        return
    graph.allow = true
    fixture["faction_treasuries"]["terran-authority"] = 5000
    if not Colonies.observe(fixture, graph, resolver, points,
            202, 1.0).get("ready", []).is_empty():
        _fail("N147 accepted unfunded passenger escrow")
        return
    fixture["faction_treasuries"]["terran-authority"] = 240000
    fixture["markets"]["mars-colony"]["supply"]["water"] = 0.0
    if not Colonies.observe(fixture, graph, resolver, points,
            203, 1.0).get("ready", []).is_empty():
        _fail("N147 moved workforce to a colony without real life support")
        return
    if runner.checkpoint() != original:
        _fail("N147 policy fixture contaminated real World")
        return
    print("P2_N147_NATIVE_COLONY_SOURCE_POLICY_NO_PHANTOM_PASSENGERS_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N147_FAIL: " + reason)
    quit(1)
