extends SceneTree
const Gate = preload("res://scripts/sim/strategy/research_gate.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
    if not ok:
        failures.append(message)
func _initialize() -> void:
    var g = Gate.new()
    check(g.TECHNOLOGIES.size() == 12, "Rust director technology count")
    check(g.next_technology("automation", []).get("next") == "industrial_methods", "first prerequisite")
    check(g.next_technology("automation", ["industrial_methods"]).get("next") == "automation", "second step")
    check(g.next_technology("automation", ["industrial_methods","automation"]).get("next") == "", "completed")
    check(g.next_technology("not_real", []).get("reason") == "unknown_technology", "unknown fail closed")
    check(g.next_technology("structuretech3", []).get("next") == "industrial_methods", "deep chain")
    check(g.mandate_valid("automation",260,10000,0) == "", "valid mandate")
    check(g.mandate_valid("automation",99,10000,0) == "invalid_mandate_budget", "minimum budget")
    check(g.spending_gate(260,10000,200,61,20000) == "player_mandate_budget_exhausted", "budget")
    check(g.spending_gate(260,10000,0,100,10050) == "player_mandate_treasury_floor", "reserve")
    check(g.spending_gate(260,10000,0,100,10200) == "", "allowed")
    check(g.tier_upgrade_gate("t1","t2",["structuretech2"]), "tier2 gate")
    check(not g.tier_upgrade_gate("t1","t3",["structuretech3"]), "no tier skip")
    check(g.slot_availability("t1",3,1).get("remaining") == 0, "construction occupies slot")
    check(not g.slot_availability("t2",-1,0).get("ok"), "invalid counts")
    if failures.is_empty():
        print("N44 PASS: read-only Rust research gates")
        quit(0)
    else:
        for failure in failures:
            push_error("N44 FAIL: " + failure)
        quit(1)
