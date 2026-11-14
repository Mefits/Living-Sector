extends RefCounted
## Native Rust strategy/station.rs :: StationAdministration::plan.
## This adapter makes the already ported N18 administrator's ALLOCATIONS
## executable in the ONE N39/N6 paid production phase. The source admin
## never creates money, people, products or a second production worker.
const Admin = preload("res://scripts/sim/strategy/station_administrator.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")

static func propose(world: Dictionary, ledger: RefCounted, tick: int,
        multiplier: int, external_workers: Dictionary = {}) -> Dictionary:
    if tick < 1 or multiplier < 1 or ledger == null:
        return {"ok": false, "reason": "n18_invalid_native_station_clock"}
    if not (world.get("facilities") is Dictionary) or not (
            world.get("markets") is Dictionary) or not (
            world.get("populations") is Dictionary):
        return {"ok": false, "reason": "n18_missing_real_n39_station_sources"}
    if not (world.get("station_administration", {}) is Dictionary):
        return {"ok": false, "reason": "n18_invalid_persisted_administrator"}
    var due: bool = tick % (5 * multiplier) == 0
    if not due:
        return {"ok": true, "due": false, "assignments": {},
            "snapshots": world.get("station_administration", {}).duplicate(true),
            "views": []}
    if tick <= int(world.get("station_administration_last_tick", 0)):
        return {"ok": false, "reason": "n18_duplicate_native_staffing_cycle"}
    var snapshots: Dictionary = world.get("station_administration", {}).duplicate(true)
    var assignments: Dictionary = {}
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for id in facility_ids:
        assignments[id] = 0
    var occupied: Dictionary = Payroll.occupied(world, tick, external_workers)
    var views: Array = []
    var market_locations: Array = world["markets"].keys()
    market_locations.sort()
    for raw_location in market_locations:
        var location: String = str(raw_location)
        var market: Dictionary = world["markets"][location]
        var owner_id: String = str(market.get("owner", ""))
        var station: Dictionary = world["facilities"].get(owner_id, {})
        if station.is_empty() or str(station.get("type", "")) != "station":
            return {"ok": false, "reason": "n18_missing_real_station_market_owner"}
        var faction: String = str(station.get("faction", ""))
        if faction.is_empty():
            return {"ok": false, "reason": "n18_station_without_original_faction"}
        var total_population: int = 0
        var real_workforce: int = 0
        var working: int = 0
        var population_ids: Array = world["populations"].keys()
        population_ids.sort()
        for pop_id in population_ids:
            var p: Dictionary = world["populations"][pop_id]
            if str(p.get("faction", "")) == faction and str(p.get("location", "")) == location:
                total_population += int(p.get("count", 0))
                working += int(occupied.get(pop_id, 0))
        var jobs: Array = []
        for id in facility_ids:
            var f: Dictionary = world["facilities"][id]
            if str(f.get("faction", "")) != faction or str(f.get("location", "")) != location:
                continue
            var body_id: String = str(f.get("body_id", ""))
            var resource: Dictionary = world.get("bodies", {}).get(body_id, {})
            var shift: Dictionary = f.get("work_shift", {})
            jobs.append({
                "id": str(id), "type": str(f.get("type", "")),
                "crew": int(f.get("crew_count", 0)),
                "owner": Schema.facility_account(owner_id),
                "household": "", "abandoned": bool(f.get("abandoned", false)),
                "paid_tick": int(shift.get("tick", -1)),
                "actual_workers": (shift.get("workers", {}) as Dictionary).values().reduce(
                    func(total: int, n: Variant) -> int: return total + int(n), 0),
                "efficiency": float(f.get("fitting_output_mult", 1.0)),
                "body_resources": resource.get("resources", {}).duplicate(true)})
        # A head priority may only come from an ACTUAL persisted Director
        # decision, never a new invented player/AI strategic objective.
        var director: Dictionary = world.get("research_directors", {}).get(faction, {})
        var strategic: Dictionary = director.get("strategic", {})
        var actual_priority: String = str(strategic.get("commodity", ""))
        var source: Dictionary = {
            "faction_id": faction, "location": location,
            "population_count": total_population,
            "occupied_workers": working,
            "market_owner": Schema.facility_account(owner_id),
            "stock": market.get("supply", {}).duplicate(true),
            "prices": market.get("prices", {}).duplicate(true),
            "limits": market.get("limits", {}).duplicate(true),
            "shortages": market.get("history", {}).get("shortage_ticks", {}).duplicate(true),
            "head_priority": actual_priority, "facilities": jobs}
        var key: String = faction + "|" + location
        var planner = Admin.new()
        if snapshots.has(key) and not planner.restore(snapshots[key]):
            return {"ok": false, "reason": "n18_corrupted_native_administrator_memory"}
        var plan: Dictionary = planner.plan(tick, source, ledger, true)
        if not plan.get("ok", false) or not bool(plan.get("executing", false)):
            return {"ok": false, "reason": "n18_real_station_allocation_rejected"}
        for row in plan.get("modules", []):
            var fid: String = str(row.get("facility_id", ""))
            var count: int = int(row.get("assigned_workers", -1))
            if not assignments.has(fid) or count < 0 or count > int(world["facilities"][fid].get("crew_count", 0)):
                return {"ok": false, "reason": "n18_invalid_native_staffing_candidate"}
            if count != 0 and count != int(world["facilities"][fid]["crew_count"]):
                return {"ok": false, "reason": "n18_partial_crew_does_not_match_rust"}
            assignments[fid] = count
        # Rust station.rs carries forward the PREVIOUS StationView's
        # assigned_workers>0 as retention on the next planning cycle.
        # N18::dispatch is deliberately NOT called: it uses a detached
        # PaidProduction executor, while N39/N6 already own real payroll.
        # Persist just the source retention memory from this live plan.
        var memory: Dictionary = planner.snapshot()
        var retained: Dictionary = {}
        for row in plan.get("modules", []):
            retained[str(row["facility_id"])] = int(row["assigned_workers"]) > 0
        memory["retained"] = retained
        snapshots[key] = memory
        views.append(plan.duplicate(true))
    return {"ok": true, "due": true, "assignments": assignments,
        "snapshots": snapshots, "views": views,
        "authority": "n18_source_administrator_n39_payroll_only"}
