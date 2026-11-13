extends PanelContainer
## N20 observational UI: no command buttons until real executor is wired.
const ObserverProjection = preload("res://scripts/sim/observer/observer_projection.gd")
var _label: RichTextLabel

func _ready() -> void:
    custom_minimum_size = Vector2(380, 320)
    var column := VBoxContainer.new()
    add_child(column)
    var heading := Label.new()
    heading.text = "НАБЛЮДЕНИЕ / УПРАВЛЕНИЕ · N20"
    column.add_child(heading)
    _label = RichTextLabel.new()
    _label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _label.selection_enabled = true
    column.add_child(_label)
    show_observation(0, "unselected", {})

func show_observation(tick: int, faction_id: String, state: Dictionary) -> void:
    var text_value: String = ObserverProjection.describe(ObserverProjection.build(tick, faction_id, state))
    if _label:
        _label.text = text_value

## P2 live economy inspection: read ONLY the authoritative N39 snapshot.
## Do not present unconnected N20 planner decisions as active gameplay.
func show_live_economy(tick: int, economy: Dictionary, summary: Dictionary,
        ships: Dictionary = {}) -> void:
    if _label == null:
        return
    if not (economy.get("facilities") is Dictionary) or not (economy.get("markets") is Dictionary) or not (economy.get("populations") is Dictionary):
        _label.text = "Живая экономика недоступна: нет единого N39 World"
        return
    var lines: Array[String] = ["ЖИВАЯ ЭКОНОМИКА · ТИК %d" % tick]
    lines.append("Станции: %d · рынки: %d · группы населения: %d" % [
        economy["facilities"].size(), economy["markets"].size(), economy["populations"].size()])
    lines.append("Зарплаты за последний тик: %d · добывающих: %d · производственных: %d" % [
        int(summary.get("last_wages_paid", 0)), int(summary.get("last_mining_facilities", 0)),
        int(summary.get("last_recipe_facilities", 0))])
    lines.append("Покупок Food/Water: %d · рынок: %s" % [
        int(summary.get("population_purchases", 0)),
        "успешно" if summary.get("market_phase_ok", null) == true else "ещё не исполнялся / отказ"])
    lines.append("N156 оплаченных ремонтов: %d · N130 покупок Fuel/Tools: %d" % [
        int(summary.get("last_paid_repairs", 0)), int(summary.get("last_service_restock", 0))])
    lines.append("СТАНЦИИ / КРЕДИТЫ / СОСТОЯНИЕ:")
    var facilities: Dictionary = economy["facilities"]
    var facility_ids: Array = facilities.keys()
    facility_ids.sort()
    var abandoned_count: int = 0
    var worn_count: int = 0
    var repair_ready_count: int = 0
    for id in facility_ids:
        if not (facilities[id] is Dictionary):
            continue
        var f: Dictionary = facilities[id]
        var abandoned: bool = bool(f.get("abandoned", false))
        var condition: float = float(f.get("condition", 1.0))
        var morale: float = float(f.get("morale", 80.0))
        var abandon_counter: int = int(f.get("abandon_counter", 0))
        var owned: Variant = f.get("reserves", {})
        var tools: float = 0.0
        var fuel: float = 0.0
        if owned is Dictionary:
            tools = float(owned.get("tools", 0.0))
            fuel = float(owned.get("fuel", 0.0))
        if abandoned:
            abandoned_count += 1
        elif condition < 0.8:
            worn_count += 1
            if tools >= 1.0:
                repair_ready_count += 1
        lines.append("  %s · CR %s · экипаж %s · уровень %s · состояние %.2f · %s" % [
            str(id), str(f.get("credits", "?")), str(f.get("crew_count", "?")),
            str(f.get("level", "?")), condition,
            "ЗАБРОШЕНА" if abandoned else "работает"])
        # N156 morale and abandonment are authoritative facility fields;
        # these are not unconnected N20 planner projections.
        lines.append("    N156 мораль %.1f · счётчик заброшенности %d" % [
            morale, abandon_counter])
        # Services are real private station reserves, not market supply.
        lines.append("    свои запасы: Fuel %.1f · Tools %.1f" % [fuel, tools])
        if not abandoned and condition < 0.8:
            lines.append("    ремонт: %s" % (
                "есть собственные Tools; требуется оплаченная смена"
                if tools >= 1.0 else "ожидание закупки собственных Tools"))
    lines.append("N156: заброшено %d · изношено (<0.8) %d · с Tools для ремонта %d" % [
        abandoned_count, worn_count, repair_ready_count])
    lines.append("ОПЛАЧЕННЫЕ СМЕНЫ / ПРОИЗВОДСТВО:")
    var paid_shifts: int = 0
    for id in facility_ids:
        if not (facilities[id] is Dictionary):
            continue
        var facility: Dictionary = facilities[id]
        var shift: Variant = facility.get("work_shift", {})
        if not (shift is Dictionary) or shift.is_empty():
            continue
        var wages: int = int(shift.get("wages", 0))
        var shift_tick: int = int(shift.get("tick", -1))
        if shift_tick < 0:
            continue
        paid_shifts += 1
        var workers: Variant = shift.get("workers", {})
        var employed: int = 0
        if workers is Dictionary:
            for pid in workers:
                employed += int(workers[pid])
        lines.append("  %s · смена %d · зарплата %d CR · работников %d" % [
            str(id), shift_tick, wages, employed])
        var outputs: Variant = shift.get("produced_outputs", {})
        if outputs is Dictionary and not outputs.is_empty():
            var recipe_ids: Array = outputs.keys()
            recipe_ids.sort()
            for recipe_id in recipe_ids:
                if not (outputs[recipe_id] is Dictionary):
                    continue
                var goods: Array[String] = []
                var commodity_ids: Array = outputs[recipe_id].keys()
                commodity_ids.sort()
                for commodity in commodity_ids:
                    goods.append("%s=%s" % [str(commodity), str(outputs[recipe_id][commodity])])
                lines.append("    %s: %s" % [str(recipe_id), ", ".join(goods)])
    if paid_shifts == 0:
        lines.append("  Оплаченных смен пока нет")
    lines.append("РЫНКИ / ФИЗИЧЕСКИЕ ЗАПАСЫ:")
    var markets: Dictionary = economy["markets"]
    var market_ids: Array = markets.keys()
    market_ids.sort()
    for id in market_ids:
        if not (markets[id] is Dictionary):
            continue
        var m: Dictionary = markets[id]
        var stocks: Dictionary = m.get("supply", {}) if m.get("supply", {}) is Dictionary else {}
        var commodities: Array = stocks.keys()
        commodities.sort()
        var amounts: Array[String] = []
        for commodity in commodities:
            amounts.append("%s=%s" % [str(commodity), str(stocks[commodity])])
        lines.append("  %s: %s" % [str(id), ", ".join(amounts) if not amounts.is_empty() else "пусто"])
        var prices: Variant = m.get("prices", {})
        if prices is Dictionary:
            var price_items: Array[String] = []
            var price_ids: Array = prices.keys()
            price_ids.sort()
            for commodity in price_ids:
                price_items.append("%s=%s" % [str(commodity), str(prices[commodity])])
            lines.append("    цены: %s" % [", ".join(price_items) if not price_items.is_empty() else "нет"])
    lines.append("НАСЕЛЕНИЕ / БЛАГОСОСТОЯНИЕ:")
    var pops: Dictionary = economy["populations"]
    var pop_ids: Array = pops.keys()
    pop_ids.sort()
    for id in pop_ids:
        if not (pops[id] is Dictionary):
            continue
        var p: Dictionary = pops[id]
        lines.append("  %s · жителей %s · CR %s · Food %s · настроение %s" % [
            str(id), str(p.get("count", "?")), str(p.get("wealth", "?")),
            str(p.get("food_satisfaction", "?")), str(p.get("overall_sentiment", "?"))])
        lines.append("    безопасность %s · досуг %s · беспорядки %s · давление миграции %s" % [
            str(p.get("safety_satisfaction", "?")),
            str(p.get("entertainment_satisfaction", "?")),
            str(p.get("unrest", "?")), str(p.get("migration_pressure", "?"))])
    var repair_failures: Dictionary = summary.get("last_repair_failures", {}) if summary.get("last_repair_failures", {}) is Dictionary else {}
    if not repair_failures.is_empty():
        lines.append("ОТКАЗЫ ОПЛАТЫ РЕМОНТА:")
        var repair_ids: Array = repair_failures.keys()
        repair_ids.sort()
        for id in repair_ids:
            lines.append("  %s: %s" % [str(id), str(repair_failures[id])])
    var failures: Dictionary = summary.get("last_failures", {}) if summary.get("last_failures", {}) is Dictionary else {}
    if not failures.is_empty():
        lines.append("ОСТАНОВКИ ПРОИЗВОДСТВА:")
        var failure_ids: Array = failures.keys()
        failure_ids.sort()
        for id in failure_ids:
            lines.append("  %s: %s" % [str(id), str(failures[id])])
    if ships.is_empty():
        lines.append("Флот: старый checkpoint без N46; не создаём новые танки из seed.")
    else:
        lines.append("РЕАЛЬНЫЙ ФЛОТ / N46 + N14: %d судов" % ships.size())
        var types: Dictionary = {}
        var flight_count: int = 0
        var ship_ids: Array = ships.keys()
        ship_ids.sort()
        for sid in ship_ids:
            var ship: Dictionary = ships[sid]
            var kind: String = str(ship.get("class", "?"))
            types[kind] = int(types.get(kind, 0)) + 1
            var transit: Dictionary = ship.get("transit", {})
            if not transit.is_empty():
                flight_count += 1
                lines.append("  В РЕЙСЕ: %s · %s → %s · Fuel %.2f / %.2f" % [
                    str(ship.get("name", sid)),
                    str(transit.get("from", "?")), str(transit.get("to", "?")),
                    float(ship.get("fuel", 0.0)),
                    float(ship.get("fuel_capacity", 0.0))])
        var class_ids: Array = types.keys()
        class_ids.sort()
        var class_lines: Array[String] = []
        for kind in class_ids:
            class_lines.append("%s %d" % [str(kind), int(types[kind])])
        lines.append("Классы: " + ", ".join(class_lines))
        lines.append("В пути: %d · на месте: %d" % [flight_count, ships.size() - flight_count])
        lines.append("AI/доставка пока не подключены; маршруты N14 требуют реальной команды.")
    lines.append("Контракты и стратегические планировщики: ещё не подключены к единому тику.")
    _label.text = "\n".join(lines)
