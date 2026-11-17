extends RefCounted
## Read-only N39 ship-to-celestial-body association. Physical landing is not
## inferred from a ship occupying an economic/nav location. The original
## N43 resolver registers exact facilities and nav_sites to source body IDs.
## No prefix guesses, synthetic trips or invented touchdown receipts.

static func _location_bodies(world: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for source in world.get("facilities", []):
        if not (source is Dictionary):
            continue
        var location: String = str(source.get("location", ""))
        var body: String = str(source.get("body", ""))
        if not location.is_empty() and not body.is_empty():
            result[location] = body
    for site in world.get("nav_sites", []):
        if not (site is Dictionary):
            continue
        var location: String = str(site.get("name", ""))
        var body: String = str(site.get("body", ""))
        if location.is_empty() or body.is_empty():
            continue
        # A conflicting seed mapping must not silently reassign a ship.
        if result.has(location) and str(result[location]) != body:
            result.erase(location)
            continue
        result[location] = body
    return result

static func _location_facilities(world: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for source in world.get("facilities", []):
        if source is Dictionary:
            var id: String = str(source.get("id", ""))
            if not id.is_empty():
                result[id] = source
    return result

static func goal_name(raw: String) -> String:
    match raw:
        "", "idle":
            return "Без задания"
        "mine_ice":
            return "Добыча льда"
        "deliver_mined_ice":
            return "Доставка добытого льда"
        "trade_route", "trade_run":
            return "Торговля"
        "construct":
            return "Строительство"
        "explore":
            return "Разведка"
        "colonize":
            return "Колонизация"
        "service":
            return "Обслуживание"
        _:
            return raw

static func ships_at_body(world: Dictionary, economy: Dictionary,
        body_id: String) -> Array[Dictionary]:
    var results: Array[Dictionary] = []
    if body_id.is_empty():
        return results
    var fleet: Variant = economy.get("ships", null)
    if not (fleet is Dictionary):
        return results
    var map: Dictionary = _location_bodies(world)
    var facilities: Dictionary = _location_facilities(world)
    var system: String = str(world.get("system", {}).get("id", ""))
    for id in fleet:
        var candidate: Variant = fleet[id]
        if not (candidate is Dictionary):
            continue
        var ship: Dictionary = candidate
        if str(ship.get("system_id", "")) != system:
            continue
        var transit: Variant = ship.get("transit", {})
        if not (transit is Dictionary) or not transit.is_empty():
            continue
        var location: String = str(ship.get("location", ""))
        if str(map.get(location, "")) != body_id:
            continue
        var docked: String = str(ship.get("docked_at", ""))
        var dock: Dictionary = facilities.get(docked, {})
        var status: String = "В локации тела · посадка не подтверждена"
        if not docked.is_empty():
            var kind: String = str(dock.get("type", ""))
            if kind == "station":
                status = "Пристыкован к станции"
            elif kind == "construction_dock":
                status = "Пристыкован к строительному доку"
            else:
                status = "Пристыкован: " + docked
        results.append({
            "id": str(id),
            "name": str(ship.get("name", id)),
            "class": str(ship.get("class", "—")),
            "location": location,
            "status": status,
            "docked_at": docked,
            "goal": goal_name(str(ship.get("current_goal", "idle"))),
            "contract_id": str(ship.get("active_contract_id", "")),
            "cargo": ship.get("cargo", {}),
            "ship": ship
        })
    results.sort_custom(func(a, b):
        return str(a["id"]) < str(b["id"]))
    return results
