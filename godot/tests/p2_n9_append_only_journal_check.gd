extends SceneTree
## II-A immutable receipt journal: fork must preserve exact historical
## insertion order, independently staged money, and N38 v1 wire format.
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var original := Bank.new()
	if not original.import_accounts({"facility/first": 25000,
			"facility/second": 5000, "ship:actual": 2000}):
		_fail("accounts rejected")
		return
	var order: Array = []
	for i in range(320):
		var id: String = "paid:%04d" % i
		var a: String = "facility/first" if i % 2 == 0 else "facility/second"
		var b: String = "facility/second" if i % 2 == 0 else "facility/first"
		var transfer: Dictionary = original.transfer(id, a, b, 1, i + 1, "actual_paid")
		if not transfer.get("ok", false):
			_fail("genuine receipt cannot be appended: " + str(i))
			return
		order.append(id)
	var before: Dictionary = original.snapshot()
	if before["receipts"].keys() != order or original.receipt_count() != 320:
		_fail("original receipt insertion order changed")
		return
	var a: RefCounted = original.fork()
	var b: RefCounted = original.fork()
	if a.snapshot() != before or b.snapshot() != before:
		_fail("fork not independent at source checkpoint")
		return
	var receipt_a: Dictionary = a.transfer("fork:one", "facility/first",
		"facility/second", 7, 321, "actual_paid")
	var receipt_b: Dictionary = b.transfer("fork:two", "facility/second",
		"facility/first", 3, 321, "actual_paid")
	if not receipt_a.get("ok", false) or not receipt_b.get("ok", false):
		_fail("independent forks failed paid settlements")
		return
	if original.snapshot() != before or original.has_receipt("fork:one") or (
			original.has_receipt("fork:two") or b.has_receipt("fork:one") or
			a.has_receipt("fork:two")):
		_fail("staged receipt leaked into another authoritative fork")
		return
	var after_a: Dictionary = a.snapshot()
	if after_a["receipts"].keys() != order + ["fork:one"] or (
			not original.retains_receipts(after_a["receipts"])):
		_fail("historical ordered append or provenance broken")
		return
	var before_fail: Dictionary = a.snapshot()
	var duplicate: Dictionary = a.transfer("paid:0000",
		"facility/first", "facility/second", 1, 322, "actual_paid")
	var unfunded: Dictionary = a.transfer("unfunded",
		"ship:actual", "facility/first", 999999, 322, "actual_paid")
	if duplicate.get("ok", true) or unfunded.get("ok", true) or (
			a.snapshot() != before_fail):
		_fail("replayed or unfunded operation mutated staged money")
		return
	var hacked: Dictionary = after_a["receipts"].duplicate(true)
	hacked["paid:0001"]["legs"][0]["delta"] = -1234
	if original.retains_receipts(hacked):
		_fail("previous receipt edit was not detected")
		return
	var deleted: Dictionary = after_a["receipts"].duplicate(true)
	deleted.erase("paid:0001")
	if original.retains_receipts(deleted):
		_fail("historical receipt deletion was not detected")
		return
	var untrusted := Bank.new()
	if not untrusted.restore(after_a) or untrusted.snapshot() != after_a:
		_fail("N38 full restore changed receipt order or balances")
		return
	var exposed: Dictionary = untrusted.snapshot()
	exposed["receipts"]["paid:0001"]["legs"][0]["delta"] = 100
	exposed["balances"]["facility/first"] = -900
	if untrusted.snapshot() != after_a:
		_fail("untrusted snapshot gave access to private journal")
		return
	var wage: Dictionary = a.pay_native_ship_crew("crew:paid",
		"ship:actual", "actual", 5, 323)
	if not wage.get("ok", false) or a.balance("ship:actual") != 1995 or (
			a.snapshot()["receipts"].keys() != order + ["fork:one", "crew:paid"]):
		_fail("crew wage receipt not in original append-only order")
		return
	var closed: Dictionary = a.close_removed_entity_account("close:ship",
		"ship:actual", 324, "ship_decommissioned")
	if not closed.get("ok", false) or a.balance("ship:actual") != -1 or (
			a.snapshot()["receipts"].keys() != order +
				["fork:one", "crew:paid", "close:ship"]):
		_fail("N9 write-off receipt or removed wallet lost")
		return
	if original.snapshot() != before or b.snapshot()["receipts"].keys() != (
			order + ["fork:two"]):
		_fail("late append mutated independent historical fork")
		return
	print("P2_N9_APPEND_ONLY_JOURNAL_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_N9_APPEND_ONLY_JOURNAL_FAIL: " + reason)
	quit(1)
