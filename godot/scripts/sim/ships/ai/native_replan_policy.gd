extends RefCounted
## N80. Exact interruption/commit policy in frozen
## agents/ship/behavior.rs decide_and_act (Bundle 2.2).
## This does NOT release a contract itself: it returns intents for the
## future atomic CommandBuffer/Apply phase, with no speculative mutation.
const Goals = preload("res://scripts/sim/ships/ai/native_ship_goal_policy.gd")
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")
const MASK32: int = 0xffffffff
const SHIFT32: int = 4294967296
const OFFSET_HI: int = 0xcbf29ce4
const OFFSET_LO: int = 0x84222325
const PRIME_HI: int = 0x100
const PRIME_LO: int = 0x1b3

## Exact (FNV-1a u64 hash bytes) % 40, calculated with two unsigned
## 32-bit limbs. GDScript does not need undocumented signed overflow.
## All intermediates stay <2^53 and are represented exactly.
static func ship_stagger_offset(ship_id: String) -> int:
    if ship_id.is_empty():
        return -1
    var hi: int = OFFSET_HI
    var lo: int = OFFSET_LO
    for byte_value in ship_id.to_utf8_buffer():
        lo = lo ^ int(byte_value)
        var low_product: int = lo * PRIME_LO
        var new_lo: int = low_product & MASK32
        var carry: int = low_product >> 32
        var new_hi: int = (hi * PRIME_LO + lo * PRIME_HI + carry) & MASK32
        hi = new_hi
        lo = new_lo
    # 2^32 % 40 == 16.
    return (
        ((hi % Goals.REPLAN_CHECK_INTERVAL_TICKS) * 16
            + lo % Goals.REPLAN_CHECK_INTERVAL_TICKS)
        % Goals.REPLAN_CHECK_INTERVAL_TICKS
    )

## Input = already-persisted, authoritative ShipAI/ShipEconomy + current
## tick data. "has_current_bt" rather than goal text determines needs_plan.
## "assigned_delivery" / "assigned_builder" come only from real strategy
## orders. No auto-generated assignments.
static func should_evaluate(snapshot: Dictionary) -> Dictionary:
    var ship_id: String = str(snapshot.get("ship_id", ""))
    var tick_value: Variant = snapshot.get("tick", null)
    var last_value: Variant = snapshot.get("last_plan_tick", null)
    if ship_id.is_empty() or not (tick_value is int) or not (last_value is int):
        return _err("invalid_native_replan_clock")
    var tick: int = int(tick_value)
    var last: int = int(last_value)
    if tick < 0 or last < 0:
        return _err("negative_tick")
    var goal: String = str(snapshot.get("current_goal", "idle"))
    var has_bt: bool = bool(snapshot.get("has_current_bt", false))
    var active_contract: bool = bool(snapshot.get("active_contract", false))
    var pending: bool = bool(snapshot.get("pending_transaction", false))
    var assigned_delivery: bool = bool(snapshot.get("assigned_delivery", false))
    var assigned_builder: bool = bool(snapshot.get("assigned_builder", false))
    var offset: int = ship_stagger_offset(ship_id)
    var elapsed: int = maxi(tick - last, 0)
    var forced_new_order: bool = (
        (assigned_delivery or assigned_builder)
        and not active_contract and not pending
        and not goal.begins_with("fulfill_")
        and not ["construct", "refuel", "rest_crew"].has(goal)
    )
    var needs_plan: bool = not has_bt or forced_new_order
    var due: bool = (
        not needs_plan
        and not pending
        and not (assigned_delivery and active_contract)
        and not assigned_builder
        and Goals.is_replan_eligible(goal)
        and elapsed >= Goals.REPLAN_MIN_COMMIT_TICKS
        and (tick + offset) % Goals.REPLAN_CHECK_INTERVAL_TICKS == 0
    )
    return {"ok": true, "evaluate": needs_plan or due,
        "needs_plan": needs_plan, "periodic_replan_due": due,
        "offset": offset, "elapsed": elapsed,
        "forced_new_order": forced_new_order}

## Called ONLY after plan_goal evaluated an actual feasible candidate.
## Contract break means Return Action Intent ("ReleaseContract") to be
## issued later by the atomic Rust-equivalent Apply phase.
static func resolve_offer(snapshot: Dictionary, profile: Dictionary,
        candidate: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return _err("invalid_personality")
    if not bool(candidate.get("ok", false)):
        return _err("invalid_candidate")
    var current: Variant = snapshot.get("current_goal_score", null)
    var proposal: Variant = candidate.get("score", null)
    if (not (current is int or current is float)
            or not (proposal is int or proposal is float)
            or not is_finite(float(current)) or not is_finite(float(proposal))):
        return _err("invalid_goal_scores")
    if float(current) < 0.0 or float(proposal) < 0.0:
        return _err("negative_goal_scores")
    var eval_result: Dictionary = should_evaluate(snapshot)
    if not bool(eval_result.get("ok", false)):
        return eval_result
    if not bool(eval_result["evaluate"]):
        return {"ok": true, "switch": false, "reason": "not_due",
            "threshold": 0.0, "release_contract_intent": false}
    var obligation: bool = bool(snapshot.get("active_contract", false))
    var ratio: float = Goals.REPLAN_SCORE_RATIO
    if obligation:
        ratio += (
            Goals.CONTRACT_OBLIGATION_WEIGHT
            + clampf(float(profile["loyalty"]), 0.0, 1.0)
            * Goals.LOYALTY_REPLAN_MULTIPLIER
        )
    var accepted: bool = bool(eval_result["needs_plan"])         or float(proposal) >= float(current) * ratio
    return {"ok": true, "switch": accepted,
        "reason": "needs_plan" if bool(eval_result["needs_plan"]) else             ("better_offer" if accepted else "commitment_threshold"),
        "threshold": float(current) * ratio,
        "effective_ratio": ratio,
        "release_contract_intent": accepted and             bool(eval_result["periodic_replan_due"]) and obligation,
        "clear_pending_transaction_intent": accepted,
        "new_goal": str(candidate.get("name", "")) if accepted else "",
        "new_goal_score": float(proposal) if accepted else float(current),
        "stagger_offset": int(eval_result["offset"])}
 
static func _err(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
