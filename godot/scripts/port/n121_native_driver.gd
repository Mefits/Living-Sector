extends RefCounted
## N121 frozen Rust planning/native_execution.rs::drive_native_htn.
## The N98 PlanLedger is a separately owned PR, so N121 consumes its
## authoritative next_gate result and returns ledger_ops to apply in
## the SAME exclusive checkpoint as ContractBoard/treasury mutations.
## Neither searches GOAP nor asserts predicted production success.
const State = preload("res://scripts/port/n121_native_execution_state.gd")
const Receipts = preload("res://scripts/port/n121_native_receipts.gd")
const Dispatch = preload("res://scripts/port/n121_native_dispatch.gd")

static func enabled(mode: String) -> bool:
    return mode == "htn" or mode == "hybrid"

## context = {faction_id,tick,mult,mode,director_present,head,
##   head_goal,snapshot,proposed_candidate,ledger_gate}
## plan candidate is externally validated by N93/N100; authoritative
## gate is externally validated by N98. Fail closed when either absent.
static func drive(state: Dictionary, world: Dictionary,
        board: Dictionary, context: Dictionary) -> Dictionary:
    var faction: String = str(context.get("faction_id", ""))
    var tick_value: Variant = context.get("tick", null)
    var mult_value: Variant = context.get("mult", null)
    if (not State.validate(state) or faction.is_empty()
            or typeof(tick_value) != TYPE_INT
            or typeof(mult_value) != TYPE_INT
            or int(tick_value) < 0 or int(mult_value) < 1):
        return _fail("invalid_native_execution_context")
    var tick: int = int(tick_value)
    var mult: int = int(mult_value)
    if (not enabled(str(context.get("mode", "")))
            or not bool(context.get("director_present", false))):
        return _fallback(state, world, board, "native_opt_in_disabled")
    var working: Dictionary = state.duplicate(true)
    var active: Variant = working["active"].get(faction, null)
    if active == null:
        var new_plan: Dictionary = _admit_plan(
            working, world, context, faction, tick, mult)
        if not bool(new_plan.get("ok", false)):
            return new_plan
        working = new_plan["state"]
        if bool(new_plan.get("fallback", false)):
            return _fallback(working, world, board,
                str(new_plan.get("reason", "legacy_director_fallback")))
        active = working["active"].get(faction, null)
    if not (active is Dictionary):
        return _fail("no_active_native_plan")
    var plan: Dictionary = active.duplicate(true)
    if (not (plan.get("ledger", null) is Dictionary)
            or not (plan.get("goal", null) is Dictionary)):
        return _fail("invalid_active_native_plan")
    var gate: Variant = context.get("ledger_gate", null)
    if not (gate is Dictionary):
        return _fail("missing_authoritative_n98_gate")
    var kind: String = str(gate.get("kind", ""))
    var ops: Array = []
    var staged_world: Dictionary = world
    var staged_board: Dictionary = board
    var status: String = "waiting"
    var reason: String = ""
    var spending: int = 0
    var keep: bool = true
    match kind:
        "completed":
            var target: int = int(plan.get("production_target_delta", 0))
            var paid: bool = (
                bool(plan.get("production_goal", false)) and target > 0
                and State.produced_goal_units(plan) + 0.0001 >= float(target)
                and _receipted_goal_output(plan))
            if paid:
                status = "completed"
                reason = "native_recipe_receipts_and_goal_production_confirmed"
                keep = false
            else:
                var observation: Dictionary = Receipts.goal_stock(
                    context.get("snapshot", {}), world, plan["goal"])
                if bool(observation.get("ok", false)):
                    status = ("completed" if
                        float(observation["stock"]) >=
                        float(plan["goal"].get("target_units", 0))
                        else "needs_replan")
                    reason = ("native_receipts_and_goal_stock_confirmed"
                        if status == "completed" else
                        "native_receipts_complete_but_goal_stock_short")
                    keep = false
                else:
                    status = "blocked"
                    reason = "native_goal_stock_unverifiable"
        "needs_replan":
            status = "needs_replan"
            reason = "native_execution_failed"
            keep = false
        "await_dependencies":
            reason = "await_plan_dependencies"
        "reconcile_prepared":
            var key: String = str(gate.get("dispatch_key", ""))
            var existing: String = _contract_by_dispatch(
                board, "station:htn:" + key)
            if existing.is_empty():
                status = "blocked"
                reason = "prepared_order_not_found_no_duplicate_dispatch"
            else:
                reason = "reconciled_existing_native_order"
                ops.append({"method": "acknowledge",
                    "step_id": gate.get("step_id", ""),
                    "dispatch_key": key, "native_order_id": existing,
                    "tick": tick})
        "await_native":
            var native_id: String = str(gate.get("native_order_id", ""))
            var step_id: String = str(gate.get("step_id", ""))
            if native_id.is_empty() or step_id.is_empty():
                return _fail("invalid_native_pending_step")
            var checked: Dictionary
            if native_id.begins_with("facility:"):
                if not (context.get("snapshot", null) is Dictionary):
                    checked = {"ok": true, "receipt": null,
                        "reason": "cannot_observe_native_production"}
                else:
                    checked = Receipts.production_receipt(world,
                        context["snapshot"], plan, step_id, native_id,
                        tick, mult)
            else:
                checked = Receipts.contract_receipt(plan,
                    board.get("contracts", {}), step_id, native_id, tick)
            if not bool(checked.get("ok", false)):
                return _fail(str(checked.get("reason", "invalid_native_receipt")))
            reason = str(checked.get("reason", "await_native"))
            if checked.get("receipt", null) is Dictionary:
                ops.append({"method": "apply_receipt",
                    "receipt": checked["receipt"].duplicate(true),
                    "accounted_after_ack":
                        checked.get("accounted_after_ack", null)})
        "ready":
            var step_id: String = str(gate.get("step_id", ""))
            var dispatch_key: String = str(gate.get("dispatch_key", ""))
            if step_id.is_empty() or dispatch_key.is_empty():
                return _fail("invalid_n98_ready_gate")
            if Dispatch.already_commissioned_this_tick(board, faction, tick):
                reason = "already_commissioned_this_tick"
            else:
                var chosen: Dictionary = Receipts.action_for_step(
                    plan, step_id)
                if not bool(chosen.get("ok", false)):
                    status = "blocked"
                    reason = "htn_action_not_supported_by_native_dispatch"
                    keep = false
                else:
                    var action: Dictionary = chosen["action"]
                    match str(action.get("kind", "")):
                        "deliver":
                            var posted: Dictionary = Dispatch.commit_paid_delivery(
                                world, board, context.get("snapshot", {}),
                                faction, action, dispatch_key, tick, mult)
                            if not bool(posted.get("ok", false)):
                                status = "blocked"
                                reason = str(posted.get(
                                    "reason", "native_dispatch_rejected"))
                                keep = false
                            else:
                                staged_world = posted["world"]
                                staged_board = posted["board"]
                                spending = int(posted["committed_credits"])
                                status = "submitted"
                                reason = "funded_native_delivery_contract"
                                ops.append({"method": "prepare_and_acknowledge",
                                    "step_id": step_id, "dispatch_key": dispatch_key,
                                    "native_order_id": posted["native_order_id"],
                                    "tick": tick, "atomic_with_posted_world": true})
                        "produce":
                            var fac: Dictionary = _production_admission(
                                world, context.get("snapshot", {}), action)
                            if bool(fac.get("ok", false)):
                                reason = "observe_native_paid_production_shift"
                                ops.append({"method": "prepare_and_acknowledge",
                                    "step_id": step_id, "dispatch_key": dispatch_key,
                                    "native_order_id":
                                        "facility:" + str(fac["facility_id"]),
                                    "tick": tick,
                                    "production_started_tick_after_ack": tick})
                            else:
                                status = "blocked"
                                reason = "production_facility_not_verifiable"
                                keep = false
                        _:
                            status = "blocked"
                            reason = "htn_action_not_supported_by_native_dispatch"
                            keep = false
        _:
            return _fail("invalid_n98_gate")
    plan["last_reason"] = reason
    var report: Dictionary = _report(plan, status, reason, spending)
    var next_state: Dictionary = working.duplicate(true)
    if keep:
        next_state["active"][faction] = plan.duplicate(true)
    else:
        var source_stock: Dictionary = Receipts.goal_stock(
            context.get("snapshot", {}), staged_world, plan["goal"])
        var observed: Variant = (source_stock["stock"]
            if bool(source_stock.get("ok", false)) else null)
        var terminal: Dictionary = State.record_terminal(
            next_state, faction, plan, status, reason, tick, mult, observed)
        if not bool(terminal.get("ok", false)):
            return terminal
        next_state = terminal["state"]
    return {"ok": true, "state": next_state, "world": staged_world,
        "board": staged_board, "status": status, "reason": reason,
        "report": report, "committed_credits": spending,
        "ledger_ops": ops, "commit_requires_single_atomic_phase":
            not ops.is_empty()}

static func _admit_plan(state: Dictionary, world: Dictionary,
        context: Dictionary, faction: String,
        tick: int, mult: int) -> Dictionary:
    var head: Variant = context.get("head", null)
    if not (head is Dictionary):
        return {"ok": true, "fallback": true, "state": state,
            "reason": "missing_head"}
    if not ["deliver", "build", "wait"].has(
            str(head.get("selected_option", ""))):
        return {"ok": true, "fallback": true, "state": state,
            "reason": "head_selected_other_domain"}
    var head_goal: Variant = context.get("head_goal", null)
    if head_goal != null and not (head_goal is Dictionary):
        return _fail("invalid_head_goal")
    var deferred: Variant = state["deferred_goals"].get(faction, null)
    var cutoff: int = int(state["blocked_until"].get(faction, 0))
    var preempt: bool = (
        head_goal is Dictionary and deferred is Dictionary
        and deferred.get("goal", null) is Dictionary
        and not State.same_stock_goal(head_goal, deferred["goal"])
        and State.urgent_preemption(head_goal, deferred["goal"]))
    if tick < cutoff and not preempt:
        return {"ok": true, "fallback": true, "state": state,
            "reason": "native_retry_cooldown"}
    var selected: Dictionary = State.select_stock_goal(head_goal, deferred)
    var goal: Variant = selected.get("goal", null)
    if not (goal is Dictionary):
        return {"ok": true, "fallback": true, "state": state,
            "reason": "no_native_stock_goal"}
    var snapshot: Variant = context.get("snapshot", null)
    if not (snapshot is Dictionary):
        return {"ok": true, "fallback": true, "state": state,
            "reason": "native_snapshot_unavailable"}
    var next_state: Dictionary = state.duplicate(true)
    if deferred is Dictionary and deferred.get("goal", null) is Dictionary:
        if State.same_stock_goal(goal, deferred["goal"]):
            var check: Dictionary = Receipts.goal_stock(snapshot, world, goal)
            if bool(check.get("ok", false)) and (
                    float(check["stock"]) >=
                    float(goal.get("target_units", 0))):
                next_state["deferred_goals"].erase(faction)
                next_state["blocked_until"].erase(faction)
                return {"ok": true, "fallback": true,
                    "state": next_state,
                    "reason": "deferred_goal_already_satisfied"}
        else:
            next_state["deferred_goals"].erase(faction)
    var candidate: Variant = context.get("proposed_candidate", null)
    if (not (candidate is Dictionary)
            or not (candidate.get("goal", null) is Dictionary)
            or not State.same_stock_goal(candidate["goal"], goal)
            or not (candidate.get("actions", null) is Array)
            or not (candidate.get("ledger", null) is Dictionary)):
        var failed: Dictionary = State.record_planning_failure(
            next_state, faction, goal, "native_candidate_unavailable",
            tick, mult)
        if not bool(failed.get("ok", false)):
            return failed
        return {"ok": true, "fallback": true, "state": failed["state"],
            "reason": "native_candidate_unavailable"}
    var plan_id: String = ("native-" +
        ("hybrid" if str(context.get("mode", "")) == "hybrid" else "htn")
        + ":" + faction + ":" + str(tick) + ":" + str(goal["goal_id"]))
    var ledger: Dictionary = candidate["ledger"]
    if (str(ledger.get("plan_id", "")) != plan_id
            or str(ledger.get("faction_id", "")) != faction
            or str(ledger.get("goal_id", "")) != str(goal["goal_id"])):
        return _fail("native_ledger_identity_mismatch")
    var reason: String = "native_plan_accepted"
    var rationale: String = str(candidate.get("planner_rationale", ""))
    if deferred is Dictionary and deferred.get("goal", null) is Dictionary:
        if State.same_stock_goal(goal, deferred["goal"]):
            reason = "native_goal_replanned"
            rationale = ("recovery attempt %d of 3; prior=%s; %s" %
                [int(deferred.get("failed_attempts", 0)) + 1,
                 str(deferred.get("last_reason", "")), rationale])
    next_state["active"][faction] = {
        "ledger": ledger.duplicate(true), "goal": goal.duplicate(true),
        "actions": (candidate["actions"] as Array).duplicate(true),
        "production_started_tick": null, "last_reason": reason,
        "planner_rationale": rationale,
        "production_goal": bool(candidate.get("production_goal", false)),
        "production_target_delta": int(
            candidate.get("production_target_delta", 0)),
        "production_baselines": (candidate.get(
            "production_baselines", {}) as Dictionary).duplicate(true),
        "production_accounted": {}}
    return {"ok": true, "fallback": false, "state": next_state}

static func _production_admission(world: Dictionary,
        snapshot: Dictionary, action: Dictionary) -> Dictionary:
    if str(action.get("kind", "")) != "produce":
        return {"ok": false}
    var action_id: String = str(action.get("action_id", ""))
    var pins: Variant = world.get("producer_recipe_pins", null)
    if not (pins is Dictionary) or not (
            pins.get(action_id, null) is Dictionary):
        return {"ok": false}
    var pin: Dictionary = pins[action_id]
    var facility_id: String = str(pin.get("facility_id", ""))
    if facility_id.is_empty() or (
            str(action.get("source_id", "")) != facility_id):
        return {"ok": false}
    var location: String = str(action.get("destination_id", ""))
    var owned: Dictionary = Receipts.unique_owned_market(snapshot, location)
    if not bool(owned.get("ok", false)):
        return {"ok": false}
    if not Receipts.unique_global_market(world, location,
            str(owned["market"].get("market_id", ""))):
        return {"ok": false}
    return {"ok": true, "facility_id": facility_id}

static func _receipted_goal_output(plan: Dictionary) -> bool:
    var commodity: String = str(plan.get("goal", {}).get("commodity", ""))
    var successful: Dictionary = {}
    for record in plan.get("ledger", {}).get("steps", []):
        if str(record.get("phase", "")) == "succeeded":
            successful[str(record.get("step", {}).get("action_id", ""))] = true
    for action in plan.get("actions", []):
        if str(action.get("kind", "")) != "produce" or not successful.has(
                str(action.get("action_id", ""))):
            continue
        for output in action.get("outputs", []):
            if str(output.get("commodity", "")) == commodity and (
                    int(output.get("quantity", 0)) > 0):
                return true
    return false

static func _contract_by_dispatch(board: Dictionary, key: String) -> String:
    if not (board.get("contracts", null) is Dictionary):
        return ""
    var ids: Array = board["contracts"].keys()
    ids.sort()
    for id in ids:
        var contract: Variant = board["contracts"][id]
        if not (contract is Dictionary):
            continue
        var funding: Variant = contract.get("funding", null)
        if not (funding is Dictionary):
            continue
        var station_order: Variant = funding.get("station_order", null)
        if station_order is Dictionary and (
                str(station_order.get("order_id", "")) == key):
            return str(id)
    return ""

static func _report(plan: Dictionary, status: String,
        reason: String, spending: int) -> Dictionary:
    var ledger: Dictionary = plan.get("ledger", {})
    var pending: Dictionary = {}
    for record in ledger.get("steps", []):
        if str(record.get("phase", "")) != "succeeded":
            pending = record
            break
    var planner: String = str(ledger.get("planner_id", ""))
    return {
        "mode": ("native_hybrid_opt_in"
            if planner.begins_with("hybrid_") else "native_htn_opt_in"),
        "planner_id": planner, "plan_id": ledger.get("plan_id", ""),
        "status": status, "reason": reason,
        "step_id": pending.get("step", {}).get("step_id", null),
        "native_order_id": pending.get("native_order_id", null),
        "committed_credits": spending,
        "planner_rationale": plan.get("planner_rationale", "")}

static func _fallback(state: Dictionary, world: Dictionary,
        board: Dictionary, reason: String) -> Dictionary:
    return {"ok": true, "status": "fallback", "reason": reason,
        "state": state.duplicate(true), "world": world,
        "board": board, "report": null, "ledger_ops": []}

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
