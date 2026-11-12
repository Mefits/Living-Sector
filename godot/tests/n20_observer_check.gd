extends SceneTree
const Projection = preload("res://scripts/sim/observer/observer_projection.gd")

func _initialize() -> void:
    var head := {"ok": true, "tick": 42, "faction_id": "genesis",
        "selected_option": "supply", "selected_target": "mars|food",
        "reason": "survival_first", "spending_limit": 7000,
        "planned_spend": 3000, "committed_spend": 0,
        "alternatives": [
            {"action": "expand", "target": "jupiter", "ready": false,
             "reason": "survival_first", "cost": 9000, "score": 90.0},
            {"action": "supply", "target": "mars|food", "ready": true,
             "reason": "ready", "cost": 3000, "score": 80.0}]}
    var state := {"head": head, "policies": {"logistics": "advise", "construction": "delegate"},
        "stations": [{"faction_id": "genesis", "observed_tick": 42, "location": "Mars",
            "workforce": 60, "assigned_workers": 12,
            "modules": [{"facility_id": "farm", "assigned_workers": 12,
                "actual_workers": 0, "execution_reason": "not_executed"}]},
            {"faction_id": "other", "observed_tick": 42, "location": "Earth"}],
        "contracts": [{"faction_id": "genesis", "observed_tick": 42,
            "id": "contract-8", "status": "delivered",
            "cargo_delivered": true, "paid": false}]}
    var before := state.duplicate(true)
    var view: Dictionary = Projection.build(42, "genesis", state)
    assert(view["ok"])
    assert(view["head"]["selected"] == "supply")
    assert(view["head"]["committed_spend"] == 0)
    assert(not view["head"]["alternatives"][0]["ready"])
    assert(view["stations"].size() == 1)
    assert(view["stations"][0]["modules"][0]["actual"] == 0)
    assert(view["contracts"][0]["paid"] == false)
    assert(not view["production"]["available"])
    assert(not view["commands"][0]["enabled"])
    assert(view["commands"][0]["mode"] == "advise")
    assert(state == before)
    var stale: Dictionary = Projection.build(43, "genesis", state)
    assert(not stale["head"]["available"])
    assert(stale["stations"].is_empty() and stale["contracts"].is_empty())
    var report: String = Projection.describe(view)
    assert(report.contains("survival_first"))
    assert(report.contains("not_executed"))
    assert(report.contains("команды недоступны"))
    assert(Projection.describe(view) == report)
    print("N20_OBSERVER_CHECK_OK")
    quit(0)
