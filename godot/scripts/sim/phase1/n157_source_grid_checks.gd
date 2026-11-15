extends RefCounted
## Rust sim_core/spatial/grid.rs six source-native tests, authored not run.
const Grid = preload("res://scripts/sim/phase1/n157_native_uniform_grid.gd")

static func run_all() -> Dictionary:
    var checks: Dictionary = {}
    var g = Grid.new()
    checks["configure_source_cell_size"] = g.configure(10.0) and g.cell_size() == 10.0
    checks["empty_before_insert"] = g.is_empty() and g.size() == 0
    g.insert("a", Vector2(0.0, 0.0))
    g.insert("b", Vector2(5.0, 5.0))
    g.insert("c", Vector2(25.0, 25.0))
    var hits: Array = g.query_radius(Vector2.ZERO, 10.0)
    checks["radius_hits_near_not_far"] = hits.has("a") and hits.has("b") and not hits.has("c")
    g.move_to("a", Vector2(100.0, 100.0))
    checks["moving_updates_bucket"] = (
        not g.query_radius(Vector2.ZERO, 5.0).has("a")
        and g.query_radius(Vector2(100.0, 100.0), 5.0).has("a"))
    checks["remove_forgets_position"] = (
        g.remove("a") == Vector2(100.0, 100.0)
        and g.position("a") == null and g.size() == 2)
    checks["distance_not_rectangle_only"] = (
        g.insert("near", Vector2(3.0, 4.0))
        and g.insert("far", Vector2(9.0, 9.0))
        and g.query_radius(Vector2.ZERO, 6.0).has("near")
        and not g.query_radius(Vector2.ZERO, 6.0).has("far"))
    var nearest: Dictionary = g.nearest(Vector2.ZERO, 20.0)
    checks["nearest_exact_euclidean"] = nearest.get("id") == "near" and absf(
        float(nearest.get("distance", -100.0)) - 5.0) < 0.0001
    checks["negative_cell_uses_floor"] = (
        g.cell_of(Vector2(-5.0, -5.0)) == Vector2i(-1, -1))
    checks["zero_query_returns_empty"] = g.query_radius(Vector2.ZERO, 0.0).is_empty()
    checks["bad_grid_size_rejected"] = not g.configure(-1.0)
    checks["rebuild_drops_old_buckets"] = (
        g.rebuild_from({"new": Vector2(50.0, 50.0)})
        and g.size() == 1
        and not g.query_radius(Vector2.ZERO, 20.0).has("near")
        and g.query_radius(Vector2(50.0, 50.0), 5.0).has("new"))
    var before: Dictionary = g.snapshot_positions()
    checks["invalid_rebuild_not_committed"] = (
        not g.rebuild_from({"broken": NAN}) and g.snapshot_positions() == before)
    var total_passed: int = 0
    for name in checks:
        if checks[name]:
            total_passed += 1
    return {"passed": total_passed, "total": checks.size(),
        "all_passed": total_passed == checks.size(), "checks": checks}
