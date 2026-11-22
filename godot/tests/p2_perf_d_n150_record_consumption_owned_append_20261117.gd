extends SceneTree
const Market = preload("res://scripts/sim/phase1/n150_native_full_market_tick.gd")

func _initialize() -> void:
	var original: Dictionary = {"consumption_window": {
		"ore": [{"tick": 1, "qty": 2.0, "meta": {"nested": [4]}}],
		"water": [{"tick": 2, "qty": 3.0}]}}
	var result: Dictionary = Market.record_consumption(original, "ore", 5.0, 3)
	assert(result.get("ok", false))
	var next: Dictionary = result["flow"]
	assert(next["consumption_window"]["ore"].size() == 2)
	assert(next["consumption_window"]["ore"][0]["qty"] == 2.0)
	assert(next["consumption_window"]["ore"][1] == {"tick": 3, "qty": 5.0})
	assert(next["consumption_window"]["water"] == original["consumption_window"]["water"])
	next["consumption_window"]["ore"][0]["meta"]["nested"][0] = 99
	assert(original["consumption_window"]["ore"][0]["meta"]["nested"][0] == 4)
	assert(original["consumption_window"]["ore"].size() == 1)
	var ignored: Dictionary = Market.record_consumption(original, "ore", 0.0, 3)
	assert(ignored.get("ok", false))
	assert(ignored["flow"]["consumption_window"]["ore"].size() == 1)
	var malformed: Dictionary = {"consumption_window": {"ore": {"bad": true}}}
	var rejected: Dictionary = Market.record_consumption(malformed, "ore", 1.0, 3)
	assert(not rejected.get("ok", true))
	assert(rejected.get("reason") == "invalid_consumption_window_entries")
	assert(malformed["consumption_window"]["ore"] == {"bad": true})
	print("PASS p2_perf_d_n150_record_consumption_owned_append")
	quit()
