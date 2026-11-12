extends RefCounted
## N134 Phase 1: native/crates/sim_core/src/strategy/coordination.rs
## lines 154-809. Data-only coordination envelope; not an ECS/ContractBoard
## adapter. Existing N98/N100/N121/N39 remain the transaction owners.
const Head = preload("res://scripts/sim/phase1/n134_coordination_head.gd")
const Policy = preload("res://scripts/sim/phase1/n134_coordination_policy.gd")
const FUNDED_TAGS: Array[String] = [
    "strategy.logistics.v1", "strategy.construction.v1",
    "strategy.colony.v1", "strategy.colony.workforce.v1"
]
var _last_tick: int = -1
var _last_projection: Dictionary = {}

static func _commissioned_in_tick(contracts: Array, faction_id: String, tick: int) -> bool:
    for raw in contracts:
        if not raw is Dictionary:
            continue
        var c: Dictionary = raw
        if str(c.get("requestor_id", "")) == faction_id and \
                int(c.get("posted_at_tick", -1)) == tick and \
                FUNDED_TAGS.has(str(c.get("mission_category", ""))):
            return true
    return false

static func _colony_safety_gate(colony: Dictionary, views: Array, faction_id: String) -> Dictionary:
    var candidate: Dictionary = colony.duplicate(true)
    if candidate.is_empty() or candidate.get("site_id", null) != null:
        return candidate
    # Rust lines 180-193: don't start third colony while established
    # household lacks unambiguous actual market stock and life support.
    for raw in views:
        if not raw is Dictionary:
            continue
        var view: Dictionary = raw
        if str(view.get("faction_id", "")) != faction_id or int(view.get("population", 0)) <= 0:
            continue
        var safe: bool = bool(view.get("market_unambiguous", false)) and \
            view.get("food", null) != null and view.get("water", null) != null and \
            view.get("food_reserve_target", null) != null and \
            view.get("water_reserve_target", null) != null
        if safe:
            safe = float(view["food"]) >= float(view["food_reserve_target"]) and \
                float(view["water"]) >= float(view["water_reserve_target"])
        if not safe:
            candidate["reason"] = "existing_colony_life_support_crisis"
            break
    return candidate

static func _mandate_matches(goal: Dictionary, mandate: Dictionary) -> bool:
    return not goal.is_empty() and not mandate.is_empty() and \
        str(goal.get("goal_id", "")) == str(mandate.get("goal_id", "")) and \
        str(goal.get("destination", "")) == str(mandate.get("location", "")) and \
        str(goal.get("commodity", "")).to_lower() == str(mandate.get("commodity", "")).to_lower()

static func _ready_native_option(comparison: Dictionary, action: String) -> bool:
    for raw in comparison.get("alternatives", []):
        if not raw is Dictionary:
            continue
        if str(raw.get("action", "")) == action and str(raw.get("status", "")) == "ready":
            return true
    return false

func preview_cycle(tick: int, mult: int, world: Dictionary) -> Dictionary:
    if tick < 0 or mult < 1:
        return {"ok": false, "reason": "invalid_tick_or_multiplier"}
    if tick == _last_tick:
        return _last_projection.duplicate(true)
    if _last_tick >= 0 and tick < _last_tick:
        return {"ok": false, "reason": "non_monotonic_tick"}
    var mode: String = str(world.get("mode", "Shadow"))
    if not ["Execute", "Shadow"].has(mode):
        return {"ok": false, "reason": "invalid_strategy_mode"}
    var factions: Dictionary = world.get("factions", {})
    var contracts: Array = world.get("contracts", [])
    var ids: Array = factions.keys()
    ids.sort()
    var decisions: Dictionary = {}
    var grants: Dictionary = {}
    var intentions: Array[Dictionary] = []
    var previews: Dictionary = {}
    var native_reports: Dictionary = {}
    for id_variant in ids:
        var id: String = str(id_variant)
        var state: Dictionary = factions[id]
        var view: Dictionary = state.get("view", {})
        var comparison: Dictionary = state.get("comparison", {})
        var commander: Dictionary = state.get("commander", {})
        var active: bool = bool(state.get("native_active", false))
        var commissioned: bool = _commissioned_in_tick(contracts, id, tick)
        var diagnostics: Dictionary = state.get("diagnostics", {})
        # Unapproved player_* proposals are disallowed in autonomous view.
        # A separate precise native quote + mandate admission is required.
        var goal: Dictionary = comparison.get("goal", {})
        if str(goal.get("goal_id", "")).begins_with("player_"):
            comparison = {}
        var head: Dictionary = Head.preview(view, comparison, tick, mult,
            commissioned, diagnostics)
        var colony: Dictionary = _colony_safety_gate(state.get("colony", {}),
            world.get("colony_views", []), id)
        head = Head.append_colony_proposal(head, colony, not commander.is_empty())
        var mandate: Dictionary = state.get("economic_mandate", {})
        var approval: Dictionary = state.get("mandate_authorization", {})
        var legal_quote: bool = not commander.is_empty() and \
            not bool(commander.get("crisis", false)) and not commissioned and \
            not active and not mandate.is_empty() and \
            str(mandate.get("mode", "")).to_lower() == "delegated" and \
            bool(approval.get("may_commission", false)) and \
            bool(approval.get("authorize_action", false))
        var quoted: Dictionary = state.get("mandate_comparison", {})
        if legal_quote:
            var required_action: String = "build" if \
                str(mandate.get("kind", "")).to_lower() == "industry" else "deliver"
            var goal_quoted: Dictionary = quoted.get("goal", {})
            if not _mandate_matches(goal_quoted, mandate) or \
                    not _ready_native_option(quoted, required_action):
                legal_quote = false
            else:
                # Exact native action, not the comparator's alternative choice.
                quoted = quoted.duplicate(true)
                quoted["selected"] = required_action
                head = Head.preview(view, quoted, tick, mult, false, diagnostics)
                head["reason"] = "player_economic_mandate"
        # Native plan owns its prepaid sequence, not a second head grant.
        if mode == "Execute" and bool(world.get("native_execution_enabled", false)) and active:
            head["selected_option"] = "wait"
            head["selected_administrator"] = ""
            head["problem"] = {}
            head["planned_spend"] = 0
            head["reason"] = "outstanding_native_plan_retained"
        elif not commander.is_empty() and not commissioned:
            var inputs: Dictionary = state.get("candidate_inputs", {}).duplicate(true)
            inputs["faction_id"] = id
            inputs["contracts"] = contracts
            inputs["native_active"] = active
            inputs["colony"] = colony
            inputs["authorized_economic_mandate"] = legal_quote
            inputs["native_target"] = str(inputs.get("native_target",
                str(head.get("problem", {}).get("destination", ""))))
            var ranked: Dictionary = Policy.build_candidates(head, commander, inputs)
            ranked["colony"] = colony
            ranked["migration"] = inputs.get("migration", {})
            ranked["native_target"] = inputs["native_target"]
            ranked["crisis"] = bool(commander.get("crisis", false))
            ranked["previous_head"] = state.get("previous_head", {})
            ranked["previous_target"] = str(inputs.get("previous_target", ""))
            ranked["previous_strategic_kind"] = str(commander.get("strategic_kind", ""))
            # Hysteresis/authorized immediate player switch belongs to N113:
            # no fake two-cycle confirmation and no state writes in Shadow.
            previews[id] = ranked
            head = Policy.apply_director_choice(head, state.get("director_choice", {}), ranked)
        # A player industry mandate cannot become a one-time import.
        # may_commission/authorize_action were checked against real treasury.
        if _mandate_matches(head.get("problem", {}), mandate):
            head = Policy.enforce_economic_mandate(head, mandate, approval)
        # A colony's actual essential stock goal can be offered to N121
        # before legacy grant, but only while no native plan is outstanding.
        var saved: Dictionary = {}
        var colony_stock_goal: Dictionary = state.get("colony_stock_goal", {})
        if mode == "Execute" and bool(world.get("native_execution_enabled", false)) and \
                not active and not commissioned and not colony_stock_goal.is_empty():
            var essential: bool = str(colony_stock_goal.get("goal_id", "")) == "colony_life_support"
            if essential or ["wait", "migrate_colony"].has(str(head.get("selected_option", ""))):
                saved = head.duplicate(true)
                head["problem"] = colony_stock_goal.duplicate(true)
                head["selected_option"] = "wait"
                head["selected_administrator"] = ""
                head["planned_spend"] = 0
                head["reason"] = "colony_life_support_native_goal" if essential else \
                    "colony_industrial_chain_native_goal"
        if mode == "Execute" and bool(world.get("native_execution_enabled", false)):
            # External N121 report must be a genuine validated drive outcome.
            var report: Dictionary = state.get("native_drive_report", {})
            if bool(report.get("validated", false)):
                native_reports[id] = report.duplicate(true)
                head["selected_option"] = "hybrid_native" if \
                    str(report.get("mode", "")) == "native_hybrid_opt_in" else "htn_native"
                head["selected_administrator"] = ""
                head["planned_spend"] = int(report.get("committed_credits", 0))
                head["reason"] = str(report.get("reason", ""))
                head["htn_execution"] = report.duplicate(true)
            elif not saved.is_empty():
                head = saved
        if bool(world.get("planning_shadow_enabled", false)):
            head["planning_shadow"] = state.get("planning_shadow", {}).duplicate(true)
        decisions[id] = head
        # Grants are permission checks only, not authoritatively posted orders.
        var grant: Dictionary = Head.grant_for(head)
        if not grant.is_empty():
            grants[id] = grant
        if mode == "Execute":
            match str(head.get("selected_option", "")):
                "deliver", "build":
                    if not grant.is_empty():
                        intentions.append({"faction_id": id, "kind": "native_administrator_grant",
                            "administrator": grant["administrator"],
                            "goal": grant["goal"].duplicate(true), "tick": tick})
                "found_colony", "supply_colony":
                    if not colony.is_empty() and str(colony.get("reason", "")) == "ready":
                        intentions.append({"faction_id": id, "kind": "colony_commission",
                            "plan": colony.duplicate(true), "tick": tick})
                "migrate_colony":
                    var migration: Dictionary = state.get("candidate_inputs", {}).get("migration", {})
                    if not migration.is_empty():
                        intentions.append({"faction_id": id, "kind": "migration_commission",
                            "plan": migration.duplicate(true), "tick": tick})
                "research":
                    intentions.append({"faction_id": id, "kind": "paid_research_shift",
                        "tick": tick})
                "htn_native", "hybrid_native":
                    # N121 has already produced the report; the driver alone
                    # stages actual board+ledger operations, never replay here.
                    pass
        if not mandate.is_empty():
            var impacts: Array = [Policy.policy_impact(head, commander,
                "economy", mandate, state.get("charter", {}),
                state.get("economic_proposal", {}))]
            if not state.get("research_mandate", {}).is_empty():
                impacts.append(Policy.policy_impact(head, commander, "research",
                    state["research_mandate"], state.get("charter", {})))
            head["policy_impacts"] = impacts
    # A preview never changes world/board/treasury or mints any receipt.
    var out: Dictionary = {
        "ok": true, "tick": tick, "mode": mode, "heads": decisions,
        "grants": grants, "intents": intentions, "native_reports": native_reports,
        "strategy_candidates": previews, "commitments_verified": false,
    }
    _last_tick = tick
    _last_projection = out.duplicate(true)
    return out

static func reconcile_committed(projection: Dictionary, board_after: Array,
        science_receipts: Dictionary, mandated: Dictionary, construction_views: Dictionary = {}) -> Dictionary:
    # Call ONLY after exclusive N98/N121/world commit. Read real funding in
    # the authoritative after-state, never a proposed quote, shadow order or
    # player's policy authorization as money actually paid.
    if not bool(projection.get("ok", false)):
        return {"ok": false, "reason": "invalid_projection"}
    var tick: int = int(projection.get("tick", -1))
    var result: Dictionary = projection.duplicate(true)
    var confirmed: Dictionary = {}
    var receipts: Array[Dictionary] = []
    var keys: Array = result.get("heads", {}).keys()
    keys.sort()
    for id_variant in keys:
        var id: String = str(id_variant)
        var total: int = 0
        for raw in board_after:
            if not raw is Dictionary:
                continue
            var c: Dictionary = raw
            if str(c.get("requestor_id", "")) != id or \
                    int(c.get("posted_at_tick", -1)) != tick or \
                    not FUNDED_TAGS.has(str(c.get("mission_category", ""))):
                continue
            var f: Dictionary = c.get("funding", {})
            total += maxi(0, int(f.get("reserved", 0)))
        var science: Dictionary = science_receipts.get(id, {})
        if bool(science.get("validated_paid", false)) and \
                int(science.get("tick", -1)) == tick:
            total += maxi(0, int(science.get("amount", 0)))
        var head: Dictionary = result["heads"][id]
        head["committed_spend"] = total
        if str(head.get("selected_option", "")) == "research":
            head["planned_spend"] = total
        confirmed[id] = total
        var mandate: Dictionary = mandated.get(id, {})
        if not _mandate_matches(head.get("problem", {}), mandate):
            continue
        if str(mandate.get("mode", "")).to_lower() != "delegated":
            continue
        var type_accepted: String = str(mandate.get("kind", "")).to_lower()
        var action: String = str(head.get("selected_option", ""))
        for raw in board_after:
            if not raw is Dictionary:
                continue
            var c: Dictionary = raw
            if str(c.get("requestor_id", "")) != id or \
                    int(c.get("posted_at_tick", -1)) != tick or \
                    str(c.get("destination_location", "")) != str(mandate.get("location", "")):
                continue
            var matches_action: bool = false
            if type_accepted == "supply" and action == "deliver":
                matches_action = str(c.get("contract_type", "")) == "Subsidy" and \
                    str(c.get("mission_category", "")) == "strategy.logistics.v1" and \
                    str(c.get("commodity", "")).to_lower() == str(mandate.get("commodity", "")).to_lower()
            elif type_accepted == "industry" and action == "build":
                var construction: Dictionary = construction_views.get(id, {})
                matches_action = str(construction.get("status", "")) == "commissioned" and \
                    str(construction.get("contract_id", "")) == str(c.get("id", "")) and \
                    str(c.get("contract_type", "")) == "Construction" and \
                    str(c.get("mission_category", "")) == "strategy.construction.v1" and \
                    str(construction.get("commodity", "")).to_lower() == str(mandate.get("commodity", "")).to_lower()
            var funding: Dictionary = c.get("funding", {})
            if matches_action and str(funding.get("source", "")) == "Faction" and \
                    int(funding.get("reserved", 0)) > 0:
                receipts.append({"faction_id": id, "contract_id": str(c.get("id", "")),
                    "action": action, "actual_paid": int(funding["reserved"]), "tick": tick})
                break
    result["verified_funded_totals"] = confirmed
    result["actual_mandate_receipt_intents"] = receipts
    result["commitments_verified"] = true
    # No direct treasury mutations or mandate actual_commit. N109 owns Apply.
    return result

func snapshot() -> Dictionary:
    return {"version": 1, "last_tick": _last_tick, "projection": _last_projection.duplicate(true)}

func restore(data: Dictionary) -> bool:
    if int(data.get("version", -1)) != 1 or not (data.get("projection", {}) is Dictionary):
        return false
    var last_tick: int = int(data.get("last_tick", -1))
    var projection: Dictionary = data.get("projection", {})
    if last_tick < -1 or (last_tick >= 0 and int(projection.get("tick", -2)) != last_tick):
        return false
    _last_tick = last_tick
    _last_projection = projection.duplicate(true)
    return true
