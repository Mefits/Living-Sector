extends SceneTree
## Deferred source N113 research/expansion/old-supply candidate checks.
## No actual Godot execution until whole Rust->Godot joint acceptance.
const Original = preload("res://scripts/sim/phase2/unified_n113_original_candidates.gd")

class NoInventedBodies extends RefCounted:
    func body_by_id(_body_id: String) -> Dictionary:
        return {}
    func seed_universe_position(_system_id: String) -> Vector2:
        return Vector2.ZERO

class NoInventedRoutes extends RefCounted:
    func shortest_path(_src: String, _dst: String) -> Dictionary:
        return {"reachable": false, "distance": -1}
    func has_location(_location: String) -> bool:
        return false

func _fail(msg: String) -> void:
    push_error("P2_N113_REAL_CANDIDATES: " + msg)
    quit(1)

func _world() -> Dictionary:
    return {
        "faction_treasuries": {"own": 20000},
        "research_directors": {"own": {
            "research": "industrial_methods", "technologies": [],
            "research_required": 40, "crisis": false,
            "profile": {"industry": 1.0, "science": 1.5,
                "expansion": 1.0},
            "strategic": {"kind": "research",
                "target": "industrial_methods", "since": 10,
                "score": 30.0, "reason": "", "pending": null}}},
        "facilities": {"station-a": {
            "id": "station-a", "faction": "own", "type": "station",
            "location": "alpha", "body_id": "planet-a",
            "credits": 100}},
        "markets": {"alpha": {
            "id": "market-a", "owner": "station-a",
            "supply": {"electronics": 5.0, "food": 30.0,
                "water": 20.0}, "prices": {"electronics": 4.4,
                "food": 3.0, "water": 3.0}}},
        "populations": {"worker-a": {"faction": "own",
            "location": "alpha", "count": 100, "wealth": 20}},
        "construction_sites": {}, "construction_contracts": {},
        "construction_receipts": {}, "bodies": {},
        "contract_board": {"contracts": {}},
        "native_planner_records": {},
        "native_execution": {"active": {}}
    }

func _initialize() -> void:
    var state: Dictionary = _world()
    var exact: Dictionary = state.duplicate(true)
    var director: Dictionary = state["research_directors"]["own"]
    var research: Dictionary = Original._research(state, "own",
        director, director["strategic"], 60)
    if not research.get("ok", false) or not research[
            "offer"]["available"] or not is_equal_approx(
            float(research["offer"]["score"]), 29.0):
        _fail("real N143 ready electronics/treasury/workers score not 18*1.5+2")
        return
    var no_cash: Dictionary = state.duplicate(true)
    no_cash["faction_treasuries"]["own"] = 10015
    research = Original._research(no_cash, "own",
        no_cash["research_directors"]["own"],
        no_cash["research_directors"]["own"]["strategic"], 60)
    if not research.get("ok", false) or bool(research[
            "offer"]["available"]):
        _fail("source N143 strict > reserve wrongly permitted research")
        return
    var no_electronics: Dictionary = state.duplicate(true)
    no_electronics["markets"]["alpha"]["supply"]["electronics"] = 0.0
    research = Original._research(no_electronics, "own",
        no_electronics["research_directors"]["own"],
        no_electronics["research_directors"]["own"]["strategic"], 60)
    if not research.get("ok", false) or bool(
            research["offer"]["available"]):
        _fail("source research invented local Electronics")
        return
    var no_workers: Dictionary = state.duplicate(true)
    no_workers["populations"]["worker-a"]["count"] = 10
    research = Original._research(no_workers, "own",
        no_workers["research_directors"]["own"],
        no_workers["research_directors"]["own"]["strategic"], 60)
    if not research.get("ok", false) or bool(
            research["offer"]["available"]):
        _fail("source research invented native free workforce")
        return
    var crisis: Dictionary = state.duplicate(true)
    crisis["research_directors"]["own"]["crisis"] = true
    research = Original._research(crisis, "own",
        crisis["research_directors"]["own"],
        crisis["research_directors"]["own"]["strategic"], 60)
    if not research.get("ok", false) or bool(
            research["offer"]["available"]):
        _fail("source Director crisis cannot choose paid research")
        return
    var exp: Dictionary = Original._expansion(state, "own",
        director, NoInventedBodies.new(), NoInventedRoutes.new(), 60, 1)
    if not exp.get("ok", false) or bool(exp["offer"]["available"]):
        _fail("empty original physical bodies spawned a fake colony site")
        return
    var old_supply: Dictionary = state.duplicate(true)
    old_supply["research_directors"]["own"]["strategic"][
        "kind"] = "supply"
    old_supply["research_directors"]["own"]["strategic"][
        "target"] = "unknown|alpha|food"
    var prior: Dictionary = Original._previous_supply(
        old_supply, "own",
        old_supply["research_directors"]["own"],
        old_supply["research_directors"]["own"]["strategic"],
        {}, NoInventedBodies.new(), NoInventedRoutes.new(), 60, 1)
    if not prior.get("ok", false) or bool(prior.get(
            "resolved", true)) or not prior.get("offer", {}).is_empty():
        _fail("unknown old N111 supply quote was treated as a vanished goal")
        return
    if state != exact:
        _fail("source N113 candidates modified the ONLY N39 world")
        return
    print("P2_N113_RESEARCH_EXPANSION_SOURCE_READINESS_PASS")
    quit(0)
