extends RefCounted
## E: opt-in owner-side control coordinator. Never owns World or advances N158.
## Caller must invoke owner_drain_one only on the simulation owner thread,
## at a completed authoritative tick boundary. UI sees only the bridge.
const BRIDGE = preload("res://scripts/sim/phase2/n158_worker_owner_bridge.gd")
const SCHEDULER = preload("res://scripts/sim/phase2/n158_worker_tick_scheduler.gd")

var _bridge = BRIDGE.new()
var _scheduler = SCHEDULER.new()
var _load_epoch: int = 0

func ui_enqueue(kind: String, payload: Dictionary = {}) -> int:
    return _bridge.ui_enqueue(kind, payload)

func ui_read_ack(ticket: int) -> Dictionary:
    return _bridge.ui_read_ack(ticket)

func ui_read_frame() -> Dictionary:
    return _bridge.ui_read_frame()

func ui_status() -> Dictionary:
    var status: Dictionary = _bridge.ui_status()
    status["scheduler"] = _scheduler.snapshot()
    status["load_epoch"] = _load_epoch
    return status

func owner_configure(tick_seconds: float) -> bool:
    return _scheduler.configure(tick_seconds)

## Persistence executor is an owner-local Callable, never queued or stored.
## Signature: executor(kind: String, slot: String) -> bool.
## The authoritative N38 implementation decides whether a save/load succeeds.
func owner_drain_one(persistence_executor: Callable = Callable()) -> Dictionary:
    var item: Dictionary = _bridge.owner_take_command()
    if item.is_empty():
        return {}
    var kind: String = String(item["kind"])
    var ticket: int = int(item["id"])
    var payload: Dictionary = item["payload"]
    var success: bool = false
    if kind == "save" or kind == "load":
        if persistence_executor.is_valid():
            var result: Variant = persistence_executor.call(kind, String(payload["slot"]))
            success = typeof(result) == TYPE_BOOL and result
            if success and kind == "load":
                success = _scheduler.reset_after_load()
                if success:
                    _load_epoch += 1
    else:
        success = _scheduler.apply_control(kind, payload)
    var accepted: bool = _bridge.owner_finish_command(ticket, success, "" if success else "command_rejected")
    if not accepted:
        _bridge.owner_freeze("fifo_ack_failed")
    return {"id": ticket, "kind": kind, "success": success and accepted}

## Owner calls this after the REAL N158 tick has committed, not on admission.
func owner_publish_committed(tick: int, projection: Dictionary) -> bool:
    return _bridge.owner_publish_committed(tick, projection)

func owner_add_elapsed(delta: float) -> bool:
    return _scheduler.add_elapsed(delta)

func owner_begin_tick() -> bool:
    return _scheduler.begin_tick()

func owner_finish_tick(success: bool) -> bool:
    var accepted: bool = _scheduler.finish_tick(success)
    if not success:
        _bridge.owner_freeze("authoritative_tick_failed")
    return accepted

func owner_freeze(reason: String) -> void:
    _bridge.owner_freeze(reason)
