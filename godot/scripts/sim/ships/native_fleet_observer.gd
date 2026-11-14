extends RefCounted
## N67 read-only Observer snapshots from N66/N64 authoritative runtime.
## Missing crew economics/trading/AI are explicit "—", NEVER invented.
## Data-only; no Godot Nodes, polling timers or writes to world state.
const UNAVAILABLE = "—"

static func snapshot(runtime: RefCounted) -> Dictionary:
    if runtime == null or not runtime._active or runtime.engine == null:
        return _fail("runtime_unavailable")
    var live: RefCounted = runtime.engine
    if not live.is_live() or live.runner == null or live.ledger == null or live.docking == null:
        return _fail("world_not_live")
    if not (live.runner._fleet.ships is Dictionary) or not (live.docking.ships is Dictionary):
        return _fail("missing_authoritative_ships")
    var ledger_snapshot: Dictionary = live.ledger.snapshot()
    if not (ledger_snapshot.get("balances", null) is Dictionary):
        return _fail("missing_ledger_balances")
    var balances: Dictionary = ledger_snapshot["balances"]
    var ids: Array = live.runner._fleet.ships.keys()
    ids.sort()
    if ids.size() != live.docking.ships.size():
        return _fail("fleet_docking_count_mismatch")
    var initial_crew: Dictionary = {}
    for value in live.opening_crew_snapshot():
        if not (value is Dictionary):
            return _fail("invalid_initial_crew")
        initial_crew[str(value.get("ship_id", ""))] = value
    var rows: Array = []
    var flying: int = 0
    var docked: int = 0
    var at_location: int = 0
    for key in ids:
        var id: String = str(key)
        if not live.docking.ships.has(id):
            return _fail("missing_dock_entry_" + id)
        var ship: Dictionary = live.runner._fleet.ships[id]
        var dock: Dictionary = live.docking.ships[id]
        var transit_value: Variant = ship.get("transit", null)
        var cargo_value: Variant = ship.get("cargo", null)
        if not (transit_value is Dictionary) or not (cargo_value is Dictionary):
            return _fail("invalid_ship_state_" + id)
        var transit: Dictionary = transit_value
        var in_flight: bool = not transit.is_empty()
        var dock_in_flight: bool = bool(dock.get("in_transit", false))
        if in_flight != dock_in_flight:
            return _fail("flight_docking_desync_" + id)
        var location: String = str(ship.get("location", ""))
        var dock_location: String = str(dock.get("location", ""))
        var docked_id: String = str(dock.get("docked_at", ""))
        if in_flight:
            if not location.is_empty() or not dock_location.is_empty() or not docked_id.is_empty():
                return _fail("invalid_in_flight_location_" + id)
        elif location.is_empty() or location != dock_location:
            return _fail("invalid_idle_location_" + id)
        var fuel: Variant = ship.get("fuel", null)
        var fuel_cap: Variant = ship.get("fuel_capacity", null)
        if not (fuel is int or fuel is float) or not (fuel_cap is int or fuel_cap is float):
            return _fail("invalid_fuel_data_" + id)
        if not is_finite(float(fuel)) or not is_finite(float(fuel_cap)) or float(fuel_cap) <= 0.0:
            return _fail("invalid_fuel_range_" + id)
        if float(fuel) < 0.0 or float(fuel) > float(fuel_cap):
            return _fail("invalid_fuel_range_" + id)
        var wallet: String = "ship:" + id
        if not balances.has(wallet):
            return _fail("missing_ship_credit_account_" + id)
        var money: int = live.ledger.balance(wallet)
        if money < 0:
            return _fail("missing_ship_credit_account_" + id)
        var route_intent: Dictionary = runtime.intents.entry_for(id)
        var status: String = "at_location"
        var reasons: Array[String] = []
        if in_flight:
            flying += 1
            status = "in_transit"
            reasons.append("in_transit_until_actual_arrival")
        elif not docked_id.is_empty():
            docked += 1
            status = "docked"
            reasons.append("undock_required_before_departure")
        else:
            at_location += 1
        if route_intent.is_empty() and not in_flight:
            reasons.append("no_assigned_route_intent")
        if is_zero_approx(float(fuel)):
            # Frozen Rust still advances transit at zero fuel (N65);
            # do NOT call it a blocked/stranded ship.
            reasons.append("empty_tank_not_a_rust_transit_hard_stop")
        var target: String = ""
        var from_location: String = ""
        if in_flight:
            target = str(transit.get("to", ""))
            from_location = str(transit.get("from", ""))
        var next_waypoint: String = ""
        if not route_intent.is_empty():
            var idx: int = int(route_intent.get("index", -1))
            var places: Variant = route_intent.get("locations", null)
            if not (places is Array):
                return _fail("invalid_intent_" + id)
            if idx < 0 or idx >= places.size():
                return _fail("invalid_intent_index_" + id)
            if idx + 1 < places.size():
                next_waypoint = str(places[idx + 1])
        var cargo: Dictionary = (cargo_value as Dictionary).duplicate(true)
        if not live.runner._fleet.can_hold(id, cargo):
            return _fail("cargo_capacity_inconsistent_" + id)
        var row: Dictionary = {
            "ship_id": id, "class": str(ship.get("class", "")),
            "faction_id": str(ship.get("faction_id", "")),
            "system_id": str(ship.get("system_id", "")),
            "status": status, "location": location if not in_flight else UNAVAILABLE,
            "from": from_location if in_flight else UNAVAILABLE,
            "destination": target if in_flight else UNAVAILABLE,
            "docked_at": docked_id if not docked_id.is_empty() else UNAVAILABLE,
            "fuel": float(fuel), "fuel_capacity": float(fuel_cap),
            "fuel_fraction": float(fuel) / float(fuel_cap),
            "cargo": cargo, "cargo_used": live.runner._fleet.cargo_used(id),
            "cargo_capacity": int(ship.get("cargo_capacity", -1)),
            "credits": money,
            "crew_size": int(ship.get("crew_size", -1)),
            "crew_current_efficiency": UNAVAILABLE,
            "crew_current_morale": UNAVAILABLE,
            "crew_wages_paid": UNAVAILABLE,
            "cargo_trade_profit": UNAVAILABLE,
            "route_intent": str(route_intent.get("status", "")) if not route_intent.is_empty() else UNAVAILABLE,
            "next_waypoint": next_waypoint if not next_waypoint.is_empty() else UNAVAILABLE,
            "blocked_reasons": reasons,
            "arrival_tick_estimate": int(transit.get("arrival_tick", -1)) if in_flight else UNAVAILABLE
        }
        if not initial_crew.has(id):
            return _fail("missing_initial_crew_" + id)
        row["crew_initial_roles"] = (initial_crew[id]["roles"] as Array).duplicate(true)
        rows.append(row)
    return {"ok": true, "tick": live.runner.tick_count,
        "ship_count": rows.size(), "in_transit": flying,
        "docked": docked, "at_location": at_location, "ships": rows,
        "production_stats": UNAVAILABLE, "live_ai_decisions": UNAVAILABLE}

static func _fail(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
