extends RefCounted
## Deferred SOURCE N21 paid FIFO / N38 state fixture. NOT RUN until
## complete Rust -> Godot source integration and single acceptance pass.
const N21 = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const BT = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")
const N9 = preload("res://scripts/sim/economy/credit_ledger.gd")

static func _ship(id: String, cash: int, dock: String,
        start: Variant = null) -> Dictionary:
    return {"id": id, "location": "dock", "docked_at": dock,
        "transit": {}, "credits": cash,
        "dock_attempt_start_tick": start,
        "current_bt": BT.sequence([BT.action({"kind": "Dock"})])}

static func fixture(broke_b: bool = false) -> Dictionary:
    return {"facilities": {"station": {
        "type": "station", "location": "dock", "faction": "faction",
        "docking_capacity": 1, "condition": 1.0, "credits": 100,
        "dock_queue": [], "abandoned": false, "dirty": false}},
        "ships": {"ship-a": _ship("ship-a", 1000, "station"),
            "ship-b": _ship("ship-b", 0 if broke_b else 1000, ""),
            "ship-c": _ship("ship-c", 1000, "")},
        "dock_receipts": {}, "cargo_receipts": {},
        "faction_relations": {}}

static func _ledger(world: Dictionary) -> Dictionary:
    var bank := N9.new()
    if not bank.import_accounts({"ship:ship-a": int(world["ships"]["ship-a"]["credits"]),
            "ship:ship-b": int(world["ships"]["ship-b"]["credits"]),
            "ship:ship-c": int(world["ships"]["ship-c"]["credits"]),
            "facility:station": int(world["facilities"]["station"]["credits"])}):
        return {}
    return bank.snapshot()

static func run_checks() -> Dictionary:
    var original: Dictionary = fixture()
    var bank: Dictionary = _ledger(original)
    if bank.is_empty():
        return {"ok": false, "reason": "source_n9_fixture_missing"}
    var b: Dictionary = N21.request(original, bank, "ship-b", "dock", 10,
        "station")
    if not b.get("ok", false) or str(b.get("status", "")) != "queued":
        return {"ok": false, "reason": "source_b_did_not_queue"}
    var c: Dictionary = N21.request(b["world"], bank, "ship-c", "dock", 11,
        "station")
    if not c.get("ok", false) or str(c.get("status", "")) != "queued":
        return {"ok": false, "reason": "source_c_did_not_queue"}
    if c["world"]["facilities"]["station"]["dock_queue"] != [
            "ship-b", "ship-c"] or original["facilities"]["station"]["dock_queue"] != []:
        return {"ok": false, "reason": "not_original_fifo_or_mutated_live"}
    var undocked: Dictionary = N21.release(c["world"], bank,
        "ship-a", "dock", 12)
    if not undocked.get("ok", false) or str(
            undocked["world"]["ships"]["ship-a"]["docked_at"]) != "":
        return {"ok": false, "reason": "source_n21_release_failed"}
    var first: Dictionary = N21.advance(undocked["world"], bank, 12)
    if not first.get("ok", false) or first["world"]["facilities"][
            "station"]["dock_queue"] != ["ship-c"]:
        return {"ok": false, "reason": "queue_did_not_admit_oldest_head"}
    if str(first["world"]["ships"]["ship-b"]["docked_at"]) != "station" or (
            str(first["world"]["ships"]["ship-c"]["docked_at"]) != ""):
        return {"ok": false, "reason": "queue_overtook_oldest_ship"}
    var fee: int = int(first["world"]["ships"]["ship-b"]["credits"])
    if fee != 950 or int(first["world"]["facilities"]["station"][
            "credits"]) != 150:
        return {"ok": false, "reason": "source_dock_fee_did_not_move_exact_cash"}
    var paid := N9.new()
    var initial := N9.new()
    if not initial.restore(bank) or not paid.restore(first["ledger_snapshot"]) or (
            initial.total() != paid.total() or
            paid.balance("ship:ship-b") != 950 or
            paid.balance("facility:station") != 150):
        return {"ok": false, "reason": "n9_single_paid_dock_not_conservative"}
    var again: Dictionary = N21.advance(
        first["world"], first["ledger_snapshot"], 12)
    if not again.get("ok", false) or bool(again.get("changed", false)) or (
            again["ledger_snapshot"] != first["ledger_snapshot"]):
        return {"ok": false, "reason": "duplicate_fee_on_source_retry"}
    var restored: Variant = JSON.parse_string(JSON.stringify(first["world"]))
    if not (restored is Dictionary) or (
            restored.get("facilities", {}).get(
            "station", {}).get("dock_queue", []) != ["ship-c"]):
        return {"ok": false, "reason": "fifo_not_persisted_by_native_n38_json"}
    var broke: Dictionary = fixture(true)
    var broke_bank: Dictionary = _ledger(broke)
    var qb: Dictionary = N21.request(
        broke, broke_bank, "ship-b", "dock", 20, "station")
    var qc: Dictionary = N21.request(
        qb["world"], broke_bank, "ship-c", "dock", 21, "station")
    var unlocked: Dictionary = N21.release(
        qc["world"], broke_bank, "ship-a", "dock", 22)
    var broke_out: Dictionary = N21.advance(
        unlocked["world"], broke_bank, 22)
    if not broke_out.get("ok", false) or str(
            broke_out["world"]["ships"]["ship-c"]["docked_at"]) != "station" or (
            broke_out["world"]["facilities"]["station"]["dock_queue"] != []):
        return {"ok": false, "reason": "unfunded_head_blocked_paid_second"}
    var stale: Dictionary = fixture()
    var stale_bank: Dictionary = _ledger(stale)
    var sqb: Dictionary = N21.request(stale, stale_bank, "ship-b",
        "dock", 30, "station")
    var sqc: Dictionary = N21.request(sqb["world"], stale_bank,
        "ship-c", "dock", 31, "station")
    var departed: Dictionary = sqc["world"].duplicate(true)
    departed["ships"]["ship-b"]["location"] = ""
    departed["ships"]["ship-b"]["transit"] = {"token": 55}
    var departed_release: Dictionary = N21.release(
        departed, stale_bank, "ship-a", "dock", 32)
    var pruned: Dictionary = N21.advance(
        departed_release["world"], stale_bank, 32)
    if not pruned.get("ok", false) or str(
            pruned["world"]["ships"]["ship-c"]["docked_at"]) != "station":
        return {"ok": false, "reason": "stale_ship_wedged_original_queue"}
    return {"ok": true, "status": "SOURCE_FIXTURE_DEFERRED_GODOT_NOT_RUN"}
