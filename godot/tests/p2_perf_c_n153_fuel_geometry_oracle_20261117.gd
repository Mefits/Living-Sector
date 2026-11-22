extends RefCounted
## N153 per-proposal fuel geometry cache vs uncached oracle.
const Dispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")

class GraphStub:
    extends RefCounted
    var calls: int = 0
    func has_location(_name: String) -> bool:
        return true
    func shortest_path(from_id: String, to_id: String) -> Dictionary:
        calls += 1
        return {"reachable": true, "locations": [from_id, to_id]}

static func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
    assert(actual == expected, label + ": actual=" + str(actual) + " expected=" + str(expected))

static func run() -> Dictionary:
    var graph := GraphStub.new()
    var positions := {"A": Vector2(0, 0), "B": Vector2(100, 0), "C": Vector2(200, 0)}
    var world := {"ships": {}, "facilities": {}}
    var contract := {"quantity": 1, "source_location": "B", "destination_location": "C"}
    var shared := {}
    var ids := ["one", "two", "low_fuel", "slow"]
    for id in ids:
        world["ships"][id] = {"location": "A", "active_contract_id": "", "transit": {},
            "docked_at": "", "cargo": {}, "cargo_capacity": 10,
            "class": "small_transport", "speed_modifier": 1.0, "fuel": 1000000.0}
    world["ships"]["low_fuel"]["fuel"] = 0.001
    world["ships"]["slow"]["speed_modifier"] = 0.5
    var results := {}
    for id in ids:
        var optimized: Dictionary = Dispatch._ready_ship(world, id, contract, graph,
            positions, graph, 1.0, shared)
        var oracle: Dictionary = Dispatch._ready_ship(world, id, contract, graph,
            positions, graph, 1.0, {})
        _assert_equal(optimized, oracle, "cached vs uncached " + id)
        results[id] = optimized
    assert(shared.has(-1), "expected proposal-local fuel cache")
    assert((shared[-1] as Dictionary).size() == 2, "speed variants must not alias")
    _assert_equal(results["low_fuel"].get("reason", ""), "insufficient_native_full_route_fuel",
        "paid fuel cannot be bypassed")
    # A new proposal must not reuse geometry after world positions change.
    positions["C"] = Vector2(200000, 0)
    var new_proposal: Dictionary = Dispatch._ready_ship(world, "one", contract,
        graph, positions, graph, 1.0, {})
    var new_oracle: Dictionary = Dispatch._ready_ship(world, "one", contract,
        graph, positions, graph, 1.0, {})
    _assert_equal(new_proposal, new_oracle, "position invalidation")
    # Cargo and contract guards must execute before any cached fuel result.
    world["ships"]["one"]["cargo"] = {"ore": 1}
    _assert_equal(Dispatch._ready_ship(world, "one", contract, graph, positions,
        graph, 1.0, shared).get("reason", ""), "ship_cargo_not_empty", "cargo guard")
    world["ships"]["one"]["cargo"] = {}
    world["ships"]["one"]["active_contract_id"] = "paid-123"
    _assert_equal(Dispatch._ready_ship(world, "one", contract, graph, positions,
        graph, 1.0, shared).get("reason", ""), "ship_busy", "paid contract guard")
    return {"ok": true, "cases": ids.size()}
