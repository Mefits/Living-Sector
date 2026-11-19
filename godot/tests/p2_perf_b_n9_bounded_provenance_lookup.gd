extends SceneTree
## Astra II-A B: bounded N9 provenance lookup against the full snapshot oracle.
## Run: godot --headless --path godot --script res://tests/p2_perf_b_n9_bounded_provenance_lookup.gd

const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"a": 100, "b": 0}))
	var legs: Array = [{"account": "a", "delta": -15}, {"account": "b", "delta": 15}]
	var first: Dictionary = ledger.commit("op-1", legs, 3, "trade")
	assert(first.get("ok") == true)
	var second: Dictionary = ledger.commit("op-2", [{"account": "b", "delta": -5},
		{"account": "a", "delta": 5}], 4, "trade")
	assert(second.get("ok") == true)
	var snapshot: Dictionary = ledger.snapshot()
	var oracle: Dictionary = snapshot["receipts"]
	assert(ledger.receipt_copy("op-1") == oracle["op-1"])
	assert(ledger.receipt_copy("missing").is_empty())
	var batch: Dictionary = ledger.receipts_for_operations(["op-2", "op-1"])
	assert(batch.get("ok") == true)
	assert(batch["receipts"]["op-1"] == oracle["op-1"])
	assert(batch["receipts"]["op-2"] == oracle["op-2"])
	assert(ledger.verify_exact_operation_receipts([oracle["op-1"], oracle["op-2"]]))
	assert(ledger.verify_operation_provenance([oracle["op-1"], oracle["op-2"]]))
	var paid: Dictionary = ledger.paid_leg_totals_for_operations(["op-1", "op-2"])
	assert(paid.get("ok") == true)
	assert(paid["debits"] == 20 and paid["credits"] == 20)
	assert(paid["account_deltas"] == {"a": -10, "b": 10})
	# Returned proof must never expose internal receipt storage.
	batch["receipts"]["op-1"]["legs"][0]["delta"] = -999
	assert(ledger.receipt_copy("op-1") == oracle["op-1"])
	assert(not ledger.receipts_for_operations(["op-1", "op-1"]).get("ok"))
	assert(not ledger.receipts_for_operations(["op-1", "missing"]).get("ok"))
	assert(not ledger.receipts_for_operations([""]).get("ok"))
	assert(not ledger.verify_exact_operation_receipts([{"id": "op-1"}]))
	assert(not ledger.verify_exact_operation_receipts([oracle["op-1"], oracle["op-1"]]))
	assert(not ledger.verify_operation_provenance([{"id": "missing",
		"kind": "trade", "tick": 3, "legs": []}]))
	assert(not ledger.paid_leg_totals_for_operations(["op-1", "missing"]).get("ok"))
	assert(not ledger.paid_leg_totals_for_operations(["op-1", "op-1"]).get("ok"))
	# Fork and N38 restore retain the same lookup/proof semantics.
	var forked = ledger.fork()
	assert(forked.receipt_copy("op-1") == oracle["op-1"])
	assert(forked.commit("op-3", [{"account": "a", "delta": -1},
		{"account": "b", "delta": 1}], 5, "trade").get("ok"))
	assert(ledger.receipt_copy("op-3").is_empty())
	var restored = Ledger.new()
	assert(restored.restore(snapshot))
	assert(restored.receipts_for_operations(["op-1", "op-2"])["receipts"] == oracle)
	assert(restored.audit_receipt_index())
	print("PASS: N9 bounded provenance oracle, alias, negatives, fork and restore")
	quit(0)
