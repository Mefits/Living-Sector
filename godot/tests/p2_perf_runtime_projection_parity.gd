extends SceneTree
## Owned N39 scalar/domain projections must match a complete immutable
## World snapshot, and mutating their output must not mutate N39 or N9.
const Native = preload("res://scripts/native_data.gd")
const Runner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var seed: Dictionary = Native.load_current_world()
    if seed.has("error"):
        _fail("original Rust seed unavailable")
        return
    var sim = Runner.new()
    if not sim.start_from_seed(seed):
        _fail("original N158 boot failed")
        return
    var world: Dictionary = sim.production.world_snapshot()
    var original: Dictionary = world.duplicate(true)
    if sim.production.native_has_ship_domain() != world.has("ships"):
        _fail("ship domain presence differs")
        return
    var identities: Dictionary = sim.production.native_ship_identity_snapshot()
    var expected: Dictionary = {}
    for sid in world["ships"]:
        expected[str(sid)] = {"ship_id": str(sid),
            "faction_id": str(world["ships"][sid].get("faction_id", ""))}
        if not sim.production.native_has_ship(str(sid)):
            _fail("valid native ship missing")
            return
    if identities != expected:
        _fail("native ship scalar projection differs")
        return
    if sim.production.native_has_ship("nonexistent-N148-ship"):
        _fail("N148 presence accepted imaginary ship")
        return
    for cid in world.get("contract_board", {}).get("contracts", {}):
        var c: Dictionary = world["contract_board"]["contracts"][cid]
        var scalar: Dictionary = sim.production.native_contract_kind(str(cid))
        if scalar != {"contract_type": str(c.get("contract_type", "")),
                "mission_category": str(c.get("mission_category", ""))}:
            _fail("source N104 contract kind mismatch")
            return
    if not sim.production.native_contract_kind("n104-nonexistent").is_empty():
        _fail("nonexistent contract should have no type")
        return
    if identities.size() > 0:
        var sid: String = str(identities.keys()[0])
        identities[sid]["faction_id"] = "forged-only-in-projection"
        identities["imaginary"] = {"ship_id": "imaginary",
            "faction_id": "forged"}
    var again: Dictionary = sim.production.world_snapshot()
    if again != original:
        _fail("mutable projection escaped N39 ownership")
        return
    print("P2_PERF_RUNTIME_OWNED_PROJECTIONS_PASS ships=" +
        str(expected.size()) + " world_unchanged=true")
    quit(0)

func _fail(message: String) -> void:
    push_error("P2_PERF_RUNTIME_OWNED_PROJECTIONS_FAIL: " + message)
    quit(1)
