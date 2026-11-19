extends SceneTree
## B-only negative provenance regression. Does not need an N39 World.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	var first: Dictionary = ledger.transfer("paid-1", "buyer", "seller", 17, 3, "trade")
	if not first.get("ok", false):
		_fail("payment")
		return
	var saved: Dictionary = ledger.snapshot()
	var forked = ledger.fork()
	var copy: Dictionary = ledger.receipt_copy("paid-1")
	if copy != saved["receipts"]["paid-1"]:
		_fail("receipt mismatch")
		return
	copy["kind"] = "forged"
	copy["legs"][0]["delta"] = -999
	if ledger.receipt_copy("paid-1") != saved["receipts"]["paid-1"]:
		_fail("mutable alias to receipt shard")
		return
	if not ledger.receipt_copy("absent").is_empty() or not ledger.receipt_copy("").is_empty():
		_fail("unknown operation accepted")
		return
	var duplicate: Dictionary = ledger.transfer("paid-1", "buyer", "seller", 17, 4, "trade")
	if duplicate.get("ok", false) or duplicate.get("reason") != "duplicate_operation":
		_fail("replay accepted")
		return
	if not forked.transfer("paid-2", "buyer", "seller", 9, 4, "trade").get("ok", false):
		_fail("fork append")
		return
	if ledger.has_receipt("paid-2") or ledger.balance("buyer") != 83:
		_fail("fork leaked into parent")
		return
	if not forked.receipt_copy("paid-1") == saved["receipts"]["paid-1"]:
		_fail("fork lost immutable ancestor")
		return
	var restored = Ledger.new()
	if not restored.restore(saved) or restored.receipt_copy("paid-1") != saved["receipts"]["paid-1"]:
		_fail("restore provenance")
		return
	var invalid: Dictionary = saved.duplicate(true)
	invalid["receipts"]["paid-1"]["id"] = "tampered"
	if restored.restore(invalid):
		_fail("tampered receipt accepted")
		return
	if restored.receipt_copy("paid-1") != saved["receipts"]["paid-1"]:
		_fail("failed restore modified authoritative receipt")
		return
	print("P2_PERF_B_RECEIPT_LOOKUP_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_LOOKUP_FAIL: " + reason)
	quit(1)
