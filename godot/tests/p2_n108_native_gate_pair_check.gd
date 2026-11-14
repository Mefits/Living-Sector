extends RefCounted
## Deferred acceptance for ORIGINAL built GateLink -> N108 paid jump.
## Authored but NOT RUN during Rust -> Godot full migration.
const Pair = preload("res://scripts/sim/phase2/unified_n108_gate_pair_stage.gd")
const Gate = preload("res://scripts/sim/phase2/unified_n108_gate_jump_stage.gd")
const Orbit = preload("res://scripts/sim/phase2/unified_n108_native_facility_orbit.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

class FakeResolver:
    extends RefCounted
    func system_for_body(body: String) -> String:
        return str({"earth": "sol", "eden": "alpha"}.get(body, ""))

    func body_universe_position(body: String, _model: RefCounted) -> Dictionary:
        var center: Dictionary = {
            "earth": Vector2(1.0, 2.0), "eden": Vector2(5.0, -2.0)}
        if not center.has(body):
            return {"ok": false}
        return {"ok": true, "position": center[body]}

static func _original_gate(location: String, body: String,
        credits: int) -> Dictionary:
    return {"type": "gate", "faction": "human",
        "location": location, "body_id": body, "credits": credits,
        "abandoned": false, "docking_capacity": 4,
        "crew_count": 0, "position": {"x": 1.0, "y": 2.0}}

static func source_fixture() -> Dictionary:
    return {"facilities": {
            "facility-earth-gate-a": _original_gate("earth-station", "earth", 100),
            "facility-alpha-gate-b": _original_gate("alpha-station", "eden", 50)},
        "bodies": {"earth": {"resources": {}}, "eden": {"resources": {}}},
        "ships": {"ship-1": {"id": "ship-1", "location": "earth-station",
            "system_id": "sol", "transit": {}, "docked_at": "",
            "credits": 500, "cargo": {"ore": 4},
            "memory": {"price_knowledge": {}, "visited": [],
                "recent_systems": [], "route_performance": {},
                "contract_rejections": {}}}},
        "native_gate_jump_receipts": {},
        "native_gate_pair_receipts": {}}

static func run_checks() -> Dictionary:
    # JavaScript BigInt independent SipHash-1-3 (0,0) known
    # Rust std DefaultHasher::new() fixtures. GDScript runtime not
    # executed at authoring time; actual verification is deferred.
    if Orbit.facility_angle("hello") != 217 or Orbit.facility_angle(
            "facility-earth-gate-a") != 333 or Orbit.facility_angle(
            "facility-alpha-gate-b") != 11:
        return {"ok": false, "reason": "rust_default_hasher_orbit_mismatch"}
    var original: Dictionary = source_fixture()
    var resolver := FakeResolver.new()
    var built: Dictionary = Pair.stage(original, resolver,
        "facility-earth-gate-a", "facility-alpha-gate-b", 10)
    if not built.get("ok", false):
        return {"ok": false, "reason": "pair_" + str(built.get(
            "reason", "rejected"))}
    var world: Dictionary = built["world"]
    var a: Dictionary = world["facilities"]["facility-earth-gate-a"]
    var b: Dictionary = world["facilities"]["facility-alpha-gate-b"]
    if str(a["gate_link"]["paired_gate_id"]) != "facility-alpha-gate-b" or (
            str(b["gate_link"]["paired_gate_id"]) != "facility-earth-gate-a") or (
            int(a["gate_link"]["fee_flat"]) != 200 or
            int(b["gate_link"]["fee_per_cargo_unit"]) != 2):
        return {"ok": false, "reason": "wrong_source_gate_pair"}
    if original["facilities"]["facility-earth-gate-a"].has("gate_link"):
        return {"ok": false, "reason": "pair_mutated_original_world"}
    if Pair.stage(world, resolver, "facility-earth-gate-a",
            "facility-alpha-gate-b", 10).get("ok", false):
        return {"ok": false, "reason": "repeat_pair_was_accepted"}
    var bank := Ledger.new()
    if not bank.import_accounts({"ship:ship-1": 500,
            "facility:facility-earth-gate-a": 100,
            "facility:facility-alpha-gate-b": 50}):
        return {"ok": false, "reason": "source_wallet_fixture"}
    var before: Dictionary = bank.snapshot()
    var jump: Dictionary = Gate.stage(world, before, resolver,
        "ship-1", "earth-station", "alpha-station", 11, RefCounted.new())
    if not jump.get("ok", false):
        return {"ok": false, "reason": "jump_" + str(jump.get(
            "reason", "rejected"))}
    var moved: Dictionary = jump["world"]["ships"]["ship-1"]
    var destination: Array = Orbit.position(Vector2(5.0, -2.0),
        "facility-alpha-gate-b")
    if int(jump.get("fee", -1)) != 208 or moved.get(
            "position", []) != destination or str(moved.get(
            "location", "")) != "alpha-station" or str(moved.get(
            "system_id", "")) != "alpha" or moved.get(
            "memory", {}).get("recent_systems", []) != ["alpha"]:
        return {"ok": false, "reason": "real_pair_did_not_jump_to_rust_orbit"}
    var after := Ledger.new()
    if not after.restore(jump["ledger_snapshot"]) or after.total() != bank.total() or (
            after.balance("ship:ship-1") != 292 or after.balance(
            "facility:facility-earth-gate-a") != 308):
        return {"ok": false, "reason": "n9_paid_gate_fee_not_conserved"}
    var missing: Dictionary = original.duplicate(true)
    missing["facilities"].erase("facility-alpha-gate-b")
    if Pair.stage(missing, resolver, "facility-earth-gate-a",
            "facility-alpha-gate-b", 10).get("ok", false):
        return {"ok": false, "reason": "ghost_gate_allowed"}
    var same: Dictionary = original.duplicate(true)
    same["facilities"]["facility-alpha-gate-b"]["body_id"] = "earth"
    if Pair.stage(same, resolver, "facility-earth-gate-a",
            "facility-alpha-gate-b", 10).get("ok", false):
        return {"ok": false, "reason": "same_system_gate_pair_allowed"}
    return {"ok": true, "status": "DEFERRED_SOURCE_FIXTURE_NOT_RUN"}
