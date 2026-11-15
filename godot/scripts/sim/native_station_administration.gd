extends RefCounted
## Frozen Rust strategy/station.rs: administrator allocation, no wages paid here.
static func urgency(commodity: String, supply: Dictionary, shortages: Dictionary) -> float:
	var stock: float = maxf(0.0, float(supply.get(commodity, 0.0)))
	var essential := 3.0 if commodity in ["food", "water"] else (2.0 if commodity == "fuel" else 1.0)
	return 10.0 + essential * 40.0 / (1.0 + stock / 20.0) + float(mini(100, int(shortages.get(commodity, 0)))) * 0.2

## Inputs are native ECS snapshots grouped by faction+location:
## population [{faction_id,location,count,occupied}], facilities [{id,faction_id,
## location,type,crew_count,abandoned,already_worked,actual_workers,owner_id,
## body_resources,recipes:[{outputs,inputs,viable}],efficiency}],
## markets [{faction_id,location,owner_id,credits,supply,shortages}],
## head_priorities {"faction|location": commodity}, previous assigned ids.
## wage_per_shift comes from Rust workforce::WAGE_PER_SHIFT.
static func plan(snapshot: Dictionary, tick: int, executing: bool, wage_per_shift: int) -> Dictionary:
	var population: Dictionary = {}
	for p in snapshot.get("population", []):
		var key := str(p.get("faction_id", "")) + "|" + str(p.get("location", ""))
		var group: Dictionary = population.get(key, {"workforce": 0, "working": 0})
		group["workforce"] = int(group["workforce"]) + maxi(0, int(p.get("count", 0))) * 3 / 5
		group["working"] = int(group["working"]) + int(p.get("occupied", 0))
		population[key] = group
	var markets: Dictionary = {}
	for m in snapshot.get("markets", []):
		markets[str(m.get("location", ""))] = m
	var groups: Dictionary = {}
	for f in snapshot.get("facilities", []):
		if str(f.get("type", "")) == "construction_dock":
			continue
		var key := str(f.get("faction_id", "")) + "|" + str(f.get("location", ""))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(f)
	var stations: Array = []
	var allocations: Dictionary = {}
	var previous: Dictionary = snapshot.get("previous_assigned", {})
	for key in groups.keys():
		var facilities: Array = groups[key]
		facilities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
		var faction := str(facilities[0].get("faction_id", ""))
		var location := str(facilities[0].get("location", ""))
		var pop: Dictionary = population.get(key, {"workforce": 0, "working": 0})
		var idle: int = maxi(0, int(pop["workforce"]) - int(pop["working"]))
		var head := str(snapshot.get("head_priorities", {}).get(key, ""))
		var view := {"faction_id": faction, "location": location, "observed_tick": tick, "executing": executing, "workforce": pop["workforce"], "already_working": pop["working"], "assigned_workers": 0, "idle_workers": idle, "head_priority": head, "modules": [], "needs": []}
		var market: Dictionary = markets.get(location, {})
		var supply: Dictionary = market.get("supply", {})
		var shortages: Dictionary = market.get("shortages", {})
		var budgets: Dictionary = snapshot.get("owner_credits", {}).duplicate(true)
		var candidates: Array = []
		for f in facilities:
			var fid := str(f.get("id", ""))
			var kind := str(f.get("type", ""))
			var mining := kind in ["mining_rig", "salvage_field"]
			var recipes: Array = f.get("recipes", [])
			var jobs := int(f.get("crew_count", 0))
			var d := {"facility_id": fid, "facility_type": kind, "required_workers": jobs, "assigned_workers": 0, "score": 0.0, "priority_commodity": "", "head_priority": false, "retained": false, "reason": "outside_production_scope", "actual_workers": int(f.get("actual_workers", 0)), "execution_reason": null}
			if not mining and recipes.is_empty():
				view["modules"].append(d)
				continue
			allocations[fid] = 0
			if bool(f.get("already_worked", false)):
				d["reason"] = "already_worked"
			elif bool(f.get("abandoned", false)):
				d["reason"] = "abandoned"
			elif jobs <= 0:
				d["reason"] = "no_jobs"
			elif market.is_empty():
				d["reason"] = "missing_market"
			elif str(market.get("faction_id", "")) != faction:
				d["reason"] = "foreign_stock_owner"
			else:
				var outputs: Array = []
				if mining:
					for commodity in f.get("body_resources", {}).keys():
						if float(f["body_resources"][commodity]) > 0.0:
							outputs.append(str(commodity))
				else:
					for recipe in recipes:
						if bool(recipe.get("viable", false)):
							for commodity in recipe.get("outputs", []):
								outputs.append(str(commodity))
						else:
							for commodity in recipe.get("inputs", []):
								if float(supply.get(commodity, 0.0)) <= 0.0:
									view["needs"].append({"facility_id": fid, "commodity": str(commodity), "kind": "supply_input"})
				outputs.sort()
				var best := ""
				var best_score := -1.0
				for commodity in outputs:
					var score := urgency(commodity, supply, shortages) + (100.0 if commodity == head else 0.0)
					if score > best_score or (is_equal_approx(score, best_score) and str(commodity) < best):
						best = commodity
						best_score = score
				if best.is_empty():
					d["reason"] = "no_extractable_resource" if mining else "no_viable_recipe"
				else:
					d["priority_commodity"] = best
					d["head_priority"] = best == head
					d["retained"] = bool(previous.get(fid, false))
					d["score"] = best_score * (1.15 if d["retained"] else 1.0)
					d["reason"] = "candidate"
					var owner := str(f.get("owner_id", ""))
					var wage := jobs * wage_per_shift
					var cost := wage + ((wage + 9) / 10 if owner != fid else 0)
					candidates.append({"owner": owner, "cost": cost, "decision": d})
			if d["reason"] != "candidate":
				view["modules"].append(d)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["decision"]["score"] != b["decision"]["score"]:
				return a["decision"]["score"] > b["decision"]["score"]
			return a["decision"]["facility_id"] < b["decision"]["facility_id"]
		)
		for candidate in candidates:
			var d: Dictionary = candidate["decision"]
			var owner: String = candidate["owner"]
			var cost: int = candidate["cost"]
			var budget: int = int(budgets.get(owner, 0))
			if idle < int(d["required_workers"]):
				d["reason"] = "insufficient_station_workers"
			elif budget < cost:
				d["reason"] = "insufficient_existing_budget"
			else:
				d["assigned_workers"] = d["required_workers"]
				d["reason"] = "head_priority" if d["head_priority"] else ("retain_viable_assignment" if d["retained"] else "local_need")
				idle -= int(d["required_workers"])
				view["assigned_workers"] += int(d["required_workers"])
				budgets[owner] = budget - cost
				allocations[d["facility_id"]] = d["required_workers"]
			view["modules"].append(d)
		view["idle_workers"] = idle
		view["modules"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["facility_id"] < b["facility_id"])
		view["needs"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["facility_id"]) + "|" + str(a["commodity"]) < str(b["facility_id"]) + "|" + str(b["commodity"])
		)
		stations.append(view)
	stations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["faction_id"]) + "|" + str(a["location"]) < str(b["faction_id"]) + "|" + str(b["location"]))
	return {"tick": tick, "executing": executing, "stations": stations, "allocations": allocations}

static func permits(state: Dictionary, facility_id: String, tick: int) -> bool:
	return not bool(state.get("executing", false)) or int(state.get("tick", -1)) != tick or int(state.get("allocations", {}).get(facility_id, 1)) > 0

static func feedback(state: Dictionary, actual: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for station in result.get("stations", []):
		for module in station.get("modules", []):
			if actual.has(module["facility_id"]):
				var entry: Dictionary = actual[module["facility_id"]]
				module["actual_workers"] = int(entry.get("workers", 0))
				module["execution_reason"] = entry.get("reason")
	return result
