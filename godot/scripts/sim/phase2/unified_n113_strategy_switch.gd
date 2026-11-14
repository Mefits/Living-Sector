extends RefCounted
## Pure frozen Rust strategy/director.rs::retain_or_switch.
## No second Director, tick, World, N9, N104 or paid operation.
## The caller MUST give current source-scored and source-validated offers.
const SUPERIORITY: float = 1.20
const CONFIRMATIONS: int = 2

static func _target(raw: Variant) -> String:
    return "" if raw == null else str(raw)

static func _valid(row: Variant) -> bool:
    if not (row is Dictionary):
        return false
    if str(row.get("action", "")) not in [
            "supply", "research", "expand", "migrate"]:
        return false
    var raw_score: Variant = row.get("score", null)
    return (raw_score is float or raw_score is int) and is_finite(
        float(raw_score)) and row.get("available", null) is bool and (
        row.get("target", null) == null or row.get("target") is String)

static func _same(a: Dictionary, b: Dictionary) -> bool:
    return str(a.get("action", "")) == str(b.get("action", "")) and (
        _target(a.get("target")) == _target(b.get("target")))

static func _chosen(memory: Dictionary, row: Dictionary, tick: int,
        reason: String) -> Dictionary:
    var next: Dictionary = memory.duplicate(true)
    if str(next.get("kind", "")) != str(row["action"]) or (
            _target(next.get("target")) != _target(row.get("target"))):
        next["since"] = tick
    next["kind"] = str(row["action"])
    next["target"] = _target(row.get("target"))
    next["score"] = float(row["score"])
    next["reason"] = reason
    next["pending"] = null
    return {"ok": true, "reason": reason, "choice": row.duplicate(true),
        "memory": next, "pending": false}

## A valid offer set is READ-ONLY; this is one actual source decision
## cycle, not one call per frame. The one N39 Apply persists memory only
## once per real N134 cycle, and only N147's admitted Head may post N104.
static func decide(memory: Dictionary, offers: Array, tick: int,
        urgent_life_support: bool = false,
        native_plan_outstanding: bool = false,
        cycle_stride: int = 0) -> Dictionary:
    if tick < 1 or not (memory.get("kind", "") is String) or (
            memory.get("target", "") != null and
            not (memory.get("target") is String)) or (
            not (memory.get("pending", null) == null or
            memory.get("pending") is Dictionary)):
        return {"ok": false, "reason": "n113_invalid_native_source_memory"}
    var eligible: Array = []
    for raw in offers:
        if not _valid(raw):
            return {"ok": false, "reason": "n113_invalid_source_candidate"}
        var offer: Dictionary = raw
        if bool(offer["available"]) and float(offer["score"]) > 0.0:
            eligible.append(offer.duplicate(true))
    if eligible.is_empty():
        return {"ok": true, "reason": "no_feasible_strategic_choice",
            "choice": {}, "memory": memory.duplicate(true), "pending": false}
    eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if float(a["score"]) != float(b["score"]):
            return float(a["score"]) > float(b["score"])
        if str(a["action"]) != str(b["action"]):
            return str(a["action"]) < str(b["action"])
        return _target(a.get("target")) < _target(b.get("target")))
    var best: Dictionary = eligible[0]
    var incumbent: Dictionary = {}
    for offer in eligible:
        if str(offer["action"]) == str(memory.get("kind", "")) and (
                _target(offer.get("target")) == _target(memory.get("target"))):
            incumbent = offer
            break
    if incumbent.is_empty():
        # Rust does NOT wait for two cycles when the old strategy is
        # no longer valid in the CURRENT market/fleet/colony snapshot.
        return _chosen(memory, best, tick, "previous_goal_unavailable")
    if _same(best, incumbent):
        return _chosen(memory, incumbent, tick,
            "viable_commitment_retained")
    if native_plan_outstanding and str(incumbent["action"]) == "supply":
        return _chosen(memory, incumbent, tick,
            "outstanding_native_plan_retained")
    if urgent_life_support and str(best["action"]) == "supply":
        return _chosen(memory, best, tick, "urgent_life_support")
    if float(best["score"]) < float(incumbent["score"]) * SUPERIORITY:
        return _chosen(memory, incumbent, tick,
            "alternative_not_strong_enough")
    var pending_raw: Variant = memory.get("pending", null)
    var prior: Dictionary = pending_raw if pending_raw is Dictionary else {}
    var matching: bool = str(prior.get("kind", "")) == str(
        best["action"]) and _target(prior.get("target")) == _target(
        best.get("target"))
    if matching and int(prior.get("first_seen_tick", -1)) >= tick:
        return {"ok": false,
            "reason": "n113_second_confirmation_in_same_decision_cycle"}
    # Rust coordination recomputes every cycle. Because N147 is invoked
    # only when a REAL prepared passenger offer exists, a missing intervening
    # cycle must invalidate pending confirmation instead of fast-forwarding.
    # The generic source helper still allows unknown cadence by default.
    if matching and cycle_stride > 0 and int(
            prior.get("first_seen_tick", 0)) + cycle_stride != tick:
        matching = false
    var count: int = mini(255, int(prior.get(
        "consecutive_cycles", 0)) + 1) if matching else 1
    if count >= CONFIRMATIONS:
        return _chosen(memory, best, tick, "sustained_higher_utility")
    var staged: Dictionary = memory.duplicate(true)
    staged["score"] = float(incumbent["score"])
    staged["reason"] = "alternative_pending_confirmation"
    staged["pending"] = {"kind": str(best["action"]),
        "target": _target(best.get("target")),
        "consecutive_cycles": count, "first_seen_tick": int(
            prior.get("first_seen_tick", tick)) if matching else tick}
    # Current Head remains with the INCUMBENT; the desired migration
    # cannot spend N9/N104 until a later real N134 confirmation.
    return {"ok": true, "reason": "alternative_pending_confirmation",
        "choice": incumbent.duplicate(true), "memory": staged,
        "pending": true, "candidate": best.duplicate(true)}
