extends SceneTree
## Astra II-A: every N9 paid/write-off receipt must publish an immutable
## record and a separately detached public proof; failed writes are atomic.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"a": 100, "b": 0, "ship:s1": 20,
		"facility/f1": 13}))
	var legs: Array = [{"account": "a", "delta": -9},
		{"account": "b", "delta": 9}]
	var paid: Dictionary = ledger.commit("paid:1", legs, 1, "trade")
	assert(paid.get("ok", false))
	var original: Dictionary = ledger.receipt_copy("paid:1")
	legs[0]["delta"] = -999
	paid["receipt"]["legs"][1]["delta"] = 999
	assert(ledger.receipt_copy("paid:1") == original)
	assert(ledger.balance("a") == 91 and ledger.balance("b") == 9)
	var after_paid: Dictionary = ledger.snapshot()
	assert(not ledger.commit("paid:1", [
		{"account": "a", "delta": -1},
		{"account": "b", "delta": 1}], 2, "trade").get("ok", false))
	assert(not ledger.transfer("unfunded", "b", "a", 100, 2, "trade").get("ok", false))
	assert(ledger.snapshot() == after_paid)
	var child = ledger.fork()
	var wage: Dictionary = child.pay_native_ship_crew("wage:1", "ship:s1", "s1", 7, 2)
	assert(wage.get("ok", false))
	var wage_original: Dictionary = child.receipt_copy("wage:1")
	wage["receipt"]["legs"][0]["delta"] = -999
	assert(child.receipt_copy("wage:1") == wage_original)
	assert(child.balance("ship:s1") == 13)
	var removed: Dictionary = child.close_removed_entity_account(
		"remove:1", "facility/f1", 3, "facility_removed")
	assert(removed.get("ok", false))
	var removed_original: Dictionary = child.receipt_copy("remove:1")
	removed["receipt"]["legs"][0]["delta"] = -999
	assert(child.receipt_copy("remove:1") == removed_original)
	assert(child.balance("facility/f1") == -1)
	assert(not child.close_removed_entity_account(
		"remove:2", "facility/f1", 4, "facility_removed").get("ok", false))
	assert(not child.pay_native_ship_crew(
		"wage:2", "ship:s1", "s1", 100, 4).get("ok", false))
	assert(ledger.snapshot() == after_paid)
	var checkpoint: Dictionary = child.snapshot()
	var restored = Ledger.new()
	assert(restored.restore(checkpoint))
	assert(restored.snapshot() == checkpoint)
	assert(restored.audit_receipt_index())
	checkpoint["receipts"]["paid:1"]["legs"][0]["delta"] = -1234
	assert(restored.receipt_copy("paid:1") == original)
	assert(restored.audit_receipt_index())
	print("PASS p2_perf_b_receipt_atomicity")
	quit(0)
