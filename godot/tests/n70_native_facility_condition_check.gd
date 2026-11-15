extends SceneTree
## CODE_UNVERIFIED: --headless --path godot --script res://tests/n70_native_facility_condition_check.gd
const Condition = preload("res://scripts/sim/production/native_facility_condition.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var c = Condition.new()
	var base := {"condition": 0.79, "tools": 2.0, "credits": 100, "abandon_counter": 0, "abandoned": false, "last_tick": -1}
	_check(c.import_facilities({"f": base}), "import")
	for tick in range(20):
		var paid := {"f": "workforce:20"} if tick == 19 else {}
		_check(c.step(tick, 1.0, 1, paid).ok, "consecutive tick")
	_check(c.facility("f").tools == 2.0, "no repair before cadence")
	_check(c.step(20, 1.0, 1, {"f": "workforce:20"}).ok, "repair cadence")
	_check(c.facility("f").tools == 1.0, "repair consumes exactly one tool")
	_check(not c.step(20, 1.0, 1, {"f": "workforce:20"}).ok, "replay rejected")
	var saved := c.snapshot()
	var d = Condition.new()
	_check(d.restore(saved), "restore")
	_check(not d.step(22, 1.0, 1, {}).ok, "skipped tick rejected")
	_check(d.step(21, 1.0, 1, {}).ok, "resume exact next tick")
	_check(not d.restore({"version": 1, "facilities": {"f": {"condition": -1}}}), "corrupt restore")
	_check(d.facility("f").last_tick == 21, "atomic restore")
	if failures.is_empty():
		print("N70_NATIVE_CONDITION_PASS")
		quit(0)
	else:
		for f in failures:
			push_error(f)
		quit(1)
func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)
