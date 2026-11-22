extends SceneTree
## Targeted N9 paid-fork regression: shallow wallet dictionary copy must not
## alias balances or receipts across parent/child/grandchild and N38 restore.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var root = Ledger.new()
	assert(root.import_accounts({"ship:a": 100, "station:b": 0}))
	var first = root.fork()
	assert(first.balance("ship:a") == 100)
	assert(first.transfer("pay:1", "ship:a", "station:b", 30, 1, "trade").get("ok"))
	assert(root.balance("ship:a") == 100)
	assert(root.balance("station:b") == 0)
	assert(not root.has_receipt("pay:1"))
	assert(first.balance("ship:a") == 70)
	assert(first.balance("station:b") == 30)
	var second = first.fork()
	assert(second.transfer("pay:2", "station:b", "ship:a", 10, 2, "trade").get("ok"))
	assert(first.balance("ship:a") == 70)
	assert(second.balance("ship:a") == 80)
	assert(not first.has_receipt("pay:2"))
	assert(not second.transfer("pay:2", "station:b", "ship:a", 10, 2, "trade").get("ok"))
	assert(second.retains_owned_receipts(first))
	var snapshot: Dictionary = second.snapshot()
	var restored = Ledger.new()
	assert(restored.restore(snapshot))
	assert(restored.snapshot() == snapshot)
	snapshot["balances"]["ship:a"] = 9999
	snapshot["receipts"]["pay:1"]["legs"][0]["delta"] = -9999
	assert(restored.balance("ship:a") == 80)
	assert(restored.receipt_copy("pay:1")["legs"][0]["delta"] == -30)
	assert(root.balance("ship:a") == 100)
	print("PASS p2_perf_b_fork_wallet_shallow_20261117")
	quit(0)
