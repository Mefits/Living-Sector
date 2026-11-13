extends "res://scripts/sim/tick_runner.gd"
## N39 opt-in tick adapter. Phase1 only: bodies and paid facilities.
## Preserves N1 event ordering, calendar, tick signal, checkpoint preflight.
## NOT the Phase2 unified engine; it cannot execute ships/markets/AI yet.
const NativeProduction = preload("res://scripts/sim/phase1/n39_native_world_production.gd")
const Payroll = preload("res://scripts/sim/phase1/n39_native_paid_shift.gd")

var production: RefCounted = NativeProduction.new()
var _native_enabled: bool = false
var _last_native_result: Dictionary = {}
var _external_labor_this_tick: Dictionary = {}
var _tick_multiplier: int = 1

func start_from_seed(seed: Dictionary) -> bool:
    if not super.start_from_seed(seed):
        return false
    production = NativeProduction.new()
    _native_enabled = false
    _last_native_result = {}
    _external_labor_this_tick = {}
    _tick_multiplier = 1
    return true

func configure_native_production(physical_world: Dictionary,
        tick_multiplier: int = 1) -> bool:
    if not is_started() or tick_count != 0 or _native_enabled:
        return false
    if tick_multiplier < 1 or tick_multiplier > 10000:
        return false
    var staged = NativeProduction.new()
    if not staged.initialize(physical_world):
        return false
    production = staged
    _tick_multiplier = tick_multiplier
    _native_enabled = true
    return true

## From confirmed N141 construction / N143 commander shifts, NOT a fabricated
## workforce pool. Must be supplied anew for every actual tick if used.
func set_external_labor_for_next_tick(occupied: Dictionary) -> bool:
    if not _native_enabled:
        return false
    var staged = production.world_snapshot()
    if Payroll.validate_reservations(staged, occupied) != "":
        return false
    _external_labor_this_tick = occupied.duplicate(true)
    return true

func implemented_phases() -> PackedStringArray:
    return PackedStringArray(["bodies", "facilities"]) if _native_enabled else super.implemented_phases()

func last_native_result() -> Dictionary:
    return _last_native_result.duplicate(true)

func _advance_one_tick() -> void:
    tick_count += 1
    var native_delta: float = clock.tick_scale()
    for index in range(NATIVE_PHASE_ORDER.size()):
        var phase: String = NATIVE_PHASE_ORDER[index]
        if phase == "bodies" and cadence.is_due(phase, tick_count):
            world.advance_orbits(native_delta)
        if phase == "facilities" and _native_enabled:
            _last_native_result = production.run_tick(tick_count,
                _tick_multiplier, _external_labor_this_tick)
            _external_labor_this_tick = {}
            if not _last_native_result.get("ok", false):
                push_error("N39 native production tick rejected: " +
                    str(_last_native_result.get("reason", "unknown")))
        for event in events.take_due(tick_count, index):
            scheduled_event_due.emit(event)
    calendar.advance_committed_tick(native_delta)
    tick_completed.emit(tick_count)

func checkpoint() -> Dictionary:
    var saved: Dictionary = super.checkpoint()
    if saved.is_empty():
        return saved
    saved["native_production_enabled"] = _native_enabled
    saved["native_production_multiplier"] = _tick_multiplier
    # The caller must also checkpoint external production owner ECS in Phase2.
    if _native_enabled:
        saved["native_production"] = production.snapshot()
        saved["scope"] = "P1 orbital events/calendar plus explicit N39 paid physical production"
    return saved

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
    if typeof(snapshot.get("native_production_enabled", false)) != TYPE_BOOL:
        return false
    var enabled: bool = bool(snapshot.get("native_production_enabled", false))
    if typeof(snapshot.get("native_production_multiplier", 1)) != TYPE_INT:
        return false
    var mult: int = int(snapshot.get("native_production_multiplier", 1))
    if mult < 1 or mult > 10000:
        return false
    var staged = NativeProduction.new()
    if enabled:
        if not (snapshot.get("native_production") is Dictionary):
            return false
        if not staged.restore(snapshot["native_production"]):
            return false
        if int(snapshot["native_production"].get("tick", -1)) != int(snapshot.get("tick", -2)):
            return false
    elif snapshot.has("native_production"):
        return false
    # The base restore is transactional for its own orbit/clock/event state.
    if not super.restore_checkpoint(snapshot, frozen_seed):
        return false
    production = staged
    _native_enabled = enabled
    _tick_multiplier = mult
    _last_native_result = {}
    _external_labor_this_tick = {}
    return true
