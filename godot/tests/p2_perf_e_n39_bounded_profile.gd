extends SceneTree
## E acceptance: diagnostic retention must be bounded without losing lifetime totals.
const World = preload("res://scripts/sim/phase1/n39_native_world_production.gd")

func _initialize() -> void:
    var owner = World.new()
    var bucket: Dictionary = {}
    for i in range(1024):
        owner.call("_record_timing", bucket, "deep:L129", i + 1)
    var row: Dictionary = bucket["deep:L129"]
    var samples: Array = row["samples_usec"]
    if samples.size() != 256 or samples[0] != 769 or samples[255] != 1024:
        _fail("rolling window retained wrong samples")
        return
    if row["calls"] != 1024 or row["total_usec"] != 524800:
        _fail("lifetime totals were truncated")
        return
    if row["min_usec"] != 1 or row["max_usec"] != 1024:
        _fail("lifetime extrema were truncated")
        return
    owner.call("_record_timing", bucket, "validate:L92", 7)
    if bucket["validate:L92"]["samples_usec"].size() != 1:
        _fail("per-site samples leaked between buckets")
        return
    var published: Dictionary = owner.call("_cost_percentiles", bucket)
    if published["deep:L129"].has("samples_usec") or (
            published["deep:L129"]["p95_usec"] != 1012):
        _fail("published p95 or detached profile incorrect")
        return
    print("P2_PERF_E_N39_BOUNDED_PROFILE_PASS calls=1024 retained=256 lifetime_total=524800")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_N39_BOUNDED_PROFILE_FAIL: " + reason)
    quit(1)
