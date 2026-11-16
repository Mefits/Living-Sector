extends RefCounted
## PERF E opt-in exact checkpoint trace gate. No World/Runner ownership.
## Both sources must supply independently captured completed-tick snapshots.
## Retains bounded detached pairs; never normalizes away N9/BT/RNG differences.
const ORACLE = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const MAX_PAIRS: int = 1024
var _last_tick: int = -1
var _pairs: int = 0
var _failure: Dictionary = {}
var _history: Array[Dictionary] = []
var _restart_pending: bool = false

func accept_pair(tick: int, direct: Dictionary, candidate: Dictionary) -> bool:
    if not _failure.is_empty():
        return false
    if _restart_pending:
        return _reject(tick, "restart_not_verified")
    if tick < 0 or (_last_tick >= 0 and tick != _last_tick + 1):
        return _reject(tick, "non_contiguous_tick")
    if not _valid_detached(direct, 0) or not _valid_detached(candidate, 0):
        return _reject(tick, "unsafe_checkpoint")
    if not direct.has("tick") or not candidate.has("tick"):
        return _reject(tick, "missing_tick")
    if typeof(direct["tick"]) != TYPE_INT or typeof(candidate["tick"]) != TYPE_INT:
        return _reject(tick, "invalid_tick_type")
    if int(direct["tick"]) != tick or int(candidate["tick"]) != tick:
        return _reject(tick, "checkpoint_tick_mismatch")
    var comparison: Dictionary = ORACLE.compare(direct, candidate)
    if not bool(comparison.get("equal", false)):
        _failure = {"tick": tick, "reason": "checkpoint_mismatch",
            "difference": comparison.get("difference", {}).duplicate(true)}
        return false
    _last_tick = tick
    _pairs += 1
    _history.append({"tick": tick, "checkpoint": direct.duplicate(true)})
    if _history.size() > MAX_PAIRS:
        _history.pop_front()
    return true

## Explicitly arm an N38 restart boundary. A new tick is forbidden until
## verify_restart succeeds; this prevents a caller silently skipping replay.
func require_restart_verification() -> bool:
    if not _failure.is_empty() or _last_tick < 0 or _history.is_empty() or _restart_pending:
        return false
    _restart_pending = true
    return true

## A restart must compare its loaded checkpoint with the last committed
## checkpoint at that exact tick BEFORE accepting any subsequent tick.
func verify_restart(tick: int, restored: Dictionary) -> bool:
    if not _failure.is_empty():
        return false
    if not _restart_pending:
        return _reject(tick, "restart_not_requested")
    if tick != _last_tick or _history.is_empty():
        return _reject(tick, "restart_boundary_mismatch")
    if not _valid_detached(restored, 0):
        return _reject(tick, "unsafe_restart_checkpoint")
    var comparison: Dictionary = ORACLE.compare(_history.back()["checkpoint"], restored)
    if not bool(comparison.get("equal", false)):
        _failure = {"tick": tick, "reason": "restart_mismatch",
            "difference": comparison.get("difference", {}).duplicate(true)}
        return false
    _restart_pending = false
    return true

func status() -> Dictionary:
    return {"ok": _failure.is_empty(), "pairs": _pairs,
        "last_tick": _last_tick, "retained": _history.size(),
        "restart_pending": _restart_pending,
        "failure": _failure.duplicate(true)}

func _reject(tick: int, reason: String) -> bool:
    _failure = {"tick": tick, "reason": reason}
    return false

static func _valid_detached(value: Variant, depth: int) -> bool:
    if depth > ORACLE.MAX_DEPTH:
        return false
    match typeof(value):
        TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
            return true
        TYPE_DICTIONARY:
            for key in value:
                if not _valid_detached(key, depth + 1) or not _valid_detached(value[key], depth + 1):
                    return false
            return true
        TYPE_ARRAY:
            for entry in value:
                if not _valid_detached(entry, depth + 1):
                    return false
            return true
    return false
