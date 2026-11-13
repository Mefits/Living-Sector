extends RefCounted
## N153 admission boundary for autonomous, FUNDED N104 delivery offers.
## Read-only: never starts a voyage, reserves cargo, changes money or accepts
## a contract. The single N39 Apply must revalidate a selected candidate.
static func eligible(world: Dictionary) -> Dictionary:
    if not (world.get("contract_board") is Dictionary) or not (world.get("ships") is Dictionary) or not (world.get("markets") is Dictionary) or not (world.get("facilities") is Dictionary):
        return {"ok": false, "reason": "missing_canonical_contract_fleet_or_markets"}
    var board: Dictionary = world["contract_board"]
    if not (board.get("contracts") is Dictionary) or not (world.get("escrow_balances") is Dictionary):
        return {"ok": false, "reason": "missing_funded_board_or_escrow"}
    var contracts: Dictionary = board["contracts"]
    var ships: Dictionary = world["ships"]
    var markets: Dictionary = world["markets"]
    var facilities: Dictionary = world["facilities"]
    var candidates: Array[Dictionary] = []
    var blocked: Array[Dictionary] = []
    var ids: Array = contracts.keys()
    ids.sort()
    var ship_ids: Array = ships.keys()
    ship_ids.sort()
    for cid in ids:
        if not (contracts[cid] is Dictionary):
            return {"ok": false, "reason": "invalid_contract_row"}
        var c: Dictionary = contracts[cid]
        if str(c.get("status", "")) != "posted" or str(c.get("contract_type", "")) != "delivery":
            continue
        var source: String = str(c.get("source_location", ""))
        var dest: String = str(c.get("destination_location", ""))
        var commodity: String = str(c.get("commodity", ""))
        var qty: int = int(c.get("quantity", 0))
        var escrow: String = str(c.get("escrow_account", ""))
        var reserved: int = int(c.get("reserved", -1))
        if source.is_empty() or dest.is_empty() or source == dest or commodity.is_empty() or qty <= 0 or reserved <= 0 or int(world["escrow_balances"].get(escrow, -1)) != reserved:
            blocked.append({"contract_id": str(cid), "reason": "invalid_or_unfunded_terms"})
            continue
        if not markets.has(source) or not markets.has(dest):
            blocked.append({"contract_id": str(cid), "reason": "market_location_missing"})
            continue
        var src: Dictionary = markets[source]
        if not (src.get("supply") is Dictionary) or float(src["supply"].get(commodity, 0.0)) < float(qty):
            blocked.append({"contract_id": str(cid), "reason": "physical_source_stock_missing"})
            continue
        var owner: String = str(src.get("owner", ""))
        if not facilities.has(owner) or str(facilities[owner].get("location", "")) != source:
            blocked.append({"contract_id": str(cid), "reason": "physical_source_owner_invalid"})
            continue
        var found: bool = false
        for sid in ship_ids:
            if not (ships[sid] is Dictionary):
                return {"ok": false, "reason": "invalid_ship_row"}
            var ship: Dictionary = ships[sid]
            if not (ship.get("transit") is Dictionary) or not (ship.get("cargo") is Dictionary):
                return {"ok": false, "reason": "invalid_ship_transit_or_hold"}
            if not ship["transit"].is_empty() or not str(ship.get("docked_at", "")).is_empty():
                continue
            if str(ship.get("location", "")) != source:
                continue
            var occupied: float = 0.0
            for item in ship["cargo"].values():
                if not (item is int or item is float) or float(item) < 0.0:
                    return {"ok": false, "reason": "invalid_physical_ship_cargo"}
                occupied += float(item)
            var capacity: float = float(ship.get("cargo_capacity", -1))
            if capacity < 0.0 or occupied + float(qty) > capacity:
                continue
            if float(ship.get("fuel", 0.0)) <= 0.0:
                continue
            found = true
            candidates.append({"contract_id": str(cid), "ship_id": str(sid),
                "source": source, "destination": dest, "commodity": commodity,
                "quantity": qty, "status": "ELIGIBLE_AT_SOURCE_ROUTE_UNVERIFIED"})
        if not found:
            blocked.append({"contract_id": str(cid), "reason": "no_idle_local_ship_with_capacity_and_fuel"})
    return {"ok": true, "candidates": candidates, "blocked": blocked,
        "status": "READ_ONLY_ELIGIBILITY_NO_ACCEPTANCE_OR_VOYAGE"}
