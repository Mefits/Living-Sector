extends SceneTree
# N39 L196 row-level lifecycle stage oracle. The production path uses this
# ownership pattern for N156 off-cadence and deep domain copy for due N130.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n39_l196_lifecycle_rows.gd

func _stage(source: Dictionary, due: bool, repairs: Array, changes: Dictionary) -> Dictionary:
    var staged: Dictionary = source.duplicate(false)
    var owned: Dictionary = {}
    staged["facilities"] = source["facilities"].duplicate(true) if due else source["facilities"].duplicate(false)
    if due:
        staged["markets"] = source["markets"].duplicate(true)
    if not repairs.is_empty():
        staged["populations"] = source["populations"].duplicate(true)
    if not due:
        for fid in repairs:
            if staged["facilities"].has(fid) and not owned.has(fid):
                staged["facilities"][fid] = source["facilities"][fid].duplicate(true)
                owned[fid] = true
    for fid in repairs:
        # Payroll success and Payroll._blocked both mutate the candidate row.
        staged["facilities"][fid]["work_shift"] = {"tick": 7, "workers": {"p": 2}}
        staged["facilities"][fid]["credits"] -= 2
        staged["populations"]["p"]["wealth"] += 2
    for fid in changes:
        if not due and not owned.has(fid):
            staged["facilities"][fid] = source["facilities"][fid].duplicate(true)
            owned[fid] = true
        staged["facilities"][fid]["condition"] = changes[fid]
        staged["facilities"][fid]["reserves"]["tools"] -= 1
    if due:
        staged["facilities"]["seller"]["credits"] += 4
        staged["facilities"]["buyer"]["reserves"]["fuel"] += 2
        staged["markets"]["m"]["supply"]["fuel"] -= 2
    return staged

func _initialize() -> void:
    var original: Dictionary = {
        "facilities": {
            "buyer": {"credits": 20, "condition": 0.5, "reserves": {"tools": 5, "fuel": 0}},
            "seller": {"credits": 50, "condition": 1.0, "reserves": {"tools": 8, "fuel": 10}},
            "idle": {"credits": 30, "condition": 0.8, "reserves": {"tools": 2, "fuel": 1}}},
        "markets": {"m": {"supply": {"fuel": 20}}},
        "populations": {"p": {"wealth": 10}},
        "ships": {"s": {"cargo": {"fuel": 4}}},
        "contract_board": {"contracts": {"c": {"state": "paid"}}}}
    var frozen: Dictionary = original.duplicate(true)
    # Paid repair + condition delta for a DIFFERENT row: both must detach.
    var stage: Dictionary = _stage(original, false, ["buyer"], {"idle": 0.7})
    var oracle: Dictionary = _stage(original.duplicate(true), false, ["buyer"], {"idle": 0.7})
    assert(stage == oracle, "N156 row-owned stage diverges from full World oracle")
    assert(original == frozen, "N156 stage changed canonical World before commit")
    stage["facilities"]["buyer"]["work_shift"]["workers"]["p"] = 99
    stage["facilities"]["idle"]["reserves"]["tools"] = 0
    assert(original == frozen, "N156 nested row aliases authoritative World")
    # Negative: rejected paid shift still sets work_blocked_reason; row isolation
    # must protect source even when the ledger transaction is rejected.
    var rejected: Dictionary = _stage(original, false, [], {"buyer": 0.4})
    rejected["facilities"]["buyer"]["work_blocked_reason"] = "insufficient_workers"
    assert(original == frozen, "rejected stage leaked blocked reason")
    # Due N130 touches buyers, sellers and markets; deep domain detachment
    # remains mandatory because its source callsite writes arbitrary rows.
    var due: Dictionary = _stage(original, true, [], {"idle": 0.6})
    var due_oracle: Dictionary = _stage(original.duplicate(true), true, [], {"idle": 0.6})
    assert(due == due_oracle, "N130 paid-restock stage differs from oracle")
    assert(original == frozen, "N130 due stage leaked money/stock into World")
    due["markets"]["m"]["supply"]["fuel"] = 0
    due["facilities"]["seller"]["reserves"]["fuel"] = 0
    assert(original == frozen, "N130 nested market/seller alias")
    # Demonstrate the exact unsafe shallow-row failure the production code avoids.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["facilities"] = frozen["facilities"].duplicate(false)
    unsafe["facilities"]["buyer"]["reserves"]["fuel"] = 777
    assert(frozen["facilities"]["buyer"]["reserves"]["fuel"] == 777,
        "negative alias fixture failed to reproduce corruption")
    assert(original["facilities"]["buyer"]["reserves"]["fuel"] == 0)
    quit(0)
