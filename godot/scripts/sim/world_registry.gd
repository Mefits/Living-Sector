extends RefCounted
## Read-only identity index for the frozen Galaxy seed. Ships and nav sites have
## no native IDs: their keys are deterministic (system + source-array ordinal).
## Never treat these keys as Rust-native persistent IDs.
var _entities: Dictionary = {}
var _counts: Dictionary = {}
var _route_graph: RefCounted
const RouteGraph = preload("res://scripts/sim/route_graph.gd")

func load_seed(seed: Dictionary) -> bool:
    if not (seed.get("worlds", null) is Array) or not (seed.get("factions", null) is Array):
        return false
    var staged: Dictionary = {}
    var counts: Dictionary = {}
    for faction in seed["factions"]:
        if not _put(staged, "faction", str(faction.get("id", "")), "", faction):
            return false
    for world in seed["worlds"]:
        if not (world is Dictionary):
            return false
        var system: Dictionary = world.get("system", {})
        var sid: String = str(system.get("id", ""))
        if not _put(staged, "system", sid, sid, system):
            return false
        for spec in [
            ["body", "bodies"], ["facility", "facilities"],
            ["market", "markets"], ["population", "populations"],
            ["ship", "ships"], ["nav_site", "nav_sites"]
        ]:
            var kind: String = spec[0]
            var field: String = spec[1]
            var values: Variant = world.get(field, null)
            if not (values is Array):
                return false
            for i in range(values.size()):
                var value: Variant = values[i]
                if not (value is Dictionary):
                    return false
                var native_id: String = str(value.get("id", ""))
                # Population, ship and nav site have no native ID in 0.6.7.
                # Explicitly namespace ordinals so they cannot collide with IDs.
                var key: String = native_id
                if key.is_empty():
                    key = "@%s/%d" % [sid, i]
                if not _put(staged, kind, key, sid, value):
                    return false
    var graph = RouteGraph.new()
    if not graph.load_worlds(seed["worlds"]):
        return false
    for key in staged:
        var kind: String = staged[key]["kind"]
        counts[kind] = int(counts.get(kind, 0)) + 1
    _entities = staged
    _counts = counts
    _route_graph = graph
    return true

func _put(target: Dictionary, kind: String, key: String, sid: String, value: Dictionary) -> bool:
    if key.is_empty():
        return false
    var compound: String = kind + ":" + key
    if target.has(compound):
        return false
    target[compound] = {"kind": kind, "key": key, "system_id": sid,
        "value": value.duplicate(true)}
    return true

func get_entity(kind: String, key: String) -> Dictionary:
    return _entities.get(kind + ":" + key, {}).duplicate(true)

func keys_for(kind: String) -> PackedStringArray:
    var result := PackedStringArray()
    for compound in _entities:
        if _entities[compound]["kind"] == kind:
            result.append(str(_entities[compound]["key"]))
    result.sort()
    return result

func counts() -> Dictionary:
    return _counts.duplicate(true)

func graph() -> RefCounted:
    return _route_graph

func snapshot() -> Dictionary:
    # Stable canonical keys independent of Dictionary insertion order.
    var entries: Array = []
    var keys: Array = _entities.keys()
    keys.sort()
    for key in keys:
        entries.append({"id": key, "entity": _entities[key].duplicate(true)})
    return {"schema": 1, "entities": entries, "routes": _route_graph.snapshot() if _route_graph != null else {}}
