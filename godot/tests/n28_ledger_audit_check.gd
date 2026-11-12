extends SceneTree
## CODE_UNVERIFIED: godot --headless --path godot --script res://tests/n28_ledger_audit_check.gd
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Auditor = preload("res://scripts/sim/economy/ledger_audit.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var original := {"facility:a": 100, "household:p": 0, "faction:f": 50, "escrow:c": 0}
	var ledger = Ledger.new()
	_check(ledger.import_accounts(original), "seed accounts")
	_check(ledger.transfer("wage:1", "facility:a", "household:p", 7, 1, "wage").get("ok", false), "wage")
	_check(ledger.transfer("fund:1", "faction:f", "escrow:c", 20, 2, "funding").get("ok", false), "escrow")
	var audit = Auditor.new()
	var snapshot = ledger.snapshot()
	var before = snapshot.duplicate(true)
	var clean = audit.reconcile(original, snapshot)
	_check(clean["ok"] and clean["initial_total"] == 150 and clean["actual_total"] == 150, "clean audit")
	_check(snapshot == before and audit.reconcile(original, snapshot) == clean, "read only deterministic")
	var restored = Ledger.new()
	_check(restored.restore(snapshot), "restore")
	_check(audit.reconcile(original, restored.snapshot())["ok"], "restore parity")
	var forged = snapshot.duplicate(true)
	forged["balances"]["facility:a"] = 94
	_check(not audit.reconcile(original, forged)["ok"], "detect balance forgery")
	var missing = snapshot.duplicate(true)
	missing["receipts"].erase("wage:1")
	_check(not audit.reconcile(original, missing)["ok"], "detect missing receipt")
	var unbalanced = snapshot.duplicate(true)
	unbalanced["receipts"]["wage:1"]["legs"][1]["delta"] = 6
	_check(not audit.reconcile(original, unbalanced)["ok"], "detect unbalanced receipt")
	var invalid = snapshot.duplicate(true)
	invalid["receipts"]["fund:1"]["tick"] = -1
	_check(not audit.reconcile(original, invalid)["ok"], "detect corrupt metadata")
	if failures.is_empty():
		print("N28_LEDGER_AUDIT_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
