extends SceneTree
## N21 performance regression: one old-ledger snapshot must still reject
## lost/rewritten N9 receipts. Uses the unmodified original Galaxy seed,
## one authoritative N39/N9 and actual paid source ticks (no fake receipts).
## godot --headless --path godot --script res://tests/p2_n21_ledger_history_guard_check.gd
const NativeData = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native seed missing")
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("native runtime boot rejected: " + sim.boot_error())
        return
    if not sim.queue_control("pause") or not sim.queue_control("speed", 8.0):
        _fail("source time controls rejected")
        return
    sim.advance_frame(0.0)
    for tick in range(1, 4):
        if not sim.queue_control("step", 1):
            _fail("native step command rejected")
            return
        sim.advance_frame(0.0)
        if not sim.last_phase_failure().is_empty() or sim.tick_count != tick:
            _fail("native tick failed at " + str(tick) + ": " +
                str(sim.last_phase_failure()))
            return
    var original: Dictionary = sim.production.snapshot()
    var world: Dictionary = original.get("world", {})
    var money: Dictionary = original.get("ledger", {})
    var receipts: Dictionary = money.get("receipts", {})
    if world.is_empty() or receipts.is_empty():
        _fail("no real N9 history after native economy ticks")
        return
    var ids: Array = receipts.keys()
    ids.sort()
    var first_id: String = str(ids[0])
    var proposal: Dictionary = {"ok": true, "changed": false,
        "status": "unchanged", "world": world.duplicate(true),
        "ledger_snapshot": money.duplicate(true)}

    # A syntactically valid existing receipt may not be rewritten, even
    # if its financial legs and balance totals are unchanged.
    var edited: Dictionary = proposal.duplicate(true)
    edited["ledger_snapshot"]["receipts"][first_id]["kind"] = "rewritten_history"
    var rejected: Dictionary = sim.production._commit_native_n21(edited)
    if rejected.get("ok", true) or str(rejected.get("reason", "")) != (
            "n21_replayed_or_edited_n9_receipt"):
        _fail("N21 did not reject forged old N9 receipt: " + str(rejected))
        return
    if sim.production.snapshot() != original:
        _fail("rejecting rewritten N9 history mutated live World/ledger")
        return

    # A shortened receipt history must fail closed without changing N9.
    var deleted: Dictionary = proposal.duplicate(true)
    deleted["ledger_snapshot"]["receipts"].erase(first_id)
    rejected = sim.production._commit_native_n21(deleted)
    if rejected.get("ok", true) or str(rejected.get("reason", "")) != (
            "n21_paid_receipt_missing"):
        _fail("N21 did not reject missing old N9 receipt: " + str(rejected))
        return
    if sim.production.snapshot() != original:
        _fail("rejecting erased N9 history mutated live World/ledger")
        return

    # No-change N21 still accepts an exact canonical proposal; the
    # guarded history and every other authoritative field stay identical.
    var accepted: Dictionary = sim.production._commit_native_n21(proposal)
    if not accepted.get("ok", false) or sim.production.snapshot() != original:
        _fail("unchanged canonical N21 proposal diverged: " + str(accepted))
        return
    print("P2_N21_LEDGER_HISTORY_GUARD_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N21_LEDGER_HISTORY_GUARD_FAIL: " + reason)
    quit(1)
