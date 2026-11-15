extends RefCounted
## N90: frozen Rust agents/ship/actions.rs economic ShipAction BT leaves.
## THIS IS PURE DECISION/COMMAND ADMISSION, not the global apply phase.
## No cargo, credit, fuel, inventory, research, XP or location mutations.
## Native 88 life-cycle leaves Dock/Undock/Rest/DockDwell/Construct stay in
## native_ship_action_lifecycle.gd (another PR/owner).
const Slot = preload("res://scripts/simulation/ai/native_ship_transaction_slot.gd")
const SUCCESS: String = "success"
const FAILURE: String = "failure"
const RUNNING: String = "running"
const MAX_U32: int = 4294967295
const COMMODITIES = [
    "ore", "ice", "gas", "rare_ore", "crystal_ore",
    "metals", "fuel", "polymers", "water", "alloys",
    "components", "electronics", "quantum_cores",
    "tools", "food", "medical", "luxury"
]
const REFIT_SLOTS = ["engine", "cargo_bay", "sensors", "reactor", "comms"]

## State is the ephemeral Rust ShipEconomy transaction mailbox plus
## dock_dwell_start_tick used by Mine shifts. A caller supplies the
## persisted authority; a new state must be created only for a new ship.
static func new_state() -> Dictionary:
    return {"transaction": Slot.empty(), "dock_dwell_start_tick": null}

## Snapshot fields read from ShipPosition/ShipTransit/ShipCargo/ShipFuel/
## ShipEconomy/ShipMemory, all REQUIRED unless an action doesn't need them.
##
## ship = {"location": str, "in_transit": bool, "docked_at": str/null,
##         "credits": int, "cargo": {commodity: int}, "cargo_capacity": int,
##         "fuel": float, "fuel_capacity": float,
##         "price_knowledge": {location: {commodity: {"price": float}}},
##         "ship_id": str }
##
## policy = {"commerce_allowed_by_location": {location:bool},
##           "market_buy_multiplier_by_location": {location:float}}
## The caller must compute these using authoritative relations/reputation,
## not infer neutral multipliers or treaty permissions. Rust DOES NOT
## check a treaty gate for Sell/SellAll here; only Buy checks commerce.
##
## Output: status, copied transaction/timer state, and commands intended
## ONLY for exclusive Apply. RequestShipTransaction includes request_id;
## pass no API to mutate balances/cargo in this leaf.
static func step(action: Dictionary, ship: Dictionary,
        previous_state: Dictionary, policy: Dictionary,
        tick: int, tick_multiplier: int) -> Dictionary:
    if tick < 0 or tick_multiplier < 1:
        return _fail(previous_state, "invalid_tick")
    var state: Dictionary = previous_state.duplicate(true)
    if not (state.get("transaction", null) is Dictionary):
        return _fail(state, "missing_transaction_mailbox")
    if not Slot.valid_slot(state["transaction"]):
        return _fail(state, "corrupt_transaction_mailbox")
    var kind: String = str(action.get("kind", ""))
    if ["accept_contract", "embark_passengers", "deliver_cargo"].has(kind):
        var contract_id: Variant = action.get("contract_id", null)
        if not (contract_id is String) or contract_id.is_empty():
            return _fail(state, "missing_contract_id")
        var tx_kind: String = {
            "accept_contract": "accept",
            "embark_passengers": "embark",
            "deliver_cargo": "deliver"
        }[kind]
        return _transaction(state, {"kind": tx_kind,
            "contract_id": contract_id}, {"kind": tx_kind,
            "contract_id": contract_id})
    if kind == "pickup_cargo":
        # Frozen Rust explicitly treats this obsolete leaf as a no-op.
        return _result(SUCCESS, state)
    if kind == "refuel":
        var refuel_poll: Dictionary = _poll(state, {"kind": "refuel"})
        if refuel_poll["status"] == FAILURE:
            return refuel_poll
        if refuel_poll["status"] == RUNNING:
            return refuel_poll
        state = refuel_poll["state"]
        var fuel: Variant = ship.get("fuel", null)
        var capacity: Variant = ship.get("fuel_capacity", null)
        if not _finite(fuel) or not _finite(capacity):
            return _fail(state, "unknown_fuel_state")
        # Rust permits applying a request without a dock check in the leaf;
        # the exclusive Apply phase chooses/determines the actual seller.
        if float(fuel) >= float(capacity) - 0.001:
            return _result(SUCCESS, state)
        var fuel_loc: String = str(ship.get("location", ""))
        if fuel_loc.is_empty():
            return _result(FAILURE, state)
        return _begin(state, {"kind": "refuel", "location": fuel_loc})

    if kind == "mine":
        var location: String = str(action.get("location", ""))
        var body: String = str(action.get("body_id", ""))
        var commodity: String = str(action.get("commodity", ""))
        var quantity: Variant = action.get("quantity", null)
        if location.is_empty() or body.is_empty() or not COMMODITIES.has(commodity):
            return _fail(state, "invalid_mine_source")
        if not _u32(quantity):
            return _fail(state, "invalid_mine_quantity")
        var expected: Dictionary = {"kind": "mine", "location": location,
            "body_id": body, "commodity": commodity, "quantity": int(quantity)}
        var mine_poll: Dictionary = _poll(state, expected)
        if mine_poll["status"] != Slot.NONE:
            return mine_poll
        state = mine_poll["state"]
        var cargo_state: Dictionary = _cargo_details(ship)
        if not bool(cargo_state.get("ok", false)):
            return _fail(state, "invalid_physical_hold")
        if (str(ship.get("location", "")) != location
                or bool(ship.get("in_transit", false))
                or ship.get("docked_at", null) != null
                or int(cargo_state["free"]) == 0):
            state["dock_dwell_start_tick"] = null
            return _result(FAILURE, state)
        var start_value: Variant = state.get("dock_dwell_start_tick", null)
        if start_value == null:
            state["dock_dwell_start_tick"] = tick
            start_value = tick
        if typeof(start_value) != TYPE_INT or int(start_value) < 0:
            return _fail(state, "invalid_mine_shift_cursor")
        var shift: int = 3 * tick_multiplier
        if maxi(0, tick - int(start_value)) < shift:
            return _result(RUNNING, state)
        state["dock_dwell_start_tick"] = null
        return _begin(state, {
            "kind": "mine", "location": location, "body_id": body,
            "commodity": commodity,
            "quantity": mini(int(quantity), int(cargo_state["free"]))
        })

    if kind == "buy":
        var buy_commodity: String = str(action.get("commodity", ""))
        if not COMMODITIES.has(buy_commodity) or not _u32(action.get("quantity", null)):
            return _fail(state, "invalid_buy_intent")
        var buy_poll: Dictionary = _poll(state,
            {"kind": "buy", "commodity": buy_commodity})
        if buy_poll["status"] != Slot.NONE:
            return buy_poll
        state = buy_poll["state"]
        var buy_at: String = str(ship.get("location", ""))
        if buy_at.is_empty():
            return _result(FAILURE, state)
        var allowed_map: Variant = policy.get("commerce_allowed_by_location", null)
        if not (allowed_map is Dictionary):
            return _fail(state, "missing_treaty_authority")
        if typeof(allowed_map.get(buy_at, null)) != TYPE_BOOL:
            return _fail(state, "missing_treaty_decision")
        if not bool(allowed_map[buy_at]):
            return _result(FAILURE, state)
        var buy_base: Dictionary = _price_at(ship, buy_at, buy_commodity)
        if not bool(buy_base.get("ok", false)):
            return _result(FAILURE, state)
        var posture_buy: Dictionary = _posture_at(policy, buy_at)
        if not bool(posture_buy.get("ok", false)):
            return _fail(state, "missing_market_posture_authority")
        var buy_price: float = float(buy_base["price"]) * float(posture_buy["multiplier"])
        var hold: Dictionary = _cargo_details(ship)
        if not bool(hold.get("ok", false)):
            return _fail(state, "invalid_physical_hold")
        var credits: Variant = ship.get("credits", null)
        if typeof(credits) != TYPE_INT:
            return _fail(state, "missing_credits_authority")
        var want: int = mini(affordable_quantity(
            int(credits), buy_price, int(hold["free"])), int(action["quantity"]))
        if want == 0:
            return _result(FAILURE, state)
        return _begin(state, {"kind": "buy", "location": buy_at,
            "commodity": buy_commodity, "quantity": want,
            "max_unit_price": buy_price})

    if kind == "sell" or kind == "sell_all":
        var sell_commodity: String = str(action.get("commodity", ""))
        if kind == "sell" and (not COMMODITIES.has(sell_commodity)
                or not _u32(action.get("quantity", null))):
            return _fail(state, "invalid_sell_intent")
        var sell_poll: Dictionary = _poll(state,
            {"kind": "sell_all"} if kind == "sell_all" else
            {"kind": "sell", "commodity": sell_commodity})
        if sell_poll["status"] == FAILURE or sell_poll["status"] == RUNNING:
            return sell_poll
        state = sell_poll["state"]
        var cargo: Dictionary = _cargo_details(ship)
        if not bool(cargo.get("ok", false)):
            return _fail(state, "invalid_physical_hold")
        if kind == "sell_all" and sell_poll["status"] == SUCCESS:
            if int(cargo["used"]) > 0:
                return _result(RUNNING, state)
            return _result(SUCCESS, state)
        if kind == "sell" and sell_poll["status"] == SUCCESS:
            return _result(SUCCESS, state)
        var at: String = str(ship.get("location", ""))
        if at.is_empty():
            return _result(FAILURE, state)
        var amount: int = 0
        if kind == "sell":
            var known_qty: int = int((ship["cargo"] as Dictionary).get(sell_commodity, 0))
            amount = known_qty if int(action["quantity"]) == 0 else mini(
                int(action["quantity"]), known_qty)
            if amount <= 0:
                return _result(FAILURE, state)
        else:
            # HashMap iteration is not canonical in Rust: SellAll explicitly
            # sorts candidate commodities lexically by as_str().
            var keys: Array = (ship["cargo"] as Dictionary).keys()
            keys.sort()
            for key in keys:
                if int(ship["cargo"][key]) <= 0:
                    continue
                var priced: Dictionary = _price_at(ship, at, str(key))
                if bool(priced.get("ok", false)):
                    sell_commodity = str(key)
                    amount = int(ship["cargo"][key])
                    break
            if amount == 0:
                # Rust returns Success even if unpriced cargo remains.
                return _result(SUCCESS, state)
        var price: Dictionary = _price_at(ship, at, sell_commodity)
        if not bool(price.get("ok", false)):
            return _result(FAILURE, state)
        var posture_sell: Dictionary = _posture_at(policy, at)
        if not bool(posture_sell.get("ok", false)):
            return _fail(state, "missing_market_posture_authority")
        return _begin(state, {"kind": "sell", "location": at,
            "commodity": sell_commodity, "quantity": amount,
            "min_unit_price": float(price["price"]) * float(posture_sell["multiplier"])})

    if kind == "refit":
        if ship.get("docked_at", null) == null:
            return _result(FAILURE, state)
        var slot_name: String = str(action.get("slot", ""))
        var slug: String = str(action.get("slug", ""))
        if not REFIT_SLOTS.has(slot_name) or slug.is_empty():
            return _fail(state, "invalid_refit_slot")
        # Rust emits a request and returns BT Success immediately; stock,
        # cost and retrofit points are rechecked by the Apply phase.
        return _result(SUCCESS, state, [{
            "type": "RequestRefit", "slot": slot_name, "slug": slug
        }])
    if kind == "gate_jump":
        var src: String = str(action.get("src_gate", ""))
        var dest: String = str(action.get("dest_gate", ""))
        if src.is_empty() or dest.is_empty() or str(ship.get("location", "")) != src:
            return _result(FAILURE, state)
        if typeof(ship.get("credits", null)) != TYPE_INT:
            return _fail(state, "missing_gate_credits")
        if int(ship["credits"]) < 50:
            return _result(FAILURE, state)
        # Executable Rust speculatively sets position=dest and undocks
        # immediately, even though Apply could reject gate fee. For a PURE
        # port return that phase-1 local patch explicitly; do not apply it
        # to world authority or the saved ship until the future adapter.
        return _result(SUCCESS, state, [{
            "type": "RequestGateJump", "src_gate_location": src,
            "dest_gate_location": dest
        }], {"native_local_position_patch": {
            "location": dest, "docked_at": null
        }, "requires_apply_confirmation": true})
    return _fail(state, "unknown_or_n88_lifecycle_action")

## Rust affordable_quantity: positive price/credits, price division,
## saturating f64→u32 and min with physical free cargo capacity.
static func affordable_quantity(credits: int, price: float, capacity: int) -> int:
    if not is_finite(price) or price <= 0.0 or credits <= 0 or capacity <= 0:
        return 0
    var by_credits: float = floor(float(credits) / float(price))
    return mini(capacity, int(minf(float(MAX_U32), by_credits)))

static func _poll(state: Dictionary, expected: Dictionary) -> Dictionary:
    var check: Dictionary = Slot.poll(state["transaction"], expected)
    if not bool(check.get("ok", false)):
        return _fail(state, str(check.get("reason", "invalid_slot")))
    var updated: Dictionary = state.duplicate(true)
    updated["transaction"] = check["state"]
    return _result(str(check["status"]), updated,
        [], {"reason": str(check.get("reason", ""))})

static func _transaction(state: Dictionary, expected: Dictionary,
        request: Dictionary) -> Dictionary:
    var check: Dictionary = _poll(state, expected)
    if check["status"] != Slot.NONE:
        return check
    return _begin(check["state"], request)

static func _begin(state: Dictionary, request: Dictionary) -> Dictionary:
    var begun: Dictionary = Slot.begin(state["transaction"], request)
    if not bool(begun.get("ok", false)):
        return _fail(state, str(begun.get("reason", "transaction_rejected")))
    var updated: Dictionary = state.duplicate(true)
    updated["transaction"] = begun["state"]
    return _result(RUNNING, updated, [begun["command"]],
        {"request_id": begun["request_id"], "request": request.duplicate(true)})

static func _price_at(ship: Dictionary, at: String, commodity: String) -> Dictionary:
    var known: Variant = ship.get("price_knowledge", null)
    if not (known is Dictionary) or not (known.get(at, null) is Dictionary):
        return {"ok": false}
    var p: Variant = known[at].get(commodity, null)
    if not (p is Dictionary):
        return {"ok": false}
    var value: Variant = p.get("price", null)
    if not _finite(value):
        return {"ok": false}
    return {"ok": true, "price": float(value)}

static func _posture_at(policy: Dictionary, at: String) -> Dictionary:
    var map: Variant = policy.get("market_buy_multiplier_by_location", null)
    if not (map is Dictionary) or not map.has(at) or not _finite(map[at]):
        return {"ok": false}
    if float(map[at]) < 0.0:
        return {"ok": false}
    return {"ok": true, "multiplier": float(map[at])}

static func _cargo_details(ship: Dictionary) -> Dictionary:
    var cargo: Variant = ship.get("cargo", null)
    var capacity: Variant = ship.get("cargo_capacity", null)
    if not (cargo is Dictionary) or not _u32(capacity):
        return {"ok": false}
    var used: int = 0
    for key in cargo:
        if not COMMODITIES.has(str(key)) or not _u32(cargo[key]):
            return {"ok": false}
        used += int(cargo[key])
        if used > MAX_U32 or used > int(capacity):
            return {"ok": false}
    return {"ok": true, "used": used, "free": int(capacity) - used}

static func _finite(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

static func _u32(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_U32

static func _result(status: String, state: Dictionary,
        commands: Array = [], flags: Dictionary = {}) -> Dictionary:
    return {
        "status": status, "state": state.duplicate(true),
        "commands": commands.duplicate(true), "flags": flags.duplicate(true)
    }

static func _fail(state: Dictionary, reason: String) -> Dictionary:
    return _result(FAILURE, state, [], {"reason": reason})
