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
    lines.append("АВТОНОМИЯ: производство / потребление / рынок — исполняются по тикам")
    lines.append("АВТОНОМИЯ N135/N104: оплаченные заявки публикуются в едином N39 World")
    lines.append("ФЛОТ: N153/N80/N81/N84 принимает задания; физическая доставка подтверждается только receipt N97/N104")
    lines.append("Игрок: режим наблюдения; индивидуальные команды скрыты до отдельного режима")
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
    # The Board and escrow are ONLY the N39 World fields; no UI model owns
    # a duplicate contract, order queue or wallet.
    var board: Dictionary = economy.get("contract_board", {})
    var contracts: Dictionary = board.get("contracts", {})
    var escrow_balances: Dictionary = economy.get("escrow_balances", {})
    var paid_orders: int = 0
    var reserved_credits: int = 0
    for order_id in contracts:
        var contract: Dictionary = contracts[order_id]
        if str(contract.get("status", "")) in ["posted", "accepted", "picked_up", "delivered"]:
            paid_orders += 1
        reserved_credits += int(escrow_balances.get(str(contract.get("escrow_account", "")), 0))
    lines.append("КОНТРАКТЫ N135/N104 · всего %d · активных %d · в escrow %d CR" % [
        contracts.size(), paid_orders, reserved_credits])
    lines.append("За этот тик оплачено: %d · отказов: %d" % [
        int(summary.get("funded_contracts_this_tick", 0)),
        int(summary.get("contract_admissions_blocked", 0))])
    lines.append("ИИ N153: принятых %d · отказов %d · отправлено N14 %d" % [
        int(summary.get("n153_accepted_this_tick", 0)),
        int(summary.get("n153_blocked_this_tick", 0)),
        int(summary.get("n153_departures_this_tick", 0))])
    if int(summary.get("n153_blocked_this_tick", 0)) > 0:
        lines.append("  Причина ожидания: " + str(summary.get("n153_first_blocker", "—")))
    var order_ids: Array = contracts.keys()
    order_ids.sort()
    for order_index in range(mini(3, order_ids.size())):
        var id: String = str(order_ids[order_index])
        var c: Dictionary = contracts[id]
        lines.append("  %s · %s %s · %s → %s · %s" % [
            str(c.get("status", "?")), str(c.get("quantity", 0)),
            str(c.get("commodity", "?")), str(c.get("source_location", "?")),
            str(c.get("destination_location", "?")),
            "ОЖИДАЕТ ИИ" if str(c.get("status", "")) == "posted" else "контракт в обработке"])
    if order_ids.size() > 3:
        lines.append("  … и ещё %d контрактов" % (order_ids.size() - 3))
    # Contract and agent trace is a read-only projection of the single
    # canonical World. Never infer delivery or payout from a planned route.
    lines.append("АВТОНОМНЫЕ ЗАКАЗЫ / ФИЗИЧЕСКОЕ ИСПОЛНЕНИЕ:")
    var lifecycle_counts: Dictionary = {}
    for cid in order_ids:
        if not (contracts[cid] is Dictionary):
            lines.append("  %s: повреждённая запись N104" % str(cid))
            continue
        var contract: Dictionary = contracts[cid]
        var stage: String = str(contract.get("status", "unknown"))
        lifecycle_counts[stage] = int(lifecycle_counts.get(stage, 0)) + 1
        var assigned_ship: String = str(contract.get("fulfiller_id", ""))
        var source: String = str(contract.get("source_location", "?"))
        var destination: String = str(contract.get("destination_location", "?"))
        var commodity: String = str(contract.get("commodity", "?"))
        var quantity: int = int(contract.get("quantity", 0))
        var account: String = str(contract.get("escrow_account", ""))
        var held_credits: int = int(escrow_balances.get(account, 0))
        if order_ids.size() <= 12 or stage in ["accepted", "picked_up", "delivered"]:
            lines.append("  N104 %s · %s · %d %s · %s → %s" % [
                str(cid), stage, quantity, commodity, source, destination])
            lines.append("    N135 потребность %s · N153 корабль %s · escrow %d CR" % [
                str(contract.get("demand_id", contract.get("need_id", "—"))),
                assigned_ship if not assigned_ship.is_empty() else "не назначен",
                held_credits])
            if not assigned_ship.is_empty():
                if not ships.has(assigned_ship) or not (ships[assigned_ship] is Dictionary):
                    lines.append("    ОТКАЗ: назначенный корабль отсутствует в N39 World")
                else:
                    var assigned: Dictionary = ships[assigned_ship]
                    var active: String = str(assigned.get("active_contract_id", ""))
                    var route: Dictionary = assigned.get("transit", {}) if assigned.get("transit", {}) is Dictionary else {}
                    var cargo: Dictionary = assigned.get("cargo", {}) if assigned.get("cargo", {}) is Dictionary else {}
                    var bt: Variant = assigned.get("current_bt", null)
                    var plan: String = "нет N84 плана"
                    if bt is Dictionary:
                        plan = "N84 план сохранён" if not bt.is_empty() else "пустой N84 план"
                    var physical: String = "рейс N14 %s → %s, ETA %s" % [
                        str(route.get("from", "?")), str(route.get("to", "?")),
                        str(route.get("arrival_tick", "?"))] if not route.is_empty() else "в системе " + str(assigned.get("location", "?"))
                    lines.append("    %s · %s · док %s" % [
                        plan, physical, str(assigned.get("docked_at", "—"))])
                    lines.append("    физический трюм: %s=%s · контракт корабля %s" % [
                        commodity, str(cargo.get(commodity, 0)),
                        active if not active.is_empty() else "не назначен"])
                    if active != str(cid) and stage in ["accepted", "picked_up"]:
                        lines.append("    ВНИМАНИЕ: назначение N104 и корабля расходится")
            if stage == "delivered":
                lines.append("    Доставка отмечена в ContractBoard; сверяйте физический receipt и выплату")
    var stages: Array = lifecycle_counts.keys()
    stages.sort()
    var stage_labels: Array[String] = []
    for stage in stages:
        stage_labels.append("%s=%d" % [str(stage), int(lifecycle_counts[stage])])
    lines.append("Стадии N104: " + (", ".join(stage_labels) if not stage_labels.is_empty() else "контрактов нет"))
    if summary.get("n84_trace", null) is Array:
        var trace: Array = summary["n84_trace"]
        lines.append("N84 решения текущего тика: %d" % trace.size())
        for entry in trace.slice(0, 8):
            if entry is Dictionary:
                lines.append("  %s · %s · %s · %s" % [
                    str(entry.get("ship_id", "?")), str(entry.get("contract_id", "?")),
                    str(entry.get("leaf", "?")), str(entry.get("reason", "—"))])
    # Native N143 research shares the exact N9 ledger and N39 source
    # market. Show paid work and true frozen faction treasury; never
    # present an unexecuted target as an unlocked technology.
    var treasuries: Dictionary = economy.get("faction_treasuries", {})
    var research_heads: Dictionary = economy.get("research_directors", {})
    if not treasuries.is_empty():
        lines.append("ИССЛЕДОВАНИЯ N143 / N82 · оплаченных смен %d · блокировок %d" % [
            int(summary.get("research_paid_shifts", 0)),
            int(summary.get("research_blocked_factions", 0))])
        var faction_ids: Array = treasuries.keys()
        faction_ids.sort()
        for faction_id in faction_ids:
            var commander: Dictionary = research_heads.get(faction_id, {})
            var technologies: Array = commander.get("technologies", [])
            var target: String = str(commander.get("research", ""))
            if target.is_empty() or target == "<null>":
                target = "цель не выбрана"
            lines.append("  %s · казна N9 %d CR · изучено %d · %s (%d/%d)" % [
                str(faction_id), int(treasuries[faction_id]), technologies.size(),
                target, int(commander.get("progress", 0)),
                int(commander.get("research_required", 0))])
    # N154 construction is intentionally separate from N135 supply and
    # from N143 research. Render only physical N39 sites and real N104
    # shipment receipts, never a shadow construction intention as a build.
    var live_sites: Dictionary = economy.get("construction_sites", {})
    lines.append("СТРОИТЕЛЬСТВО N154 · площадок %d · оплаченных смен N141 %d · новых объектов %d" % [
        live_sites.size(), int(summary.get("construction_paid_labor_this_tick", 0)),
        int(summary.get("construction_new_facilities_this_tick", 0))])
    var head_paid: int = int(summary.get("construction_head_commissions_this_tick", 0))
    var engineers: int = int(summary.get("construction_engineers_assigned_this_tick", 0))
    if head_paid > 0 or engineers > 0:
        lines.append("  N134: оплаченных проектов %d | N91: инженеров назначено %d" % [
            head_paid, engineers])
    var site_ids: Array = live_sites.keys()
    site_ids.sort()
    for sid in site_ids.slice(0, 8):
        var site: Dictionary = live_sites[sid]
        var labor: Dictionary = site.get("labor", {})
        lines.append("  %s · %s · материалы %d/%d · труд %d/%d" % [
            str(sid), str(site.get("facility_type", "?")),
            int(site.get("progress_delivered", 0)),
            int(site.get("progress_required", 0)),
            int(labor.get("completed", 0)),
            int(labor.get("required", 0))])
    if site_ids.size() > 8:
        lines.append("  … ещё площадок: %d" % (site_ids.size() - 8))
    var source_construction: Dictionary = summary.get("construction_last_observation", {})
    if source_construction.get("ok", false):
        for fid in source_construction.get("factions", {}):
            var view: Dictionary = source_construction["factions"][fid]
            if str(view.get("status", "")) != "idle":
                lines.append("  N154 %s: %s · %s (план, не постройка)" % [
                    str(fid), str(view.get("status", "—")),
                    str(view.get("reason", "—"))])
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
        var stranded_count: int = 0
        var ship_ids: Array = ships.keys()
        ship_ids.sort()
        for sid in ship_ids:
            if not (ships[sid] is Dictionary):
                lines.append("  %s: повреждённая запись корабля" % str(sid))
                continue
            var ship: Dictionary = ships[sid]
            var kind: String = str(ship.get("class", "?"))
            types[kind] = int(types.get(kind, 0)) + 1
            var transit: Dictionary = ship.get("transit", {}) if ship.get("transit", {}) is Dictionary else {}
            var fuel: float = float(ship.get("fuel", 0.0))
            var fuel_capacity: float = float(ship.get("fuel_capacity", 0.0))
            var name: String = str(ship.get("name", sid))
            var location: String = str(ship.get("location", ""))
            var status: String = "СТОЯНКА: " + location
            if not transit.is_empty():
                flight_count += 1
                var destination: String = str(transit.get("to", "?"))
                var origin: String = str(transit.get("from", "?"))
                var position: Variant = transit.get("position", [])
                var position_text: String = "?"
                if position is Array and position.size() == 2:
                    position_text = "(%.2f, %.2f)" % [float(position[0]), float(position[1])]
                var eta: int = int(transit.get("arrival_tick", -1))
                status = "РЕЙС: %s → %s · позиция %s · ETA тик %s" % [
                    origin, destination, position_text,
                    str(eta) if eta >= 0 else "неизвестен"]
                if fuel <= 0.0:
                    stranded_count += 1
                    status += " · БЕЗ ТОПЛИВА"
            lines.append("  %s [%s] · %s" % [name, kind, status])
            lines.append("    фракция %s · система %s · Fuel %.2f/%.2f · экипаж %s" % [
                str(ship.get("faction_id", "?")), str(ship.get("system_id", "?")),
                fuel, fuel_capacity, str(ship.get("crew_size", "?"))])
            var cargo: Variant = ship.get("cargo", {})
            var cargo_items: Array[String] = []
            var cargo_used: int = 0
            if cargo is Dictionary:
                var goods: Array = cargo.keys()
                goods.sort()
                for good in goods:
                    var quantity: int = int(cargo[good])
                    cargo_used += quantity
                    if quantity > 0:
                        cargo_items.append("%s=%d" % [str(good), quantity])
            lines.append("    груз %d/%d: %s" % [
                cargo_used, int(ship.get("cargo_capacity", 0)),
                ", ".join(cargo_items) if not cargo_items.is_empty() else "пусто"])
        var class_ids: Array = types.keys()
        class_ids.sort()
        var class_lines: Array[String] = []
        for kind in class_ids:
            class_lines.append("%s %d" % [str(kind), int(types[kind])])
        lines.append("Классы: " + ", ".join(class_lines))
        lines.append("В пути: %d · на месте: %d · без топлива в рейсе: %d" % [
            flight_count, ships.size() - flight_count, stranded_count])
        lines.append("Доставка считается завершённой только после N104 receipt и физического N15/N97 Apply.")
    lines.append("N134/N100/N155 стратегические планировщики: полная автономия ещё не подтверждена.")
    _label.text = "\n".join(lines)
