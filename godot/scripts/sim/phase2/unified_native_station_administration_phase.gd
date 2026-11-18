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
        # N39 reads snapshots only for due staffing cycles. Previously this
        # branch deep-copied every persisted administrator memory on each
        # non-due paid tick, then N39 discarded the entire copy. Return an
        # independent empty staging container instead: never expose a World
        # alias and never mutate/persist administrator memory on idle ticks.
        return {"ok": true, "due": false, "assignments": {},
            "snapshots": {}, "views": []}
    if tick <= int(world.get("station_administration_last_tick", 0)):
        return {"ok": false, "reason": "n18_duplicate_native_staffing_cycle"}
    var snapshots: Dictionary = world.get("station_administration", {}).duplicate(true)
    var assignments: Dictionary = {}
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for id in facility_ids:
        assignments[id] = 0
    # Build read-only ordered rosters once per due cycle. These are local to this
    # proposal, so ownership/movement/removal on the next tick cannot go stale.
    var occupied: Dictionary = Payroll.occupied(world, tick, external_workers)
    var population_totals: Dictionary = {}
    var population_ids: Array = world["populations"].keys()
    population_ids.sort()
    for pop_id in population_ids:
        var pop: Dictionary = world["populations"][pop_id]
        var pop_key: String = str(pop.get("faction", "")) + "|" + str(pop.get("location", ""))
        # Aggregate in sorted population-ID order, matching the old per-market
        # loop exactly; no mutable World references escape this proposal.
        var people: int = maxi(0, int(pop.get("count", 0)))
        if not population_totals.has(pop_key):
            population_totals[pop_key] = {"people": 0, "workforce": 0, "occupied": 0}
        var totals: Dictionary = population_totals[pop_key]
        totals["people"] = int(totals["people"]) + people
        totals["workforce"] = int(totals["workforce"]) + int(people * 3 / 5)
        totals["occupied"] = int(totals["occupied"]) + int(occupied.get(pop_id, 0))
    var facility_roster: Dictionary = {}
    for fid in facility_ids:
        var facility: Dictionary = world["facilities"][fid]
        var facility_key: String = str(facility.get("faction", "")) + "|" + str(facility.get("location", ""))
        if not facility_roster.has(facility_key):
            facility_roster[facility_key] = []
        facility_roster[facility_key].append(fid)
    # The planner consumes stock/prices/limits/shortages and body resources
    # read-only. Its recipe probes duplicate stock before mutation, while
    # returned decisions/snapshots contain only owned scalar/decision data.
    # Borrow these growing World maps for the synchronous planning call;
    # never retain source references in the persisted administration memory.
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
        var key: String = faction + "|" + location
        var totals: Dictionary = population_totals.get(key, {})
        var total_population: int = int(totals.get("people", 0))
        var real_workforce: int = int(totals.get("workforce", 0))
        var working: int = int(totals.get("occupied", 0))
        var station_account: String = Schema.facility_account(owner_id)
        var jobs: Array = []
        for id in facility_roster.get(key, []):
            var f: Dictionary = world["facilities"][id]
            var body_id: String = str(f.get("body_id", ""))
            var resource: Dictionary = world.get("bodies", {}).get(body_id, {})
            var shift: Dictionary = f.get("work_shift", {})
            jobs.append({
                "id": str(id), "type": str(f.get("type", "")),
                "crew": int(f.get("crew_count", 0)),
                "owner": station_account,
                "household": "", "abandoned": bool(f.get("abandoned", false)),
                "paid_tick": int(shift.get("tick", -1)),
                "actual_workers": (shift.get("workers", {}) as Dictionary).values().reduce(
                    func(total: int, n: Variant) -> int: return total + int(n), 0),
                "efficiency": float(f.get("fitting_output_mult", 1.0)),
                "body_resources": resource.get("resources", {})})
        # A head priority may only come from an ACTUAL persisted Director
        # decision, never a new invented player/AI strategic objective.
        var director: Dictionary = world.get("research_directors", {}).get(faction, {})
        var strategic: Dictionary = director.get("strategic", {})
        var actual_priority: String = str(strategic.get("commodity", ""))
        var source: Dictionary = {
            "faction_id": faction, "location": location,
            "population_count": total_population,
            "workforce_limit": real_workforce,
            "occupied_workers": working,
            "market_owner": station_account,
            "stock": market.get("supply", {}),
            "prices": market.get("prices", {}),
            "limits": market.get("limits", {}),
            "shortages": market.get("history", {}).get("shortage_ticks", {}),
            "head_priority": actual_priority, "facilities": jobs}
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
