extends RefCounted
## N152 source-driven status changes and admin cleanup from contracts.rs.
## This stages only ContractBoard rows and indices, NEVER returns a
## fabricated physical receipt, payment, refund, freight or cargo.
const Core = preload("res://scripts/sim/phase1/n152_native_contract_board_core.gd")

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

static func _contract_by_status(board: Dictionary, id: String, required: String) -> Dictionary:
	if not Core._board_ok(board) or not board["contracts"].has(id):
		return {}
	var c = board["contracts"][id]
	if not (c is Dictionary) or str(c.get("status",""))!=required:
		return {}
	return c

static func accept_after_funding(board: Dictionary, id: String,
		ship: String, tick: int, trusted_receipt: Dictionary) -> Dictionary:
	## ContractBoard.accept only moves Posted→Accepted. The engine
	## MUST call N104.accept first and prove the payer top-up, agreed
	## payment, actual ship ownership, mission guards and real funds.
	## A UI-provided receipt is NOT proof: invoke from private engine.
	var original := _contract_by_status(board,id,"posted")
	if original.is_empty() or ship.is_empty() or tick<0:
		return _fail("invalid_accept_or_missing_posted")
	if not bool(trusted_receipt.get("trusted_internal_apply",false)) or \
			not bool(trusted_receipt.get("funding_committed",false)) or \
			str(trusted_receipt.get("contract_id",""))!=id or \
			str(trusted_receipt.get("ship_id",""))!=ship:
		return _fail("authoritative_accept_receipt_required")
	var result := board.duplicate(true)
	var c: Dictionary = result["contracts"][id]
	Core._remove_posted(result,id,c)
	c["status"]="accepted"
	c["fulfiller_id"]=ship
	c["accepted_at_tick"]=tick
	Core._move_status(result,id,"posted","accepted")
	return {"ok":true,"board":result,"contract":c.duplicate(true),
		"authority":"N104_real_paid_accept_then_single_board_commit"}

static func release(board: Dictionary, id: String,
		expected_fulfiller: Variant = null) -> Dictionary:
	## Rust::release accepts an Optional ship guard; it returns false if
	## absent, not accepted, or fulfiller differs. Does NOT refund funds.
	var original := _contract_by_status(board,id,"accepted")
	if original.is_empty():
		return _fail("not_accepted")
	if expected_fulfiller!=null and original.get("fulfiller_id",null)!=expected_fulfiller:
		return _fail("wrong_expected_fulfiller")
	var result := board.duplicate(true)
	var c: Dictionary = result["contracts"][id]
	c["status"]="posted"
	c["fulfiller_id"]=null
	c["accepted_at_tick"]=null
	var reward=Core.fixed_strategy_reward(c)
	if reward!=null:
		c["payment"]=reward
	if c.get("funding",null) is Dictionary:
		c["funding"]["agreed_payment"]=null
	Core._move_status(result,id,"accepted","posted")
	Core._add_posted(result,id,c)
	return {"ok":true,"board":result,"contract":c.duplicate(true)}

static func mark_picked_up_after_physical_receipt(board: Dictionary,
		id: String, receipt: Dictionary) -> Dictionary:
	## Rust ContractBoard.mark_picked_up only Accepted->PickedUp.
	## N97 physical ship cargo or N104 embarking is the real owner.
	var original := _contract_by_status(board,id,"accepted")
	if original.is_empty():
		return _fail("not_accepted")
	if not bool(receipt.get("trusted_internal_apply",false)) or \
			not bool(receipt.get("pickup_committed",false)) or \
			str(receipt.get("contract_id",""))!=id or \
			str(receipt.get("ship_id",""))!=str(original.get("fulfiller_id","")):
		return _fail("native_physical_pickup_receipt_required")
	var result := board.duplicate(true)
	result["contracts"][id]["status"]="picked_up"
	Core._move_status(result,id,"accepted","picked_up")
	return {"ok":true,"board":result}

static func mark_delivered_after_physical_receipt(board: Dictionary,
		id: String, receipt: Dictionary) -> Dictionary:
	## Original Board.mark_delivered jumps Accepted OR PickedUp directly
	## to Paid (NOT Delivered), after native real delivery/refund Apply.
	## Do NOT invoke N16 invented "delivered" intermediate transition.
	if not Core._board_ok(board) or not board["contracts"].has(id):
		return _fail("missing_contract")
	var c: Dictionary = board["contracts"][id]
	var old: String = str(c.get("status",""))
	if old not in ["accepted","picked_up"]:
		return _fail("not_currently_accepted_or_picked_up")
	if not bool(receipt.get("trusted_internal_apply",false)) or \
			not bool(receipt.get("delivery_and_payment_committed",false)) or \
			str(receipt.get("contract_id",""))!=id or \
			str(receipt.get("ship_id",""))!=str(c.get("fulfiller_id","")):
		return _fail("real_delivery_and_payout_required")
	var result := board.duplicate(true)
	result["contracts"][id]["status"]="paid"
	Core._move_status(result,id,old,"paid")
	return {"ok":true,"board":result,
		"paid_contract":result["contracts"][id].duplicate(true)}

static func drop_ship_holdings(board: Dictionary, ship_id: String) -> Dictionary:
	## Rust::drop_ship_holdings returns two lists:
	## Accepted -> Posted (cargo not aboard), PickedUp -> Expired
	## (cargo lost). Paid/Expired and stale Posted left unchanged.
	## Real admin_delete_ship, ledger release and refunds are owned
	## by N104/engine/admin; NO money is moved here.
	if not Core._board_ok(board) or ship_id.is_empty():
		return _fail("invalid_board_or_ship")
	var result := board.duplicate(true)
	var released: Array[String] = []
	var cancelled: Array[String] = []
	var ids: Array = result["contracts"].keys()
	ids.sort() # Rust HashMap order unspecified; deterministic projections.
	for id in ids:
		var c: Dictionary = result["contracts"][id]
		if c.get("fulfiller_id",null)!=ship_id:
			continue
		var old: String = str(c.get("status",""))
		if old=="accepted":
			c["status"]="posted"
			c["fulfiller_id"]=null
			c["accepted_at_tick"]=null
			# Original bulk cleanup differs from release(): it DOES
			# NOT reset c.payment to fixed strategy reward here.
			if c.get("funding",null) is Dictionary:
				c["funding"]["agreed_payment"]=null
			Core._move_status(result,id,"accepted","posted")
			Core._add_posted(result,str(id),c)
			released.append(str(id))
		elif old=="picked_up":
			c["status"]="expired"
			# Preserve original fulfiller for persisted cargo-loss audit.
			Core._move_status(result,id,"picked_up","expired")
			cancelled.append(str(id))
	return {"ok":true,"board":result,
		"released":released,"cancelled":cancelled,
		"requires":"engine_admin_ship_remove_and_existing_N104_funding_cleanup"}

static func cancel_for_facility(board: Dictionary,
		requestor: Variant, source: Variant, destination: Variant) -> Dictionary:
	## Exact native admin three independent optional selectors.
	## Caller ONLY supplies locations if last facility at location was
	## actually removed; otherwise this would cancel unrelated trade.
	if not Core._board_ok(board):
		return _fail("invalid_board")
	for candidate in [requestor,source,destination]:
		if candidate!=null and not (candidate is String):
			return _fail("invalid_optional_facility_selector")
	var result := board.duplicate(true)
	var cancelled: Array[String] = []
	var ids: Array = result["contracts"].keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = result["contracts"][id]
		var old: String = str(c.get("status",""))
		if old in ["paid","expired"]:
			continue
		var match_requestor: bool = requestor!=null and str(c.get("requestor_id",""))==requestor
		var match_source: bool = source!=null and str(c.get("source_location",""))==source
		var match_destination: bool = destination!=null and str(c.get("destination_location",""))==destination
		if not match_requestor and not match_source and not match_destination:
			continue
		if old=="posted":
			Core._remove_posted(result,str(id),c)
		c["status"]="expired"
		Core._move_status(result,str(id),old,"expired")
		cancelled.append(str(id))
	# No refund (ContractBoard.cancel_for_facility doesn't touch escrow).
	return {"ok":true,"board":result,"cancelled":cancelled,
		"requires":"existing_N104_escrow_refund_after_real_facility_delete"}
