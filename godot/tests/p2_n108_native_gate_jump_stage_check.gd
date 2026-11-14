extends RefCounted
## P2 Chat1 source N108 gate Apply contract checks.
## Authored for the FINAL Godot source integration verification; NOT
## run during the frozen Rust -> Godot migration.
const Jump = preload("res://scripts/sim/phase2/unified_n108_gate_jump_stage.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

class FrozenResolver:
    extends RefCounted

    func system_for_body(body_id: String) -> String:
        return {"earth": "sol", "eden": "alpha"}.get(body_id, "")

static func _test_world() -> Dictionary:
    var source: Dictionary = {
        "type": "gate", "faction": "human", "location": "gate-sol",
        "body_id": "earth", "credits": 100, "abandoned": false,
        "gate_link": {"paired_gate_id": "gate-b",
            "fee_flat": 200, "fee_per_cargo_unit": 2,
            "throughput_cap": 3},
        "position": {"x": 1.25, "y": 2.0}}
    var dest: Dictionary = {
        "type": "gate", "faction": "human", "location": "gate-alpha",
        "body_id": "eden", "credits": 50, "abandoned": false,
        "gate_link": {"paired_gate_id": "gate-a",
            "fee_flat": 200, "fee_per_cargo_unit": 2,
            "throughput_cap": 3},
        "position": {"x": 2.5, "y": -1.0}}
    var ship: Dictionary = {
        "id": "ship-1", "location": "gate-sol", "docked_at": "",
        "system_id": "sol", "transit": {}, "credits": 500,
        "cargo": {"ore": 4}, "memory": {
            "price_knowledge": {}, "visited": [],
            "recent_systems": [], "route_performance": {},
            "contract_rejections": {}}}
    return {"ships": {"ship-1": ship},
        "facilities": {"gate-a": source, "gate-b": dest},
        "bodies": {"earth": {"resources": {}},
            "eden": {"resources": {}}},
        "native_gate_jump_receipts": {}}

static func run_checks() -> Dictionary:
    var source: Dictionary = _test_world()
    var resolver := FrozenResolver.new()
    var bank := Ledger.new()
    if not bank.import_accounts({"ship:ship-1": 500,
            "facility:gate-a": 100,
            "facility:gate-b": 50}):
        return {"ok": false, "reason": "source_ledger_fixture"}
    var before: Dictionary = bank.snapshot()
    var result: Dictionary = Jump.stage(source, before, resolver,
        "ship-1", "gate-sol", "gate-alpha", 10)
    if not result.get("ok", false):
        return {"ok": false, "reason": "source_jump_stage_" +
            str(result.get("reason", "unknown"))}
    var world: Dictionary = result["world"]
    var ship: Dictionary = world["ships"]["ship-1"]
    var verified := Ledger.new()
    if not verified.restore(result["ledger_snapshot"]):
        return {"ok": false, "reason": "source_ledger_restore"}
    if int(result.get("fee", -1)) != 208 or ship.get(
            "position", null) != [2.5, -1.0] or str(ship.get(
            "location", "")) != "gate-alpha" or str(ship.get(
            "system_id", "")) != "alpha" or str(ship.get(
            "docked_at", "invalid")) != "":
        return {"ok": false, "reason": "real_gate_teleport_unverified"}
    if ship["memory"]["recent_systems"] != ["alpha"] or int(
            ship["credits"]) != 292 or int(world["facilities"][
            "gate-a"]["credits"]) != 308:
        return {"ok": false, "reason": "real_source_memory_or_fee"}
    if verified.total() != bank.total() or verified.balance(
            "ship:ship-1") != 292 or verified.balance(
            "facility:gate-a") != 308 or not verified.snapshot().get(
            "receipts", {}).has("n108:gate:ship-1:10"):
        return {"ok": false, "reason": "real_n9_money_receipt"}
    if world.get("native_gate_jump_receipts", {}).size() != 1 or (
            source["ships"]["ship-1"]["location"] != "gate-sol"):
        return {"ok": false, "reason": "missing_immutable_physical_receipt"}
    var repeat: Dictionary = Jump.stage(world, verified.snapshot(),
        resolver, "ship-1", "gate-alpha", "gate-sol", 10)
    if repeat.get("ok", false):
        return {"ok": false, "reason": "same_ship_same_tick_replayed"}
    var unpaired: Dictionary = source.duplicate(true)
    unpaired["facilities"]["gate-b"]["gate_link"] = {}
    if Jump.stage(unpaired, before, resolver, "ship-1",
            "gate-sol", "gate-alpha", 11).get("ok", false):
        return {"ok": false, "reason": "invented_gate_pair"}
    var insolvent: Dictionary = source.duplicate(true)
    insolvent["ships"]["ship-1"]["credits"] = 199
    if Jump.stage(insolvent, before, resolver, "ship-1",
            "gate-sol", "gate-alpha", 11).get("ok", false):
        return {"ok": false, "reason": "unfunded_gate_teleport"}
    var unknown_pos: Dictionary = source.duplicate(true)
    unknown_pos["facilities"]["gate-b"].erase("position")
    if Jump.stage(unknown_pos, before, resolver, "ship-1",
            "gate-sol", "gate-alpha", 11).get("ok", false):
        return {"ok": false, "reason": "invented_rust_facility_orbit"}
    var absent: Dictionary = source.duplicate(true)
    absent["facilities"] = {}
    if Jump.stage(absent, before, resolver, "ship-1",
            "gate-sol", "gate-alpha", 11).get("ok", false):
        return {"ok": false, "reason": "teleported_without_a_real_gate"}
    return {"ok": true, "status": "SOURCE_FIXTURE_NOT_EXECUTED"}
