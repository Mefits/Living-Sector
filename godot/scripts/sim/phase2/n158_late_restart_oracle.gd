extends RefCounted
## PERF E: opt-in N38 milestone restart verification on the real N158 path.
## Never advances a paid tick; refuses partial, missing, or divergent checkpoints.
const ORACLE = preload("res://scripts/sim/phase2/n158_checkpoint_parity_oracle.gd")
const TIMED = preload("res://scripts/sim/phase2/n158_timed_phase_probe.gd")
const MILESTONES: Array[int] = [100, 300, 600, 900]

static func verify_detached(expected: Dictionary, restored: Dictionary,
        milestone: int) -> Dictionary:
    if not MILESTONES.has(milestone):
        return {"valid": false, "reason": "invalid_milestone"}
    for checkpoint in [expected, restored]:
        if typeof(checkpoint.get("native_production", null)) != TYPE_DICTIONARY:
            return {"valid": false, "reason": "missing_native_checkpoint"}
        if int(checkpoint["native_production"].get("tick", -1)) != milestone:
            return {"valid": false, "reason": "native_tick_mismatch"}
    var comparison: Dictionary = ORACLE.compare(expected, restored)
    if not comparison.get("equal", false):
        return {"valid": false, "reason": "restart_divergence",
            "difference": comparison.get("difference", {})}
    return {"valid": true, "milestone": milestone, "exact": true}

static func verify_file(path: String, seed: Dictionary,
        expected: Dictionary, milestone: int) -> Dictionary:
    if not MILESTONES.has(milestone):
        return {"valid": false, "reason": "invalid_milestone"}
    if path.is_empty() or not FileAccess.file_exists(path):
        return {"valid": false, "reason": "missing_checkpoint_file"}
    var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
    if handle == null:
        return {"valid": false, "reason": "checkpoint_read_failed"}
    var raw: Variant = handle.get_var(false)
    var read_error: Error = handle.get_error()
    handle.close()
    if read_error != OK and read_error != ERR_FILE_EOF:
        return {"valid": false, "reason": "checkpoint_read_failed"}
    if not (raw is Dictionary):
        return {"valid": false, "reason": "invalid_checkpoint_payload"}
    var persisted: Dictionary = verify_detached(expected, raw, milestone)
    if not persisted.get("valid", false):
        return {"valid": false, "reason": "persisted_" + str(persisted["reason"]),
            "difference": persisted.get("difference", {})}
    var restarted = TIMED.new()
    if not restarted.start_from_seed(seed):
        return {"valid": false, "reason": "restart_seed_rejected"}
    if not restarted.restore_checkpoint(raw, seed):
        return {"valid": false, "reason": "restart_restore_rejected"}
    if restarted.tick_count != milestone:
        return {"valid": false, "reason": "restart_clock_mismatch"}
    var restored: Dictionary = restarted.checkpoint()
    return verify_detached(raw, restored, milestone)
