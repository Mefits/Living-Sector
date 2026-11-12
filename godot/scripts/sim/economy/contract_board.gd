extends RefCounted
## CODE_UNVERIFIED. Rust: sim_core/economy/contracts.rs and sim_server/engine/contract_funding.rs.
## Prepaid contracts only; cargo delivery must be confirmed by the physical cargo subsystem.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const TYPES = ["delivery", "courier", "passenger", "subsidy", "supply", "crew_mission", "construction"]
const ACTIVE = ["posted", "accepted", "picked_up", "delivered"]
var _contracts: Dictionary = {}
var _ledger: RefCounted

func _init(ledger: RefCounted) -> void:
	_ledger = ledger

## The escrow account must already exist in the imported ledger. This function NEVER mints funds.
func post(id: String, kind: String, payer: String, escrow: String, commodity: String, quantity: int, source: String, destination: String, payment: int, tick: int, expiry: int, funding_source: String) -> Dictionary:
	if id.is_empty() or _contracts.has(id) or not TYPES.has(kind) or not ["facility", "faction", "population"].has(funding_source):
		return _error("invalid_contract")
	if payer.is_empty() or escrow.is_empty() or payer == escrow or quantity <= 0 or payment <= 0 or tick < 0 or expiry <= tick or source.is_empty() or destination.is_empty():
		return _error("invalid_terms")
	if _ledger.balance(payer) < payment or _ledger.balance(escrow) != 0:
		return _error("funding_unavailable")
	var paid: Dictionary = _ledger.transfer("contract:" + id + ":post", payer, escrow, payment, tick, "contract_advance")
	if not paid.get("ok", false):
		return paid
	_contracts[id] = {"id": id, "contract_type": kind, "status": "posted", "requestor_id": payer, "funding_source": funding_source, "escrow_account": escrow, "reserved": payment, "agreed_payment": -1, "fulfiller_id": "", "commodity": commodity, "quantity": quantity, "source_location": source, "destination_location": destination, "payment": payment, "initial_payment": payment, "posted_at_tick": tick, "expires_at_tick": expiry, "accepted_at_tick": -1, "delivered_at_tick": -1}
	return {"ok": true, "contract": get_contract(id)}

func accept(id: String, ship: String, ship_faction: String, comms_bonus: float, treaty_multiplier: float, tick: int) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if c["status"] != "posted" or tick > int(c["expires_at_tick"]) or ship.is_empty() or ship_faction.is_empty() or not is_finite(comms_bonus) or not is_finite(treaty_multiplier) or comms_bonus < -1.0 or treaty_multiplier < 0.0:
		return _error("contract_unavailable")
	# Rust acceptance_payment: rounded current offer * (1+comms) * treaty; fixed strategy rewards require separate policy.
	var raw: float = float(c["payment"]) * (1.0 + comms_bonus) * treaty_multiplier
	if not is_finite(raw) or raw < 0.0 or raw >= 9223372036854775807.0:
		return _error("invalid_payment")
	var agreed: int = int(round(raw))
	var top_up: int = maxi(0, agreed - int(c["reserved"]))
	if top_up > 0:
		var funded: Dictionary = _ledger.transfer("contract:" + id + ":topup", c["requestor_id"], c["escrow_account"], top_up, tick, "contract_top_up")
		if not funded.get("ok", false):
			return funded
	c["reserved"] = int(c["reserved"]) + top_up
	c["agreed_payment"] = agreed
	c["fulfiller_id"] = ship
	c["accepted_at_tick"] = tick
	c["status"] = "accepted"
	return {"ok": true, "agreed_payment": agreed, "top_up": top_up}

## Only a verified cargo/passenger handler should call these transitions.
func confirm_pickup(id: String, ship: String, tick: int, receipt_id: String) -> Dictionary:
	return _transition(id, ship, "accepted", "picked_up", tick, receipt_id)

func confirm_delivery(id: String, ship: String, tick: int, receipt_id: String) -> Dictionary:
	return _transition(id, ship, "picked_up", "delivered", tick, receipt_id)

func settle(id: String, ship: String, ship_wallet: String, tick: int) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if c["status"] != "delivered" or c["fulfiller_id"] != ship or ship_wallet.is_empty() or tick < int(c["delivered_at_tick"]):
		return _error("not_delivered")
	var agreed: int = int(c["agreed_payment"])
	if agreed <= 0 or agreed > int(c["reserved"]):
		return _error("invalid_escrow")
	var result: Dictionary = _ledger.transfer("contract:" + id + ":payout", c["escrow_account"], ship_wallet, agreed, tick, "contract_payment")
	if not result.get("ok", false):
		return result
	c["reserved"] = int(c["reserved"]) - agreed
	c["status"] = "paid"
	return {"ok": true, "paid": agreed}

## Native renewals are intentionally NOT faked. Only posted contracts can expire here.
func expire_posted(id: String, tick: int) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if c["status"] != "posted" or tick < int(c["expires_at_tick"]):
		return _error("not_expirable")
	c["status"] = "expired"
	return {"ok": true}

func refund_closed(id: String, tick: int) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if not ["paid", "expired"].has(c["status"]):
		return _error("not_closed")
	var amount: int = int(c["reserved"])
	if amount == 0:
		return {"ok": true, "refunded": 0}
	var result: Dictionary = _ledger.transfer("contract:" + id + ":refund", c["escrow_account"], c["requestor_id"], amount, tick, "contract_refund")
	if not result.get("ok", false):
		return result
	c["reserved"] = 0
	return {"ok": true, "refunded": amount}

func get_contract(id: String) -> Dictionary:
	if not _contracts.has(id):
		return {}
	return _contracts[id].duplicate(true)

func snapshot() -> Dictionary:
	return {"version": 1, "contracts": _contracts.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or not (data.get("contracts") is Dictionary):
		return false
	var candidate: Dictionary = data["contracts"]
	for id in candidate:
		if not (id is String) or not (candidate[id] is Dictionary):
			return false
		var c: Dictionary = candidate[id]
		if c.get("id") != id or not TYPES.has(c.get("contract_type")) or not (ACTIVE + ["paid", "expired"]).has(c.get("status")):
			return false
		if typeof(c.get("reserved")) != TYPE_INT or int(c["reserved"]) < 0 or _ledger.balance(str(c.get("escrow_account"))) < int(c["reserved"]):
			return false
	_contracts = candidate.duplicate(true)
	return true

func _transition(id: String, ship: String, before: String, after: String, tick: int, receipt_id: String) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if receipt_id.is_empty() or c["status"] != before or c["fulfiller_id"] != ship or tick < int(c["accepted_at_tick"]):
		return _error("invalid_transition")
	# The caller owns the physical cargo receipt; do not fabricate inventory movement here.
	c["status"] = after
	c[after + "_receipt"] = receipt_id
	if after == "delivered":
		c["delivered_at_tick"] = tick
	return {"ok": true}

func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
