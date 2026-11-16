extends SceneTree
## B negative regression: the optimized N9 append stores a private receipt
## without duplicating it twice. Public result, caller legs, forks and N38
## snapshots must remain detached, including nested caller metadata.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 200, "seller": 0}):
		_fail("seed")
		return
	var legs: Array = [
		{"account": "buyer", "delta": -17, "metadata": {"tags": ["original"]}},
		{"account": "seller", "delta": 17}
	]
	var result: Dictionary = ledger.commit("paid-1", legs, 3, "trade")
	if not result.get("ok", false):
		_fail("commit")
		return
	var forked = ledger.fork()
	var original: Dictionary = ledger.snapshot()
	if original["receipts"]["paid-1"]["legs"][0]["metadata"]["tags"] != ["original"]:
		_fail("original metadata")
		return
	# Both the caller's nested data and the returned detached receipt are
	# untrusted; mutating them must never alter the private append row.
	legs[0]["metadata"]["tags"].append("caller-mutated")
	result["receipt"]["legs"][0]["metadata"]["tags"].append("result-mutated")
	result["receipt"]["id"] = "forged"
	if ledger.snapshot() != original or forked.snapshot() != original:
		_fail("mutable alias leaked to ledger or fork")
		return
	if not forked.transfer("paid-2", "buyer", "seller", 4, 4, "trade").get("ok", false):
		_fail("fork transfer")
		return
	if ledger.has_receipt("paid-2") or not forked.has_receipt("paid-2"):
		_fail("fork isolation")
		return
	var snapshot: Dictionary = forked.snapshot()
	snapshot["receipts"]["paid-1"]["legs"][0]["metadata"]["tags"].append("snapshot-mutated")
	if forked.snapshot()["receipts"]["paid-1"]["legs"][0]["metadata"]["tags"] != ["original"]:
		_fail("snapshot mutable alias")
		return
	var restored = Ledger.new()
	if not restored.restore(forked.snapshot()) or not restored.audit_receipt_index():
		_fail("N38 restore or receipt index")
		return
	if restored.snapshot() != forked.snapshot():
		_fail("roundtrip")
		return
	if ledger.balance("buyer") != 183 or forked.balance("buyer") != 179:
		_fail("balance")
		return
	if ledger.transfer("paid-1", "buyer", "seller", 1, 5, "trade").get("ok", false):
		_fail("duplicate operation replay")
		return
	print("P2_PERF_B_PRIVATE_RECEIPT_APPEND_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_PRIVATE_RECEIPT_APPEND_FAIL: " + reason)
	quit(1)
