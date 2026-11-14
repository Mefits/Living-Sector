extends RefCounted
## P2 N135 -> N104 escrow admission. This is a TRANSACTIONAL CANDIDATE,
## not a second live board or ledger: the canonical N158 Apply must validate
## and publish BOTH returned snapshots together, or publish neither.
## Never call this after the canonical World has changed without revalidation.
const Admission = preload("res://scripts/sim/phase2/unified_contract_demand_admission.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const ContractBoard = preload("res://scripts/sim/economy/contract_board.gd")

static func stage(world: Dictionary, ledger_snapshot: Dictionary,
		board_snapshot: Dictionary, demand: Dictionary, tick: int,
		expiry_ticks: int = 256) -> Dictionary:
	if expiry_ticks <= 0 or tick < 0 or tick > 9223372036854775807 - expiry_ticks:
		return _error("invalid_expiry")
	if not (board_snapshot.get("contracts") is Dictionary):
		return _error("invalid_board_snapshot")
	var admitted: Dictionary = Admission.validate(world, ledger_snapshot, demand,
			tick, board_snapshot["contracts"])
	if not admitted.get("ok", false):
		return _error(str(admitted.get("reason", "demand_rejected")))
	var id: String = str(admitted["contract_id"])
	var escrow: String = "escrow:" + id
	var ledger := Ledger.new()
	if not ledger.restore(ledger_snapshot):
		return _error("invalid_ledger_snapshot")
	var original_total: int = ledger.total()
	var board := ContractBoard.new(ledger)
	if not board.restore(board_snapshot):
		return _error("invalid_board_snapshot")
	if not ledger.register_empty_account(escrow):
		return _error("escrow_account_conflict")
	var result: Dictionary = board.post(id, "delivery",
			str(admitted["payer_account"]), escrow, str(admitted["commodity"]),
			int(admitted["quantity"]), str(admitted["source_location"]),
			str(admitted["destination_location"]), int(admitted["payment"]),
			tick, tick + expiry_ticks, "facility")
	if not result.get("ok", false):
		return _error(str(result.get("reason", "post_failed")))
	if ledger.total() != original_total:
		return _error("money_conservation_failed")
	var next_ledger: Dictionary = ledger.snapshot()
	var next_board: Dictionary = board.snapshot()
	if not next_board["contracts"].has(id):
		return _error("contract_missing_after_post")
	if int(next_ledger["balances"].get(escrow, -1)) != int(admitted["payment"]):
		return _error("escrow_balance_mismatch")
	return {"ok": true, "status": "STAGED_NOT_APPLIED",
			"contract_id": id, "escrow_account": escrow,
			"ledger_snapshot": next_ledger, "board_snapshot": next_board,
			"receipt_id": "contract:" + id + ":post",
			"validated_at_tick": tick}

static func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
