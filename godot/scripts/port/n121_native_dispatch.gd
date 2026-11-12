extends RefCounted
## N121 source: strategy/planning/native_execution.rs::post_native_delivery
## and economy/contracts.rs::ContractBoard::post_subsidy/register_prepaid.
##
## The dispatcher uses the same real SOURCE market, global uniqueness,
## physical carrier, cost/route, treasury floor, and per-cycle gates.
## Returns copies of ONE world+board or no changes. NO new commodity
## stock: subsidy is an escrow-funded delivery *obligation*, not output.
const Receipts = preload("res://scripts/port/n121_native_receipts.gd")
const FACTION_SUBSIDY_FLOOR: int = 5000
const SUBSIDY_LIFESPAN_BASE: int = 500
const REP_GATE_FACTION_ONLY: int = 70
const MAX_I64: int = 9223372036854775807
const MAX_U32: int = 4294967295
const F32_MAX: float = 3.4028234663852886e38
const BASE_PRICE = {
    "ore": 15.0, "ice": 10.0, "gas": 20.0,
    "rare_ore": 75.0, "crystal_ore": 140.0,
    "metals": 45.0, "fuel": 25.0, "polymers": 40.0,
    "water": 12.0, "alloys": 145.0,
    "components": 80.0, "electronics": 120.0,
    "quantum_cores": 320.0, "tools": 90.0,
    "food": 18.0, "medical": 100.0, "luxury": 150.0
}
const PROJECT_TAG: String = "strategy.logistics.v1"
const OTHER_PROJECT_TAGS = [
    "strategy.construction.v1", "strategy.colony.v1"
]

## Raw snapshot must come from authoritative PlanningSnapshot.capture,
## not from the action's hypothetical projection. Strict schema:
## snapshot:{owned_markets,active_commitments}
## world:{global_markets,ships,factions,nav_shortest_distance}
## board:{contracts,next_id,by_status,posted_by_destination,
##        posted_by_faction}. 
static func preflight(world: Dictionary, board: Dictionary,
        snapshot: Dictionary, faction_id: String, action: Dictionary,
        dispatch_key: String, tick: int, mult: int) -> Dictionary:
    if tick < 0 or faction_id.is_empty() or dispatch_key.is_empty():
        return _err("invalid_native_dispatch_identity")
    var kind: String = str(action.get("kind", ""))
    var units_value: Variant = action.get("units", null)
    var reward_value: Variant = action.get("cost_credits", null)
    if (kind != "deliver" or not _u32(units_value)
            or int(units_value) <= 0
            or typeof(reward_value) != TYPE_INT
            or int(reward_value) <= 0):
        return _err("invalid_delivery_action")
    var units: int = int(units_value)
    var reward: int = int(reward_value)
    var source: String = str(action.get("source_id", ""))
    var dest: String = str(action.get("destination_id", ""))
    if source.is_empty():
        return _err("delivery_source_missing")
    if dest.is_empty() or source == dest:
        return _err("same_source_and_destination")
    var from_market: Dictionary = Receipts.unique_owned_market(snapshot, source)
    if not bool(from_market.get("ok", false)):
        return _err("source_market_changed_or_ambiguous")
    var to_market: Dictionary = Receipts.unique_owned_market(snapshot, dest)
    if not bool(to_market.get("ok", false)):
        return _err("destination_market_changed_or_ambiguous")
    var from: Dictionary = from_market["market"]
    var to: Dictionary = to_market["market"]
    if (not Receipts.unique_global_market(world, source, str(from["market_id"]))
            or not Receipts.unique_global_market(world, dest, str(to["market_id"]))):
        return _err("native_global_market_ambiguity")
    var commodity: String = str(action.get("commodity", ""))
    if not BASE_PRICE.has(commodity):
        return _err("delivery_commodity_missing")
    var expected_id: String = ("htn-preview:deliver:%s:%s:%s:%d" %
        [str(from["market_id"]), str(to["market_id"]), commodity, units])
    if str(action.get("action_id", "")) != expected_id:
        return _err("native_market_identity_changed")
    if not (from.get("stock", null) is Dictionary):
        return _err("invalid_native_market_source")
    var physical_source: Variant = from["stock"].get(commodity, 0.0)
    if not _num(physical_source) or float(physical_source) < float(units):
        return _err("native_source_stock_gone")
    if not (from.get("prices", null) is Dictionary):
        return _err("missing_source_prices")
    var price: Variant = (from["prices"] as Dictionary).get(
        commodity, BASE_PRICE[commodity])
    if not _num(price) or float(price) <= 0.0:
        return _err("no_native_source_price")
    if float(price) > F32_MAX:
        return _err("native_price_out_of_range")
    # Native sourcing::purchase_cost(price as f32, units, relations,
    # faction_id, 0, faction_id) => own-faction 100 rep => 0.75x.
    # Rust f32 multiply is not bit-exact in double-only GDScript;
    # the invoice is rechecked by the true N97 transaction Apply.
    var purchase_float: float = ceil(float(price) * 0.75 * float(units))
    if not is_finite(purchase_float) or purchase_float <= 0.0             or purchase_float >= float(MAX_I64):
        return _err("native_quote_invalid")
    var purchase: int = int(purchase_float)
    if purchase >= reward:
        return _err("native_price_exceeds_funded_reward")
    var nav: Variant = world.get("nav_shortest_distance", null)
    if not (nav is Dictionary):
        return _err("native_route_unavailable")
    var travel_key: String = source + "\u001f" + dest
    var distance: Variant = nav.get(travel_key, null)
    if typeof(distance) != TYPE_INT or int(distance) < 0:
        return _err("native_route_unavailable")
    if not (snapshot.get("active_commitments", null) is Array):
        return _err("missing_native_commitments")
    var assigned: Dictionary = {}
    for commitment in snapshot["active_commitments"]:
        if not (commitment is Dictionary):
            return _err("invalid_native_commitment")
        var assigned_id: Variant = commitment.get("assigned_ship_id", null)
        if assigned_id != null:
            assigned[str(assigned_id)] = true
    if not (world.get("ships", null) is Dictionary):
        return _err("missing_native_carrier_registry")
    var carrier: String = ""
    # Stable result is intentionally not a dispatch command; original
    # source only checks existence, then station order assigns itself.
    var ship_ids: Array = world["ships"].keys()
    ship_ids.sort()
    for id in ship_ids:
        var ship: Variant = world["ships"][id]
        if not (ship is Dictionary):
            continue
        if (str(ship.get("faction_id", "")) != faction_id
                or assigned.has(str(id))
                or str(ship.get("location", "")) != source):
            continue
        if (not (ship.get("transit", null) is Dictionary)
                or not (ship["transit"] as Dictionary).is_empty()):
            continue
        var capacity: Variant = ship.get("cargo_capacity", null)
        var cargo: Variant = ship.get("cargo", null)
        if not _u32(capacity) or not (cargo is Dictionary):
            continue
        var total: int = 0
        var correct: bool = true
        for good in cargo:
            if not _u32(cargo[good]) or total > MAX_U32 - int(cargo[good]):
                correct = false
                break
            total += int(cargo[good])
        if (not correct or total > int(capacity)
                or int(capacity) - total < units):
            continue
        var fuel: Variant = ship.get("fuel", null)
        var credits: Variant = ship.get("credits", null)
        if (not _num(fuel) or float(fuel) <= 0.0
                or typeof(credits) != TYPE_INT
                or int(credits) < purchase):
            continue
        if ship.get("active_contract_id", null) != null:
            continue
        carrier = str(id)
        break
    if carrier.is_empty():
        return _err("no_funded_idle_native_carrier")
    if not (board.get("contracts", null) is Dictionary):
        return _err("missing_native_contract_board")
    for contract in board["contracts"].values():
        if not (contract is Dictionary):
            return _err("invalid_native_contract_board")
        if (str(contract.get("requestor_id", "")) == faction_id
                and str(contract.get("destination_location", "")) == dest
                and str(contract.get("commodity", "")) == commodity
                and not ["paid", "expired"].has(
                    str(contract.get("status", "")))):
            return _err("existing_native_delivery_commitment")
    if (not (world.get("factions", null) is Dictionary)
            or not (world["factions"].get(faction_id, null) is Dictionary)):
        return _err("native_treasury_floor")
    var treasury: Variant = world["factions"][faction_id].get("treasury", null)
    if (typeof(treasury) != TYPE_INT
            or int(treasury) < FACTION_SUBSIDY_FLOOR
            or int(treasury) - FACTION_SUBSIDY_FLOOR < reward):
        return _err("native_treasury_floor")
    var measured: int = int(distance)
    if measured > (MAX_I64 - 1200) / 100:
        return _err("contract_expiry_overflow")
    var horizon: int = maxi(SUBSIDY_LIFESPAN_BASE, measured * 100 + 1200)
    if horizon > MAX_I64 / maxi(mult, 1):
        return _err("contract_expiry_overflow")
    var lifespan: int = horizon * maxi(mult, 1)
    if tick > MAX_I64 - lifespan:
        return _err("contract_expiry_overflow")
    return {"ok": true, "faction_id": faction_id, "dispatch_key": dispatch_key,
        "source": source, "destination": dest, "commodity": commodity,
        "units": units, "reward": reward, "purchase_cost": purchase,
        "lifespan_ticks": lifespan, "tick": tick, "carrier_proven": true,
        "source_market_id": str(from["market_id"]),
        "destination_market_id": str(to["market_id"])}

## Atomic Rust-equivalent debit and subsidy board post. The source
## regenerates native ID ContractBoard.next_id+1; never reuses an
## existing contract ID and never reissues a prepared dispatch key.
static func commit_paid_delivery(world: Dictionary, board: Dictionary,
        snapshot: Dictionary, faction_id: String, action: Dictionary,
        dispatch_key: String, tick: int, mult: int) -> Dictionary:
    var admissible: Dictionary = preflight(world, board, snapshot,
        faction_id, action, dispatch_key, tick, mult)
    if not bool(admissible.get("ok", false)):
        return admissible
    for contract in board["contracts"].values():
        if (contract is Dictionary
                and contract.get("funding", null) is Dictionary):
            var station_order: Variant = contract["funding"].get(
                "station_order", null)
            if (station_order is Dictionary
                    and str(station_order.get("order_id", "")) ==
                    "station:htn:" + dispatch_key):
                return _err("already_dispatched_native_order")
    if not (board.get("next_id", null) is int):
        return _err("invalid_contract_next_id")
    var next_id: int = int(board["next_id"]) + 1
    if next_id <= 0 or next_id >= MAX_I64:
        return _err("contract_id_overflow")
    var id: String = "contract-" + str(next_id)
    if board["contracts"].has(id):
        return _err("contract_id_collision")
    # To match Rust board, all indexes must be updated together with the
    # new contract record. Missing index metadata => no partial post.
    if (not (board.get("by_status", null) is Dictionary)
            or not (board.get("posted_by_destination", null) is Dictionary)
            or not (board.get("posted_by_faction", null) is Dictionary)):
        return _err("missing_contract_board_indexes")
    var staged_world: Dictionary = world.duplicate(true)
    var staged_board: Dictionary = board.duplicate(true)
    var reward: int = int(admissible["reward"])
    staged_world["factions"][faction_id]["treasury"] = int(
        world["factions"][faction_id]["treasury"]) - reward
    staged_world["factions"][faction_id]["dirty"] = true
    staged_board["next_id"] = next_id
    var funded: Dictionary = {
        "source": "faction", "reserved": reward, "agreed_payment": null,
        "embarked": null,
        "station_order": {
            "order_id": "station:htn:" + dispatch_key,
            "executor_id": null, "state": "waiting",
            "blocked_reason": null, "attempt": 0,
            "assigned_tick": 0, "retry_after_tick": 0
        }
    }
    var contract: Dictionary = {
        "id": id, "contract_type": "subsidy", "status": "posted",
        "requestor_id": faction_id, "faction_id": faction_id,
        "fulfiller_id": null, "commodity": admissible["commodity"],
        "quantity": admissible["units"],
        "source_location": admissible["source"],
        "destination_location": admissible["destination"],
        "payment": reward, "initial_payment": reward,
        "funding": funded, "posted_at_tick": tick,
        "accepted_at_tick": null, "expires_at_tick":
            tick + int(admissible["lifespan_ticks"]),
        "mission_category": PROJECT_TAG,
        "min_reputation": REP_GATE_FACTION_ONLY,
        "initial_min_reputation": REP_GATE_FACTION_ONLY,
        "renewal_count": 0
    }
    staged_board["contracts"][id] = contract
    if not (staged_board["by_status"].get("posted", []) is Array)             or not (staged_board["posted_by_destination"].get(
                str(admissible["destination"]), []) is Array):
        return _err("invalid_contract_board_indexes")
    var posted: Array = staged_board["by_status"].get("posted", [])
    posted.append(id)
    staged_board["by_status"]["posted"] = posted
    var destination_ids: Array = staged_board["posted_by_destination"].get(
        str(admissible["destination"]), [])
    destination_ids.append(id)
    staged_board["posted_by_destination"][
        str(admissible["destination"])] = destination_ids
    # Rust posted_by_faction is BTreeMap<Option<faction>,
    # BTreeMap<min_reputation,Vec<contract_id>>>.
    var faction_bucket: Dictionary = staged_board["posted_by_faction"].get(
        faction_id, {})
    var gate_key: String = str(REP_GATE_FACTION_ONLY)
    var tier_ids: Array = faction_bucket.get(gate_key, [])
    if not (tier_ids is Array):
        return _err("invalid_faction_posted_index")
    tier_ids.append(id)
    faction_bucket[gate_key] = tier_ids
    staged_board["posted_by_faction"][faction_id] = faction_bucket
    return {"ok": true, "world": staged_world,
        "board": staged_board, "native_order_id": id,
        "committed_credits": reward,
        "event": {"kind": "native_delivery_submitted",
            "contract_id": id, "dispatch_key": dispatch_key,
            "faction_id": faction_id, "tick": tick,
            "reward": reward, "source": admissible["source"],
            "destination": admissible["destination"]}}

static func already_commissioned_this_tick(board: Dictionary,
        faction_id: String, tick: int) -> bool:
    if not (board.get("contracts", null) is Dictionary):
        return true
    for contract in board["contracts"].values():
        if not (contract is Dictionary):
            continue
        if (str(contract.get("requestor_id", "")) == faction_id
                and int(contract.get("posted_at_tick", -1)) == tick
                and ([PROJECT_TAG] + OTHER_PROJECT_TAGS).has(
                    str(contract.get("mission_category", "")))):
            return true
    return false

static func _u32(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT and int(value) >= 0
        and int(value) <= MAX_U32)

static func _num(value: Variant) -> bool:
    return (value is float or value is int) and is_finite(float(value))

static func _err(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
