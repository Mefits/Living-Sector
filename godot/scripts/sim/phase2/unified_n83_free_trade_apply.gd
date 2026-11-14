extends RefCounted
## ONE P2 bridge for frozen Rust N90 -> N97 -> N9 free trade.
## Reuses original P1 N97::apply_transaction and actual physical
## settlement without promoting a detached fixture to a second World.
## The source N90 mailbox belongs to the real N39 ship row.
const N97 = preload("res://scripts/port/n97_ship_transaction_apply.gd")
const N90 = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const N9 = preload("res://scripts/sim/economy/credit_ledger.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")

static func _bad(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}

static func _fixture(world: Dictionary, ship_id: String) -> Dictionary:
    # Adapt CURRENT authoritative components to the frozen N97 P1
    # source shape. No invented cash, market, commodity or occupied dock.
    if not (world.get("ships") is Dictionary) or not world["ships"].has(ship_id):
        return _bad("n83_ship_not_in_original_world")
    if not (world.get("markets") is Dictionary) or not (
            world.get("facilities") is Dictionary):
        return _bad("n83_missing_actual_market_registry")
    var ship: Dictionary = world["ships"][ship_id]
    var loc: String = str(ship.get("location", ""))
    if not world["markets"].has(loc):
        return _bad("n83_ship_without_physical_market")
    var market: Dictionary = world["markets"][loc]
    var fid: String = str(market.get("owner", ""))
    if fid.is_empty() or not world["facilities"].has(fid):
        return _bad("n83_market_has_no_actual_facility")
    var facility: Dictionary = world["facilities"][fid]
    if str(facility.get("location", "")) != loc or str(facility.get("type", "")) != "station":
        return _bad("n83_market_not_real_station")
    var pairs: Dictionary = world.get("faction_relations", {})
    if not Relations.validate_pairs(pairs):
        return _bad("n83_invalid_real_treaties")
    var normalized: Dictionary = {}
    for pair in pairs.values():
        var a: String = str(pair.get("a", ""))
        var b: String = str(pair.get("b", ""))
        if a.is_empty() or b.is_empty():
            return _bad("n83_unknown_treaty_actor")
        normalized[a + "\u001f" + b] = str(pair.get("treaty", "neutral"))
    var projected_ship: Dictionary = ship.duplicate(true)
    projected_ship["faction_reputation"] = ship.get("faction_reputation", {}).duplicate(true)
    projected_ship["cargo_origin"] = ship.get("cargo_origin", {}).duplicate(true)
    var original_memory: Dictionary = ship.get("memory", {})
    if not (original_memory.get("route_performance", {}) is Dictionary):
        return _bad("n83_invalid_source_trade_memory")
    projected_ship["route_performance"] = original_memory.get(
        "route_performance", {}).duplicate(true)
    projected_ship["crew_task"] = str(ship.get("crew", {}).get(
        "current_task", "idle"))
    var projected_facility: Dictionary = facility.duplicate(true)
    projected_facility["faction_id"] = str(facility.get("faction", ""))
    var docked: Array = []
    for other_id in world["ships"]:
        var other: Dictionary = world["ships"][other_id]
        if str(other.get("docked_at", "")) == fid:
            docked.append(str(other_id))
    projected_facility["docked_ships"] = docked
    var projected_market: Dictionary = market.duplicate(true)
    projected_market["facility_id"] = fid
    projected_market["location"] = loc
    projected_market["trade_volume"] = market.get("trade_volume", {}).duplicate(true)
    var projection: Dictionary = {
        "ships": {}, "facilities": {}, "markets": {},
        "relations": normalized, "market_controllers": {}
    }
    projection["ships"][ship_id] = projected_ship
    projection["facilities"][fid] = projected_facility
    projection["markets"][loc] = projected_market
    projection["market_controllers"][loc] = str(facility.get("faction", ""))
    return {"ok": true, "world": projection, "market_id": loc,
        "facility_id": fid}

static func stage(world: Dictionary, original_ledger: Dictionary,
        ship_id: String, request_id: int, tick: int) -> Dictionary:
    if tick < 1 or request_id < 1:
        return _bad("n83_invalid_paid_request_identity")
    var projection: Dictionary = _fixture(world, ship_id)
    if not projection.get("ok", false):
        return projection
    var ship: Dictionary = world["ships"][ship_id]
    var mailbox: Variant = ship.get("transaction", null)
    if not (mailbox is Dictionary) or not N90.valid_slot(mailbox):
        return _bad("n83_invalid_original_n90_mailbox")
    var pending: Dictionary = mailbox["pending"]
    if pending.is_empty() or int(pending.get("id", -1)) != request_id or (
            pending.get("result", "invalid") != null):
        return _bad("n83_no_authorized_pending_n90_request")
    var request: Dictionary = pending.get("request", {})
    var kind: String = str(request.get("kind", ""))
    if kind not in ["buy", "sell"] or str(request.get("location", "")) != str(ship.get("location", "")):
        return _bad("n83_wrong_original_free_trade_request")
    if not str(ship.get("active_contract_id", "")).is_empty() or (
            str(ship.get("current_goal", "")) != "trade_route"):
        return _bad("n83_ship_has_other_live_obligation")
    if str(ship.get("docked_at", "")) != str(projection["facility_id"]):
        # Native N97 will also enforce docked_ships and all balances;
        # don't synthesize a N21 slot to make a trade pass.
        return _bad("n83_ship_not_at_actual_market_dock")
    var outcome: Dictionary = N97.apply(
        projection["world"], ship_id, request_id, tick)
    if not outcome.get("ok", false) or not (outcome.get("world") is Dictionary):
        return _bad("n83_source_n97_" + str(outcome.get("reason", "invalid")))
    var paid_world: Dictionary = world.duplicate(true)
    var result_fixture: Dictionary = outcome["world"]
    var applied_ship: Dictionary = result_fixture["ships"][ship_id]
    paid_world["ships"][ship_id]["transaction"] = applied_ship["transaction"].duplicate(true)
    if str(outcome.get("status", "")) == "rejected":
        return {"ok": true, "status": "rejected", "world": paid_world,
            "ledger_snapshot": original_ledger.duplicate(true),
            "reason": str(outcome.get("reason", "native_n97_rejected")),
            "ship_id": ship_id, "request_id": request_id, "tick": tick}
    if str(outcome.get("status", "")) != "applied":
        return _bad("n83_unexpected_native_n97_outcome")
    var market_id: String = str(projection["market_id"])
    var fid: String = str(projection["facility_id"])
    var real_market: Dictionary = paid_world["markets"][market_id]
    var real_facility: Dictionary = paid_world["facilities"][fid]
    var real_ship: Dictionary = paid_world["ships"][ship_id]
    var physical_market: Dictionary = result_fixture["markets"][market_id]
    var physical_facility: Dictionary = result_fixture["facilities"][fid]
    var payment: int = int(outcome.get("payment", -1))
    var units: float = float(outcome.get("quantity", -1))
    if payment <= 0 or not is_finite(units) or units <= 0.0 or (
            not is_equal_approx(units, float(roundi(units)))):
        return _bad("n83_invalid_native_n97_quantity_or_payment")
    var ship_delta: int = int(applied_ship["credits"]) - int(ship["credits"])
    var facility_delta: int = int(physical_facility["credits"]) - int(world["facilities"][fid]["credits"])
    if ship_delta + facility_delta != 0 or absi(ship_delta) != payment or (
            (kind == "buy" and ship_delta != -payment) or
            (kind == "sell" and ship_delta != payment)):
        return _bad("n83_source_unbalanced_physical_trade")
    var staged_ledger := N9.new()
    if not staged_ledger.restore(original_ledger):
        return _bad("n83_original_n9_restore_refused")
    var receipt_id: String = "n83:ship:" + ship_id + ":" + str(request_id)
    var transfer: Dictionary = staged_ledger.transfer(
        receipt_id, "ship:" + ship_id if kind == "buy" else "facility:" + fid,
        "facility:" + fid if kind == "buy" else "ship:" + ship_id,
        payment, tick, "native_n97_free_" + kind)
    if not transfer.get("ok", false):
        return _bad("n83_original_n9_" + str(transfer.get("reason", "unfunded")))
    if staged_ledger.balance("ship:" + ship_id) != int(applied_ship["credits"]) or (
            staged_ledger.balance("facility:" + fid) != int(physical_facility["credits"])):
        return _bad("n83_n97_n9_paid_balance_disagrees")
    real_ship["cargo"] = applied_ship["cargo"].duplicate(true)
    real_ship["cargo_age"] = applied_ship["cargo_age"].duplicate(true)
    real_ship["cargo_origin"] = applied_ship["cargo_origin"].duplicate(true)
    real_ship["credits"] = int(applied_ship["credits"])
    real_ship["crew_skills"] = applied_ship["crew_skills"].duplicate(true)
    if real_ship.get("crew") is Dictionary:
        real_ship["crew"]["current_task"] = str(applied_ship.get("crew_task", "idle"))
    if real_ship.get("lifecycle") is Dictionary:
        real_ship["lifecycle"]["dirty"] = true
    if real_ship.get("memory") is Dictionary:
        real_ship["memory"]["route_performance"] = applied_ship["route_performance"].duplicate(true)
    real_facility["credits"] = int(physical_facility["credits"])
    real_facility["dirty"] = true
    real_market["supply"] = physical_market["supply"].duplicate(true)
    real_market["trade_volume"] = physical_market["trade_volume"].duplicate(true)
    real_market["dirty"] = true
    if not (paid_world.get("cargo_receipts") is Dictionary):
        return _bad("n83_missing_original_n15_receipt_registry")
    if paid_world["cargo_receipts"].has(receipt_id):
        return _bad("n83_replayed_native_n15_goods")
    var event: Dictionary = {
        "operation_id": receipt_id, "tick": tick,
        "kind": "native_n97_free_" + kind, "ship_id": ship_id,
        "facility_id": fid, "location": market_id,
        "commodity": str(request.get("commodity", "")),
        "quantity": int(roundi(units)), "payment": payment,
        "request_id": request_id, "financial_receipt": receipt_id}
    paid_world["cargo_receipts"][receipt_id] = event.duplicate(true)
    return {"ok": true, "status": "applied", "world": paid_world,
        "ledger_snapshot": staged_ledger.snapshot(),
        "receipt": event, "ship_id": ship_id, "request_id": request_id,
        "tick": tick, "kind": kind, "payment": payment,
        "quantity": int(roundi(units))}
