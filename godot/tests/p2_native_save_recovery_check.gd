extends SceneTree
## V3/N38 regression: a self-consistent JSON digest is NOT proof that a
## checkpoint can be restored. Deferred: not run before final integration.
const Saves = preload("res://scripts/sim/save_state.gd")
const Coherence = preload("res://scripts/sim/phase2/unified_native_checkpoint_coherence.gd")

class FakeRunner extends RefCounted:
    var source: Dictionary = {}
    var tick_count: int = 0
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return source.duplicate(true)
    func restore_checkpoint(saved: Dictionary, _seed: Dictionary) -> bool:
        # A source-verified SHA may still fail the authoritative runner's
        # seed/clock/native restore checks. This fake models that outcome.
        if str(saved.get("restore_status", "")) == "reject":
            return false
        source = saved.duplicate(true)
        tick_count = int(saved.get("tick", 0))
        return true

func _fail(message: String) -> void:
    push_error("P2_N38_RECOVERY: " + message)
    quit(1)

func _frame(tick: int, status: String = "accept") -> Dictionary:
    return {
        "format": "living-sector-godot", "schema_version": 1,
        "scenario": "galaxy-067", "seed_fingerprint": "test-seed",
        "tick": tick, "restore_status": status,
        "clock": {"paused": false},
        "orbital_angles": {}, "pending_controls": [],
        "events": {"next_sequence": 1, "pending": []},
        "native_production": {"version": 1, "tick": tick,
            "world": {
                "facilities": {"facility-a": {"credits": 120}},
                "populations": {"population-a": {"wealth": 89}},
                "markets": {"earth-station": {"supply": {"food": 2.5}}},
                "ships": {"ship-a": {"credits": 51}},
                "faction_treasuries": {"terran-authority": 50000},
                "escrow_balances": {"escrow-a": 400},
                "passenger_manifests": {
                    "transport-1": {"wealth": 12}}},
            "ledger": {"version": 1,
                "balances": {"facility/facility-a": 120,
                    "population/population-a": 89, "ship:ship-a": 51,
                    "faction/terran-authority": 50000,
                    "escrow-a": 400, "passengers/transport-1": 12},
                "receipts": {"contract-a": {
                    "id": "contract-a", "kind": "contract_advance",
                    "tick": maxi(0, tick - 1), "legs": [
                        {"account": "faction/terran-authority", "delta": -400},
                        {"account": "escrow-a", "delta": 400}]}}}}
    }

func _write_envelope(path: String, frame: Dictionary) -> bool:
    var absolute: String = ProjectSettings.globalize_path(path)
    if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
        return false
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(Saves._wrap(frame), "", true, true) + "\n")
    file.flush()
    var error: Error = file.get_error()
    file.close()
    return error == OK

func _cleanup(path: String) -> void:
    var absolute: String = ProjectSettings.globalize_path(path)
    for suffix in ["", ".bak", ".pending"]:
        if FileAccess.file_exists(absolute + suffix):
            DirAccess.remove_absolute(absolute + suffix)

func _initialize() -> void:
    var path: String = "user://tests/p2-n38-recovery-" + str(Time.get_ticks_usec()) + ".json"
    var seed: Dictionary = {}
    var runner := FakeRunner.new()
    runner.source = _frame(12)
    runner.tick_count = 12
    var base_copy: Dictionary = runner.source.duplicate(true)
    if not Coherence.validate_serialized_candidate(runner.source).get("ok", false):
        _fail("native source was not coherent before serialization")
        return
    var serialized: Variant = JSON.parse_string(JSON.stringify(runner.source))
    if not (serialized is Dictionary) or not Coherence.validate_serialized_candidate(
            serialized).get("ok", false):
        _fail("valid JSON decoded native i64/receipt/clock incorrectly rejected")
        return
    if runner.source != base_copy:
        _fail("validating on-disk numerics mutated live World")
        return
    if Saves.save_runner(runner, path) != OK:
        _fail("first healthy primary could not be saved")
        return
    runner.source = _frame(13)
    runner.tick_count = 13
    if Saves.save_runner(runner, path) != OK:
        _fail("second primary save or original backup rotation failed")
        return
    var absolute: String = ProjectSettings.globalize_path(path)
    if int(Saves._read_checkpoint(path + ".bak").get("tick", -1)) != 12:
        _fail("healthy original primary was not rotated to backup")
        return
    var backup_before: String = FileAccess.get_file_as_string(absolute + ".bak")
    if backup_before.is_empty():
        _fail("backup missing after first valid rotation")
        return

    # Corruption is SELF-CONSISTENT with its SHA: old digest-only rotation
    # would overwrite the last healthy backup with this non-restorable World.
    var bad: Dictionary = _frame(13)
    bad["native_production"]["ledger"]["balances"]["ship:ship-a"] = 52
    if not _write_envelope(path, bad) or Saves._read_checkpoint(path).is_empty():
        _fail("test needs corrupt-but-SHA-valid primary")
        return
    if Saves._trusted_for_backup_rotation(Saves._read_checkpoint(path)):
        _fail("incoherent N9 primary would poison the last healthy backup")
        return
    runner.source = _frame(14)
    runner.tick_count = 14
    if Saves.save_runner(runner, path) != OK:
        _fail("new consistent checkpoint refused after invalid primary")
        return
    if FileAccess.get_file_as_string(absolute + ".bak") != backup_before:
        _fail("invalid primary overwrote the last healthy .bak")
        return
    if int(Saves._read_checkpoint(path).get("tick", -1)) != 14:
        _fail("healthy new primary was not promoted")
        return

    # Primary SHA-valid but semantically not restorable; backup also
    # unusable. Once the Runner REALLY restores .pending, it must promote
    # it even when the discarded primary's SHA is correct.
    var rejected_primary: Dictionary = _frame(15, "reject")
    var rejected_backup: Dictionary = _frame(14, "reject")
    var good_pending: Dictionary = _frame(16, "accept")
    if not _write_envelope(path, rejected_primary) or not _write_envelope(
            path + ".bak", rejected_backup) or not _write_envelope(
            path + ".pending", good_pending):
        _fail("failed to prepare valid-digest rejected primary and backup")
        return
    runner.source = _frame(10)
    runner.tick_count = 10
    var recovered: Dictionary = Saves.load_runner(runner, seed, path)
    if not recovered.get("ok", false) or not recovered.get(
            "recovered_pending", false) or not recovered.get(
            "promoted_pending", false):
        _fail("restored pending remained blocked by SHA-valid rejected primary: " +
            str(recovered))
        return
    if runner.tick_count != 16 or int(Saves._read_checkpoint(path).get(
            "tick", -1)) != 16 or FileAccess.file_exists(absolute + ".pending"):
        _fail("actual runner state and promoted pending disk frame diverged")
        return
    if str(Saves._read_checkpoint(path + ".bak").get(
            "restore_status", "")) != "reject":
        _fail("pending promotion illegally replaced old backup")
        return

    # A truly restorable primary always takes precedence over pending.
    if not _write_envelope(path, _frame(17, "accept")) or not _write_envelope(
            path + ".pending", _frame(18, "accept")):
        _fail("primary priority setup failed")
        return
    runner.source = _frame(10)
    runner.tick_count = 10
    recovered = Saves.load_runner(runner, seed, path)
    if not recovered.get("ok", false) or recovered.get(
            "recovered_pending", true) or runner.tick_count != 17 or not (
            FileAccess.file_exists(absolute + ".pending")):
        _fail("restorable primary was wrongly replaced with uncommitted pending")
        return

    # Fallback to valid backup must remain higher priority than pending.
    if not _write_envelope(path, _frame(19, "reject")) or not _write_envelope(
            path + ".bak", _frame(18, "accept")):
        _fail("backup priority setup failed")
        return
    runner.source = _frame(10)
    runner.tick_count = 10
    recovered = Saves.load_runner(runner, seed, path)
    if not recovered.get("ok", false) or runner.tick_count != 18 or recovered.get(
            "recovered_pending", true):
        _fail("recoverable backup was bypassed in favor of pending")
        return
    _cleanup(path)
    print("P2_N38_RECOVERY_BACKUP_PENDING_SOURCE_CHECK_PASS")
    quit(0)
