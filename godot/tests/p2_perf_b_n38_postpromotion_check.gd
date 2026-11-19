extends SceneTree
## Astra III/B: installed N38 primary must pass authenticated verification
## before .bak.previous is discarded. Real v1 envelope; no fake money.
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

func _read(path: String) -> String:
    return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _clear(path: String) -> void:
    for suffix in ["", ".pending", ".bak", ".bak.previous",
            ".recovery-displaced", ".recovery-rejected"]:
        if FileAccess.file_exists(path + suffix):
            assert(DirAccess.remove_absolute(path + suffix) == OK)

func _initialize() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2-perf-b-n38-postpromotion-check.json")
    _clear(path)
    var valid: String = JSON.stringify(Saves._wrap(_frame()), "", true, true) + "\n"
    assert(Saves._trusted_for_backup_rotation(Saves._read_checkpoint(
        _make_fixture(path, valid))))
    # Positive: installed primary passes, old primary becomes backup,
    # parked old backup can be retired only after the second verification.
    _clear(path)
    _write(path, valid)
    _write(path + ".bak", "older-backup")
    _write(path + ".pending", valid)
    assert(Saves._promote_verified_pending(path, true, true) == OK)
    assert(_read(path) == valid and _read(path + ".bak") == valid)
    assert(not FileAccess.file_exists(path + ".bak.previous"))
    assert(not FileAccess.file_exists(path + ".pending"))
    # Negative: corrupted pending after an assumed preflight. The post-
    # promotion gate rejects it and restores BOTH previous checkpoints.
    _clear(path)
    _write(path, valid)
    _write(path + ".bak", "older-backup")
    _write(path + ".pending", "{corrupted")
    assert(Saves._promote_verified_pending(path, true, true) == ERR_FILE_CORRUPT)
    assert(_read(path) == valid)
    assert(_read(path + ".bak") == "older-backup")
    assert(_read(path + ".pending") == "{corrupted")
    assert(not FileAccess.file_exists(path + ".bak.previous"))
    # Negative: corrupt original primary must remain available as rejected
    # bytes until post-rename verification accepts the replacement.
    _clear(path)
    _write(path, "old-invalid-primary")
    _write(path + ".pending", "new-invalid-primary")
    assert(Saves._promote_verified_pending(path, false, true) == ERR_FILE_CORRUPT)
    assert(_read(path) == "old-invalid-primary")
    assert(_read(path + ".pending") == "new-invalid-primary")
    assert(not FileAccess.file_exists(path + ".recovery-rejected"))
    # Positive: actual save_runner callsite requests verification and writes
    # an authenticated, coherent checkpoint without changing N38 format.
    _clear(path)
    var runner := FakeRunner.new()
    runner.source = _frame()
    assert(Saves.save_runner(runner, path) == OK)
    assert(Saves._trusted_for_backup_rotation(Saves._read_checkpoint(path)))
    assert(not FileAccess.file_exists(path + ".pending"))
    _clear(path)
    print("PASS p2_perf_b_n38_postpromotion_check")
    quit(0)

func _make_fixture(path: String, value: String) -> String:
    _write(path + ".pending", value)
    return path + ".pending"
