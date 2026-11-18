extends RefCounted
## One bounded, read-only projection from the already-present completed
## N39 snapshot and static source world. No second simulation or snapshot.
const BODY_NAMES_RU: Dictionary = {
    "Earth": "Земля", "Mars": "Марс", "Luna": "Луна",
    "Venus": "Венера", "Mercury": "Меркурий",
    "Jupiter": "Юпитер", "Saturn": "Сатурн",
    "Callisto": "Каллисто"
}

static func project(world: Dictionary, requested_body: String,
        economy: Dictionary) -> Dictionary:
    var facilities: Array = world.get("facilities", [])
    var body: String = requested_body
    var locations: Dictionary = {}
    var source_ids: Dictionary = {}
    # When opening a system without a selected planet, prefer the first
    # ACTUAL settlement from the source, never a fictional colony.
    if body.is_empty():
        for row in facilities:
            if row is Dictionary and str(row.get("body", "")) != "":
                body = str(row["body"])
                break
    var active: Variant = economy.get("facilities", {})
    if body.is_empty() and active is Dictionary:
        var known: Dictionary = {}
        for item in world.get("bodies", []):
            if item is Dictionary:
                known[str(item.get("id", ""))] = true
        for fid in active:
            var candidate: Variant = active[fid]
            if not (candidate is Dictionary):
                continue
            var bid: String = str(candidate.get(
                "body_id", candidate.get("body", "")))
            if known.has(bid):
                body = bid
                break
    for row in facilities:
        if not (row is Dictionary) or str(row.get("body", "")) != body:
            continue
        locations[str(row.get("location", ""))] = true
        source_ids[str(row.get("id", ""))] = true
    # The real N39 colony is not in the frozen Rust seed.
    if active is Dictionary:
        for fid in active:
            var row: Variant = active[fid]
            if not (row is Dictionary) or str(row.get(
                    "body_id", row.get("body", ""))) != body:
                continue
            var kind: String = str(row.get("type", ""))
            if kind not in ["station", "shipyard", "construction_dock",
                    "mining_rig", "refinery", "farm", "factory",
                    "laboratory", "research", "power_plant"]:
                continue
            source_ids[str(fid)] = true
            locations[str(row.get("location", ""))] = true
    if locations.is_empty():
        return {"visible": false}
    var under_construction: bool = false
    var colony_established: bool = false
    if active is Dictionary:
        for fid in active:
            var row: Variant = active[fid]
            if not (row is Dictionary) or str(row.get(
                    "body_id", row.get("body", ""))) != body:
                continue
            if str(row.get("location", "")) != body + "-colony":
                continue
            if str(row.get("type", "")) == "construction_dock":
                under_construction = true
            elif str(row.get("type", "")) == "station":
                colony_established = true
    var name: String = body
    for value in world.get("bodies", []):
        if value is Dictionary and str(value.get("id", "")) == body:
            name = str(value.get("name", body))
            break
    name = str(BODY_NAMES_RU.get(name, name))
    var live: bool = economy.get("markets") is Dictionary and (
        economy.get("populations") is Dictionary) and (
        economy.get("facilities") is Dictionary)
    var result: Dictionary = {
        "visible": true, "body": body, "name": name, "live": live,
        "stage": ("Подготовка колонии" if (
            under_construction and not colony_established)
            else "Обзор существующего поселения"),
        "population": null, "food": null, "energy": null,
        "construction": null, "alerts": null,
        "details": {"colony": ["Колония: " + name,
            "Объектов на теле: %d" % source_ids.size()]}
    }
    if not live:
        for key in ["population", "food", "energy", "construction", "alerts"]:
            result["details"][key] = ["Живая экономика ещё не загружена"]
        return result
    var count: int = 0
    var pop_groups: int = 0
    var food: float = 0.0
    var has_food: bool = false
    var energy: float = 0.0
    var has_energy: bool = false
    for value in (economy["populations"] as Dictionary).values():
        if not (value is Dictionary) or not locations.has(
                str(value.get("location", ""))):
            continue
        pop_groups += 1
        count += maxi(0, int(value.get("count", 0)))
    for loc in locations:
        var market: Variant = (economy["markets"] as Dictionary).get(loc, null)
        if not (market is Dictionary):
            continue
        var supply: Variant = market.get("supply", {})
        if not (supply is Dictionary):
            continue
        if supply.has("food"):
            food += float(supply["food"])
            has_food = true
        if supply.has("energy_cells"):
            energy += float(supply["energy_cells"])
            has_energy = true
    result["population"] = count
    result["food"] = food if has_food else null
    result["energy"] = energy if has_energy else null
    var construction: int = 0
    var sites: Variant = economy.get("construction_sites", null)
    if sites is Dictionary:
        for value in sites.values():
            if value is Dictionary and not bool(value.get("completed", false)):
                var location: String = str(value.get("location_name",
                    value.get("location", "")))
                if locations.has(location):
                    construction += 1
        result["construction"] = construction
    var damaged: int = 0
    var abandoned: int = 0
    for id in source_ids:
        var f: Variant = (economy["facilities"] as Dictionary).get(id, null)
        if not (f is Dictionary):
            continue
        if bool(f.get("abandoned", false)):
            abandoned += 1
        elif f.has("condition") and float(f["condition"]) < 0.8:
            damaged += 1
    result["alerts"] = damaged + abandoned
    result["details"]["population"] = [
        "Население: %d" % count, "Групп населения: %d" % pop_groups]
    result["details"]["food"] = ([
        "Доступно на рынках: %.0f ед." % food,
        "Это текущий запас, НЕ прогноз в днях."
    ] if has_food else ["Запас еды в рынках не представлен"])
    result["details"]["energy"] = ([
        "Energy Cells на рынках: %.0f ед." % energy,
        "Это запас, НЕ баланс производства/потребления."
    ] if has_energy else [
        "Энергобаланс пока недоступен в этом снимке N39.",
        "Нельзя считать топливо автоматически энергией."
    ])
    result["details"]["construction"] = ([
        "Реальных незавершённых площадок: %d" % construction,
        "Не включает намерения ИИ без стройплощадки."
    ] if sites is Dictionary else ["Данные о стройплощадках недоступны"])
    result["details"]["alerts"] = [
        "Изношенных предприятий: %d" % damaged,
        "Заброшенных предприятий: %d" % abandoned,
        "Здесь пока нет общего анализа всех дефицитов."
    ]
    return result
