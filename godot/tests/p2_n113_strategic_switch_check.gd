extends SceneTree
## Deferred SOURCE test for native Rust director.rs::retain_or_switch.
## No Godot run or CI until one combined post-integration acceptance.
const Switch = preload("res://scripts/sim/phase2/unified_n113_strategy_switch.gd")

func _fail(why: String) -> void:
    push_error("P2_N113_ORIGINAL_STRATEGY_PARITY: " + why)
    quit(1)

func _old() -> Dictionary:
    return {"kind": "supply", "target": "earth-station|food",
        "score": 40.0, "since": 30,
        "reason": "viable_commitment_retained", "pending": null}

func _offers(old_score: float = 40.0,
        candidate_score: float = 60.0) -> Array:
    return [
        {"action": "supply", "target": "earth-station|food",
         "score": old_score, "available": true},
        {"action": "migrate", "target": "mars-colony",
         "score": candidate_score, "available": true}]

func _assert(condition: bool, msg: String) -> bool:
    if not condition:
        _fail(msg)
        return false
    return true

func _initialize() -> void:
    var memory: Dictionary = _old()
    var original: Dictionary = memory.duplicate(true)
    var first: Dictionary = Switch.decide(memory, _offers(), 60)
    if not _assert(first.get("ok", false) and first.get("pending", false)
            and first.get("reason") == "alternative_pending_confirmation"
            and first.get("choice", {}).get("action") == "supply",
            "first real N113 cycle spent too early"):
        return
    if not _assert(memory == original and int(first["memory"][
            "pending"]["consecutive_cycles"]) == 1 and
            int(first["memory"]["pending"]["first_seen_tick"]) == 60,
            "pending N113 was not purely recorded for later N38 save"):
        return
    var repeated: Dictionary = Switch.decide(first["memory"],
        _offers(), 60)
    if not _assert(not repeated.get("ok", true),
            "one N134 tick counted as two confirmations"):
        return
    var second: Dictionary = Switch.decide(first["memory"],
        _offers(), 120)
    if not _assert(second.get("ok", false) and not second.get(
            "pending", true) and second.get("reason") ==
            "sustained_higher_utility" and second[
            "choice"]["action"] == "migrate" and
            second["memory"]["kind"] == "migrate" and
            second["memory"]["target"] == "mars-colony" and
            second["memory"]["pending"] == null and
            int(second["memory"]["since"]) == 120,
            "two valid 1.2x cycles failed to switch to migration"):
        return
    var more: Dictionary = Switch.decide(second["memory"],
        _offers(), 180)
    if not _assert(more.get("reason") == "viable_commitment_retained"
            and int(more["memory"]["since"]) == 120,
            "existing migrated strategy was restarted instead of retained"):
        return
    var equal: Dictionary = Switch.decide(_old(),
        _offers(50.0, 60.0), 60)
    if not _assert(equal.get("pending", false),
            "equality at Rust >=1.20 threshold was rejected"):
        return
    var weak: Dictionary = Switch.decide(_old(),
        _offers(51.0, 60.0), 60)
    if not _assert(weak.get("reason") ==
            "alternative_not_strong_enough" and
            weak["memory"]["pending"] == null,
            "sub-1.2 score fabricated a switch"):
        return
    var recovered: Dictionary = Switch.decide(first["memory"],
        _offers(55.0, 60.0), 120)
    if not _assert(recovered.get("reason") ==
            "alternative_not_strong_enough" and
            recovered["memory"]["pending"] == null,
            "persisted pending ignored refreshed original incumbent score"):
        return
    var extinct: Array = _offers()
    extinct[0]["available"] = false
    var no_old: Dictionary = Switch.decide(_old(), extinct, 60)
    if not _assert(no_old.get("reason") ==
            "previous_goal_unavailable" and
            no_old["choice"]["action"] == "migrate" and
            no_old["memory"]["pending"] == null,
            "missing source incumbent illegally waited two cycles"):
        return
    var funded: Dictionary = Switch.decide(_old(), _offers(), 60,
        false, true)
    if not _assert(funded.get("reason") ==
            "outstanding_native_plan_retained" and
            funded["choice"]["action"] == "supply",
            "real paid N104 source supply commitment was displaced"):
        return
    var crisis: Dictionary = Switch.decide(_old(), [
        {"action": "supply", "target": "new-food",
         "score": 1000.0, "available": true},
        {"action": "supply", "target": "earth-station|food",
         "score": 40.0, "available": true},
        {"action": "migrate", "target": "mars-colony",
         "score": 60.0, "available": true},
    ], 60, true)
    if not _assert(crisis.get("reason") == "urgent_life_support"
            and crisis["choice"]["target"] == "new-food",
            "valid original Rust survival candidate did not bypass hysteresis"):
        return
    var same_score: Dictionary = Switch.decide({}, [
        {"action": "research", "target": "techA",
         "score": 60.0, "available": true},
        {"action": "migrate", "target": "mars-colony",
         "score": 60.0, "available": true},
    ], 60)
    if not _assert(same_score["choice"]["action"] == "migrate",
            "Rust tie-break should choose alphabetical action/target"):
        return
    var no_work: Dictionary = Switch.decide(_old(), [
        {"action": "migrate", "target": "mars-colony",
         "score": 60.0, "available": false}], 120)
    if not _assert(no_work.get("ok", false) and
            no_work["choice"].is_empty() and
            no_work["memory"] == _old(),
            "invalid no-candidate state mutated N113 strategy"):
        return
    print("P2_N113_RUST_RETAIN_OR_SWITCH_SOURCE_CHECK_PASS")
    quit(0)
