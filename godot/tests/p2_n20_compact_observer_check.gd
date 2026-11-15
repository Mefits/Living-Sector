extends SceneTree
## P2 N20: compact observer is a read-only projection; no CI required
## until one coordinated Godot acceptance pass.
## godot --headless --path godot --script res://tests/p2_n20_compact_observer_check.gd
const Observer = preload("res://scripts/observer_panel.gd")

func _initialize() -> void:
    var ui = Observer.new()
    var grouped: Array[String] = [
        "ЖИВАЯ ЭКОНОМИКА · ТИК 212",
        "КОНТРАКТЫ N135/N104 · всего 0",
        "Стадии N104: контрактов нет",
        "ИССЛЕДОВАНИЯ N143 / N82 · оплаченных смен 0",
        "СТРОИТЕЛЬСТВО N154 · площадок 0",
        "КОЛОНИИ N147 · действующих колоний нет",
        "СТАНЦИИ / КРЕДИТЫ / СОСТОЯНИЕ:",
        "  station-1",
        "ОПЛАЧЕННЫЕ СМЕНЫ / ПРОИЗВОДСТВО:",
        "  shift-1",
        "РЫНКИ / ФИЗИЧЕСКИЕ ЗАПАСЫ:",
        "  market-1",
        "НАСЕЛЕНИЕ / БЛАГОСОСТОЯНИЕ:",
        "  pop-1",
        "РЕАЛЬНЫЙ ФЛОТ / N46 + N14: 24 судов",
        "  ship-1"
    ]
    ui._split_diagnostics(grouped)
    for item in [
        ["Заказы", "Стадии N104: контрактов нет"],
        ["Исследования", "оплаченных смен"],
        ["Строительство", "КОЛОНИИ N147"],
        ["Станции", "station-1"],
        ["Производство", "shift-1"],
        ["Рынки", "market-1"],
        ["Население", "pop-1"],
        ["Флот", "ship-1"]
    ]:
        if not str(ui._section_texts.get(str(item[0]), "")).contains(str(item[1])):
            _fail("section lost read-only proof: " + str(item[0]))
            return
    if str(ui._section_texts.get("Станции", "")).contains("ship-1"):
        _fail("long stations/ships mixed into one viewport")
        return
    var state: Dictionary = {
        "facilities": {"a": {}},
        "markets": {"earth-station": {
            "supply": {"food": 100.0},
            "consumption_window": {"food": [{"tick": 160, "qty": 7.0}]} }},
        "populations": {}, "construction_sites": {}
    }
    var summary: Dictionary = {
        "station_demand_status": "PROPOSALS_ONLY_NOT_POSTED",
        "station_demand_candidates": 0,
        "n153_accepted_this_tick": 0, "n153_blocked_this_tick": 0
    }
    var waiting: String = Observer.demand_diagnosis(state, summary)
    if not waiting.contains("покрыт запасами"):
        _fail("N135 zero orders not explained by actual market stock")
        return
    var concise: String = Observer._compact_summary(
        212, state, summary, {"s1": {"transit": {}, "active_contract_id": ""}}, {})
    if concise.split("\n").size() > 20 or concise.contains("station-1") or not concise.contains("Корабли: 1"):
        _fail("summary no longer fits a compact viewport")
        return
    state["markets"]["earth-station"]["supply"]["food"] = 1.0
    if not Observer.demand_diagnosis(state, summary).contains("дефицитов 1"):
        _fail("unposted consumption shortage hidden from observer")
        return
    state["markets"]["earth-station"]["consumption_window"] = {}
    if not Observer.demand_diagnosis(state, summary).contains("нет истории покупок"):
        _fail("empty N151 consumption history not distinguished")
        return
    summary["station_demand_candidates"] = 2
    if not Observer.demand_diagnosis(state, summary).contains("найдено заявок 2"):
        _fail("N135 proposal exists but no order incorrectly diagnosed")
        return
    print("P2_N20_COMPACT_OBSERVER_AND_N135_ZERO_ORDER_DIAGNOSTIC_PASS")
    quit(0)

func _fail(reason: String) -> void:
    push_error("P2_N20_OBSERVER_FAIL: " + reason)
    quit(1)
