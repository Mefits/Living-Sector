extends RefCounted
## N80. Frozen Rust ai/utility.rs: additive consideration scorer.
## This is intentionally separate from the tiered ship::behavior::plan_goal.
const Personality = preload("res://scripts/sim/ships/ai/native_personality.gd")

## spec = {"name": str, "factors": [{"key": str, "direction":
## "positive" | "negative"}, ...]}
## considerations = {key: {"axis": str, "value": float in [0,1]}}
static func score_action(spec: Dictionary, considerations: Dictionary,
        profile: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return {"ok": false, "reason": "invalid_personality"}
    var name: Variant = spec.get("name", null)
    var factors: Variant = spec.get("factors", null)
    if not (name is String) or name.is_empty() or not (factors is Array):
        return {"ok": false, "reason": "invalid_action_spec"}
    var score: float = 0.0
    for factor in factors:
        if not (factor is Dictionary):
            return {"ok": false, "reason": "invalid_factor"}
        var key: Variant = factor.get("key", null)
        var direction: Variant = factor.get("direction", null)
        if not (key is String) or not (direction is String):
            return {"ok": false, "reason": "invalid_factor_key"}
        if direction != "positive" and direction != "negative":
            return {"ok": false, "reason": "invalid_factor_direction"}
        if not considerations.has(key):
            # Rust score_action uses filter_map and skips absent factors.
            continue
        var c: Variant = considerations[key]
        if not (c is Dictionary):
            return {"ok": false, "reason": "invalid_consideration"}
        var axis: Variant = c.get("axis", null)
        var value: Variant = c.get("value", null)
        if not (axis is String) or not Personality.AXES.has(axis):
            return {"ok": false, "reason": "unknown_personality_axis"}
        if not (value is int or value is float) or not is_finite(float(value)):
            return {"ok": false, "reason": "invalid_consideration_value"}
        if float(value) < 0.0 or float(value) > 1.0:
            return {"ok": false, "reason": "unnormalized_consideration"}
        var contribution: float = float(value) * float(profile[axis])
        score += contribution if direction == "positive" else -contribution
    return {"ok": true, "name": name, "base_score": score}

## Rust best_action takes strictly greater than the previous high score.
## A tie therefore leaves the EARLIER supplied action as the winner.
## Its score includes prefer_goals[name] regardless of factor count.
static func best_action(actions: Array, considerations: Dictionary,
        profile: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return {"ok": false, "reason": "invalid_personality"}
    var best_name: String = "idle"
    var best_score: float = 0.0
    for value in actions:
        if not (value is Dictionary):
            return {"ok": false, "reason": "invalid_action"}
        var result: Dictionary = score_action(value, considerations, profile)
        if not bool(result.get("ok", false)):
            return result
        var name: String = str(result["name"])
        var total: float = float(result["base_score"]) + float(
            (profile["prefer_goals"] as Dictionary).get(name, 0.0))
        if total > best_score:
            best_score = total
            best_name = name
    return {"ok": true, "name": best_name, "score": best_score}

## Rust rank_actions uses a stable descending sort. Keep equal-score
## actions in source order, including negative/zero scores (not filtered).
static func rank_actions(actions: Array, considerations: Dictionary,
        profile: Dictionary) -> Dictionary:
    if not Personality.validate(profile):
        return {"ok": false, "reason": "invalid_personality"}
    var result: Array = []
    for action in actions:
        if not (action is Dictionary):
            return {"ok": false, "reason": "invalid_action"}
        var score: Dictionary = score_action(action, considerations, profile)
        if not bool(score.get("ok", false)):
            return score
        var name: String = str(score["name"])
        var total: float = float(score["base_score"]) + float(
            (profile["prefer_goals"] as Dictionary).get(name, 0.0))
        var insert_at: int = result.size()
        for i in range(result.size()):
            if total > float(result[i]["score"]):
                insert_at = i
                break
        result.insert(insert_at, {"name": name, "score": total})
    return {"ok": true, "ranked": result}
