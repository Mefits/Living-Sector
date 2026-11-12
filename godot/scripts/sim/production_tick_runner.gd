extends "res://scripts/sim/tick_runner.gd"
## N23: opt-in economy-enabled runner. Never synthesizes production from seed.
## The base P1 runner remains orbital-only for backward compatibility.
## Rust source: native/crates/sim_server/src/engine.rs (bodies -> facilities).
const ProductionCoordinator = preload("res://scripts/sim/economy/production_coordinator.gd")

var production: RefCounted = ProductionCoordinator.new()
var _economy_enabled: bool = false
var _last_facilities_result: Dictionary = {}

func configure_production(accounts: Dictionary, facilities: Dictionary) -> bool:
    # Only explicit caller-provided real accounts/stock can enable facilities.
    if not is_started() or tick_count != 0 or _economy_enabled:
        return false
    var candidate = ProductionCoordinator.new()
    if not candidate.initialize(accounts, facilities):
        return false
    production = candidate
    _economy_enabled = true
    _last_facilities_result = {}
    return true

func start_from_seed(seed: Dictionary) -> bool:
    if not super.start_from_seed(seed):
        return false
    production = ProductionCoordinator.new()
    _economy_enabled = false
    _last_facilities_result = {}
    return true

func implemented_phases() -> PackedStringArray:
    if _economy_enabled:
        return PackedStringArray(["bodies", "facilities"])
    return super.implemented_phases()

func _advance_one_tick() -> void:
    # Do not call super: it emits tick_completed BEFORE facilities.
    # Currently no other native phases have executable effects in this base.
    tick_count += 1
    world.advance_orbits(clock.tick_scale())
    if _economy_enabled:
        _last_facilities_result = production.run_tick(tick_count)
        if not _last_facilities_result.get("ok", false):
            push_error("N23 facilities execution rejected tick " + str(tick_count))
    tick_completed.emit(tick_count)

func last_facilities_result() -> Dictionary:
    return _last_facilities_result.duplicate(true)

func checkpoint() -> Dictionary:
    var saved: Dictionary = super.checkpoint()
    if saved.is_empty():
        return saved
    saved["economy_enabled"] = _economy_enabled
    if _economy_enabled:
        saved["production"] = production.snapshot()
        saved["scope"] = "P1 orbital state plus explicitly configured N8 paid facilities"
    return saved

func restore_checkpoint(snapshot: Dictionary, frozen_seed: Dictionary) -> bool:
    # Stage the economy BEFORE mutating the parent runner. A malformed ledger
    # or inventory cannot partially restore orbital or financial state.
    var enabled: Variant = snapshot.get("economy_enabled", false)
    if typeof(enabled) != TYPE_BOOL:
        return false
    var staged = ProductionCoordinator.new()
    if enabled:
        if not (snapshot.get("production") is Dictionary):
            return false
        if not staged.restore(snapshot["production"]):
            return false
        if int(snapshot.get("tick", -1)) < int(snapshot["production"].get("tick", -1)):
            return false
    elif snapshot.has("production"):
        return false
    if not super.restore_checkpoint(snapshot, frozen_seed):
        return false
    production = staged
    _economy_enabled = enabled
    _last_facilities_result = {}
    return true
