extends SceneTree
## CODE_UNVERIFIED. Run: godot --headless --path godot --script res://tests/n11_ledger_check.gd
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var ledger = Ledger.new()
	_check(ledger.import_accounts({"facility:a": 100, "household:p": 0, "faction:f": 40, "escrow:c": 0}), "import native accounts")
	var initial = ledger.total()
	_check(ledger.transfer("wage:1", "facility:a", "household:p", 5, 1, "wage").get("ok", false), "wage paid")
	_check(ledger.balance("facility:a") == 95 and ledger.balance("household:p") == 5, "wage balances")
	_check(not ledger.transfer("wage:1", "facility:a", "household:p", 5, 1, "wage").get("ok", false), "idempotent wage")
	_check(not ledger.transfer("too-much", "facility:a", "household:p", 96, 1, "wage").get("ok", false), "insufficient payroll")
	_check(ledger.transfer("reserve:1", "faction:f", "escrow:c", 20, 2, "contract_fund").get("ok", false), "escrow funding")
	_check(ledger.transfer("refund:1", "escrow:c", "faction:f", 20, 3, "contract_refund").get("ok", false), "escrow refund")
	_check(not ledger.commit("unbalanced", [{"account": "facility:a", "delta": -5}, {"account": "household:p", "delta": 4}], 4, "invalid").get("ok", false), "reject money creation/destruction")
	_check(ledger.total() == initial, "global money conserved")
	var saved = ledger.snapshot()
	var restored = Ledger.new()
	_check(restored.restore(saved), "restore snapshot")
	_check(restored.total() == initial and restored.has_receipt("wage:1"), "receipt persisted")
	_check(not restored.transfer("wage:1", "facility:a", "household:p", 5, 4, "wage").get("ok", false), "idempotence after restore")
	_check(not restored.restore({"version": 1, "balances": {"bad": -1}, "receipts": {}}), "reject corrupt balances")
	_check(restored.total() == initial, "failed restore atomic")
	if failures.is_empty():
		print("N11_LEDGER_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
