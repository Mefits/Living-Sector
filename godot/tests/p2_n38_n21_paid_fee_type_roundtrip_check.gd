extends SceneTree
## Codec-only regression for exact Rust N21 fee integer at an N151 dock.
## The isolated receipt below is never committed to N39 or used to move
## a ship, market goods or money. Full source acceptance uses clean seed.
const NativeData = preload("res://scripts/native_data.gd")
const Runtime = preload("res://scripts/sim/phase2/n158_production_runtime.gd")

func _initialize() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("source Galaxy seed missing")
        return
    var runner = Runtime.new()
    if not runner.start_from_seed(seed):
        _fail("original N158 source seed rejected")
        return
    var frame: Dictionary = runner.checkpoint()["native_production"]
    var originals: Dictionary = frame.duplicate(true)
    # Godot JSON sometimes materializes integer-shaped N21 fee as float.
    # Exercise N38's exact field normalizer on a detached codec fixture.
    var dock_key: String = "n21:dock:codec-only"
    frame["world"]["dock_receipts"][dock_key] = {
        "operation_id": dock_key, "action": "dock",
        "facility_id": "codec-only", "tick": 0.0, "fee": 75.0,
        "financial_receipt": dock_key
    }
    var normalized: Dictionary = frame.duplicate(true)
    if not runner._normalize_native_snapshot(normalized):
        _fail("N38 refused exact whole N21 source fee")
        return
    var receipt: Dictionary = normalized["world"]["dock_receipts"][dock_key]
    if typeof(receipt["fee"]) != TYPE_INT or int(receipt["fee"]) != 75 or (
            typeof(receipt["tick"]) != TYPE_INT):
        _fail("N38 lost N21 proof's integral fee/tick type")
        return
    if runner.checkpoint()["native_production"] != originals:
        _fail("read-only type test unexpectedly changed live N39 World")
        return
    for invalid_fee in [75.5, -1.5, "75"]:
        var bad: Dictionary = frame.duplicate(true)
        bad["world"]["dock_receipts"][dock_key]["fee"] = invalid_fee
        if runner._normalize_native_snapshot(bad):
            _fail("N38 accepted fractional or nonnumeric N21 fee")
            return
    print("P2_N38_N21_FEE_INTEGER_ROUNDTRIP_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N38_N21_FEE_CODEC_FAIL: " + reason)
    quit(1)
