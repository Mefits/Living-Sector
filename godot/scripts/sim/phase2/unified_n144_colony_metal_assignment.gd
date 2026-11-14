extends RefCounted
## Frozen Rust N153::select_contract(Construction), N80/N81/N84 source
## selection against the one N39 World. No ship, credits, goods or
## contract mutate until the single authoritative N39 Accept Apply.
const SourceSelection = preload("res://scripts/sim/phase1/n153_native_ship_contract_selection.gd")
const SourceDispatch = preload("res://scripts/sim/phase2/unified_n153_contract_dispatch.gd")
const Planning = preload("res://scripts/sim/phase2/unified_ship_ai_planner.gd")
const SourceMarketRules = preload("res://scripts/port/n97_ship_market_rules.gd")
const Materials = preload("res://scripts/sim/phase2/unified_n144_colony_metals.gd")

static func propose(world: Dictionary, graph: RefCounted,
        positions: Dictionary, resolver: RefCounted,
        tick: int, scale: float) -> Dictionary:
    if tick < 1 or graph == null or resolver == null or scale <= 0.0:
        return {"ok": false, "reason": "b2_real_n153_selector_unavailable"}
    var ids: Array = world.get("contract_board", {}).get("contracts", {}).keys()
    ids.sort()
    var ships: Array = world.get("ships", {}).keys()
    ships.sort()
    for cid in ids:
        var c: Dictionary = world["contract_board"]["contracts"][cid]
        if str(c.get("contract_type", "")) != "construction" or (
                str(c.get("mission_category", "")) != Materials.PROJECT_TAG or
                str(c.get("status", "")) != "posted" or
                tick > int(c.get("expires_at_tick", -1))):
            continue
        var site_id: String = str(c.get("colony_site_id", ""))
        var quote: Dictionary = Materials.source_quote(world, site_id)
        if not quote.get("ok", false):
            continue
        var source: String = str(c["source_location"])
        var dest: String = str(c["destination_location"])
        var faction: String = str(c.get("faction_id", ""))
        var qty: int = int(c.get("quantity", 0))
        if source != str(quote["source"]) or dest != str(quote["destination"]) or (
                qty != int(quote["quantity"]) or int(c.get("payment", 0)) != Materials.PAYMENT):
            continue
        var price: float = float(world["markets"][source]["prices"]["metals"])
        var winner: Dictionary = {}
        for sid in ships:
            var ship: Dictionary = world["ships"][sid]
            var here: String = str(ship.get("location", ""))
            if str(ship.get("faction_id", "")) != faction or (
                    not str(ship.get("active_contract_id", "")).is_empty() or
                    str(ship.get("current_goal", "")) not in ["", "idle"] or
                    not (ship.get("cargo", {}) as Dictionary).is_empty()):
                continue
            var path: Dictionary = SourceDispatch._ready_ship(
                world, str(sid), c, graph, positions, resolver, scale)
            if not path.get("ok", false):
                continue
            var current_price: Dictionary = {}
            if ship.get("price_knowledge") is Dictionary:
                current_price = ship["price_knowledge"].duplicate(true)
            if here == source:
                current_price[source] = {"metals": {"price": price}}
            var knowledge: Variant = SourceSelection.quote_source_price(
                {"price_knowledge": current_price}, source, "metals")
            if knowledge == null:
                continue
            var posture: Dictionary = SourceMarketRules.posture({}, faction,
                faction, int(ship.get("faction_reputation", {}).get(faction, 0)))
            if not posture.get("ok", false):
                continue
            var source_cost: int = int(ceil(float(qty) * price * float(posture["multiplier"])))
            if source_cost <= 0 or source_cost >= Materials.PAYMENT or (
                    source_cost > int(ship.get("credits", 0))):
                continue
            var bonus: float = float(ship.get("comms_bonus", 0.0))
            if not is_finite(bonus) or bonus < 0.0 or bonus > 0.10:
                continue
            var extra: int = int(round(float(Materials.PAYMENT) * (1.0 + bonus))) - int(c.get("reserved", 0))
            var treasury: int = int(world.get("faction_treasuries", {}).get(faction, -1))
            if extra > treasury or treasury < 0:
                continue
            var systems: Dictionary = {}
            systems[here] = resolver.system_for_location(here)
            systems[source] = resolver.system_for_location(source)
            systems[dest] = resolver.system_for_location(dest)
            if systems.values().has(""):
                continue
            var sensor: float = float(ship.get("sensor_range_au", 1.0))
            if not is_finite(sensor) or sensor < 0.0:
                continue
            var commerce: Dictionary = {}
            commerce[faction] = true
            var owners: Dictionary = {}
            owners[source] = faction
            owners[dest] = faction
            var quotes: Dictionary = {}
            quotes[str(cid)] = {"valid": true, "top_up": maxi(0, extra),
                "quoted_payment": int(c.get("payment", 0)) + maxi(0, extra),
                "payer_balance": treasury, "source_purchase_cost": source_cost,
                "fixed_strategy_reward": Materials.PAYMENT,
                "reserved": int(c.get("reserved", 0))}
            var selected: Dictionary = SourceSelection.select_contract({
                "offers": [{"id": str(cid), "status": "Posted",
                    "contract_type": "Construction", "faction_id": faction,
                    "requestor_id": faction, "source_location": source,
                    "destination_location": dest, "commodity": "metals",
                    "quantity": qty, "may_accept": true}],
                "ship_id": str(sid), "ship_faction": faction,
                "ship_location": here, "cargo_capacity": int(ship.get("cargo_capacity", 0)),
                "credits": int(ship.get("credits", 0)),
                "sensor_range_au": sensor, "system_by_location": systems,
                "commerce_allowed": commerce, "controllers": owners,
                "quotes": quotes,
                "memory": {"price_knowledge": current_price}, "tick": tick})
            if str(selected.get("id", "")) != str(cid):
                continue
            # Frozen N81 maps Construction to cargo-delivery GOAP leaves,
            # but the destination Sell/DeliverCargo will commit to N154
            # site rather than to a phantom warehouse.
            var native_bt: Dictionary = Planning.propose(ship, {
                "contract_id": str(cid), "source": source,
                "destination": dest, "commodity": "metals", "quantity": qty,
                "profit": int(selected.get("profit", 0)),
                "ownership_priority": 1.25}, graph)
            if not native_bt.get("ok", false):
                continue
            var candidate: Dictionary = {
                "contract_id": str(cid), "site_id": site_id,
                "ship_id": str(sid), "source_purchase_cost": source_cost,
                "ai_bt": native_bt["ai_bt"],
                "n80_score": native_bt["n80_score"],
                "personality_source": native_bt["personality_source"],
                "profit": int(selected.get("profit", 0)),
                "path_to_source": path["path_to_source"],
                "path_to_destination": path["source_to_destination"]}
            if winner.is_empty() or int(candidate["profit"]) > int(winner["profit"]):
                winner = candidate
        if not winner.is_empty():
            return {"ok": true, "assigned": true, "candidate": winner,
                "contract_id": str(cid), "ship_id": str(winner["ship_id"]),
                "ai_bt": winner["ai_bt"], "status": "B2_N153_REAL_CONSTRUCTION_HULL_SELECTED"}
    return {"ok": true, "assigned": false, "status": "B2_NO_FUNDABLE_REAL_METAL_SHIP"}
