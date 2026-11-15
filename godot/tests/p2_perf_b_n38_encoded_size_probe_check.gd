extends SceneTree
## Standalone: godot --headless --path godot --script res://tests/p2_perf_b_n38_encoded_size_probe_check.gd
const Probe = preload("res://scripts/sim/phase2/p2_perf_b_n38_encoded_size_probe.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")

func _initialize() -> void:
    var failures: Array[String] = []
    var empty: Dictionary = Probe.measure({})
    _check(not empty.get("ok", true) and empty.get("reason") == "empty_checkpoint",
        "empty checkpoint must be rejected", failures)

    var receipt: Dictionary = {"id": "op:one", "tick": 0, "kind": "test",
        "legs": [{"account": "faction:a", "delta": -1},
                 {"account": "faction:b", "delta": 1}]}
    var snapshot: Dictionary = {
        "format": "living-sector-godot", "tick": 0,
        "description": "unicode: Мир 🚀",
        "native_production": {
            "version": 1, "tick": 0, "world": {"markets": {}},
            "ledger": {"version": 1, "balances": {"faction:a": 10,
                "faction:b": 0}, "receipts": {"op:one": receipt}}
        }
    }
    var original: Dictionary = snapshot.duplicate(true)
    var result: Dictionary = Probe.measure(snapshot)
    var actual: String = JSON.stringify(SaveState._wrap(snapshot), "\t", true, true) + "\n"
    _check(result.get("ok", false), "valid probe", failures)
    _check(result.get("encoded_bytes", -1) == actual.to_utf8_buffer().size(),
        "exact on-disk UTF-8 size, including envelope/newline", failures)
    _check(result.get("limit_bytes", -1) == SaveState.MAX_SAVE_BYTES,
        "uses the real N38 16MiB cap", failures)
    _check(result.get("receipt_count", -1) == 1,
        "reports authoritative N9 receipt count", failures)
    _check(result.get("fits", false), "small save fits", failures)
    _check(snapshot == original, "probe cannot mutate authoritative checkpoint", failures)

    var legacy: Dictionary = Probe.measure({"format": "living-sector-godot",
        "tick": 0, "description": "legacy"})
    _check(legacy.get("ok", false) and legacy.get("receipt_count", -1) == 0,
        "legacy P1 snapshot is supported without inventing N9", failures)

    var big: Dictionary = {"format": "living-sector-godot",
        "description": "X".repeat(SaveState.MAX_SAVE_BYTES + 64)}
    var overflow: Dictionary = Probe.measure(big)
    _check(overflow.get("ok", false) and not overflow.get("fits", true),
        "oversize save is detected, never silently accepted", failures)
    _check(overflow.get("over_limit_bytes", 0) > 0 and
        overflow.get("remaining_bytes", -1) == 0,
        "oversize diagnostic reports bytes over cap", failures)

    if failures.is_empty():
        print("PASS p2_perf_b_n38_encoded_size_probe_check")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)
