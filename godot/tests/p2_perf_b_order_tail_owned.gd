extends SceneTree
## Astra II-A: default owned tail must not re-copy between paid operations,
## but must detach on fork, restore, and chunk rollover (64 IDs).
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	var oracle = Ledger.new()
	if not parent.import_accounts({"a": 5000, "b": 0}) or not oracle.import_accounts({"a": 5000, "b": 0}):
		_fail("accounts")
		return
	if not _pay(parent, 0) or not _pay(oracle, 0):
		_fail("first receipt")
		return
	var tail: Array = parent.get("_receipt_order_chunks")[0]
	for i in range(1, 31):
		if not _pay(parent, i) or not _pay(oracle, i):
			_fail("append")
			return
		if not is_same(tail, parent.get("_receipt_order_chunks")[0]):
			_fail("private tail was copied again")
			return
	var frozen: Dictionary = parent.snapshot()
	var child = parent.fork()
	var grandchild = child.fork()
	var parent_tail: Array = parent.get("_receipt_order_chunks")[0]
	if not _pay(parent, 31) or not _pay(child, 32) or not _pay(grandchild, 33):
		_fail("fork payments")
		return
	if is_same(parent_tail, parent.get("_receipt_order_chunks")[0]) or (
			is_same(parent.get("_receipt_order_chunks")[0], child.get("_receipt_order_chunks")[0])) or (
			is_same(child.get("_receipt_order_chunks")[0], grandchild.get("_receipt_order_chunks")[0])):
		_fail("shared mutable tail after fork")
		return
	if parent.snapshot()["receipts"].size() != 32 or child.snapshot()["receipts"].size() != 32 or (
			grandchild.snapshot()["receipts"].size() != 32):
		_fail("branch counts")
		return
	if child.has_receipt("op-31") or parent.has_receipt("op-32") or grandchild.has_receipt("op-32"):
		_fail("cross-branch receipt leak")
		return
	if frozen["receipts"].size() != 31 or not frozen["receipts"].has("op-30"):
		_fail("snapshot mutated")
		return
	var before_failure: Dictionary = parent.snapshot()
	if parent.transfer("op-31", "a", "b", 1, 50, "trade").get("ok", false) or (
			parent.transfer("unfunded", "a", "b", 9000, 50, "trade").get("ok", false)):
		_fail("negative transfer accepted")
		return
	if parent.snapshot() != before_failure:
		_fail("failed transfer mutated ledger")
		return
	for i in range(34, 132):
		if not _pay(parent, i):
			_fail("rollover")
			return
	var chunks: Array = parent.get("_receipt_order_chunks")
	if chunks.size() != 3 or (chunks[0] as Array).size() != 64 or (
			chunks[1] as Array).size() != 64 or (chunks[2] as Array).size() != 2):
		_fail("chunk rollover")
		return
	var saved: Dictionary = parent.snapshot()
	var restored = Ledger.new()
	if not restored.restore(saved) or restored.snapshot() != saved or not restored.audit_receipt_index():
		_fail("N38 exact restore")
		return
	var restored_tail: Array = restored.get("_receipt_order_chunks")[2]
	if not _pay(restored, 132) or is_same(restored_tail, restored.get("_receipt_order_chunks")[2]):
		_fail("restored tail not detached")
		return
	if restored.snapshot()["receipts"].size() != saved["receipts"].size() + 1 or (
			parent.snapshot() != saved):
		_fail("restore alias")
		return
	print("P2_PERF_B_ORDER_TAIL_OWNED_PASS")
	quit(0)

func _pay(ledger: RefCounted, i: int) -> bool:
	return ledger.transfer("op-%d" % i, "a", "b", 1, i, "trade").get("ok", false)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_ORDER_TAIL_OWNED_FAIL: " + reason)
	quit(1)
