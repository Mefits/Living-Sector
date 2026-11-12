extends RefCounted
## N18 CODE_UNVERIFIED: Rust strategy/station.rs station-wide workforce arbitration.
## Pure plans cannot spend credits or produce stock. N6 is the sole shift executor.
const Recipes = preload("res://scripts/sim/economy/native_recipes.gd")
const Production = preload("res://scripts/sim/economy/paid_production.gd")
const WAGE_PER_SHIFT: int = 1

var _last_plan_tick: int = -1
var _last_plan: Dictionary = {}
var _retained: Dictionary = {}
var _producer: RefCounted = Production.new()

## station: faction_id, location, population_count, occupied_workers,
## market_owner, stock, limits, shortages, head_priority, facilities.
## Each facility: id, type, crew, owner, household, abandoned, paid_tick,
## efficiency, body_resources (only for mining). No invented local resources.
func plan(tick: int, station: Dictionary, ledger: RefCounted, executing: bool = true) -> Dictionary:
    if tick < 0 or str(station.get("faction_id", "")).is_empty() or str(station.get("location", "")).is_empty():
        return {"ok": false, "reason": "invalid_station"}
    if tick == _last_plan_tick:
        return _last_plan.duplicate(true)
    var stock: Dictionary = station.get("stock", {})
    var shortages: Dictionary = station.get("shortages", {})
    var facilities: Array = station.get("facilities", [])
    var owner: String = str(station.get("market_owner", ""))
    var workforce: int = maxi(0, int(floor(float(station.get("population_count", 0)) * 3.0 / 5.0)))
    var occupied: int = maxi(0, int(station.get("occupied_workers", 0)))
    var idle: int = maxi(0, workforce - occupied)
    var head: String = str(station.get("head_priority", ""))
    var installed: Array[String] = []
    for facility in facilities:
        installed.append(str(facility.get("type", "")))
    # Rust production_chain::available_local_precursor: only real installed
    # co-located producers and one batch with currently available inputs.
    head = _local_precursor(head, installed, stock)
    var decisions: Array[Dictionary] = []
    var candidates: Array[Dictionary] = []
    var budgets: Dictionary = {}
    var ordered: Array = facilities.duplicate(true)
    ordered.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
    for f in ordered:
        var id: String = str(f.get("id", ""))
        var kind: String = str(f.get("type", ""))
        var crew: int = int(f.get("crew", 0))
        var account: String = str(f.get("owner", ""))
        var decision: Dictionary = {"facility_id": id, "facility_type": kind,
            "required_workers": crew, "assigned_workers": 0, "score": 0.0,
            "priority_commodity": "", "head_priority": false,
            "retained": bool(_retained.get(id, false)),
            "reason": "outside_production_scope", "actual_workers": 0,
            "execution_reason": ""}
        var recipes: Array[Dictionary] = Recipes.for_facility(kind)
        var mining: bool = kind == "mining_rig" or kind == "salvage_field"
        if not mining and recipes.is_empty():
            decisions.append(decision)
            continue
        if int(f.get("paid_tick", -1)) == tick:
            decision["reason"] = "already_worked"
            decision["actual_workers"] = int(f.get("actual_workers", 0))
        elif bool(f.get("abandoned", false)):
            decision["reason"] = "abandoned"
        elif crew <= 0:
            decision["reason"] = "no_jobs"
        elif owner.is_empty() or account != owner or ledger.balance(owner) < 0:
            decision["reason"] = "foreign_stock_owner"
        else:
            var outputs: Array[String] = []
            if mining:
                for slug in f.get("body_resources", {}):
                    if float(f["body_resources"][slug]) > 0.0:
                        outputs.append(str(slug))
            else:
                for recipe in recipes:
                    var probe: Dictionary = stock.duplicate(true)
                    if not Recipes.execute(str(recipe["id"]), probe, float(f.get("efficiency", 1.0)), 1, station.get("prices", null)).is_empty():
                        for slug in recipe["out"]:
                            outputs.append(str(slug))
            outputs.sort()
            var best_score: float = -1.0
            var best: String = ""
            for slug in outputs:
                var score: float = _urgency(slug, stock, shortages) + (100.0 if slug == head else 0.0)
                if score > best_score or (is_equal_approx(score, best_score) and slug < best):
                    best_score = score
                    best = slug
            if best.is_empty():
                decision["reason"] = "no_extractable_resource" if mining else "no_viable_recipe"
            else:
                decision["priority_commodity"] = best
                decision["head_priority"] = best == head
                decision["score"] = best_score * (1.15 if decision["retained"] else 1.0)
                decision["reason"] = "candidate"
                candidates.append(decision)
        decisions.append(decision)
    candidates.sort_custom(func(a, b):
        if float(a["score"]) != float(b["score"]):
            return float(a["score"]) > float(b["score"])
        return str(a["facility_id"]) < str(b["facility_id"]))
    for d in candidates:
        var crew: int = int(d["required_workers"])
        var cost: int = crew * WAGE_PER_SHIFT
        if idle < crew:
            d["reason"] = "insufficient_station_workers"
        else:
            var available: int = int(budgets.get(owner, ledger.balance(owner)))
            if available < cost:
                d["reason"] = "insufficient_existing_budget"
            else:
                d["assigned_workers"] = crew
                d["reason"] = "head_priority" if d["head_priority"] else ("retain_viable_assignment" if d["retained"] else "local_need")
                idle -= crew
                budgets[owner] = available - cost
    # candidates reference the same dictionaries as decisions, no duplicate allocations.
    var assigned: int = 0
    for d in decisions:
        assigned += int(d["assigned_workers"])
    var result: Dictionary = {"ok": true, "tick": tick, "executing": executing,
        "faction_id": station["faction_id"], "location": station["location"],
        "workforce": workforce, "already_working": occupied,
        "assigned_workers": assigned, "idle_workers": idle,
        "head_priority": head, "modules": decisions}
    _last_plan_tick = tick
    _last_plan = result.duplicate(true)
    return result

## Dispatch revalidates N6 payroll and inventory on every shift; no phantom
## execution in shadow mode, no mining until a native extractor is connected.
func dispatch(plan_data: Dictionary, station: Dictionary, ledger: RefCounted) -> Dictionary:
    if not plan_data.get("ok", false) or not plan_data.get("executing", false):
        return {"ok": false, "reason": "not_executing"}
    if int(plan_data.get("tick", -1)) != _last_plan_tick:
        return {"ok": false, "reason": "stale_plan"}
    var results: Array[Dictionary] = []
    var stock: Dictionary = station.get("stock", {})
    var facilities: Array = station.get("facilities", [])
    for decision in plan_data["modules"]:
        if int(decision["assigned_workers"]) <= 0:
            continue
        var facility: Dictionary = {}
        for f in facilities:
            if str(f.get("id", "")) == str(decision["facility_id"]):
                facility = f
                break
        if facility.is_empty():
            results.append({"facility_id": decision["facility_id"], "ok": false, "reason": "facility_missing"})
            continue
        var recipe_id: String = ""
        for recipe in Recipes.for_facility(str(facility.get("type", ""))):
            if recipe["out"].has(str(decision["priority_commodity"])):
                recipe_id = str(recipe["id"])
                break
        if recipe_id.is_empty():
            results.append({"facility_id": decision["facility_id"], "ok": false, "reason": "no_executable_recipe"})
            continue
        var result: Dictionary = _producer.run_shift(str(facility["id"]), recipe_id,
            str(facility["type"]), int(plan_data["tick"]), int(decision["assigned_workers"]),
            int(station.get("population_count", 0)), stock, station.get("limits", {}),
            ledger, str(facility["owner"]), str(facility.get("household", "")),
            float(facility.get("efficiency", 1.0)), 1, station.get("prices", null))
        result["facility_id"] = decision["facility_id"]
        results.append(result)
    for d in plan_data["modules"]:
        _retained[str(d["facility_id"])] = int(d["assigned_workers"]) > 0
    return {"ok": true, "results": results}

func snapshot() -> Dictionary:
    return {"version": 1, "last_plan_tick": _last_plan_tick,
        "last_plan": _last_plan.duplicate(true), "retained": _retained.duplicate(true),
        "producer": _producer.snapshot()}

func restore(data: Dictionary) -> bool:
    if data.get("version") != 1 or not (data.get("retained") is Dictionary) or not (data.get("last_plan") is Dictionary):
        return false
    var candidate: RefCounted = Production.new()
    if not candidate.restore(data.get("producer", {})):
        return false
    _last_plan_tick = int(data.get("last_plan_tick", -1))
    _last_plan = data["last_plan"].duplicate(true)
    _retained = data["retained"].duplicate(true)
    _producer = candidate
    return true

func _urgency(slug: String, stock: Dictionary, shortages: Dictionary) -> float:
    var essential: float = 3.0 if slug == "food" or slug == "water" else (2.0 if slug == "fuel" else 1.0)
    return 10.0 + essential * 40.0 / (1.0 + maxf(0.0, float(stock.get(slug, 0.0))) / 20.0) + float(mini(100, maxi(0, int(shortages.get(slug, 0))))) * 0.2

func _local_precursor(product: String, installed: Array[String], stock: Dictionary) -> String:
    if product.is_empty():
        return product
    var sorted_kinds: Array[String] = installed.duplicate()
    sorted_kinds.sort()
    for final_kind in sorted_kinds:
        for final_recipe in Recipes.for_facility(final_kind):
            if not final_recipe["out"].has(product):
                continue
            var missing: Array[String] = []
            for slug in final_recipe["in"]:
                if float(stock.get(slug, 0.0)) < float(final_recipe["in"][slug]):
                    missing.append(str(slug))
            missing.sort()
            for slug in missing:
                for kind in sorted_kinds:
                    for recipe in Recipes.for_facility(kind):
                        if not recipe["out"].has(slug):
                            continue
                        var probe: Dictionary = stock.duplicate(true)
                        if not Recipes.execute(str(recipe["id"]), probe, 1.0, 1).is_empty():
                            return slug
    return product
