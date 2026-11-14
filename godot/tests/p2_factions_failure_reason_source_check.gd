extends SceneTree
## Source regression: propagate a real P2 failed substage, not just
## "factions tick=361" or yesterday's successful N153 status.
## Deferred until the coordinated final Godot diagnostic run.
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _fail(what: String) -> void:
    push_error("P2_FACTIONS_FAILURE_REASON: " + what)
    quit(1)

func _initialize() -> void:
    var runner = Runtime.new()
    runner.set("_last_n153_result", {"ok": true, "tick": 361})
    runner.set("_last_n151_docks", {
        "ok": false, "fatal": true,
        "reason": "n151_invalid_original_temporary_dock:bad_policy"})
    var reason: String = runner._integrated_phase_failure_reason("factions")
    if reason != "n151_colony_docks:n151_invalid_original_temporary_dock:bad_policy":
        _fail("N151 reason masked by successful previous N153: " + reason)
        return
    runner.set("_last_n151_docks", {"ok": true, "tick": 361})
    runner.set("_last_native_passengers", {
        "ok": false, "fatal": true,
        "reason": "n104_single_world_escrow_mismatch"})
    reason = runner._integrated_phase_failure_reason("factions")
    if reason != "n104_passengers:n104_single_world_escrow_mismatch":
        _fail("paid passenger root cause lost: " + reason)
        return
    runner.set("_last_native_passengers", {"ok": true, "tick": 361})
    runner.set("_last_research_result", {
        "ok": false, "reason": "n143_stale_original_policy"})
    reason = runner._integrated_phase_failure_reason("factions")
    if reason != "n143_research:n143_stale_original_policy":
        _fail("research mandate reason lost: " + reason)
        return
    runner.set("_last_research_result", {"ok": true, "tick": 361})
    if runner._integrated_phase_failure_reason("factions") != (
            "factions_rejected_without_substage_result"):
        _fail("missing failure substage was reported as success")
        return
    print("P2_FACTIONS_FAILURE_REASON_SOURCE_CHECK_PASS")
    quit(0)
