extends SceneTree
const PROBE = preload("res://scripts/sim/phase2/n158_authoritative_size_probe.gd")

func _initialize() -> void:
    var world: Dictionary = {
        "ships": {"ship-a": {}, "ship-b": {}},
        "facilities": {
            "dock-a": {"dock_queue": ["ship-a", "ship-b"]},
            "dock-b": {"dock_queue": []},
            "factory": {}},
        "dock_receipts": {"paid-1": {}, "paid-2": {}},
        "cargo_receipts": {"cargo-1": {}},
        "contract_board": {"contracts": {"contract-1": {}}}}
    var sample: Dictionary = PROBE.measure(100, world)
    assert(sample["valid"])
    assert(sample["ships"] == 2)
    assert(sample["facilities"] == 3)
    assert(sample["dock_waiting"] == 2)
    assert(sample["contracts"] == 1)
    assert(sample["receipt_categories"]["dock_receipts"] == 2)
    assert(sample["receipt_categories"]["cargo_receipts"] == 1)
    assert(sample["missing"].has("n9_ledger_receipts"))
    assert(sample["missing"].has("source_events"))
    assert(PROBE.measure(101, world).is_empty())
    # No source dictionary is retained or modified by the detached probe.
    assert(world["facilities"]["dock-a"]["dock_queue"].size() == 2)
    world["facilities"]["dock-a"]["dock_queue"] = "invalid"
    assert(PROBE.measure(300, world)["reason"] == "invalid_dock_queue")
    world["facilities"]["dock-a"]["dock_queue"] = []
    world["dock_receipts"] = []
    assert(PROBE.measure(600, world)["reason"] == "invalid_dock_receipts")
    world.erase("ships")
    assert(PROBE.measure(900, world)["reason"] == "missing_authoritative_world_domain")
    print("P2_PERF_E_AUTHORITATIVE_SIZE_PROBE PASS")
    quit(0)
