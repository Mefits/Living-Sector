extends RefCounted
## Actual P1 tick loop. Owns the only writable WorldModel. No SceneTree or
## visual nodes here. This is NOT yet an economy or fleet simulation.

signal tick_completed(tick: int)
signal controls_applied()

const SimClock = preload("res://scripts/sim/clock.gd")
const SimCalendar = preload("res://scripts/sim/calendar.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const SAVE_SCHEMA: int = 1
const SCENARIO_ID: String = "galaxy-067"

# Source: native/crates/sim_server/src/engine.rs, run_tick_loop. P1 only
# executes 'bodies', not pretend no-op versions of the later phases.
const NATIVE_PHASE_ORDER: Array[String] = [
    "bodies", "bodies_regen", "lod", "ships", "apply1",
    "dock_queue", "drains", "facilities", "construction_labor",
    "populations", "markets", "crisis", "apply2", "factions",
    "progression", "colony", "relations", "snapshots",
    "persistence", "broadcast"
]

var clock: RefCounted = SimClock.new()
var calendar: RefCounted = SimCalendar.new()
var world: RefCounted
var tick_count: int = 0
var _controls: Array[Dictionary] = []
var _started: bool = false

func start_from_seed(seed: Dictionary) -> bool:
    var model = WorldModel.new()
    if not model.load_seed(seed):
        return false
    world = model
    clock = SimClock.new()
    calendar = SimCalendar.new()
    tick_count = 0
    _controls.clear()
    _started = true
    return true

func is_started() -> bool:
    return _started

func implemented_phases() -> PackedStringArray:
    return PackedStringArray(["bodies"])

func queue_control(kind: String, value: Variant = null) -> bool:
    if not _started:
        return false
    match kind:
        "pause", "resume":
            pass
        "step":
            if not (value is int) or value < 1 or value > 1024:
                return false
        "speed":
            if not (value is float or value is int):
                return false
            if not is_finite(float(value)) or float(value) <= 0.0 or float(value) > 16.0:
                return false
        _:
            # E.g. credits, contracts or fabricated production are prohibited
            # until the corresponding native execution rules are ported.
            return false
    _controls.append({"kind": kind, "value": value})
    return true

func _drain_controls() -> void:
    if _controls.is_empty():
        return
    var batch: Array[Dictionary] = _controls.duplicate(true)
    _controls.clear()
    for control in batch:
        match str(control["kind"]):
            "pause":
                clock.set_paused(true)
            "resume":
                clock.set_paused(false)
            "step":
                clock.request_steps(int(control["value"]))
            "speed":
                clock.set_speed(float(control["value"]))
    controls_applied.emit()

func advance_frame(delta: float) -> void:
    if not _started:
        return
    # Controls are drained even while paused, just like native's control_rx.
    _drain_controls()
    var due: int = clock.consume_frame(delta)
    for _i in range(due):
        _advance_one_tick()

func _advance_one_tick() -> void:
    tick_count += 1
    var native_delta: float = clock.tick_scale()
    world.advance_orbits(native_delta)
    calendar.advance_committed_tick(native_delta)
    tick_completed.emit(tick_count)

func checkpoint() -> Dictionary:
    if not _started:
        return {}
    return {
        "format": "living-sector-godot",
        "schema_version": SAVE_SCHEMA,
        "scenario": SCENARIO_ID,
        "seed_fingerprint": world.seed_fingerprint(),
        "tick": tick_count,
        "clock": clock.snapshot(),
        "calendar": calendar.snapshot(),
        "orbital_angles": world.orbital_snapshot(),
        "pending_controls": _controls.duplicate(true),
        "scope": "P1 orbital-only; no economic, ship or contract state is mutable yet"
    }

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
    # Transactional in-memory restoration: stage and validate everything
    # before swapping live world/clock. Invalid files cannot half-restore.
    if not _started or snapshot.get("format", "") != "living-sector-godot":
        return false
    if snapshot.get("scenario", "") != SCENARIO_ID:
        return false
    var version: Variant = snapshot.get("schema_version", null)
    var saved_tick: Variant = snapshot.get("tick", null)
    if not _safe_whole_number(version, 1) or int(version) != SAVE_SCHEMA:
        return false
    if not _safe_whole_number(saved_tick, 0):
        return false
    var source_sha: String = str(snapshot.get("seed_fingerprint", ""))
    if source_sha.is_empty() or source_sha != world.seed_fingerprint():
        return false
    var angle_value: Variant = snapshot.get("orbital_angles", null)
    var clock_value: Variant = snapshot.get("clock", null)
    var queued_value: Variant = snapshot.get("pending_controls", null)
    if not (angle_value is Dictionary) or not (clock_value is Dictionary):
        return false
    if not (queued_value is Array) or queued_value.size() > 1024:
        return false
    var staged_controls: Array[Dictionary] = []
    for control in queued_value:
        if not (control is Dictionary):
            return false
        var kind: String = str(control.get("kind", ""))
        var value: Variant = control.get("value", null)
        if not _valid_control(kind, value):
            return false
        staged_controls.append(control.duplicate(true))
    var staged_world = WorldModel.new()
    if not staged_world.load_seed(frozen_seed):
        return false
    if staged_world.seed_fingerprint() != source_sha:
        return false
    if not staged_world.restore_orbital_snapshot(angle_value):
        return false
    var staged_calendar = SimCalendar.new()
    # Schema v1 saves predate the calendar; replaying a constant historic
    # world_speed is unsafe because speed could change between saved ticks.
    # Keep legacy saves loadable, but mark elapsed native time as unknown.
    var calendar_value: Variant = snapshot.get("calendar", null)
    if calendar_value != null:
        if not (calendar_value is Dictionary) or not staged_calendar.restore(calendar_value):
            return false
    elif int(version) == SAVE_SCHEMA:
        staged_calendar.native_time_units = 0.0
        staged_calendar.origin_known = false
    var staged_clock = SimClock.new()
    if not staged_clock.restore(clock_value):
        return false
    world = staged_world
    clock = staged_clock
    calendar = staged_calendar
    tick_count = int(saved_tick)
    _controls = staged_controls
    # UI receives the exact restored counter before a further update.
    tick_completed.emit(tick_count)
    return true

func _valid_control(kind: String, value: Variant) -> bool:
    match kind:
        "pause", "resume":
            return value == null
        "step":
            return _safe_whole_number(value, 1) and int(value) <= 1024
        "speed":
            return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0 and float(value) <= 16.0
    return false

func _safe_whole_number(value: Variant, minimum: int) -> bool:
    # Godot JSON parser can represent numeric JSON values as floats.
    if not (value is int or value is float):
        return false
    if not is_finite(float(value)):
        return false
    return float(value) >= float(minimum) and float(value) <= 9007199254740991.0 and float(int(value)) == float(value)
