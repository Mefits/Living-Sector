extends SceneTree
## Astra II-A: final N9 wallet staging must preserve atomic multi-leg commits,
## repeated accounts, i64 limits, duplicate IDs and detached N38 snapshots.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const MAX_CREDITS: int = 9223372036854775807

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"a": 100, "b": 40, "c": 0}))
	var before: Dictionary = ledger.snapshot()
	# A late failing wallet must not publish earlier staged wallets or receipts.
	var failed: Dictionary = ledger.commit("fail:funds", [
		{"account": "a", "delta": -20},
		{"account": "c", "delta": 120},
		{"account": "b", "delta": -100}], 1, "trade")
	assert(not failed.get("ok", false))
	assert(failed.get("reason") == "insufficient_funds")
	assert(ledger.snapshot() == before)
	# Repeated account IDs are aggregated before funding validation.
	var legs: Array = [
		{"account": "a", "delta": -30},
		{"account": "a", "delta": 10},
		{"account": "b", "delta": -10},
		{"account": "c", "delta": 30}]
	assert(ledger.commit("pay:1", legs, 2, "trade").get("ok"))
	assert(ledger.balance("a") == 80)
	assert(ledger.balance("b") == 30)
	assert(ledger.balance("c") == 30)
	var paid: Dictionary = ledger.snapshot()
	legs[0]["delta"] = -999
	assert(ledger.receipt_copy("pay:1")["legs"][0]["delta"] == -30)
	assert(not ledger.commit("pay:1", [
		{"account": "a", "delta": -1},
		{"account": "b", "delta": 1}], 3, "trade").get("ok"))
	assert(ledger.snapshot() == paid)
	var restored = Ledger.new()
	assert(restored.restore(paid))
	assert(restored.snapshot() == paid)
	var child = restored.fork()
	assert(child.transfer("pay:2", "c", "a", 5, 4, "trade").get("ok"))
	assert(restored.snapshot() == paid)
	assert(child.balance("a") == 85)
	assert(child.balance("c") == 25)
	# Overflow on the second wallet must reject the entire staged batch.
	var near = Ledger.new()
	assert(near.import_accounts({"a": 1, "b": MAX_CREDITS}))
	var near_before: Dictionary = near.snapshot()
	assert(not near.transfer("overflow", "a", "b", 1, 5, "trade").get("ok"))
	assert(near.snapshot() == near_before)
	print("PASS p2_perf_b_paid_staged_wallet_atomic_20261118")
	quit(0)
