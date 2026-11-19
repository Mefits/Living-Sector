extends SceneTree
## A-owned N91 no-op hotpath: no full World copy or Schema scan when
## source dispatch produces no assignments. No N9/World authority changes.
const Native = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")

func _initialize() -> void:
    var sim = Runtime.new()
    if not sim.start_from_seed(Native.load_current_world()):
        _fail("seed_start_failed")
        return
    var owner = sim.production
    var paid: Dictionary = owner.run_tick(1)
    if not paid.get("ok", false):
        _fail("first_paid_tick_failed:" + str(paid))
        return
    var before: Dictionary = owner.snapshot()
    if Schema.validate(before["world"]) != "":
        _fail("source_world_invalid")
        return
    var result: Dictionary = owner.apply_native_construction_assignments(1, [])
    if result != {"ok": true, "status": "N91_NATIVE_ENGINEERS_ASSIGNED",
            "tick": 1, "assigned": []}:
        _fail("empty_assignment_payload_changed:" + str(result))
        return
    if var_to_bytes(owner.snapshot()) != var_to_bytes(before):
        _fail("empty_assignment_mutated_world_or_ledger")
        return
    var invalid: Dictionary = owner.apply_native_construction_assignments(1,
        [{"site_id": "", "ship_id": ""}])
    if invalid.get("ok", true) or not invalid.get("fatal", false) or (
            invalid.get("reason", "") != "n91_duplicate_site_or_ship"):
        _fail("nonempty_invalid_proposal_bypassed_source_guard:" + str(invalid))
        return
    if var_to_bytes(owner.snapshot()) != var_to_bytes(before):
        _fail("rejected_proposal_mutated_world_or_ledger")
        return
    print("P2_PERF_A_N91_EMPTY_ASSIGNMENTS_HOTPATH_PASS")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PERF_A_N91_EMPTY_ASSIGNMENTS_HOTPATH_FAIL: " + message)
    quit(1)
