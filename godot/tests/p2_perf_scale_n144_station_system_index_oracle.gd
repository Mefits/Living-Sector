extends SceneTree
## SCALE hypothesis: station-system index must match the frozen
## any-station same-system scoring rule, without mutating world or graph.
## TEST_ADDED_NOT_RUN / TEST_UNVERIFIED pending morning Godot.
const N144 = preload("res://scripts/sim/phase2/unified_n144_new_colony_head.gd")

class BodyModel:
    extends RefCounted
    var lookups: int = 0
    func body_by_id(id: String) -> Dictionary:
        lookups += 1
        var systems: Dictionary = {
            "earth": "sol", "mars": "sol", "venus": "sol",
            "alpha": "alpha", "beta": "beta"}
        return {"system_id": systems.get(id, ""),
            "value": {"type": "planet"}}

class RouteGraph:
    extends RefCounted
    func shortest_path(_source: String, _destination: String) -> Dictionary:
        return {"reachable": true, "distance": 9.0}

func _initialize() -> void:
    var model := BodyModel.new()
    var graph := RouteGraph.new()
    var world: Dictionary = {
        "bodies": {
            "mars": {"resources": {"ore": 0.7, "ice": 0.2, "gas": 0.1}},
            "alpha": {"resources": {"ore": 0.7, "ice": 0.2, "gas": 0.1}}},
        "markets": {"earth-market": {"supply": {"gas": 0.0}}},
        "facilities": {
            "home": {"faction": "a", "type": "station", "body_id": "earth"},
            "foreign": {"faction": "b", "type": "station", "body_id": "alpha"},
            "gate": {"faction": "a", "type": "gate", "body_id": "alpha"}}}
    var before: Dictionary = world.duplicate(true)
    var systems: Dictionary = {}
    for fac in world["facilities"].values():
        if str(fac.get("faction", "")) == "a" and str(fac.get("type", "")) == "station":
            systems[str(model.body_by_id(str(fac.get("body_id", ""))).get("system_id", ""))] = true
    var lookup_count: int = model.lookups
    var home_score: float = N144._score(world, model, graph, "a", "mars",
        "earth-market", systems)
    var foreign_score: float = N144._score(world, model, graph, "a", "alpha",
        "earth-market", systems)
    # Same resource inputs and route; same-system multiplier is exactly 4.
    if not is_equal_approx(home_score, foreign_score * 4.0):
        _fail("native same-system valuation or foreign-station exclusion changed")
        return
    if model.lookups != lookup_count + 2:
        _fail("scoring re-scanned station body identities")
        return
    # A second owned station in alpha must enable the same-system boost.
    world["facilities"]["alpha-home"] = {
        "faction": "a", "type": "station", "body_id": "alpha"}
    systems["alpha"] = true
    var owned_score: float = N144._score(world, model, graph, "a", "alpha",
        "earth-market", systems)
    if not is_equal_approx(owned_score, home_score):
        _fail("new faction station not counted")
        return
    if before["facilities"]["home"] != world["facilities"]["home"] or (
            world["markets"] != before["markets"]):
        _fail("read-only scoring changed authoritative source")
        return
    print("P2_PERF_SCALE_N144_STATION_SYSTEM_INDEX_ORACLE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_SCALE_N144_STATION_SYSTEM_INDEX_FAIL: " + reason)
    quit(1)
