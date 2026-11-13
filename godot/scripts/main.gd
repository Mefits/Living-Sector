extends Control
## P2 N158: original Galaxy orbital clock + real N39 physical paid production.
## Fleet, contract, population consumption and Head AI still await later P2 integration.

const NativeData = preload("res://scripts/native_data.gd")
const TickRunner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const P2_SAVE_PATH: String = "user://saves/galaxy-067-p2-integration.json"
const SPEEDS = [0.25, 1.0, 2.0, 4.0, 8.0, 16.0]
const SystemMap = preload("res://scripts/system_map.gd")
const ObserverPanel = preload("res://scripts/observer_panel.gd")

var _model
var _runner
var _seed: Dictionary = {}
var _selected_system: String = "system-sol"
var _notice: String = ""
var _startup_error: String = ""
var _pause_button: Button
var _speed_menu: OptionButton
var _map: Control
var _details: RichTextLabel
var _status: Label
var _observer_panel: PanelContainer
var _observer_button: Button

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
    title.text = "LIVING SECTOR  /  GODOT P2"
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

    var toolbar := HBoxContainer.new()
    toolbar.add_theme_constant_override("separation", 8)
    root.add_child(toolbar)
    _pause_button = Button.new()
    _pause_button.text = "Пауза"
    _pause_button.pressed.connect(_toggle_pause)
    toolbar.add_child(_pause_button)
    for spec in [{"text":"+1 тик", "count":1}, {"text":"+8 тиков", "count":8}]:
        var step_button := Button.new()
        step_button.text = str(spec["text"])
        step_button.pressed.connect(_step.bind(int(spec["count"])))
        toolbar.add_child(step_button)
    var speed_menu := OptionButton.new()
    for speed in SPEEDS:
        speed_menu.add_item("×" + str(speed))
    speed_menu.selected = 0
    _speed_menu = speed_menu
    speed_menu.item_selected.connect(_change_speed)
    toolbar.add_child(speed_menu)
    var save_button := Button.new()
    save_button.text = "Сохранить"
    save_button.pressed.connect(_save_game)
    toolbar.add_child(save_button)
    var load_button := Button.new()
    load_button.text = "Загрузить"
    load_button.pressed.connect(_load_game)
    toolbar.add_child(load_button)

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

    _observer_button = Button.new()
    _observer_button.text = "Наблюдение"
    _observer_button.pressed.connect(_toggle_observer)
    toolbar.add_child(_observer_button)
    _observer_panel = ObserverPanel.new()
    _observer_panel.visible = false
    _observer_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(_observer_panel)

    var footer := Label.new()
    footer.text = "P2 · орбиты + оплаченное производство Rust · население, рынки, корабли, ИИ — следующая интеграция"
    footer.add_theme_color_override("font_color", Color("#8da6b5"))
    root.add_child(footer)

    var data: Dictionary = NativeData.load_current_world()
    if data.has("error"):
        _status.text = "Ошибка импорта Galaxy"
        _details.text = str(data["error"])
        _startup_error = str(data["error"])
        push_error(_startup_error)
        return

    _seed = data
    _runner = TickRunner.new()
    if not _runner.start_from_seed(_seed):
        _status.text = "Ошибка индексации исходного мира"
        _details.text = "Не удалось собрать физический мир P2: " + str(_runner.boot_error())
        _startup_error = _details.text + " / " + str(_runner.boot_error())
        push_error(_startup_error)
        return

    # Resume the one authoritative N158 World/ledger before building map/UI projections.
    # A failed or incompatible checkpoint must never prevent a clean seed boot.
    _restore_startup_checkpoint()
    _model = _runner.world
    _runner.tick_completed.connect(_on_tick_completed)
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
    print("GODOT_P2_PAID_PRODUCTION_BOOT ", JSON.stringify(_runner.production_stats()))
    _update_status()

func _restore_startup_checkpoint() -> void:
    var primary: String = P2_SAVE_PATH
    # SaveState owns pending/backup recovery and checksum validation; do not
    # parse JSON here or create another in-memory economy.
    if not FileAccess.file_exists(primary) and not FileAccess.file_exists(primary + ".bak") and not FileAccess.file_exists(primary + ".pending"):
        return
    var result: Dictionary = SaveState.load_runner(_runner, _seed, primary)
    if bool(result.get("ok", false)):
        var source: String = str(result.get("source", primary))
        _notice = "Автоматически восстановлен P2 тик %s%s" % [
            str(result.get("tick", _runner.tick_count)),
            " (резервная копия)" if source.ends_with(".bak") else ""
        ]
        _sync_speed_control()
    else:
        # Preserve the initialized seed world; the user may still load manually.
        _notice = "Автозагрузка P2 не удалась: " + str(result.get("error", "неизвестная ошибка"))


func _toggle_observer() -> void:
    _observer_panel.visible = not _observer_panel.visible
    _observer_button.text = "Скрыть наблюдение" if _observer_panel.visible else "Наблюдение"
    _refresh_observer()

func _refresh_observer() -> void:
    if not _observer_panel or not _observer_panel.visible or not _runner:
        return
    # The current P1 world contains only seed/orbital state. Never present
    # an unconnected N19/N18/N16 subsystem as if it were executing.
    _observer_panel.call("show_observation", _runner.tick_count, "genesis", {})

func _process(delta: float) -> void:
    if _runner:
        _runner.advance_frame(delta)

func _toggle_pause() -> void:
    if not _runner:
        return
    if _runner.clock.paused and not _runtime_failure().is_empty():
        _notice = "Симуляция остановлена из-за ошибки фазы; загрузите последнее корректное сохранение"
        _update_status()
        return
    _runner.queue_control("resume" if _runner.clock.paused else "pause")
    _runner.advance_frame(0.0)
    _update_status()

func _step(count: int) -> void:
    if not _runner:
        return
    if not _runtime_failure().is_empty():
        _notice = "Нельзя продолжать повреждённый тик; загрузите сохранение"
        _update_status()
        return
    _runner.queue_control("pause")
    _runner.queue_control("step", count)
    _runner.advance_frame(0.0)
    _update_status()

func _change_speed(index: int) -> void:
    if not _runner or index < 0 or index >= SPEEDS.size():
        return
    _runner.queue_control("speed", float(SPEEDS[index]))
    _runner.advance_frame(0.0)
    _update_status()

func _save_game(save_path: String = "") -> void:
    if not _runner:
        return
    _runner.advance_frame(0.0)
    if not _runtime_failure().is_empty():
        _notice = "Сохранение запрещено: незавершённая экономическая фаза. Предыдущий файл не изменён."
        _update_status()
        return
    var target: String = P2_SAVE_PATH if save_path.is_empty() else save_path
    var result: Error = SaveState.save_runner(_runner, target)
    _notice = "Орбиты, товары, зарплаты и чеки сохранены (P2)" if result == OK else "Ошибка сохранения: " + str(result)
    _update_status()

func _load_game(save_path: String = "") -> void:
    if not _runner:
        return
    var target: String = P2_SAVE_PATH if save_path.is_empty() else save_path
    var result: Dictionary = SaveState.load_runner(_runner, _seed, target)
    if result.get("ok", false):
        _model = _runner.world
        # A loaded checkpoint replaces the authoritative world and clock. Refresh
        # all read-only projections; never keep a stale seed-era map or speed UI.
        _map.call("set_worlds", _model.worlds())
        _map.call("select_system", _selected_system)
        _sync_speed_control()
        _refresh_observer()
        var recovered_from_backup: bool = str(result.get("source", "")).ends_with(".bak")
        _notice = ("Восстановлена резервная копия: " if recovered_from_backup else "Загружено сохранение: ") + "орбиты и производство P2, тик " + str(result.get("tick", "—"))
        _refresh_selection()
    else:
        _notice = str(result.get("error", "Не удалось загрузить"))
    _update_status()

func _sync_speed_control() -> void:
    if _speed_menu == null or _runner == null:
        return
    var restored_speed: float = float(_runner.clock.world_speed)
    for index in range(SPEEDS.size()):
        if is_equal_approx(float(SPEEDS[index]), restored_speed):
            # Assigning selected does not dispatch item_selected or mutate time.
            _speed_menu.selected = index
            return
    # A compatible checkpoint may carry a valid custom speed. Do not lie
    # about the current multiplier by displaying a different preset.
    _speed_menu.select(-1)


func _on_tick_completed(tick: int) -> void:
    _refresh_observer()
    if tick % 8 == 0 or not _runner.last_native_result().get("receipts", []).is_empty():
        _refresh_selection()
    _update_status()

func _runtime_failure() -> Dictionary:
    if _runner != null and _runner.has_method("last_phase_failure"):
        return _runner.last_phase_failure()
    return {}

func _update_status() -> void:
    if not _runner:
        return
    var totals: Dictionary = _model.seed_stats()
    _status.text = "%d систем · %d фракции · %d тел   |   Тик %d   |   ×%s   |   %s%s" % [
        totals.get("systems", 0), totals.get("factions", 0),
        totals.get("bodies", 0), _runner.tick_count,
        str(_runner.clock.world_speed),
        "Пауза" if _runner.clock.paused else "Идёт время",
        "   |   " + _notice if not _notice.is_empty() else ""
    ]
    _status.text += "   |   " + _runner.calendar.display_text(_runner.tick_count)
    if _runner.has_method("economy_summary"):
        var economic: Dictionary = _runner.economy_summary()
        _status.text += "   |   Native: %d рын. / %d предприятий" % [int(economic.get("markets", 0)), int(economic.get("facilities", 0))]
        if _runner.tick_count % 5 == 0 and _runner.tick_count > 0:
            _status.text += " · Выпуск: %d · Добыча: %d" % [int(economic.get("last_recipe_facilities", 0)), int(economic.get("last_mining_facilities", 0))]
    var failure: Dictionary = _runtime_failure()
    if not failure.is_empty():
        _status.text += "   |   ОШИБКА ФАЗЫ %s / тик %d: %s" % [
            str(failure.get("phase", "?")), int(failure.get("tick", -1)),
            str(failure.get("reason", "unknown"))]
    _pause_button.text = "Ошибка — загрузите" if not failure.is_empty() else ("Продолжить" if _runner.clock.paused else "Пауза")

func _refresh_selection() -> void:
    if not _runner:
        return
    var selected: Dictionary = _model.system_by_id(_selected_system)
    if not selected.is_empty():
        _select_world(selected)

func _reset_map() -> void:
    if _map:
        _map.call("reset_view")

func _select_world(world: Dictionary) -> void:
    var system: Dictionary = world.get("system", {})
    var sid: String = str(system.get("id", ""))
    _selected_system = sid
    if _model:
        var current: Dictionary = _model.system_by_id(sid)
        if not current.is_empty():
            world = current
            system = world.get("system", {})
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
        lines.append(" • %s [%s] биом: %s угол: %.2f°" % [
            body.get("name", "—"), body.get("type", "—"), body.get("biome", "—"),
            float(body.get("current_angle", 0.0))
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
    # Physical runtime is separate from the read-only orbit geometry.
    # Never display seed stock as if it were current stock.
    if _runner != null and _runner.has_method("economy_snapshot"):
        var economy: Dictionary = _runner.economy_snapshot()
        lines.append("")
        lines.append("ТЕКУЩИЕ РЕАЛЬНЫЕ ЗАПАСЫ И ЗАРПЛАТЫ (N39)")
        for source_market in markets:
            var location: String = str(source_market.get("facility_id", ""))
            if not economy.get("markets", {}).has(location):
                continue
            var live_market: Dictionary = economy["markets"][location]
            var stock: Dictionary = live_market["supply"]
            var goods: Array = stock.keys()
            goods.sort()
            lines.append(" • Рынок " + location + " — владелец " + str(live_market["owner"]))
            var entries: PackedStringArray = PackedStringArray()
            for commodity in goods:
                entries.append("%s %.1f ед. / %.2f CR" % [commodity, float(stock[commodity]), float(live_market.get("prices", {}).get(commodity, 0.0))])
            lines.append("   " + " · ".join(entries))
        for source_fac in facilities:
            var id: String = str(source_fac.get("id", ""))
            if not economy.get("facilities", {}).has(id):
                continue
            var live: Dictionary = economy["facilities"][id]
            var shift: Dictionary = live.get("work_shift", {})
            var shift_text: String = "нет оплаченной смены"
            if not shift.is_empty():
                shift_text = "смена #%d · зарплата %d" % [int(shift.get("tick", 0)), int(shift.get("wages", 0))]
            lines.append(" • %s: %d CR · %s" % [
                str(source_fac.get("name", id)), int(live["credits"]), shift_text
            ])
    lines.append("")
    lines.append("Орбиты и производственный цикл реальны. Корабли, потребление населения,")
    lines.append("динамическая переоценка рынков и ИИ пока не подключены к общему тику.")
    _details.text = "\n".join(lines)

## Read-only boot diagnostics for local Windows/Godot compatibility smoke.
## No gameplay mutation and no false claim that P2/P3 phases execute.
func startup_health() -> Dictionary:
    var booted: bool = _runner != null and _runner.is_started()
    var has_map: bool = _map != null and is_instance_valid(_map)
    var has_ui: bool = _status != null and _details != null and _pause_button != null
    var seed_ok: bool = booted and _model != null and _model.seed_stats().get("systems", 0) == 8
    return {
        "ok": booted and has_map and has_ui and seed_ok and _startup_error.is_empty(),
        "error": _startup_error,
        "godot_version": Engine.get_version_info().get("string", "unknown"),
        "booted": booted,
        "seed_ok": seed_ok,
        "map_ready": has_map,
        "ui_ready": has_ui,
        "tick": _runner.tick_count if booted else -1,
        "runtime_failure": _runtime_failure(),
        "implemented_phases": _runner.implemented_phases() if booted else PackedStringArray()
    }
