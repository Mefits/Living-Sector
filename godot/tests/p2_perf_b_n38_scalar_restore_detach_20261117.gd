extends SceneTree
## Negative N38 regression: restored scalar wallets must not alias untrusted
## source dictionaries, and failed restore must leave authoritative N9 intact.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var source = Ledger.new()
	if not source.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	if not source.transfer("paid-1", "buyer", "seller", 17, 1, "trade").get("ok", false):
		_fail("paid seed")
		return
	var checkpoint: Dictionary = source.snapshot()
	var restored = Ledger.new()
	if not restored.restore(checkpoint) or restored.snapshot() != checkpoint:
		_fail("exact N9 roundtrip")
		return
	# Caller mutation of the original untrusted N38 balances cannot modify
	# the restored wallet map after the scalar-only shallow duplication.
	(checkpoint["balances"] as Dictionary)["buyer"] = 999
	if restored.balance("buyer") != 83 or restored.balance("seller") != 17:
		_fail("wallet alias")
		return
	var baseline: Dictionary = restored.snapshot()
	var corrupted: Dictionary = baseline.duplicate(true)
	(corrupted["balances"] as Dictionary)["buyer"] = -1
	if restored.restore(corrupted) or restored.snapshot() != baseline:
		_fail("failed restore mutated state")
		return
	var fork = restored.fork()
	if not fork.transfer("paid-2", "buyer", "seller", 3, 2, "trade").get("ok", false):
		_fail("post-restore paid fork")
		return
	if restored.snapshot() != baseline or restored.has_receipt("paid-2"):
		_fail("fork alias after restore")
		return
	if fork.transfer("paid-2", "buyer", "seller", 3, 2, "trade").get("ok", false):
		_fail("duplicate receipt")
		return
	print("P2_PERF_B_N38_SCALAR_RESTORE_DETACH_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_N38_SCALAR_RESTORE_DETACH_FAIL " + reason)
	quit(1)
