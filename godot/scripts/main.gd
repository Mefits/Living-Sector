extends Control
## Godot P0: view the real Galaxy seed, never pretend this is a running sim.

const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const SystemMap = preload("res://scripts/system_map.gd")

var _model
var _map: Control
var _details: RichTextLabel
var _status: Label

func _ready() -> void:
    var background := ColorRect.new()
    background.color = Color("#08101a")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var margins := MarginContainer.new()
    add_child(margins)
    margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
        margins.add_theme_constant_override(side, 14)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margins.add_child(root)

    var heading := HBoxContainer.new()
    root.add_child(heading)
    var title := Label.new()
    title.text = "LIVING SECTOR  /  GODOT P0"
    title.add_theme_font_size_override("font_size", 23)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    heading.add_child(title)
    var reset := Button.new()
    reset.text = "Центрировать карту"
    reset.pressed.connect(_reset_map)
    heading.add_child(reset)

    _status = Label.new()
    _status.text = "Загрузка замороженных JSON Galaxy 0.6.7..."
    _status.add_theme_color_override("font_color", Color("#9fb9c9"))
    root.add_child(_status)

    var columns := HBoxContainer.new()
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_theme_constant_override("separation", 10)
    root.add_child(columns)

    var map_panel := PanelContainer.new()
    map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(map_panel)

    _map = SystemMap.new()
    _map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _map.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _map.custom_minimum_size = Vector2(420, 420)
    map_panel.add_child(_map)

    var details_panel := PanelContainer.new()
    details_panel.custom_minimum_size = Vector2(355, 0)
    details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(details_panel)

    _details = RichTextLabel.new()
    _details.bbcode_enabled = false
    _details.scroll_active = true
    _details.fit_content = false
    details_panel.add_child(_details)

    var footer := Label.new()
    footer.text = "P0 · данные только для чтения · экономика, контракты, корабельные тики и ИИ ещё не перенесены"
    footer.add_theme_color_override("font_color", Color("#8da6b5"))
    root.add_child(footer)

    var data: Dictionary = NativeData.load_current_world()
    if data.has("error"):
        _status.text = "Ошибка импорта Galaxy"
        _details.text = str(data["error"])
        push_error(str(data["error"]))
        return

    _model = WorldModel.new()
    if not _model.load_seed(data):
        _status.text = "Ошибка индексации исходного мира"
        _details.text = "Godot не смог построить read-only индексы исходных JSON."
        push_error(_details.text)
        return

    var stats: Dictionary = _model.seed_stats()
    _status.text = "Исходный Galaxy: %d систем · %d фракции · %d тел · %d объектов · %d корабля" % [
        stats.get("systems", 0), stats.get("factions", 0),
        stats.get("bodies", 0), stats.get("facilities", 0),
        stats.get("ships", 0)
    ]
    var worlds: Array = _model.worlds()
    _map.call("set_worlds", worlds)
    _map.connect("system_selected", _select_world)
    var initial: Dictionary = _model.system_by_id("system-sol")
    if initial.is_empty() and not worlds.is_empty():
        initial = worlds[0]
    if not initial.is_empty():
        _select_world(initial)
    print("GODOT_P0_SEED_LOADED ", JSON.stringify(stats))

func _reset_map() -> void:
    if _map:
        _map.call("reset_view")

func _select_world(world: Dictionary) -> void:
    var system: Dictionary = world.get("system", {})
    var sid: String = str(system.get("id", ""))
    _map.call("select_system", sid)
    var bodies: Array = world.get("bodies", [])
    var facilities: Array = world.get("facilities", [])
    var markets: Array = world.get("markets", [])
    var ships: Array = world.get("ships", [])
    var populations: Array = world.get("populations", [])
    var routes: Array = world.get("travel_routes", [])
    var lines: Array[String] = []
    lines.append("СИСТЕМА: " + str(system.get("name", "—")))
    lines.append("ID: " + sid)
    lines.append("Звезда: " + str(system.get("star_type", "—")))
    lines.append("universe_offset: " + str(system.get("universe_offset", "—")))
    lines.append("Координаты не выражены в световых годах.")
    lines.append("")
    lines.append("СТАРТОВЫЕ ОБЪЕКТЫ")
    lines.append("Тел: %d   Предприятий/станций: %d" % [bodies.size(), facilities.size()])
    lines.append("Кораблей: %d   Рынков: %d" % [ships.size(), markets.size()])
    lines.append("Записей населения: %d" % populations.size())
    lines.append("")
    lines.append("НЕБЕСНЫЕ ТЕЛА")
    for body in bodies:
        lines.append(" • %s [%s]  биом: %s" % [
            body.get("name", "—"), body.get("type", "—"), body.get("biome", "—")
        ])
    lines.append("")
    lines.append("ПРЕДПРИЯТИЯ / СТАНЦИИ")
    for facility in facilities:
        lines.append(" • %s [%s]" % [
            facility.get("name", "—"), facility.get("type", "—")
        ])
        lines.append("   Владелец: " + str(facility.get("faction_id", "—")))
    lines.append("")
    lines.append("НАЧАЛЬНЫЕ КОРАБЛИ")
    for ship in ships:
        lines.append(" • %s [%s]" % [ship.get("name", "—"), ship.get("class", "—")])
    lines.append("")
    lines.append("ЛОКАЛЬНЫЕ МАРШРУТЫ")
    for route in routes:
        lines.append(" • %s → %s : %s (нативные единицы)" % [
            route.get("from", "—"), route.get("to", "—"),
            route.get("distance", "—")
        ])
    lines.append("")
    lines.append("ФРАКЦИИ ЭТАЛОНА")
    for faction in _model.factions():
        lines.append(" • %s [%s]" % [
            faction.get("name", "—"), faction.get("id", "—")
        ])
    lines.append("")
    lines.append("Все числовые ресурсы в JSON остаются исходными.")
    lines.append("Изменения запасов и тики на этом этапе не выполняются.")
    _details.text = "\n".join(lines)
