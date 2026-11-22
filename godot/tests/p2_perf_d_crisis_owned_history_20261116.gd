extends SceneTree
## PERF D: N150-owned crisis staging must match detached legacy output.
const Crisis = preload("res://scripts/sim/phase2/unified_native_crisis_events.gd")

func _initialize() -> void:
    var original: Dictionary = {
        "shortage_ticks": {"ore": 200, "water": 0},
        "crisis_notified": {"ore": false, "water": true},
        "trend_samples": [{"tick": 16, "prices": {"ore": 5.0}}]
    }
    var untouched: Dictionary = original.duplicate(true)
    var legacy: Dictionary = Crisis.stage_market_history("market-1", "loc-1", original)
    var owned_input: Dictionary = original.duplicate(true)
    var owned: Dictionary = Crisis.stage_market_history("market-1", "loc-1", owned_input, true)
    assert(legacy.get("ok", false) and owned.get("ok", false))
    assert(legacy["events"] == owned["events"])
    assert(legacy["history"] == owned["history"])
    assert(original == untouched)
    owned["history"]["trend_samples"][0]["prices"]["ore"] = 999.0
    owned["history"]["crisis_notified"]["ore"] = false
    assert(original == untouched)
    assert(legacy["history"]["trend_samples"][0]["prices"]["ore"] == 5.0)
    assert(legacy["history"]["crisis_notified"]["ore"] == true)
    var bad: Dictionary = original.duplicate(true)
    bad["crisis_notified"]["ore"] = "invalid"
    var rejected: Dictionary = Crisis.stage_market_history("market-1", "loc-1", bad, true)
    assert(not rejected.get("ok", false))
    assert(rejected.get("reason", "") == "invalid_market_crisis_flag")
    var bad_count: Dictionary = original.duplicate(true)
    bad_count["shortage_ticks"]["ore"] = -1
    assert(not Crisis.stage_market_history("market-1", "loc-1", bad_count, true).get("ok", false))
    var no_flags: Dictionary = {"shortage_ticks": {"ore": 200}, "trend_samples": []}
    var a: Dictionary = Crisis.stage_market_history("market-1", "loc-1", no_flags)
    var b: Dictionary = Crisis.stage_market_history("market-1", "loc-1", no_flags.duplicate(true), true)
    assert(a.get("ok", false) and b.get("ok", false))
    assert(a["history"] == b["history"] and a["events"] == b["events"])
    print("PASS p2_perf_d_crisis_owned_history_20261116")
    quit()
