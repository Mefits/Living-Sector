extends RefCounted
## Deferred P2 N80 source proof; NOT run until whole Rust->Godot port.
const Stage = preload("res://scripts/sim/phase2/unified_n80_ship_exploration_stage.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")

class FakeResolver:
    extends RefCounted
    func system_for_location(location: String) -> String:
        return str({"sol-dock": "sol", "sol-gate": "sol",
            "alpha-gate": "alpha", "alpha-dock": "alpha"}.get(location, ""))
    func system_for_body(body: String) -> String:
        return str({"sol-body": "sol", "alpha-body": "alpha"}.get(body, ""))

class FakeGraph:
    extends RefCounted
    var edges: Dictionary = {
        "sol-dock": [{"to": "sol-gate", "distance": 3.0}],
        "sol-gate": [], "alpha-gate": [
            {"to": "alpha-dock", "distance": 2.0}], "alpha-dock": []}
    func has_location(location: String) -> bool:
        return edges.has(location)
    func outgoing(location: String) -> Array:
        return edges.get(location, [])
    func shortest_path(start: String, finish: String) -> Dictionary:
        if not has_location(start) or not has_location(finish):
            return {"reachable": false}
        if start == finish:
            return {"reachable": true, "locations": [start], "distance": 0.0}
        for edge in outgoing(start):
            if str(edge["to"]) == finish:
                return {"reachable": true, "locations": [start, finish],
                    "distance": float(edge["distance"])}
        return {"reachable": false}

static func fixture() -> Dictionary:
    return {"ship_next_token": 1, "facilities": {
        "sol-gate-id": {"type": "gate", "body_id": "sol-body",
            "location": "sol-gate", "abandoned": false,
            "gate_link": {"paired_gate_id": "alpha-gate-id",
                "fee_flat": 200, "fee_per_cargo_unit": 2}},
        "alpha-gate-id": {"type": "gate", "body_id": "alpha-body",
            "location": "alpha-gate", "abandoned": false,
            "gate_link": {"paired_gate_id": "sol-gate-id",
                "fee_flat": 200, "fee_per_cargo_unit": 2}},
        "sol-station": {"type": "station", "body_id": "sol-body",
            "location": "sol-dock", "abandoned": false,
            "docking_capacity": 3},
        "alpha-station": {"type": "station", "body_id": "alpha-body",
            "location": "alpha-dock", "abandoned": false,
            "docking_capacity": 2}},
        "markets": {"sol-dock": {"owner": "sol-station"},
            "alpha-dock": {"owner": "alpha-station"}},
        "ships": {"ship-a": {
            "id": "ship-a", "location": "sol-dock", "system_id": "sol",
            "class": "trader", "current_goal": "idle",
            "current_bt": null, "active_contract_id": "", "transit": {},
            "docked_at": "sol-station", "credits": 5000,
            "fuel_capacity": 100.0, "fuel": 90.0,
            "cargo": {}, "cargo_capacity": 80,
            "crew": {"morale": 70.0},
            "personality": Personality.for_class("trader"),
            "lifecycle": {"idle_ticks": 10000},
            "memory": {"recent_systems": [], "visited": [],
                "price_knowledge": {}, "route_performance": {},
                "contract_rejections": {}}}}}

static func real_positions() -> Dictionary:
    return {"sol-dock": Vector2(0.0, 0.0),
        "sol-gate": Vector2(0.1, 0.0),
        "alpha-gate": Vector2(1.0, 0.0),
        "alpha-dock": Vector2(1.1, 0.0)}

static func run_checks() -> Dictionary:
    var original: Dictionary = fixture()
    var graph := FakeGraph.new()
    var resolver := FakeResolver.new()
    var accepted: Dictionary = Stage.stage(original, graph, resolver,
        12000, {"ship-a": 1}, real_positions(), 1.0)
    if not accepted.get("ok", false) or not accepted.get("changed", false):
        return {"ok": false, "reason": "n80_did_not_recover_real_idle_gate_plan"}
    if original["ships"]["ship-a"]["current_bt"] != null or (
            str(original["ships"]["ship-a"]["current_goal"]) != "idle"):
        return {"ok": false, "reason": "n80_mutated_original_world"}
    var selected: Dictionary = accepted["ships"]["ship-a"]
    var tree: Dictionary = selected.get("current_bt", {})
    if str(selected.get("current_goal", "")) != "explore" or (
            not BT.validate(tree) or BT.current_action(tree) != "Undock"):
        return {"ok": false, "reason": "n80_missing_persistent_rust_explore_bt"}
    var actions: Array = []
    for node in tree.get("children", []):
        actions.append(str(node.get("action", {}).get("kind", "")))
    if actions != ["Undock", "Travel", "GateJump", "Travel",
            "Dock", "DockDwell", "Undock"]:
        return {"ok": false, "reason": "n80_missing_rust_gate_dock_sequence"}
    var gate_step: Dictionary = tree["children"][2]["action"]
    if gate_step.get("src_gate", "") != "sol-gate" or (
            gate_step.get("dest_gate", "") != "alpha-gate"):
        return {"ok": false, "reason": "n80_fake_navigation_edge"}
    var shared_dock: Dictionary = fixture()
    shared_dock["facilities"]["alpha-station"]["location"] = "alpha-gate"
    shared_dock["markets"].erase("alpha-dock")
    shared_dock["markets"]["alpha-gate"] = {"owner": "alpha-station"}
    var same_endpoint: Dictionary = Stage.stage(shared_dock, graph, resolver,
        12000, {"ship-a": 1}, real_positions(), 1.0)
    if not same_endpoint.get("changed", false):
        return {"ok": false, "reason": "n80_rejected_real_market_at_gate_location"}
    var same_bt: Dictionary = same_endpoint["ships"]["ship-a"]["current_bt"]
    var kinds: Array = []
    for node in same_bt.get("children", []):
        kinds.append(str(node.get("action", {}).get("kind", "")))
    if kinds != ["Undock", "Travel", "GateJump", "Dock",
            "DockDwell", "Undock"]:
        return {"ok": false, "reason": "n80_shared_gate_market_route_invalid"}
    var no_pair: Dictionary = fixture()
    no_pair["facilities"]["sol-gate-id"].erase("gate_link")
    if Stage.stage(no_pair, graph, resolver, 12000, {
            "ship-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n80_ghost_gate_exploration"}
    var poor: Dictionary = fixture()
    poor["ships"]["ship-a"]["credits"] = 100
    if Stage.stage(poor, graph, resolver, 12000, {
            "ship-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n80_unfunded_gate"}
    var no_route := FakeGraph.new()
    no_route.edges["sol-dock"] = []
    if Stage.stage(fixture(), no_route, resolver, 12000, {
            "ship-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n80_unreachable_gate"}
    if Stage.stage(fixture(), graph, resolver, 12000, {}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n80_sleeping_ship_woke_up"}
    return {"ok": true, "status": "DEFERRED_SOURCE_FIXTURE_NOT_RUN"}
