extends RefCounted
## Phase2 N156 bridge: translate the ONE N39 physical world to the frozen
## facility lifecycle input. Pure proposal only; never runs a second clock,
## spends money, repairs Tools or mutates the authoritative world.
const NativeLifecycle = preload("res://scripts/sim/phase1/n156_native_facility_lifecycle.gd")

static func propose(world: Dictionary, tick: int, tick_scale: float,
        multiplier: int, ships: Dictionary = {},
        paid_receipts: Dictionary = {}, paid_credits: Dictionary = {}) -> Dictionary:
    if not (world.get("facilities") is Dictionary
            and world.get("markets") is Dictionary
            and world.get("populations") is Dictionary):
        return {"ok": false, "reason": "missing_authoritative_n39_world"}
    if tick < 0 or multiplier < 1 or not is_finite(tick_scale) or tick_scale < 0.0:
        return {"ok": false, "reason": "invalid_authoritative_clock"}
    var facilities: Array = []
    var ids: Array = world["facilities"].keys()
    ids.sort()
    var satisfaction: Dictionary = {}
    for pid in world["populations"]:
        var pop: Variant = world["populations"][pid]
        if not (pop is Dictionary):
            return {"ok": false, "reason": "invalid_authoritative_population"}
        satisfaction[str(pid)] = float(pop.get("food_satisfaction", 50))
    for fid in ids:
        var fac: Variant = world["facilities"][fid]
        if not (fac is Dictionary):
            return {"ok": false, "reason": "invalid_authoritative_facility"}
        var location: String = str(fac.get("location", ""))
        if location.is_empty():
            return {"ok": false, "reason": "facility_has_no_physical_location"}
        # Rust colony::prepare_docks has no market until completion.
        # Only an approved unfinished N151 construction_dock may lack
        # a seller. N156 still updates its real lifecycle/condition.
        if not world["markets"].has(location):
            var site_ref: String = str(fac.get("construction_source_site_id", ""))
            var site: Dictionary = world.get("construction_sites", {}).get(site_ref, {})
            if str(fac.get("type", "")) != "construction_dock" or (
                    site.is_empty() or str(site.get("location_name", "")) != location or
                    str(site.get("faction_id", "")) != str(fac.get("faction", ""))):
                return {"ok": false, "reason": "facility_has_no_physical_market"}
        else:
            var market: Variant = world["markets"][location]
            if not (market is Dictionary) or not (market.get("supply") is Dictionary):
                return {"ok": false, "reason": "invalid_physical_market"}
        var condition: float = float(fac.get("condition", 1.0))
        if not is_finite(condition) or condition < 0.0 or condition > 1.0:
            return {"ok": false, "reason": "invalid_facility_condition"}
        # These are the ACTUAL physical service reserves owned by THIS
        # facility, not market supply. The seed has {} until a real restock.
        var existing: Variant = fac.get("reserves", {})
        if not (existing is Dictionary):
            return {"ok": false, "reason": "invalid_facility_owned_reserves"}
        var reserves: Dictionary = existing.duplicate(true)
        for commodity in reserves:
            var amount: Variant = reserves[commodity]
            if not (commodity is String) or not (amount is float or amount is int):
                return {"ok": false, "reason": "invalid_facility_owned_reserves"}
            if not is_finite(float(amount)) or float(amount) < 0.0:
                return {"ok": false, "reason": "invalid_facility_owned_reserves"}
        # Frozen N156 crew welfare derives from the last paid N39 WorkShift.
        var crew_projection: Dictionary = {}
        var shift: Variant = fac.get("work_shift", {})
        if not (shift is Dictionary):
            return {"ok": false, "reason": "invalid_paid_work_shift"}
        if not shift.is_empty():
            if not (shift.get("workers") is Dictionary):
                return {"ok": false, "reason": "invalid_paid_work_shift_workers"}
            var worker_pairs: Array = []
            var worker_ids: Array = shift["workers"].keys()
            worker_ids.sort()
            for worker_id in worker_ids:
                var count: Variant = shift["workers"][worker_id]
                if not satisfaction.has(str(worker_id)) or not (count is int) or int(count) <= 0:
                    return {"ok": false, "reason": "unmatched_paid_work_shift_population"}
                worker_pairs.append([str(worker_id), int(count)])
            crew_projection = {
                "work_shift": {"workers": worker_pairs},
                "morale": float(fac.get("morale", 80.0)),
                "hunger": float(fac.get("crew_hunger", 0.0)),
                "food_debt": 0.0
            }
        facilities.append({
            "id": str(fid), "location_name": location,
            "facility_type": str(fac.get("type", "")),
            "operations": {"condition": condition, "credits": int(fac.get("credits", 0))},
            "storage": {"reserves": reserves, "dock_queue": []},
            "crew": crew_projection,
            "lifecycle": {
                "abandoned": bool(fac.get("abandoned", false)),
                "abandon_counter": int(fac.get("abandon_counter", 0))
            }
        })
    var stage: Dictionary = NativeLifecycle.start_tick(
        facilities, ships, satisfaction, tick, tick_scale, multiplier)
    if not stage.get("ok", false):
        return stage
    # PayShift is applied by the single N39 owner, NOT by this pure bridge.
    # Repair receipts and post-wage credits are injected only after the
    # authoritative N9 ledger has actually committed each shift.
    var staged_rows: Array = stage["facilities_before_abandonment"]
    for row in staged_rows:
        var rid: String = str(row.get("id", ""))
        if paid_credits.has(rid):
            if typeof(paid_credits[rid]) != TYPE_INT or int(paid_credits[rid]) < 0:
                return {"ok": false, "reason": "invalid_paid_repair_balance"}
            row["operations"]["credits"] = int(paid_credits[rid])
    var after_stage: Dictionary = NativeLifecycle.after_real_paid_repairs_and_abandonment(
        staged_rows, paid_receipts, tick, multiplier)
    if not after_stage.get("ok", false):
        return after_stage
    var changes: Dictionary = {}
    for row in after_stage["facilities"]:
        var id: String = str(row["id"])
        var original: Dictionary = world["facilities"][id]
        var after: float = float(row["operations"]["condition"])
        var life: Dictionary = row["lifecycle"]
        var morale_after: float = float(row.get("crew", {}).get("morale", original.get("morale", 80.0)))
        var reserves_after: Dictionary = row["storage"]["reserves"]
        var reserves_before: Dictionary = original.get("reserves", {})
        if after != float(original.get("condition", 1.0)) or bool(life["abandoned"]) != bool(original.get("abandoned", false)) or int(life["abandon_counter"]) != int(original.get("abandon_counter", 0)) or morale_after != float(original.get("morale", 80.0)) or reserves_after != reserves_before:
            changes[id] = {"condition": after,
                "abandoned": bool(life["abandoned"]),
                "abandon_counter": int(life["abandon_counter"]),
                "morale": morale_after,
                "reserves": reserves_after.duplicate(true)}
    return {
        "ok": true, "tick": tick, "changes": changes,
        "repair_candidates": stage["repair_candidates"],
        "events": after_stage["events"],
        "due": stage["due"],
        "source": "N156 frozen lifecycle, N39 paid repair receipts; staged only",
        "commit_required": true,
        "limitations": "Ship dock queues remain deferred"
    }
