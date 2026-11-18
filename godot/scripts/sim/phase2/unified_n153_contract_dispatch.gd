extends RefCounted
## P2 N153 autonomous contract choice against ONE N39/N104 world snapshot.
## Source N153 does the actual profitability/cargo/commerce/sensor gating.
## This adapter only supplies verifiable N104/N150/N9/route observations.
## NO fake treaties, ship sensors, market knowledge, fuel or contract success.
const N153 = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const EligibilityIndex = preload("res://scripts/sim/phase2/n153_ship_eligibility_index.gd")
const NativePipeline = preload("res://scripts/sim/phase2/unified_ship_ai_planner.gd")
const Catalog = preload("res://scripts/sim/ship_catalog.gd")
const Schema = preload("res://scripts/sim/phase1/n39_native_world_schema.gd")
const Transit = preload("res://scripts/sim/ship_transit.gd")

## Read-only rejection accounting for native N153. The selector and its
## business requirements remain unchanged. This is only persisted in the
## transient phase result, never in the authoritative contract or wallet.
static func _blocked_ship(reasons: Dictionary, name: String) -> void:
    reasons[name] = int(reasons.get(name, 0)) + 1

## Only immutable-for-this-proposal ship fields are cached. A fresh root is
## allocated by propose() on every paid tick and after every N38 restore.
## Keep the source rejection order: busy -> location -> dock -> cargo -> capacity.
static func _ship_static_readiness(world: Dictionary, ship_id: String,
        cache: Dictionary) -> Dictionary:
    if cache.has(ship_id):
        return cache[ship_id]
    var ship: Dictionary = world["ships"][ship_id]
    var result: Dictionary = {"ok": true}
    if str(ship.get("active_contract_id", "")) != "" or not (ship.get("transit", {}) as Dictionary).is_empty():
        result = {"ok": false, "reason": "ship_busy"}
    elif str(ship.get("location", "")).is_empty():
        result = {"ok": false, "reason": "ship_not_at_real_location"}
    else:
        var dock_id: String = str(ship.get("docked_at", ""))
        if not dock_id.is_empty() and (not world["facilities"].has(dock_id) or
                str(world["facilities"][dock_id].get("location", "")) != str(ship["location"])):
            result = {"ok": false, "reason": "invalid_idle_dock"}
        elif not (ship.get("cargo") is Dictionary) or not ship["cargo"].is_empty():
            result = {"ok": false, "reason": "ship_cargo_not_empty"}
    cache[ship_id] = result
    return result

## Resolve immutable ship fitting once per proposal, but only after route
## success, preserving the source order of route versus class/fuel errors.
static func _ship_flight_fitting(ship: Dictionary, ship_id: String,
        cache: Dictionary) -> Dictionary:
    if cache.has(ship_id):
        return cache[ship_id]
    var ship_class: String = str(ship.get("class", ""))
    var spec: Dictionary = Catalog.spec(ship_class)
    var fitting: Dictionary = {
        "speed": float(ship.get("speed_modifier",
            Catalog.effective_speed(ship_class, str(ship.get("size", ""))))),
        "rate": float(spec.get("fuel_consumption_base", 0.0))
    }
    cache[ship_id] = fitting
    return fitting

static func _ready_ship(world: Dictionary, ship_id: String, contract: Dictionary,
        graph: RefCounted, positions: Dictionary, resolver: RefCounted,
        tick_scale: float, route_index: Dictionary = {},
        readiness_cache: Dictionary = {}, fitting_cache: Dictionary = {}) -> Dictionary:
    var ship: Dictionary = world["ships"][ship_id]
    var static_gate: Dictionary = _ship_static_readiness(world, ship_id, readiness_cache)
    if not static_gate.get("ok", false):
        return static_gate
    var quantity: int = int(contract.get("quantity", 0))
    if quantity < 1 or int(ship.get("cargo_capacity", 0)) < quantity:
        return {"ok": false, "reason": "cargo_capacity"}
    var source: String = str(contract.get("source_location", ""))
    var dest: String = str(contract.get("destination_location", ""))
    var here: String = str(ship.get("location", ""))
    var route: Dictionary = EligibilityIndex.legs(route_index, here, source, dest, graph, positions, false)
    if route.has("error"):
        return {"ok": false, "reason": str(route["error"])}
    var fitting: Dictionary = _ship_flight_fitting(ship, ship_id, fitting_cache)
    var speed: float = float(fitting["speed"])
    var rate: float = float(fitting["rate"])
    if speed <= 0.0 or rate <= 0.0 or float(ship.get("fuel", 0.0)) <= 0.0:
        return {"ok": false, "reason": "invalid_fuel_or_class"}
    # N14 advances one physical directed edge per tick. Check the COMPLETE
    # source+destination trip from real moving world positions before an AI
    # accepts an obligation; otherwise we could strand a ship with cargo.
    # Many ships bid on the same posted offer from the same location.
    # Geometry is immutable during this N153 proposal. Cache only the
    # computed fuel requirement (including invalid geometry), keyed by
    # the actual ship speed and fuel rate; never cache ship eligibility.
    # The route index is proposal-local and rebuilt after every paid tick.
    # Distinct fittings can share a route and velocity but have different
    # consumption rates. Cache the integer edge tick counts once per
    # origin/speed/tick-scale, then retain the original per-edge floating
    # summation for each fuel rate (no reordered arithmetic).
    var travel_key: Array = [here, speed, tick_scale]
    var travel_cache: Dictionary = route_index.get(-2, {})
    var travel: Dictionary = travel_cache.get(travel_key, {})
    if travel.is_empty():
        var counts: Array = []
        var geometry_error: String = ""
        for leg in route["steps"]:
            if not bool(leg["present"]):
                geometry_error = "missing_leg_world_position"
                break
            var distance: float = float(leg["distance"])
            var velocity: float = Transit.BASE_VELOCITY * speed * tick_scale
            if velocity <= 0.0 or not is_finite(distance) or distance <= 0.0:
                geometry_error = "invalid_flight_geometry"
                break
            counts.append(maxi(1, ceili(distance / velocity)))
        travel = {"error": geometry_error} if not geometry_error.is_empty() else {"counts": counts}
        travel_cache[travel_key] = travel
        route_index[-2] = travel_cache
    if travel.has("error"):
        return {"ok": false, "reason": str(travel["error"])}
    var fuel_key: Array = [here, speed, rate, tick_scale]
    var fuel_cache: Dictionary = route_index.get(-1, {})
    var flight_cost: float = 0.0
    if fuel_cache.has(fuel_key):
        flight_cost = float(fuel_cache[fuel_key])
    else:
        for edge_ticks in travel["counts"]:
            flight_cost += float(edge_ticks) * rate * tick_scale
        fuel_cache[fuel_key] = flight_cost
        route_index[-1] = fuel_cache
    if float(ship["fuel"]) + 0.0001 < flight_cost:
        return {"ok": false, "reason": "insufficient_native_full_route_fuel"}
    # Geometry steps are read-only within this call. Detach only the two
    # paths that escape into the winning contract proposal.
    return {"ok": true, "path_to_source": route["inbound"],
        "source_to_destination": route["outbound"]}

## Read-only N154 funding proof. This value is invariant across bidders
## for one posted offer, even when comms bonuses change the required top-up.
## Preserve -1 for unproven payer ownership and missing treasuries.
static func _offer_payer_balance(world: Dictionary, contract: Dictionary,
        contract_id: String, buyer_faction: String, buyer_market: Dictionary,
        buyer: Dictionary) -> int:
    var real_payer: String = str(contract.get("requestor_id", ""))
    if str(contract.get("funding_source", "")) == "faction":
        if (world.get("construction_contracts", {}).has(contract_id) or
                world.get("native_htn_contracts", {}).has(contract_id)) and real_payer == Schema.faction_account(buyer_faction):
            return int(world.get("faction_treasuries", {}).get(buyer_faction, -1))
    elif str(contract.get("funding_source", "")) == "facility":
        if real_payer == Schema.facility_account(str(buyer_market["owner"])):
            return int(buyer["credits"])
    return -1

## Offer-local price result, keyed by posture multiplier. No cross-offer state.
static func _purchase_quote(cache: Dictionary, multiplier: float,
        quantity: int, source_price: float) -> Dictionary:
    if cache.has(multiplier):
        return cache[multiplier]
    var amount: float = ceil(float(quantity) * source_price * multiplier)
    var valid: bool = is_finite(amount) and amount > 0.0 and amount <= 9007199254740991.0
    var result: Dictionary = {"valid": valid, "cost": int(amount) if valid else 0}
    cache[multiplier] = result
    return result

## Ship observations are proposal-local. No mutable ship row escapes.
static func _bid_observation(cache: Dictionary, ship_id: String,
        ship: Dictionary) -> Dictionary:
    if cache.has(ship_id):
        return cache[ship_id]
    var sensor: Variant = ship.get("sensor_range_au", null)
    if not (sensor is int or sensor is float) or not is_finite(float(sensor)) or float(sensor) < 0.0:
        sensor = 2.0 if str(ship.get("size", "")) in ["huge", "massive"] else 1.0
    var result: Dictionary = {"sensor": float(sensor),
        "bonus": float(ship.get("comms_bonus", 0.0))}
    cache[ship_id] = result
    return result

## Immutable-for-this-proposal bidder roster. Do not copy or mutate World ship
## rows: the canonical World cannot change during a synchronous propose().
## Assignment remains offer-order dependent and is checked separately.
static func _bidder_rows(world: Dictionary, ids: Array, factions: Dictionary) -> Array:
    var rows: Array = []
    for ship_id in ids:
        var ship: Dictionary = world["ships"][ship_id]
        var faction_id: String = str(ship.get("faction_id", ""))
        var exists: bool = factions.has(faction_id)
        var outlaw: bool = exists and str(factions[faction_id].get("type", "")) == "outlaw"
        rows.append({"id": str(ship_id), "ship": ship,
            "faction": faction_id, "exists": exists, "outlaw": outlaw})
    return rows

## Seller-specific reputation gates are invariant across posted offers in
## this one proposal. Cache rejection as well as acceptance; never cache a
## contract-specific quote, assignment, cargo or payment decision.
static func _seller_bidder_gate(row: Dictionary, seller_faction: String,
        buyer_faction: String, posture_cache: Dictionary,
        gate_cache: Dictionary) -> Dictionary:
    var seller_cache: Dictionary = gate_cache.get(seller_faction, {})
    var buyer_cache: Dictionary = seller_cache.get(buyer_faction, {})
    var ship_id: String = str(row["id"])
    if buyer_cache.has(ship_id):
        return buyer_cache[ship_id]
    var result: Dictionary = {"ok": true}
    var faction_id: String = str(row["faction"])
    if not bool(row["exists"]):
        result = {"ok": false, "reason": "ship_faction_missing_or_already_assigned"}
    elif bool(row["outlaw"]) and (faction_id != buyer_faction or faction_id != seller_faction):
        result = {"ok": false, "reason": "outlaw_source_commerce_restricted"}
    else:
        var ship: Dictionary = row["ship"]
        var reputation: Dictionary = ship.get("faction_reputation", {})
        var posture: Dictionary = EligibilityIndex.posture(posture_cache,
            faction_id, seller_faction, int(reputation.get(seller_faction, 0)))
        if not posture.get("ok", false):
            result = {"ok": false, "reason": "source_reputation_posture_rejected"}
        else:
            result = {"ok": true, "multiplier": float(posture["multiplier"])}
    buyer_cache[ship_id] = result
    seller_cache[buyer_faction] = buyer_cache
    gate_cache[seller_faction] = seller_cache
    return result

static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, resolver: RefCounted, tick: int,
        tick_scale: float, factions: Dictionary = {}) -> Dictionary:
    if tick < 0 or graph == null or resolver == null or tick_scale <= 0.0 or not is_finite(tick_scale):
        return {"ok": false, "reason": "unavailable_native_ai_context"}
    if not (world.get("ships") is Dictionary) or not (world.get("contract_board") is Dictionary):
        return {"ok": false, "reason": "missing_canonical_contracts_or_fleet"}
    var contracts: Dictionary = world["contract_board"].get("contracts", {})
    if not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "missing_actual_markets"}
    var ships: Array = EligibilityIndex.ship_ids(world)
    var bidder_rows: Array = _bidder_rows(world, ships, factions)
    var seller_gate_cache: Dictionary = {} # seller/buyer/ship, proposal-local
    var ids: Array = EligibilityIndex.offer_ids(contracts)
    var posture_cache: Dictionary = {} # Call-scoped; never survives N38 restore.
    var system_cache: Dictionary = {} # Resolver IDs for one proposal only.
    var candidates: Array = []
    var blocked: Array = []
    var already_assigned: Dictionary = {}
    # Per-proposal geometry: contracts sharing source/destination can reuse
    # the same here->legs index. Never persists across World/tick/N38 load.
    var route_indices: Dictionary = {} # source -> destination -> here -> legs
    var readiness_cache: Dictionary = {} # ship -> stable rejection or ok
    var fitting_cache: Dictionary = {} # ship -> speed and fuel rate
    var observation_cache: Dictionary = {} # ship -> sensor and comms observations
    for contract_id in ids:
        var c: Dictionary = contracts[contract_id]
        if str(c.get("status", "")) != "posted" or str(c.get("contract_type", "")) != "delivery":
            continue
        if tick > int(c.get("expires_at_tick", -1)):
            blocked.append({"contract_id": str(contract_id), "reason": "offer_expired"})
            continue
        var source: String = str(c.get("source_location", ""))
        var dest: String = str(c.get("destination_location", ""))
        if not world["markets"].has(source) or not world["markets"].has(dest):
            blocked.append({"contract_id": str(contract_id), "reason": "market_missing"})
            continue
        var seller_market: Dictionary = world["markets"][source]
        var buyer_market: Dictionary = world["markets"][dest]
        if not world["facilities"].has(str(seller_market.get("owner", ""))) or not world["facilities"].has(str(buyer_market.get("owner", ""))):
            blocked.append({"contract_id": str(contract_id), "reason": "source_owner_missing"})
            continue
        var seller: Dictionary = world["facilities"][str(seller_market["owner"])]
        var buyer: Dictionary = world["facilities"][str(buyer_market["owner"])]
        var good: String = str(c.get("commodity", ""))
        var qty: int = int(c.get("quantity", 0))
        var stock: float = float(seller_market.get("supply", {}).get(good, 0.0))
        if not is_finite(stock) or stock < float(qty):
            blocked.append({"contract_id": str(contract_id), "reason": "source_stock_unavailable"})
            continue
        # Frozen FactionRelations::state_or_default() is Neutral. Regular
        # factions can trade under Neutral; outlaw/regular traffic is NOT
        # opened merely from a missing treaty (pirates are seeded hostile).
        # When live world treaty data arrives, it must override this gate.
        var buyer_faction: String = str(buyer.get("faction", ""))
        var seller_faction: String = str(seller.get("faction", ""))
        if not factions.has(buyer_faction) or not factions.has(seller_faction):
            blocked.append({"contract_id": str(contract_id), "reason": "unknown_source_faction"})
            continue
        if buyer_faction != seller_faction and (str(factions[buyer_faction].get("type", "")) == "outlaw" or str(factions[seller_faction].get("type", "")) == "outlaw"):
            blocked.append({"contract_id": str(contract_id), "reason": "outlaw_commerce_not_authorized"})
            continue
        var source_price: Variant = seller_market.get("prices", {}).get(good, null)
        if not (source_price is int or source_price is float) or not is_finite(float(source_price)) or float(source_price) <= 0.0:
            blocked.append({"contract_id": str(contract_id), "reason": "missing_source_quote"})
            continue
        var winner: Dictionary = {}
        var ship_blockers: Dictionary = {}
        var route_index: Dictionary = EligibilityIndex.offer_route_index(route_indices, source, dest)
        var fixed_offer: Dictionary = {}
        var fixed_controllers: Dictionary = {}
        # The payer, original reserved amount and owning treasury belong to
        # the posted offer, not to each bidding ship. Resolve their proof once
        # per offer; the ship's boosted payment and top-up remain per-bid.
        var payer_balance: int = _offer_payer_balance(world, c, str(contract_id),
            buyer_faction, buyer_market, buyer)
        var reserved_amount: int = int(c["reserved"])
        var base_commerce: Dictionary = {buyer_faction: true, seller_faction: true}
        var fixed_systems: Dictionary = {}
        # A posture multiplier and source quote are fixed for this offer.
        # Keep this local: a later offer can change quantity, price or payer.
        var purchase_quotes: Dictionary = {}
        for bidder in bidder_rows:
            var ship_id: String = str(bidder["id"])
            var ship: Dictionary = bidder["ship"]
            var ship_faction: String = str(bidder["faction"])
            # Assignment is mutable across offers; never cache it. The old
            # rejection priority checks it before outlaw/reputation gates.
            if already_assigned.has(ship_id):
                _blocked_ship(ship_blockers, "ship_faction_missing_or_already_assigned")
                continue
            var bidder_gate: Dictionary = _seller_bidder_gate(bidder,
                seller_faction, buyer_faction, posture_cache, seller_gate_cache)
            if not bool(bidder_gate["ok"]):
                _blocked_ship(ship_blockers, str(bidder_gate["reason"]))
                continue
            var posture_multiplier: float = float(bidder_gate["multiplier"])
            var quote_result: Dictionary = _purchase_quote(purchase_quotes, posture_multiplier, qty, float(source_price))
            if not bool(quote_result["valid"]):
                _blocked_ship(ship_blockers, "invalid_source_purchase_quote")
                continue
            var source_purchase: int = int(quote_result["cost"])
            var readiness: Dictionary = _ready_ship(world, str(ship_id), c, graph, positions, resolver,
                tick_scale, route_index, readiness_cache, fitting_cache)
            if not readiness.get("ok", false):
                _blocked_ship(ship_blockers, "n14_" + str(
                    readiness.get("reason", "unavailable")))
                continue
            var here: String = str(ship["location"])
            # Source-market quote is genuinely available ONLY to ships at
            # that market. No fabricated omniscient price_knowledge in AI.
            var observations: Dictionary = {}
            # Original N153 only reads its passed memory; pass the real
            # N80 knowledge without deep-copying every known market.
            # At the source override ONLY a shallow top-level copy, so
            # the native ship memory (including its nested rows) is safe.
            if ship.get("price_knowledge") is Dictionary:
                observations = ship["price_knowledge"]
            if here == source:
                observations = observations.duplicate()
                observations[source] = {good: {"price": float(source_price)}}
            var systems: Dictionary = {}
            systems[here] = EligibilityIndex.system_for(system_cache, here, resolver)
            # Resolve each offer endpoint once, but only after the first
            # ready bidder, preserving the old lazy resolver call boundary.
            if fixed_systems.is_empty():
                fixed_systems[source] = EligibilityIndex.system_for(system_cache, source, resolver)
                fixed_systems[dest] = EligibilityIndex.system_for(system_cache, dest, resolver)
            systems[source] = fixed_systems[source]
            systems[dest] = fixed_systems[dest]
            if str(systems[here]).is_empty() or str(systems[source]).is_empty() or str(systems[dest]).is_empty():
                _blocked_ship(ship_blockers, "missing_system_for_market")
                continue
            # Per-ship sensor and comms fields cannot change inside propose().
            # Compute lazily after route/system gates, preserving reject order.
            var observation: Dictionary = _bid_observation(observation_cache, str(ship_id), ship)
            var sensor: float = float(observation["sensor"])
            # The selector does not mutate the offer or controller DTO.
            # Reuse them only within this contract, after a real ready ship.
            if fixed_offer.is_empty():
                fixed_offer = {
                    "id": str(contract_id), "status": "Posted", "contract_type": "Delivery",
                    "faction_id": buyer_faction, "requestor_id": str(c.get("requestor_id", "")),
                    "source_location": source, "destination_location": dest,
                    "commodity": good, "quantity": qty, "may_accept": true}
                fixed_controllers[source] = seller_faction
                fixed_controllers[dest] = buyer_faction
            var bonus: float = float(observation["bonus"])
            if not is_finite(bonus) or bonus < 0.0 or bonus > 0.10:
                _blocked_ship(ship_blockers, "invalid_native_comms_bonus")
                continue
            var boosted: float = round(float(c["payment"]) * (1.0 + bonus))
            if not is_finite(boosted) or boosted > 9007199254740991.0:
                _blocked_ship(ship_blockers, "invalid_native_payment_quote")
                continue
            var quoted_payment: int = int(boosted)
            var top_up: int = maxi(0, quoted_payment - reserved_amount)
            var quotes: Dictionary = {}
            quotes[str(contract_id)] = {"valid": payer_balance >= top_up and payer_balance >= 0,
                "quoted_payment": quoted_payment, "top_up": top_up,
                "payer_balance": payer_balance,
                "reserved": reserved_amount, "source_purchase_cost": source_purchase}
            # Per-bid detached outer dictionary: never let a selector's
            # temporary context mutate the next bidder's commerce roster.
            var commerce: Dictionary = base_commerce.duplicate()
            commerce[ship_faction] = true
            var context: Dictionary = {
                "offers": [fixed_offer], "ship_id": str(ship_id),
                "ship_faction": ship_faction, "ship_location": here,
                "cargo_capacity": int(ship["cargo_capacity"]), "credits": int(ship.get("credits", 0)),
                "sensor_range_au": float(sensor), "system_by_location": systems,
                "controllers": fixed_controllers,
                "commerce_allowed": commerce,
                "quotes": quotes,
                "memory": {"price_knowledge": observations},
                "tick": tick}
            var choice: Dictionary = N153.select_contract(context)
            if str(choice.get("id", "")) == str(contract_id):
                # Source winner tie-break is strictly profit > (not >=).
                # N81 cannot change the profit selected by N153; building
                # a full GOAP/BT for a weaker/equal bid cannot replace the
                # existing winner. In this branch a winner is already
                # nonempty, so ship_blockers is never published; when no
                # winner exists every N81 rejection is still counted.
                # N153 and all real gates above still execute unchanged.
                if not winner.is_empty() and int(choice["profit"]) <= int(winner["profit"]):
                    continue
                var origin_owner: bool = ship_faction == seller_faction
                var candidate_plan: Dictionary = NativePipeline.propose(ship, {
                    "contract_id": str(contract_id),
                    "source": source, "destination": dest,
                    "commodity": good, "quantity": qty,
                    "profit": int(choice["profit"]),
                    "ownership_priority": 1.25 if origin_owner else 1.0
                }, graph)
                if not candidate_plan.get("ok", false):
                    _blocked_ship(ship_blockers, "n81_" + str(
                        candidate_plan.get("reason", "plan_rejected")))
                    continue
                var row: Dictionary = {"contract_id": str(contract_id), "ship_id": str(ship_id),
                    "profit": int(choice["profit"]), "source": source,
                    "destination": dest, "path_to_source": (readiness["path_to_source"] as Array).duplicate(),
                    "path_to_destination": (readiness["source_to_destination"] as Array).duplicate(),
                    "source_purchase_cost": source_purchase,
                    "ai_bt": candidate_plan["ai_bt"],
                    "n80_score": candidate_plan["n80_score"],
                    "n81_cost": candidate_plan["n81_cost"],
                    "personality_source": candidate_plan["personality_source"]}
                if winner.is_empty() or int(row["profit"]) > int(winner["profit"]):
                    winner = row
            else:
                _blocked_ship(ship_blockers, "rust_n153_selector_declined")
        if winner.is_empty():
            blocked.append({"contract_id": str(contract_id),
                "reason": "n153_no_eligible_profitable_known_ship",
                "ship_rejection_counts": ship_blockers})
            continue
        candidates.append(winner)
        already_assigned[str(winner["ship_id"])] = true
    return {"ok": true, "tick": tick, "candidates": candidates,
        "blocked": blocked, "status": "N153_SOURCE_SELECTED_NOT_APPLIED"}
