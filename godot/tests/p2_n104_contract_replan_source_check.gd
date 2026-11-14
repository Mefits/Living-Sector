extends RefCounted
## DEFERRED N104/Rust ReleaseContract + resume_contract_bt source tests.
## No fake goods, money, payment receipts, or actual Godot run claimed.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Release = preload("res://scripts/sim/phase2/unified_n104_release_stage.gd")
const Resume = preload("res://scripts/sim/phase2/unified_n104_contract_resume.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

class Graph:
    extends RefCounted
    var edges: Dictionary = {
        "source": [{"to": "destination", "distance": 3.0}],
        "destination": [{"to": "source", "distance": 3.0}]}
    func has_location(n: String) -> bool:
        return edges.has(n)
    func outgoing(n: String) -> Array:
        return edges.get(n, []).duplicate(true)
    func shortest_path(a: String, z: String) -> Dictionary:
        if not has_location(a) or not has_location(z):
            return {"reachable": false}
        if a == z:
            return {"reachable": true, "locations": [a], "distance": 0.0}
        for e in outgoing(a):
            if str(e.get("to", "")) == z:
                return {"reachable": true, "locations": [a, z],
                    "distance": float(e["distance"])}
        return {"reachable": false}

static func fixture(status: String = "accepted") -> Dictionary:
    return {"ship_next_token": 1,
        "ships": {"ship-a": {"id": "ship-a", "class": "trader",
            "faction_id": "red", "location": "destination",
            "docked_at": "", "transit": {},
            "active_contract_id": "contract-a",
            "current_goal": "fulfill_delivery",
            "current_goal_score": 1.0,
            "current_bt": Bt.sequence([Bt.action({"kind": "Dock"})]),
            "dock_attempt_start_tick": 1,
            "cargo": {"Ore": 2} if status == "picked_up" else {},
            "fuel": 95.0, "fuel_capacity": 100.0, "credits": 5000,
            "crew": {"morale": 70.0},
            "faction_reputation": {"blue": 90},
            "transaction": {"sequence": 0, "pending": {},
                "last_acknowledgment": {}}}},
        "contract_board": {"version": 1, "receipt_claims": {},
            "contracts": {"contract-a": {
                "id": "contract-a", "contract_type": "delivery",
                "status": status, "fulfiller_id": "ship-a",
                "requestor_id": "facility-1", "faction_id": "blue",
                "commodity": "Ore", "quantity": 2,
                "source_location": "source",
                "destination_location": "destination",
                "payment": 5000, "reserved": 5000,
                "agreed_payment": 5000, "accepted_at_tick": 1,
                "escrow_account": "escrow:contract-a"}}},
        "escrow_balances": {"escrow:contract-a": 5000},
        "faction_relations": {}}

static func run_checks() -> Dictionary:
    var graph := Graph.new()
    var initial: Dictionary = fixture()
    var source: Dictionary = N84.propose(initial, graph, {}, 151, 1.0, 1)
    if not source.get("ok", false) or source.get("commands", []).size() != 1:
        return {"ok": false, "reason": "n104_no_single_n146_release"}
    var command: Dictionary = source["commands"][0]
    if command.get("kind") != "ReleaseContract" or (
            command.get("contract_id") != "contract-a" or
            command.get("ship_id") != "ship-a" or
            command.get("reason") != "bt_failure"):
        return {"ok": false, "reason": "n104_wrong_original_release_command"}
    if initial["ships"]["ship-a"]["current_bt"] == null or (
            initial["contract_board"]["contracts"]["contract-a"]["status"] != "accepted"):
        return {"ok": false, "reason": "n104_proposal_mutated_authority"}
    var stage: Dictionary = initial.duplicate(true)
    stage["ships"] = source["ships"]
    var apply: Dictionary = Release.stage(
        stage, 151, "ship-a", "contract-a", "bt_failure")
    if not apply.get("ok", false) or not apply.get("changed", false):
        return {"ok": false, "reason": "n104_guarded_source_release_rejected"}
    var changed: Dictionary = apply["world"]
    if changed["contract_board"]["contracts"]["contract-a"]["status"] != "posted" or (
            changed["contract_board"]["contracts"]["contract-a"]["fulfiller_id"] != ""):
        return {"ok": false, "reason": "n104_accepted_not_returned_to_source_board"}
    if changed["ships"]["ship-a"]["active_contract_id"] != "" or (
            changed["ships"]["ship-a"]["faction_reputation"]["blue"] != 75):
        return {"ok": false, "reason": "n104_missing_rust_breach_penalty"}
    if changed["escrow_balances"] != initial["escrow_balances"] or (
            changed["contract_board"]["receipt_claims"] != {} or
            changed["ships"]["ship-a"]["credits"] != 5000):
        return {"ok": false, "reason": "n104_release_minted_or_refunded_escrow"}
    if Release.stage(changed, 151, "ship-a",
            "contract-a", "bt_failure").get("changed", false):
        return {"ok": false, "reason": "n104_duplicate_source_release"}
    var wrong: Dictionary = stage.duplicate(true)
    wrong["contract_board"]["contracts"]["contract-a"]["fulfiller_id"] = "ship-b"
    if Release.stage(wrong, 151, "ship-a",
            "contract-a", "bt_failure").get("changed", false):
        return {"ok": false, "reason": "n104_loser_unseated_original_winner"}
    var loaded: Dictionary = fixture("picked_up")
    if Release.stage(loaded, 151, "ship-a",
            "contract-a", "bt_failure").get("changed", false):
        return {"ok": false, "reason": "n104_rereleased_pickedup_cargo"}
    var resumed: Dictionary = N84.propose(loaded, graph, {}, 151, 1.0, 1)
    if not resumed.get("ok", false) or (
            not resumed.get("commands", []).is_empty()):
        return {"ok": false, "reason": "n104_pickedup_emitted_phantom_release"}
    var ship: Dictionary = resumed.get("ships", {}).get("ship-a", {})
    var plan: Dictionary = ship.get("current_bt", {})
    if plan.is_empty() or not Bt.validate(plan) or (
            str(ship.get("active_contract_id", "")) != "contract-a" or
            str(ship.get("planning_source", "")) != "n104_original_n81_pickedup_resume"):
        return {"ok": false, "reason": "n104_no_real_loaded_goap_resume"}
    var kinds: Array = []
    for step in plan.get("children", []):
        kinds.append(str(step.get("action", {}).get("kind", "")))
    if kinds.has("AcceptContract") or kinds.has("Buy") or not (
            kinds.has("DeliverCargo")):
        return {"ok": false, "reason": "n104_resumed_with_second_purchase"}
    if ship["cargo"].get("Ore", -1) != 2 or loaded[
            "contract_board"]["contracts"]["contract-a"]["status"] != "picked_up":
        return {"ok": false, "reason": "n104_replan_modified_real_cargo_or_board"}
    var no_cargo: Dictionary = fixture("picked_up")
    no_cargo["ships"]["ship-a"]["cargo"] = {}
    if Resume.propose(no_cargo["ships"]["ship-a"],
            no_cargo["contract_board"]["contracts"]["contract-a"],
            graph).get("ok", false):
        return {"ok": false, "reason": "n104_resume_invented_missing_paid_cargo"}
    var missing_route := Graph.new()
    missing_route.edges["destination"] = []
    if Resume.propose(loaded["ships"]["ship-a"],
            loaded["contract_board"]["contracts"]["contract-a"],
            missing_route).get("ok", false):
        return {"ok": false, "reason": "n104_replan_invented_interstellar_leg"}
    return {"ok": true, "status": "DEFERRED_SOURCE_FIXTURE_NOT_RUN"}
