extends RefCounted
## Frozen Rust simulation/lod.rs + ship/mod.rs::tick_ships Pass 1.
## One transient gate over canonical N39 World.ships; no second fleet,
## World clock, AI planner, N9 money or observer guessed from the GUI.
const SourceLod = preload("res://scripts/sim/phase1/n140_native_spatial_lod.gd")

static func stage(world: Dictionary, location_positions: Dictionary,
        tick: int, multiplier: int, observers: Array = []) -> Dictionary:
    if tick < 1 or multiplier < 1 or not (world.get("ships") is Dictionary):
        return {"ok": false, "reason": "n140_missing_single_native_fleet"}
    if not (location_positions is Dictionary):
        return {"ok": false, "reason": "n140_missing_real_locations"}
    # Rust Observer list consists of real position and radius triplets.
    # With no connected observers, Rust forces divisor 1 everywhere.
    # P2 may NOT derive observer coordinates from map pixel positions.
    for observer in observers:
        if not (observer is Dictionary):
            return {"ok": false, "reason": "n140_invalid_native_observer"}
        var pos: Variant = observer.get("position", null)
        var radius: Variant = observer.get("radius", null)
        if not (pos is Vector2) or not is_finite(pos.x) or not is_finite(pos.y):
            return {"ok": false, "reason": "n140_observer_position_unavailable"}
        if not (radius is int or radius is float) or not is_finite(float(radius)):
            return {"ok": false, "reason": "n140_invalid_observer_radius"}
    var ids: Array = world["ships"].keys()
    ids.sort()
    var agents: Dictionary = {}
    for sid in ids:
        var ship: Variant = world["ships"][sid]
        if not (ship is Dictionary):
            return {"ok": false, "reason": "n140_invalid_ship_row"}
        var real_ship: Dictionary = ship
        var entry: Dictionary = {}
        # Rust ships without AgentLod tick every single native tick.
        # Older P2 checkpoints must not invent an absent component.
        if real_ship.has("lod"):
            if not (real_ship["lod"] is Dictionary):
                return {"ok": false, "reason": "n140_invalid_lod_component",
                    "ship_id": str(sid)}
            if not SourceLod._cursor_ok(real_ship["lod"]):
                return {"ok": false, "reason": "n140_bad_persisted_cursor",
                    "ship_id": str(sid)}
            entry["lod"] = real_ship["lod"].duplicate(true)
        var transit: Variant = real_ship.get("transit", null)
        if not (transit is Dictionary):
            return {"ok": false, "reason": "n140_invalid_real_transit",
                "ship_id": str(sid)}
        if not transit.is_empty():
            var p: Variant = transit.get("position", null)
            if p is Array and p.size() == 2 and (p[0] is int or p[0] is float) and (
                    p[1] is int or p[1] is float) and is_finite(float(p[0])) and is_finite(float(p[1])):
                entry["position"] = Vector2(float(p[0]), float(p[1]))
        else:
            var location: String = str(real_ship.get("location", ""))
            var location_pos: Variant = location_positions.get(location, null)
            if location_pos is Vector2 and is_finite(location_pos.x) and is_finite(location_pos.y):
                entry["position"] = location_pos
        agents[str(sid)] = entry
    var recomputed: bool = SourceLod.should_recompute(tick, multiplier)
    var stats: Dictionary = {}
    if recomputed:
        var updated: Dictionary = SourceLod.recompute(agents, observers, tick)
        if not updated.get("ok", false):
            return {"ok": false, "reason": "n140_source_recompute_" +
                str(updated.get("reason", "rejected"))}
        agents = updated["agents"]
        stats = updated["stats"].duplicate(true)
    var gated: Dictionary = SourceLod.ship_gate(agents, ids, tick)
    if not gated.get("ok", false):
        return {"ok": false, "reason": "n140_ship_gate_" +
            str(gated.get("reason", "rejected"))}
    var out: Dictionary = world["ships"].duplicate(true)
    var changed: bool = false
    for sid in ids:
        if out[sid].has("lod"):
            var old_lod: Dictionary = out[sid]["lod"]
            var new_lod: Dictionary = gated["agents"][str(sid)]["lod"]
            if old_lod != new_lod:
                changed = true
            out[sid]["lod"] = new_lod.duplicate(true)
    return {"ok": true, "ships": out, "changed": changed,
        "fired": gated["fires"].duplicate(true),
        "fired_count": gated["fires"].size(),
        "skipped_count": ids.size() - gated["fires"].size(),
        "recomputed": recomputed, "stats": stats, "tick": tick}

