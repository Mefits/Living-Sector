extends RefCounted
## N30 CODE_UNVERIFIED: read-only cross-component reconciliation.
## Rust reference: sim_core/economy/contracts.rs, sim_server/engine/contract_funding.rs.
## This does not authorize transfers or substitute for the N27 physical gate.

func inspect(board: RefCounted, cargo: RefCounted, ledger: RefCounted) -> Dictionary:
	var contracts: Dictionary = board.snapshot().get("contracts", {})
	var cargo_receipts: Dictionary = cargo.receipts
	var ledger_state: Dictionary = ledger.snapshot()
	var balances: Dictionary = ledger_state.get("balances", {})
	var money_receipts: Dictionary = ledger_state.get("receipts", {})
	var problems: Array = []
	var escrow_owners: Dictionary = {}
	var ids: Array = contracts.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = contracts[id]
		var prefix := "contract:" + str(id) + ":"
		var escrow := str(c.get("escrow_account", ""))
		var payer := str(c.get("requestor_id", ""))
		var status := str(c.get("status", ""))
		var reserved := int(c.get("reserved", -1))
		if escrow.is_empty() or not balances.has(escrow) or escrow_owners.has(escrow):
			problems.append(str(id) + ":escrow_missing_or_shared")
		else:
			escrow_owners[escrow] = id
			if typeof(balances[escrow]) != TYPE_INT or int(balances[escrow]) != reserved:
				problems.append(str(id) + ":escrow_balance_mismatch")
		if not _money_leg(money_receipts.get(prefix + "post", {}), payer, escrow, int(c.get("initial_payment", 0))):
			problems.append(str(id) + ":missing_funding")
		if status in ["accepted", "picked_up", "delivered", "paid"]:
			var agreed := int(c.get("agreed_payment", -1))
			var initial := int(c.get("initial_payment", 0))
			if agreed < 0:
				problems.append(str(id) + ":invalid_agreed_payment")
			var topup := maxi(0, agreed - initial)
			if topup > 0 and not _money_leg(money_receipts.get(prefix + "topup", {}), payer, escrow, topup):
				problems.append(str(id) + ":missing_topup")
		if status in ["picked_up", "delivered", "paid"]:
			if not _cargo_leg(cargo_receipts.get(prefix + "load", {}), c, "load"):
				problems.append(str(id) + ":missing_pickup")
			if str(c.get("picked_up_receipt", "")) != prefix + "load":
				problems.append(str(id) + ":pickup_reference_mismatch")
		if status in ["delivered", "paid"]:
			if not _cargo_leg(cargo_receipts.get(prefix + "unload", {}), c, "unload"):
				problems.append(str(id) + ":missing_delivery")
			if str(c.get("delivered_receipt", "")) != prefix + "unload":
				problems.append(str(id) + ":delivery_reference_mismatch")
			var load_tick := int((cargo_receipts.get(prefix + "load", {}) as Dictionary).get("tick", -1))
			var unload_tick := int((cargo_receipts.get(prefix + "unload", {}) as Dictionary).get("tick", -1))
			if load_tick < int(c.get("accepted_at_tick", -1)) or unload_tick < load_tick or int(c.get("delivered_at_tick", -1)) < unload_tick:
				problems.append(str(id) + ":invalid_delivery_order")
		if status == "paid":
			var payout: Dictionary = money_receipts.get(prefix + "payout", {})
			if not _outgoing_leg(payout, escrow, int(c.get("agreed_payment", -1))):
				problems.append(str(id) + ":missing_payout")
		elif money_receipts.has(prefix + "payout"):
			problems.append(str(id) + ":premature_payout")
		if status == "posted" and (cargo_receipts.has(prefix + "load") or cargo_receipts.has(prefix + "unload")):
			problems.append(str(id) + ":premature_cargo")
	return {"ok": problems.is_empty(), "checked": ids.size(), "problems": problems}

func _money_leg(receipt: Variant, source: String, target: String, amount: int) -> bool:
	if not (receipt is Dictionary) or amount <= 0:
		return false
	var legs: Variant = receipt.get("legs", [])
	if not (legs is Array) or legs.size() != 2:
		return false
	return _has_leg(legs, source, -amount) and _has_leg(legs, target, amount)

func _outgoing_leg(receipt: Variant, source: String, amount: int) -> bool:
	if not (receipt is Dictionary) or amount <= 0:
		return false
	var legs: Variant = receipt.get("legs", [])
	return legs is Array and legs.size() == 2 and _has_leg(legs, source, -amount)

func _has_leg(legs: Array, account: String, delta: int) -> bool:
	for leg in legs:
		if leg is Dictionary and leg.get("account") == account and typeof(leg.get("delta")) == TYPE_INT and int(leg["delta"]) == delta:
			return true
	return false

func _cargo_leg(receipt: Variant, c: Dictionary, direction: String) -> bool:
	if not (receipt is Dictionary) or receipt.get("ok", false) != true:
		return false
	var location := str(c.get("source_location", "")) if direction == "load" else str(c.get("destination_location", ""))
	var amounts: Variant = receipt.get("quantities", {})
	return receipt.get("direction") == direction and receipt.get("ship_id") == c.get("fulfiller_id") and receipt.get("location_id") == location and typeof(receipt.get("tick")) == TYPE_INT and amounts is Dictionary and amounts.size() == 1 and typeof(amounts.get(str(c.get("commodity", "")))) == TYPE_INT and int(amounts.get(str(c.get("commodity", "")), 0)) == int(c.get("quantity", -1))
