extends RefCounted
## Compact source-backed right-panel cards. Reads the same completed
## economy frame as the existing inspector. Never mutates N39/AI/ledger.
const QuickData = preload("res://scripts/view/colony_quick_projection.gd")
const Names = preload("res://scripts/view/facility_labels_ru.gd")

static func _card(label: String, value: String, note: String = "") -> Dictionary:
    return {"label": label, "value": value, "note": note}

static func _value(source: Dictionary, key: String,
        suffix: String = "") -> String:
    if not source.has(key):
        return "—"
    return str(source[key]) + suffix

static func build(world: Dictionary, body_id: String,
        facility_id: String, ship_id: String, economy: Dictionary) -> Dictionary:
    if not ship_id.is_empty():
        var fleet: Variant = economy.get("ships", {})
        if fleet is Dictionary and fleet.get(ship_id) is Dictionary:
            var ship: Dictionary = fleet[ship_id]
            var transit: Variant = ship.get("transit", {})
            var flying: bool = transit is Dictionary and not transit.is_empty()
            var goods: Variant = ship.get("cargo", {})
            var cargo: float = 0.0
            if goods is Dictionary:
                for quantity in goods.values():
                    cargo += float(quantity)
            return {"title": str(ship.get("name", ship_id)),
                "subtitle": "Корабль · " + str(ship.get("class", "тип неизвестен")),
                "cards": [_card("Рейс", "В полёте" if flying else "В локации"),
                    _card("Топливо", _value(ship, "fuel")),
                    _card("Груз", "%.0f" % cargo),
                    _card("Кредиты", _value(ship, "credits"))],
                "lines": ["Локация: " + str(ship.get("location", "—")),
                    "Фракция: " + str(ship.get("faction_id", "—"))]}
        return {"title": "Корабль", "subtitle": "Нет живого снимка",
            "cards": [], "lines": []}
    if not facility_id.is_empty():
        var source: Dictionary = {}
        for item in world.get("facilities", []):
            if item is Dictionary and str(item.get("id", "")) == facility_id:
                source = item
                break
        if source.is_empty():
            var candidate: Variant = economy.get(
                "facilities", {}).get(facility_id, {})
            if candidate is Dictionary:
                var bid: String = str(candidate.get("body_id",
                    candidate.get("body", "")))
                for body in world.get("bodies", []):
                    if body is Dictionary and str(body.get("id", "")) == bid:
                        source = candidate.duplicate(false)
                        source["id"] = facility_id
                        source["body"] = bid
                        source["faction_id"] = str(candidate.get(
                            "faction_id", candidate.get("faction", "")))
                        break
        if not source.is_empty():
            var live: Variant = economy.get("facilities", {}).get(facility_id, {})
            if not (live is Dictionary):
                live = {}
            var live_row: Dictionary = live
            var shift: Variant = live_row.get("work_shift", {})
            if not (shift is Dictionary):
                shift = {}
            var wages: String = ("%d CR" % int(shift["wages"])
                if shift.has("wages") else "—")
            var condition: String = ("%.0f%%" % (
                float(live_row["condition"]) * 100.0)
                if live_row.has("condition") else "—")
            if bool(live_row.get("abandoned", false)):
                condition = "Заброшено"
            var lines: Array[String] = [
                "Фракция: " + str(source.get("faction_id", "—")),
                "Место: " + str(source.get("location", "—"))]
            if shift.has("tick"):
                lines.append("Последняя оплаченная смена: тик %d" % int(
                    shift["tick"]))
            else:
                lines.append("Оплаченная смена: нет данных")
            if str(source.get("type", "")) in ["station", "shipyard"]:
                lines.append("Стыковочных мест: %d" % int(
                    source.get("docking_capacity", 0)))
            var stock: Variant = live_row.get("module_stock", {})
            if stock is Dictionary:
                var supplies: Variant = stock.get("stock", {})
                if supplies is Dictionary:
                    var keys: Array = supplies.keys()
                    keys.sort()
                    var shown: int = 0
                    for resource in keys:
                        if float(supplies[resource]) <= 0.0:
                            continue
                        lines.append("%s: %s ед." % [str(resource),
                            str(supplies[resource])])
                        shown += 1
                        if shown >= 3:
                            break
            var facility_type: String = str(source.get("type", ""))
            var colony_dock: bool = (
                str(source.get("location", "")) ==
                str(source.get("body", "")) + "-colony")
            var subtitle: String = Names.type_name(facility_type)
            if colony_dock:
                subtitle = ("Строительный док колонии"
                    if facility_type == "construction_dock"
                    else "Административный центр" if (
                    facility_type == "station") else subtitle)
            return {"title": Names.display_name(source),
                "subtitle": subtitle,
                "cards": [
                    _card("Состояние", condition),
                    _card("Рабочие", _value(live_row, "assigned_workers")),
                    _card("Смена: оплата", wages),
                    _card("Средства", _value(live_row, "credits", " CR"))],
                "lines": lines}
    var colony: Dictionary = QuickData.project(world, body_id, economy)
    if not bool(colony.get("visible", false)):
        return {"title": str(world.get("system", {}).get("name", "Система")),
            "subtitle": "Выберите планету или предприятие",
            "cards": [], "lines": ["Информация появится после выбора."]}
    var food: Variant = colony.get("food", null)
    var energy: Variant = colony.get("energy", null)
    var construction: Variant = colony.get("construction", null)
    var signals: Variant = colony.get("alerts", null)
    return {"title": str(colony.get("name", "Колония")),
        "subtitle": str(colony.get(
            "stage", "Обзор существующего поселения")),
        "cards": [
            _card("Жители", _value(colony, "population")
                if colony.get("population") != null else "—"),
            _card("Еда", "%.0f ед." % float(food) if food != null else "—",
                "Запас на рынке, не дни"),
            _card("Энергия", "%.0f ед." % float(energy)
                if energy != null else "—",
                "Energy Cells на рынке"),
            _card("Стройки", str(construction)
                if construction != null else "—")],
        "lines": [
            "Сигналы износа/заброшенности: " + (
                str(signals) if signals != null else "—"),
            "Полная экономика и причины дефицитов — в разделе «Данные»."]}
