extends RefCounted
## N26 CODE_UNVERIFIED. Physical delivery gate for N15 cargo and N16 prepaid contracts.
## A contract is never paid from an arbitrary caller-provided receipt string.
## Native Rust references: sim_core/economy/contracts.rs; sim_server/engine/contract_funding.rs.
var _board: RefCounted
var _cargo: RefCounted
var _ships: RefCounted

func _init(board: RefCounted, cargo: RefCounted, ships: RefCounted) -> void:
	_board = board
	_cargo = cargo
	_ships = ships

func pickup(contract_id: String, ship_id: String, source_stock: Dictionary, tick: int) -> Dictionary:
	var c: Dictionary = _board.get_contract(contract_id)
	if not _eligible(c, ship_id, "accepted", tick):
		return _error("contract_not_accepted")
	var location: String = str(c["source_location"])
	var commodity: String = str(c["commodity"])
	var amount: int = int(c["quantity"])
	var receipt_id := "contract:" + contract_id + ":load"
	if _cargo.receipts.has(receipt_id):
		return _error("duplicate_pickup")
	var result: Dictionary = _cargo.move(_ships, ship_id, source_stock, {commodity: amount}, receipt_id, "load", location, tick)
	if not result.get("ok", false):
		return result
	# The synchronous, prevalidated transition cannot be bypassed by a forged receipt.
	return _board.confirm_pickup(contract_id, ship_id, tick, receipt_id)

func deliver(contract_id: String, ship_id: String, destination_stock: Dictionary, tick: int) -> Dictionary:
	var c: Dictionary = _board.get_contract(contract_id)
	if not _eligible(c, ship_id, "picked_up", tick):
		return _error("contract_not_picked_up")
	var load_id := "contract:" + contract_id + ":load"
	var load: Dictionary = _cargo.receipts.get(load_id, {})
	if not _receipt_matches(load, c, ship_id, "load", str(c["source_location"])):
		return _error("missing_verified_pickup")
	if str(c.get("picked_up_receipt", "")) != load_id or tick < int(load.get("tick", -1)):
		return _error("pickup_mismatch")
	var receipt_id := "contract:" + contract_id + ":unload"
	if _cargo.receipts.has(receipt_id):
		return _error("duplicate_delivery")
	var result: Dictionary = _cargo.move(_ships, ship_id, destination_stock, {str(c["commodity"]): int(c["quantity"])}, receipt_id, "unload", str(c["destination_location"]), tick)
	if not result.get("ok", false):
		return result
	return _board.confirm_delivery(contract_id, ship_id, tick, receipt_id)

func settle_verified(contract_id: String, ship_id: String, ship_wallet: String, tick: int) -> Dictionary:
	var c: Dictionary = _board.get_contract(contract_id)
	if not _eligible(c, ship_id, "delivered", tick):
		return _error("contract_not_delivered")
	var receipt_id := "contract:" + contract_id + ":unload"
	var unload: Dictionary = _cargo.receipts.get(receipt_id, {})
	if str(c.get("delivered_receipt", "")) != receipt_id or not _receipt_matches(unload, c, ship_id, "unload", str(c["destination_location"])):
		return _error("missing_verified_delivery")
	if tick < int(unload.get("tick", -1)):
		return _error("invalid_tick")
	return _board.settle(contract_id, ship_id, ship_wallet, tick)

func _eligible(c: Dictionary, ship_id: String, expected: String, tick: int) -> bool:
	return not c.is_empty() and str(c.get("status", "")) == expected and str(c.get("fulfiller_id", "")) == ship_id and not ship_id.is_empty() and tick >= int(c.get("accepted_at_tick", -1)) and tick >= 0 and str(c.get("commodity", "")) != "" and int(c.get("quantity", 0)) > 0

func _receipt_matches(receipt: Dictionary, c: Dictionary, ship_id: String, direction: String, location: String) -> bool:
	if receipt.get("ok", false) != true or str(receipt.get("ship_id", "")) != ship_id or str(receipt.get("direction", "")) != direction or str(receipt.get("location_id", "")) != location:
		return false
	var quantities: Variant = receipt.get("quantities", null)
	return quantities is Dictionary and quantities.size() == 1 and typeof(quantities.get(str(c["commodity"]))) == TYPE_INT and int(quantities[str(c["commodity"])]) == int(c["quantity"])

func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
