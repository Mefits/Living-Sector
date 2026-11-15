extends RefCounted
## Frozen Rust native/crates/sim_db/src/spawner.rs::chart_colony_routes.
## This is a DB navigation chart ONLY, never an inhabited colony.
## SQL: INSERT OR IGNORE planet location as "body-colony", then for
## every different pair in the SAME star system where at least one end
## has loc_type="colony", INSERT OR IGNORE the directed route of cost
## max(8, CAST(8 + 10 * abs(orbit_radius_a-orbit_radius_b) AS INTEGER)).
## We retain the original seeder's existing corridors on conflict.
static func chart(worlds: Array) -> Dictionary:
    var bodies: Dictionary = {}
    var locations: Dictionary = {}
    for row in worlds:
        if not (row is Dictionary and row.get("system") is Dictionary):
            return {"ok": false, "reason": "n142_invalid_native_world"}
        var system_id: String = str(row["system"].get("id", ""))
        if system_id.is_empty():
            return {"ok": false, "reason": "n142_missing_source_system"}
        for raw_body in row.get("bodies", []):
            if not (raw_body is Dictionary):
                return {"ok": false, "reason": "n142_invalid_native_body"}
            var bid: String = str(raw_body.get("id", ""))
            var radius: Variant = raw_body.get("orbit_radius", null)
            if bid.is_empty() or bodies.has(bid) or not (radius is int or radius is float) or not is_finite(float(radius)) or float(radius) < 0.0:
                return {"ok": false, "reason": "n142_missing_authentic_orbit"}
            bodies[bid] = {"system_id": system_id, "orbit_radius": float(radius),
                "body_type": str(raw_body.get("type", ""))}
        for raw in row.get("facilities", []):
            if not (raw is Dictionary):
                return {"ok": false, "reason": "n142_invalid_seed_facility"}
            var location: String = str(raw.get("location", ""))
            var body_id: String = str(raw.get("body", ""))
            if location.is_empty() or body_id.is_empty() or not bodies.has(body_id) or str(bodies[body_id]["system_id"]) != system_id:
                return {"ok": false, "reason": "n142_station_without_source_body"}
            if locations.has(location) and str(locations[location]["body_id"]) != body_id:
                return {"ok": false, "reason": "n142_conflicting_station_location"}
            locations[location] = {"body_id": body_id, "system_id": system_id, "colony": false}
        for raw in row.get("nav_sites", []):
            if not (raw is Dictionary):
                return {"ok": false, "reason": "n142_invalid_seed_nav"}
            var location: String = str(raw.get("name", ""))
            var body_id: String = str(raw.get("body", ""))
            if location.is_empty() or body_id.is_empty() or not bodies.has(body_id) or str(bodies[body_id]["system_id"]) != system_id:
                return {"ok": false, "reason": "n142_nav_without_source_body"}
            if not locations.has(location):
                locations[location] = {"body_id": body_id, "system_id": system_id, "colony": false}
            elif str(locations[location]["body_id"]) != body_id:
                return {"ok": false, "reason": "n142_conflicting_nav_location"}
    var charted: Dictionary = {}
    var body_keys: Array = bodies.keys()
    body_keys.sort()
    for body_id in body_keys:
        if str(bodies[body_id]["body_type"]) != "planet":
            continue
        var proposed_id: String = str(body_id) + "-colony"
        if not locations.has(proposed_id):
            var info: Dictionary = bodies[body_id]
            locations[proposed_id] = {"body_id": str(body_id),
                "system_id": str(info["system_id"]), "colony": true}
            charted[proposed_id] = locations[proposed_id].duplicate(true)
        elif str(locations[proposed_id]["body_id"]) != str(body_id):
            return {"ok": false, "reason": "n142_conflicting_colony_location"}
    var edges: Array = []
    var ids: Array = locations.keys()
    ids.sort()
    for origin in ids:
        var start: Dictionary = locations[origin]
        var origin_body: Dictionary = bodies[str(start["body_id"])]
        for destination in ids:
            if origin == destination:
                continue
            var target: Dictionary = locations[destination]
            if str(start["system_id"]) != str(target["system_id"]) or not (bool(start["colony"]) or bool(target["colony"])):
                continue
            var target_body: Dictionary = bodies[str(target["body_id"])]
            var distance: int = maxi(8, int(8.0 + 10.0 * absf(
                float(origin_body["orbit_radius"]) - float(target_body["orbit_radius"]))))
            edges.append({"from": str(origin), "to": str(destination),
                "distance": distance, "system_id": str(start["system_id"])})
    return {"ok": true, "charted": charted, "locations": locations,
        "edges": edges, "source": "native spawner::chart_colony_routes SQL"}
