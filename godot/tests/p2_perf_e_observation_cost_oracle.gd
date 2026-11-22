extends SceneTree
const Probe = preload("res://scripts/sim/phase2/n158_observation_cost_acceptance.gd")

func _initialize() -> void:
    var parity: Dictionary = {"accepted": true, "tick": 100}
    var gate: Dictionary = {"accepted": true, "tick": 100}
    var costs: Dictionary = {"direct_checkpoint": 10,
        "worker_checkpoint_request": 20, "exact_parity_oracle": 3,
        "size_oracle": 5, "n9_event_oracle": 7}
    var good: Dictionary = Probe.sample(100, costs, parity, gate, gate)
    if not good.get("accepted", false):
        _fail("positive sample")
        return
    var later: Dictionary = Probe.sample(300, costs, {
        "accepted": true, "tick": 300}, {
        "accepted": true, "tick": 300}, {
        "accepted": true, "tick": 300})
    if not later.get("accepted", false):
        _fail("positive later sample")
        return
    if not Probe.summarize([good, later], [100, 300]).get("accepted", false):
        _fail("positive bounded summary")
        return
    if not Probe.compare_growth(good, later).get("accepted", false):
        _fail("positive growth")
        return
    costs["size_oracle"] = -1
    if Probe.sample(100, costs, parity, gate, gate).get("accepted", false):
        _fail("negative time admitted")
        return
    costs["size_oracle"] = 5
    costs.erase("n9_event_oracle")
    if Probe.sample(100, costs, parity, gate, gate).get("accepted", false):
        _fail("missing callsite admitted")
        return
    costs["n9_event_oracle"] = 7
    if Probe.sample(100, costs, {"accepted": false, "tick": 100},
            gate, gate).get("accepted", false):
        _fail("failed exact oracle admitted")
        return
    if Probe.sample(100, costs, parity, gate, {}).get("accepted", false):
        _fail("missing N9 source oracle admitted")
        return
    if Probe.sample(20, costs, {"accepted": true, "tick": 20},
            {}, {}).get("accepted", false):
        _fail("unexpected early size observation admitted")
        return
    var forged: Dictionary = good.duplicate(true)
    forged["costs"]["direct_checkpoint"] = -4
    if Probe.summarize([forged, later], [100, 300]).get("accepted", false):
        _fail("forged summary admitted")
        return
    forged = good.duplicate(true)
    forged["included_in_paid_tick_window"] = true
    if Probe.summarize([forged, later], [100, 300]).get("accepted", false):
        _fail("paid-tick contamination admitted")
        return
    if Probe.summarize([later, good], [100, 300]).get("accepted", false):
        _fail("reordered milestones admitted")
        return
    if Probe.compare_growth(later, good).get("accepted", false):
        _fail("reverse growth admitted")
        return
    # The report is scalar-detached from caller-owned input dictionaries.
    costs["direct_checkpoint"] = 999
    if good["costs"]["direct_checkpoint"] != 10:
        _fail("mutable alias")
        return
    print("P2_PERF_E_OBSERVATION_COST_ORACLE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_OBSERVATION_COST_ORACLE_FAIL " + reason)
    quit(1)
