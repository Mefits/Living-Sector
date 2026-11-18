extends RefCounted
## Compact, read-only explanations for a real N134/N154 decision cycle.
## Never runs planning, queries N39 or synthesizes a candidate/market/AI order.
## All fields are derived from already accepted N158 strategy observations.

const REASONS: Dictionary = {
    "ready": "Проект допустим по текущим проверкам",
    "no_chronic_shortage": "Нет длительного дефицита",
    "no_ready_native_option": "Нет разрешённого готового проекта",
    "no_accessible_stock": "Недостаточно доступных материалов на других рынках",
    "unprofitable_source": "Материалы есть, но закупка не проходит ценовое ограничение",
    "insufficient_budget": "Недостаточно денег фракции",
    "insufficient_project_budget": "Не хватает бюджета на полный строительный цикл",
    "no_free_station_slot": "Не осталось строительных слотов у станции",
    "no_local_resource": "Нет нужного местного сырья",
    "no_producer": "Для ресурса нет доступного типа предприятия",
    "producer_already_present": "Предприятие этого типа уже есть",
    "producer_already_planned": "Предприятие этого типа уже запланировано",
    "invalid_site_location": "Площадка или маршрут не прошли проверку",
    "head_priority": "Глава фракции выбрал другой приоритет",
    "existing_contract": "Ожидается ранее оплаченная поставка",
    "shadow_no_mutation": "Проект оценён, но не разрешён к исполнению",
    "research_required_alloytech2": "Требуется технология сплавов T2",
    "research_required_quantumtech3": "Требуется квантовая технология T3",
    "awaiting_paid_labor": "Материалы доставлены; ожидается оплачиваемый труд",
    "no_projected_shortage_relief": "Не обнаружен дефицит, который окупит проект",
    "cost_exceeds_projected_relief": "Расчётная польза ниже стоимости проекта",
    "outstanding_native_plan_retained": "Предыдущий оплаченный план ещё выполняется",
    "n113_current_original_head_preempts_legacy_n154": "Приоритет главы фракции выше строительства",
    "b1_native_head_preempts_competing_n154": "Колонизация или другая задача имеет приоритет",
    "n100_plan_awaits_original_n121_executor": "Стратегический план ждёт исполнителя",
    "colony_life_support_native_goal": "Приоритет — жизнеобеспечение колонии",
    "source_n134_wait": "Стратегический ИИ решил пока не строить",
    "no_native_ready_site": "Нет готовой к строительству площадки",
    "existing_colony_life_support_crisis": "Колония испытывает нехватку базовых ресурсов",
    "missing_native_construction_world": "Сведения для оценки строительства отсутствуют"
}

static func reason_text(code: String) -> String:
    return str(REASONS.get(code, code.replace("_", " ")))

static func action_text(code: String) -> String:
    return str({
        "wait": "Ожидать", "build": "Строить",
        "deliver": "Доставить ресурсы", "research": "Исследовать",
        "found_colony": "Основать колонию", "supply_colony": "Обеспечить колонию",
        "migrate_colony": "Перевезти жителей", "hybrid_native": "Исполнить план"
    }.get(code, code))

static func _focused_faction(economy: Dictionary, body_id: String) -> String:
    if body_id.is_empty():
        return ""
    var facilities: Variant = economy.get("facilities", {})
    if not (facilities is Dictionary):
        return ""
    for id in facilities:
        var row: Variant = facilities[id]
        if not (row is Dictionary):
            continue
        var bid: String = str(row.get("body_id", row.get("body", "")))
        if bid == body_id and str(row.get("location", "")) == (
                body_id + "-colony") and str(row.get("type", "")) in [
                "station", "construction_dock"]:
            return str(row.get("faction", row.get("faction_id", "")))
    return ""

static func _head_item(raw: Dictionary) -> Dictionary:
    var item: Dictionary = {
        "action": str(raw.get("selected_option", "wait")),
        "reason": str(raw.get("reason", "")),
        "target": str(raw.get("selected_target", "")),
        "problem": raw.get("problem", {})
    }
    return item

static func build(trace: Dictionary, economy: Dictionary,
        body_id: String = "") -> Dictionary:
    var faction_focus: String = _focused_faction(economy, body_id)
    var result: Dictionary = {
        "tick": int(trace.get("strategy_tick",
            trace.get("tick", -1))),
        "focused_faction": faction_focus,
        "factions": []
    }
    var rows: Dictionary = {}
    # Worker receives a cached N158 summary; local mode receives the same
    # bounded strategy_trace. Neither permits implicit actor creation.
    var compact: Variant = trace.get("strategy_trace", {})
    if compact is Dictionary:
        for raw_id in compact.get("factions", {}):
            var fid: String = str(raw_id)
            var value: Variant = compact["factions"][raw_id]
            if value is Dictionary:
                rows[fid] = value
    if rows.is_empty():
        var observations: Variant = trace.get(
            "construction_last_observation", {})
        var heads: Variant = trace.get("construction_heads", {})
        if observations is Dictionary:
            var items: Variant = observations.get("factions", {})
            if items is Dictionary:
                for raw_id in items:
                    var fid: String = str(raw_id)
                    var view: Variant = items[raw_id]
                    if view is Dictionary:
                        rows[fid] = {"construction": view}
        if heads is Dictionary:
            for raw_id in heads:
                var fid: String = str(raw_id)
                if not rows.has(fid):
                    rows[fid] = {}
                rows[fid]["head"] = heads[raw_id]
    var keys: Array = rows.keys()
    keys.sort()
    for key in keys:
        var fid: String = str(key)
        if not faction_focus.is_empty() and faction_focus != fid:
            continue
        var item: Dictionary = rows[key]
        var head: Dictionary = item.get("head", {})
        var view: Dictionary = item.get("construction", {})
        var choices: Array[Dictionary] = []
        var offers: Variant = view.get("offers", [])
        if offers is Array:
            for raw_offer in offers:
                if not (raw_offer is Dictionary):
                    continue
                var goal: Variant = raw_offer.get("goal", {})
                if not (goal is Dictionary):
                    continue
                choices.append({
                    "goal": str(goal.get("goal_id", "")),
                    "commodity": str(goal.get("commodity", "")),
                    "location": str(goal.get("destination", "")),
                    "building": str(raw_offer.get("facility_type", "")),
                    "reason": str(raw_offer.get("reason", "")),
                    "ready": bool(raw_offer.get("ready", false)),
                    "material": str(raw_offer.get("delivery_commodity", "")),
                    "cost": int(raw_offer.get("total_cost", 0))
                })
                if choices.size() >= 5:
                    break
        result["factions"].append({
            "id": fid, "action": str(head.get("action",
                head.get("selected_option", ""))),
            "head_reason": str(head.get("reason", "")),
            "valuation_reason": str(head.get(
                "valuation", {}).get("build_reason", "")),
            "valuation_goal": head.get("valuation", {}).get(
                "goal", {}),
            "problem": head.get("problem", {}),
            "construction_status": str(view.get("status", "")),
            "construction_reason": str(view.get("reason", "")),
            "selected_goal": view.get("selected_goal", {}),
            "offers": choices
        })
    return result
