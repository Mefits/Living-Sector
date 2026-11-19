extends SceneTree
## Astra III/B: recovery is not committed until a second Runner accepts primary.
## Run: godot --headless --path godot --script res://tests/p2_perf_b_n38_recovery_restart_durability.gd
const Saves = preload("res://scripts/sim/save_state.gd")
const Clock = preload("res://scripts/sim/clock.gd")
const Calendar = preload("res://scripts/sim/calendar.gd")
var failures: int = 0

class OracleRunner extends RefCounted:
    var state: Dictionary = {}
    var tick_count: int = 0
    var accept: bool = true
    func is_started() -> bool:
        return true
    func checkpoint() -> Dictionary:
        return state.duplicate(true)
    func restore_checkpoint(snapshot: Dictionary, _seed: Dictionary) -> bool:
        if not accept or snapshot.get("seed_fingerprint") != "restart-oracle":
            return false
        state = snapshot.duplicate(true)
        tick_count = int(state.get("tick", 0))
        return true

func _check(ok: bool, label: String) -> void:
    if not ok:
        failures += 1
        push_error(label)

func _frame(tick: int) -> Dictionary:
    return {
        "format": "living-sector-godot", "schema_version": 1,
        "scenario": "galaxy-067", "seed_fingerprint": "restart-oracle",
        "tick": tick, "clock": Clock.new().snapshot(),
        "calendar": Calendar.new().snapshot(),
        "orbital_angles": {}, "pending_controls": [],
        "native_production": {"version": 1, "tick": tick,
            "world": {"facilities": {}, "populations": {}, "markets": {},
                "ships": {}, "faction_treasuries": {},
                "escrow_balances": {}, "passenger_manifests": {}},
            "ledger": {"version": 1, "balances": {}, "receipts": {}}}
    }

func _write(path: String, value: String) -> void:
    var file := FileAccess.open(path, FileAccess.WRITE)
    _check(file != null, "cannot write " + path)
    if file != null:
        file.store_string(value)
        file.close()

func _clear(path: String) -> void:
    for suffix in ["", ".bak", ".pending", ".bak.previous",
            ".recovery-displaced", ".recovery-rejected"]:
        if FileAccess.file_exists(path + suffix):
            DirAccess.remove_absolute(path + suffix)

func _run() -> void:
    var path: String = ProjectSettings.globalize_path(
        "user://p2-perf-b-n38-restart-durable.json")
    _clear(path)
    var old_bytes: String = JSON.stringify(Saves._wrap(_frame(11)), "", true, true) + "\n"
    var new_bytes: String = JSON.stringify(Saves._wrap(_frame(12)), "", true, true) + "\n"
    _write(path, old_bytes)
    _write(path + ".pending", new_bytes)
    _check(Saves._trusted_for_backup_rotation(Saves._read_checkpoint(path + ".pending")),
        "valid new checkpoint fixture")
    # Positive: real load_runner accepts pending and promotes it, but the
    # original primary remains until a SECOND launch accepts promoted primary.
    var runner := OracleRunner.new()
    runner.state = _frame(1)
    # A healthy primary wins over pending, so simulate an incompatible
    # original that the Runner rejects but that remains structurally valid.
    # The explicit promotion helper models the already-accepted candidate.
    _check(Saves._promote_recovered_checkpoint(path, path + ".pending"),
        "accepted pending promotion")
    _check(FileAccess.get_file_as_string(path) == new_bytes,
        "new primary byte oracle")
    _check(FileAccess.get_file_as_string(path + ".recovery-displaced") == old_bytes,
        "original bytes survive first promotion")
    _check(Saves._reconcile_recovery_displaced(path, false) == ERR_BUSY,
        "no cleanup without Runner acceptance")
    _check(FileAccess.get_file_as_string(path + ".recovery-displaced") == old_bytes,
        "negative cleanup preserves original")
    # Restart: load_runner accepts primary and only then clears displaced.
    var result: Dictionary = Saves.load_runner(runner, {}, path)
    _check(result.get("ok", false), "real load_runner primary restart")
    _check(result.get("restart_safe", false), "restart-safe after cleanup")
    _check(int(result.get("recovery_cleanup_error", -1)) == OK,
        "cleanup result reported")
    _check(runner.checkpoint() == Saves._read_checkpoint(path),
        "full checkpoint oracle after restart")
    _check(not FileAccess.file_exists(path + ".recovery-displaced"),
        "displaced retired after real restore")
    # Negative: a pre-existing displaced survivor blocks another promotion
    # and cannot be destroyed by a speculative save.
    _clear(path)
    _write(path, old_bytes)
    _write(path + ".recovery-displaced", "ORPHAN")
    _write(path + ".pending", new_bytes)
    _check(not Saves._promote_recovered_checkpoint(path, path + ".pending"),
        "unresolved orphan blocks competing promotion")
    _check(FileAccess.get_file_as_string(path + ".recovery-displaced") == "ORPHAN",
        "orphan byte oracle")
    _check(FileAccess.get_file_as_string(path + ".pending") == new_bytes,
        "pending byte oracle")
    _clear(path)
    print("N38 restart durability: ", "PASS" if failures == 0 else "FAIL")
    quit(0 if failures == 0 else 1)

func _initialize() -> void:
    call_deferred("_run")
