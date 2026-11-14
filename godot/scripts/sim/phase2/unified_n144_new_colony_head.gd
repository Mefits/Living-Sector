extends RefCounted
## Frozen native/crates/sim_core/src/strategy/colony.rs::proposals:
## THE NEW-SITE branch only. A pure ranked source proposal for N134;
## it does not create a site, dock, market, ship, people, cargo or cash.
## Source coordination.rs::run_cycle later needs a single Head grant.
const SourceFounding = preload("res://scripts/sim/phase2/unified_n151_colony_founding_phase.gd")
const Commission = preload("res://scripts/sim/phase1/n151_native_colony_commission.gd")

static func _rejected(reason: String) -> Dictionary:
    return {"ok": true, "ready": false, "reason": reason,
        "blocked": [], "plan": {}, "candidate": {}}

static func _score(world: Dictionary, original: RefCounted, graph: RefCounted,
        faction: String, body_id: String, source: String) -> float:
    var body_rec: Dictionary = original.body_by_id(body_id)
    var body: Dictionary = body_rec.get("value", {})
    var supplies: Dictionary = world.get("bodies", {}).get(body_id, {}).get("resources", {})
    var ore: float = float(supplies.get("ore", 0.0))
    var ice: float = float(supplies.get("ice", 0.0))
    var gas: float = float(supplies.get("gas", 0.0))
    var local_gas: float = float(world.get("markets", {}).get(source, {}).get(
        "supply", {}).get("gas", 0.0))
    var distance: Dictionary = graph.shortest_path(source, body_id + "-colony")
    if not bool(distance.get("reachable", false)):
        return -1.0
    var d: float = float(distance.get("distance", -1.0))
    if not is_finite(d) or d < 0.0:
        return -1.0
    var same_system: bool = false
    for facility in world.get("facilities", {}).values():
        if str(facility.get("faction", "")) != faction or (
                str(facility.get("type", "")) != "station"):
            continue
        var home_rec: Dictionary = original.body_by_id(str(facility.get("body_id", "")))
        if str(home_rec.get("system_id", "")) == str(body_rec.get("system_id", "")):
            same_system = true
            break
    # Exact Rust colony.rs value, not arbitrary planet order:
    # gas value rises when original sponsoring market has <50 Gas.
    var gas_value: float = gas * (0.55 if local_gas < 50.0 else 0.10)
    var specialty: float = maxf(ore, maxf(ice, gas))
    var local_factor: float = 4.0 if same_system else 1.0
    var score: float = (0.1 + specialty + gas_value) * local_factor / (1.0 + d)
    return score if is_finite(score) and score > 0.0 else -1.0

## One faction, one actual best viable candidate, same sorting/tie
## priority as Rust. SourceFounding.proposal revalidates original orbit,
## technology, treasury, ship classes, true route and all 600 Metals.
static func propose(world: Dictionary, original: RefCounted, graph: RefCounted,
        faction: String, tick: int, mult: int) -> Dictionary:
    if original == null or graph == null or tick < 1 or mult < 1 or (
            not world.get("faction_treasuries", {}).has(faction)):
        return {"ok": false, "reason": "n144_no_real_faction_graph_or_tick"}
    if not (world.get("construction_sites") is Dictionary and
            world.get("bodies") is Dictionary and
            world.get("markets") is Dictionary):
        return {"ok": false, "reason": "n144_missing_single_world_site_registry"}
    # The original colony proposal completes an active project before
    # choosing new expansion, and one N98/N121 native funded commitment
    # cannot be displaced by another unsponsored construction decision.
    for site in world["construction_sites"].values():
        if str(site.get("faction_id", "")) == faction and (
                not bool(site.get("completed", false)) and
                site.get("labor", {}) is Dictionary and
                site["labor"].get("colony_source", null) != null):
            return _rejected("n144_existing_colony_expedition_takes_priority")
    var execution: Dictionary = world.get("native_planner_records", {}).get(faction, {})
    if str(execution.get("status", "")) in [
            "n98_planned_not_dispatched", "n121_active"]:
        return _rejected("n144_existing_native_n98_n121_commitment")
    var ids: Array = world["bodies"].keys()
    ids.sort()
    var source_ids: Array = world["markets"].keys()
    source_ids.sort()
    var best: Dictionary = {}
    var best_score: float = -INF
    var blocked: Array = []
    for raw_body_id in ids:
        var body_id: String = str(raw_body_id)
        var identity: Dictionary = original.body_by_id(body_id)
        if str(identity.get("value", {}).get("type", "")) != "planet":
            continue
        for raw_source in source_ids:
            var source: String = str(raw_source)
            var owner: String = str(world["markets"][source].get("owner", ""))
            var station: Dictionary = world.get("facilities", {}).get(owner, {})
            if str(station.get("type", "")) != "station" or (
                    str(station.get("faction", "")) != faction):
                continue
            # The original Rust may later support farther journeys.
            # Until the full physical N14 remote-founding reachability
            # is wired, the existing N151 source preflight is authoritative.
            var candidate: Dictionary = SourceFounding.proposal(
                world, original, graph, faction, body_id, source,
                tick, mult, true)
            if not candidate.get("ok", false):
                blocked.append({"body_id": body_id, "source": source,
                    "reason": str(candidate.get("reason", "source_preflight_blocked"))})
                continue
            var score: float = _score(world, original, graph, faction,
                body_id, source)
            if score <= 0.0:
                blocked.append({"body_id": body_id, "source": source,
                    "reason": "n144_invalid_original_valuation"})
                continue
            var destination: String = body_id + "-colony"
            # Rust: ready first; higher score first; lexical smaller
            # destination, then lexical smaller source on exact tie.
            if best.is_empty() or score > best_score or (
                    is_equal_approx(score, best_score) and (
                    destination < str(best["destination"]) or (
                    destination == str(best["destination"]) and
                    source < str(best["source"])))):
                best = candidate.duplicate(true)
                best_score = score
    if best.is_empty():
        return {"ok": true, "ready": false,
            "reason": "n144_no_source_ready_new_colony", "blocked": blocked,
            "plan": {}, "candidate": {}}
    var planet: String = str(best["body_id"])
    var source: String = str(best["source"])
    var destination: String = str(best["destination"])
    var quantity: int = 50 if world.get("research_directors", {}).has(faction) else Commission.SETTLERS
    var initial_cost: int = 3 * 10000 + 20000 + 150 + quantity * 80
    var goal: Dictionary = {
        "goal_id": "found_colony", "commodity": "metals",
        "destination": destination, "shortage_ticks": 0, "score": best_score}
    var plan: Dictionary = {
        "goal": goal, "faction_id": faction, "body_id": planet,
        "source": source, "destination": destination, "site_id": null,
        "cost": initial_cost, "quantity": quantity,
        "passenger": true, "reason": "ready"}
    return {"ok": true, "ready": true, "reason": "ready",
        "faction_id": faction, "plan": plan,
        "candidate": best, "blocked": blocked}
