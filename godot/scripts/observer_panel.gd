extends PanelContainer
## N20 observational UI: no command buttons until real executor is wired.
const ObserverProjection = preload("res://scripts/sim/observer/observer_projection.gd")
const SECTIONS := ["Сводка", "Заказы", "Исследования", "Строительство",
    "Станции", "Производство", "Рынки", "Население", "Флот"]
var _label: RichTextLabel
var _section_choice: OptionButton
var _section_texts: Dictionary = {}

func _ready() -> void:
    custom_minimum_size = Vector2(340, 280)
    var column := VBoxContainer.new()
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(column)
    var heading := Label.new()
    heading.text = "НАБЛЮДЕНИЕ"
    heading.add_theme_font_size_override("font_size", 16)
    column.add_child(heading)
    _section_choice = OptionButton.new()
    _section_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for section in SECTIONS:
        _section_choice.add_item(str(section))
    _section_choice.item_selected.connect(_on_section_selected)
    column.add_child(_section_choice)
    _label = RichTextLabel.new()
    _label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _label.selection_enabled = true
    _label.scroll_following = false
    _label.add_theme_font_size_override("normal_font_size", 15)
    column.add_child(_label)
    show_observation(0, "unselected", {})

func _on_section_selected(_index: int) -> void:
    _show_selected(true)

func _show_selected(reset_scroll: bool = false) -> void:
    if _label == null or _section_choice == null:
        return
    var selected: int = _section_choice.selected
    if selected < 0 or selected >= SECTIONS.size():
        return
    var section: String = str(SECTIONS[selected])
    var content: String = str(_section_texts.get(section, "Пока нет данных"))
    if _label.text == content:
        return
    var scrollbar: VScrollBar = _label.get_v_scroll_bar()
    var old_position: float = scrollbar.value
    _label.text = content
    if reset_scroll:
        scrollbar.value = 0.0
    else:
        scrollbar.value = minf(old_position, maxf(0.0, scrollbar.max_value - scrollbar.page))

func show_observation(tick: int, faction_id: String, state: Dictionary) -> void:
    var value: String = ObserverProjection.describe(ObserverProjection.build(tick, faction_id, state))
    _section_texts["Сводка"] = value
    _show_selected()

## P2 live economy inspection: read ONLY the authoritative N39 snapshot.
## Do not present unconnected N20 planner decisions as active gameplay.
func show_live_economy(tick: int, economy: Dictionary, summary: Dictionary,
        ships: Dictionary = {}, proof: Dictionary = {}) -> void:
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
    # This is evidence, not a new event log: receipts are read from the
    # exact N38 checkpoint of the one N39/N9 world. A BT plan, route or
    # ContractBoard status alone is never displayed as physical delivery.
    var proof_ledger: Dictionary = proof.get("ledger", {}) if proof.get("ledger", {}) is Dictionary else {}
    var proof_receipts: Dictionary = proof_ledger.get("receipts", {}) if proof_ledger.get("receipts", {}) is Dictionary else {}
    var cargo_receipts: Dictionary = economy.get("cargo_receipts", {}) if economy.get("cargo_receipts", {}) is Dictionary else {}
    if not order_ids.is_empty():
        lines.append("ДОКАЗАТЕЛЬСТВА АВТОНОМНОЙ ЦЕПОЧКИ (сохранённые receipts):")
        for cid_variant in order_ids.slice(0, 8):
            var proof_id: String = str(cid_variant)
            var proof_contract: Dictionary = contracts.get(proof_id, {})
            var proof_ship: String = str(proof_contract.get("fulfiller_id", ""))
            var load_receipt: Dictionary = cargo_receipts.get("contract:" + proof_id + ":load", {})
            var unload_receipt: Dictionary = cargo_receipts.get("contract:" + proof_id + ":unload", {})
            var payout_receipt: Dictionary = proof_receipts.get("contract:" + proof_id + ":payout", {})
            var milestones: Array[String] = []
            if not load_receipt.is_empty() and str(load_receipt.get("action", "")) == "load":
                milestones.append("N15/N97 pickup подтверждён")
            if not unload_receipt.is_empty() and str(unload_receipt.get("action", "")) == "unload":
                milestones.append("N15 delivery подтверждён")
            if not payout_receipt.is_empty():
                milestones.append("N104/N9 payout подтверждён")
            if milestones.is_empty():
                lines.append("  %s · %s · физического/денежного receipt пока нет" % [
                    proof_id, str(proof_contract.get("status", "unknown"))])
            else:
                lines.append("  %s · корабль %s · %s" % [proof_id,
                    proof_ship if not proof_ship.is_empty() else "не назначен",
                    " → ".join(milestones)])
                if not payout_receipt.is_empty():
                    lines.append("    payout: %s" % str(payout_receipt.get("id", "сохранён в N9")))
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
    # An N147 proposal is deliberately NOT a paid passenger contract or
    # a colonized location. Display the last real read-only policy scan.
    # N151 site approval is a separate source-backed action, NOT an
    # existing colony nor a paid N104 passenger mission.
    var foundation_status: String = str(summary.get("colony_founding_status", "NOT_EVALUATED"))
    if foundation_status != "NOT_EVALUATED":
        lines.append("ОСНОВАНИЕ N151 · доступных планов без утверждения: %d" % [
            int(summary.get("colony_founding_ready_unapproved", 0))])
        var foundation_blocked: Array = summary.get("colony_founding_blocked", [])
        for blocked in foundation_blocked.slice(0, 3):
            if blocked is Dictionary:
                lines.append("  %s · %s" % [
                    str(blocked.get("faction_id", "?")),
                    str(blocked.get("reason", "неизвестная блокировка"))])
    var colony_status: String = str(summary.get("colony_migration_status", "NOT_EVALUATED"))
    if colony_status == "N147_NO_ESTABLISHED_COLONIES":
        lines.append("КОЛОНИИ N147 · действующих колоний нет · пассажирских контрактов 0")
    elif colony_status == "N147_SOURCE_EVALUATED":
        lines.append("КОЛОНИИ N147 · наблюдается %d · предложений переселения %d (НЕ отправлены)" % [
            int(summary.get("colony_observed_groups", 0)),
            int(summary.get("colony_passenger_proposals_unposted", 0))])
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
    var last_migration: Dictionary = summary.get("population_last_migration", {})
    if not last_migration.is_empty():
        lines.append("  N151 миграция · тик %d · %s → %s · жителей %d · переведено %d CR (N9)" % [
            int(last_migration.get("tick", -1)),
            str(last_migration.get("source_location", "?")),
            str(last_migration.get("destination_location", "?")),
            int(last_migration.get("count", 0)),
            int(last_migration.get("wealth_transferred", 0))])
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
    _split_diagnostics(lines)
    _section_texts["Сводка"] = _compact_summary(tick, economy, summary, ships, contracts)
    _show_selected()

## Keep complete N9/N104/N14 evidence in its own page, but never force
## a user to scroll through 15 facilities and 24 ships just to diagnose AI.
func _split_diagnostics(lines: Array[String]) -> void:
    var pages: Dictionary = {}
    for section in SECTIONS:
        pages[str(section)] = []
    var section: String = ""
    for line in lines:
        if line.begins_with("КОНТРАКТЫ N135") or line.begins_with("АВТОНОМНЫЕ ЗАКАЗЫ"):
            section = "Заказы"
        elif line.begins_with("ИССЛЕДОВАНИЯ N143"):
            section = "Исследования"
        elif line.begins_with("СТРОИТЕЛЬСТВО N154") or line.begins_with("КОЛОНИИ N147"):
            section = "Строительство"
        elif line.begins_with("СТАНЦИИ / КРЕДИТЫ"):
            section = "Станции"
        elif line.begins_with("ОПЛАЧЕННЫЕ СМЕНЫ") or line.begins_with("ОТКАЗЫ ОПЛАТЫ РЕМОНТА") or line.begins_with("ОСТАНОВКИ ПРОИЗВОДСТВА"):
            section = "Производство"
        elif line.begins_with("РЫНКИ / ФИЗИЧЕСКИЕ"):
            section = "Рынки"
        elif line.begins_with("НАСЕЛЕНИЕ / БЛАГОСОСТОЯНИЕ"):
            section = "Население"
        elif line.begins_with("РЕАЛЬНЫЙ ФЛОТ") or line.begins_with("Флот: старый checkpoint"):
            section = "Флот"
        elif line.begins_with("N134/N100/N155"):
            section = "Строительство"
        if not section.is_empty():
            (pages[section] as Array).append(line)
    for key in pages:
        var content: Array = pages[key]
        _section_texts[key] = "\n".join(content) if not content.is_empty() else "В этом разделе данных пока нет."

## N135 posts only when real N151 consumption-window purchases exceed
## the physical market supply; zero contract count alone is not an AI error.
## This is observation, never a second demand queue or invented contract.
static func demand_diagnosis(economy: Dictionary, summary: Dictionary) -> String:
    if str(summary.get("station_demand_status", "NOT_EVALUATED")) == "NOT_EVALUATED":
        return "N135: рынок ещё не оценивал потребности"
    var created: int = int(summary.get("station_demand_candidates", 0))
    if created > 0:
        return "N135: найдено заявок %d; публикацию см. в «Заказы»" % created
    var markets: Dictionary = economy.get("markets", {})
    var with_purchases: int = 0
    var deficits: int = 0
    for raw in markets.values():
        if not (raw is Dictionary):
            continue
        var supply: Dictionary = raw.get("supply", {})
        var windows: Dictionary = raw.get("consumption_window", {})
        for commodity in windows:
            if not (windows[commodity] is Array):
                continue
            var consumed: float = 0.0
            for entry in windows[commodity]:
                if entry is Dictionary:
                    consumed += float(entry.get("qty", 0.0))
            if consumed > 0.0:
                with_purchases += 1
            if consumed > float(supply.get(commodity, 0.0)):
                deficits += 1
    if deficits > 0:
        return "N135: дефицитов %d, но заявок 0 — проверьте «Заказы»" % deficits
    if with_purchases == 0:
        return "N135: нет истории покупок для расчёта дефицита"
    return "N135: спрос пока покрыт запасами; заказов нет"

static func _compact_summary(tick: int, economy: Dictionary, summary: Dictionary,
        ships: Dictionary, contracts: Dictionary) -> String:
    var active: int = 0
    for contract in contracts.values():
        if contract is Dictionary and str(contract.get("status", "")) in ["posted", "accepted", "picked_up", "delivered"]:
            active += 1
    var traveling: int = 0
    var assigned: int = 0
    for raw in ships.values():
        if not (raw is Dictionary):
            continue
        var transit: Variant = raw.get("transit", {})
        if transit is Dictionary and not transit.is_empty():
            traveling += 1
        if not str(raw.get("active_contract_id", "")).is_empty():
            assigned += 1
    var lines: Array[String] = [
        "ТИК %d · ЖИВАЯ ЭКОНОМИКА" % tick,
        "Станций %d · рынков %d · население %d групп" % [
            economy.get("facilities", {}).size(), economy.get("markets", {}).size(),
            economy.get("populations", {}).size()],
        "",
        "ЗАКАЗЫ / ФЛОТ",
        "N104: %d контрактов · активных %d" % [contracts.size(), active],
        "N153: принято %d · отказов %d" % [
            int(summary.get("n153_accepted_this_tick", 0)),
            int(summary.get("n153_blocked_this_tick", 0))],
        "Корабли: %d · в пути %d · с заказом %d" % [
            ships.size(), traveling, assigned],
        demand_diagnosis(economy, summary),
        "",
        "ПРОИЗВОДСТВО (последний тик)",
        "Зарплаты %d CR · добыча %d · выпуск %d" % [
            int(summary.get("last_wages_paid", 0)),
            int(summary.get("last_mining_facilities", 0)),
            int(summary.get("last_recipe_facilities", 0))],
        "Покупки Food/Water: %d" % int(summary.get("population_purchases", 0)),
        "",
        "РАЗВИТИЕ",
        "Исследования: оплаченных смен %d" % int(summary.get("research_paid_shifts", 0)),
        "Стройка: площадок %d · новых объектов %d" % [
            economy.get("construction_sites", {}).size(),
            int(summary.get("construction_new_facilities_this_tick", 0))],
        "Колонии: %s" % (
            "нет" if summary.get("colony_migration_status", "") == "N147_NO_ESTABLISHED_COLONIES"
            else str(summary.get("colony_migration_status", "не оценены"))),
        "",
        "Подробности — в выборе раздела выше."
    ]
    return "\n".join(lines)
