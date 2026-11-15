extends SceneTree
const Gate = preload("res://scripts/sim/n75_construction_delivery.gd")
func _initialize() -> void:
	var site := {"commodity": "metals", "location": "port", "progress_delivered": 400, "progress_required": 600, "labor": {"required": 150, "completed": 149}}
	assert(Gate.delivery(site, "metals", "port", 200, "r1", {}).ok)
	assert(Gate.delivery(site, "metals", "port", 201, "r1", {}).reason == "exceeds_material_requirement")
	assert(Gate.delivery(site, "metals", "port", 200, "r1", {"r1": true}).reason == "duplicate_or_missing_receipt")
	assert(Gate.delivery(site, "water", "port", 1, "r2", {}).reason == "wrong_site")
	assert(not Gate.completion_ready(site))
	site.progress_delivered = 600
	site.labor.completed = 150
	assert(Gate.completion_ready(site))
	quit(0)
