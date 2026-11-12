extends SceneTree
## N23: paid facilities run in authoritative tick, never on UI frame alone.
## godot --headless --path godot --script res://tests/n23_production_tick_check.gd
const Runner = preload("res://scripts/sim/production_tick_runner.gd")
const NativeData = preload("res://scripts/native_data.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("native seed unavailable")
        return
    var factory = {"location":"earth", "recipe":"smelt_metals",
        "facility_type":"refinery", "workers":2, "population":5,
        "employer":"company", "household":"people",
        "stock":{"ore":30.0,"fuel":3.0,"metals":0.0}, "limits":{}}
    var a = Runner.new()
    if not a.start_from_seed(seed):
        _fail("seed rejected")
        return
    if not a.configure_production({"company":8,"people":0}, {"a":factory}):
        _fail("production initialization")
        return
    if a.implemented_phases() != PackedStringArray(["bodies","facilities"]):
        _fail("phase registry")
        return
    # A paused frame must not pay wages or produce stock.
    a.queue_control("pause")
    a.advance_frame(0.0)
    if a.production.balance("company") != 8 or a.tick_count != 0:
        _fail("production before tick")
        return
    a.queue_control("step", 1)
    a.advance_frame(0.0)
    if a.tick_count != 1 or a.production.balance("company") != 6:
        _fail("first paid shift")
        return
    if a.production.stock_of("a")["metals"] != 8.0:
        _fail("first physical output")
        return
    a.advance_frame(0.0)
    if a.production.balance("company") != 6:
        _fail("duplicate wage on idle frame")
        return
    var checkpoint: Dictionary = a.checkpoint()
    var b = Runner.new()
    if not b.start_from_seed(seed) or not b.restore_checkpoint(checkpoint, seed):
        _fail("restoring economy checkpoint")
        return
    if b.production.snapshot() != a.production.snapshot():
        _fail("ledger or inventory diverged")
        return
    var invalid = checkpoint.duplicate(true)
    invalid["production"]["facilities"]["a"]["stock"]["ore"] = -3.0
    var before = b.checkpoint()
    if b.restore_checkpoint(invalid, seed) or b.checkpoint() != before:
        _fail("invalid restore changed live state")
        return
    b.queue_control("pause")
    b.queue_control("step", 1)
    b.advance_frame(0.0)
    if b.tick_count != 2 or b.production.balance("company") != 4:
        _fail("replayed shift after restore")
        return
    if b.production.stock_of("a")["metals"] != 16.0:
        _fail("second physical output")
        return
    print("N23_PRODUCTION_TICK_PASS: phase, payroll, conservation, idle, restore")
    quit(0)

func _fail(reason: String) -> void:
    push_error("N23_PRODUCTION_TICK_FAIL: " + reason)
    quit(1)
