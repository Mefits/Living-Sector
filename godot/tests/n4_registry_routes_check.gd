extends SceneTree
## godot --headless --path godot --script res://tests/n4_registry_routes_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Registry = preload("res://scripts/sim/world_registry.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail(str(seed["error"]))
        return
    var registry = Registry.new()
    if not registry.load_seed(seed):
        _fail("native seed registry rejected")
        return
    var counts: Dictionary = registry.counts()
    var expected: Dictionary = {
        "system": 8, "faction": 3, "body": 47, "facility": 15,
        "ship": 24, "market": 3, "population": 3
    }
    for kind in expected:
        if int(counts.get(kind, -1)) != expected[kind]:
            _fail("count mismatch: " + kind)
            return
    var first_ship: Dictionary = registry.get_entity("ship", "@system-sol/0")
    if first_ship.get("value", {}).get("class", "") != "miner":
        _fail("stable source ordinal identity")
        return
    first_ship["value"]["class"] = "forged"
    if registry.get_entity("ship", "@system-sol/0")["value"]["class"] != "miner":
        _fail("registry leaked writable references")
        return
    var graph = registry.graph()
    if graph == null or graph.edge_count() != 12:
        _fail("native route count")
        return
    var path: Dictionary = graph.shortest_path("earth-station", "pirate-outpost")
    var expected_path: Array = [
        "earth-station", "lane-epsilon", "lane-tau",
        "lane-barnard", "pirate-outpost"
    ]
    if not path.get("reachable", false) or path["locations"] != expected_path:
        _fail("native directed route chain")
        return
    if not is_equal_approx(float(path["distance"]), 855.0):
        _fail("native route distance")
        return
    if graph.shortest_path("pirate-outpost", "earth-station").get("reachable", true):
        _fail("invented reverse route")
        return
    var snapshot: String = JSON.stringify(registry.snapshot())
    var second = Registry.new()
    if not second.load_seed(seed) or JSON.stringify(second.snapshot()) != snapshot:
        _fail("non-deterministic registry snapshot")
        return
    var malformed: Dictionary = seed.duplicate(true)
    malformed["worlds"][0]["travel_routes"].append({
        "from": "bad", "to": "bad2", "distance": -2
    })
    if registry.load_seed(malformed):
        _fail("accepted invalid distance")
        return
    if JSON.stringify(registry.snapshot()) != snapshot:
        _fail("failed load mutated existing registry")
        return
    print("N4_REGISTRY_ROUTES_PASS ", JSON.stringify(counts))
    quit(0)

func _fail(reason: String) -> void:
    push_error("N4_REGISTRY_ROUTES_FAIL " + reason)
    quit(1)
