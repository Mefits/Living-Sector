extends SceneTree
## N9 hot-path regression: a trusted fork skips 1024 temporary shard
## allocations while retaining independent COW ownership and exact v1 export.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	if not parent.import_accounts({"buyer": 10000, "seller": 0}):
		_fail("import")
		return
	if parent.get("_receipt_partitions").size() != Ledger.RECEIPT_PARTITIONS:
		_fail("ordinary construction missing partitions")
		return
	for i in range(160):
		if not parent.transfer("base-%d" % i, "buyer", "seller", 1, i, "trade").get("ok", false):
			_fail("base transfer")
			return
	var before: Dictionary = parent.snapshot()
	var child = parent.fork()
	if child.get("_receipt_partitions").size() != Ledger.RECEIPT_PARTITIONS:
		_fail("fork missing partitions")
		return
	if child.snapshot() != before or not child.retains_owned_receipts(parent):
		_fail("fork lost original receipts")
		return
	if not child.transfer("child-only", "buyer", "seller", 3, 161, "trade").get("ok", false):
		_fail("child payment")
		return
	if parent.has_receipt("child-only") or parent.snapshot() != before:
		_fail("child mutated parent")
		return
	if not child.retains_owned_receipts(parent) or not child.audit_receipt_index():
		_fail("COW provenance")
		return
	var restored = Ledger.new()
	if not restored.restore(child.snapshot()) or restored.snapshot() != child.snapshot():
		_fail("N38 v1 exact roundtrip")
		return
	var normal = Ledger.new()
	if not normal.audit_receipt_index() or normal.receipt_count() != 0:
		_fail("normal empty index")
		return
	print("P2_PERF_B_TRUSTED_FORK_ALLOCATION_NEGATIVE_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_TRUSTED_FORK_ALLOCATION_NEGATIVE_FAIL: " + reason)
	quit(1)
