extends SceneTree
## CODE_UNVERIFIED: --headless --path godot --script res://tests/n69_native_relations_check.gd
const Relations = preload("res://scripts/sim/factions/native_relations.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var r = Relations.new()
	_check(r.commerce_allowed("a", "b"), "neutral commerce")
	_check(r.set_state("b", "a", 40, "trade_pact", 10), "treaty")
	_check(r.state("a", "b").standing == 40, "canonical pair")
	_check(r.payment_multiplier("a", "b") == 1.10, "pact payment")
	_check(r.dock_modifiers("b", "a") == Vector2(0.8, 0.5), "dock modifier")
	_check(r.visibility_floor("a", "b") == 50, "pact visibility")
	_check(r.bump("a", "b", 100, 11) and r.state("a", "b").standing == 100, "standing clamp")
	_check(r.set_state("a", "b", -90, "war", 12), "war state")
	_check(not r.commerce_allowed("a", "b"), "war blocks commerce")
	_check(not r.set_state("a", "b", 0, "unknown", 13), "invalid treaty")
	var saved := r.snapshot()
	var restored = Relations.new()
	_check(restored.restore(saved), "restore")
	_check(not restored.commerce_allowed("b", "a"), "war persists")
	_check(not restored.restore({"version": 1, "pairs": {"bad": {"a": "a", "b": "b"}}}), "corrupt restore")
	_check(not restored.commerce_allowed("a", "b"), "atomic restore")
	if failures.is_empty():
		print("N69_NATIVE_RELATIONS_PASS")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)
func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
