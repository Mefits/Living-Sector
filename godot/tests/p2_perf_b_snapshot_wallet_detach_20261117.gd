extends SceneTree
## N9 snapshot wallet-copy regression: detached i64 balances, immutable
## receipt history, N38 v1 restore and failed duplicate payment.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var accounts: Dictionary = {"ship:a": 1000, "station:b": 0}
	for i in range(512):
		accounts["wallet:%d" % i] = i
	var ledger = Ledger.new()
	assert(ledger.import_accounts(accounts))
	assert(ledger.transfer("paid:1", "ship:a", "station:b", 25, 7, "trade").get("ok"))
	var exported: Dictionary = ledger.snapshot()
	assert(exported["version"] == 1)
	assert(exported["balances"].size() == accounts.size())
	assert(exported["balances"]["ship:a"] == 975)
	var restored = Ledger.new()
	assert(restored.restore(exported))
	assert(restored.snapshot() == exported)
	exported["balances"]["ship:a"] = 9000
	exported["balances"]["wallet:511"] = -1
	exported["receipts"]["paid:1"]["legs"][0]["delta"] = -999
	assert(ledger.balance("ship:a") == 975)
	assert(restored.balance("ship:a") == 975)
	assert(ledger.balance("wallet:511") == 511)
	assert(restored.balance("wallet:511") == 511)
	assert(ledger.receipt_copy("paid:1")["legs"][0]["delta"] == -25)
	assert(restored.receipt_copy("paid:1")["legs"][0]["delta"] == -25)
	assert(not restored.transfer("paid:1", "ship:a", "station:b", 25, 8, "trade").get("ok"))
	assert(not Ledger.new().restore(exported))
	assert(ledger.snapshot()["balances"]["ship:a"] == 975)
	print("PASS p2_perf_b_snapshot_wallet_detach_20261117")
	quit(0)
