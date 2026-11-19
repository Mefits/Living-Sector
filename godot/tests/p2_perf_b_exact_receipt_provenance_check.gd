extends SceneTree
## B: exact bounded provenance must reject omitted metadata, tampering,
## duplicate IDs and missing IDs without mutating N9 or copying history.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"wallet:a": 100, "wallet:b": 0}))
	var paid: Dictionary = ledger.transfer(
		"paid:1", "wallet:a", "wallet:b", 17, 4, "purchase")
	assert(paid.get("ok", false))
	var original: Dictionary = paid["receipt"]
	assert(ledger.verify_exact_operation_receipts([original]))
	assert(not ledger.verify_exact_operation_receipts([]))
	assert(not ledger.verify_exact_operation_receipts([original, original]))
	var missing: Dictionary = original.duplicate(true)
	missing["id"] = "paid:missing"
	assert(not ledger.verify_exact_operation_receipts([missing]))
	var omitted: Dictionary = original.duplicate(true)
	omitted.erase("kind")
	assert(not ledger.verify_exact_operation_receipts([omitted]))
	var forged: Dictionary = original.duplicate(true)
	forged["tick"] = 5
	assert(not ledger.verify_exact_operation_receipts([forged]))
	var extra: Dictionary = original.duplicate(true)
	extra["provenance"] = "forged"
	assert(not ledger.verify_exact_operation_receipts([extra]))
	var alias: Dictionary = ledger.receipt_copy("paid:1")
	alias["legs"][0]["delta"] = -999
	assert(not ledger.verify_exact_operation_receipts([alias]))
	assert(ledger.verify_exact_operation_receipts([original]))
	assert(ledger.balance("wallet:a") == 83)
	assert(ledger.balance("wallet:b") == 17)
	assert(ledger.receipt_count() == 1)
	assert(ledger.audit_receipt_index())
	var child = ledger.fork()
	assert(child.verify_exact_operation_receipts([original]))
	assert(child.transfer("paid:2", "wallet:a", "wallet:b", 1, 5,
		"purchase").get("ok", false))
	assert(not ledger.has_receipt("paid:2"))
	assert(ledger.verify_exact_operation_receipts([original]))
	print("P2_PERF_B_EXACT_RECEIPT_PROVENANCE_PASS")
	quit(0)
