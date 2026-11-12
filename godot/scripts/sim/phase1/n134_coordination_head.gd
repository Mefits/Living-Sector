extends RefCounted
## N134 / Phase 1 / CODE_UNVERIFIED.
## Source: frozen native/crates/sim_core/src/strategy/coordination.rs lines 4-149.
## Pure Rust HeadDecision projection. Alternatives are produced by the native
## options comparator (N80/N99 etc.), never fabricated by this module.
const SUBSIDY_FLOOR: int = 5000

static func same_problem(a: Dictionary, b: Dictionary) -> bool:
    # Rust options::same_problem deliberately ignores goal_id and shortage age.
    return str(a.get("commodity", "")) == str(b.get("commodity", "")) and \
        str(a.get("destination", "")) == str(b.get("destination", ""))

static func granted_goal_matches(granted: Dictionary, goal: Dictionary, administrator: String) -> bool:
    if not same_problem(granted, goal):
        return false
    match str(granted.get("goal_id", "")):
        "player_supply":
            return administrator == "logistics" and str(goal.get("goal_id", "")) == "player_supply"
        "player_industry":
            return administrator == "construction" and \
                ["player_industry", "expand_production"].has(str(goal.get("goal_id", "")))
        _:
            return not str(goal.get("goal_id", "")).begins_with("player_")

static func authorized(grants_present: bool, grants: Dictionary, faction_id: String, administrator: String, goal: Dictionary) -> bool:
    # Rust authorized() permits unguarded legacy administrators only if the
    # transient Grants resource does not exist at all.
    if not grants_present:
        return true
    if not grants.has(faction_id):
        return false
    var grant: Dictionary = grants[faction_id]
    return str(grant.get("administrator", "")) == administrator and \
        granted_goal_matches(grant.get("goal", {}), goal, administrator)

static func preview(view: Dictionary, comparison: Dictionary, tick: int, mult: int,
        already_commissioned: bool, diagnostics: Dictionary = {}) -> Dictionary:
    var treasury: int = int(view.get("treasury", 0))
    var alternatives: Array = comparison.get("alternatives", [])
    var has_problem: bool = comparison.get("goal", null) is Dictionary and \
        not (comparison.get("goal", {}) as Dictionary).is_empty()
    var problem: Dictionary = comparison.get("goal", {}).duplicate(true) if has_problem else {}
    var selected: String = "wait" if already_commissioned else str(comparison.get("selected", "wait"))
    if not ["deliver", "build", "wait"].has(selected):
        selected = "wait"
    if not has_problem:
        selected = "wait"
    var administrator: String = ""
    if selected == "deliver":
        administrator = "logistics"
    elif selected == "build":
        administrator = "construction"
    var planned: int = 0
    var proposals: Array[Dictionary] = []
    for item in alternatives:
        if not item is Dictionary:
            continue
        var action: String = str(item.get("action", ""))
        if action == selected:
            planned = int(item.get("first_payment", 0))
        if action != "deliver" and action != "build":
            continue
        var priority: int = 0
        if action == "deliver" and ["food", "water", "fuel"].has(str(problem.get("commodity", "")).to_lower()):
            priority = 3
        elif action == "build":
            priority = 2 if item.get("site_id", null) != null else 1
        proposals.append({
            "administrator": "logistics" if action == "deliver" else "construction",
            "goal": problem.duplicate(true),
            "status": "proposed" if str(item.get("status", "")) == "ready" else "blocked",
            "reason": str(item.get("reason", "")),
            "requested_credits": int(item.get("first_payment", 0)),
            "priority": priority,
        })
    var reason: String = "best_projected_relief"
    if already_commissioned:
        reason = "already_commissioned_this_tick"
    elif not has_problem:
        reason = "no_current_problem"
    elif selected == "wait":
        reason = "wait_no_positive_option"
    # IMPORTANT: projection has no money mutation and no committed receipt.
    return {
        "observed_tick": tick,
        "selected_administrator": administrator,
        "reason": reason,
        "treasury_before": treasury,
        "spending_limit": maxi(0, treasury - SUBSIDY_FLOOR),
        "planned_spend": planned,
        "committed_spend": 0,
        "proposals": proposals,
        "problem": problem,
        "selected_option": selected,
        "horizon_ticks": int(diagnostics.get("horizon_ticks", 1200 * maxi(mult, 1))),
        "alternatives": alternatives.duplicate(true),
        "goal_reviews": diagnostics.get("goal_reviews", []).duplicate(true),
        "shadow_portfolio": diagnostics.get("shadow_portfolio", {}).duplicate(true),
        "native_chain_probe": diagnostics.get("native_chain_probe", {}).duplicate(true),
        "policy_impacts": [],
        "planning_shadow": {},
        "htn_execution": {},
    }

static func append_colony_proposal(head: Dictionary, colony: Dictionary,
        has_commander: bool) -> Dictionary:
    var result: Dictionary = head.duplicate(true)
    if colony.is_empty():
        return result
    var ready: bool = str(colony.get("reason", "")) == "ready"
    result["proposals"].append({
        "administrator": "construction", "goal": colony.get("goal", {}).duplicate(true),
        "status": "proposed" if ready else "blocked",
        "reason": str(colony.get("reason", "")), "requested_credits": int(colony.get("cost", 0)),
        "priority": 1,
    })
    if not has_commander and ready and result["reason"] != "already_commissioned_this_tick" and \
            (colony.get("site_id", null) != null or result["selected_option"] == "wait"):
        result["selected_administrator"] = "construction"
        result["selected_option"] = "supply_colony" if colony.get("site_id", null) != null else "found_colony"
        result["problem"] = colony.get("goal", {}).duplicate(true)
        result["reason"] = "viable_expansion"
        result["planned_spend"] = int(colony.get("cost", 0))
        result["alternatives"] = []
    return result

static func grant_for(head: Dictionary) -> Dictionary:
    var administrator: String = str(head.get("selected_administrator", ""))
    var goal: Dictionary = head.get("problem", {})
    if administrator.is_empty() or goal.is_empty():
        return {}
    return {"administrator": administrator, "goal": goal.duplicate(true)}
