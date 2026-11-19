extends SceneTree
## Run: godot --headless --path godot --script res://tests/p2_perf_d_n150_copy_probe_20261117.gd
const N150 = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	N150.configure_copy_probe(true)
	var initial: Dictionary = N150.copy_probe_snapshot()
	assert(initial["enabled"] == true)
	assert(initial["calls"] == 0 and initial["copy_us"] == 0 and initial["trend_rows"] == 0)
	# A rejected malformed market must never enter the deep-copy hotpath.
	var rejected: Dictionary = N150.tick_one_market({}, 1, 1, Callable())
	assert(not rejected.get("ok", false))
	var after: Dictionary = N150.copy_probe_snapshot()
	assert(after["calls"] == 0 and after["copy_us"] == 0)
	# Diagnostic results must be detached: caller mutations cannot corrupt counters.
	after["calls"] = 999
	assert(N150.copy_probe_snapshot()["calls"] == 0)
	N150.configure_copy_probe(false)
	var disabled: Dictionary = N150.copy_probe_snapshot()
	assert(not disabled["enabled"] and disabled["calls"] == 0)
	print("PASS p2_perf_d_n150_copy_probe_20261117")
	quit(0)
