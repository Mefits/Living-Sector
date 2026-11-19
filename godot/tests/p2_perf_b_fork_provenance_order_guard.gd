extends SceneTree
## Astra II-A: trusted fork provenance must prove receipt order AND shard
## ownership; the fallback must preserve exact parent prefix after N38 restore.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	if not parent.import_accounts({"buyer": 1000, "seller": 0}):
		_fail("seed")
		return
	for i in range(70):
		if not parent.transfer("paid-%03d" % i, "buyer", "seller", 1, i, "trade").get("ok", false):
			_fail("seed receipt")
			return
	var baseline: Dictionary = parent.snapshot()
	var child = parent.fork()
	for i in range(70, 135):
		if not child.transfer("paid-%03d" % i, "buyer", "seller", 1, i, "trade").get("ok", false):
			_fail("child receipt")
			return
	if not child.retains_owned_receipts(parent) or parent.retains_owned_receipts(child):
		_fail("normal fork provenance")
		return
	if parent.snapshot() != baseline or not parent.audit_receipt_index() or not child.audit_receipt_index():
		_fail("parent isolation")
		return
	var restored = Ledger.new()
	if not restored.restore(child.snapshot()) or not restored.retains_owned_receipts(parent):
		_fail("N38 fallback provenance")
		return
	# Replace the old tail with the same-size reordered prefix. The receipt
	# shards still contain every original row, so a shard-only proof is unsafe.
	var reordered = parent.fork()
	var order: Array = reordered.get("_receipt_order_chunks").duplicate()
	var tail: Array = (order[1] as Array).duplicate()
	var first: Variant = tail[0]
	tail[0] = tail[1]
	tail[1] = first
	order[1] = tail
	reordered.set("_receipt_order_chunks", order)
	if reordered.retains_owned_receipts(parent):
		_fail("reordered old tail accepted")
		return
	# A forged extra order ID must not be accepted just because a receipt
	# count or unchanged shard header appears valid.
	var missing = parent.fork()
	if not missing.transfer("paid-new", "buyer", "seller", 1, 71, "trade").get("ok", false):
		_fail("new payment")
		return
	var missing_order: Array = missing.get("_receipt_order_chunks").duplicate()
	var missing_tail: Array = (missing_order[1] as Array).duplicate()
	missing_tail[missing_tail.size() - 1] = "nonexistent-operation"
	missing_order[1] = missing_tail
	missing.set("_receipt_order_chunks", missing_order)
	if missing.retains_owned_receipts(parent):
		_fail("missing appended receipt accepted")
		return
	# The trusted write-set must not conceal a modified unmarked shard.
	var altered = parent.fork()
	var shards: Array = altered.get("_receipt_partitions").duplicate()
	var index: int = int("paid-000".hash()) & 1023
	shards[index] = (shards[index] as Dictionary).duplicate()
	altered.set("_receipt_partitions", shards)
	if altered.retains_owned_receipts(parent):
		_fail("unmarked shard replacement accepted")
		return
	if parent.snapshot() != baseline:
		_fail("negative tests mutated parent")
		return
	print("P2_PERF_B_FORK_PROVENANCE_ORDER_GUARD_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_FORK_PROVENANCE_ORDER_GUARD_FAIL: " + reason)
	quit(1)
