extends SceneTree
## Deferred original Rust N109/N110 + N143 paid receipt + N113 priority.
## One canonical World policy, no second funds. NOT EXECUTED until final P2.
const Charter = preload("res://scripts/native_port/n109_charter.gd")
const Mandate = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const Research = preload("res://scripts/sim/phase2/unified_native_research_phase.gd")
const Shift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")
const Tech = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const OriginalN113 = preload("res://scripts/sim/phase2/unified_n113_original_candidates.gd")

func _fail(reason: String) -> void:
    push_error("P2_ORIGINAL_N109_N110_SOURCE: " + reason)
    quit(1)

func _world() -> Dictionary:
    return {
        "faction_treasuries": {"own": 20000},
        "research_directors": {"own": {
            "technologies": [], "research": "industrial_methods",
            "research_required": 40, "progress": 0,
            "last_research_tick": null, "last_shift": null, "history": [],
            "crisis": false,
            "profile": {"industry": 1.0, "science": 1.5, "expansion": 1.0},
            "strategic": {"kind": "research", "target": "industrial_methods",
                "score": 29.0, "since": 15, "reason": "", "pending": null}}},
        "research": {"own": []}, "research_receipts": {},
        "research_mandates": {}, "faction_charters": {},
        "facilities": {"station-a": {
            "id": "station-a", "type": "station", "faction": "own",
            "location": "alpha", "body_id": "planet-a", "credits": 100}},
        "markets": {"alpha": {
            "id": "market-a", "owner": "station-a",
            "supply": {"electronics": 5.0, "food": 30.0, "water": 20.0},
            "prices": {"electronics": 4.4, "food": 3.0, "water": 3.0}}},
        "populations": {"worker-a": {
            "faction": "own", "location": "alpha", "count": 100,
            "wealth": 20}}, "construction_sites": {},
        "contract_board": {"contracts": {}}}

func _science(world: Dictionary) -> Dictionary:
    var director: Dictionary = world["research_directors"]["own"]
    return OriginalN113._research(world, "own", director,
        director["strategic"], 60)

func _initialize() -> void:
    var world: Dictionary = _world()
    var clean: Dictionary = world.duplicate(true)
    var default_research: Dictionary = _science(world)
    if not default_research.get("ok", false) or not is_equal_approx(
            float(default_research["offer"]["score"]), 29.0):
        _fail("original clean seed acquired player priority without mandate")
        return
    var incoming: Dictionary = {"target_technology": "industrial_methods",
        "mode": "delegated", "budget_ceiling_cr": 300,
        "treasury_floor_cr": 10000, "spent_cr": 0}
    var m: Dictionary = Mandate.update_mandate(
        {}, incoming, 50, Mandate.catalogue_map(Tech.all()))
    if not m.get("ok", false):
        _fail("original N110 delegated policy validation refused")
        return
    world["research_mandates"]["own"] = m["mandate"]
    var charter: Dictionary = Charter.default_charter()
    charter["research_authority"] = "review"
    charter["approved_research_cr"] = 100
    charter["shared_ceiling_cr"] = 1000
    charter["research_priority"] = 80
    var c: Dictionary = Charter.install(
        {}, "own", charter, ["own"], 50)
    if c.has("error"):
        _fail("original N109 approved research charter refused")
        return
    world["faction_charters"]["own"] = c["charter"]
    var expected_score: float = 29.0 + 160.0 + 2.0 * (80.0 - 50.0)
    var decision: Dictionary = _science(world)
    if not decision.get("ok", false) or not is_equal_approx(
            float(decision["offer"]["score"]), expected_score):
        _fail("source N113 delegated research ranking omitted charter priority")
        return
    var before: Dictionary = world.duplicate(true)
    var intent: Dictionary = Research.propose(
        world, {"own": {"id": "own",
            "personality": {"prefer_goals": {"leader_technocrat": 2.0}}}},
        60, 1)
    if not intent.get("ok", false) or intent.get(
            "shifts", []).size() != 1:
        _fail("N143 live research did not use real N109/N110 policies")
        return
    var shift: Dictionary = intent["shifts"][0]
    if not bool(shift.get("mandated_shift", false)) or (
            shift["mandate_preconditions"] != world[
                "research_mandates"]["own"]) or (
            shift["charter_preconditions"] != world[
                "faction_charters"]["own"]) or int(
            shift.get("cost", 0)) != 15:
        _fail("N143 source policy and actual paid-shift proposal diverged")
        return
    if int(shift["mandate_after"]["spent_cr"]) != 15 or (
            int(shift["charter_after"]["spent_cr"]) != 15) or (
            int(shift["charter_after"]["spent_research_cr"]) != 15):
        _fail("original counters would not match a real 15CR N9 receipt")
        return
    if before != world:
        _fail("pure N143 research preflight wrote World/credits prematurely")
        return

    var low_budget: Dictionary = world.duplicate(true)
    low_budget["research_mandates"]["own"]["spent_cr"] = 295
    var blocked: Dictionary = _science(low_budget)
    if not blocked.get("ok", false) or bool(
            blocked["offer"]["available"]):
        _fail("delegated research exceeded original cumulative budget")
        return
    var holding: Dictionary = world.duplicate(true)
    holding["research_mandates"]["own"]["mode"] = "hold"
    if _science(holding)["offer"]["available"]:
        _fail("hold policy funded autonomous research")
        return
    var no_tranche: Dictionary = world.duplicate(true)
    no_tranche["faction_charters"]["own"]["approved_research_cr"] = 10
    if _science(no_tranche)["offer"]["available"]:
        _fail("review without enough player approval funded research")
        return
    var autonomous: Dictionary = world.duplicate(true)
    autonomous["faction_charters"]["own"]["research_authority"] = "autonomous"
    var normal: Dictionary = _science(autonomous)
    if not normal["offer"]["available"] or not is_equal_approx(
            float(normal["offer"]["score"]), 29.0):
        _fail("autonomous charter still added player delegated priority")
        return

    var reconfigured: Dictionary = Mandate.update_mandate(
        shift["mandate_after"], incoming, 80,
        Mandate.catalogue_map(Tech.all()))
    if not reconfigured.get("ok", false) or int(
            reconfigured["mandate"]["spent_cr"]) != 15:
        _fail("N110 reconfiguration erased already-paid original spend")
        return
    var lowered: Dictionary = incoming.duplicate(true)
    lowered["budget_ceiling_cr"] = 10
    if Mandate.update_mandate(
            shift["mandate_after"], lowered, 80,
            Mandate.catalogue_map(Tech.all())).get("ok", true):
        _fail("new policy incorrectly lowered budget below source minimum")
        return
    var revised_charter: Dictionary = Charter.install({
        "own": shift["charter_after"]}, "own",
        Charter.default_charter(), ["own"], 80)
    if revised_charter.has("error") or int(
            revised_charter["charter"]["spent_research_cr"]) != 15:
        _fail("N109 reconfiguration erased prior approved research payment")
        return
    print("P2_N109_N110_N143_N113_NATIVE_POLICY_SOURCE_CHECK_PASS")
    quit(0)
