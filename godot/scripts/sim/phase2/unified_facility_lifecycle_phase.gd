extends RefCounted
## Phase2 N156 bridge: translate the ONE N39 physical world to the frozen
## facility lifecycle input. Pure proposal only; never runs a second clock,
## spends money, repairs Tools or mutates the authoritative world.
const NativeLifecycle = preload("res://scripts/sim/phase1/n156_native_facility_lifecycle.gd")

static func propose(world: Dictionary, tick: int, tick_scale: float,
        multiplier: int, ships: Dictionary = {}) -> Dictionary:
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
        if location.is_empty() or not world["markets"].has(location):
            return {"ok": false, "reason": "facility_has_no_physical_market"}
        var market: Variant = world["markets"][location]
        if not (market is Dictionary) or not (market.get("supply") is Dictionary):
            return {"ok": false, "reason": "invalid_physical_market"}
        var condition: float = float(fac.get("condition", 1.0))
        if not is_finite(condition) or condition < 0.0 or condition > 1.0:
            return {"ok": false, "reason": "invalid_facility_condition"}
        var reserves: Dictionary = {}
        # N39's market is the only actual commodity stock; never invent
        # a second station inventory or copy market supply as owned Tools.
        reserves["tools"] = 0.0
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
    # Frozen order: decay, (no paid repairs without owned Tools), abandonment.
    # The authoritative N39 world has no station-owned Tools inventory yet;
    # never debit public market supply as if it belonged to the facility.
    var after_stage: Dictionary = NativeLifecycle.after_real_paid_repairs_and_abandonment(
        stage["facilities_before_abandonment"], {}, tick, multiplier)
    if not after_stage.get("ok", false):
        return after_stage
    var changes: Dictionary = {}
    for row in after_stage["facilities"]:
        var id: String = str(row["id"])
        var original: Dictionary = world["facilities"][id]
        var after: float = float(row["operations"]["condition"])
        var life: Dictionary = row["lifecycle"]
        var morale_after: float = float(row.get("crew", {}).get("morale", original.get("morale", 80.0)))
        if after != float(original.get("condition", 1.0)) or bool(life["abandoned"]) != bool(original.get("abandoned", false)) or int(life["abandon_counter"]) != int(original.get("abandon_counter", 0)) or morale_after != float(original.get("morale", 80.0)):
            changes[id] = {"condition": after,
                "abandoned": bool(life["abandoned"]),
                "abandon_counter": int(life["abandon_counter"]),
                "morale": morale_after}
    return {
        "ok": true, "tick": tick, "changes": changes,
        "repair_candidates": stage["repair_candidates"],
        "events": after_stage["events"],
        "due": stage["due"],
        "source": "N156 frozen facility lifecycle; staged only",
        "commit_required": true,
        "limitations": "Paid Tools repairs and ship dock queues remain deferred"
    }
