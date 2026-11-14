extends RefCounted
## Rust: agents/construction/executor.rs. Pure decisions; never awards construction progress.

static func utility(loyalty: float) -> float:
	return 20.0 + 30.0 * clampf(loyalty, 0.0, 1.0)

static func capable(ship_class: String, class_catalogue: Dictionary) -> bool:
	if not class_catalogue.has(ship_class):
		return false
	var roles: Array = class_catalogue[ship_class].get("crew_roles", [])
	return roles.has("engineer")

static func target(tree: Dictionary) -> String:
	match str(tree.get("kind", "")):
		"action":
			var action: Variant = tree.get("action", "")
			if action is Dictionary and str(action.get("kind", "")) == "Construct":
				return str(action.get("site_id", ""))
			if action == "construct":
				return str(tree.get("site_id", ""))
		"sequence":
			for child in tree.get("children", []):
				var found := target(child)
				if not found.is_empty():
					return found
	return ""

static func active(tree: Dictionary) -> String:
	match str(tree.get("kind", "")):
		"action":
			var action: Variant = tree.get("action", "")
			if action is Dictionary and str(action.get("kind", "")) == "Construct":
				return str(action.get("site_id", ""))
			if action == "construct":
				return str(tree.get("site_id", ""))
		"sequence":
			var children: Array = tree.get("children", [])
			var index: int = int(tree.get("index", 0))
			if index >= 0 and index < children.size():
				return active(children[index])
	return ""

static func offers(sites: Array, ships: Array, class_catalogue: Dictionary, executing: bool) -> Array:
	var claims := {}
	for ship in ships:
		if ship.get("current_goal", "") != "construct" or not capable(str(ship.get("class", "")), class_catalogue):
			continue
		var site_id := target(ship.get("bt", {}))
		if site_id.is_empty():
			continue
		var ship_id := str(ship.get("id", ""))
		if not claims.has(site_id) or ship_id < str(claims[site_id]):
			claims[site_id] = ship_id
	var result := []
	for site in sites:
		if site.get("completed", false) or int(site.get("remaining_material", -1)) != 0:
			continue
		if int(site.get("labor_completed", 0)) >= int(site.get("labor_required", 0)):
			continue
		var order: Dictionary = site.get("station_order", {})
		if executing and str(order.get("executor_id", "")).is_empty():
			continue
		var site_id := str(site.get("id", ""))
		result.append({"site_id":site_id, "location":str(site.get("location", "")),
			"faction":str(site.get("faction", "")),
			"claimed_by":str(order.get("executor_id", claims.get(site_id, "")))})
	result.sort_custom(func(a, b): return a["site_id"] < b["site_id"])
	return result

static func choose(available: Array, ship: Dictionary, systems: Dictionary, class_catalogue: Dictionary, competing_score: float, committed: bool) -> Dictionary:
	if committed or not capable(str(ship.get("class", "")), class_catalogue):
		return {}
	if utility(float(ship.get("loyalty", 0.0))) <= competing_score:
		return {}
	var location := str(ship.get("location", ""))
	if not systems.has(location):
		return {}
	for offer in available:
		var claimed := str(offer.get("claimed_by", ""))
		if offer.get("faction", "") == ship.get("faction", "") and systems.get(offer.get("location", "")) == systems[location] and (claimed.is_empty() or claimed == ship.get("id", "")):
			return offer.duplicate(true)
	return {}

static func present(site: Dictionary, ships: Array, class_catalogue: Dictionary, docks: Dictionary) -> String:
	var candidates := []
	for ship in ships:
		if not capable(str(ship.get("class", "")), class_catalogue) or ship.get("faction", "") != site.get("faction", ""):
			continue
		var assigned := str(site.get("executor_id", ""))
		if not assigned.is_empty() and assigned != ship.get("id", ""):
			continue
		if ship.get("current_goal", "") != "construct" or active(ship.get("bt", {})) != site.get("id", ""):
			continue
		if ship.get("in_transit", false) or ship.get("location", "") != site.get("location", ""):
			continue
		var dock_id := str(ship.get("docked_at", ""))
		if dock_id.is_empty() or not docks.has(dock_id):
			continue
		var dock: Dictionary = docks[dock_id]
		if dock.get("abandoned", false) or not dock.get("docked_ships", []).has(ship.get("id", "")):
			continue
		candidates.append(str(ship.get("id", "")))
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""
