extends SceneTree
## Paid source-style N9 commits, same version-1 ledger on both branches.
## Measures repeated trusted fork + isolated paid transfer at increasing
## receipt history size; does not count archive creation or N38 export.
const Bank = preload("res://scripts/sim/economy/credit_ledger.gd")
const TARGETS: Array[int] = [250, 1000, 4000]
const FORKS: int = 45

func _initialize() -> void:
	var ledger := Bank.new()
	if not ledger.import_accounts({"facility/a": 100000,
			"facility/b": 100000, "ship:c": 100000}):
		_fail("initial funds rejected")
		return
	var number: int = 0
	for target in TARGETS:
		while number < target:
			var payer: String = "facility/a" if number % 2 == 0 else "facility/b"
			var payee: String = "facility/b" if number % 2 == 0 else "facility/a"
			var paid: Dictionary = ledger.transfer("paid:%06d" % number,
				payer, payee, 1, number + 1, "native_trade")
			if not paid.get("ok", false):
				_fail("source journal setup failed at " + str(number))
				return
			number += 1
		var before: int = ledger.total()
		var started: int = Time.get_ticks_usec()
		for k in range(FORKS):
			var stage: RefCounted = ledger.fork()
			var id: String = "probe:%d:%d" % [target, k]
			var result: Dictionary = stage.transfer(id,
				"facility/a", "facility/b", 2, target + 1, "native_trade")
			if not result.get("ok", false) or not stage.has_receipt(id) or (
					ledger.has_receipt(id)):
				_fail("owned fork settlement affected the original")
				return
		var elapsed: int = Time.get_ticks_usec() - started
		if ledger.receipt_count() != target or ledger.total() != before:
			_fail("benchmark changed authoritative original N9")
			return
		print("N9_FORK_SCALE_RESULT receipts=" + str(target) +
			" forks=" + str(FORKS) + " elapsed_usec=" + str(elapsed))
	print("N9_FORK_SCALE_BENCH_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("N9_FORK_SCALE_BENCH_FAIL: " + reason)
	quit(1)
