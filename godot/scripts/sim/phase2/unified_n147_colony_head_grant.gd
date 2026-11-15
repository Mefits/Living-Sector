extends RefCounted
## Frozen Rust strategy/coordination.rs::run_cycle (migrants only).
## A source N147 ready offer is NOT a faction grant. In the original ECS
## the actual Head must choose "migrate_colony" before N92::commission
## posts a paid N104 Passenger order. This is a pure read-only grant
## validation/proposal: the one N39 World/N9/ContractBoard owns Apply.
const SourceMigrationScore: float = 60.0
const SourceN113 = preload("res://scripts/sim/phase2/unified_n113_strategy_switch.gd")
const SourceN113Candidates = preload("res://scripts/sim/phase2/unified_n113_original_candidates.gd")

## Frozen Rust director.rs::option_score for CURRENT authentic N111
## alternative, never stale N113.strategic.score or a synthetic bid.
static func _native_supply_offer(head: Dictionary,
        director: Dictionary) -> Dictionary:
    var selection: String = str(head.get("selected_option", ""))
    if selection not in ["deliver", "build"]:
        return {}
    var goal: Variant = head.get("problem", null)
    var profile: Variant = director.get("profile", null)
    if not (goal is Dictionary) or goal.is_empty() or (
            not (profile is Dictionary)):
        return {}
    var target: String = "%s|%s|%s" % [
        str(goal.get("goal_id", "")),
        str(goal.get("destination", "")),
        str(goal.get("commodity", ""))]
    if target.begins_with("|") or str(goal.get("destination", "")).is_empty():
        return {}
    var alternatives: Variant = head.get("alternatives", null)
    if not (alternatives is Array):
        return {}
    for raw in alternatives:
        if not (raw is Dictionary):
            continue
        var alt: Dictionary = raw
        if str(alt.get("action", "")) != selection or (
                str(alt.get("status", "")) != "ready"):
            continue
        var site: bool = alt.get("site_id", null) != null and (
            not str(alt.get("site_id", "")).is_empty())
        var industry: float = float(profile.get("industry", -1.0))
        if not is_finite(industry) or industry < 0.0:
            return {}
        var score: float = -1.0
        if selection == "build" and (str(goal.get("goal_id", "")) in [
                "develop_colony", "player_industry"] or (
                str(goal.get("destination", "")).ends_with("-colony")
                and site)):
            score = 35.0 * industry + (8.0 if site else 0.0)
        else:
            var covered: float = float(alt.get("covered_units", -1.0))
            var net_value: Variant = alt.get("estimated_net_value", null)
            if not is_finite(covered) or covered <= 0.0 or (
                    not (net_value is float or net_value is int)):
                return {}
            var net: float = float(net_value)
            if not is_finite(net) or net <= 0.0:
                return {}
            score = log(1.0 + net) * (
                industry if selection == "build" else 1.0)
            score += float(mini(1000, maxi(0, int(
                goal.get("shortage_ticks", 0))))) * 0.01
            if site:
                score += 5.0
        if not is_finite(score) or score <= 0.0:
            return {}
        return {"action": "supply", "target": target,
            "score": score, "available": true,
            "reason": str(head.get("reason", ""))}
    return {}


static func _fail(why: String) -> Dictionary:
    return {"ok": false, "reason": why}

static func authorize(world: Dictionary, faction: String, ready: Dictionary,
        baseline: Dictionary, tick: int, sources: Dictionary = {},
        original: RefCounted = null, graph: RefCounted = null,
        multiplier: int = 1) -> Dictionary:
    if tick <= 0 or faction.is_empty() or not (
            world.get("faction_treasuries") is Dictionary) or not (
            world.get("research_directors") is Dictionary) or not (
            world.get("contract_board") is Dictionary):
        return _fail("n147_missing_source_head_authority")
    if not world["faction_treasuries"].has(faction) or not (
            world["research_directors"].get(faction) is Dictionary):
        return _fail("n147_no_actual_faction_director")
    if ready.get("faction_id", null) != faction or (
            str(ready.get("status", "")) != "N147_PREPARED_NOT_POSTED"):
        return _fail("n147_untrusted_or_old_migration_offer")
    var destination: String = str(ready.get("destination", ""))
    var origin: String = str(ready.get("source", ""))
    var passengers: int = int(ready.get("quantity", -1))
    var price: int = int(ready.get("payment", -1))
    if destination.is_empty() or origin.is_empty() or origin == destination or (
            passengers <= 0 or price <= 0):
        return _fail("n147_bad_physical_migration_terms")
    if int(baseline.get("observed_tick", -1)) != tick:
        return _fail("n147_head_not_from_this_decision_tick")
    var choice: String = str(baseline.get("selected_option", ""))
    # A live N134 build/deliver option is a candidate to re-score,
    # NOT automatic authority for a second paid action. Real existing
    # N104/Construction financial commitments are blocked below.
    if choice not in ["wait", "migrate_colony", "build", "deliver"] or str(
            baseline.get("reason", "")) in [
            "already_commissioned_this_tick",
            "outstanding_native_plan_retained"]:
        return {"ok": true, "authorized": false,
            "reason": "n147_other_original_head_grant_retained"}
    if choice == "wait" and not str(baseline.get(
            "selected_administrator", "")).is_empty():
        return {"ok": true, "authorized": false,
            "reason": "n147_wait_head_has_another_grant"}
    var record: Dictionary = world.get("native_planner_records", {}).get(
        faction, {})
    if str(record.get("status", "")) in [
            "n98_planned_not_dispatched", "n121_active"] or (
            world.get("native_execution", {}).get(
                "active", {}).has(faction)):
        return {"ok": true, "authorized": false,
            "reason": "n147_one_existing_native_plan_first"}
    var contracts: Variant = world["contract_board"].get("contracts", null)
    if not (contracts is Dictionary):
        return _fail("n147_missing_original_n104_contracts")
    for c in contracts.values():
        if not (c is Dictionary):
            return _fail("n147_invalid_real_contract")
        if str(c.get("requestor_id", "")) in [
                "faction/" + faction, faction] and str(
                c.get("status", "")) not in ["paid", "expired"] and (
                int(c.get("posted_at_tick", -1)) == tick or str(
                c.get("mission_category", "")) in [
                "strategy.colony.v1", "strategy.colony.workforce.v1",
                "strategy.construction.v1"]):
            return {"ok": true, "authorized": false,
                "reason": "n147_existing_original_funded_head_commit"}
    var director: Dictionary = world["research_directors"][faction]
    # Rust Director::build_candidates excludes migration in an active
    # faction survival crisis, even when N92 has a physical passenger plan.
    if bool(director.get("crisis", false)):
        return {"ok": true, "authorized": false,
            "reason": "n147_original_director_survival_first"}
    var old: Variant = director.get("strategic", {})
    if not (old is Dictionary):
        return _fail("n147_invalid_retained_director_strategy")
    var memory: Dictionary = old
    var incumbent: String = str(memory.get("kind", ""))
    var current_target: String = str(memory.get("target", ""))
    # All migration candidates have ALREADY passed real N92/N147
    # inhabitants/market/cargo/seats/route/fuel/treasury preflight.
    var options: Array = [{"action": "migrate", "target": destination,
        "score": SourceMigrationScore, "available": true,
        "reason": "colony_needs_workers"}]
    var real_supply: Dictionary = _native_supply_offer(baseline, director)
    if not real_supply.is_empty():
        options.append(real_supply)
    var resolved_previous: bool = false
    if original != null and graph != null:
        # Same N39 World, real N143 paid research readiness, real N144
        # colonies, and source N111 recomparison of the prior supply.
        # This is NOT an additional strategy tick or cloned director.
        var current: Dictionary = SourceN113Candidates.project(
            world, sources, original, graph,
            faction, baseline, tick, multiplier)
        if not current.get("ok", false):
            return {"ok": true, "authorized": false,
                "reason": str(current.get("reason",
                    "n113_original_source_candidates_unavailable"))}
        resolved_previous = bool(current.get("prior_supply_resolved", false))
        for candidate in current.get("offers", []):
            # On duplicated action+target use the actual source N134
            # Head score, never double-count the same incumbent.
            var duplicate: bool = false
            for existing in options:
                if str(existing.get("action", "")) == str(
                        candidate.get("action", "")) and str(
                        existing.get("target", "")) == str(
                        candidate.get("target", "")):
                    duplicate = true
                    break
            if not duplicate:
                options.append(candidate.duplicate(true))
    # An original previously funded choice must not be declared extinct
    # merely because a narrower, construction-only adapter omitted it.
    if (incumbent in ["research", "expand"] and original == null) or (
            incumbent == "supply" and (real_supply.is_empty() or
            str(real_supply.get("target", "")) != current_target) and
            not resolved_previous):
        return {"ok": true, "authorized": false,
            "reason": "n113_original_incumbent_needs_real_comparison"}
    var source_choice: Dictionary = SourceN113.decide(
        memory, options, tick, false, false, 60 * multiplier)
    if not source_choice.get("ok", false):
        return source_choice
    if source_choice.get("choice", {}).get("action", "") != "migrate" or (
            str(source_choice.get("choice", {}).get("target", "")) != destination):
        # This N147 path is not a second Head owner of research/expansion
        # actions. If a newly elected NON-migration choice differs from
        # the retained incumbent, its real N134/N143/N144 grant belongs
        # to its own phase; do not install a fake Director choice here.
        var elected: Dictionary = source_choice.get("choice", {})
        if not elected.is_empty() and (
                str(elected.get("action", "")) != incumbent or
                str(elected.get("target", "")) != current_target):
            return {"ok": true, "authorized": false,
                "reason": "n113_nonmigration_grant_owned_by_original_phase"}
        # One first-cycle or insufficient-advantage decision only updates
        # N113 StrategicMemory; NOT a passenger post or paid vote.
        return {"ok": true, "authorized": false, "pending": bool(
            source_choice.get("pending", false)),
            "reason": str(source_choice.get("reason", "")),
            "faction_id": faction, "tick": tick,
            "strategy": source_choice["memory"].duplicate(true),
            "head": baseline.duplicate(true),
            "money_spent": 0}
    var staged: Dictionary = source_choice["memory"].duplicate(true)
    var head: Dictionary = baseline.duplicate(true)
    head["selected_option"] = "migrate_colony"
    head["selected_administrator"] = ""
    head["problem"] = {}
    head["planned_spend"] = price
    head["reason"] = "colony_workforce_needed"
    return {"ok": true, "authorized": true,
        "faction_id": faction, "tick": tick, "head": head,
        "strategy": staged, "ready": ready.duplicate(true),
        "money_spent": 0, "reason": str(source_choice.get("reason", "")),
        "source": "rust_n113_retain_or_switch_then_n92_migration_commission"}
