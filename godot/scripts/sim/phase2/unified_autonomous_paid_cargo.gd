extends RefCounted
## P2 N97/N15/N104: physical funded delivery, proposed in isolation.
## N21 dock, N15 CargoTransfer, one N9 Ledger, original N104 Board.
## This is NOT a second World or money system: only N39 can commit it.
const Fleet = preload("res://scripts/sim/phase2/unified_fleet_logistics.gd")
const Ledger = preload("res://scripts/sim/economy/credit_ledger.gd")
const Board = preload("res://scripts/sim/economy/contract_board.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Catalog = preload("res://scripts/sim/economy/commodity_catalog.gd")
const MarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")
const NativeDiplomacy = preload("res://scripts/sim/phase2/unified_native_diplomacy_phase.gd")
const MAX_SAFE_MONEY: float = 9007199254740991.0

static func propose(original: Dictionary, bank: Dictionary,
        ship_id: String, contract_id: String, direction: String,
        tick: int) -> Dictionary:
    if direction not in ["pickup", "delivery"] or tick < 0:
        return {"ok": false, "reason": "invalid_native_contract_operation"}
    if not (original.get("contract_board") is Dictionary) or not (original.get("ships") is Dictionary):
        return {"ok": false, "reason": "missing_native_contract_authority"}
    var contracts: Dictionary = original["contract_board"].get("contracts", {})
    if not contracts.has(contract_id) or not original["ships"].has(ship_id):
        return {"ok": false, "reason": "unknown_delivery_or_ship"}
    var c: Dictionary = contracts[contract_id]
    var ship: Dictionary = original["ships"][ship_id]
    var expected: String = "accepted" if direction == "pickup" else "picked_up"
    if str(c.get("status", "")) != expected or str(c.get("contract_type", "")) != "delivery":
        return {"ok": false, "reason": "invalid_delivery_stage"}
    if str(c.get("fulfiller_id", "")) != ship_id or str(ship.get("active_contract_id", "")) != contract_id:
        return {"ok": false, "reason": "not_the_contract_ship"}
    var location: String = str(c["source_location"]) if direction == "pickup" else str(c["destination_location"])
    var good: String = str(c.get("commodity", ""))
    var count: int = int(c.get("quantity", 0))
    if count < 1 or not Catalog.contains(good):
        return {"ok": false, "reason": "invalid_original_goods"}
    if str(ship.get("location", "")) != location or not (ship.get("transit", {}) as Dictionary).is_empty():
        return {"ok": false, "reason": "not_at_original_contract_location"}
    if not original["markets"].has(location):
        return {"ok": false, "reason": "original_market_missing"}
    var market: Dictionary = original["markets"][location]
    var station: String = str(market.get("owner", ""))
    if station.is_empty() or not original["facilities"].has(station) or str(ship.get("docked_at", "")) != station:
        return {"ok": false, "reason": "not_docked_at_contract_warehouse"}
    if str(original["facilities"][station].get("location", "")) != location:
        return {"ok": false, "reason": "market_station_mismatch"}
    # Frozen Rust faction_relations::commerce_allowed is consulted by
    # the actual market buyer. Do not let N97 pay/transfer inventory at
    # an explicitly Hostile/War controller, even with a funded contract.
    # A completed delivery never retroactively revokes an already-paid
    # pickup, so this check applies to source purchases only.
    if direction == "pickup" and not NativeDiplomacy.commerce_allowed(
            original, ship_id, location):
        return {"ok": false, "reason": "n150_real_treaty_commerce_embargo"}
    var operation_id: String = "contract:" + contract_id + (":load" if direction == "pickup" else ":unload")
    if original.get("cargo_receipts", {}).has(operation_id):
        return {"ok": false, "reason": "duplicate_physical_contract_receipt"}
    if direction == "delivery":
        var pickup_id: String = "contract:" + contract_id + ":load"
        var pickup: Dictionary = original.get("cargo_receipts", {}).get(pickup_id, {})
        if pickup.get("ok", false) != true or str(pickup.get("ship_id", "")) != ship_id or str(pickup.get("operation_id", "")) != pickup_id:
            return {"ok": false, "reason": "missing_original_paid_pickup"}
        if str(pickup.get("action", "")) != "load" or str(pickup.get("location_id", "")) != str(c["source_location"]):
            return {"ok": false, "reason": "original_pickup_receipt_wrong_source"}
        var expected_pickup: Dictionary = {}
        expected_pickup[good] = count
        if pickup.get("quantities", {}) != expected_pickup or str(c.get("picked_up_receipt", "")) != pickup_id:
            return {"ok": false, "reason": "original_pickup_receipt_wrong_quantity"}
    var ledger := Ledger.new()
    if not ledger.restore(bank):
        return {"ok": false, "fatal": true, "reason": "invalid_single_n9_ledger"}
    var board := Board.new(ledger)
    if not board.restore(original["contract_board"]):
        return {"ok": false, "fatal": true, "reason": "invalid_single_n104_board"}
    var staged: Dictionary = original.duplicate(true)
    var opened: Dictionary = Fleet._open(staged)
    if not opened.get("ok", false):
        return opened
    var gate: RefCounted = opened["gate"]
    var quantities: Dictionary = {}
    quantities[good] = count
    var transfer: Dictionary = gate.transfer(ship_id, station, quantities,
        operation_id, "load" if direction == "pickup" else "unload", tick)
    if not transfer.get("ok", false):
        return transfer
    # The actual N15 gate has debited the detached warehouse and credited
    # the detached ship, or vice versa. Persist exactly these two inventories.
    staged["ships"][ship_id]["cargo"] = (opened["fleet"].ships[ship_id]["cargo"] as Dictionary).duplicate(true)
    staged["markets"][location]["supply"] = (gate.warehouses[station] as Dictionary).duplicate(true)
    var receipt: Dictionary = {"ok": true,
        "action": "load" if direction == "pickup" else "unload",
        "ship_id": ship_id, "facility_id": station, "operation_id": operation_id,
        "tick": tick, "quantities": quantities.duplicate(true), "location_id": location}
    staged["cargo_receipts"][operation_id] = receipt.duplicate(true)
    # ContractBoard checks the REAL N15 domain's durable receipt. Its old
    # source expected "direction", canonical N15 receipts use "action".
    gate.cargo_transfer.receipts[operation_id] = receipt.duplicate(true)
    board.bind_physical_cargo(gate.cargo_transfer)
    var money_id: String = ""
    var paid: int = 0
    if direction == "pickup":
        var price: float = float(original["markets"][location].get("prices", {}).get(good, 0.0))
        if not is_finite(price) or price <= 0.0:
            return {"ok": false, "reason": "n97_invalid_live_source_quote"}
        var seller_faction: String = str(original["facilities"][station].get("faction", ""))
        var ship_faction: String = str(ship.get("faction_id", ""))
        var reputation: Dictionary = ship.get("faction_reputation", {})
        var posture: Dictionary = MarketRules.posture({}, ship_faction,
            seller_faction, int(reputation.get(seller_faction, 0)))
        if not posture.get("ok", false):
            return {"ok": false, "reason": "n97_native_market_posture_unavailable"}
        var cost: float = ceil(price * float(posture["multiplier"]) * float(count))
        if not is_finite(cost) or cost <= 0.0 or cost > MAX_SAFE_MONEY:
            return {"ok": false, "reason": "n97_purchase_overflow"}
        paid = int(cost)
        var maximum: int = int(ship.get("max_source_cost", 0))
        if maximum <= 0 or paid > maximum:
            return {"ok": false, "reason": "n97_market_quote_exceeds_accepted_limit"}
        var ship_wallet: String = Schema.ship_account(ship_id)
        var seller_wallet: String = Schema.facility_account(station)
        money_id = "contract:" + contract_id + ":source_buy"
        var buying: Dictionary = ledger.transfer(money_id,
            ship_wallet, seller_wallet, paid, tick, "n97_real_source_buy")
        if not buying.get("ok", false):
            return {"ok": false, "reason": "n97_" + str(buying.get("reason", "cannot_pay"))}
        staged["ships"][ship_id]["credits"] = ledger.balance(ship_wallet)
        staged["facilities"][station]["credits"] = ledger.balance(seller_wallet)
        var confirmed: Dictionary = board.confirm_pickup(contract_id, ship_id, tick, operation_id)
        if not confirmed.get("ok", false):
            return {"ok": false, "reason": "n104_" + str(confirmed.get("reason", "pickup_not_confirmed"))}
    else:
        var delivered: Dictionary = board.confirm_delivery(contract_id, ship_id, tick, operation_id)
        if not delivered.get("ok", false):
            return {"ok": false, "reason": "n104_" + str(delivered.get("reason", "delivery_not_confirmed"))}
        var receiving: Dictionary = board.settle(contract_id, ship_id,
            Schema.ship_account(ship_id), tick)
        if not receiving.get("ok", false):
            return {"ok": false, "reason": "n104_" + str(receiving.get("reason", "unpaid"))}
        paid = int(receiving["paid"])
        money_id = "contract:" + contract_id + ":payout"
        staged["ships"][ship_id]["credits"] = ledger.balance(Schema.ship_account(ship_id))
        staged["escrow_balances"][str(c["escrow_account"])] = ledger.balance(str(c["escrow_account"]))
        staged["ships"][ship_id]["active_contract_id"] = ""
        staged["ships"][ship_id]["current_goal"] = "idle"
        staged["ships"][ship_id]["current_bt"] = null
        staged["ships"][ship_id]["max_source_cost"] = 0
    staged["contract_board"] = board.snapshot()
    if not Schema.validate(staged).is_empty():
        return {"ok": false, "fatal": true, "reason": "n97_invalid_staged_n39_world"}
    var accounts: Dictionary = Schema.accounts(staged)
    var actual: Dictionary = ledger.snapshot().get("balances", {})
    if accounts.size() != actual.size():
        return {"ok": false, "fatal": true, "reason": "n97_account_cardinality"}
    for account in accounts:
        if actual.get(account, null) != accounts[account]:
            return {"ok": false, "fatal": true, "reason": "n97_world_n9_divergence"}
    var old_total: int = 0
    for credits in bank.get("balances", {}).values():
        old_total += int(credits)
    if old_total != ledger.total():
        return {"ok": false, "fatal": true, "reason": "n97_money_not_conserved"}
    return {"ok": true, "status": "N97_N15_N104_REAL_" + direction.to_upper(),
        "world": staged, "ledger_snapshot": ledger.snapshot(),
        "ship_id": ship_id, "contract_id": contract_id, "direction": direction,
        "receipt_id": operation_id, "money_receipt": money_id,
        "credits": paid, "tick": tick}
