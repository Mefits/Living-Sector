extends RefCounted
## Frozen Rust coordination.rs original N113 candidate reconstruction,
## over the ONE N39 world. Pure read-only. Research remains N143-owned,
## expansion N144-owned, and prior N111 quotes N154-owned.
const NativeResearch = preload("res://scripts/sim/phase2/unified_native_research_phase.gd")
const ResearchShift = preload("res://scripts/sim/phase1/n143_native_research_shift.gd")
const ResearchTech = preload("res://scripts/sim/strategy/native_technology_catalog.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")
const NativeNewColony = preload("res://scripts/sim/phase2/unified_n144_new_colony_head.gd")
const NativeColonyContracts = preload("res://scripts/sim/phase2/unified_n144_colony_contracts.gd")
const NativeConstruction = preload("res://scripts/sim/phase2/unified_native_construction_phase.gd")
const NativeN134Construction = preload("res://scripts/sim/phase2/unified_n134_construction_head.gd")
const N111 = preload("res://scripts/native_port/n111_options.gd")
const N155Director = preload("res://scripts/sim/phase1/n155_director_native_observation.gd")
const OriginalResearchMandate = preload("res://scripts/sim/phase1/n143_native_research_director.gd")
const OriginalCharter = preload("res://scripts/native_port/n109_charter.gd")

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _target(goal: Dictionary) -> String:
    return "%s|%s|%s" % [
        str(goal.get("goal_id", "")), str(goal.get("destination", "")),
        str(goal.get("commodity", ""))]

static func _research(world: Dictionary, faction: String,
        director: Dictionary, memory: Dictionary, tick: int) -> Dictionary:
    if not (world.get("markets") is Dictionary) or not (
            world.get("facilities") is Dictionary) or not (
            world.get("populations") is Dictionary) or not (
            world.get("faction_treasuries") is Dictionary):
        return _fail("n113_missing_real_n143_world")
    for market in world["markets"].values():
        if not (market is Dictionary) or not world[
                "facilities"].has(str(market.get("owner", ""))):
            return _fail("n113_research_market_without_original_facility")
    var occupied: Dictionary = Payroll.occupied(world, tick)
    var people: Array = NativeResearch._population_rows(world, occupied)
    var markets: Array = NativeResearch._market_rows(world)
    var mandates: Dictionary = world.get("research_mandates", {})
    var charters: Dictionary = world.get("faction_charters", {})
    var mandate: Dictionary = mandates.get(faction, {})
    var charter: Dictionary = charters.get(faction, {})
    var ready: Dictionary = ResearchShift.research_ready({
        "faction_id": faction, "tick": tick,
        "commander": director, "markets": markets, "people": people,
        "treasury": int(world["faction_treasuries"][faction]),
        # Exact N143 uses these SAME canonical policy maps. Empty means
        # original frozen Rust 0.6.7 autonomous default.
        "mandate": mandate, "charter": charter
    }, ResearchTech.all())
    if not ready.get("ok", false):
        return _fail("n113_native_research_ready_error:" +
            str(ready.get("reason", "unknown")))
    var target: String = str(director.get("research", ""))
    var score: float = -1.0
    if bool(ready.get("ready", false)) and not target.is_empty():
        var profile: Dictionary = director.get("profile", {})
        var science: float = float(profile.get("science", -1.0))
        if not is_finite(science) or science < 0.0:
            return _fail("n113_missing_source_science_profile")
        score = 18.0 * science + (2.0 if str(
            memory.get("kind", "")) == "research" else 0.0)
        # Rust coordination.rs adds the player charter PRIORITY (not
        # money) only for a genuinely active delegated research mandate
        # whose original charter allows player direction. N143 still
        # owns the real paid authorization and N9 receipt.
        var active: Dictionary = OriginalResearchMandate.active_mandate(
            mandates, faction, director.get("technologies", []))
        if str(active.get("mode", "")) == "delegated" and (
                OriginalCharter.may_direct(charters, faction, "research")):
            score += OriginalCharter.priority_score(
                charters, faction, "research", 160.0)
    return {"ok": true, "offer": {
        "action": "research", "target": target,
        "score": score, "available": score > 0.0,
        "reason": "paid_science_available" if score > 0.0 else
            str(ready.get("reason", "research_resources_unavailable"))}}

static func _expansion(world: Dictionary, faction: String,
        director: Dictionary, original: RefCounted,
        graph: RefCounted, tick: int, multiplier: int) -> Dictionary:
    # Rust colony::proposals prefers the established ACTIVE site branch.
    # It can require a real paid metals or passenger mission, and the
    # new-site branch cannot outrank such an unfinished project.
    var active: Dictionary = NativeColonyContracts.active_site(
        world, graph, faction, tick, multiplier)
    if not active.get("ok", false):
        return _fail("n113_invalid_original_active_colony_site:" +
            str(active.get("reason", "unknown")))
    var plan: Dictionary = active.get("plan", {})
    var score: float = -1.0
    var reason: String = str(active.get("reason", "not_ready"))
    if bool(active.get("ready", false)) and not plan.is_empty():
        score = 80.0
    elif reason == "no_active_native_colony_site":
        # No active project: original Rust's colony::proposals may
        # choose a newly feasible planet with one real native quote.
        var founding: Dictionary = NativeNewColony.propose(
            world, original, graph, faction, tick, multiplier)
        if not founding.get("ok", false):
            return _fail("n113_invalid_original_new_colony_quote:" +
                str(founding.get("reason", "unknown")))
        if bool(founding.get("ready", false)):
            plan = founding.get("plan", {})
            var expansion: float = float(director.get(
                "profile", {}).get("expansion", -1.0))
            if not is_finite(expansion) or expansion < 0.0:
                return _fail("n113_missing_real_expansion_profile")
            score = 25.0 * expansion
        reason = str(founding.get("reason", "not_ready"))
    var goal: Dictionary = plan.get("goal", {})
    return {"ok": true, "offer": {"action": "expand",
        "target": _target(goal) if not goal.is_empty() else "",
        "score": score, "available": score > 0.0,
        "reason": reason}}

static func _previous_supply(world: Dictionary, faction: String,
        director: Dictionary, memory: Dictionary,
        sources: Dictionary, original: RefCounted,
        graph: RefCounted, tick: int, multiplier: int) -> Dictionary:
    if str(memory.get("kind", "")) != "supply":
        return {"ok": true, "resolved": true, "offer": {}}
    var prior: String = str(memory.get("target", ""))
    if prior.is_empty():
        return _fail("n113_invalid_original_previous_supply_target")
    # N154's canonical source offers contain the ONLY grounded N111
    # construction cost/output quote. Never reuse yesterday's N113
    # strategic.score as current source profitability.
    var observed: Dictionary = NativeConstruction.observe(
        world, sources, original, graph, faction, tick)
    if not observed.get("ok", false):
        return {"ok": true, "resolved": false, "offer": {},
            "reason": "n113_prior_supply_original_n154_quote_unavailable"}
    var rows: Variant = observed.get("view", {}).get("offers", null)
    if not (rows is Array):
        return {"ok": true, "resolved": false, "offer": {},
            "reason": "n113_missing_original_n154_goal_catalogue"}
    var candidate: Dictionary = {}
    for raw in rows:
        if not (raw is Dictionary):
            return _fail("n113_invalid_original_n154_offer")
        var goal: Variant = raw.get("goal", {})
        if goal is Dictionary and _target(goal) == prior:
            candidate = raw
            break
    if candidate.is_empty():
        # N134's construction-only option set is narrower than the
        # Rust full logistics/source comparator; unknown != extinct.
        return {"ok": true, "resolved": false, "offer": {},
            "reason": "n113_prior_supply_not_in_source_n154_catalogue"}
    var goal: Dictionary = candidate.get("goal", {})
    var location: String = str(goal.get("destination", ""))
    var market: Dictionary = world.get("markets", {}).get(location, {})
    if market.is_empty():
        return _fail("n113_prior_supply_original_market_missing")
    var forecast: Dictionary = NativeN134Construction._forecast(
        world, candidate)
    var quoted: Dictionary = N111.compare_goal(goal, market,
        {"reason": "n121_subsidy_quote_not_available"}, forecast,
        int(world["faction_treasuries"][faction]), multiplier,
        NativeN134Construction.DEMAND_WINDOW,
        NativeN134Construction.SHIPMENT_TIME,
        NativeN134Construction.DELIVERY_REWARD,
        NativeN134Construction.CONSTRUCTION_PAYMENT,
        NativeN134Construction.MATERIAL_LOT)
    var selection: String = str(quoted.get("selected", "wait"))
    var score: float = -1.0
    for row in quoted.get("alternatives", []):
        if not (row is Dictionary) or str(row.get(
                "action", "")) != selection:
            continue
        score = N155Director.option_score(director, goal, row)
        break
    # This bridge can PROVE an old N154 build remains viable, but
    # N135/N121 may still fulfill the same prior supply goal via a
    # separate funded transport that N154's local builder cannot see.
    # "no positive N154 quote" is NOT a proof that the old Rust supply
    # commitment has disappeared. Preserve it conservatively.
    if not is_finite(score) or score <= 0.0:
        return {"ok": true, "resolved": false, "offer": {},
            "reason": "n113_prior_supply_logistics_quote_not_reconstructed"}
    return {"ok": true, "resolved": true, "offer": {
        "action": "supply", "target": prior,
        "score": score, "available": true,
        "reason": "previous_supply_still_feasible"}}

## Caller already has the exact N134 Head and physically verified N147
## migration quote, and has rechecked it against CURRENT source World.
## Returns research, expansion, and previous *different* supply alternatives.
static func project(world: Dictionary, sources: Dictionary,
        original: RefCounted, graph: RefCounted,
        faction: String, head: Dictionary, tick: int,
        multiplier: int) -> Dictionary:
    if original == null or graph == null or tick < 1 or multiplier < 1 or (
            not sources.has(faction)) or not world.get(
            "research_directors", {}).has(faction):
        return _fail("n113_missing_original_world_source_or_faction")
    var director: Dictionary = world["research_directors"][faction]
    var raw: Variant = director.get("strategic", {})
    if not (raw is Dictionary):
        return _fail("n113_invalid_original_retained_memory")
    var memory: Dictionary = raw
    var research: Dictionary = _research(
        world, faction, director, memory, tick)
    if not research.get("ok", false):
        return research
    var expansion: Dictionary = _expansion(
        world, faction, director, original, graph, tick, multiplier)
    if not expansion.get("ok", false):
        return expansion
    var previous: Dictionary = _previous_supply(
        world, faction, director, memory, sources,
        original, graph, tick, multiplier)
    if not previous.get("ok", false):
        return previous
    var rows: Array = [research["offer"], expansion["offer"]]
    if not previous.get("offer", {}).is_empty():
        rows.append(previous["offer"])
    return {"ok": true, "offers": rows, "prior_supply_resolved": bool(
        previous.get("resolved", false)),
        "prior_supply_reason": str(previous.get("reason", "")),
        "source": "current_n143_research_n144_colony_n111_prior_supply"}
