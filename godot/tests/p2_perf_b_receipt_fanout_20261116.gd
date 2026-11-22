extends SceneTree
## PERF B: paid-path COW fanout negative regression. No N39/World changes.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"a": 10000, "b": 0}):
		_fail("import")
		return
	if Ledger.RECEIPT_PARTITIONS != 1024:
		_fail("fanout contract")
		return
	for i in range(2048):
		if not ledger.transfer("paid-" + str(i), "a", "b", 1, i, "trade").get("ok", false):
			_fail("commit " + str(i))
			return
	var profile: Dictionary = ledger.receipt_storage_profile()
	if not profile.get("ok", false) or int(profile.get("receipts", -1)) != 2048:
		_fail("storage profile")
		return
	if int(profile.get("largest_shard", 0)) >= 2048:
		_fail("no partitioning")
		return
	if not ledger.audit_receipt_index():
		_fail("index audit")
		return
	var before: Dictionary = ledger.snapshot()
	var fork = ledger.fork()
	if not fork.transfer("fork-only", "a", "b", 2, 2048, "trade").get("ok", false):
		_fail("fork paid append")
		return
	if ledger.snapshot() != before or ledger.has_receipt("fork-only"):
		_fail("parent mutated")
		return
	if fork.transfer("paid-0", "a", "b", 1, 2049, "trade").get("ok", false):
		_fail("duplicate operation accepted")
		return
	var restore = Ledger.new()
	if not restore.restore(before) or restore.snapshot() != before:
		_fail("N38 v1 exact restore")
		return
	if not restore.audit_receipt_index():
		_fail("restored index")
		return
	var forged: Dictionary = before.duplicate(true)
	forged["receipts"]["paid-0"]["legs"][0]["delta"] = -999
	if restore.snapshot() != before:
		_fail("mutable alias after snapshot")
		return
	if ledger.balance("a") != 7952 or ledger.balance("b") != 2048:
		_fail("paid balances")
		return
	print("P2_PERF_B_RECEIPT_FANOUT_PASS ", JSON.stringify(profile))
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_FANOUT_FAIL " + reason)
	quit(1)
