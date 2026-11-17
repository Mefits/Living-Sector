extends SceneTree
## Negative regression for opt-in N9 snapshot cost accounting. The counters
## must not enter authoritative N9 snapshots or affect idempotency/fork data.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	ledger.set("_profile_append", true)
	if not ledger.import_accounts({"buyer": 200, "seller": 0}):
		_fail("seed")
		return
	var baseline: Dictionary = ledger.snapshot()
	var first: Dictionary = ledger.paid_path_profile()
	if int(first["snapshot_rebuild_calls"]) != 1:
		_fail("first materialization must rebuild")
		return
	if ledger.snapshot() != baseline:
		_fail("repeat snapshot differs")
		return
	var cached: Dictionary = ledger.paid_path_profile()
	if int(cached["snapshot_rebuild_calls"]) != 1 or int(cached["snapshot_calls"]) != 2:
		_fail("cached snapshot rebuilt receipt map")
		return
	if not ledger.transfer("b-prof-1", "buyer", "seller", 12, 1, "trade").get("ok", false):
		_fail("paid transfer")
		return
	var paid: Dictionary = ledger.snapshot()
	var measured: Dictionary = ledger.paid_path_profile()
	if int(measured["snapshot_rebuild_calls"]) != 2 or int(measured["snapshot_calls"]) != 3:
		_fail("append did not invalidate materialization exactly once")
		return
	if int(measured["snapshot_rebuild_usec"]) < 0 or int(measured["snapshot_copy_usec"]) < 0:
		_fail("negative measured duration")
		return
	if paid.has("snapshot_rebuild_calls") or paid.has("snapshot_copy_usec"):
		_fail("diagnostics leaked into authoritative N9")
		return
	var child = ledger.fork()
	if child.snapshot() != paid:
		_fail("fork changed authoritative state")
		return
	if child.transfer("b-prof-1", "buyer", "seller", 12, 2, "trade").get("ok", false):
		_fail("duplicate payment accepted")
		return
	if ledger.snapshot() != paid:
		_fail("fork mutated parent")
		return
	print("PASS p2_perf_b_n9_snapshot_cost_split_20261117")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
