extends SceneTree
## Astra II-A: opt-in exact-object owned shard reuse against legacy COW oracle.
## Never enables the experimental backend globally or modifies N38 format.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var fast = Ledger.new()
	var oracle = Ledger.new()
	fast.set("_reuse_private_shards", true)
	if not fast.import_accounts({"a": 5000, "b": 0}) or not oracle.import_accounts({"a": 5000, "b": 0}):
		_fail("accounts")
		return
	var ids: Array = []
	var bucket: int = -1
	for i in range(100000):
		var id: String = "owned-shard-%d" % i
		if bucket < 0:
			bucket = fast._bucket_index(id)
		if fast._bucket_index(id) == bucket:
			ids.append(id)
			if ids.size() == 12:
				break
	if ids.size() != 12:
		_fail("collision fixture")
		return
	for i in range(4):
		if not _pay(fast, ids[i]) or not _pay(oracle, ids[i]):
			_fail("initial payments")
			return
	var owned: Dictionary = fast.get("_receipt_partitions")[bucket]
	if not is_same(owned, fast.get("_private_shards")[bucket]):
		_fail("ownership identity not recorded")
		return
	if not _pay(fast, ids[4]) or not _pay(oracle, ids[4]):
		_fail("owned append")
		return
	if not is_same(owned, fast.get("_receipt_partitions")[bucket]):
		_fail("owned shard unnecessarily detached")
		return
	if fast.snapshot() != oracle.snapshot():
		_fail("initial oracle parity")
		return
	var frozen: Dictionary = fast.snapshot()
	var sibling = fast.fork()
	var oracle_sibling = oracle.fork()
	var old_shard: Dictionary = fast.get("_receipt_partitions")[bucket]
	if not _pay(fast, ids[5]) or not _pay(oracle, ids[5]) or not _pay(sibling, ids[6]) or not _pay(oracle_sibling, ids[6]):
		_fail("fork payments")
		return
	if is_same(old_shard, fast.get("_receipt_partitions")[bucket]) or is_same(old_shard, sibling.get("_receipt_partitions")[bucket]):
		_fail("fork did not detach shared shard")
		return
	if frozen != oracle_sibling.snapshot() or fast.snapshot() != oracle.snapshot() or sibling.snapshot() != oracle_sibling.snapshot():
		_fail("fork oracle parity")
		return
	# Simulate a stale private-shard marker after a new shard header was
	# installed. Object identity must prevent accidental shared mutation.
	var stale: Dictionary = fast.get("_receipt_partitions")[bucket]
	var replacement: Dictionary = stale.duplicate()
	var header: Array = fast.get("_receipt_partitions").duplicate()
	header[bucket] = replacement
	fast.set("_receipt_partitions", header)
	if not _pay(fast, ids[7]) or not _pay(oracle, ids[7]):
		_fail("replaced header append")
		return
	if is_same(replacement, fast.get("_receipt_partitions")[bucket]) or replacement.has(ids[7]):
		_fail("stale ownership mutated replacement")
		return
	if fast.snapshot() != oracle.snapshot() or not fast.audit_receipt_index():
		_fail("replacement oracle parity")
		return
	var prior: Dictionary = fast.snapshot()
	if fast.transfer(ids[7], "a", "b", 1, 100, "trade").get("ok", false) or fast.transfer("unfunded", "a", "b", 9000, 100, "trade").get("ok", false):
		_fail("negative payment accepted")
		return
	if fast.snapshot() != prior:
		_fail("rejected payment changed receipts")
		return
	var restored = Ledger.new()
	restored.set("_reuse_private_shards", true)
	if not restored.restore(prior) or restored.snapshot() != prior:
		_fail("N38 v1 restore")
		return
	var restored_shard: Dictionary = restored.get("_receipt_partitions")[bucket]
	if not _pay(restored, ids[8]) or is_same(restored_shard, restored.get("_receipt_partitions")[bucket]):
		_fail("restore did not revoke ownership")
		return
	if restored_shard.has(ids[8]) or fast.has_receipt(ids[8]):
		_fail("restore alias leak")
		return
	var tampered: Dictionary = prior.duplicate(true)
	tampered["receipts"][ids[0]]["id"] = "forged"
	var before_tamper: Dictionary = restored.snapshot()
	if restored.restore(tampered) or restored.snapshot() != before_tamper:
		_fail("tampered restore accepted or mutated ledger")
		return
	if not restored.audit_receipt_index() or not sibling.audit_receipt_index():
		_fail("post-restore index audit")
		return
	print("PASS p2_perf_b_n9_shard_owned_append")
	quit(0)

func _pay(ledger: RefCounted, id: String) -> bool:
	return bool(ledger.transfer(id, "a", "b", 1, 1, "trade").get("ok", false))

func _fail(message: String) -> void:
	push_error("FAIL p2_perf_b_n9_shard_owned_append: " + message)
	quit(1)
