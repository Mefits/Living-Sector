extends SceneTree
## Standalone E positive/negative detached checkpoint byte observation oracle.
const Probe = preload("res://scripts/sim/phase2/n158_checkpoint_byte_probe.gd")

func _initialize() -> void:
    var a: Dictionary = {"tick": 100, "native_production": {
        "world": {"ships": [{"id": "ship-1", "cargo": [2, 4]}]},
        "ledger": {"receipts": [{"amount": 7}]}},
        "events": {"pending": [{"tick": 120}]}}
    var b: Dictionary = a.duplicate(true)
    var exact: Dictionary = {"accepted": true, "tick": 100, "exact": true}
    var good: Dictionary = Probe.measure(100, a, b, exact)
    if not good.get("accepted", false):
        _fail("equal checkpoint rejected")
        return
    if int(good["encoded_bytes"]["direct"]) <= 0 or (
            int(good["encoded_bytes"]["worker"]) <= 0):
        _fail("empty encoded bytes")
        return
    var row: Dictionary = good.duplicate(true)
    var summary: Dictionary = Probe.summarize([row], [100])
    if not summary.get("accepted", false) or (
            int(summary["growth_bytes"]["direct"]) != 0):
        _fail("valid bounded summary rejected")
        return
    # The report must not retain mutable checkpoint data.
    a["native_production"]["world"]["ships"][0]["cargo"][0] = 999
    if row.has("native_production") or row.has("events") or (
            summary["samples"][0].has("native_production")):
        _fail("checkpoint mutable alias escaped")
        return
    if Probe.measure(100, a, b, {"accepted": false, "tick": 100,
            "exact": false}).get("accepted", false):
        _fail("missing parity gate accepted")
        return
    if Probe.measure(100, a, b, {"accepted": true, "tick": 99,
            "exact": true}).get("accepted", false):
        _fail("wrong parity clock accepted")
        return
    if Probe.measure(101, a, b, exact).get("accepted", false):
        _fail("unsupported boundary accepted")
        return
    if Probe.measure(100, a, {"tick": 99}, exact).get("accepted", false):
        _fail("wrong worker clock accepted")
        return
    var forged: Dictionary = row.duplicate(true)
    forged["encode_wall_usec"]["worker"] = -1
    if Probe.summarize([forged], [100]).get("accepted", false):
        _fail("negative encode duration accepted")
        return
    forged = row.duplicate(true)
    forged["encoded_bytes"]["direct"] = Probe.MAX_ENCODED_BYTES + 1
    if Probe.summarize([forged], [100]).get("accepted", false):
        _fail("unbounded encoded bytes accepted")
        return
    forged = row.duplicate(true)
    forged["encoded_bytes"].erase("worker")
    if Probe.summarize([forged], [100]).get("accepted", false):
        _fail("missing worker encoding accepted")
        return
    forged = row.duplicate(true)
    forged["included_in_paid_tick_window"] = true
    if Probe.summarize([forged], [100]).get("accepted", false):
        _fail("misattributed observation accepted")
        return
    if Probe.summarize([row, row], [100, 100]).get("accepted", false):
        _fail("duplicate checkpoint accepted")
        return
    if Probe.summarize([row], [300]).get("accepted", false):
        _fail("forged checkpoint accepted")
        return
    print("P2_PERF_E_CHECKPOINT_BYTE_ORACLE_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_CHECKPOINT_BYTE_ORACLE_FAIL " + reason)
    quit(1)
