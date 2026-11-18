extends SceneTree
## Source-based smoke of Figma Make compact-workspace routing.
## No N39/AI simulation is executed, and no DEMO objects are introduced.
const Workspaces = preload("res://scripts/view/strategy_workspaces.gd")

func _initialize() -> void:
    call_deferred("_verify")

func _verify() -> void:
    var expected: Dictionary = {
        "colony": ["Сводка"],
        "facility": ["Процесс и снабжение", "Труд и склад"],
        "economy": ["Рынок и цепочки", "Дефициты и узкие места"],
        "construction": ["Проекты и снабжение"],
        "fleet": ["Рейсы и контракты", "Грузы и стыковка"],
        "administration": ["Цели и задачи", "Объяснения"],
        "research": ["Текущая программа"]
    }
    for mode in expected:
        assert(Workspaces.TABS.get(mode, []) == expected[mode])
    var aliases: Array = [
        ["colony", "Обзор", "Сводка"],
        ["colony", "Население", "Сводка"],
        ["facility", "Поставщики", "Процесс и снабжение"],
        ["facility", "Склад", "Труд и склад"],
        ["economy", "Баланс", "Рынок и цепочки"],
        ["economy", "Узкие места", "Дефициты и узкие места"],
        ["construction", "Материалы", "Проекты и снабжение"],
        ["construction", "Блокировки", "Проекты и снабжение"],
        ["fleet", "Маршруты", "Рейсы и контракты"],
        ["fleet", "Контракты", "Рейсы и контракты"],
        ["fleet", "Стыковка", "Грузы и стыковка"],
        ["administration", "Приоритеты ИИ", "Цели и задачи"],
        ["administration", "Обоснование", "Объяснения"],
        ["research", "Предпосылки", "Текущая программа"]
    ]
    for entry in aliases:
        assert(Workspaces.canonical_tab(entry[0],
            entry[1]) == entry[2])
    var ui: VBoxContainer = Workspaces.new()
    root.add_child(ui)
    var world: Dictionary = {
        "system": {"id": "system-ven", "name": "Venus system"},
        "bodies": [{"id": "venus", "name": "Venus",
            "type": "planet"}],
        "facilities": []
    }
    var economy: Dictionary = {
        "facilities": {
            "ac-venus": {
                "name": "Venus Colony",
                "type": "station", "location": "venus-colony",
                "body_id": "venus", "faction": "faction-1",
                "credits": 100
            }
        },
        "markets": {}, "populations": {},
        "ships": {}, "construction_sites": {}
    }
    ui.show_state("colony", "Обзор", world, economy,
        "venus", "", "", 42)
    assert(str(ui.get("_tab")) == "Сводка")
    assert(ui.call("_facility_rows", "venus").size() == 1)
    ui.show_state("fleet", "Контракты", world, economy,
        "venus", "", "", 43)
    assert(str(ui.get("_tab")) == "Рейсы и контракты")
    ui.show_state("research", "Открытия", world, economy,
        "venus", "", "", 44)
    assert(str(ui.get("_tab")) == "Текущая программа")
    ui.queue_free()
    print("FIGMA_UX_V2_ROUTE_PASS")
    quit(0)
