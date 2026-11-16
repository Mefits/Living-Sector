extends SceneTree
## B-only exact per-kind provenance aggregate; no N39 World or N38 format changes.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0, "ship:s1": 30}):
		_fail("seed")
		return
	if not ledger.transfer("trade-1", "buyer", "seller", 17, 3, "trade").get("ok", false):
		_fail("trade")
		return
	if not ledger.transfer("trade-2", "buyer", "seller", 9, 4, "trade").get("ok", false):
		_fail("second trade")
		return
	if not ledger.pay_native_ship_crew("crew-1", "ship:s1", "s1", 5, 5).get("ok", false):
		_fail("crew")
		return
	if not _counts(ledger, 2, 1, 3):
		_fail("initial counts")
		return
	var baseline: Dictionary = ledger.snapshot()
	var forked = ledger.fork()
	if not forked.transfer("trade-3", "buyer", "seller", 3, 6, "trade").get("ok", false):
		_fail("fork transfer")
		return
	if not _counts(forked, 3, 1, 4) or not _counts(ledger, 2, 1, 3):
		_fail("fork counter alias")
		return
	if not ledger.close_removed_entity_account("closed-1", "ship:s1", 7, "ship_decommissioned").get("ok", false):
		_fail("close wallet")
		return
	if ledger.receipt_kind_count("ship_decommissioned") != 1 or ledger.receipt_kind_count("trade") != 2:
		_fail("writeoff aggregate")
		return
	if forked.receipt_kind_count("ship_decommissioned") != 0:
		_fail("parent counter leaked to fork")
		return
	var restored = Ledger.new()
	if not restored.restore(baseline) or not _counts(restored, 2, 1, 3):
		_fail("restore counters")
		return
	var tampered: Dictionary = baseline.duplicate(true)
	tampered["receipts"]["trade-1"]["id"] = "wrong"
	if restored.restore(tampered):
		_fail("tampered restore accepted")
		return
	if not _counts(restored, 2, 1, 3) or restored.snapshot() != baseline:
		_fail("failed restore changed counts or history")
		return
	if ledger.transfer("trade-1", "buyer", "seller", 1, 8, "trade").get("ok", false):
		_fail("duplicate accepted")
		return
	if ledger.receipt_kind_count("trade") != 2:
		_fail("duplicate changed aggregate")
		return
	var legacy = Ledger.new()
	if not legacy.restore({"version": 1, "balances": {"buyer": 5},
			"receipts": {"legacy": {"id": "legacy", "legs": []}}}):
		_fail("legacy missing-kind receipt rejected")
		return
	if legacy.receipt_count() != 1 or legacy.receipt_kind_count("trade") != 0:
		_fail("legacy missing-kind aggregate")
		return
	print("P2_PERF_B_RECEIPT_KIND_INDEX_PASS")
	quit(0)

func _counts(ledger: RefCounted, trades: int, crews: int, total: int) -> bool:
	return ledger.receipt_kind_count("trade") == trades and \
		ledger.receipt_kind_count("native_ship_crew_wages") == crews and \
		ledger.receipt_kind_count("missing") == 0 and \
		ledger.receipt_kind_count("") == 0 and ledger.receipt_count() == total

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_KIND_INDEX_FAIL: " + reason)
	quit(1)
