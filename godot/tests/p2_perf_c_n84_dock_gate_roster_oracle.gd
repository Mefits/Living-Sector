extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_perf_c_n84_dock_gate_roster_oracle.gd
const N84 = preload("res://scripts/sim/phase2/unified_ship_ai_execution.gd")

func _initialize() -> void:
    var failures: Array = []
    _check_shipyards(failures)
    _check_gates(failures)
    if failures.is_empty():
        print("PASS p2_perf_c_n84_dock_gate_roster_oracle")
        quit(0)
    else:
        for failure in failures:
            push_error(str(failure))
        quit(1)

func _world() -> Dictionary:
    return {"ships": {"s": {"location": "_ready", "current_goal": "refit",
        "active_contract_id": "", "docked_at": "", "transit": {},
        "credits": 100, "crew": {"morale": 100.0}}},
        "facilities": {}, "markets": {}}

func _call(world: Dictionary, kind: String, scratch: Dictionary,
        yards: Dictionary = {}) -> Dictionary:
    return N84._dispatch({"kind": kind, "src_gate": "_ready",
        "dest_gate": "dest"}, {}, world, null, {}, "s", 1, 1.0,
        1, scratch, yards)

func _equal(actual: Variant, expected: Variant, label: String,
        failures: Array) -> void:
    if actual != expected:
        failures.append("%s expected=%s actual=%s" % [label, str(expected), str(actual)])

func _check_shipyards(failures: Array) -> void:
    var world: Dictionary = _world()
    var cached: Dictionary = {}
    var scratch: Dictionary = {}
    # "_ready" was the old control key: a real location must never collide.
    var empty: Dictionary = _call(world, "DockAtShipyard", scratch, cached)
    _equal(empty.get("reason"), "n108_no_built_shipyard_here",
        "empty yard", failures)
    world["facilities"]["yard"] = {"type": "shipyard",
        "location": "_ready", "abandoned": false}
    # A fresh proposal sees the new dock. A stale proposal must not
    # invent a dock; World is immutable during a normal proposal.
    var fresh: Dictionary = _call(world, "DockAtShipyard", {}, {})
    _equal(fresh.get("reason"), "n108_wait_real_n21_shipyard_dock",
        "fresh yard", failures)
    cached.clear()
    var present: Dictionary = _call(world, "DockAtShipyard", scratch, cached)
    _equal(present.get("reason"), fresh.get("reason"),
        "cached yard parity", failures)
    world["facilities"]["yard"]["abandoned"] = true
    var stale: Dictionary = _call(world, "DockAtShipyard", scratch, cached)
    var uncached: Dictionary = _call(world, "DockAtShipyard", {}, {})
    _equal(stale.get("reason"), uncached.get("reason"),
        "abandoned yard invalidation", failures)
    world["facilities"]["yard"]["abandoned"] = false
    world["facilities"]["yard"]["location"] = "elsewhere"
    stale = _call(world, "DockAtShipyard", scratch, cached)
    uncached = _call(world, "DockAtShipyard", {}, {})
    _equal(stale.get("reason"), uncached.get("reason"),
        "moved yard invalidation", failures)

func _check_gates(failures: Array) -> void:
    var world: Dictionary = _world()
    world["facilities"] = {
        "g1": {"type": "gate", "location": "_ready",
            "gate_link": {"paired_gate_id": "g2"}},
        "g2": {"type": "gate", "location": "dest",
            "gate_link": {"paired_gate_id": "g1"}}}
    var scratch: Dictionary = {}
    var baseline: Dictionary = _call(world, "GateJump", {}, {})
    var cached: Dictionary = _call(world, "GateJump", scratch, {})
    _equal(cached.get("reason"), baseline.get("reason"),
        "gate command parity", failures)
    _equal(cached.get("commands", []), baseline.get("commands", []),
        "gate command payload", failures)
    world["facilities"]["g1"]["type"] = "station"
    cached = _call(world, "GateJump", scratch, {})
    baseline = _call(world, "GateJump", {}, {})
    _equal(cached.get("reason"), baseline.get("reason"),
        "gate type invalidation", failures)
    world["facilities"]["g1"]["type"] = "gate"
    world["facilities"]["g1"]["location"] = "elsewhere"
    cached = _call(world, "GateJump", scratch, {})
    baseline = _call(world, "GateJump", {}, {})
    _equal(cached.get("reason"), baseline.get("reason"),
        "gate location invalidation", failures)
