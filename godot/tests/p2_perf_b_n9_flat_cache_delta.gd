extends SceneTree
## N9 delta-cache oracle: repeated paid appends, fork, restore, rejected
## operations and external mutation must match a fresh full-history rebuild.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var root = Ledger.new()
	if not root.import_accounts({"a": 10000, "b": 0}):
		_fail("seed")
		return
	for i in range(70):
		if not root.transfer("seed_%d" % i, "a", "b", 1, i, "trade").get("ok", false):
			_fail("seed payment")
			return
	var before: Dictionary = root.snapshot()
	var child = root.fork()
	var sibling = root.fork()
	for i in range(70, 135):
		if not child.transfer("child_%d" % i, "a", "b", 1, i, "trade").get("ok", false):
			_fail("child payment")
			return
		if i % 3 == 0 and not root.transfer("parent_%d" % i, "a", "b", 2, i, "trade").get("ok", false):
			_fail("parent payment")
			return
	if child.transfer("child_70", "a", "b", 1, 140, "trade").get("ok", false):
		_fail("duplicate accepted")
		return
	if child.transfer("unfunded", "a", "b", 20000, 140, "trade").get("ok", false):
		_fail("unfunded accepted")
		return
	if sibling.snapshot() != before:
		_fail("sibling history changed")
		return
	for ledger in [root, child, sibling]:
		var delta: Dictionary = ledger.snapshot()
		var oracle = Ledger.new()
		if not oracle.restore(delta) or oracle.snapshot() != delta:
			_fail("N38 restore oracle")
			return
		# Rebuild without the delta shortcut, compare complete receipt order.
		ledger.set("_flat_cache_count", -1)
		ledger.set("_flat_receipt_cache", {})
		ledger.set("_flat_delta_base", {})
		ledger.set("_flat_delta_base_count", -1)
		ledger.set("_flat_pending_ids", [])
		if ledger.snapshot() != delta or not ledger.audit_receipt_index():
			_fail("full scan parity")
			return
		delta["receipts"]["seed_0"]["legs"][0]["delta"] = -900
		if ledger.receipt_copy("seed_0")["legs"][0]["delta"] != -1:
			_fail("external mutable alias")
			return
	if root.receipt_count() != 92 or child.receipt_count() != 135 or sibling.receipt_count() != 70:
		_fail("receipt count or rejected operation")
		return
	print("P2_PERF_B_N9_FLAT_CACHE_DELTA_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_N9_FLAT_CACHE_DELTA_FAIL: " + reason)
	quit(1)
