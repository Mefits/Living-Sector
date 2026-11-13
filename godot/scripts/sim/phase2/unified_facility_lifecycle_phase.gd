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
        facilities.append({
            "id": str(fid), "location_name": location,
            "facility_type": str(fac.get("type", "")),
            "operations": {"condition": condition, "credits": int(fac.get("credits", 0))},
            "storage": {"reserves": reserves, "dock_queue": []},
            "lifecycle": {
                "abandoned": bool(fac.get("abandoned", false)),
                "abandon_counter": int(fac.get("abandon_counter", 0))
            }
        })
    var stage: Dictionary = NativeLifecycle.start_tick(
        facilities, ships, satisfaction, tick, tick_scale, multiplier)
    if not stage.get("ok", false):
        return stage
    var changes: Dictionary = {}
    for row in stage["facilities_before_abandonment"]:
        var id: String = str(row["id"])
        var original: Dictionary = world["facilities"][id]
        var after: float = float(row["operations"]["condition"])
        if after != float(original.get("condition", 1.0)):
            changes[id] = {"condition": after}
    return {
        "ok": true, "tick": tick, "changes": changes,
        "repair_candidates": stage["repair_candidates"],
        "due": stage["due"],
        "source": "N156 frozen facility lifecycle; staged only",
        "commit_required": true,
        "limitations": "No authoritative facility condition Apply yet; no repair or abandonment committed"
    }
