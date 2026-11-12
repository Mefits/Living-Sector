extends SceneTree
const Head = preload("res://scripts/sim/strategy/faction_head.gd")

func _initialize() -> void:
    var head: RefCounted = Head.new()
    var faction: Dictionary = {"id": "genesis", "treasury": 12000, "crisis": false,
        "proposals": [
            {"action": "research", "target": "lab_t2", "score": 20.0, "ready": true, "cost": 2000},
            {"action": "supply", "target": "mars|food", "score": 80.0, "ready": true, "cost": 3000, "essential": true},
            {"action": "expand", "target": "jupiter", "score": 90.0, "ready": true, "cost": 9000}]}
    var first: Dictionary = head.decide(10, faction)
    assert(first["selected_option"] == "supply")
    assert(first["spending_limit"] == 7000)
    assert(first["committed_spend"] == 0)
    assert(head.authorized(first, 10, "genesis", "supply", "mars|food", 3000))
    assert(not head.authorized(first, 10, "genesis", "expand", "jupiter", 1))
    assert(not head.authorized(first, 11, "genesis", "supply", "mars|food", 1))
    assert(head.decide(10, faction) == first)
    var cash_before: int = faction["treasury"]
    assert(cash_before == 12000) # head does not transfer credits
    faction["proposals"][0]["score"] = 150.0
    var hold: Dictionary = head.decide(11, faction)
    assert(hold["selected_option"] == "supply")
    assert(hold["reason"] == "strategy_hysteresis")
    var switched: Dictionary = head.decide(12, faction)
    assert(switched["selected_option"] == "research")
    assert(switched["reason"] == "strategy_switch_confirmed")
    faction["active_native_plan"] = true
    var locked: Dictionary = head.decide(13, faction)
    assert(locked["selected_option"] == "wait")
    assert(locked["grant"].is_empty())
    faction["active_native_plan"] = false
    faction["crisis"] = true
    var survival: Dictionary = head.decide(14, faction)
    assert(survival["selected_option"] == "supply")
    assert(survival["reason"] == "survival_first")
    var save: Dictionary = head.snapshot()
    var restored: RefCounted = Head.new()
    assert(restored.restore(save))
    assert(restored.decide(14, faction) == survival)
    assert(not restored.decide(13, faction)["ok"])
    var denied: Dictionary = faction.duplicate(true)
    denied["crisis"] = false
    denied["proposals"] = [{"action": "supply", "target": "earth|water",
        "score": 200.0, "ready": true, "cost": 0, "mandate_mode": "advise"}]
    var advice: Dictionary = Head.new().decide(1, denied)
    assert(advice["selected_option"] == "wait")
    assert(advice["alternatives"][0]["reason"] == "policy_not_delegated")
    print("N19_HEAD_CHECK_OK")
    quit(0)
