extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_perf_b_n38_pending_survivor.gd
## Real N38 envelope + native coherence fixture; no fabricated money movements.
const Saves = preload("res://scripts/sim/save_state.gd")
const Clock = preload("res://scripts/sim/clock.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")

class FakeRunner extends RefCounted:
    var source: Dictionary = {}
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return source.duplicate(true)

func _frame() -> Dictionary:
    return {
        "format": "living-sector-godot", "schema_version": 1,
        "scenario": "galaxy-067", "seed_fingerprint": "pending-survivor-seed",
        "tick": 12, "clock": Clock.new().snapshot(),
        "calendar": Calendar.new().snapshot(),
        "cadence": {"bodies": {"period": 1, "offset": 0}},
        "orbital_angles": {}, "pending_controls": [],
        "events": {"next_sequence": 1, "pending": []},
        "native_production": {"version": 1, "tick": 12,
            "world": {
                "facilities": {"facility-a": {"credits": 120}},
                "populations": {"population-a": {"wealth": 89}},
                "markets": {"earth-station": {"supply": {"food": 2.5}}},
                "ships": {"ship-a": {"credits": 51}},
                "faction_treasuries": {"terran-authority": 50000},
                "escrow_balances": {"escrow-a": 400},
                "passenger_manifests": {"transport-1": {"wealth": 12}}},
            "ledger": {"version": 1,
                "balances": {"facility/facility-a": 120,
                    "population/population-a": 89, "ship:ship-a": 51,
                    "faction/terran-authority": 50000,
                    "escrow-a": 400, "passengers/transport-1": 12},
                "receipts": {"contract-a": {
                    "id": "contract-a", "kind": "contract_advance",
                    "tick": 11, "legs": [
                        {"account": "faction/terran-authority", "delta": -400},
                        {"account": "escrow-a", "delta": 400}]}}}}
    }

func _write(path: String, value: String) -> void:
    var f := FileAccess.open(path, FileAccess.WRITE)
    assert(f != null)
    f.store_string(value)
    f.close()

func _clean(path: String) -> void:
    for suffix in ["", ".pending", ".bak", ".bak.previous",
            ".recovery-displaced", ".recovery-rejected"]:
        if FileAccess.file_exists(path + suffix):
            assert(DirAccess.remove_absolute(path + suffix) == OK)

func _initialize() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2-perf-b-n38-pending-survivor.json")
    _clean(path)
    var pending: String = path + ".pending"
    var envelope: String = JSON.stringify(Saves._wrap(_frame()), "", true, true) + "\n"
    _write(pending, envelope)
    assert(Saves._trusted_for_backup_rotation(Saves._read_checkpoint(pending)))
    assert(Saves._pending_is_only_recoverable_checkpoint(path))
    # A malformed primary cannot authorize truncating the last good pending.
    _write(path, "{corrupt")
    assert(Saves._pending_is_only_recoverable_checkpoint(path))
    assert(FileAccess.get_file_as_string(pending) == envelope)
    # The production save entry point must refuse to truncate the pending
    # survivor, even when a new coherent live snapshot is available.
    var runner := FakeRunner.new()
    runner.source = _frame()
    assert(Saves.save_runner(runner, path) == ERR_BUSY)
    assert(FileAccess.get_file_as_string(pending) == envelope)
    assert(FileAccess.get_file_as_string(path) == "{corrupt")
    # A separately verified backup authorizes a subsequent pending rewrite.
    _write(path + ".bak", envelope)
    assert(not Saves._pending_is_only_recoverable_checkpoint(path))
    assert(FileAccess.get_file_as_string(pending) == envelope)
    # An invalid backup is not sufficient.
    _write(path + ".bak", "{corrupt")
    assert(Saves._pending_is_only_recoverable_checkpoint(path))
    # An independent primary is also sufficient.
    _write(path, envelope)
    assert(not Saves._pending_is_only_recoverable_checkpoint(path))
    # A corrupted pending is not considered recoverable.
    _write(pending, "{corrupt")
    assert(not Saves._pending_is_only_recoverable_checkpoint(path))
    _clean(path)
    assert(not Saves._pending_is_only_recoverable_checkpoint(path))
    print("PASS p2_perf_b_n38_pending_survivor")
    quit(0)
