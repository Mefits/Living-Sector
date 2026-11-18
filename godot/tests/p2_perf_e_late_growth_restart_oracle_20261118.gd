extends SceneTree
## PERF E: exact checkpoint/restart oracle, positive and adversarial fixtures.
const RESTART = preload("res://scripts/sim/phase2/n158_late_restart_oracle.gd")

func _snapshot(tick: int) -> Dictionary:
    return {"tick": tick, "native_production": {"tick": tick,
        "world": {"ships": {"ship-1": {"cargo": {"ore": 4}}},
            "markets": {}, "facilities": {}, "populations": {}},
        "ledger": {"receipts": [{"id": "r-1"}]}},
        "clock": {"tick": tick}, "rng": {"draws": 17},
        "bt": {"ship-1": "idle"}, "n38": {"version": 1}}

func _initialize() -> void:
    var original: Dictionary = _snapshot(300)
    assert(RESTART.verify_detached(original, original.duplicate(true), 300)["valid"])
    for domain in ["rng", "bt", "clock", "n38"]:
        var changed: Dictionary = original.duplicate(true)
        changed[domain] = {"tampered": true}
        assert(RESTART.verify_detached(original, changed, 300)["reason"] ==
            "restart_divergence")
    var cargo: Dictionary = original.duplicate(true)
    cargo["native_production"]["world"]["ships"]["ship-1"]["cargo"]["ore"] = 5
    assert(RESTART.verify_detached(original, cargo, 300)["reason"] ==
        "restart_divergence")
    var receipt: Dictionary = original.duplicate(true)
    receipt["native_production"]["ledger"]["receipts"].clear()
    assert(RESTART.verify_detached(original, receipt, 300)["reason"] ==
        "restart_divergence")
    var tick_drift: Dictionary = original.duplicate(true)
    tick_drift["native_production"]["tick"] = 301
    assert(RESTART.verify_detached(original, tick_drift, 300)["reason"] ==
        "native_tick_mismatch")
    assert(RESTART.verify_detached(original, original, 301)["reason"] ==
        "invalid_milestone")
    assert(RESTART.verify_detached(original, {}, 300)["reason"] ==
        "missing_native_checkpoint")
    assert(RESTART.verify_file("res://logs/late-growth/absent-oracle-300.bin",
        {}, original, 300)["reason"] == "missing_checkpoint_file")
    # Verify actual FileAccess bytes and reject altered persisted payload
    # before attempting to boot N158 from the intentionally empty seed.
    var filename: String = "user://p2_perf_e_restart_negative.bin"
    var file: FileAccess = FileAccess.open(filename, FileAccess.WRITE)
    assert(file != null)
    file.store_var(cargo)
    file.close()
    assert(RESTART.verify_file(filename, {}, original, 300)["reason"] ==
        "persisted_restart_divergence")
    file = FileAccess.open(filename, FileAccess.WRITE)
    assert(file != null)
    file.store_var("invalid")
    file.close()
    assert(RESTART.verify_file(filename, {}, original, 300)["reason"] ==
        "invalid_checkpoint_payload")
    DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
    print("P2_PERF_E_LATE_GROWTH_RESTART_ORACLE PASS")
    quit(0)
