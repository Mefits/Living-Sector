extends SceneTree
# N39 lifecycle off-cadence copy isolation and N130 no-write oracle.
# Run: godot --headless --path godot --script res://tests/p2_perf_a_n39_lifecycle_off_cadence_owned_stage.gd
const Restock = preload("res://scripts/sim/phase2/unified_service_restock_phase.gd")

func _initialize() -> void:
    var before: Dictionary = {
        "facilities": {"f": {"reserves": {"fuel": 12.0}, "credits": 100}},
        "markets": {"m": {"supply": {"fuel": 40.0}, "prices": {"fuel": 2}}},
        "populations": {"p": {"wealth": 40, "history": [1, 2]}},
        "ships": {"s": {"cargo": {"ore": 5}}}}
    var frozen: Dictionary = before.duplicate(true)
    var oracle: Dictionary = before.duplicate(true)
    var owned: Dictionary = before.duplicate(false)
    owned["facilities"] = before["facilities"].duplicate(true)
    # No repair candidates, no N130 restock on tick 1: both read-only.
    owned["facilities"]["f"]["reserves"]["fuel"] = 11.0
    oracle["facilities"]["f"]["reserves"]["fuel"] = 11.0
    assert(owned == oracle, "off-cadence owned stage differs from deep oracle")
    assert(before == frozen, "facility write leaked to authoritative World")
    var no_op: Dictionary = Restock.apply(owned, null, 1, 1)
    assert(no_op.get("ok", false) and not no_op.get("due", true),
        "N130 unexpectedly runs outside 20x cadence")
    assert(owned == oracle and before == frozen,
        "N130 off-cadence mutated read-only market or population")
    # Negative: writing a shared domain without detaching would corrupt World.
    var unsafe: Dictionary = frozen.duplicate(false)
    unsafe["markets"]["m"]["supply"]["fuel"] = 999.0
    assert(frozen["markets"]["m"]["supply"]["fuel"] == 999.0,
        "negative mutable alias fixture failed")
    assert(before["markets"]["m"]["supply"]["fuel"] == 40.0,
        "negative fixture unexpectedly modified authoritative source")
    # Paid/cadence stages MUST detach markets before any write.
    var paid: Dictionary = before.duplicate(false)
    paid["facilities"] = before["facilities"].duplicate(true)
    paid["markets"] = before["markets"].duplicate(true)
    paid["populations"] = before["populations"].duplicate(true)
    paid["markets"]["m"]["supply"]["fuel"] = 10.0
    paid["populations"]["p"]["history"].append(3)
    assert(before == frozen, "paid-stage detached domain leaked")
    quit(0)
