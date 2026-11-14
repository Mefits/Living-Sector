extends RefCounted
## Frozen Rust ship/actions.rs::Buy/Sell/SellAll -> N90 slot -> N146.
## This proposal never transfers cargo or money: only N39/N97 Apply may.
const Slot = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const Commands = preload("res://scripts/simulation/native_sim_command_buffer.gd")
const Market = preload("res://scripts/port/n97_ship_market_rules.gd")
const Relations = preload("res://scripts/sim/phase1/n150_native_full_faction_relations.gd")
const Bt = preload("res://scripts/sim/ships/ai/native_behavior_tree.gd")

static func _fail(why: String) -> Dictionary:
    return {"status": Bt.FAILURE, "reason": "n83_" + why}

static func propose(ship: Dictionary, action: Dictionary,
        world: Dictionary, tick: int) -> Dictionary:
    var kind: String = str(action.get("kind", ""))
    if tick < 1 or kind not in ["Buy", "Sell", "SellAll"] or (
            str(ship.get("current_goal", "")) != "trade_route" or
            not str(ship.get("active_contract_id", "")).is_empty()):
        return _fail("invalid_real_trade_goal")
    var slot: Dictionary = ship.get("transaction", Slot.empty())
    if not Slot.valid_slot(slot):
        return _fail("invalid_native_transaction_slot")
    var commodity: String = str(action.get("commodity", ""))
    var expected: Dictionary = {"kind": "buy" if kind == "Buy" else (
        "sell_all" if kind == "SellAll" else "sell"), "commodity": commodity}
    if not slot["pending"].is_empty():
        var poll: Dictionary = Slot.poll(slot, expected)
        if not poll.get("ok", false):
            return _fail("native_poll_rejected")
        ship["transaction"] = poll["state"].duplicate(true)
        var settled_state: String = str(poll.get("status", ""))
        if settled_state == Slot.RUNNING:
            return {"status": Bt.RUNNING, "reason": "n90_wait_real_paid_apply"}
        if settled_state == Slot.FAILURE:
            return _fail(str(poll.get("reason", "n97_rejected")))
        if settled_state == Slot.SUCCESS:
            if kind != "SellAll":
                return {"status": Bt.SUCCESS, "reason": "n97_paid_ack"}
            for qty in ship.get("cargo", {}).values():
                if int(qty) > 0:
                    return {"status": Bt.RUNNING, "reason": "n83_more_cargo_to_sell"}
            return {"status": Bt.SUCCESS, "reason": "n83_all_cargo_sold"}
        return _fail("n90_unknown_reply")
    var loc: String = str(ship.get("location", ""))
    if loc.is_empty() or not ship.get("transit", {}).is_empty() or (
            not world.get("markets", {}).has(loc)):
        return _fail("no_live_source_market_here")
    var market: Dictionary = world["markets"][loc]
    var station: Dictionary = world.get("facilities", {}).get(str(market.get("owner", "")), {})
    if station.is_empty() or str(station.get("location", "")) != loc:
        return _fail("missing_actual_station")
    var known: Variant = ship.get("memory", {}).get("price_knowledge", {}).get(loc, null)
    if not (known is Dictionary):
        return _fail("no_actual_observed_prices")
    if kind == "SellAll":
        # Source Rust: lexical-minimum sellable commodity, one at a time.
        commodity = ""
        var goods: Array = ship.get("cargo", {}).keys()
        goods.sort()
        for good in goods:
            if int(ship["cargo"][good]) > 0 and known.has(good):
                commodity = str(good)
                break
        if commodity.is_empty():
            return {"status": Bt.SUCCESS, "reason": "n83_no_priced_hold_left"}
    var entry: Variant = known.get(commodity, null)
    if not (entry is Dictionary):
        return _fail("no_original_price_for_commodity")
    var base: float = float(entry.get("price", NAN))
    if not is_finite(base) or base <= 0.0:
        return _fail("invalid_learned_price")
    var buyer: String = str(ship.get("faction_id", ""))
    var operator: String = str(station.get("faction", ""))
    var pairs: Dictionary = world.get("faction_relations", {})
    if not Relations.validate_pairs(pairs) or not Relations.commerce_allowed(
            pairs, buyer, operator):
        return _fail("native_diplomatic_embargo")
    var source_treaty: Dictionary = Relations.state(pairs, buyer, operator)
    var treaties: Dictionary = {}
    treaties[buyer + "\u001f" + operator] = str(source_treaty.get("treaty", "neutral"))
    var posture: Dictionary = Market.posture(treaties, buyer, operator,
        int(ship.get("faction_reputation", {}).get(operator, 0)))
    if not posture.get("ok", false):
        return _fail("invalid_native_reputation")
    var unit: float = base * float(posture["multiplier"])
    if not is_finite(unit) or unit <= 0.0:
        return _fail("invalid_original_quote")
    var quantity: int = 0
    var request: Dictionary = {"kind": "buy" if kind == "Buy" else "sell",
        "location": loc, "commodity": commodity}
    if kind == "Buy":
        var used: int = 0
        for qty in ship.get("cargo", {}).values():
            used += int(qty)
        var free: int = maxi(0, int(ship.get("cargo_capacity", 0)) - used)
        var wanted: int = maxi(0, int(action.get("qty", 0)))
        var high: int = mini(mini(free, wanted), 16777216)
        var low: int = 0
        var credits: int = int(ship.get("credits", 0))
        while low < high:
            var mid: int = low + int((high - low + 1) / 2)
            if ceil(unit * float(mid)) <= float(credits):
                low = mid
            else:
                high = mid - 1
        quantity = low
        if quantity <= 0:
            return _fail("no_affordable_or_free_hold")
        request["max_unit_price"] = unit
    else:
        var have: int = int(ship.get("cargo", {}).get(commodity, 0))
        var wanted: int = int(action.get("qty", 0))
        quantity = mini(have, 16777216) if kind == "SellAll" else mini(
            have, have if wanted == 0 else maxi(0, wanted))
        if quantity <= 0:
            return _fail("empty_hold")
        request["min_unit_price"] = unit
    request["quantity"] = quantity
    var begun: Dictionary = Slot.begin(slot, request)
    if not begun.get("ok", false):
        return _fail("n90_already_pending")
    var cmd: Dictionary = Commands.make_command("RequestShipTransaction", {
        "ship": str(ship.get("id", "")), "request_id": int(begun["request_id"]),
        "operation": "free_trade"})
    if cmd.is_empty():
        return _fail("n146_rejected_real_source_request")
    ship["transaction"] = begun["state"].duplicate(true)
    return {"status": Bt.RUNNING, "commands": [cmd],
        "reason": "n83_real_paid_" + str(request["kind"]) + "_requested"}
