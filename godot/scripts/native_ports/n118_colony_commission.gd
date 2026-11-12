extends RefCounted
## Port of strategy/colony.rs commission. Pure proposal; caller owns atomic ECS/board commit.
const MATERIAL_REQUIRED := 600
const PROJECT_TAG := "strategy.colony.v1"

static func commission(plan: Dictionary, world: Dictionary, tick: int, multiplier: int, floor_credits: int, lifespan_base: int) -> Dictionary:
	var faction_id := str(plan.get("faction_id", ""))
	var destination := str(plan.get("destination", ""))
	var body_id := str(plan.get("body_id", ""))
	var site_id := str(plan.get("site_id", ""))
	var sites: Dictionary = world.get("sites", {})
	var treasury: Dictionary = world.get("treasuries", {})
	if faction_id.is_empty() or destination.is_empty() or body_id.is_empty():
		return {"ok": false, "reason": "invalid_colony_plan"}
	if not treasury.has(faction_id):
		return {"ok": false, "reason": "missing_faction"}
	if site_id.is_empty():
		for site in sites.values():
			if str(site.get("body_id", "")) == body_id and not bool(site.get("completed", false)):
				return {"ok": false, "reason": "site_already_exists"}
		var bodies: Dictionary = world.get("bodies", {})
		if not bodies.has(body_id) or not bodies[body_id].has("position"):
			return {"ok": false, "reason": "missing_body_position"}
		var new_id := "site-station-%s-%d" % [destination, tick]
		if sites.has(new_id):
			return {"ok": false, "reason": "duplicate_site"}
		return {"ok": true, "kind": "create_site", "site": {
			"id": new_id, "name": str(plan.get("body_name", body_id)) + " Colony",
			"facility_type": "station", "faction_id": faction_id, "body_id": body_id,
			"location_name": destination, "commodity": "metals",
			"progress_delivered": 0, "progress_required": MATERIAL_REQUIRED,
			"position": bodies[body_id]["position"], "spawned_at_tick": tick,
			"completed": false, "dirty": true,
			"labor": {"colony_source": str(plan.get("source", ""))}},
			"debit": 0, "event": "colony_approved"}
	if not sites.has(site_id) or bool(sites[site_id].get("completed", false)):
		return {"ok": false, "reason": "missing_active_site"}
	var cost := int(plan.get("cost", -1))
	if cost < 0 or int(treasury[faction_id]) - floor_credits < cost:
		return {"ok": false, "reason": "insufficient_colony_budget"}
	var distance := maxi(0, int(plan.get("shortest_distance", 0)))
	var lifespan := maxi(lifespan_base, distance * 100 + 1200) * maxi(1, multiplier)
	var passenger := bool(plan.get("passenger", false))
	var quantity := int(plan.get("quantity", 0))
	if quantity <= 0:
		return {"ok": false, "reason": "empty_delivery"}
	return {"ok": true, "kind": "post_prepaid_contract",
		"contract_type": "passenger" if passenger else "construction",
		"commodity": "" if passenger else "metals", "quantity": quantity,
		"source": str(plan.get("source", "")), "destination": destination,
		"faction_id": faction_id, "funding_source": "Faction",
		"mission_category": PROJECT_TAG, "debit": cost, "lifespan": lifespan,
		"tick": tick, "site_id": site_id}
