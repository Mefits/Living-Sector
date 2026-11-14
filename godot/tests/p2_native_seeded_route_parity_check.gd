extends SceneTree
## N142/N4: prove the physical reverse corridors originally created by
## Rust sim_db::seeder, WITHOUT changing generic directed graph semantics.
## No Github Actions; coordinate with one later headless Godot gate.
const Native = preload("res://scripts/native_data.gd")
const RawGraph = preload("res://scripts/sim/route_graph.gd")
const Registry = preload("res://scripts/sim/world_registry.gd")
const Audit = preload("res://scripts/sim/route_graph_audit.gd")
const Adapter = preload("res://scripts/sim/phase2/n158_galaxy_production_seed.gd")
const World = preload("res://scripts/sim/world_model.gd")
const Locations = preload("res://scripts/sim/ships/native_location_resolver.gd")
const Ships = preload("res://scripts/sim/phase2/unified_ship_phase.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("real frozen Galaxy source missing")
        return
    var raw = RawGraph.new()
    var registry = Registry.new()
    if not raw.load_worlds(seed["worlds"]) or not registry.load_seed(seed):
        _fail("raw JSON or original Rust database seeder graph rejected")
        return
    var db: RefCounted = registry.graph()
    if raw.edge_count() != 12 or db.edge_count() != 24:
        _fail("expected 12 raw forward and 24 native SQLite corridor rows")
        return
    if raw.shortest_path("alpha-station", "earth-station").get("reachable", false):
        _fail("generic raw directed graph changed unexpectedly")
        return
    if not db.shortest_path("alpha-station", "earth-station").get("reachable", false):
        _fail("original Rust seeded return path absent")
        return
    var audit = Audit.new()
    if not audit.audit(seed["worlds"], raw).get("ok", false) or not audit.audit(
            seed["worlds"], db, true).get("ok", false):
        _fail("N58 provenance against raw and SQLite-seeded route modes failed")
        return
    if audit.audit(seed["worlds"], db).get("ok", false):
        _fail("N58 failed to distinguish raw JSON and seeded native DB")
        return
    for world in seed["worlds"]:
        for edge in world["travel_routes"]:
            var src: String = str(edge["from"])
            var dst: String = str(edge["to"])
            var distance: float = float(edge["distance"])
            var forward: bool = false
            var backward: bool = false
            for row in db.outgoing(src):
                if str(row.get("to", "")) == dst and float(row.get("distance", -1)) == distance:
                    forward = true
            for row in db.outgoing(dst):
                if str(row.get("to", "")) == src and float(row.get("distance", -1)) == distance:
                    backward = true
            if not forward or not backward:
                _fail("missing original N142 SQLite corridor pair: " + src + " <-> " + dst)
                return
    var return_trip: Dictionary = db.shortest_path(
        "pirate-outpost", "earth-station")
    if not return_trip.get("reachable", false) or return_trip.get("locations", []) != [
            "pirate-outpost", "lane-barnard", "lane-tau",
            "lane-epsilon", "earth-station"] or not is_equal_approx(
            float(return_trip.get("distance", -1)), 855.0):
        _fail("Rust-seeded multi-system reverse corridor has wrong physical cost")
        return
    if db.has_location("mars-colony") or db.shortest_path(
            "earth-station", "mars-colony").get("reachable", false):
        _fail("invalid phantom colony navigation inferred from reversible routes")
        return
    var model = World.new()
    var resolver = Locations.new()
    if not model.load_seed(seed) or not resolver.load_seed(seed):
        _fail("native N43 moving world failed to load")
        return
    var points: Dictionary = resolver.positions_from_world(model, 0.0, true)
    var native: Dictionary = Adapter.from_seed(seed)
    if not points.get("ok", false) or not native.get("ok", false):
        _fail("real physical world/positions unavailable")
        return
    var before: Dictionary = native["world"]
    var target_ship: String = ""
    for id in before["ships"]:
        var ship: Dictionary = before["ships"][id]
        if str(ship.get("location", "")) == "alpha-station" and (
                ship.get("transit", {}) is Dictionary and ship["transit"].is_empty()):
            target_ship = str(id)
            break
    if target_ship.is_empty():
        _fail("no real native Alpha Centauri starter hull")
        return
    var rejected: Dictionary = Ships.depart(before, raw,
        points["positions"], 1, 1.0, target_ship, "earth-station")
    if rejected.get("ok", false):
        _fail("raw JSON accidentally granted return corridor")
        return
    var accepted: Dictionary = Ships.depart(before, db,
        points["positions"], 1, 1.0, target_ship, "earth-station")
    if not accepted.get("ok", false) or str(accepted.get("ships", {}).get(
            target_ship, {}).get("transit", {}).get("to", "")) != "earth-station":
        _fail("real N14 ship cannot depart on Rust-seeded return leg")
        return
    if before["ships"][target_ship]["transit"] != {}:
        _fail("N14 pure departure mutated original N39 input")
        return
    print("P2_NATIVE_SEEDED_ROUTES_N14_RETURN_FLIGHT_NO_GHOST_COLONY_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_NATIVE_SEED_ROUTE_FAIL: " + reason)
    quit(1)
