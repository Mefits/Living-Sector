extends SceneTree
## Opt-in order-chunk reuse must preserve receipt ordering and fork isolation.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var baseline = Ledger.new()
	var optimized = Ledger.new()
	optimized.set("_reuse_private_shards", true)
	if not baseline.import_accounts({"a": 10000, "b": 0}) or not optimized.import_accounts({"a": 10000, "b": 0}):
		_fail("seed")
		return
	for i in range(70):
		if not _pay(baseline, i) or not _pay(optimized, i):
			_fail("initial payment")
			return
	var parent_before: Dictionary = optimized.snapshot()
	var baseline_child = baseline.fork()
	var optimized_child = optimized.fork()
	for i in range(70, 145):
		if not _pay(baseline_child, i) or not _pay(optimized_child, i):
			_fail("child payment")
			return
	for i in range(145, 151):
		if not _pay(baseline, i) or not _pay(optimized, i):
			_fail("parent payment")
			return
	if baseline.snapshot() != optimized.snapshot() or baseline_child.snapshot() != optimized_child.snapshot():
		_fail("baseline parity")
		return
	if parent_before["receipts"].size() != 70 or optimized.snapshot()["receipts"].size() != 76:
		_fail("fork shared order chunk")
		return
	if optimized.has_receipt("op-100") or not optimized_child.has_receipt("op-100"):
		_fail("fork receipt isolation")
		return
	var restored = Ledger.new()
	if not restored.restore(optimized_child.snapshot()) or not restored.audit_receipt_index():
		_fail("restore/index")
		return
	if restored.snapshot() != baseline_child.snapshot():
		_fail("roundtrip")
		return
	if optimized_child.transfer("op-100", "a", "b", 1, 200, "trade").get("ok", false):
		_fail("duplicate receipt accepted")
		return
	print("P2_PERF_B_ORDER_CHUNK_PRIVATE_FORK_PASS")
	quit(0)

func _pay(ledger: RefCounted, i: int) -> bool:
	return ledger.transfer("op-%d" % i, "a", "b", 1, i, "trade").get("ok", false)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_ORDER_CHUNK_PRIVATE_FORK_FAIL: " + reason)
	quit(1)
