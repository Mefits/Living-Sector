extends SceneTree
## Standalone negative regression for B-owned read-only N38 growth probe.
## godot --headless --path godot --script res://tests/p2_perf_b_n38_growth_probe_check.gd
const Probe = preload("res://scripts/sim/phase2/p2_perf_b_n38_growth_probe.gd")
const SizeProbe = preload("res://scripts/sim/phase2/p2_perf_b_n38_encoded_size_probe.gd")

func _initialize() -> void:
    var failures: Array[String] = []
    var before: Dictionary = _checkpoint({"op:1": _receipt("op:1")})
    var after: Dictionary = before.duplicate(true)
    after["native_production"]["ledger"]["receipts"]["op:2"] = _receipt("op:2")
    after["note"] = "Мир 🚀"
    var before_copy: Dictionary = before.duplicate(true)
    var after_copy: Dictionary = after.duplicate(true)
    var result: Dictionary = Probe.measure(before, after)
    _check(result.get("ok", false), "append accepted", failures)
    _check(result.get("added_receipts", -1) == 1, "one new receipt", failures)
    _check(result.get("before_bytes", -1) == SizeProbe.measure(before).get("encoded_bytes"),
        "before size matches actual encoder", failures)
    _check(result.get("after_bytes", -1) == SizeProbe.measure(after).get("encoded_bytes"),
        "after size matches actual encoder", failures)
    _check(result.get("delta_bytes", 0) == int(result.get("after_bytes", 0)) -
        int(result.get("before_bytes", 0)), "exact delta", failures)
    _check(before == before_copy and after == after_copy, "no input mutation", failures)

    var tampered: Dictionary = after.duplicate(true)
    tampered["native_production"]["ledger"]["receipts"]["op:1"]["kind"] = "forged"
    _check(Probe.measure(before, tampered).get("reason") == "old_receipt_changed",
        "tampered historical receipt rejected", failures)
    var missing: Dictionary = after.duplicate(true)
    missing["native_production"]["ledger"]["receipts"].erase("op:1")
    _check(Probe.measure(before, missing).get("reason") == "old_receipt_missing",
        "replaced historical ID rejected", failures)
    var shrunk: Dictionary = before.duplicate(true)
    shrunk["native_production"]["ledger"]["receipts"].clear()
    _check(Probe.measure(before, shrunk).get("reason") == "receipt_history_shrank",
        "shrunk history rejected", failures)
    var no_ledger: Dictionary = {"format": "living-sector-godot"}
    _check(Probe.measure(before, no_ledger).get("reason") == "missing_n9_receipts",
        "missing N9 rejected", failures)
    _check(not Probe.measure({}, after).get("ok", true),
        "empty checkpoint rejected", failures)
    var same: Dictionary = Probe.measure(before, before)
    _check(same.get("ok", false) and same.get("added_receipts", -1) == 0 and
        same.get("delta_bytes", -1) == 0, "unchanged checkpoint", failures)
    # Other domains may shrink even as receipts append. This is diagnostic,
    # not a monotonic-byte assumption.
    var smaller: Dictionary = before.duplicate(true)
    smaller["note"] = "x".repeat(1024)
    var compact: Dictionary = after.duplicate(true)
    compact["note"] = ""
    var shrink_result: Dictionary = Probe.measure(smaller, compact)
    _check(shrink_result.get("ok", false) and
        shrink_result.get("delta_bytes", 0) < 0,
        "negative byte delta with valid receipt append", failures)

    if failures.is_empty():
        print("PASS p2_perf_b_n38_growth_probe_check")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        quit(1)

func _receipt(id: String) -> Dictionary:
    return {"id": id, "tick": 0, "kind": "transfer",
        "legs": [{"account": "a", "delta": -1}, {"account": "b", "delta": 1}]}

func _checkpoint(receipts: Dictionary) -> Dictionary:
    return {"format": "living-sector-godot", "tick": 0, "note": "base",
        "native_production": {"ledger": {"version": 1,
            "balances": {"a": 5, "b": 0}, "receipts": receipts}}}

func _check(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)
