extends RefCounted
## P2 Gate 2: N21 docking + N15 physical cargo using ONE canonical N39 world.
## No second ledger, warehouse, fleet clock or ContractBoard.
const Docking = preload("res://scripts/sim/ships/docking_registry.gd")
const CargoGate = preload("res://scripts/sim/ships/docked_cargo_gate.gd")
const ShipState = preload("res://scripts/sim/ship_state.gd")

static func _open(world: Dictionary) -> Dictionary:
    if not (world.get("ships") is Dictionary) or not (world.get("facilities") is Dictionary) or not (world.get("markets") is Dictionary):
        return {"ok": false, "reason": "missing_single_world"}
    var registry = Docking.new()
    var facility_ids: Array = world["facilities"].keys()
    facility_ids.sort()
    for fid in facility_ids:
        var f: Dictionary = world["facilities"][fid]
        if typeof(f.get("docking_capacity", null)) != TYPE_INT or int(f["docking_capacity"]) < 0:
            return {"ok": false, "reason": "source_docking_capacity_missing"}
        if not registry.register_facility(str(fid), str(f["location"]), int(f["docking_capacity"]), str(f["type"])):
            return {"ok": false, "reason": "dock_facility_registration_failed"}
    var rows: Array = []
    var ids: Array = world["ships"].keys()
    ids.sort()
    for sid in ids:
        var ship: Dictionary = world["ships"][sid]
        var transit: Dictionary = ship.get("transit", {})
        var location: String = str(ship.get("location", ""))
        if not registry.register_ship(str(sid), location, not transit.is_empty()):
            return {"ok": false, "reason": "dock_ship_registration_failed"}
        var dock: String = str(ship.get("docked_at", ""))
        if not dock.is_empty():
            if not registry.facilities.has(dock) or not transit.is_empty():
                return {"ok": false, "reason": "invalid_canonical_dock"}
            if str(registry.facilities[dock]["location"]) != location:
                return {"ok": false, "reason": "dock_location_mismatch"}
            registry.ships[sid]["docked_at"] = dock
            (registry.occupants[dock] as Array).append(str(sid))
        rows.append(ship.duplicate(true))
    for fid in registry.occupants:
        (registry.occupants[fid] as Array).sort()
    if not registry.restore(registry.snapshot()):
        return {"ok": false, "reason": "dock_occupancy_invalid"}
    var fleet = ShipState.new()
    if not fleet.restore(rows):
        return {"ok": false, "reason": "canonical_ship_state_invalid"}
    var gate = CargoGate.new()
    if not gate.configure(registry, fleet):
        return {"ok": false, "reason": "cargo_gate_unavailable"}
    for loc in world["markets"]:
        var market: Dictionary = world["markets"][loc]
        var owner: String = str(market.get("owner", ""))
        if not registry.facilities.has(owner) or str(registry.facilities[owner]["location"]) != str(loc):
            return {"ok": false, "reason": "market_warehouse_owner_mismatch"}
        if not gate.register_warehouse(owner, market["supply"]):
            return {"ok": false, "reason": "market_warehouse_registration_failed"}
    return {"ok": true, "registry": registry, "fleet": fleet, "gate": gate}

## One explicit command, backed by the existing N21/N15 domain objects.
## World is duplicated BEFORE the original domain methods mutate it.
static func command(source: Dictionary, action: String, ship_id: String,
        operation_id: String, tick: int, quantities: Dictionary = {}) -> Dictionary:
    if ship_id.is_empty() or operation_id.is_empty() or tick < 0:
        return {"ok": false, "reason": "invalid_command_identity"}
    if action not in ["dock", "undock", "load", "unload"]:
        return {"ok": false, "reason": "invalid_fleet_logistics_action"}
    if not (source.get("dock_receipts", null) is Dictionary) or not (source.get("cargo_receipts", null) is Dictionary):
        return {"ok": false, "reason": "legacy_save_without_logistics"}
    if source["dock_receipts"].has(operation_id) or source["cargo_receipts"].has(operation_id):
        return {"ok": false, "reason": "duplicate_operation_id"}
    var staged: Dictionary = source.duplicate(true)
    var prepared: Dictionary = _open(staged)
    if not prepared.get("ok", false):
        return prepared
    var registry: RefCounted = prepared["registry"]
    var result: Dictionary = {}
    var facility: String = ""
    if action == "dock":
        # Original N21 chooses the most free slots at the ship's real
        # location. Prefer the source station so N15 can use its Market.
        result = registry.request_dock(ship_id, operation_id, "station")
        if not result.get("ok", false):
            return result
        facility = str(result["facility_id"])
        staged["ships"][ship_id]["docked_at"] = facility
    elif action == "undock":
        result = registry.undock(ship_id, operation_id)
        if not result.get("ok", false):
            return result
        facility = str(result["facility_id"])
        staged["ships"][ship_id]["docked_at"] = ""
    else:
        if not staged["ships"].has(ship_id):
            return {"ok": false, "reason": "unknown_ship"}
        facility = str(staged["ships"][ship_id].get("docked_at", ""))
        if facility.is_empty():
            return {"ok": false, "reason": "ship_not_docked"}
        # No free inter-faction market theft before paid N104 contracts.
        # This manual N15 path is SAME-FACTION physical logistics only.
        if not staged["facilities"].has(facility) or str(staged["facilities"][facility]["faction"]) != str(staged["ships"][ship_id]["faction_id"]):
            return {"ok": false, "reason": "cargo_requires_same_faction"}
        result = prepared["gate"].transfer(ship_id, facility, quantities,
            operation_id, action, tick)
        if not result.get("ok", false):
            return result
        # CargoGate mutates only the isolated N15 ship and local market
        # warehouse. Copy the validated hold into the same staged World.
        staged["ships"][ship_id]["cargo"] = (prepared["fleet"].ships[ship_id]["cargo"] as Dictionary).duplicate(true)
        # N15 mutates its isolated warehouse as well as the isolated ship.
        # Both physical sides MUST enter the same N39 proposal; otherwise
        # N39 apply_fleet_logistics correctly rejects the missing stock delta.
        var warehouse_location: String = str(registry.facilities[facility]["location"])
        if not staged["markets"].has(warehouse_location):
            return {"ok": false, "reason": "cargo_market_location_missing"}
        var market: Dictionary = staged["markets"][warehouse_location]
        if str(market.get("owner", "")) != facility or not (prepared["gate"].warehouses.get(facility) is Dictionary):
            return {"ok": false, "reason": "cargo_warehouse_owner_mismatch"}
        market["supply"] = (prepared["gate"].warehouses[facility] as Dictionary).duplicate(true)
    var receipt: Dictionary = {
        "ok": true, "action": action, "ship_id": ship_id, "facility_id": facility,
        "operation_id": operation_id, "tick": tick
    }
    if action in ["load", "unload"]:
        receipt["quantities"] = quantities.duplicate(true)
        receipt["location_id"] = str(registry.facilities[facility]["location"])
        staged["cargo_receipts"][operation_id] = receipt.duplicate(true)
    else:
        staged["dock_receipts"][operation_id] = receipt.duplicate(true)
    return {"ok": true, "world": staged, "receipt": receipt}
