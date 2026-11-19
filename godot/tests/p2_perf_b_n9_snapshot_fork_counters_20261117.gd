extends SceneTree
## Regression: all opt-in N9 snapshot subphase counters must survive COW forks.
## Otherwise later paid ticks report artificially reset rebuild/copy costs.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	parent.set("_profile_append", true)
	if not parent.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	parent.snapshot()
	if not parent.transfer("b-counter-1", "buyer", "seller", 10, 1, "trade").get("ok", false):
		_fail("transfer")
		return
	var authoritative: Dictionary = parent.snapshot()
	var before: Dictionary = parent.paid_path_profile()
	if int(before["snapshot_rebuild_calls"]) != 2:
		_fail("expected two actual rebuilds")
		return
	var child = parent.fork()
	var sibling = parent.fork()
	for forked in [child, sibling]:
		var inherited: Dictionary = forked.paid_path_profile()
		for key in ["snapshot_rebuild_calls", "snapshot_rebuild_usec", "snapshot_copy_usec",
				"snapshot_calls", "snapshot_usec"]:
			if inherited[key] != before[key]:
				_fail("fork lost counter " + key)
				return
		if forked.snapshot() != authoritative:
			_fail("fork authoritative mismatch")
			return
	if not child.transfer("b-counter-2", "buyer", "seller", 5, 2, "trade").get("ok", false):
		_fail("child transfer")
		return
	child.snapshot()
	if int(child.paid_path_profile()["snapshot_rebuild_calls"]) != 3:
		_fail("child rebuild not accounted")
		return
	if parent.paid_path_profile()["snapshot_rebuild_calls"] != before["snapshot_rebuild_calls"]:
		_fail("parent counter mutated")
		return
	if sibling.paid_path_profile()["snapshot_rebuild_calls"] != before["snapshot_rebuild_calls"]:
		_fail("sibling counter mutated")
		return
	if parent.snapshot() != authoritative:
		_fail("child changed parent receipts")
		return
	if child.transfer("b-counter-1", "buyer", "seller", 10, 3, "trade").get("ok", false):
		_fail("duplicate receipt accepted")
		return
	print("PASS p2_perf_b_n9_snapshot_fork_counters_20261117")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
