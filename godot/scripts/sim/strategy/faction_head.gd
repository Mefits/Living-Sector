extends RefCounted
## N19 CODE_UNVERIFIED. Pure faction-head arbitration, not an executor.
## Rust: strategy/coordination.rs (single funded grant, survival first,
## 2-cycle hysteresis, no second grant while native order outstanding).
const SUBSIDY_FLOOR: int = 5000
const ACTIONS: Array[String] = ["supply", "research", "expand", "migrate"]

var _memory: Dictionary = {}
var _last_tick: Dictionary = {}
var _last_decision: Dictionary = {}

## faction: id, treasury, crisis, active_native_plan, funded_order,
## already_commissioned, profile {science,expansion}, proposals.
## proposal: action, target, score, ready, cost, reason, essential,
## authorized, department, mandate_mode. Scores come from real native
## administrator/research/colony probes, NEVER invented by this class.
func decide(tick: int, faction: Dictionary) -> Dictionary:
    var id: String = str(faction.get("id", ""))
    if tick < 0 or id.is_empty():
        return {"ok": false, "reason": "invalid_faction"}
    if int(_last_tick.get(id, -1)) == tick:
        return _last_decision[id].duplicate(true)
    if tick < int(_last_tick.get(id, -1)):
        return {"ok": false, "reason": "non_monotonic_tick"}
    var treasury: int = int(faction.get("treasury", 0))
    var spendable: int = maxi(0, treasury - SUBSIDY_FLOOR)
    var proposals: Array[Dictionary] = []
    var seen: Dictionary = {}
    for raw in faction.get("proposals", []):
        if not raw is Dictionary:
            continue
        var action: String = str(raw.get("action", ""))
        var target: String = str(raw.get("target", ""))
        var key: String = action + "|" + target
        if not ACTIONS.has(action) or target.is_empty() or seen.has(key):
            continue
        seen[key] = true
        var cost: int = int(raw.get("cost", 0))
        var score: float = float(raw.get("score", -1.0))
        var reason: String = str(raw.get("reason", "not_ready"))
        var ready: bool = bool(raw.get("ready", false)) and score > 0.0 and cost >= 0
        if bool(faction.get("crisis", false)) and action != "supply":
            ready = false
            reason = "survival_first"
        if not bool(raw.get("authorized", true)):
            ready = false
            reason = "mandate_not_authorized"
        if str(raw.get("mandate_mode", "delegated")) != "delegated":
            ready = false
            reason = "policy_not_delegated"
        if cost > spendable:
            ready = false
            reason = "insufficient_spendable_treasury"
        proposals.append({"action": action, "target": target, "score": score,
            "cost": cost, "ready": ready, "reason": reason,
            "essential": bool(raw.get("essential", false)),
            "department": str(raw.get("department", ""))})
    proposals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["score"]) != float(b["score"]):
            return float(a["score"]) > float(b["score"])
        if str(a["action"]) != str(b["action"]):
            return str(a["action"]) < str(b["action"])
        return str(a["target"]) < str(b["target"]))
    var memory: Dictionary = _memory.get(id, {"action": "wait", "target": "", "pending": "", "confirmations": 0})
    var current: String = str(memory.get("action", "wait")) + "|" + str(memory.get("target", ""))
    var selected: Dictionary = {}
    var reason: String = "no_ready_native_option"
    var locked: bool = bool(faction.get("active_native_plan", false)) or bool(faction.get("funded_order", false))
    if locked:
        reason = "outstanding_native_plan_retained"
    elif bool(faction.get("already_commissioned", false)):
        reason = "already_commissioned_this_tick"
    else:
        var best: Dictionary = {}
        for p in proposals:
            if not p["ready"]:
                continue
            if bool(faction.get("crisis", false)) and not p["essential"]:
                continue
            best = p
            break
        if not best.is_empty():
            var desired: String = str(best["action"]) + "|" + str(best["target"])
            var existing: Dictionary = {}
            for p in proposals:
                if p["ready"] and str(p["action"]) + "|" + str(p["target"]) == current:
                    existing = p
                    break
            if desired == current or existing.is_empty() or (bool(faction.get("crisis", false)) and best["essential"]):
                selected = best
                reason = "survival_first" if bool(faction.get("crisis", false)) else "best_projected_relief"
                memory["pending"] = ""
                memory["confirmations"] = 0
            else:
                if str(memory.get("pending", "")) == desired:
                    memory["confirmations"] = int(memory.get("confirmations", 0)) + 1
                else:
                    memory["pending"] = desired
                    memory["confirmations"] = 1
                if int(memory["confirmations"]) >= 2:
                    selected = best
                    reason = "strategy_switch_confirmed"
                    memory["pending"] = ""
                    memory["confirmations"] = 0
                else:
                    selected = existing
                    reason = "strategy_hysteresis"
    if not selected.is_empty():
        memory["action"] = selected["action"]
        memory["target"] = selected["target"]
    _memory[id] = memory
    _last_tick[id] = tick
    var result: Dictionary = {"ok": true, "tick": tick, "faction_id": id,
        "treasury_before": treasury, "spending_limit": spendable,
        "selected_option": selected.get("action", "wait"),
        "selected_target": selected.get("target", ""),
        "planned_spend": int(selected.get("cost", 0)),
        "committed_spend": 0, "reason": reason,
        "alternatives": proposals, "pending": memory.get("pending", ""),
        "confirmations": memory.get("confirmations", 0),
        "grant": {}}
    if not selected.is_empty():
        result["grant"] = {"faction_id": id, "tick": tick,
            "action": selected["action"], "target": selected["target"],
            "max_first_payment": selected["cost"]}
    _last_decision[id] = result.duplicate(true)
    return result

## Exact grant check. The downstream native executor must revalidate live
## stock, route, price, contract and ledger before posting a paid order.
func authorized(decision: Dictionary, tick: int, faction_id: String, action: String, target: String, cost: int) -> bool:
    var grant: Dictionary = decision.get("grant", {})
    return decision.get("ok", false) and int(decision.get("tick", -1)) == tick and \
        str(decision.get("faction_id", "")) == faction_id and \
        str(grant.get("action", "")) == action and str(grant.get("target", "")) == target and \
        cost >= 0 and cost <= int(grant.get("max_first_payment", -1))

func snapshot() -> Dictionary:
    return {"version": 1, "memory": _memory.duplicate(true),
        "last_tick": _last_tick.duplicate(true),
        "last_decision": _last_decision.duplicate(true)}

func restore(data: Dictionary) -> bool:
    if data.get("version") != 1 or not (data.get("memory") is Dictionary) or \
        not (data.get("last_tick") is Dictionary) or not (data.get("last_decision") is Dictionary):
        return false
    for id in data["last_tick"]:
        if int(data["last_tick"][id]) < 0 or not data["last_decision"].has(id):
            return false
    _memory = data["memory"].duplicate(true)
    _last_tick = data["last_tick"].duplicate(true)
    _last_decision = data["last_decision"].duplicate(true)
    return true
