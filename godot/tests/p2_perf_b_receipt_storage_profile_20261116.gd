extends SceneTree
## B-owned bounded receipt storage profiler oracle; no paid-path changes.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"a": 10000, "b": 0}):
		_fail("import")
		return
	var empty: Dictionary = ledger.receipt_storage_profile()
	if not empty.get("ok", false) or int(empty["receipts"]) != 0 or (
			int(empty["largest_shard"]) != 0):
		_fail("empty")
		return
	for i in range(300):
		var receipt: Dictionary = ledger.transfer("paid-" + str(i), "a",
			"b", 1, i, "trade")
		if not receipt.get("ok", false):
			_fail("commit " + str(i))
			return
	var before: Dictionary = ledger.receipt_storage_profile()
	if not before.get("ok", false) or int(before["receipts"]) != 300 or (
			int(before["largest_shard"]) <= 0) or (
			int(before["occupied_shards"]) > Ledger.RECEIPT_PARTITIONS):
		_fail("index counters")
		return
	var forked = ledger.fork()
	if forked.receipt_storage_profile() != before:
		_fail("fork counter isolation")
		return
	if not forked.transfer("fork-only", "a", "b", 1, 301, "trade").get("ok", false):
		_fail("fork transfer")
		return
	if ledger.receipt_storage_profile() != before:
		_fail("parent mutated by fork")
		return
	var detached: Dictionary = ledger.snapshot()
	var restored = Ledger.new()
	if not restored.restore(detached):
		_fail("restore")
		return
	var after: Dictionary = restored.receipt_storage_profile()
	if not after.get("ok", false) or int(after["receipts"]) != 300 or (
			int(after["largest_shard"]) != int(before["largest_shard"])):
		_fail("restore counters")
		return
	if not restored.audit_receipt_index():
		_fail("authoritative index")
		return
	print("P2_PERF_B_RECEIPT_STORAGE_PROFILE_PASS ",
		JSON.stringify(before))
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_STORAGE_PROFILE_FAIL " + reason)
	quit(1)
