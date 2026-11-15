extends RefCounted
## Deferred original Rust N21 manual paid docket regression.
## Fixture intentionally runs in final shared Godot acceptance only.
const SourceN21 = preload("res://scripts/sim/phase2/unified_n21_dock_queue_stage.gd")
const Fixture = preload("res://tests/p2_n21_fifo_paid_source_check.gd")
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")

static func run_checks() -> Dictionary:
    # A manual user Dock never writes an extra queue, but it can
    # occupy a real free berth through the same source stage + N9 fee.
    var first: Dictionary = Fixture.fixture()
    var original: Dictionary = Fixture._ledger(first)
    var undocked: Dictionary = SourceN21.release(first, original,
        "ship-a", "dock", 30)
    if not undocked.get("ok", false):
        return {"ok": false, "reason": "n21_manual_fixture_release"}
    var manual: Dictionary = SourceN21.request(
        undocked["world"], original, "ship-b", "dock", 31)
    if not manual.get("ok", false) or str(manual.get(
            "status", "")) != "docked":
        return {"ok": false, "reason": "n21_manual_no_real_paid_berth"}
    var source_bank := Bank.new()
    if not source_bank.restore(manual["ledger_snapshot"]) or (
            source_bank.balance("ship:ship-b") != 950 or
            source_bank.balance("facility:station") != 150):
        return {"ok": false, "reason": "n21_manual_dock_not_paid_to_n9"}
    if manual["world"]["ships"]["ship-b"]["docked_at"] != "station":
        return {"ok": false, "reason": "n21_manual_payment_without_physical_dock"}
    if not manual["world"]["dock_receipts"].has("n21:dock:ship-b:31"):
        return {"ok": false, "reason": "n21_manual_missing_immutable_receipt"}
    var again: Dictionary = SourceN21.request(
        manual["world"], manual["ledger_snapshot"], "ship-b", "dock", 31)
    if again.get("ok", false):
        return {"ok": false, "reason": "n21_manual_replayed_same_tick"}
    var with_line: Dictionary = Fixture.fixture()
    var queued: Dictionary = SourceN21.request(with_line,
        Fixture._ledger(with_line), "ship-b", "dock", 40)
    if not queued.get("ok", false) or str(queued.get(
            "status", "")) != "queued":
        return {"ok": false, "reason": "n21_manual_missing_source_fifo"}
    var released: Dictionary = SourceN21.release(
        queued["world"], Fixture._ledger(with_line),
        "ship-a", "dock", 41)
    var queue_jump: Dictionary = SourceN21.request(
        released["world"], Fixture._ledger(with_line),
        "ship-c", "dock", 41)
    if not queue_jump.get("ok", false) or str(
            queue_jump.get("status", "")) != "queued" or (
            queue_jump["world"]["facilities"]["station"]["dock_queue"] != [
                "ship-b", "ship-c"]):
        return {"ok": false, "reason": "n21_manual_stepped_over_fifo_head"}
    # N39.apply_native_n21_manual_dock explicitly commits ONLY
    # status=docked, so this queued proposal is not published.
    if queue_jump["ledger_snapshot"] != Fixture._ledger(with_line):
        return {"ok": false, "reason": "n21_manual_fabricated_payment_on_queue"}
    return {"ok": true, "status": "SOURCE_ONLY_DEFERRED_NOT_RUN"}
