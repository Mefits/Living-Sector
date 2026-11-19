extends SceneTree
## First insert into an empty N9 bucket must preserve fork isolation,
## exact receipt order, duplicate rejection, and N38 v1 roundtrip.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	if not parent.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	var child = parent.fork()
	var operation_id := "empty-bucket-first"
	if not child.transfer(operation_id, "buyer", "seller", 9, 1, "trade").get("ok", false):
		_fail("first append")
		return
	if parent.has_receipt(operation_id) or parent.balance("buyer") != 100:
		_fail("parent mutated by empty-shard append")
		return
	if not child.has_receipt(operation_id) or child.balance("buyer") != 91:
		_fail("child receipt/balance")
		return
	var before: Dictionary = child.snapshot()
	if child.transfer(operation_id, "buyer", "seller", 1, 2, "trade").get("ok", false):
		_fail("duplicate accepted")
		return
	if child.snapshot() != before:
		_fail("duplicate changed state")
		return
	var sibling = parent.fork()
	if not sibling.transfer(operation_id, "buyer", "seller", 4, 1, "trade").get("ok", false):
		_fail("sibling append")
		return
	if sibling.balance("buyer") != 96 or child.balance("buyer") != 91:
		_fail("sibling alias")
		return
	var restored = Ledger.new()
	if not restored.restore(before) or restored.snapshot() != before:
		_fail("N38 exact restore")
		return
	if not restored.audit_receipt_index() or not child.audit_receipt_index():
		_fail("receipt index")
		return
	before["receipts"][operation_id]["legs"][0]["delta"] = -99
	if restored.receipt_copy(operation_id)["legs"][0]["delta"] != -9:
		_fail("snapshot alias")
		return
	print("P2_PERF_B_EMPTY_SHARD_APPEND_COW_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_EMPTY_SHARD_APPEND_COW_FAIL: " + reason)
	quit(1)
