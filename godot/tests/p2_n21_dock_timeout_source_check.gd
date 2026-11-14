extends RefCounted
## Deferred frozen Rust N21 ShipAction::Dock patience tests, source only.
## Run with the final all-project Godot 4.7.2 acceptance, not interim.
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func ship(morale: float, contract_id: String = "") -> Dictionary:
    return {"id": "waiter", "location": "dock-location",
        "docked_at": "", "transit": {},
        "crew": {"morale": morale}, "active_contract_id": contract_id,
        "dock_attempt_start_tick": null}

static func _check_budget(morale: float, cid: String,
        budget: int, mult: int) -> bool:
    var s: Dictionary = ship(morale, cid)
    if not N84._native_dock_wait(s, 100, mult).is_empty() or (
            s["dock_attempt_start_tick"] != 100):
        return false
    if not N84._native_dock_wait(s, 100 + budget - 1, mult).is_empty():
        return false
    var expired: Dictionary = N84._native_dock_wait(s, 100 + budget, mult)
    return str(expired.get("status", "")) == Bt.FAILURE and (
        str(expired.get("reason", "")) == "n21_original_dock_wait_timeout") and (
        s["dock_attempt_start_tick"] == null)

static func run_checks() -> Dictionary:
    # Exact Rust 150 / 60 / 30 base tick constants, multiplied by config.
    if not _check_budget(80.0, "", 60, 1):
        return {"ok": false, "reason": "n21_default_60_ticks"}
    if not _check_budget(39.0, "", 30, 1):
        return {"ok": false, "reason": "n21_low_morale_30_ticks"}
    if not _check_budget(10.0, "paid-1", 150, 1):
        return {"ok": false, "reason": "n21_contract_150_overrides_low_morale"}
    if not _check_budget(80.0, "", 120, 2):
        return {"ok": false, "reason": "n21_multiplier_exact"}
    var flying: Dictionary = ship(80.0)
    flying["location"] = ""
    flying["transit"] = {"token": 1}
    var flight: Dictionary = N84._native_dock_wait(flying, 100, 1)
    if flight.get("status") != Bt.RUNNING or flying[
            "dock_attempt_start_tick"] != null:
        return {"ok": false, "reason": "n21_started_wait_before_arrival"}
    var docked: Dictionary = ship(80.0)
    docked["docked_at"] = "physical-station"
    docked["dock_attempt_start_tick"] = 75
    if not N84._native_dock_wait(docked, 100, 1).is_empty() or (
            docked["dock_attempt_start_tick"] != null):
        return {"ok": false, "reason": "n21_arrival_did_not_clear_wait"}
    var saved: Dictionary = ship(80.0)
    saved["dock_attempt_start_tick"] = 10
    var resumed: Variant = JSON.parse_string(JSON.stringify(saved))
    if not (resumed is Dictionary) or (
            int(resumed.get("dock_attempt_start_tick", -1)) != 10):
        return {"ok": false, "reason": "n21_n38_integral_cursor_not_saved"}
    var timed_out: Dictionary = N84._native_dock_wait(resumed, 70, 1)
    if timed_out.get("status") != Bt.FAILURE or (
            resumed["dock_attempt_start_tick"] != null):
        return {"ok": false, "reason": "n21_restore_reset_original_wait"}
    return {"ok": true, "status": "DEFERRED_RUST_SOURCE_ONLY_NOT_RUN"}
