extends SceneTree
const Gate = preload("res://scripts/sim/n76_research_progress.gd")
func _initialize() -> void:
	var c := {"faction_id": "civ", "research": "industrial_methods", "progress": 30, "research_required": 40, "last_research_tick": 4, "crisis": false}
	var r := {"id": "shift5", "paid": true, "electronics_debited": true, "workers": 10, "tick": 5, "faction_id": "civ"}
	assert(Gate.admit(c, 5, r).completed)
	assert(Gate.admit(c, 5, {"paid": false}).reason == "unverified_paid_shift")
	c.last_research_tick = 5
	assert(Gate.admit(c, 5, r).reason == "already_researched")
	c.last_research_tick = 4
	c.crisis = true
	assert(Gate.admit(c, 5, r).reason == "survival_first")
	quit(0)
