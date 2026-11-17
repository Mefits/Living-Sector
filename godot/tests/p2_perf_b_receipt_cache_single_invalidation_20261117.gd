extends SceneTree
## Negative regression: repeated paid appends must not retain an obsolete
## full-history cache or expose mutable receipt rows across snapshots/forks.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	if not ledger.transfer("first", "buyer", "seller", 5, 1, "trade").get("ok", false):
		_fail("first payment")
		return
	var old: Dictionary = ledger.snapshot()
	if ledger.get("_flat_cache_count") != 1:
		_fail("initial cache not materialized")
		return
	var sibling = ledger.fork()
	if not ledger.transfer("second", "buyer", "seller", 7, 2, "trade").get("ok", false):
		_fail("second payment")
		return
	if ledger.get("_flat_cache_count") != -1 or not (ledger.get("_flat_receipt_cache") as Dictionary).is_empty():
		_fail("stale receipt cache retained after first invalidation")
		return
	if not ledger.transfer("third", "buyer", "seller", 9, 3, "trade").get("ok", false):
		_fail("third payment")
		return
	if ledger.get("_flat_cache_count") != -1 or not (ledger.get("_flat_receipt_cache") as Dictionary).is_empty():
		_fail("cache reappeared without snapshot")
		return
	if old["receipts"].size() != 1 or sibling.receipt_count() != 1:
		_fail("fork or old snapshot mutated")
		return
	var now: Dictionary = ledger.snapshot()
	if now["receipts"].size() != 3 or ledger.get("_flat_cache_count") != 3:
		_fail("rebuild missed committed receipts")
		return
	if ledger.transfer("third", "buyer", "seller", 1, 4, "trade").get("ok", false):
		_fail("duplicate accepted")
		return
	if ledger.snapshot() != now or not ledger.audit_receipt_index():
		_fail("duplicate mutated ledger or index")
		return
	var restored = Ledger.new()
	if not restored.restore(now) or restored.snapshot() != now:
		_fail("exact N9 restore")
		return
	now["receipts"]["first"]["legs"][0]["delta"] = -999
	if ledger.receipt_copy("first")["legs"][0]["delta"] != -5:
		_fail("external snapshot alias")
		return
	print("P2_PERF_B_RECEIPT_CACHE_SINGLE_INVALIDATION_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_CACHE_SINGLE_INVALIDATION_FAIL: " + reason)
	quit(1)
