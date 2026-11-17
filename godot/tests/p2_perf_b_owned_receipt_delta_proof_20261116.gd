extends SceneTree
## Direct-fork receipt proof must match the exhaustive old-receipt oracle.
## Covers changed shard, parent append, same-count restore and unrelated fork.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var parent = Ledger.new()
	if not parent.import_accounts({"a": 500, "b": 0}):
		_fail("accounts")
		return
	for i in range(40):
		if not parent.transfer("seed-%d" % i, "a", "b", 1, i, "trade").get("ok", false):
			_fail("seed transfer")
			return
	var child = parent.fork()
	if not child.retains_owned_receipts(parent):
		_fail("unchanged fork")
		return
	if not child.transfer("child-only", "a", "b", 2, 41, "trade").get("ok", false):
		_fail("child append")
		return
	if not child.retains_owned_receipts(parent) or parent.has_receipt("child-only"):
		_fail("changed shard provenance or alias")
		return
	var before: Dictionary = child.snapshot()
	if not parent.transfer("parent-only", "a", "b", 3, 42, "trade").get("ok", false):
		_fail("parent append")
		return
	# Parent generation changed, so the original exhaustive proof must run.
	if child.retains_owned_receipts(parent):
		_fail("parent changed but child claimed all receipts")
		return
	if child.snapshot() != before:
		_fail("parent mutated child")
		return
	var restored = Ledger.new()
	if not restored.restore(before) or restored.snapshot() != before:
		_fail("restore exact")
		return
	if restored.retains_owned_receipts(child):
		_fail("untrusted restored history accepted")
		return
	var fork2 = child.fork()
	var replacement: Dictionary = child.snapshot()
	if not child.restore(replacement):
		_fail("same-count parent restore")
		return
	if fork2.retains_owned_receipts(child):
		_fail("same-count restore bypassed identity oracle")
		return
	# A forged replacement row must be rejected by the full proof oracle.
	var forged: Dictionary = replacement.duplicate(true)
	forged["receipts"]["seed-0"]["legs"][0]["delta"] = -99
	var tampered = Ledger.new()
	if not tampered.restore(forged):
		_fail("tamper fixture restore")
		return
	if tampered.retains_owned_receipts(child):
		_fail("tampered receipt accepted")
		return
	if not parent.audit_receipt_index() or not child.audit_receipt_index():
		_fail("index")
		return
	print("P2_PERF_B_OWNED_RECEIPT_DELTA_PROOF_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_OWNED_RECEIPT_DELTA_PROOF_FAIL: " + reason)
	quit(1)
