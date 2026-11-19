extends SceneTree
## B-owned regression: opt-in timing must never mutate N9 money/receipts.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("accounts")
		return
	var before: Dictionary = ledger.paid_path_profile()
	if not before.has("enabled") or int(before["append_calls"]) != 0:
		_fail("initial counters")
		return
	var first: Dictionary = ledger.transfer("op-1", "buyer", "seller", 25, 1, "trade")
	if not first.get("ok", false):
		_fail("first paid transfer")
		return
	var old: Dictionary = ledger.snapshot()
	var duplicate: Dictionary = ledger.transfer("op-1", "buyer", "seller", 25, 1, "trade")
	if duplicate.get("ok", false):
		_fail("duplicate paid operation accepted")
		return
	var after: Dictionary = ledger.paid_path_profile()
	if int(after["receipt_count"]) != 1:
		_fail("receipt count")
		return
	if bool(after["enabled"]):
		if int(after["append_calls"]) != 1 or int(after["snapshot_calls"]) != 1:
			_fail("actual hotpath timing counted rejected operation")
			return
		if int(after["append_usec"]) < 0 or int(after["snapshot_usec"]) < 0:
			_fail("negative clock delta")
			return
	else:
		if int(after["append_calls"]) != 0 or int(after["snapshot_calls"]) != 0:
			_fail("disabled timing performed work")
			return
	var fork = ledger.fork()
	if not fork.transfer("op-2", "buyer", "seller", 5, 2, "trade").get("ok", false):
		_fail("fork commit")
		return
	if ledger.snapshot() != old or ledger.balance("buyer") != 75:
		_fail("fork changed authoritative ledger")
		return
	var restored = Ledger.new()
	if not restored.restore(old) or restored.snapshot() != old:
		_fail("N9 snapshot restore")
		return
	print("P2_PERF_B_N9_PAID_PATH_TIMING_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_N9_PAID_PATH_TIMING_FAIL " + reason)
	quit(1)
