extends RefCounted
## N134 phase-1 source port: coordination.rs lines 252-519 and 714-809.
## Produces head strategy candidates + policy audit. N113 alone owns hysteresis.
## N109/N110/N121 own charter / mandate / native dispatch transaction logic.
const SURVIVAL_COMMODITIES: Array[String] = ["food", "water"]
const FUNDED_TAGS: Array[String] = [
    "strategy.logistics.v1", "strategy.construction.v1",
    "strategy.colony.v1", "strategy.colony.workforce.v1"
]

static func _commodity(goal: Dictionary) -> String:
    return str(goal.get("commodity", "")).to_lower()

static func _supply_target(goal: Dictionary) -> String:
    return str(goal.get("target", goal.get("destination", "")))

static func is_active_funded_order(contracts: Array, faction_id: String) -> bool:
    for raw in contracts:
        if not raw is Dictionary:
            continue
        var c: Dictionary = raw
        if str(c.get("requestor_id", "")) != faction_id:
            continue
        if not FUNDED_TAGS.has(str(c.get("mission_category", ""))):
            continue
        if ["Paid", "Expired"].has(str(c.get("status", ""))):
            continue
        var funding: Dictionary = c.get("funding", {})
        if int(funding.get("reserved", 0)) > 0:
            return true
    return false

static func build_candidates(head: Dictionary, commander: Dictionary, inputs: Dictionary) -> Dictionary:
    # Inputs are actual native comparisons, research validation, colony
    # proposals, charter authority, migration proposals; not predicted assets.
    var crisis: bool = bool(commander.get("crisis", false))
    var score: float = maxf(0.0, float(inputs.get("native_option_score", 0.0)))
    var problem: Dictionary = head.get("problem", {})
    var native_target: String = str(inputs.get("native_target", _supply_target(problem)))
    var authorized_economic: bool = bool(inputs.get("authorized_economic_mandate", false))
    if authorized_economic and not crisis:
        score = maxf(score, float(inputs.get("economy_charter_score", 0.0)))
    var research: float = -1.0
    var science: float = float(commander.get("science", 0.0))
    if bool(inputs.get("research_ready", false)) and not crisis:
        research = 18.0 * science
        if str(commander.get("strategic_kind", "")) == "research":
            research += 2.0
        if bool(inputs.get("delegated_science", false)):
            research += float(inputs.get("research_charter_score", 0.0))
    var colony: Dictionary = inputs.get("colony", {})
    var expansion: float = -1.0
    if str(colony.get("reason", "")) == "ready" and \
            (not crisis or colony.get("site_id", null) != null):
        expansion = 80.0 if colony.get("site_id", null) != null else \
            25.0 * float(commander.get("expansion", 0.0))
    var migration: Dictionary = inputs.get("migration", {})
    var migration_possible: bool = not migration.is_empty() and not crisis
    var migration_score: float = 60.0 if migration_possible else -1.0
    var candidates: Array[Dictionary] = [
        {"action": "supply", "target": native_target, "score": score,
         "available": str(head.get("selected_option", "wait")) != "wait" and score > 0.0,
         "reason": str(head.get("reason", ""))},
        {"action": "research", "target": str(commander.get("research", "")),
         "score": research, "available": research > 0.0,
         "reason": "survival_first" if crisis else
             ("research_resources_unavailable" if research <= 0.0 else "paid_science_available")},
        {"action": "expand", "target": str(colony.get("target", _supply_target(colony.get("goal", {})))),
         "score": expansion, "available": expansion > 0.0,
         "reason": str(colony.get("reason", "no_colony_target"))},
        {"action": "migrate", "target": str(migration.get("destination", "")),
         "score": migration_score, "available": migration_possible,
         "reason": "survival_first" if crisis else
             ("colony_needs_workers" if migration_possible else "no_funded_passenger_route")},
    ]
    # Reassess the previous target using current world prices and ownership,
    # passed by N113 / native options comparator. Never reuse stale score.
    var old: Dictionary = inputs.get("previous_supply", {})
    if str(commander.get("strategic_kind", "")) == "supply" and not old.is_empty() and \
            str(old.get("target", "")) != native_target:
        var old_score: float = maxf(0.0, float(old.get("native_option_score", 0.0)))
        candidates.append({"action": "supply", "target": str(old.get("target", "")),
            "score": old_score, "available": old_score > 0.0,
            "reason": "previous_supply_still_feasible"})
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["score"]) != float(b["score"]):
            return float(a["score"]) > float(b["score"])
        if str(a["action"]) != str(b["action"]):
            return str(a["action"]) < str(b["action"])
        return str(a["target"]) < str(b["target"]))
    var prior_goal: Dictionary = old.get("goal", {})
    var survival: bool = crisis and candidates.any(func(item: Dictionary) -> bool:
        if item["action"] != "supply" or not item["available"]:
            return false
        var current_essential: bool = SURVIVAL_COMMODITIES.has(_commodity(problem))
        var old_essential: bool = SURVIVAL_COMMODITIES.has(_commodity(prior_goal))
        return (current_essential and item["target"] == native_target) or \
            (old_essential and item["target"] == str(old.get("target", ""))))
    var funded: bool = is_active_funded_order(inputs.get("contracts", []), str(inputs.get("faction_id", "")))
    var player_top: bool = authorized_economic and not crisis and \
        not bool(inputs.get("native_active", false)) and not funded and \
        not candidates.is_empty() and bool(candidates[0].get("available", false)) and \
        str(candidates[0].get("action", "")) == "supply" and \
        str(candidates[0].get("target", "")) == native_target
    return {
        "candidates": candidates, "survival": survival,
        "funded_order": funded, "native_active": bool(inputs.get("native_active", false)),
        "player_top": player_top,
        "needs_immediate_player_switch": player_top and \
            (str(commander.get("strategic_kind", "")) != "supply" or \
             str(commander.get("strategic_target", "")) != native_target),
    }

static func apply_director_choice(head: Dictionary, director_choice: Dictionary,
        inputs: Dictionary) -> Dictionary:
    # director_choice is the authoritative N113 retain_or_switch / player
    # priority result, including hysteresis, not calculated twice here.
    var result: Dictionary = head.duplicate(true)
    if director_choice.is_empty():
        return result
    var action: String = str(director_choice.get("action", ""))
    var target: String = str(director_choice.get("target", ""))
    var candidates: Array = inputs.get("candidates", [])
    var valid: bool = false
    for candidate in candidates:
        if str(candidate.get("action", "")) == action and \
                str(candidate.get("target", "")) == target and bool(candidate.get("available", false)):
            valid = true
            break
    if not valid:
        return result
    # Native active execution and one-funded-order locks are authority gates,
    # even if an erroneously supplied director decision says otherwise.
    if bool(inputs.get("native_active", false)) or bool(inputs.get("funded_order", false)):
        return result
    var reason: String = str(director_choice.get("reason", "best_projected_relief"))
    match action:
        "research":
            result["selected_option"] = "research"
            result["selected_administrator"] = ""
            result["problem"] = {}
            result["planned_spend"] = 0
            result["reason"] = reason
        "migrate":
            var plan: Dictionary = inputs.get("migration", {})
            if plan.is_empty():
                return result
            result["selected_option"] = "migrate_colony"
            result["selected_administrator"] = ""
            result["problem"] = {}
            result["planned_spend"] = int(plan.get("payment", 0))
            result["reason"] = "colony_workforce_needed"
        "expand":
            var plan: Dictionary = inputs.get("colony", {})
            if str(plan.get("reason", "")) != "ready":
                return result
            result["selected_option"] = "supply_colony" if plan.get("site_id", null) != null else "found_colony"
            result["selected_administrator"] = "construction"
            result["problem"] = plan.get("goal", {}).duplicate(true)
            result["planned_spend"] = int(plan.get("cost", 0))
            result["reason"] = reason
        "supply":
            var native_target: String = str(inputs.get("native_target", ""))
            if target != native_target:
                var previous: Dictionary = inputs.get("previous_head", {})
                if previous.is_empty() or str(inputs.get("previous_target", "")) != target:
                    return result
                result = previous.duplicate(true)
            if bool(inputs.get("crisis", false)) and \
                    SURVIVAL_COMMODITIES.has(_commodity(result.get("problem", {}))):
                result["reason"] = "urgent_life_support"
            elif str(inputs.get("previous_strategic_kind", "")) == "" and reason == "previous_goal_unavailable":
                pass
            else:
                result["reason"] = reason
    return result

static func enforce_economic_mandate(head: Dictionary, mandate: Dictionary,
        authorization: Dictionary) -> Dictionary:
    var result: Dictionary = head.duplicate(true)
    var goal: Dictionary = result.get("problem", {})
    if mandate.is_empty() or goal.is_empty():
        return result
    if str(goal.get("goal_id", "")) != str(mandate.get("goal_id", "")) or \
            str(goal.get("destination", "")) != str(mandate.get("location", "")) or \
            _commodity(goal) != str(mandate.get("commodity", "")).to_lower():
        return result
    if str(mandate.get("kind", "")).to_lower() == "industry" and \
            str(result.get("selected_option", "")) != "build":
        result["problem"] = {}
        result["selected_option"] = "wait"
        result["selected_administrator"] = ""
        result["planned_spend"] = 0
        result["reason"] = "industry_requires_native_build"
        return result
    # The true may_commission and authorize_action gates belong to N109 and
    # mandate native code; absent validation must not invent permission.
    if not bool(authorization.get("may_commission", false)) or \
            not bool(authorization.get("authorize_action", false)):
        result["problem"] = {}
        result["selected_option"] = "wait"
        result["selected_administrator"] = ""
        result["planned_spend"] = 0
        result["reason"] = str(authorization.get("reason", "player_mandate_budget_or_reserve_blocked"))
    return result

static func policy_impact(head: Dictionary, commander: Dictionary, department: String,
        mandate: Dictionary, charter: Dictionary, proposal: Dictionary = {}) -> Dictionary:
    var mode: String = str(mandate.get("mode", "")).to_lower()
    var autonomous: bool = str(charter.get(department + "_authority", "")).to_lower() == "autonomous"
    var selected: bool = false
    var target: String = ""
    var funded_id: String = ""
    if department == "economy":
        var goal: Dictionary = head.get("problem", {})
        var requested: String = str(mandate.get("goal_id", ""))
        var action: String = "deliver" if str(mandate.get("kind", "")).to_lower() == "supply" else "build"
        selected = str(head.get("selected_option", "")) == action and \
            str(goal.get("goal_id", "")) == requested and \
            str(goal.get("destination", "")) == str(mandate.get("location", "")) and \
            _commodity(goal) == str(mandate.get("commodity", "")).to_lower()
        target = requested + " · " + str(mandate.get("location", "")) + " · " + str(mandate.get("commodity", ""))
        funded_id = str(proposal.get("funded_contract_id", ""))
    else:
        selected = str(head.get("selected_option", "")) == "research"
        target = str(mandate.get("target_technology", ""))
    var status: String = "not_selected"
    if mode == "hold":
        status = "hold"
    elif mode == "advise":
        status = "advisory"
    elif autonomous:
        status = "charter_autonomous"
    elif bool(commander.get("crisis", false)):
        status = "survival_override"
    elif department == "economy" and not funded_id.is_empty():
        status = "native_contract_linked"
    elif selected:
        status = "selected_by_head"
    elif department == "economy" and str(proposal.get("status", "")) == "Pending":
        status = "awaiting_specific_approval"
    return {
        "department": department, "mode": mode, "target": target,
        "priority": charter.get(department + "_priority", null),
        "selected": selected and mode == "delegated" and not autonomous,
        "status": status, "reason": str(mandate.get("last_reason", "")),
        "funded_contract_id": funded_id,
    }
