extends RefCounted
## N104 frozen Rust sim_server/engine/contract_funding.rs and
## sim_core/economy/contracts.rs. Exclusive, staged source-backed escrow.
##
## REQUIRED authoritative snapshot:
## world = {ships:{id:{id,faction_id,active_contract_id,comms_bonus}},
##   contracts:{id:Contract}, populations:{id:{total_wealth}},
##   facilities:{id:{credits}}, factions:{id:{treasury}},
##   relations:{ "factionA\u001ffactionB":"neutral|..." },
##   construction_sites:[{completed, labor:{completed,required,
##     station_order:{executor_id}|null}}]}
## No invented beneficiary, station market, ship purse or money creation.
const Quote = preload("res://scripts/port/n104_contract_quote.gd")
const MAX_I64: int = 9223372036854775807

## Rust server::contract_funding::account and set_balance source mapping.
static func payer_account(world: Dictionary, contract: Dictionary) -> Dictionary:
    var funding: Variant = contract.get("funding", null)
    if not (funding is Dictionary):
        return _bad("unverified_legacy_funding")
    var source: String = str(funding.get("source", ""))
    if not Quote.FUNDING_SOURCES.has(source):
        return _bad("invalid_funding_source")
    var requestor: String = str(contract.get("requestor_id", ""))
    if requestor.is_empty():
        return _bad("missing_contract_payer")
    var collection: String = {
        "population": "populations",
        "facility": "facilities",
        "faction": "factions"
    }[source]
    var field: String = {
        "population": "total_wealth",
        "facility": "credits",
        "faction": "treasury"
    }[source]
    if not (world.get(collection, null) is Dictionary):
        return _bad("missing_contract_payer")
    var payer: Variant = world[collection].get(requestor, null)
    if not (payer is Dictionary):
        return _bad("missing_contract_payer")
    var balance: Variant = payer.get(field, null)
    if typeof(balance) != TYPE_INT:
        return _bad("missing_contract_payer")
    return {"ok": true, "collection": collection, "field": field,
        "id": requestor, "balance": int(balance)}

static func _set_balance(staged: Dictionary, account: Dictionary,
        balance: int) -> void:
    var entity: Dictionary = staged[account["collection"]][account["id"]]
    entity[account["field"]] = balance
    # Exactly as the Rust entity component setters: dirty only if
    # respective lifecycle/sentiment exists. Do not fabricate components.
    if str(account["collection"]) == "populations":
        if entity.get("sentiment", null) is Dictionary:
            entity["sentiment"]["dirty"] = true
    elif entity.has("dirty"):
        entity["dirty"] = true

static func _assigned_elsewhere(contracts: Dictionary, ship_id: String,
        contract_id: String) -> bool:
    # Rust ContractBoard::iter filter then min_by contract ID. Only the
    # distinction "different ID assigned" matters for funding gate.
    for key in contracts:
        var c: Variant = contracts[key]
        if not (c is Dictionary):
            continue
        if not Quote.OPEN_STATUSES.has(str(c.get("status", ""))):
            continue
        var funding: Variant = c.get("funding", null)
        if not (funding is Dictionary):
            continue
        var order: Variant = funding.get("station_order", null)
        if not (order is Dictionary):
            continue
        if str(order.get("executor_id", "")) == ship_id and str(c.get("id", "")) != contract_id:
            return true
    return false

static func _assigned_builder(world: Dictionary, ship_id: String) -> Dictionary:
    var sites: Variant = world.get("construction_sites", null)
    if not (sites is Array):
        return _bad("missing_builder_assignments")
    for site in sites:
        if not (site is Dictionary):
            return _bad("invalid_builder_site")
        if not (site.get("labor", null) is Dictionary):
            return _bad("invalid_builder_labor")
        var labor: Dictionary = site["labor"]
        var completed: Variant = labor.get("completed", null)
        var required: Variant = labor.get("required", null)
        if typeof(completed) != TYPE_INT or typeof(required) != TYPE_INT:
            return _bad("invalid_builder_labor")
        if bool(site.get("completed", false)) or int(completed) >= int(required):
            continue
        var order: Variant = labor.get("station_order", null)
        if order is Dictionary and str(order.get("executor_id", "")) == ship_id:
            return {"ok": true, "assigned": true}
    return {"ok": true, "assigned": false}

## Rust accept: Posted -> Accepted, only after:
##  - station-order may_accept and competing assigned jobs
##  - same-faction / diplomatic commerce
##  - no different active contract
##  - nonlegacy proof of prepaid source
##  - exact quote, top-up from REAL payer, checked balance
## The entire snapshot is copied and published only after checks.
static func accept(world: Dictionary, ship_id: String,
        contract_id: String, tick: int) -> Dictionary:
    if tick < 0 or ship_id.is_empty() or contract_id.is_empty():
        return _bad("invalid_accept_context")
    if not (world.get("contracts", null) is Dictionary) or not (world.get("ships", null) is Dictionary):
        return _bad("missing_contract_world")
    var source_contract: Variant = world["contracts"].get(contract_id, null)
    if not (source_contract is Dictionary):
        return _bad("missing_contract")
    var contract: Dictionary = source_contract
    if str(contract.get("status", "")) != "posted":
        return _bad("contract_unavailable")
    var source_ship: Variant = world["ships"].get(ship_id, null)
    if not (source_ship is Dictionary):
        return _bad("missing_ship")
    var ship: Dictionary = source_ship
    if str(ship.get("id", "")) != ship_id:
        return _bad("mismatched_ship_identity")
    var faction: String = str(ship.get("faction_id", ""))
    if not Quote.may_accept(contract, ship_id, faction):
        return _bad("station_order_assigned_elsewhere")
    if _assigned_elsewhere(world["contracts"], ship_id, contract_id):
        return _bad("station_order_assigned_elsewhere")
    var builder: Dictionary = _assigned_builder(world, ship_id)
    if not bool(builder.get("ok", false)):
        return builder
    if bool(builder["assigned"]):
        return _bad("station_order_assigned_elsewhere")
    if not (world.get("relations", null) is Dictionary):
        return _bad("missing_relations")
    var tag: Variant = contract.get("faction_id", null)
    var owner: String = "" if tag == null else str(tag)
    if not owner.is_empty():
        var allowed: Dictionary = Quote.commerce_allowed(world["relations"], faction, owner)
        if not bool(allowed.get("ok", false)):
            return allowed
        if not bool(allowed["allowed"]):
            return _bad("embargo")
    var active: Variant = ship.get("active_contract_id", null)
    if active != null and str(active) != contract_id:
        return _bad("already_has_contract")
    if not (contract.get("funding", null) is Dictionary):
        return _bad("unverified_legacy_funding")
    var quoted: Dictionary = Quote.quote(contract, ship, world["relations"])
    if not bool(quoted.get("ok", false)):
        return quoted
    var payment: int = int(quoted["payment"])
    var top: Dictionary = Quote.top_up(contract, payment)
    if not bool(top.get("ok", false)):
        return top
    var extra: int = int(top["added"])
    var payer: Dictionary = {}
    if extra > 0:
        payer = payer_account(world, contract)
        if not bool(payer.get("ok", false)):
            return payer
        if int(payer["balance"]) < extra:
            return _bad("insufficient_contract_funding")
    var staged: Dictionary = world.duplicate(true)
    var record: Dictionary = staged["contracts"][contract_id]
    record["status"] = "accepted"
    record["fulfiller_id"] = ship_id
    record["accepted_at_tick"] = tick
    if extra > 0:
        _set_balance(staged, payer, int(payer["balance"]) - extra)
    var funding: Dictionary = record["funding"]
    funding["reserved"] = int(funding["reserved"]) + extra
    funding["agreed_payment"] = payment
    staged["ships"][ship_id]["active_contract_id"] = contract_id
    if staged["ships"][ship_id].has("lifecycle_dirty"):
        staged["ships"][ship_id]["lifecycle_dirty"] = true
    var evt: Dictionary = {
        "kind": "contract_accepted", "contract_id": contract_id,
        "contract_type": str(record.get("contract_type", "")),
        "ship_id": ship_id, "commodity": record.get("commodity", null),
        "source": record.get("source_location", null),
        "destination": record.get("destination_location", null),
        "payment": record.get("payment", null),
        "agreed_payment": payment, "reserved_top_up": extra, "tick": tick
    }
    return {"ok": true, "world": staged, "events": [evt],
        "agreed_payment": payment, "top_up": extra}

## Rust board::release: Accepted -> Posted. The escrow stays reserved,
## and agreed_payment becomes None. Only the current fulfiller may
## release; no double refund, no phantom restart of the budget.
static func release(world: Dictionary, contract_id: String,
        expected_ship_id: String) -> Dictionary:
    if not (world.get("contracts", null) is Dictionary):
        return _bad("missing_contract_world")
    var source: Variant = world["contracts"].get(contract_id, null)
    if not (source is Dictionary) or str(source.get("status", "")) != "accepted":
        return _bad("not_accepted_contract")
    if not expected_ship_id.is_empty() and str(source.get("fulfiller_id", "")) != expected_ship_id:
        return _bad("wrong_contract_fulfiller")
    var frozen: Dictionary = Quote.fixed_reward(source)
    if not bool(frozen.get("ok", false)):
        return frozen
    var staged: Dictionary = world.duplicate(true)
    var contract: Dictionary = staged["contracts"][contract_id]
    contract["status"] = "posted"
    contract["fulfiller_id"] = null
    contract["accepted_at_tick"] = null
    if bool(frozen["fixed"]):
        contract["payment"] = int(frozen["value"])
    if contract.get("funding", null) is Dictionary:
        contract["funding"]["agreed_payment"] = null
    # Rust contract board release doesn't clear a ShipEconomy active_id:
    # that is cleared by its own BT/lifecycle handler, not this function.
    return {"ok": true, "world": staged, "events": []}

## Rust refund_closed: sorted by contract ID, only Paid/Expired, reserved>0.
## Missing / overflowed beneficiary remains intact for later recovery.
## No payment to nonexistent accounts or treasury fallback.
static func refund_closed(world: Dictionary, tick: int) -> Dictionary:
    if tick < 0 or not (world.get("contracts", null) is Dictionary):
        return _bad("invalid_refund_context")
    var staged: Dictionary = world.duplicate(true)
    var keys: Array = staged["contracts"].keys()
    keys.sort()
    var events: Array = []
    for id in keys:
        var contract: Variant = staged["contracts"][id]
        if not (contract is Dictionary):
            continue
        if not ["paid", "expired"].has(str(contract.get("status", ""))):
            continue
        var funding: Variant = contract.get("funding", null)
        if not (funding is Dictionary):
            continue
        var reserved: Variant = funding.get("reserved", null)
        if typeof(reserved) != TYPE_INT or int(reserved) <= 0:
            continue
        var payer: Dictionary = payer_account(staged, contract)
        if not bool(payer.get("ok", false)):
            continue
        if int(payer["balance"]) > MAX_I64 - int(reserved):
            continue
        _set_balance(staged, payer, int(payer["balance"]) + int(reserved))
        contract["funding"]["reserved"] = 0
        events.append({"kind": "contract_escrow_refunded",
            "contract_id": str(id), "requestor_id": str(contract["requestor_id"]),
            "amount": int(reserved), "tick": tick})
    return {"ok": true, "world": staged, "events": events}

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
