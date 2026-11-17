extends SceneTree
## Targeted negative regression: paid-path counters must survive authoritative
## ledger COW forks without leaking into N38 or mutating the parent.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent: RefCounted = Ledger.new()
	parent.set("_profile_append", true)
	parent.set("_profile_append_calls", 7)
	parent.set("_profile_append_usec", 111)
	parent.set("_profile_append_max_usec", 31)
	parent.set("_profile_append_old_shard_rows", 17)
	parent.set("_profile_snapshot_calls", 5)
	parent.set("_profile_snapshot_usec", 79)
	parent.set("_profile_snapshot_max_usec", 23)
	var child: RefCounted = parent.fork()
	var before: Dictionary = child.paid_path_profile()
	if int(before.get("append_calls", -1)) != 7 or int(before.get("append_usec", -1)) != 111:
		_fail("append counters lost on fork")
		return
	if int(before.get("append_max_usec", -1)) != 31 or int(before.get("append_old_shard_rows", -1)) != 17:
		_fail("append distribution lost on fork")
		return
	if int(before.get("snapshot_calls", -1)) != 5 or int(before.get("snapshot_usec", -1)) != 79 or int(before.get("snapshot_max_usec", -1)) != 23:
		_fail("snapshot counters lost on fork")
		return
	child.set("_profile_append_calls", 99)
	if int(parent.paid_path_profile().get("append_calls", -1)) != 7:
		_fail("child diagnostic mutation leaked into parent")
		return
	var exported: Dictionary = child.snapshot()
	if exported.has("_profile_append_calls") or exported.has("profile") or exported.has("append_usec"):
		_fail("diagnostic counters leaked into N38")
		return
	print("PASS p2_perf_b_n9_paid_profile_fork_counters_20261117")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
