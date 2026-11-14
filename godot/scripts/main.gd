extends Control
## P2 N158: original Galaxy orbital clock + real N39 physical paid production.
## Fleet, contract, population consumption and Head AI still await later P2 integration.

const NativeData = preload("res://scripts/native_data.gd")
const TickRunner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const P2_SAVE_PATH: String = "user://saves/galaxy-067-p2-integration.json"
const SPEEDS = [0.25, 1.0, 2.0, 4.0, 8.0, 16.0]
## User decision 13.11.2026: observer-first autonomous sector. Keep the
## N14/N21/N15 manual tools as an explicit later-game debug feature.
## Do NOT remove N39/N14 engine APIs: future autonomous agents reuse them.
const ENABLE_DEBUG_MANUAL_FLEET_UI: bool = false
const SystemMap = preload("res://scripts/system_map.gd")
const StarSystemView = preload("res://scripts/star_system_view.gd")
const ObserverPanel = preload("res://scripts/observer_panel.gd")

var _model
var _runner
var _seed: Dictionary = {}
var _selected_system: String = "system-sol"
var _selected_body_id: String = ""
var _in_system: bool = false
var _notice: String = ""
var _startup_error: String = ""
var _fatal_restore_error: String = ""
var _pause_button: Button
var _speed_menu: OptionButton
var _map: Control
var _system_view
var _back_button: Button
var _open_button: Button
var _details: RichTextLabel
var _status: Label
var _observer_panel: PanelContainer
var _observer_button: Button
var _ship_choice: OptionButton
var _ship_destination: LineEdit
var _cargo_commodity: LineEdit
var _cargo_quantity: SpinBox

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
    _back_button = Button.new()
    _back_button.text = "← К сектору"
    _back_button.visible = false
    _back_button.pressed.connect(_return_to_sector)
    heading.add_child(_back_button)
    var reset := Button.new()
    reset.text = "Центрировать карту"
    reset.pressed.connect(_reset_map)
    heading.add_child(reset)

    _status = Label.new()
    _status.text = "Загрузка замороженных JSON Galaxy 0.6.7..."
    # This line changes every tick and sometimes gains extra production
    # details. A normal Label would resize its minimum width and push the
    # entire map+inspector out of the window while the simulation runs.
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.clip_text = true
    _status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _status.custom_minimum_size = Vector2.ZERO
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
    _open_button = Button.new()
    _open_button.text = "Открыть систему"
    _open_button.pressed.connect(_open_selected_system)
    toolbar.add_child(_open_button)

    # Explicit N14 command surface: the one N158 runner validates the native
    # directed route and commits the ship state to its canonical N39 World.
    # No demo fleet, no separate clock, and no local cargo/credit mutation.
    var ship_orders := HBoxContainer.new()
    ship_orders.add_theme_constant_override("separation", 8)
    root.add_child(ship_orders)
    ship_orders.visible = ENABLE_DEBUG_MANUAL_FLEET_UI
    var ship_caption := Label.new()
    ship_caption.text = "Корабль / рейс N14:"
    ship_orders.add_child(ship_caption)
    _ship_choice = OptionButton.new()
    # The selected ship's location/name changes at runtime. Never let the
    # longest dropdown item resize this row (or the main map) each tick.
    _ship_choice.custom_minimum_size = Vector2(250, 0)
    _ship_choice.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
    _ship_choice.fit_to_longest_item = false
    _ship_choice.clip_text = true
    ship_orders.add_child(_ship_choice)
    _ship_destination = LineEdit.new()
    _ship_destination.placeholder_text = "ID назначения (например alpha-station)"
    _ship_destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ship_orders.add_child(_ship_destination)
    var depart_button := Button.new()
    depart_button.text = "Отправить"
    depart_button.pressed.connect(_depart_selected_ship)
    ship_orders.add_child(depart_button)

    # N21/N15 explicit physical logistics. This is NOT a paid trade or
    # second warehouse: all buttons call the same N158 single-World Apply.
    var logistics := HBoxContainer.new()
    logistics.add_theme_constant_override("separation", 8)
    root.add_child(logistics)
    logistics.visible = ENABLE_DEBUG_MANUAL_FLEET_UI
    var cargo_caption := Label.new()
    cargo_caption.text = "Док / свой груз N21·N15:"
    logistics.add_child(cargo_caption)
    for spec in [{"text": "Стыковка", "action": "dock"},
            {"text": "Отстыковать", "action": "undock"}]:
        var button := Button.new()
        button.text = str(spec["text"])
        button.pressed.connect(_ship_logistics.bind(str(spec["action"])))
        logistics.add_child(button)
    _cargo_commodity = LineEdit.new()
    _cargo_commodity.placeholder_text = "Товар (например ore)"
    _cargo_commodity.custom_minimum_size = Vector2(170, 0)
    _cargo_commodity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    logistics.add_child(_cargo_commodity)
    _cargo_quantity = SpinBox.new()
    _cargo_quantity.min_value = 1
    _cargo_quantity.max_value = 1000
    _cargo_quantity.step = 1
    _cargo_quantity.rounded = true
    _cargo_quantity.value = 1
    logistics.add_child(_cargo_quantity)
    for spec in [{"text": "Загрузить", "action": "load"},
            {"text": "Выгрузить", "action": "unload"}]:
        var button := Button.new()
        button.text = str(spec["text"])
        button.pressed.connect(_ship_logistics.bind(str(spec["action"])))
        logistics.add_child(button)

    # The player observes the world instead of assigning individual ship orders.
    # Autonomous ship decision execution is not wired yet; do not pretend it is.
    var autonomy_hint := Label.new()
    autonomy_hint.text = "НАБЛЮДЕНИЕ: экономика работает сама; автономные приказы флоту и главам фракций ещё интегрируются"
    autonomy_hint.clip_text = true
    autonomy_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    autonomy_hint.tooltip_text = "Ручные команды кораблями сохранены в коде, но скрыты. N153/N135/N100 ещё должны выдавать реальные решения через один мировой Apply."
    root.add_child(autonomy_hint)

    var columns := HBoxContainer.new()
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_theme_constant_override("separation", 10)
    root.add_child(columns)

    var map_panel := PanelContainer.new()
    map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(map_panel)

    # One container owns two read-only views: sector and its selected system.
    # No second World, clock, or gameplay state is constructed here.
    var map_stage := Control.new()
    map_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
    map_stage.custom_minimum_size = Vector2(420, 420)
    map_panel.add_child(map_stage)
    _map = SystemMap.new()
    map_stage.add_child(_map)
    _map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _system_view = StarSystemView.new()
    _system_view.visible = false
    map_stage.add_child(_system_view)
    _system_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _system_view.connect("body_selected", _on_body_selected)
    _system_view.connect("body_open_requested", _on_body_open_requested)

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
    footer.text = "P2 · карта сектора → система → планета · экономика и автономный флот N84/N153 в интеграции; состояние в Наблюдении"
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
    # The default OptionButton index is not the clock's authoritative speed.
    # Synchronize it even on a fresh seed boot (without a saved checkpoint).
    _sync_speed_control()
    _model = _runner.world
    _populate_ship_choices()
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
    _map.connect("system_open_requested", _open_world)
    var initial: Dictionary = _model.system_by_id("system-sol")
    if initial.is_empty() and not worlds.is_empty():
        initial = worlds[0]
    if not initial.is_empty():
        _select_world(initial)
    else:
        _selected_system = ""
        _details.text = "В сохранённом мире нет доступных звёздных систем"
    print("GODOT_P2_PAID_PRODUCTION_BOOT ", JSON.stringify(_runner.production_stats()))
    _update_status()
    # Opt-in end-to-end check executes the actual GUI scene and authoritative
    # runtime, unlike source-only parser checks. Never run in normal gameplay.
    if OS.get_cmdline_user_args().has("--p2-boot-check"):
        call_deferred("_run_boot_check")

func _run_boot_check() -> void:
    # One bounded live-world tick and round-trip through the sole SaveState.
    # This mode is for a release checkpoint, not a second simulation.
    if _runner == null or not _runner.is_started():
        push_error("P2_BOOT_CHECK_FAIL: world did not start")
        get_tree().quit(1)
        return
    var before: int = _runner.tick_count
    if not _runner.queue_control("pause") or not _runner.queue_control("step", 2):
        push_error("P2_BOOT_CHECK_FAIL: controls rejected")
        get_tree().quit(1)
        return
    _runner.advance_frame(0.0)
    if _runner.tick_count != before + 2 or not _runtime_failure().is_empty():
        push_error("P2_BOOT_CHECK_FAIL: tick or paid phase failed")
        get_tree().quit(1)
        return
    var check_path: String = "user://saves/p2-boot-check.json"
    if SaveState.save_runner(_runner, check_path) != OK:
        push_error("P2_BOOT_CHECK_FAIL: save rejected")
        get_tree().quit(1)
        return
    var expected_tick: int = _runner.tick_count
    # A successful return code and matching tick do not prove that physical
    # stocks survived JSON serialization. Check the same authoritative N39
    # market supplies before and after restoring the actual GUI checkpoint.
    var before_save: Dictionary = _runner.economy_snapshot()
    var expected_markets: Dictionary = before_save.get("markets", {})
    var restored: Dictionary = SaveState.load_runner(_runner, _seed, check_path)
    if not bool(restored.get("ok", false)) or _runner.tick_count != expected_tick:
        push_error("P2_BOOT_CHECK_FAIL: restore rejected")
        get_tree().quit(1)
        return
    var after_load: Dictionary = _runner.economy_snapshot()
    var actual_markets: Dictionary = after_load.get("markets", {})
    if expected_markets.size() != actual_markets.size():
        push_error("P2_BOOT_CHECK_FAIL: market count changed on restore")
        get_tree().quit(1)
        return
    for market_id in expected_markets:
        if not actual_markets.has(market_id):
            push_error("P2_BOOT_CHECK_FAIL: missing restored market " + str(market_id))
            get_tree().quit(1)
            return
        var expected_supply: Variant = expected_markets[market_id].get("supply", {})
        var actual_supply: Variant = actual_markets[market_id].get("supply", {})
        if expected_supply != actual_supply:
            push_error("P2_BOOT_CHECK_FAIL: physical stock changed at " + str(market_id)
                + " expected=" + JSON.stringify(expected_supply)
                + " actual=" + JSON.stringify(actual_supply))
            get_tree().quit(1)
            return
    # Exercise the same public navigation callbacks as the real game without
    # altering simulation state or requiring a second fake demo scene.
    var sol_view: Dictionary = _model.system_by_id("system-sol")
    if sol_view.is_empty():
        push_error("P2_BOOT_CHECK_FAIL: no Sol for in-system view")
        get_tree().quit(1)
        return
    _open_world(sol_view)
    if not _in_system or not _system_view.visible or _map.visible:
        push_error("P2_BOOT_CHECK_FAIL: could not enter live star system")
        get_tree().quit(1)
        return
    _on_body_selected({"id": "earth"})
    if _selected_body_id != "earth" or not _details.text.contains("Earth"):
        push_error("P2_BOOT_CHECK_FAIL: selected planet inspector is missing")
        get_tree().quit(1)
        return
    _return_to_sector()
    if _in_system or _system_view.visible or not _map.visible:
        push_error("P2_BOOT_CHECK_FAIL: could not return to sector")
        get_tree().quit(1)
        return
    print("P2_BOOT_CHECK_PASS tick=", expected_tick,
        " facilities=", _runner.economy_summary().get("facilities", 0))
    get_tree().quit(0)

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
            _checkpoint_recovery_suffix(result)
        ]
        _sync_speed_control()
    else:
        # Preserve the initialized seed world; the user may still load manually.
        _notice = "Автозагрузка P2 не удалась: " + str(result.get("error", "неизвестная ошибка"))
        _check_restore_rollback(result)


# Recovery status comes from the sole SaveState authority, never from a second
# filesystem probe. A pending checkpoint may be valid but not yet durable.
func _checkpoint_recovery_suffix(result: Dictionary) -> String:
    if bool(result.get("recovered_pending", false)):
        return " (аварийное сохранение восстановлено)" if bool(result.get("promoted_pending", false)) else " (аварийное сохранение загружено, НЕ закреплено на диске — сохраните игру)"
    if str(result.get("source", "")).ends_with(".bak"):
        return " (резервная копия)"
    return ""


func _populate_ship_choices() -> void:
    if not ENABLE_DEBUG_MANUAL_FLEET_UI or _ship_choice == null or _runner == null:
        return
    var previous: String = ""
    if _ship_choice.selected >= 0:
        previous = str(_ship_choice.get_item_metadata(_ship_choice.selected))
    _ship_choice.clear()
    var ships: Dictionary = _runner.fleet_snapshot()
    var ids: Array = ships.keys()
    ids.sort()
    var restored_index: int = -1
    for id in ids:
        var ship: Dictionary = ships[id]
        var label_text: String = "%s · %s · %s" % [
            str(ship.get("name", id)), str(ship.get("class", "?")),
            str(ship.get("location", "в полёте"))]
        if not str(ship.get("docked_at", "")).is_empty():
            label_text += " · пристыкован"
        var index: int = _ship_choice.item_count
        _ship_choice.add_item(label_text)
        _ship_choice.set_item_metadata(index, str(id))
        if str(id) == previous:
            restored_index = index
    if _ship_choice.item_count > 0:
        _ship_choice.select(restored_index if restored_index >= 0 else 0)


func _depart_selected_ship() -> void:
    if not ENABLE_DEBUG_MANUAL_FLEET_UI:
        return
    if _runner == null or not _fatal_restore_error.is_empty() or not _runtime_failure().is_empty():
        return
    if _ship_choice == null or _ship_choice.selected < 0:
        _notice = "Нет кораблей в текущем сохранении"
        _update_status()
        return
    var ship_id: String = str(_ship_choice.get_item_metadata(_ship_choice.selected))
    var destination: String = _ship_destination.text.strip_edges()
    if destination.is_empty():
        _notice = "Укажите точный ID назначения из локальных маршрутов"
        _update_status()
        return
    var outcome: Dictionary = _runner.request_ship_departure(ship_id, destination)
    if outcome.get("ok", false):
        _notice = "N14: %s отправлен к %s" % [ship_id, destination]
        _populate_ship_choices()
        _refresh_observer()
        _refresh_selection()
    else:
        _notice = "Рейс отклонён: " + str(outcome.get("reason", "unknown"))
    _update_status()


func _ship_logistics(action: String) -> void:
    if not ENABLE_DEBUG_MANUAL_FLEET_UI:
        return
    if _runner == null or not _fatal_restore_error.is_empty() or not _runtime_failure().is_empty():
        return
    if _ship_choice == null or _ship_choice.selected < 0:
        _notice = "Нет доступного корабля"
        _update_status()
        return
    var ship_id: String = str(_ship_choice.get_item_metadata(_ship_choice.selected))
    # The receipt sequence is saved in the ONE N39 world, so a restored
    # game never silently replays an earlier UI command.
    var snapshot: Dictionary = _runner.economy_snapshot()
    var used: int = snapshot.get("dock_receipts", {}).size() + snapshot.get("cargo_receipts", {}).size()
    var operation_id: String = "ui:%s:%s:%d" % [action, ship_id, used + 1]
    var result: Dictionary = {}
    if action == "dock":
        result = _runner.request_ship_dock(ship_id, operation_id)
    elif action == "undock":
        result = _runner.request_ship_undock(ship_id, operation_id)
    else:
        var commodity: String = _cargo_commodity.text.strip_edges().to_lower()
        if commodity.is_empty():
            _notice = "Укажи товар (например ore)"
            _update_status()
            return
        result = _runner.request_ship_cargo(ship_id, operation_id, action,
            {commodity: int(_cargo_quantity.value)})
    if result.get("ok", false):
        _notice = "N21/N15: %s — %s (тик %d)" % [ship_id, action, _runner.tick_count]
        _populate_ship_choices()
        _refresh_observer()
        _refresh_selection()
    else:
        _notice = "Операция отклонена: " + str(result.get("reason", "unknown"))
    _update_status()


func _toggle_observer() -> void:
    _observer_panel.visible = not _observer_panel.visible
    _observer_button.text = "Скрыть наблюдение" if _observer_panel.visible else "Наблюдение"
    _refresh_observer()

func _refresh_observer() -> void:
    if not _observer_panel or not _observer_panel.visible or not _runner:
        return
    # A read-only checkpoint projection lets the Observer distinguish a
    # planned route from durable N15/N97 cargo and N9/N104 receipts. It
    # never owns, mutates, or reconstructs a second World/Ledger/Board.
    var checkpoint: Dictionary = _runner.checkpoint()
    var native_production: Dictionary = checkpoint.get("native_production", {})
    _observer_panel.call("show_live_economy", _runner.tick_count,
        _runner.economy_snapshot(), _runner.economy_summary(),
        _runner.fleet_snapshot(), native_production)

func _process(delta: float) -> void:
    if _runner and _fatal_restore_error.is_empty():
        _runner.advance_frame(delta)

func _toggle_pause() -> void:
    if not _runner or not _fatal_restore_error.is_empty():
        return
    if _runner.clock.paused and not _runtime_failure().is_empty():
        _notice = "Симуляция остановлена из-за ошибки фазы; загрузите последнее корректное сохранение"
        _update_status()
        return
    _runner.queue_control("resume" if _runner.clock.paused else "pause")
    _runner.advance_frame(0.0)
    _update_status()

func _step(count: int) -> void:
    if not _runner or not _fatal_restore_error.is_empty():
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
    if not _runner or not _fatal_restore_error.is_empty() or index < 0 or index >= SPEEDS.size():
        return
    _runner.queue_control("speed", float(SPEEDS[index]))
    _runner.advance_frame(0.0)
    _update_status()

func _save_game(save_path: String = "") -> void:
    if not _runner or not _fatal_restore_error.is_empty():
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
        _fatal_restore_error = ""
        _startup_error = ""
        _model = _runner.world
        # A loaded checkpoint replaces the authoritative world and clock. Refresh
        # all read-only projections; never keep a stale seed-era map or speed UI.
        var restored_worlds: Array = _model.worlds()
        _map.call("set_worlds", restored_worlds)
        var selected: Dictionary = _model.system_by_id(_selected_system)
        if selected.is_empty() and not restored_worlds.is_empty():
            selected = restored_worlds[0]
            _selected_system = str((selected.get("system", {}) as Dictionary).get("id", ""))
        if not selected.is_empty():
            _map.call("select_system", _selected_system)
        _sync_speed_control()
        _populate_ship_choices()
        _refresh_observer()
        _notice = "Загружено сохранение: орбиты и производство P2, тик " + str(result.get("tick", "—")) + _checkpoint_recovery_suffix(result)
        if not selected.is_empty():
            _select_world(selected)
        else:
            _details.text = "В загруженном мире нет доступных звёздных систем"
        _refresh_selection()
    else:
        _notice = str(result.get("error", "Не удалось загрузить"))
        _check_restore_rollback(result)
    _update_status()

# A failed restore that cannot roll back has left the single authoritative
# world in an unknown state. No ticks, saves, or controls until a good load.
func _check_restore_rollback(result: Dictionary) -> void:
    var reason: String = str(result.get("error", ""))
    if reason.contains("rollback failed"):
        _fatal_restore_error = reason
        _startup_error = reason
        _runner.queue_control("pause")
        _runner.advance_frame(0.0)
        push_error("P2 checkpoint rollback failed: " + reason)

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
    _populate_ship_choices()
    _refresh_observer()
    # Orbit positions are read from the SAME live World after each real tick.
    if _in_system and _system_view != null and _model != null:
        var live_system: Dictionary = _model.system_by_id(_selected_system)
        if not live_system.is_empty():
            _system_view.update_world(live_system)
            _system_view.call("set_live_fleet", _runner.fleet_snapshot())
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
    if not _fatal_restore_error.is_empty():
        _status.text += "   |   КРИТИЧЕСКАЯ ОШИБКА ЗАГРУЗКИ: " + _fatal_restore_error
    if not failure.is_empty():
        _status.text += "   |   ОШИБКА ФАЗЫ %s / тик %d: %s" % [
            str(failure.get("phase", "?")), int(failure.get("tick", -1)),
            str(failure.get("reason", "unknown"))]
    _pause_button.text = "Ошибка — загрузите" if not failure.is_empty() or not _fatal_restore_error.is_empty() else ("Продолжить" if _runner.clock.paused else "Пауза")
    # Preserve the complete diagnostics on hover, even when the visible
    # status bar is clipped in the embedded Godot game panel.
    _status.tooltip_text = _status.text

func _refresh_selection() -> void:
    if not _runner:
        return
    var selected: Dictionary = _model.system_by_id(_selected_system)
    if not selected.is_empty():
        if _in_system:
            _system_view.update_world(selected)
            _system_view.call("set_live_fleet", _runner.fleet_snapshot())
            _show_body_details(selected)
        else:
            _select_world(selected)

func _reset_map() -> void:
    if _in_system and _system_view:
        _system_view.reset_view()
    elif _map:
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
    if _in_system:
        _system_view.update_world(world)
        _system_view.call("set_live_fleet", _runner.fleet_snapshot())
        _show_body_details(world)
        return
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
    # Read only the authoritative N39/N151 population snapshot, not frozen
    # seed population counts. All purchases are committed by the one ledger.
    if _runner != null and _runner.has_method("economy_snapshot"):
        var live_economy: Dictionary = _runner.economy_snapshot()
        var live_populations: Dictionary = live_economy.get("populations", {})
        var local_locations: Dictionary = {}
        for source_market in markets:
            local_locations[str(source_market.get("facility_id", ""))] = true
        var population_ids: Array = live_populations.keys()
        population_ids.sort()
        var local_population_count: int = 0
        for pid in population_ids:
            var population: Dictionary = live_populations[pid]
            if not local_locations.has(str(population.get("location", ""))):
                continue
            if local_population_count == 0:
                lines.append("")
                lines.append("ЖИВОЕ НАСЕЛЕНИЕ (ЕДИНЫЙ N39 WORLD)")
            local_population_count += 1
            lines.append(" • %s: %d жителей · %d CR · еда %d/100 · настроение %d/100" % [
                str(population.get("label", pid)), int(population.get("count", 0)),
                int(population.get("wealth", 0)),
                int(population.get("food_satisfaction", 0)),
                int(population.get("overall_sentiment", 0))
            ])
        if _runner.has_method("last_population_result"):
            var population_result: Dictionary = _runner.last_population_result()
            if population_result.get("ok", false) and local_population_count > 0:
                lines.append(" Последняя общая оплаченная фаза населения: тик %d · покупок %d" % [
                    int(population_result.get("tick", -1)),
                    int(population_result.get("purchases", 0))
                ])
    lines.append("")
    lines.append("Орбиты, производство, покупки населения и рынок работают в одном тике.")
    lines.append("Флот N46/N14 подключён, но автономный ИИ и контракты ещё не работают.")
    _details.text = "\n".join(lines)

func _open_selected_system() -> void:
    if _model == null:
        return
    var world: Dictionary = _model.system_by_id(_selected_system)
    if not world.is_empty():
        _open_world(world)


func _open_world(world: Dictionary) -> void:
    if _model == null or _system_view == null:
        return
    var sid: String = str(world.get("system", {}).get("id", ""))
    var current: Dictionary = _model.system_by_id(sid)
    if current.is_empty():
        return
    _selected_system = sid
    _selected_body_id = ""
    _in_system = true
    _map.visible = false
    _system_view.visible = true
    _system_view.set_world(current)
    _system_view.call("set_live_fleet", _runner.fleet_snapshot())
    _map.call("select_system", sid)
    _back_button.visible = true
    _back_button.text = "← К сектору"
    _open_button.visible = false
    _show_body_details(current)


func _return_to_sector() -> void:
    # Three semantic map levels: globe -> orbital system -> sector.
    # Do not reset or duplicate the running world on a UI-only transition.
    if _in_system and _system_view != null and _system_view.is_body_focused():
        _system_view.unfocus_body()
        _back_button.text = "← К сектору"
        return
    _in_system = false
    _system_view.visible = false
    _map.visible = true
    _back_button.visible = false
    _back_button.text = "← К сектору"
    _open_button.visible = true
    _selected_body_id = ""
    _refresh_selection()


func _on_body_selected(body: Dictionary) -> void:
    if not _in_system or _model == null:
        return
    _selected_body_id = str(body.get("id", ""))
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        _show_body_details(current)


func _on_body_open_requested(body: Dictionary) -> void:
    if not _in_system or _model == null or _system_view == null:
        return
    var id: String = str(body.get("id", ""))
    if id.is_empty() or not _system_view.focus_body(id):
        return
    _selected_body_id = id
    _back_button.text = "← К системе"
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        _show_body_details(current)


func _show_body_details(world: Dictionary) -> void:
    var system: Dictionary = world.get("system", {})
    var bodies: Array = world.get("bodies", [])
    var lines: Array[String] = []
    lines.append("СИСТЕМА: " + str(system.get("name", "?")))
    lines.append("Звезда: " + str(system.get("star_type", "?")))
    lines.append("Тел: %d · станций/предприятий: %d" % [
        bodies.size(), (world.get("facilities", []) as Array).size()])
    lines.append("")
    var chosen: Dictionary = {}
    for body in bodies:
        if str(body.get("id", "")) == _selected_body_id:
            chosen = body
            break
    if chosen.is_empty():
        _selected_body_id = ""
        _system_view.select_body("")
        lines.append("Выбери небесное тело на карте.")
        lines.append("Положение объектов и текущие углы орбит взяты из живой модели.")
        lines.append("Радиусы отображения сжаты для удобства и не являются световыми годами.")
        lines.append("")
        lines.append("НЕБЕСНЫЕ ТЕЛА")
        for body in bodies:
            lines.append(" • %s [%s] · %s" % [
                str(body.get("name", "?")), str(body.get("type", "?")),
                str(body.get("biome", "?"))])
        lines.append("")
        lines.append("Кораблей в исходной системе: %d (движение ещё не подключено)" %
            (world.get("ships", []) as Array).size())
        _details.text = "\n".join(lines)
        return

    lines.append("НЕБЕСНОЕ ТЕЛО")
    lines.append(str(chosen.get("name", _selected_body_id)))
    lines.append("Тип: " + str(chosen.get("type", "?")) + " · Биом: " +
        str(chosen.get("biome", "?")))
    lines.append("ID: " + _selected_body_id)
    if _system_view != null and _system_view.is_body_focused():
        lines.append("Крупный глобус — схематическая поверхность, не реальные координаты построек.")
    else:
        lines.append("Двойной клик по телу или приближение к нему открывает крупный глобус.")
    lines.append("Радиус орбиты: %.2f (условные единицы)" %
        float(chosen.get("orbit_radius", 0.0)))
    lines.append("Период: %.1f (нативные единицы)" %
        float(chosen.get("orbit_period", 0.0)))
    lines.append("Текущий угол: %.2f°" %
        float(chosen.get("current_angle", 0.0)))
    lines.append("")
    lines.append("ИСХОДНЫЕ РЕСУРСЫ")
    var resources: Dictionary = chosen.get("resources", {})
    if resources.is_empty():
        lines.append(" • Не указаны")
    else:
        var names: Array = resources.keys()
        names.sort()
        for commodity in names:
            lines.append(" • %s: %s" % [str(commodity), str(resources[commodity])])

    lines.append("")
    lines.append("СТАНЦИИ И ПРЕДПРИЯТИЯ НА ТЕЛЕ")
    var economic: Dictionary = _runner.economy_snapshot() if _runner != null else {}
    var live_facilities: Dictionary = economic.get("facilities", {})
    var locations: Dictionary = {}
    var count: int = 0
    for facility in world.get("facilities", []):
        if str(facility.get("body", "")) != _selected_body_id:
            continue
        count += 1
        var fid: String = str(facility.get("id", ""))
        var location: String = str(facility.get("location", ""))
        locations[location] = true
        lines.append(" • %s [%s]" % [
            str(facility.get("name", fid)), str(facility.get("type", "?"))])
        if live_facilities.has(fid):
            var live: Dictionary = live_facilities[fid]
            var shift: Dictionary = live.get("work_shift", {})
            lines.append("   Фракция: %s · %d CR" % [
                str(facility.get("faction_id", "?")), int(live.get("credits", 0))])
            if not shift.is_empty():
                lines.append("   Последняя оплаченная смена: тик %d · зарплата %d CR" % [
                    int(shift.get("tick", 0)), int(shift.get("wages", 0))])
        else:
            lines.append("   Исходный объект, живой счёт пока не подключён")
    if count == 0:
        lines.append(" • Нет привязанных объектов")

    lines.append("")
    lines.append("ЖИВАЯ ЭКОНОМИКА / НАСЕЛЕНИЕ")
    var printed: bool = false
    var markets: Dictionary = economic.get("markets", {})
    for location in locations:
        if not markets.has(location):
            continue
        printed = true
        var market: Dictionary = markets[location]
        lines.append(" • Рынок: " + str(location))
        var stock: Dictionary = market.get("supply", {})
        var stock_names: Array = stock.keys()
        stock_names.sort()
        for commodity in stock_names:
            if float(stock[commodity]) > 0.0:
                lines.append("   %s: %.1f ед. · цена %.2f CR" % [
                    str(commodity), float(stock[commodity]),
                    float(market.get("prices", {}).get(commodity, 0.0))])
    var population: Dictionary = economic.get("populations", {})
    for pid in population:
        var pop: Dictionary = population[pid]
        if not locations.has(str(pop.get("location", ""))):
            continue
        printed = true
        lines.append(" • Население %s: %d · средства %d CR" % [
            str(pop.get("label", pid)), int(pop.get("count", 0)),
            int(pop.get("wealth", 0))])
        lines.append("   Еда %d/100 · настроение %d/100" % [
            int(pop.get("food_satisfaction", 0)),
            int(pop.get("overall_sentiment", 0))])
    if not printed:
        lines.append(" • Для этого тела пока нет активного рынка/населения")
    lines.append("")
    lines.append("КОРАБЛИ В ЛОКАЦИЯХ ЭТОГО ТЕЛА")
    var ships_by_class: Dictionary = {}
    var active_fleet: Dictionary = _runner.fleet_snapshot()
    for ship_id in active_fleet:
        var ship: Dictionary = active_fleet[ship_id]
        if not locations.has(str(ship.get("location", ""))):
            continue
        var ship_class: String = str(ship.get("class", "other"))
        ships_by_class[ship_class] = int(ships_by_class.get(ship_class, 0)) + 1
    if ships_by_class.is_empty():
        lines.append(" • Нет находящихся здесь кораблей")
    else:
        var ship_types: Array = ships_by_class.keys()
        ship_types.sort()
        for ship_type in ship_types:
            lines.append(" • %s: %d" % [str(ship_type), int(ships_by_class[ship_type])])
    lines.append("Полёты по реальным N14 маршрутам: статус в панели Наблюдение.")
    lines.append("Автономный корабельный ИИ ещё не подключён.")
    _details.text = "\n".join(lines)


## Read-only boot diagnostics for local Windows/Godot compatibility smoke.
## No gameplay mutation and no false claim that P2/P3 phases execute.
func startup_health() -> Dictionary:
    var booted: bool = _runner != null and _runner.is_started()
    var has_map: bool = _map != null and is_instance_valid(_map)
    var has_ui: bool = _status != null and _details != null and _pause_button != null
    var seed_ok: bool = booted and _model != null and _model.seed_stats().get("systems", 0) == 8
    return {
        "ok": booted and has_map and has_ui and seed_ok and _startup_error.is_empty() and _fatal_restore_error.is_empty(),
        "error": _startup_error,
        "godot_version": Engine.get_version_info().get("string", "unknown"),
        "booted": booted,
        "seed_ok": seed_ok,
        "map_ready": has_map,
        "ui_ready": has_ui,
        "tick": _runner.tick_count if booted else -1,
        "runtime_failure": _runtime_failure(),
        "fatal_restore_error": _fatal_restore_error,
        "implemented_phases": _runner.implemented_phases() if booted else PackedStringArray()
    }
