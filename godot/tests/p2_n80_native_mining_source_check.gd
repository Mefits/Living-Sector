extends RefCounted
## Deferred N103/N80 paid-mining selector fixture. NOT RUN until
## the full Rust -> Godot code integration is complete.
const Source = preload("res://scripts/sim/phase2/unified_n80_ship_mining_stage.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

class FakeResolver:
    extends RefCounted
    func system_for_location(location: String) -> String:
        return str({"ice-dock": "sol", "ice-field": "sol"}.get(location, ""))
    func body_for_location(location: String) -> String:
        return str({"ice-dock": "depot-body",
            "ice-field": "ice-body"}.get(location, ""))

class FakeGraph:
    extends RefCounted
    var edges: Dictionary = {
        "ice-dock": [{"to": "ice-field", "distance": 2.0}],
        "ice-field": [{"to": "ice-dock", "distance": 2.0}]}
    func has_location(loc: String) -> bool:
        return edges.has(loc)
    func outgoing(loc: String) -> Array:
        return edges.get(loc, []).duplicate(true)
    func shortest_path(start: String, finish: String) -> Dictionary:
        if not has_location(start) or not has_location(finish):
            return {"reachable": false}
        if start == finish:
            return {"reachable": true, "locations": [start], "distance": 0.0}
        for edge in outgoing(start):
            if str(edge.get("to", "")) == finish:
                return {"reachable": true, "locations": [start, finish],
                    "distance": edge["distance"]}
        return {"reachable": false}
    func snapshot() -> Dictionary:
        var result: Array = []
        for start in edges:
            for edge in edges[start]:
                result.append({"from": str(start), "to": str(edge["to"]),
                    "distance": edge["distance"]})
        return {"edges": result}

static func fixture() -> Dictionary:
    return {"bodies": {
            "depot-body": {"resources": {"ice": 0.0}},
            "ice-body": {"resources": {"ice": 0.1}}},
        "markets": {"ice-dock": {"owner": "real-depot",
            "prices": {"ice": 100.0, "fuel": 2.0}}},
        "facilities": {"real-depot": {
            "location": "ice-dock", "type": "station",
            "faction": "colony", "credits": 100000,
            "docking_capacity": 4, "abandoned": false}},
        "ship_next_token": 1,
        "ships": {"miner-a": {
            "id": "miner-a", "class": "miner", "size": "medium",
            "faction_id": "colony", "location": "ice-dock",
            "system_id": "sol", "current_goal": "idle",
            "current_bt": null, "active_contract_id": "",
            "transit": {}, "docked_at": "real-depot",
            "credits": 5000, "fuel": 100.0, "fuel_capacity": 100.0,
            "cargo": {}, "cargo_capacity": 50,
            "crew": {"morale": 80.0},
            "personality": Personality.for_class("miner"),
            "memory": {"price_knowledge": {"ice-dock": {
                "ice": {"price": 100.0, "tick": 1},
                "fuel": {"price": 2.0, "tick": 1}}},
                "visited": [], "recent_systems": []}}}}

static func real_positions() -> Dictionary:
    return {"ice-dock": Vector2(0.0, 0.0),
        "ice-field": Vector2(0.1, 0.0)}

static func run_checks() -> Dictionary:
    var world: Dictionary = fixture()
    var graph := FakeGraph.new()
    var resolver := FakeResolver.new()
    var result: Dictionary = Source.stage(world, graph, resolver,
        500, {"miner-a": 1}, real_positions(), 1.0)
    if not result.get("ok", false) or not result.get("changed", false):
        return {"ok": false, "reason": "n103_original_ice_candidate_not_found"}
    if world["ships"]["miner-a"]["current_bt"] != null:
        return {"ok": false, "reason": "n103_source_mutated_live_world"}
    var ship: Dictionary = result["ships"]["miner-a"]
    var tree: Dictionary = ship.get("current_bt", {})
    if str(ship.get("current_goal", "")) != "mine" or not BT.validate(tree):
        return {"ok": false, "reason": "n103_missing_rust_mine_bt"}
    var actions: Array = []
    for node in tree.get("children", []):
        actions.append(str(node.get("action", {}).get("kind", "")))
    if actions != ["Undock", "Travel", "Mine", "Travel",
            "Dock", "Sell", "Undock"]:
        return {"ok": false, "reason": "n103_ghost_mining_or_missing_sell_chain"}
    if str(tree["children"][2]["action"].get("body_id", "")) != "ice-body":
        return {"ok": false, "reason": "n103_wrong_source_deposit"}
    var depleted: Dictionary = fixture()
    depleted["bodies"]["ice-body"]["resources"]["ice"] = 0.0
    if Source.stage(depleted, graph, resolver, 500, {
            "miner-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n103_free_ice_when_depleted"}
    var insolvent: Dictionary = fixture()
    insolvent["facilities"]["real-depot"]["credits"] = 0
    if Source.stage(insolvent, graph, resolver, 500, {
            "miner-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n103_unpaid_mining_buyer"}
    var unknown: Dictionary = fixture()
    unknown["ships"]["miner-a"]["memory"]["price_knowledge"] = {}
    if Source.stage(unknown, graph, resolver, 500, {
            "miner-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n103_invented_market_quotes"}
    var severed := FakeGraph.new()
    severed.edges["ice-field"] = []
    if Source.stage(fixture(), severed, resolver, 500, {
            "miner-a": 1}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n103_one_way_delivery_was_accepted"}
    if Source.stage(fixture(), graph, resolver, 500, {}, real_positions(), 1.0).get("changed", false):
        return {"ok": false, "reason": "n103_woke_sleeping_n140_ship"}
    return {"ok": true, "status": "DEFERRED_SOURCE_FIXTURE_NOT_RUN"}
