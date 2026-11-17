extends SceneTree
## Opt-in COW negative regression: repeated same-shard paid receipts must not
## mutate a parent, sibling, or a child created after the first append.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var root: RefCounted = Ledger.new()
	root.set("_reuse_private_shards", true)
	if not root.import_accounts({"a": 1000, "b": 0}):
		_fail("account setup")
		return
	var ids: Array = []
	var target_bucket: int = -1
	for n in range(100000):
		var id: String = "b-reuse-%d" % n
		var bucket: int = root._bucket_index(id)
		if target_bucket < 0:
			target_bucket = bucket
		if bucket == target_bucket:
			ids.append(id)
			if ids.size() == 4:
				break
	if ids.size() != 4:
		_fail("same-shard fixture")
		return
	var child: RefCounted = root.fork()
	var sibling: RefCounted = root.fork()
	if not _pay(child, ids[0]):
		_fail("first paid append")
		return
	if not _pay(child, ids[1]):
		_fail("second paid append")
		return
	if child.receipt_count() != 2 or root.receipt_count() != 0 or sibling.receipt_count() != 0:
		_fail("private shard leaked into parent/sibling")
		return
	var grandchild: RefCounted = child.fork()
	if not _pay(child, ids[2]) or not _pay(grandchild, ids[3]):
		_fail("post-fork paid append")
		return
	if child.has_receipt(ids[3]) or grandchild.has_receipt(ids[2]):
		_fail("fork shared writable shard")
		return
	if root.has_receipt(ids[0]) or sibling.has_receipt(ids[1]):
		_fail("ancestor receipt mutated")
		return
	var snapshot: Dictionary = grandchild.snapshot()
	(snapshot["receipts"] as Dictionary).clear()
	if not grandchild.has_receipt(ids[0]) or not grandchild.has_receipt(ids[3]):
		_fail("external snapshot mutated live receipts")
		return
	if _pay(grandchild, ids[3]):
		_fail("duplicate operation accepted")
		return
	var restored: RefCounted = Ledger.new()
	if not restored.restore(grandchild.snapshot()) or restored.receipt_count() != 3:
		_fail("N38 v1 restore")
		return
	if restored.has_receipt(ids[2]) or not restored.has_receipt(ids[3]):
		_fail("N38 restored wrong branch")
		return
	print("PASS p2_perf_b_n9_private_shard_reuse_20261117")
	quit(0)

func _pay(ledger: RefCounted, id: String) -> bool:
	return bool(ledger.transfer(id, "a", "b", 1, 1, "test").get("ok", false))

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
