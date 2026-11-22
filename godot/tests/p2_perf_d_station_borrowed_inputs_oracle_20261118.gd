extends RefCounted
## Astra II-C: source/borrowed planning parity and no World mutable aliases.
## Execute via Godot 4.7.2 test harness; TEST_NOT_RUN until executed.
const Admin = preload("res://scripts/sim/strategy/station_administrator.gd")
const Station = preload("res://scripts/sim/phase2/unified_native_station_administration_phase.gd")

class LedgerStub:
    extends RefCounted
    func balance(_account: String) -> int:
        return 100000

static func _station_fixture() -> Dictionary:
    return {
        "faction_id": "alpha", "location": "earth",
        "population_count": 30, "workforce_limit": 18,
        "occupied_workers": 0, "market_owner": "facility/station",
        "stock": {"ore": 100.0, "water": 50.0, "food": 10.0},
        "prices": {"ore": 12.0, "water": 8.0, "food": 20.0},
        "limits": {"ore": 1000}, "shortages": {"food": 7},
        "head_priority": "ore",
        "facilities": [
            {"id": "rig-b", "type": "mining_rig", "crew": 4,
                "owner": "facility/station", "household": "",
                "abandoned": false, "paid_tick": -1,
                "actual_workers": 0, "efficiency": 1.0,
                "body_resources": {"ore": 0.8, "water": 0.2}},
            {"id": "rig-a", "type": "mining_rig", "crew": 3,
                "owner": "facility/station", "household": "",
                "abandoned": false, "paid_tick": -1,
                "actual_workers": 0, "efficiency": 1.0,
                "body_resources": {"ore": 0.9}}
        ]}

static func run() -> Dictionary:
    var ledger: RefCounted = LedgerStub.new()
    for tick in [5, 10, 15]:
        var source: Dictionary = _station_fixture()
        var original: Dictionary = source.duplicate(true)
        var old_owned: Dictionary = source.duplicate(true)
        old_owned["facilities"] = old_owned["facilities"].duplicate(true)
        var expected_planner = Admin.new()
        var actual_planner = Admin.new()
        var expected: Dictionary = expected_planner.plan(tick, old_owned, ledger, true)
        var actual: Dictionary = actual_planner.plan(tick, source, ledger, true)
        if expected != actual or not actual.get("ok", false):
            return {"ok": false, "reason": "deep_vs_borrowed_plan", "tick": tick}
        if source != original:
            return {"ok": false, "reason": "planner_mutated_source", "tick": tick}
        var snapshot: Dictionary = actual_planner.snapshot()
        if snapshot != expected_planner.snapshot():
            return {"ok": false, "reason": "snapshot_parity", "tick": tick}
        actual["modules"][0]["reason"] = "caller_changed"
        snapshot["last_plan"]["modules"][0]["reason"] = "snapshot_changed"
        if source != original:
            return {"ok": false, "reason": "returned_alias_into_input", "tick": tick}
        if actual_planner.snapshot() != expected_planner.snapshot():
            return {"ok": false, "reason": "snapshot_alias", "tick": tick}
    # Negative: corrupted source resource map must not be silently fixed by
    # the borrowed path; the planning path reads it without writing to it.
    var broken: Dictionary = _station_fixture()
    broken["facilities"][0]["body_resources"] = {"ore": 0.0}
    var before: Dictionary = broken.duplicate(true)
    var bad_plan: Dictionary = Admin.new().plan(20, broken, ledger, true)
    if not bad_plan.get("ok", false) or broken != before:
        return {"ok": false, "reason": "unextractable_source_mutation"}
    # Exercise the actual N18 adapter (no production or ledger write).
    var world: Dictionary = {
        "facilities": {"station": {"faction": "alpha", "location": "earth",
            "type": "station", "crew_count": 0},
            "rig-a": {"faction": "alpha", "location": "earth",
                "type": "mining_rig", "crew_count": 3, "body_id": "earth"},
            "rig-b": {"faction": "alpha", "location": "earth",
                "type": "mining_rig", "crew_count": 4, "body_id": "earth"}},
        "markets": {"earth": {"owner": "station",
            "supply": {"ore": 100.0}, "prices": {"ore": 12.0},
            "limits": {"ore": 1000},
            "history": {"shortage_ticks": {"ore": 1}}}},
        "populations": {}, "bodies": {"earth": {"resources": {"ore": 0.9}}},
        "station_administration": {}, "station_administration_last_tick": 0}
    var world_before: Dictionary = world.duplicate(true)
    var proposal: Dictionary = Station.propose(world, ledger, 5, 1)
    if not proposal.get("ok", false) or not proposal.get("due", false):
        return {"ok": false, "reason": "adapter_failed", "detail": proposal}
    if world != world_before:
        return {"ok": false, "reason": "adapter_mutated_world"}
    proposal["views"][0]["modules"][0]["reason"] = "external_change"
    if world != world_before:
        return {"ok": false, "reason": "adapter_return_alias"}
    return {"ok": true, "planner_cycles": 3, "adapter_cycles": 1}
