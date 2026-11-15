extends RefCounted
## N157 Frozen Rust:
## sim_server/engine/persist.rs::emit_persist_writes
## sim_db/persistence.rs::{buffer_write,flush_buffer,run}
## No persistent IO and no second economic ledger; Phase2 uses SaveState.
const Contract = preload("res://scripts/sim/phase1/n157_native_db_write_contract.gd")
const Transaction = preload("res://scripts/sim/phase1/n157_native_persist_transaction.gd")

var _capacity: int = 1
var _admitted: Array = []
var _buffer: Dictionary = {}
var _last_admitted_tick: int = -1
var _database: Dictionary = {}

func initialize(seed_database: Dictionary, queue_capacity: int = 1) -> bool:
    if queue_capacity < 1 or queue_capacity > 65536:
        return false
    if not Transaction.valid_database(seed_database):
        return false
    if not _database.is_empty():
        return false
    _database = seed_database.duplicate(true)
    _capacity = queue_capacity
    _last_admitted_tick = int(
        _database["simulation_state"].get("tick_counter", {}).get("current_tick", -1))
    return true

## Important: caller retains dirty flags and pending lifecycle events on
## rejection. Do not mark anything clean unless "accepted" is true.
func try_admit_frame(tick: int, writes: Array,
        dirty_identity_keys: Array = []) -> Dictionary:
    if _database.is_empty():
        return {"accepted": false, "reason": "not_initialized"}
    if tick <= _last_admitted_tick or tick < 0:
        return {"accepted": false, "reason": "stale_tick"}
    if _admitted.size() >= _capacity:
        return {"accepted": false, "reason": "channel_backpressure"}
    var seen_keys: Dictionary = {}
    var ticker: int = 0
    var boards: int = 0
    for write in writes:
        var error: String = Contract.validate_write(write)
        if not error.is_empty():
            return {"accepted": false, "reason": error}
        var key: String = Contract.dedup_key(write)
        if key.is_empty():
            return {"accepted": false, "reason": "missing_dedup_key"}
        if seen_keys.has(key):
            return {"accepted": false, "reason": "duplicate_write_in_frame"}
        seen_keys[key] = true
        if write["kind"] == "tick":
            ticker += 1
            if int(write["data"]["current_tick"]) != tick:
                return {"accepted": false, "reason": "frame_tick_mismatch"}
        if write["kind"] == "contract_board":
            boards += 1
    if ticker != 1 or boards != 1:
        return {"accepted": false, "reason": "partial_economic_frame"}
    var dirtied: Dictionary = {}
    for key in dirty_identity_keys:
        if not (key is String) or key.is_empty() or dirtied.has(key):
            return {"accepted": false, "reason": "invalid_dirty_identity"}
        dirtied[key] = true
    # Rust reserves a channel slot BEFORE clearing component dirty flags.
    _admitted.append({"tick": tick, "writes": writes.duplicate(true)})
    _last_admitted_tick = tick
    return {"accepted": true, "tick": tick,
        "accepted_dirty_keys": dirty_identity_keys.duplicate(true)}

## Rust worker synchronously flattens EVERY EconomicFrame before a sweep.
## Same typed key from later frames overrides older data without discarding
## different fields (e.g. the payer debit absent from a newer frame).
func drain_admitted() -> int:
    var consumed: int = _admitted.size()
    for frame in _admitted:
        for write in frame["writes"]:
            _buffer[Contract.dedup_key(write)] = write.duplicate(true)
    _admitted.clear()
    return consumed

func pending_count() -> int:
    return _admitted.size()

func buffered_count() -> int:
    return _buffer.size()

func current_database() -> Dictionary:
    return _database.duplicate(true)

func flush(inject_failure: bool = false) -> Dictionary:
    if _database.is_empty():
        return {"ok": false, "reason": "not_initialized"}
    if not _admitted.is_empty():
        return {"ok": false, "reason": "pending_channel_not_drained"}
    if _buffer.is_empty():
        return {"ok": true, "writes": 0}
    var records: Array = _buffer.values()
    var outcome: Dictionary = Transaction.transact(
        _database, records, inject_failure)
    if not outcome.get("ok", false):
        # Transaction failed, original DB and entire dedup buffer remain.
        return outcome
    _database = outcome["state"]
    _buffer.clear()
    return {"ok": true, "writes": int(outcome["writes"]),
        "tick": int(_database["simulation_state"].get("tick_counter", {}).get("current_tick", -1))}

## Source on-demand save-as barrier: drain exactly the frames known at
## request boundary, then flush. Acknowledgement only after COMMIT succeeds.
## Actual FileAccess backup/rename belongs to existing SaveState (N32/N38).
func checkpoint_barrier(inject_failure: bool = false) -> Dictionary:
    drain_admitted()
    var result: Dictionary = flush(inject_failure)
    if not result.get("ok", false):
        return {"acknowledged": false, "reason": result.get("reason", "flush_failed")}
    return {"acknowledged": true, "tick": result.get("tick", -1)}

func source_snapshot() -> Dictionary:
    return {"version": 1, "last_admitted_tick": _last_admitted_tick,
        "capacity": _capacity, "database": _database.duplicate(true),
        "queued_frames": _admitted.duplicate(true),
        "dedup_buffer": _buffer.duplicate(true)}

func restore_source_snapshot(data: Dictionary) -> bool:
    if data.get("version") != 1 or not (data.get("database") is Dictionary):
        return false
    if not Transaction.valid_database(data["database"]):
        return false
    if typeof(data.get("capacity", null)) != TYPE_INT or int(data["capacity"]) < 1:
        return false
    if not (data.get("queued_frames") is Array) or not (data.get("dedup_buffer") is Dictionary):
        return false
    if data["queued_frames"].size() > int(data["capacity"]):
        return false
    if typeof(data.get("last_admitted_tick", null)) != TYPE_INT or int(data["last_admitted_tick"]) < -1:
        return false
    var last_seen: int = int(
        data["database"]["simulation_state"].get("tick_counter", {}).get("current_tick", -1))
    for frame in data["queued_frames"]:
        if not (frame is Dictionary) or not (frame.get("writes") is Array):
            return false
        if typeof(frame.get("tick", null)) != TYPE_INT or int(frame["tick"]) <= last_seen:
            return false
        var has_tick: bool = false
        var has_board: bool = false
        for write in frame["writes"]:
            if Contract.validate_write(write) != "":
                return false
            has_tick = has_tick or write["kind"] == "tick"
            has_board = has_board or write["kind"] == "contract_board"
        if not has_tick or not has_board:
            return false
        last_seen = int(frame["tick"])
    for key in data["dedup_buffer"]:
        var write: Variant = data["dedup_buffer"][key]
        if Contract.validate_write(write) != "" or Contract.dedup_key(write) != key:
            return false
    if last_seen > int(data["last_admitted_tick"]):
        return false
    _database = data["database"].duplicate(true)
    _capacity = int(data["capacity"])
    _admitted = data["queued_frames"].duplicate(true)
    _buffer = data["dedup_buffer"].duplicate(true)
    _last_admitted_tick = int(data["last_admitted_tick"])
    return true
