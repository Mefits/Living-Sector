extends SceneTree
## V3 single-timebase source regression. Deferred until final joined Godot
## acceptance; no N39, N9, N104 or second TickRunner is instantiated.
const Timeline = preload("res://scripts/sim/phase2/unified_native_timeline_integrity.gd")
const Saves = preload("res://scripts/sim/save_state.gd")
const Clock = preload("res://scripts/sim/clock.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")

class FixtureRunner extends RefCounted:
    var source: Dictionary = {}
    var tick_count: int = 0
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return source.duplicate(true)
    func restore_checkpoint(record: Dictionary, _seed: Dictionary) -> bool:
        source = record.duplicate(true)
        tick_count = int(record.get("tick", -1))
        return true

func _fail(reason: String) -> void:
    push_error("P2_V3_NATIVE_TIMELINE: " + reason)
    quit(1)

func _frame(tick: int) -> Dictionary:
    return {
        "format": "living-sector-godot", "schema_version": 1,
        "scenario": "galaxy-067", "seed_fingerprint": "v3-fixture-seed",
        "tick": tick, "clock": Clock.new().snapshot(),
        "calendar": Calendar.new().snapshot(),
        "cadence": {"bodies": {"period": 1, "offset": 0}},
        "events": {"next_sequence": 2,
            "pending": [{"id": "future-n1", "due_tick": tick + 4,
                "phase": 10, "entity_id": "ship-a", "sequence": 1,
                "kind": "observer_notice", "payload": {}}]},
        "orbital_angles": {}, "pending_controls": [],
        "native_production": {"version": 1, "tick": tick,
            "world": {
                "facilities": {"facility-a": {"credits": 123}},
                "populations": {"pop-a": {"wealth": 40}},
                "ships": {"ship-a": {"credits": 90,
                    "transit": {"departure_tick": 30,
                        "last_tick": 31, "arrival_tick": 50, "token": 1}}},
                "faction_treasuries": {"terran-authority": 5000},
                "escrow_balances": {"escrow-a": 400},
                "markets": {"earth-station": {
                    "supply": {"food": 12.25},
                    "history": {
                        "spawned_at_tick": 1, "last_tick": 32,
                        "trend_samples": [
                            {"tick": 16, "prices": {"food": 4.0},
                                "supply": {"food": 20.0}},
                            {"tick": 32, "prices": {"food": 3.0},
                                "supply": {"food": 12.25}}]},
                    "consumption_window": {"food": [
                        {"tick": 31, "qty": 2.0}]} }},
                "dock_receipts": {"dock-a": {
                    "operation_id": "dock-a", "tick": 10}},
                "cargo_receipts": {"cargo-a": {
                    "operation_id": "cargo-a", "tick": 20}},
                "native_gate_jump_receipts": {"gate-a": {
                    "operation_id": "gate-a", "tick": 31}}
            },
            "ledger": {"version": 1,
                "balances": {"facility/facility-a": 123,
                    "population/pop-a": 40, "ship:ship-a": 90,
                    "faction/terran-authority": 5000,
                    "escrow-a": 400},
                "receipts": {"advance": {"id": "advance", "tick": 16,
                    "kind": "contract_advance", "legs": [
                        {"account": "faction/terran-authority",
                            "delta": -400},
                        {"account": "escrow-a", "delta": 400}]}}}
        }
    }

func _changed(original: Dictionary, path: Array, value: Variant) -> Dictionary:
    var changed: Dictionary = original.duplicate(true)
    var cursor: Dictionary = changed
    for index in range(path.size() - 1):
        cursor = cursor[path[index]]
    cursor[path[path.size() - 1]] = value
    return changed

func _must_reject(valid: Dictionary, path: Array, value: Variant,
        token: String) -> bool:
    var altered: Dictionary = _changed(valid, path, value)
    var check: Dictionary = Timeline.validate(altered)
    if check.get("ok", false) or not str(check.get("reason", "")).contains(token):
        _fail("timestamp accepted: " + str(path) + ", result=" + str(check))
        return false
    return true

func _write_json(path: String, frame: Dictionary) -> bool:
    var absolute: String = ProjectSettings.globalize_path(path)
    if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
        return false
    var handle := FileAccess.open(absolute, FileAccess.WRITE)
    if handle == null:
        return false
    handle.store_string(JSON.stringify(Saves._wrap(frame), "", true, true) + "\n")
    handle.flush()
    var status: Error = handle.get_error()
    handle.close()
    return status == OK

func _initialize() -> void:
    var valid: Dictionary = _frame(32)
    var before: Dictionary = valid.duplicate(true)
    var report: Dictionary = Timeline.validate(valid)
    if not report.get("ok", false) or report.get("markets", -1) != 1 or (
            report.get("trend_samples", -1) != 2) or (
            report.get("physical_receipts", -1) != 3):
        _fail("source market and paid history baseline rejected: " + str(report))
        return
    # Future arrival 50 and pending scheduled event 36 are valid at tick 32.
    if not _must_reject(valid, ["native_production", "world",
            "markets", "earth-station", "history", "last_tick"], 33,
            "future_or_invalid"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "markets", "earth-station", "history", "spawned_at_tick"], 33,
            "spawned_at_tick"):
        return
    var reversed_trends: Array = valid["native_production"]["world"]["markets"][
        "earth-station"]["history"]["trend_samples"].duplicate(true)
    reversed_trends.reverse()
    if not _must_reject(valid, ["native_production", "world",
            "markets", "earth-station", "history", "trend_samples"],
            reversed_trends, "trend_not_chronological"):
        return
    var future_trends: Array = valid["native_production"]["world"]["markets"][
        "earth-station"]["history"]["trend_samples"].duplicate(true)
    future_trends.append({"tick": 48, "prices": {}, "supply": {}})
    if not _must_reject(valid, ["native_production", "world",
            "markets", "earth-station", "history", "trend_samples"],
            future_trends, "trend_in_future"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "markets", "earth-station", "consumption_window", "food"],
            [{"tick": 36, "qty": 2.0}], "future_or_invalid_consumption"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "cargo_receipts", "cargo-a", "tick"], 49,
            "future_physical_receipt"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "native_gate_jump_receipts", "gate-a", "tick"], 70,
            "future_physical_receipt"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "ships", "ship-a", "transit", "departure_tick"], 40,
            "future_or_invalid"):
        return
    if not _must_reject(valid, ["native_production", "world",
            "ships", "ship-a", "transit", "arrival_tick"], 20,
            "arrival_before_departure"):
        return
    var serialized: Variant = JSON.parse_string(JSON.stringify(valid))
    if not (serialized is Dictionary) or not Timeline.validate(
            serialized).get("ok", false):
        _fail("exact JSON decoded native history rejected")
        return
    if valid != before:
        _fail("read-only validation mutated source N39 World")
        return

    # Actual SaveState writes, backup selection and restore precedence
    # operate on the SAME N38 authoritative single-frame path.
    var runner := FixtureRunner.new()
    runner.source = valid.duplicate(true)
    runner.tick_count = 32
    var path: String = "user://tests/p2-v3-timeline-" + str(Time.get_ticks_usec()) + ".json"
    if Saves.save_runner(runner, path) != OK:
        _fail("healthy tick32 N38 frame not saved")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    var primary: String = FileAccess.get_file_as_string(absolute)
    if primary.is_empty():
        _fail("N38 primary not materialized")
        return
    runner.source = _changed(valid, ["native_production", "world",
        "markets", "earth-station", "history", "last_tick"], 100)
    if Saves.save_runner(runner, path) != ERR_INVALID_DATA:
        _fail("source time-travel market allowed to write N38 pending")
        return
    if FileAccess.get_file_as_string(absolute) != primary or (
            FileAccess.file_exists(absolute + ".bak")) or (
            FileAccess.file_exists(absolute + ".pending")):
        _fail("failed timeline preflight modified primary/backup/pending")
        return

    # Recovered older N38 backup must win over SHA-valid future market data.
    var backup_frame: Dictionary = valid.duplicate(true)
    backup_frame["native_production"]["world"]["markets"][
        "earth-station"]["history"]["last_tick"] = 32
    var bad_primary: Dictionary = _changed(valid, ["native_production",
        "world", "markets", "earth-station", "history", "last_tick"], 40)
    if not _write_json(path, bad_primary) or not _write_json(
            path + ".bak", backup_frame):
        _fail("unable to stage source timeline recovery fixture")
        return
    runner.source = valid.duplicate(true)
    runner.tick_count = 32
    var loaded: Dictionary = Saves.load_runner(runner, {}, path)
    if not loaded.get("ok", false) or not str(
            loaded.get("source", "")).ends_with(".bak") or (
            runner.tick_count != 32):
        _fail("N38 accepted future market primary instead of healthy backup: " +
            str(loaded))
        return
    for suffix in ["", ".bak", ".pending"]:
        if FileAccess.file_exists(absolute + suffix):
            DirAccess.remove_absolute(absolute + suffix)
    if not Timeline.validate({"tick": 9}).get("ok", false):
        _fail("legacy P1 snapshot with no N39 world must remain readable")
        return
    print("P2_V3_ONE_TIMELINE_N38_MARKET_RECEIPT_PASS")
    quit(0)
