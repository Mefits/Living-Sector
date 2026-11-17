extends SceneTree
## Negative regression: a detached balances-only view cannot mutate N9.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	assert(ledger.import_accounts({"a": 100, "b": 0}))
	var detached: Dictionary = ledger.balances_snapshot()
	assert(detached == {"a": 100, "b": 0})
	detached["a"] = 0
	detached["b"] = 999
	detached["injected"] = 42
	assert(ledger.balance("a") == 100)
	assert(ledger.balance("b") == 0)
	assert(ledger.balance("injected") == -1)
	var payment: Dictionary = ledger.transfer("b-scalar-copy-1", "a", "b", 25, 1, "test")
	assert(payment.get("ok", false))
	assert(ledger.balance("a") == 75)
	assert(ledger.balance("b") == 25)
	assert(detached["a"] == 0 and detached["b"] == 999)
	var after: Dictionary = ledger.balances_snapshot()
	assert(after == {"a": 75, "b": 25})
	after.clear()
	assert(ledger.balance("a") == 75 and ledger.balance("b") == 25)
	assert(ledger.has_receipt("b-scalar-copy-1"))
	print("PASS p2_perf_b_balances_snapshot_scalar_isolation")
	quit()
