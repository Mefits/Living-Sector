extends SceneTree
## Verify committed N9 provenance without copying all historical receipts.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")

func _initialize() -> void:
	var ledger = Ledger.new()
	if not ledger.import_accounts({"buyer": 100, "seller": 0}):
		_fail("seed")
		return
	if not ledger.transfer("paid-1", "buyer", "seller", 13, 7, "trade").get("ok", false):
		_fail("transfer")
		return
	var proof: Dictionary = {"id": "paid-1", "kind": "trade", "tick": 7,
		"legs": [{"account": "buyer", "delta": -13}, {"account": "seller", "delta": 13}]}
	var before: Dictionary = ledger.snapshot()
	if not ledger.verify_operation_provenance([proof]):
		_fail("valid proof rejected")
		return
	if not ledger.verify_operation_provenance([]):
		_fail("empty proof rejected")
		return
	var bad: Dictionary = proof.duplicate(true)
	for key in ["id", "kind", "tick", "legs"]:
		bad = proof.duplicate(true)
		bad.erase(key)
		if ledger.verify_operation_provenance([bad]):
			_fail("missing field accepted: " + key)
			return
	for key in ["kind", "tick", "legs"]:
		bad = proof.duplicate(true)
		if key == "kind":
			bad[key] = "wages"
		elif key == "tick":
			bad[key] = 8
		else:
			bad[key][0]["delta"] = -12
		if ledger.verify_operation_provenance([bad]):
			_fail("forged provenance accepted: " + key)
			return
	bad = proof.duplicate(true)
	bad["id"] = "absent"
	if ledger.verify_operation_provenance([bad]) or ledger.verify_operation_provenance([proof, proof]):
		_fail("missing or duplicate operation accepted")
		return
	if ledger.verify_operation_provenance([{"id": 1, "kind": "trade", "tick": 7, "legs": []}]):
		_fail("invalid id accepted")
		return
	var forked = ledger.fork()
	if not forked.verify_operation_provenance([proof]):
		_fail("fork lost provenance")
		return
	var restored = Ledger.new()
	if not restored.restore(before) or not restored.verify_operation_provenance([proof]):
		_fail("restore lost provenance")
		return
	if ledger.snapshot() != before or ledger.balance("buyer") != 87:
		_fail("proof mutated authoritative ledger")
		return
	print("P2_PERF_B_RECEIPT_PROOF_WITHOUT_COPY_PASS")
	quit(0)

func _fail(reason: String) -> void:
	push_error("P2_PERF_B_RECEIPT_PROOF_WITHOUT_COPY_FAIL: " + reason)
	quit(1)
