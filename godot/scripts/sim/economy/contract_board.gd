extends RefCounted
## CODE_UNVERIFIED. Rust: sim_core/economy/contracts.rs and sim_server/engine/contract_funding.rs.
## Prepaid contracts only; cargo delivery must be confirmed by the physical cargo subsystem.
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const TYPES = ["delivery", "courier", "passenger", "subsidy", "supply", "crew_mission", "construction"]
const ACTIVE = ["posted", "accepted", "picked_up", "delivered"]
var _contracts: Dictionary = {}
## One physical cargo operation can prove at most one contract transition.
## Claims survive save/reload and are rebuilt from legacy version-1 snapshots.
var _receipt_claims: Dictionary = {}
var _ledger: RefCounted
var _physical_cargo: RefCounted

## N27: bind the authoritative cargo receipt registry before accepting physical transitions.
## A caller-supplied receipt string is never proof of physical movement.
func bind_physical_cargo(cargo: RefCounted) -> void:
	_physical_cargo = cargo

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
	_contracts[id] = {"id": id, "contract_type": kind, "status": "posted", "requestor_id": payer, "funding_source": funding_source, "escrow_account": escrow, "reserved": payment, "agreed_payment": -1, "fulfiller_id": "", "commodity": commodity, "quantity": quantity, "source_location": source, "destination_location": destination, "payment": payment, "initial_payment": payment, "posted_at_tick": tick, "expires_at_tick": expiry, "accepted_at_tick": -1, "delivered_at_tick": -1, "renewal_count": 0, "min_reputation": (70 if kind == "subsidy" else (50 if kind == "crew_mission" else 0)), "initial_min_reputation": (70 if kind == "subsidy" else (50 if kind == "crew_mission" else 0))}
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
	if not _valid_physical_receipt(c, ship, "unload", str(c.get("delivered_receipt", "")), int(c["delivered_at_tick"])):
		return _error("unverified_delivery")
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

## Frozen N152::drop_ship_holdings under the EXISTING N104 authority.
## Called only inside N39's isolated admin commit, after preflight has
## verified the real ship exists and has no embarked passengers.
## Never refund or fabricate cargo here: the next N152 market pass
## returns any stranded escrow through a REAL N9 receipt.
func drop_removed_ship_holdings(ship_id: String) -> Dictionary:
    if ship_id.is_empty():
        return _error("missing_removed_ship")
    var ids: Array = _contracts.keys()
    ids.sort()
    var released: Array = []
    var cancelled: Array = []
    for id in ids:
        var c: Dictionary = _contracts[id]
        if str(c.get("fulfiller_id", "")) != ship_id:
            continue
        var previous: String = str(c.get("status", ""))
        if previous == "accepted":
            c["status"] = "posted"
            c["fulfiller_id"] = ""
            c["accepted_at_tick"] = -1
            c["agreed_payment"] = -1
            released.append(str(id))
        elif previous == "picked_up":
            c["status"] = "expired"
            cancelled.append(str(id))
    return {"ok": true, "released": released, "cancelled": cancelled}

## Frozen N152::cancel_for_facility, using only the actual removed ID.
## Location cancellations are admitted ONLY if it was the LAST local
## facility. Keep PAID/EXPIRED history and the original N15 receipts.
func cancel_removed_facility_contracts(facility_id: String,
        location: String, last_at_location: bool) -> Dictionary:
    if facility_id.is_empty() or location.is_empty():
        return _error("missing_removed_facility")
    var cancelled: Array = []
    var ids: Array = _contracts.keys()
    ids.sort()
    for id in ids:
        var c: Dictionary = _contracts[id]
        if str(c.get("status", "")) in ["paid", "expired"]:
            continue
        var is_requestor: bool = str(c.get("requestor_id", "")) in [
            facility_id, "facility/" + facility_id]
        var is_unserved_endpoint: bool = last_at_location and (
            str(c.get("source_location", "")) == location or
            str(c.get("destination_location", "")) == location)
        if not is_requestor and not is_unserved_endpoint:
            continue
        c["status"] = "expired"
        cancelled.append(str(id))
    return {"ok": true, "cancelled": cancelled}

func get_contract(id: String) -> Dictionary:
	if not _contracts.has(id):
		return {}
	return _contracts[id].duplicate(true)

func snapshot() -> Dictionary:
	return {"version": 1, "contracts": _contracts.duplicate(true), "receipt_claims": _receipt_claims.duplicate(true)}

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
	var reconstructed: Dictionary = {}
	for id in candidate:
		var c: Dictionary = candidate[id]
		for phase in ["picked_up", "delivered"]:
			var key: String = phase + "_receipt"
			if not c.has(key):
				continue
			var receipt_id: String = str(c[key])
			if receipt_id.is_empty() or reconstructed.has(receipt_id):
				return false
			reconstructed[receipt_id] = str(id) + ":" + phase
	if data.has("receipt_claims"):
		if not (data["receipt_claims"] is Dictionary):
			return false
		var stored: Dictionary = data["receipt_claims"]
		if stored.size() != reconstructed.size():
			return false
		for receipt_id in reconstructed:
			if stored.get(receipt_id) != reconstructed[receipt_id]:
				return false
	_contracts = candidate.duplicate(true)
	_receipt_claims = reconstructed
	return true

func _transition(id: String, ship: String, before: String, after: String, tick: int, receipt_id: String) -> Dictionary:
	if not _contracts.has(id):
		return _error("missing_contract")
	var c: Dictionary = _contracts[id]
	if receipt_id.is_empty() or c["status"] != before or c["fulfiller_id"] != ship or tick < int(c["accepted_at_tick"]):
		return _error("invalid_transition")
	var direction := "load" if after == "picked_up" else "unload"
	if _receipt_claims.has(receipt_id):
		return _error("physical_receipt_already_claimed")
	if not _valid_physical_receipt(c, ship, direction, receipt_id, tick):
		return _error("unverified_physical_receipt")
	# Receipt validation is authoritative for delivery contracts, not a string assertion.
	c["status"] = after
	c[after + "_receipt"] = receipt_id
	_receipt_claims[receipt_id] = id + ":" + after
	if after == "delivered":
		c["delivered_at_tick"] = tick
	return {"ok": true}

## Delivery contracts require the actual N15 receipt registry; no direct board transition bypass.
## Non-delivery contract types are not granted a synthetic physical receipt.
func _valid_physical_receipt(c: Dictionary, ship: String, direction: String, receipt_id: String, tick: int) -> bool:
	if str(c.get("contract_type", "")) != "delivery":
		return false
	if _physical_cargo == null or receipt_id.is_empty():
		return false
	var receipt: Dictionary = _physical_cargo.receipts.get(receipt_id, {})
	if receipt.get("ok", false) != true or str(receipt.get("ship_id", "")) != ship:
		return false
	# The live N15/N97 docked cargo gate writes action (load/unload),
	# not the older source-only direction field. Require canonical identity.
	if str(receipt.get("operation_id", "")) != receipt_id:
		return false
	if str(receipt.get("action", "")) != direction or int(receipt.get("tick", -1)) > tick:
		return false
	var expected_location := str(c["source_location"]) if direction == "load" else str(c["destination_location"])
	if str(receipt.get("location_id", "")) != expected_location:
		return false
	var quantities: Variant = receipt.get("quantities", null)
	return (quantities is Dictionary and quantities.size() == 1
		and typeof(quantities.get(str(c["commodity"]))) == TYPE_INT
		and int(quantities[str(c["commodity"])]) == int(c["quantity"]))

func _error(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
