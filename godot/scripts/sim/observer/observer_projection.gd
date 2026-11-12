extends RefCounted
## N20: read-only observer projection. Does not authorize or execute orders.
## Native parity: strategy/coordination.rs HeadDecision, station.rs StationView.
## Missing live inputs are explicitly unavailable, never synthesized from seed.
const MODES: Array[String] = ["hold", "advise", "delegate"]

static func build(tick: int, faction_id: String, state: Dictionary) -> Dictionary:
    if tick < 0 or faction_id.is_empty():
        return {"ok": false, "reason": "invalid_observation"}
    var result: Dictionary = {"ok": true, "tick": tick, "faction_id": faction_id,
        "head": {"available": false, "reason": "head_not_connected"},
        "stations": [], "contracts": [],
        "production": {"available": false, "reason": "production_not_connected"},
        "commands": []}
    var head: Dictionary = state.get("head", {})
    if bool(head.get("ok", false)) and str(head.get("faction_id", "")) == faction_id and int(head.get("tick", -1)) == tick:
        var alternatives: Array[Dictionary] = []
        for raw in head.get("alternatives", []):
            if not raw is Dictionary:
                continue
            var item: Dictionary = raw
            alternatives.append({"action": str(item.get("action", "")),
                "target": str(item.get("target", "")), "ready": bool(item.get("ready", false)),
                "reason": str(item.get("reason", "not_ready")),
                "cost": int(item.get("cost", 0)), "score": float(item.get("score", 0.0))})
        result["head"] = {"available": true, "selected": str(head.get("selected_option", "wait")),
            "target": str(head.get("selected_target", "")),
            "reason": str(head.get("reason", "")),
            "spending_limit": int(head.get("spending_limit", 0)),
            "planned_spend": int(head.get("planned_spend", 0)),
            "committed_spend": int(head.get("committed_spend", 0)),
            "alternatives": alternatives}
    for raw in state.get("stations", []):
        if not raw is Dictionary:
            continue
        var station: Dictionary = raw
        if str(station.get("faction_id", "")) != faction_id or int(station.get("observed_tick", -1)) != tick:
            continue
        var modules: Array[Dictionary] = []
        for module_raw in station.get("modules", []):
            if not module_raw is Dictionary:
                continue
            var m: Dictionary = module_raw
            modules.append({"id": str(m.get("facility_id", "")),
                "assigned": int(m.get("assigned_workers", 0)),
                "actual": int(m.get("actual_workers", 0)),
                "reason": str(m.get("reason", "")),
                "execution_reason": str(m.get("execution_reason", "not_executed"))})
        modules.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return str(a["id"]) < str(b["id"]))
        result["stations"].append({"location": str(station.get("location", "")),
            "executing": bool(station.get("executing", false)),
            "workforce": int(station.get("workforce", 0)),
            "assigned": int(station.get("assigned_workers", 0)),
            "modules": modules})
    result["stations"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["location"]) < str(b["location"]))
    for raw in state.get("contracts", []):
        if not raw is Dictionary:
            continue
        var c: Dictionary = raw
        if str(c.get("faction_id", "")) != faction_id or int(c.get("observed_tick", -1)) != tick:
            continue
        result["contracts"].append({"id": str(c.get("id", "")),
            "status": str(c.get("status", "unknown")),
            "cargo_delivered": bool(c.get("cargo_delivered", false)),
            "paid": bool(c.get("paid", false))})
    result["contracts"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a["id"]) < str(b["id"]))
    var production: Dictionary = state.get("production", {})
    if bool(production.get("authoritative", false)) and int(production.get("observed_tick", -1)) == tick and str(production.get("faction_id", "")) == faction_id:
        result["production"] = {"available": true,
            "facility_id": str(production.get("facility_id", "")),
            "produced": production.get("produced", {}).duplicate(true),
            "receipt": str(production.get("receipt", ""))}
    var policies: Dictionary = state.get("policies", {})
    for department in ["logistics", "construction", "research"]:
        var mode: String = str(policies.get(department, "hold"))
        if not MODES.has(mode):
            mode = "hold"
        # Display-only; a real command requires an authoritative policy writer
        # and executor with live permission/stock/ledger revalidation.
        result["commands"].append({"department": department, "mode": mode,
            "enabled": false, "reason": "command_executor_not_connected"})
    return result

static func describe(view: Dictionary) -> String:
    if not view.get("ok", false):
        return "Наблюдение недоступно: " + str(view.get("reason", "unknown"))
    var lines: Array[String] = ["ФРАКЦИЯ: %s · ТИК %d" % [view["faction_id"], view["tick"]]]
    var head: Dictionary = view["head"]
    if head["available"]:
        lines.append("Глава: %s %s · %s" % [head["selected"], head["target"], head["reason"]])
        lines.append("Лимит: %d · план: %d · оплачено: %d" % [
            head["spending_limit"], head["planned_spend"], head["committed_spend"]])
        for option in head["alternatives"]:
            lines.append("  %s %s: %s (%s)" % [option["action"], option["target"],
                "доступно" if option["ready"] else "недоступно", option["reason"]])
    else:
        lines.append("Глава: нет подключённого решения на этот тик")
    lines.append("АДМИНИСТРАТОРЫ:")
    if view["stations"].is_empty():
        lines.append("  Нет подключённых решений")
    for station in view["stations"]:
        lines.append("  %s · работников %d / назначено %d" % [
            station["location"], station["workforce"], station["assigned"]])
        for m in station["modules"]:
            lines.append("    %s · план %d / факт %d · %s" % [
                m["id"], m["assigned"], m["actual"], m["execution_reason"]])
    lines.append("ПРОИЗВОДСТВО:")
    lines.append("  %s" % ["Квитанция " + str(view["production"]["receipt"]) if view["production"]["available"] else "Нет подтверждённого исполнения"])
    lines.append("КОНТРАКТЫ:")
    if view["contracts"].is_empty():
        lines.append("  Нет подключённых контрактных записей")
    for c in view["contracts"]:
        lines.append("  %s · %s · груз %s · оплата %s" % [
            c["id"], c["status"], "да" if c["cargo_delivered"] else "нет",
            "да" if c["paid"] else "нет"])
    lines.append("ПОЛНОМОЧИЯ (только просмотр):")
    for command in view["commands"]:
        lines.append("  %s: %s · команды недоступны" % [command["department"], command["mode"]])
    return "\n".join(lines)
