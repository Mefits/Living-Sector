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
    var recomputed: bool = SourceLod.should_recompute(tick, multiplier)
    var positions_by_ship: Dictionary = {}
    var has_lod: bool = false
    # Preflight is read-only. Geometry is needed only on recompute ticks;
    # most paid ticks must not rebuild a full ship-position projection.
    for sid in ids:
        var ship: Variant = world["ships"][sid]
        if not (ship is Dictionary):
            return {"ok": false, "reason": "n140_invalid_ship_row"}
        var real_ship: Dictionary = ship
        if real_ship.has("lod"):
            has_lod = true
            if not (real_ship["lod"] is Dictionary):
                return {"ok": false, "reason": "n140_invalid_lod_component",
                    "ship_id": str(sid)}
            if not SourceLod._cursor_ok(real_ship["lod"]):
                return {"ok": false, "reason": "n140_bad_persisted_cursor",
                    "ship_id": str(sid)}
        var transit: Variant = real_ship.get("transit", null)
        if not (transit is Dictionary):
            return {"ok": false, "reason": "n140_invalid_real_transit",
                "ship_id": str(sid)}
        if not recomputed or not real_ship.has("lod"):
            continue
        if not transit.is_empty():
            var p: Variant = transit.get("position", null)
            if p is Array and p.size() == 2 and (p[0] is int or p[0] is float) and (
                    p[1] is int or p[1] is float) and is_finite(float(p[0])) and is_finite(float(p[1])):
                positions_by_ship[str(sid)] = Vector2(float(p[0]), float(p[1]))
        else:
            var location: String = str(real_ship.get("location", ""))
            var location_pos: Variant = location_positions.get(location, null)
            if location_pos is Vector2 and is_finite(location_pos.x) and is_finite(location_pos.y):
                positions_by_ship[str(sid)] = location_pos
    if not has_lod:
        var every_ship: Dictionary = {}
        for sid in ids:
            every_ship[str(sid)] = 1
        var empty_stats: Dictionary = {}
        if recomputed:
            empty_stats = SourceLod.stats_for_agents({})
        return {"ok": true, "ships": world["ships"].duplicate(true),
            "changed": false, "fired": every_ship,
            "fired_count": every_ship.size(), "skipped_count": 0,
            "recomputed": recomputed, "stats": empty_stats, "tick": tick}

    # SourceLod's set_divisor and try_fire already return detached cursor
    # dictionaries. Stage ONLY these small cursor results before cloning the
    # fleet; invalid ticks/cursors cannot trigger a deep cargo/BT copy.
    # This is a local overlay, never a second authoritative ship store.
    var cursors: Dictionary = {}
    var stats: Dictionary = {}
    if recomputed:
        stats = SourceLod.stats_for_agents({})
    var stat_keys: Dictionary = {1: "d1", 2: "d2", 5: "d5",
        10: "d10", 20: "d20", 50: "d50"}
    var fired: Dictionary = {}
    var changed: bool = false
    for sid in ids:
        var key: String = str(sid)
        var original: Dictionary = world["ships"][sid]
        if not original.has("lod"):
            fired[key] = 1
            continue
        var cursor: Dictionary = original["lod"]
        if recomputed and positions_by_ship.has(key):
            var new_divisor: int = SourceLod.divisor_for_position(
                positions_by_ship[key], observers)
            var staged: Dictionary = SourceLod.set_divisor(
                cursor, new_divisor, tick)
            if not staged.get("ok", false):
                return {"ok": false, "reason": "n140_source_recompute_set_divisor_failed:" + key}
            cursor = staged["cursor"]
            var stat_key: String = stat_keys.get(new_divisor, "other")
            stats[stat_key] += 1
            stats["total"] += 1
        var gate: Dictionary = SourceLod.try_fire(cursor, tick)
        if not gate.get("ok", false):
            return {"ok": false, "reason": "n140_ship_gate_" +
                str(gate.get("reason", "invalid_cursor_or_tick")) + ":" + key}
        cursors[sid] = gate["cursor"]
        if original["lod"] != gate["cursor"]:
            changed = true
        if gate.get("fired", false):
            fired[key] = int(gate["skipped_ticks"])
    # One deep detachment after every read-only validation and cursor gate.
    # All original cargo, BT and memory rows remain untouched on failure;
    # on success the caller owns the entire detached fleet, including sleepers.
    var out: Dictionary = world["ships"].duplicate(true)
    for sid in cursors:
        out[sid]["lod"] = cursors[sid]
    return {"ok": true, "ships": out, "changed": changed,
        "fired": fired, "fired_count": fired.size(),
        "skipped_count": ids.size() - fired.size(),
        "recomputed": recomputed, "stats": stats, "tick": tick}
