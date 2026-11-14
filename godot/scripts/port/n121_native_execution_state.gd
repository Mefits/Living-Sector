extends RefCounted
## N121 frozen Rust strategy/planning/native_execution.rs NativeExecution
## and native retry/deferred/terminal outcome memory. Pure data snapshots.
## Not a second inventory, credit ledger or source of produced goods.
const MAX_GOAL_RETRIES: int = 3
const MAX_OUTCOMES: int = 64
const SUBSIDY_CHECK_INTERVAL_BASE: int = 60
const MAX_U64_SIGNED: int = 9223372036854775807
const RETRYABLE_REASONS = [
    "no_funded_idle_native_carrier", "native_source_stock_gone",
    "existing_native_delivery_commitment", "native_treasury_floor",
    "native_price_exceeds_funded_reward", "native_quote_invalid",
    "native_route_unavailable", "production_facility_not_verifiable"
]

static func empty() -> Dictionary:
    return {"active": {}, "blocked_until": {}, "history": [],
        "deferred_goals": {}}

static func validate(state: Dictionary) -> bool:
    return (state.get("active", null) is Dictionary
        and state.get("blocked_until", null) is Dictionary
        and state.get("history", null) is Array
        and state.get("deferred_goals", null) is Dictionary)

## Source same_stock_goal explicitly ignores target_units: a newly
## refreshed head probe is the same need, not another funding authority.
static func same_stock_goal(a: Dictionary, b: Dictionary) -> bool:
    return (str(a.get("goal_id", "")) == str(b.get("goal_id", ""))
        and str(a.get("destination_id", "")) == str(b.get("destination_id", ""))
        and str(a.get("commodity", "")) == str(b.get("commodity", ""))
        and not str(a.get("goal_id", "")).is_empty())

static func urgent_preemption(new_goal: Dictionary,
        old_goal: Dictionary) -> bool:
    var old_good: String = str(old_goal.get("commodity", ""))
    var new_good: String = str(new_goal.get("commodity", ""))
    if not ["food", "water"].has(old_good) and ["food", "water"].has(new_good):
        return true
    var incoming: int = int(new_goal.get("priority", 0))
    var previous: int = maxi(0, int(old_goal.get("priority", 0)))
    return incoming > previous + (previous / 4) + 1

## Rust select_stock_goal: prefer deferred original target, unless an
## urgent head request preempts it. Never reuse its stale route/prices.
static func select_stock_goal(head: Variant, deferred: Variant) -> Dictionary:
    if head == null and deferred == null:
        return {"ok": true, "goal": null}
    if deferred is Dictionary and deferred.get("goal", null) is Dictionary:
        var old: Dictionary = deferred["goal"]
        if head is Dictionary and same_stock_goal(head, old):
            var result: Dictionary = old.duplicate(true)
            result["priority"] = maxi(
                int(result.get("priority", 0)), int(head.get("priority", 0)))
            return {"ok": true, "goal": result, "source": "deferred_same_need"}
        if head is Dictionary and urgent_preemption(head, old):
            return {"ok": true, "goal": head.duplicate(true), "source": "urgent_head"}
        if int(deferred.get("failed_attempts", 0)) < MAX_GOAL_RETRIES:
            return {"ok": true, "goal": old.duplicate(true),
                "source": "deferred_retry"}
    if head is Dictionary:
        return {"ok": true, "goal": head.duplicate(true), "source": "head"}
    return {"ok": true, "goal": null}

static func retryable(status: String, reason: String) -> bool:
    return status == "needs_replan" or (
        status == "blocked" and RETRYABLE_REASONS.has(reason))

## Rust: 2 * 60 * max(1,mult) * (1 << min(attempts-1,3)).
static func next_retry_delay(mult: int, attempts: int) -> int:
    var exp: int = mini(maxi(attempts - 1, 0), 3)
    var multiplier: int = maxi(mult, 1)
    var value: int = 2 * SUBSIDY_CHECK_INTERVAL_BASE * multiplier
    if value > (MAX_U64_SIGNED >> exp):
        return MAX_U64_SIGNED
    return value << exp

static func _next_failure_count(state: Dictionary, faction: String,
        goal: Dictionary) -> int:
    var old: Variant = state["deferred_goals"].get(faction, null)
    if (old is Dictionary and old.get("goal", null) is Dictionary
            and same_stock_goal(old["goal"], goal)):
        return mini(255, int(old.get("failed_attempts", 0)) + 1)
    return 1

static func record_planning_failure(state: Dictionary, faction: String,
        goal: Dictionary, reason: String, tick: int, mult: int) -> Dictionary:
    if not validate(state) or faction.is_empty() or tick < 0:
        return {"ok": false, "reason": "invalid_execution_state"}
    var next: Dictionary = state.duplicate(true)
    var attempts: int = _next_failure_count(next, faction, goal)
    if attempts < MAX_GOAL_RETRIES:
        next["deferred_goals"][faction] = {
            "goal": goal.duplicate(true), "failed_attempts": attempts,
            "last_failed_tick": tick, "last_reason": "planning:" + reason
        }
    else:
        next["deferred_goals"].erase(faction)
    next["blocked_until"][faction] = _saturated_add(tick,
        next_retry_delay(mult, attempts))
    return {"ok": true, "state": next, "attempts": attempts}

## Terminal attempt release: keep only RETRYABLE goals. Even after a
## failed dispatch, NEVER reuse action IDs or quoted source markets.
static func record_terminal(state: Dictionary, faction: String,
        plan: Dictionary, status: String, reason: String,
        tick: int, mult: int, stock: Variant) -> Dictionary:
    if not validate(state) or not (plan.get("goal", null) is Dictionary)             or not (plan.get("ledger", null) is Dictionary):
        return {"ok": false, "reason": "invalid_terminal_plan"}
    var next: Dictionary = state.duplicate(true)
    var goal: Dictionary = plan["goal"]
    next["active"].erase(faction)
    if status == "completed":
        next["deferred_goals"].erase(faction)
        next["blocked_until"].erase(faction)
    else:
        var attempts: int = _next_failure_count(next, faction, goal)
        if retryable(status, reason) and attempts < MAX_GOAL_RETRIES:
            next["deferred_goals"][faction] = {
                "goal": goal.duplicate(true), "failed_attempts": attempts,
                "last_failed_tick": tick, "last_reason": reason
            }
        else:
            next["deferred_goals"].erase(faction)
        next["blocked_until"][faction] = _saturated_add(tick,
            next_retry_delay(mult, attempts))
    var ledger: Dictionary = plan["ledger"]
    var outcome: Dictionary = {
        "faction_id": faction,
        "plan_id": str(ledger.get("plan_id", "")),
        "planner_id": str(ledger.get("planner_id", "")),
        "tick": tick, "final_status": status, "reason": reason,
        "steps": (ledger.get("steps", []) as Array).duplicate(true),
        "goal": goal.duplicate(true),
        "observed_goal_stock": stock,
        "produced_goal_units": produced_goal_units(plan)
            if bool(plan.get("production_goal", false)) else null,
        "required_goal_production_units":
            plan.get("production_target_delta", 0)
            if bool(plan.get("production_goal", false)) else null
    }
    next["history"].append(outcome)
    while next["history"].size() > MAX_OUTCOMES:
        next["history"].pop_front()
    return {"ok": true, "state": next, "outcome": outcome}

## Frozen Rust product-qualified counters; repeated steps share a
## cumulative output key. Legacy unqualified source counters apply to
## action.commodity ONLY, not to a co-product from the same recipe.
## N155 frozen ActionSpec encodes recipe outputs as [Commodity, u32].
## Standalone N121 fixtures also used {commodity, quantity}. Normalize at
## the driver boundary; never change the planner catalogue's source shape.
static func output_spec(raw: Variant) -> Dictionary:
    if raw is Array and raw.size() == 2:
        var good: String = str(raw[0])
        if good.is_empty() or typeof(raw[1]) != TYPE_INT or int(raw[1]) <= 0:
            return {}
        return {"commodity": good, "quantity": int(raw[1])}
    if raw is Dictionary:
        var good: String = str(raw.get("commodity", ""))
        var count: Variant = raw.get("quantity", null)
        if good.is_empty() or typeof(count) != TYPE_INT or int(count) <= 0:
            return {}
        return {"commodity": good, "quantity": int(count)}
    return {}

static func output_key(action: Dictionary, commodity: String) -> String:
    return str(action.get("action_id", "")) + "::output:" + commodity

static func output_value(counters: Dictionary, action: Dictionary,
        commodity: String) -> Variant:
    var key: String = output_key(action, commodity)
    if counters.has(key):
        return counters[key]
    if str(action.get("commodity", "")) == commodity:
        return counters.get(str(action.get("action_id", "")), null)
    return null

static func produced_goal_units(plan: Dictionary) -> float:
    if not (plan.get("goal", null) is Dictionary):
        return 0.0
    var goal: Dictionary = plan["goal"]
    var commodity: String = str(goal.get("commodity", ""))
    var dest: String = str(goal.get("destination_id", ""))
    var baselines: Dictionary = plan.get("production_baselines", {})
    var accounted: Dictionary = plan.get("production_accounted", {})
    if not (plan.get("actions", null) is Array):
        return 0.0
    var total: float = 0.0
    for action in plan["actions"]:
        if not (action is Dictionary) or str(action.get("kind", "")) != "produce":
            continue
        if str(action.get("destination_id", "")) != dest:
            continue
        for raw_output in action.get("outputs", []):
            var output: Dictionary = output_spec(raw_output)
            if output.is_empty() or (str(output["commodity"]) != commodity
                    or int(output["quantity"]) <= 0):
                continue
            var start_value: Variant = output_value(baselines, action, commodity)
            var start: float = float(start_value) if start_value != null else 0.0
            var end_value: Variant = output_value(accounted, action, commodity)
            var end: float = float(end_value) if end_value != null else start
            total += maxf(0.0, end - start)
            break
    return total

static func active_production_priority(plan: Dictionary,
        gate: Dictionary) -> Dictionary:
    if not ["ready", "await_native"].has(str(gate.get("kind", ""))):
        return {"ok": true, "priority": null}
    var step_id: String = str(gate.get("step_id", ""))
    var ledger: Dictionary = plan.get("ledger", {})
    var action_id: String = ""
    for record in ledger.get("steps", []):
        if str(record.get("step", {}).get("step_id", "")) == step_id:
            action_id = str(record["step"].get("action_id", ""))
            break
    if action_id.is_empty():
        return {"ok": false, "reason": "missing_action_step"}
    for action in plan.get("actions", []):
        if str(action.get("action_id", "")) != action_id:
            continue
        if str(action.get("kind", "")) != "produce":
            return {"ok": true, "priority": null}
        var preferred: String = str(action.get("commodity", ""))
        for raw_output in action.get("outputs", []):
            var out: Dictionary = output_spec(raw_output)
            if not out.is_empty() and (str(out["commodity"]) ==
                    str(plan.get("goal", {}).get("commodity", ""))):
                preferred = str(out["commodity"])
        if preferred.is_empty():
            return {"ok": false, "reason": "unknown_recipe_product"}
        return {"ok": true, "priority": {
            "destination_id": action.get("destination_id", ""),
            "commodity": preferred}}
    return {"ok": false, "reason": "missing_action"}

static func _saturated_add(a: int, b: int) -> int:
    return MAX_U64_SIGNED if a > MAX_U64_SIGNED - b else a + b
