extends RefCounted
## Same time parameters as Rust native/crates/sim_core/src/simulation/config.rs.
## Game time and frames are independent. This clock never changes cargo or money.

const DEFAULT_TPS: int = 8
const DEFAULT_WORLD_SPEED: float = 0.25
const MAX_TICKS_PER_FRAME: int = 16

var ticks_per_second: int = DEFAULT_TPS
var world_speed: float = DEFAULT_WORLD_SPEED
var paused: bool = false

var _accumulator: float = 0.0
var _step_queue: int = 0

func tick_scale() -> float:
    # Rust: world_speed / ticks_per_second
    return world_speed / float(ticks_per_second)

func tick_multiplier() -> int:
    # Rust: round(tps / world_speed); 0 at sufficiently high speed is
    # legal in native, and consumers must account for it explicitly.
    if world_speed <= 0.0:
        return 0
    return roundi(float(ticks_per_second) / world_speed)

func set_speed(value: float) -> bool:
    if not is_finite(value) or value <= 0.0 or value > 16.0:
        return false
    world_speed = value
    return true

func set_tps(value: int) -> bool:
    if value < 1 or value > 60:
        return false
    ticks_per_second = value
    _accumulator = 0.0
    return true

func set_paused(value: bool) -> void:
    paused = value
    _accumulator = 0.0

func request_steps(count: int) -> bool:
    if count < 1 or count > 1024:
        return false
    _step_queue = mini(_step_queue + count, 1024)
    return true

func reset() -> void:
    ticks_per_second = DEFAULT_TPS
    world_speed = DEFAULT_WORLD_SPEED
    paused = false
    _step_queue = 0
    _accumulator = 0.0

func consume_frame(delta: float) -> int:
    # Manual steps are honoured even while paused, just like native.
    if _step_queue > 0:
        var manual: int = mini(_step_queue, MAX_TICKS_PER_FRAME)
        _step_queue -= manual
        return manual
    if paused:
        _accumulator = 0.0
        return 0
    if not is_finite(delta) or delta <= 0.0:
        return 0
    # Rust tokio::MissedTickBehavior::Delay also avoids unbounded catch-up.
    # Long OS/window stalls must not simulate hundreds of economic ticks at once.
    _accumulator += minf(delta, 0.25)
    var interval: float = 1.0 / float(ticks_per_second)
    var due: int = mini(int(floor(_accumulator / interval)), MAX_TICKS_PER_FRAME)
    _accumulator -= float(due) * interval
    return due

func snapshot() -> Dictionary:
    return {
        "ticks_per_second": ticks_per_second,
        "world_speed": world_speed,
        "paused": paused,
        "pending_steps": _step_queue
    }

func restore(saved: Dictionary) -> bool:
    var tps: Variant = saved.get("ticks_per_second", null)
    var speed: Variant = saved.get("world_speed", null)
    var paused_value: Variant = saved.get("paused", null)
    var steps: Variant = saved.get("pending_steps", null)
    if not (tps is int or tps is float) or not (speed is float or speed is int):
        return false
    if not (paused_value is bool) or not (steps is int or steps is float):
        return false
    if not is_finite(float(tps)) or not is_finite(float(steps)):
        return false
    if float(tps) != float(int(tps)) or float(steps) != float(int(steps)):
        return false
    if tps < 1 or tps > 60 or steps < 0 or steps > 1024:
        return false
    if not is_finite(float(speed)) or float(speed) <= 0.0 or float(speed) > 16.0:
        return false
    ticks_per_second = int(tps)
    world_speed = float(speed)
    paused = paused_value
    _step_queue = int(steps)
    _accumulator = 0.0
    return true
