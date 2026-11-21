extends Control
## Sol-only read-only visual slice. This does NOT advance authoritative N158/N39.
const SolProfile = preload("res://scripts/sol_profile.gd")
const SolStarter = preload("res://scripts/sol_start_scenario.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const EarthDistrict = preload("res://scripts/view/sol_earth_district.gd")
var district: Control

const SurfaceSites = preload("res://scripts/view/sol_surface_sites.gd")
const NativeStarSystemView = preload("res://scripts/star_system_view.gd")
const BuildingBrowser = preload("res://scripts/building_browser.gd")
const UIFrameProfiler = preload("res://scripts/ui_frame_profiler.gd")
const NativeClock = preload("res://scripts/sim/clock.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const ConstructionRuntime = preload("res://scripts/sol_construction_runtime.gd")
const ColonyStockPanel = preload("res://scripts/view/colony_stock_panel.gd")
const ColonyPanel = preload("res://scripts/view/colony_panel.gd")
const SPEED_PRESETS: Array[int] = [1, 4, 8, 16]
const DEFAULTS = "res://data/balance_defaults.json"
const USER_CONFIG = "user://sol_lab_balance.json"
const USER_SAVE = "user://sol_lab_construction_save_v1.json"
const SIDE_WIDTH = 340.0
var world: Dictionary = {}
var config: Dictionary = {}
var native_time: float = 0.0
var visual_tick_count: int = 0
var visual_clock = NativeClock.new()
var colony_button: Button
var freight_button: Button
var manual_freight_dialog: AcceptDialog
var manual_ship: OptionButton
var expedition_dialog: AcceptDialog
var expedition_summary: Label
var expedition_food: SpinBox
var expedition_target := ""
var yard_controls: VBoxContainer
var yard_status: Label
var yard_order: Button
var yard_colonizer: Button
var colonizer_order_dialog: ConfirmationDialog
var pending_yard := ""
var yard_cancel: Button
var manual_destination: OptionButton
var manual_resource: OptionButton
var manual_empty: CheckButton
var manual_amount: SpinBox
var manual_preview: Label
var freight_line_buttons: HBoxContainer
var freight_line_toggle: Button
var freight_line_dialog: AcceptDialog
var freight_line_fields: Dictionary = {}
var construction = ConstructionRuntime.new()
var construction_ui_elapsed: float = 0.0
var message_line: Label
var _calendar_display_day: int = -1
var _map_view_last_usec: int = 0
var _map_view_peak_usec: int = 0
var _dock_refresh_last_usec: int = 0
var _dock_refresh_peak_usec: int = 0
var paused: bool = false
var speed: int = 1
var speed_buttons: Dictionary = {}
var frame_profiler = UIFrameProfiler.new()
var perf_label: Label
var previous_process_started_usec: int = -1
var selected: String = "earth"
var details: Label
var planet_name_label: Label
var colony_stock_panel: PanelContainer
var info_area: VBoxContainer
var mode_button: Button
var pause_button: Button
var time_label: Label
var browser
var native_view
var sidebar: PanelContainer
var colony_panel
var diagnostics_visible: bool = false
var top_bar: HBoxContainer
var performance_bar: HBoxContainer

func _ready() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sol.json"))
    if not (parsed is Dictionary):
        push_error("Отсутствует исходный Sol")
        return
    world = SolStarter.apply(parsed)
    if not SolProfile.apply_world(world):
        push_error("Отклонены исходные параметры спутников")
        return
    visual_clock.set_speed(float(speed))
    config = _load_config()
    _init_extra_settings()
    construction.planets = config["planets"]
    construction.setup(world, config["buildings"])
    _build_ui()
    _make_native_map()
    _make_browser()
    _dock_colony_stock()
    resized.connect(_layout_right_side)
    _layout_right_side()
    _show_selected()
    _update_calendar_label()
    queue_redraw()

func _build_ui() -> void:
    var bar := HBoxContainer.new()
    top_bar = bar
    add_child(bar)
    bar.anchor_right = 1.0
    bar.offset_right = -SIDE_WIDTH
    bar.offset_bottom = 46
    var title := Label.new()
    title.text = "  LIVING SECTOR  /  SOL LAB  "
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(title)
    time_label = Label.new()
    time_label.custom_minimum_size = Vector2(108, 0)
    time_label.add_theme_font_size_override("font_size", 16)
    bar.add_child(time_label)
    pause_button = _button(bar, "Пауза", _pause)
    _button(bar, "+1", _step)
    var speeds := HBoxContainer.new()
    speeds.add_theme_constant_override("separation", 3)
    bar.add_child(speeds)
    for preset in SPEED_PRESETS:
        var speed_button := _button(speeds, "×%d" % preset,
            _set_speed.bind(preset))
        speed_button.toggle_mode = true
        speed_button.button_pressed = preset == speed
        speed_button.custom_minimum_size = Vector2(43, 30)
        speed_button.tooltip_text = ("Скорость игрового календаря ×%d; " +
            "строительство и орбиты используют одни часы. " +
            "Экономика N39 пока не подключена.") % preset
        speed_buttons[preset] = speed_button
    var game_menu := MenuButton.new()
    game_menu.text = "Игра"
    game_menu.custom_minimum_size = Vector2(70, 32)
    bar.add_child(game_menu)
    var popup: PopupMenu = game_menu.get_popup()
    popup.add_item("Новая игра", 1)
    popup.add_item("Сохранить", 2)
    popup.add_item("Загрузить", 3)
    popup.add_separator()
    popup.add_item("Диагностика", 4)
    popup.add_item("Админ-панель · F9", 5)
    popup.id_pressed.connect(_on_game_menu)
    _button(bar, "Камера", _reset_camera)
    performance_bar = HBoxContainer.new()
    add_child(performance_bar)
    performance_bar.anchor_right = 1.0
    performance_bar.offset_top = 46
    performance_bar.offset_bottom = 78
    performance_bar.offset_right = -SIDE_WIDTH
    perf_label = Label.new()
    perf_label.text = "FPS — · кадр p95 — · CPU p95 — · UI p95 — · карта — · SIM —"
    perf_label.add_theme_font_size_override("font_size", 14)
    perf_label.add_theme_color_override("font_color", Color("#8fc6d9"))
    perf_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    perf_label.clip_text = true
    perf_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    performance_bar.add_child(perf_label)
    performance_bar.hide()

    colony_panel = ColonyPanel.new()
    sidebar = colony_panel
    add_child(sidebar)
    sidebar.anchor_left = 1.0
    sidebar.anchor_right = 1.0
    sidebar.anchor_bottom = 1.0
    sidebar.offset_left = -SIDE_WIDTH
    sidebar.offset_right = 0.0
    sidebar.offset_top = 46
    planet_name_label = colony_panel.heading
    colony_stock_panel = colony_panel.stock_panel
    details = colony_panel.details
    message_line = colony_panel.message
    colony_button = colony_panel.colonize_button
    colony_button.pressed.connect(_open_expedition)
    _build_expedition_dialog()
    freight_button = colony_panel.freight_button
    freight_button.hide()
    colony_panel.build_requested.connect(_open_build)
    colony_panel.ship_requested.connect(func(slot: int):
        if slot == 1 and construction.freight_line().enabled:
            _open_freight_line()
        else:
            _open_manual_freight(slot))
    colony_panel.line_requested.connect(_open_colony_logistics)
    colony_panel.facility_requested.connect(_colony_facility_selected)
    yard_controls = VBoxContainer.new()
    colony_panel.overview.add_child(yard_controls)
    colony_panel.overview.move_child(yard_controls, colony_panel.built_list.get_index())
    yard_status = Label.new()
    yard_controls.add_child(yard_status)
    yard_order = _button(yard_controls, "Заказать грузовик 2", _order_second_ship)
    yard_colonizer = _button(yard_controls, "Колонизатор · 80 металла · 60 дн. · Земля", _order_colonizer)
    yard_cancel = _button(yard_controls, "Отменить заказ", _cancel_second_ship)
    yard_controls.hide()
    colonizer_order_dialog = ConfirmationDialog.new()
    colonizer_order_dialog.title = "Заказ на земной верфи"
    colonizer_order_dialog.dialog_text = "Колонизатор: %d металла · %d игровых дней.\nГотовый корабль появится у Земли." % [
        ConstructionRuntime.SHIP_METALS, ConstructionRuntime.COLONIZER_DAYS]
    colonizer_order_dialog.confirmed.connect(func():
        if construction.order_ship(pending_yard, "colonizer"):
            _show_selected()
            _notice("Колонизатор заложен на Земле"))
    add_child(colonizer_order_dialog)
    _build_freight_line_controls(colony_panel.line_holder)


func _on_game_menu(id: int) -> void:
    match id:
        1: _new_game()
        2: _save_game()
        3: _load_game()
        4:
            diagnostics_visible = not diagnostics_visible
            performance_bar.visible = diagnostics_visible
            _layout_right_side()
        5: _toggle_admin()


func _button(parent: Node, label: String, action: Callable) -> Button:
    var b := Button.new()
    b.text = label
    parent.add_child(b)
    b.pressed.connect(action)
    return b

func _load_config() -> Dictionary:
    var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS))
    if not (defaults is Dictionary):
        return {}
    var output: Dictionary = defaults
    if not FileAccess.file_exists(USER_CONFIG):
        return output
    var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_CONFIG))
    if not (saved is Dictionary):
        return output
    for group in output.keys():
        if not (saved.get(group, null) is Dictionary):
            continue
        var section: Dictionary = output[group]
        for key in section.keys():
            var value: Variant = saved[group].get(key, null)
            if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0:
                section[key] = int(value)
        output[group] = section
    return output

func _save_config() -> bool:
    var file := FileAccess.open(USER_CONFIG, FileAccess.WRITE)
    if file == null:
        return false
    config["construction_balance_version"] = 2
    file.store_string(JSON.stringify(config, "  ") + "\n")
    file.close()
    return true

func _apply() -> void:
    # Admin balance updates affect NEW construction orders. Do not reload
    # and destroy the current construction timeline or warehouse state.
    if not _save_config():
        _notice("Не удалось сохранить параметры")
        return
    construction.planets = config["planets"]
    construction.settings = config["buildings"]
    _notice("Баланс сохранён; новые стройки используют новые значения")

func _restore() -> void:
    if FileAccess.file_exists(USER_CONFIG):
        if DirAccess.remove_absolute(ProjectSettings.globalize_path(
                USER_CONFIG)) != OK:
            _notice("Не удалось сбросить баланс")
            return
    config = _load_config()
    _init_extra_settings()
    construction.planets = config["planets"]
    construction.settings = config["buildings"]
    browser.configure(world, config, selected, true)
    browser.set_construction_state(world, construction.sites, native_time)
    _show_selected()
    _notice("Баланс сброшен, текущие стройки сохранены")

func _toggle_admin() -> void:
    if browser.visible and browser.page.begins_with("admin"):
        _close_browser()
    else:
        _open_browser(true)

func _pause() -> void:
    paused = not paused
    visual_clock.set_paused(paused)
    if native_view != null:
        native_view.set_flight_clock_paused(paused)
    pause_button.text = "Продолжить" if paused else "Пауза"

func _step() -> void:
    # Exactly one original 8 TPS clock step, even while paused.
    if not visual_clock.request_steps(1):
        return
    var completed: int = visual_clock.consume_frame(0.0)
    visual_tick_count += completed
    native_time += float(completed) * visual_clock.tick_scale()
    _advance_construction()
    _update_native_map()
    _update_calendar_label()
    _refresh_construction_ui()

func _reset_camera() -> void:
    if district != null and district.visible:
        _close_district()
        return
    if native_view != null:
        native_view.reset_view()

func _process(delta: float) -> void:
    var started_usec: int = Time.get_ticks_usec()
    var frame_delta: float = delta
    if previous_process_started_usec >= 0:
        frame_delta = float(maxi(0,
            started_usec - previous_process_started_usec)) / 1000000.0
    previous_process_started_usec = started_usec
    var ui_started_usec: int = Time.get_ticks_usec()
    if not paused:
        _advance_visual_clock(delta)
    if district != null and district.visible:
        district.set_traffic_time(native_time + visual_clock.render_offset())
    _update_calendar_label()
    construction_ui_elapsed += delta
    if construction_ui_elapsed >= 0.5:
        construction_ui_elapsed = fmod(construction_ui_elapsed, 0.5)
        _refresh_yard()
        if expedition_dialog != null and expedition_dialog.visible:
            _refresh_expedition_preview()
        # No construction rows = nothing to animate. Open/close/order/
        # completion paths still refresh immediately as needed.
        if browser != null and browser.visible and (
                browser.page == "build") and not construction.sites.is_empty():
            _refresh_construction_ui()
    var ui_usec: int = maxi(0, Time.get_ticks_usec() - ui_started_usec)
    var process_usec: int = maxi(0, Time.get_ticks_usec() - started_usec)
    # Zero N158 and zero real sim ticks: this project renders a visual clock
    # only. Never present visual time as production/simulation performance.
    frame_profiler.capture(frame_delta, process_usec, 0, ui_usec, 0)
    if frame_profiler.display_due():
        _update_performance_label()

func _build_expedition_dialog() -> void:
    expedition_dialog = AcceptDialog.new()
    expedition_dialog.ok_button_text = "Отправить колонизатор"
    expedition_dialog.add_cancel_button("Отмена")
    add_child(expedition_dialog)
    var form := VBoxContainer.new()
    form.custom_minimum_size.x = 430
    expedition_dialog.add_child(form)
    expedition_summary = Label.new()
    expedition_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    expedition_summary.custom_minimum_size.x = 430
    form.add_child(expedition_summary)
    var label := Label.new()
    label.text = "Дополнительная еда с земного склада"
    form.add_child(label)
    expedition_food = SpinBox.new()
    expedition_food.step = 1
    form.add_child(expedition_food)
    expedition_food.value_changed.connect(func(_amount: float): _refresh_expedition_preview())
    expedition_dialog.confirmed.connect(func():
        if construction.depart_colonizer(expedition_target, int(expedition_food.value)):
            _update_native_map()
            _show_selected()
            _notice("Колонизатор отправился · " + Model.PLANET_NAMES[expedition_target])
        else:
            _notice("Отправка недоступна · проверьте земной запас еды"))

func _open_expedition() -> void:
    var plan: Dictionary = construction.expedition_preview(selected)
    if plan.is_empty():
        return
    expedition_target = selected
    expedition_dialog.title = "Экспедиция · " + Model.PLANET_NAMES[selected]
    expedition_food.max_value = floorf(plan.earth_food)
    expedition_food.set_value_no_signal(minf(plan.recommended, expedition_food.max_value))
    _refresh_expedition_preview()
    expedition_dialog.popup_centered(Vector2i(484, 340))

func _refresh_expedition_preview() -> void:
    var plan: Dictionary = construction.expedition_preview(expedition_target)
    if plan.is_empty():
        return
    expedition_food.max_value = maxf(0.0, floorf(plan.earth_food))
    var supplies: float = construction.expedition.STARTER_FOOD + expedition_food.value
    var rate: float = construction.expedition.PASSENGERS * ConstructionRuntime.FOOD_PER_RESIDENT
    var cycles := floorf(supplies / rate)
    expedition_summary.text = (
        "Поселенцы: %d · строительный металл: %d · еда: %s
" +
        "Полёт: %.1f дн. · местная шахта: %s руды за цикл
" +
        "Порт: %d дн. · первая доставка примерно через %.1f дн. после посадки
" +
        "Расход: %s еды за 30 дн. · первый дефицит на %.0f-й день после посадки
" +
        "Земной склад: %s → %s еды при отправке") % [
        construction.expedition.PASSENGERS, construction.expedition.METALS,
        Model.batch_amount(supplies), plan.flight_days, Model.batch_amount(plan.ore),
        plan.port_days, plan.resupply_days, Model.batch_amount(rate),
        (cycles + 1) * ConstructionRuntime.CYCLE_DAYS,
        Model.batch_amount(plan.earth_food), Model.batch_amount(plan.earth_food - expedition_food.value)]
    if expedition_food.value < plan.recommended:
        expedition_summary.text += "
До первой доставки возможен голод. Добавьте %d еды." % (
            plan.recommended - int(expedition_food.value))

# Legacy scenario helper. Player orders use the confirmation dialog.
func _colonize_luna() -> void:
    if selected == "luna" and construction.depart_colonizer("luna", 0):
        _update_native_map()
        _show_selected()


func _send_freighter(food: bool = false) -> void:
    if not construction.depart_freighter(selected, food):
        return
    native_view.set_freight(construction.freight_status())
    _show_selected()
    _notice("Грузовик отправлен")

func _return_freighter() -> void:
    if selected != construction.colony_destination() or not construction.return_freighter():
        return
    native_view.set_freight(construction.freight_status())
    _show_selected()
    _notice("Грузовик возвращается на Землю · линия отключена")

func _build_freight_line_controls(parent: Control) -> void:
    freight_line_buttons = HBoxContainer.new()
    parent.add_child(freight_line_buttons)
    _button(freight_line_buttons, "Настройка линии", _open_freight_line)
    _button(freight_line_buttons, "Разовый рейс", _open_manual_freight)
    freight_line_toggle = _button(freight_line_buttons, "", _toggle_freight_line)
    for action in freight_line_buttons.get_children():
        if action is Button:
            action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            action.add_theme_font_size_override("font_size", 12)

    manual_freight_dialog = AcceptDialog.new()
    manual_freight_dialog.title = "Разовый рейс грузовика"
    manual_freight_dialog.ok_button_text = "Отправить"
    manual_freight_dialog.add_cancel_button("Отмена")
    manual_freight_dialog.confirmed.connect(_submit_manual_freight)
    add_child(manual_freight_dialog)
    var manual_form := VBoxContainer.new()
    manual_form.custom_minimum_size.x = 340.0
    manual_freight_dialog.add_child(manual_form)
    manual_ship = OptionButton.new()
    manual_form.add_child(manual_ship)
    manual_ship.item_selected.connect(func(_index: int): _manual_ship_changed())
    var direction_label := Label.new()
    direction_label.text = "Маршрут"
    manual_form.add_child(direction_label)
    manual_destination = OptionButton.new()
    manual_form.add_child(manual_destination)
    manual_destination.item_selected.connect(_manual_route_changed)
    var commodity_label := Label.new()
    commodity_label.text = "Товар"
    manual_form.add_child(commodity_label)
    manual_resource = OptionButton.new()
    manual_form.add_child(manual_resource)
    manual_resource.item_selected.connect(
        func(_index: int): _preview_manual_freight())
    var amount_label := Label.new()
    amount_label.text = "Количество (0 — пустой возврат на Землю)"
    manual_form.add_child(amount_label)
    manual_amount = SpinBox.new()
    manual_amount.min_value = 0
    manual_amount.step = 0.01
    manual_amount.max_value = ConstructionRuntime.FREIGHT_CAPACITY
    manual_amount.value = ConstructionRuntime.FREIGHT_CAPACITY
    manual_form.add_child(manual_amount)
    manual_empty = CheckButton.new()
    manual_empty.text = "Лететь без груза"
    manual_form.add_child(manual_empty)
    manual_empty.toggled.connect(func(empty: bool):
        manual_resource.disabled = empty
        manual_amount.editable = not empty
        _preview_manual_freight())
    manual_amount.value_changed.connect(
        func(_value: float): _preview_manual_freight())
    manual_preview = Label.new()
    manual_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    manual_form.add_child(manual_preview)

    freight_line_dialog = AcceptDialog.new()
    freight_line_dialog.title = "Грузовая линия Земля ↔ Луна"
    freight_line_dialog.ok_button_text = "Применить"
    freight_line_dialog.add_cancel_button("Отмена")
    freight_line_dialog.confirmed.connect(_apply_freight_line)
    add_child(freight_line_dialog)
    var grid := GridContainer.new()
    grid.columns = 5
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 8)
    freight_line_dialog.add_child(grid)
    for heading in ["Направление", "Груз", "Партия", "Мин. остаток", "При отправке"]:
        var label := Label.new()
        label.text = heading
        grid.add_child(label)
    for destination in ["luna", "earth"]:
        var order: Dictionary = construction.freight_order(destination)
        var direction := Label.new()
        direction.text = "%s → %s" % [
            Model.PLANET_NAMES[order.source], Model.PLANET_NAMES[destination]]
        grid.add_child(direction)
        var resource := OptionButton.new()
        for id in ConstructionRuntime.FREIGHT_RESOURCES[destination]:
            resource.add_item(Model.resource_label(id))
            resource.set_item_metadata(resource.item_count - 1, id)
        grid.add_child(resource)
        var amount := SpinBox.new()
        amount.min_value = 1
        amount.max_value = ConstructionRuntime.FREIGHT_CAPACITY
        grid.add_child(amount)
        var reserve := SpinBox.new()
        reserve.max_value = 100000
        reserve.allow_greater = true
        grid.add_child(reserve)
        var policy := OptionButton.new()
        for key in ConstructionRuntime.LOAD_POLICIES:
            policy.add_item(ConstructionRuntime.LOAD_POLICIES[key])
            policy.set_item_metadata(policy.item_count - 1, key)
        grid.add_child(policy)
        freight_line_fields[destination] = {"direction": direction, "policy": policy,"resource": resource, "amount": amount, "reserve": reserve}

func _open_manual_freight(preferred_slot: int = 0) -> void:
    manual_empty.button_pressed = false
    var previous := preferred_slot if preferred_slot > 0 else _manual_ship_slot()
    manual_ship.clear()
    for slot in [1, 2]:
        var ship: Dictionary = construction.freight_status(slot)
        if ship.is_empty():
            continue
        var location: String = ship.location
        var status: String = {"transit": "В пути", "loading": "Погрузка"}.get(
            location, Model.PLANET_NAMES.get(location, location))
        var busy: bool = location in ["transit", "loading"] or (slot == 1 and construction.freight_line().enabled)
        manual_ship.add_item("Грузовик %d · %s%s" % [slot, status, " · линия" if slot == 1 and construction.freight_line().enabled else ""], slot)
        var index := manual_ship.item_count - 1
        manual_ship.set_item_disabled(index, busy)
        if not busy and (manual_ship.selected < 0 or manual_ship.is_item_disabled(manual_ship.selected) or slot == previous):
            manual_ship.select(index)
    _manual_ship_changed()
    manual_freight_dialog.popup_centered(Vector2i(455, 445))


func _manual_ship_slot() -> int:
    return manual_ship.get_selected_id() if manual_ship.selected >= 0 else 1


func _manual_ship_changed() -> void:
    var location: String = construction.freight_status(_manual_ship_slot()).get("location", "earth")
    manual_destination.clear()
    var destinations: Array = ["earth"]
    if location == "earth":
        destinations = construction.expedition.colonies.keys()
        if destinations.is_empty():
            destinations = [construction.colony_destination()]
    for destination in destinations:
        var order: Dictionary = construction.freight_order(destination, location)
        manual_destination.add_item("%s → %s" % [
            Model.PLANET_NAMES[order.source], Model.PLANET_NAMES[destination]])
        var index := manual_destination.item_count - 1
        manual_destination.set_item_metadata(index, destination)
        if destination == selected:
            manual_destination.select(index)
    _manual_route_changed(manual_destination.selected)


func _manual_route_changed(_index: int) -> void:
    var destination: String = str(manual_destination.get_selected_metadata())
    manual_resource.clear()
    for resource in ConstructionRuntime.FREIGHT_RESOURCES.get(destination, []):
        manual_resource.add_item(Model.resource_label(resource))
        manual_resource.set_item_metadata(
            manual_resource.item_count - 1, resource)
    for index in manual_resource.item_count:
        if manual_resource.get_item_metadata(index) == construction.freight_order(destination).resource:
            manual_resource.select(index)
            break
    manual_amount.min_value = 0 if destination == "earth" else 0.01
    manual_amount.value = clampf(manual_amount.value,
        manual_amount.min_value, manual_amount.max_value)
    _preview_manual_freight()


func _preview_manual_freight() -> void:
    if manual_resource.item_count == 0:
        manual_freight_dialog.get_ok_button().disabled = true
        return
    var destination: String = str(manual_destination.get_selected_metadata())
    var resource: String = str(manual_resource.get_selected_metadata())
    var amount: float = 0.0 if manual_empty.button_pressed else manual_amount.value
    var shipment: Dictionary = construction.freight_order(destination, construction.freight_status(_manual_ship_slot()).get("location", ""))
    var reason: String = construction.manual_freight_reason(
        destination, resource, amount, _manual_ship_slot())
    var cargo := "Без груза" if amount == 0 else "%s %s" % [Model.batch_amount(amount), Model.resource_label(resource)]
    manual_preview.text = "%s → %s\n%s%s" % [
        Model.PLANET_NAMES[shipment.source],
        Model.PLANET_NAMES[shipment.destination],
        cargo,
        "" if reason.is_empty() else "\n" + reason]
    if amount > 0:
        var stock: float = construction.colony_inventory(shipment.source).get("supply", {}).get(resource, 0.0)
        manual_preview.text += "\nСклад отправителя: %s" % Model.batch_amount(stock)
        if stock >= amount:
            manual_preview.text += " → " + Model.batch_amount(stock - amount)
    manual_freight_dialog.get_ok_button().disabled = not reason.is_empty()


func _submit_manual_freight() -> void:
    var destination: String = str(manual_destination.get_selected_metadata())
    var resource: String = str(manual_resource.get_selected_metadata())
    var amount: float = 0.0 if manual_empty.button_pressed else manual_amount.value
    if not construction.depart_manual_freight(destination, resource, amount, _manual_ship_slot()):
        _notice(construction.manual_freight_reason(
            destination, resource, amount, _manual_ship_slot()))
        return
    _update_native_map()
    _show_selected()
    _notice("Рейс принят · грузовик %d" % _manual_ship_slot())


## The quick "Линия" entry and clicking a spaceport open the SAME
## colony logistics surface. Existing dialog actions live inside it.
func _open_colony_logistics() -> void:
    if browser != null and browser.visible:
        _close_browser()
    _show_selected()
    colony_panel.open_logistics()


func _open_freight_line() -> void:
    var line: Dictionary = construction.freight_line()
    for destination in freight_line_fields:
        var fields: Dictionary = freight_line_fields[destination]
        var leg: Dictionary = line.legs[destination]
        var actual: String = "earth" if destination == "earth" else construction.colony_destination()
        var order: Dictionary = construction.freight_order(actual)
        fields.direction.text = "%s → %s" % [Model.PLANET_NAMES[order.source], Model.PLANET_NAMES[actual]]
        var resource: OptionButton = fields.resource
        for index in resource.item_count:
            if resource.get_item_metadata(index) == leg.resource:
                resource.select(index)
                break
        for index in fields.policy.item_count:
            if fields.policy.get_item_metadata(index) == leg.get("policy", "full"):
                fields.policy.select(index)
        fields.amount.value = leg.amount
        fields.reserve.value = leg.reserve
    freight_line_dialog.popup_centered(Vector2i(750, 220))

func _apply_freight_line() -> void:
    var legs := {}
    for destination in freight_line_fields:
        var fields: Dictionary = freight_line_fields[destination]
        fields.amount.apply()
        fields.reserve.apply()
        legs[destination] = {"resource": fields.resource.get_selected_metadata(),
            "amount": fields.amount.value, "reserve": fields.reserve.value, "policy": fields.policy.get_selected_metadata()}
    if construction.configure_freight_line(legs):
        _show_selected()

func _toggle_freight_line() -> void:
    construction.set_freight_line_enabled(not construction.freight_line().enabled)
    _show_selected()

func _show_selected() -> void:
    if details == null:
        return
    for body in world.get("bodies", []):
        if str(body.get("id", "")) != selected:
            continue
        var name_ru: String = str(Model.PLANET_NAMES.get(
            selected, body.get("name", selected)))
        planet_name_label.text = name_ru
        var warehouse: Dictionary = construction.colony_inventory(selected)
        var items: Array[String] = [
            "Тип: "+str(body.get("type", "—")),
            "Биом: "+str(body.get("biome", "—")),
            construction.production_summary(selected),
            "Строек в очереди: %d" % _pending_on(selected),
            "Ресурсные коэффициенты:"
        ]
        var expedition = construction.expedition
        var free_world: bool = selected in expedition.TARGETS and not expedition.colonies.has(selected)
        var building_colonizer: bool = construction.ship_order.get("kind") == "colonizer"
        colony_button.visible = free_world
        colony_button.text = "Экспедиция · " + name_ru
        colony_button.disabled = expedition.ship.get("location") != "earth-colony"
        if free_world and colony_button.disabled:
            var status := "Требуется колонизатор с земной верфи"
            if building_colonizer:
                status = "Колонизатор строится на Земле"
            elif expedition.ship.get("location") == "transit":
                status = "Колонизатор уже в пути"
            items.insert(1, status)
        if selected in Model.VISIBLE and not expedition.ship.is_empty():
            if expedition.ship.location == "transit":
                items.insert(1, "Колонизатор → " + Model.PLANET_NAMES[expedition.ship.target] + " · прибытие " + Calendar.calendar_text(expedition.ship.arrival))
            else:
                items.insert(1, "Колонизатор у Земли · выберите Луну или Марс")
        elif selected == construction.colony_destination() and not expedition.settlers.is_empty():
            items.insert(1, "Население: %d" % int(expedition.settlers.population_count))
        var order: Dictionary = construction.freight_order(selected)
        var freight: Dictionary = construction.freight_status()
        freight_button.hide()
        freight_line_buttons.visible = not order.is_empty() and (selected == "earth" or expedition.colonies.has(selected))
        if freight_line_buttons.visible:
            var line: Dictionary = construction.freight_line()
            freight_line_toggle.text = "Отключить линию" if line.enabled else "Включить линию"
            match freight.get("location"):
                "earth":
                    items.insert(1, "Грузовик на Земле · трюм пуст")
                "transit":
                    var cargo: Dictionary = freight.order
                    var payload := "%s %s" % [
                        Model.batch_amount(cargo.amount), Model.batch_unit(cargo.resource)] if (
                        cargo.amount > 0) else "трюм пуст"
                    items.insert(1, "Грузовик → %s · %s\nПрибытие: %s" % [
                        Model.PLANET_NAMES[cargo.destination], payload,
                        Calendar.calendar_text(freight.arrival)])
                "luna":
                    items.insert(1, "Грузовик на Луне · трюм пуст")
            if line.enabled:
                var wait: String = construction.freight_line_wait()
                if not wait.is_empty():
                    items.insert(2, wait)
        var coeff: Dictionary = config.get("planets",{}).get(selected,{})
        for key in body.get("resources",{}).keys():
            items.append("%s: %.2f" % [Model.resource_label(str(key)),
                float(coeff.get(key,0.0))])
        details.text = "\n".join(items)
        var population_count: int = construction.colony_population(selected)
        var built: Array = []
        var idle: String = ""
        for facility in world.get("facilities", []):
            if str(facility.get("body", "")) != selected:
                continue
            if str(facility.get("type", "")) == "construction_site":
                continue
            if str(facility.get("type", "")) == "station" and (
                    str(facility.get("location", "")) != selected + "-colony"):
                continue
            built.append(facility)
            var problem: String = str(facility.get("production_status", ""))
            if idle.is_empty() and problem.begins_with("Простой"):
                idle = str(facility.get("name", "")) + " · " + problem
        var line_status: String = "Линия выкл."
        if construction.freight_line().enabled:
            line_status = "Линия активна"
            var line_wait: String = construction.freight_line_wait()
            if not line_wait.is_empty():
                line_status = line_wait
        var batches: Dictionary = {}
        for facility in built:
            var facility_id: String = str(facility.get("id", ""))
            batches[facility_id] = construction.production_details(facility_id)
        colony_panel.show_colony(selected, name_ru, population_count, warehouse, built,
            construction.sites, idle, line_status, native_time, batches)
        if expedition.ship.get("location") == "transit" and expedition.ship.get("target") == selected:
            colony_panel.summary.text = "Колонизатор в пути · " + Calendar.calendar_text(expedition.ship.arrival)
            colony_panel.summary.tooltip_text = colony_panel.summary.text
        _refresh_yard()
        colony_panel.show_food(construction.colony_food(selected))
        colony_panel.show_logistics(construction.freight_line(),
            freight, construction.freight_line_wait(), construction.freight_status(2), construction.colony_destination())
        if browser != null and browser.visible:
            browser.set_colony_summary(name_ru, population_count, warehouse)
        return

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F9:
            _toggle_admin()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ESCAPE and native_view != null and (
                not native_view._placement_body_id.is_empty() or
                (district != null and district.visible and district.is_placing())):
            _cancel_placement()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ESCAPE and district != null and district.visible:
            _close_district()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_SPACE:
            # Handle BEFORE focused Buttons can reinterpret Space as
            # ui_accept and accidentally repeat the previous command.
            _pause()
            get_viewport().set_input_as_handled()

func _init_extra_settings() -> void:
    config["buildings"] = Model.building_defaults(config.get("recipes", {}))
    config["planets"] = Model.planet_defaults(world)
    if not FileAccess.file_exists(USER_CONFIG):
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(USER_CONFIG))
    if not (parsed is Dictionary):
        return
    var balance_version: int = int(parsed.get("construction_balance_version", 0))
    for group in ["buildings","planets"]:
        var saved: Variant = parsed.get(group,null)
        if not (saved is Dictionary):
            continue
        var target: Dictionary = config[group]
        for id in target.keys():
            if not (saved.get(id,null) is Dictionary):
                continue
            var defaults: Dictionary = target[id]
            for key in defaults.keys():
                # Pre-calendar saves contain old 600 metal/150 labor values.
                # Never let them silently override the new one-metal test.
                if group == "buildings" and balance_version < 2 and (
                        key in ["metals", "days"]):
                    continue
                var n: Variant = saved[id].get(key,null)
                if (n is float or n is int) and is_finite(float(n)) and (
                        float(n) >= 0.0) and float(n) <= 100000.0:
                    defaults[key] = float(n) if group=="planets" else int(n)
            target[id] = defaults
        config[group] = target

func _make_browser() -> void:
    browser = BuildingBrowser.new()
    add_child(browser)
    browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    browser.apply_requested.connect(_apply)
    browser.reset_requested.connect(_restore)
    browser.values_changed.connect(_show_selected)
    browser.close_requested.connect(_close_browser)
    browser.build_requested.connect(_begin_placement)
    browser.placement_confirmed.connect(_order_build)
    browser.placement_cancelled.connect(_cancel_placement)
    browser.cancel_requested.connect(_cancel_build)
    browser.stock_requested.connect(_open_stock_from_browser)
    browser.save_game_requested.connect(_save_game)
    browser.load_game_requested.connect(_load_game)
    browser.new_game_requested.connect(_new_game)
    browser.set_construction_state(world, construction.sites, native_time)
    browser.hide()

func _open_build() -> void:
    _open_browser(false)

func _open_stock_from_browser() -> void:
    _close_browser()
    _show_selected()
    colony_panel.open_stock()

func _open_browser(admin: bool) -> void:
    browser.configure(world, config, selected, admin)
    browser.set_construction_state(world, construction.sites, native_time)
    sidebar.hide()
    _dock_colony_stock()
    _layout_right_side()

func _close_browser() -> void:
    _cancel_placement()
    browser.hide()
    sidebar.show()
    _dock_colony_stock()
    _layout_right_side()

func _layout_right_side() -> void:
    if sidebar == null or native_view == null or browser == null:
        return
    var active_width: float = clampf(size.x * 0.30, 390.0, 500.0)
    if browser.visible and browser.page.begins_with("admin"):
        active_width = clampf(size.x * 0.43, 470.0, 740.0)
    for bar in [top_bar, performance_bar]:
        if bar != null:
            bar.offset_right = -active_width
    sidebar.offset_left = -active_width
    sidebar.offset_right = 0.0
    sidebar.offset_top = 46.0
    native_view.offset_right = -active_width
    native_view.offset_top = 78.0 if diagnostics_visible else 46.0
    district.offset_right = native_view.offset_right
    district.offset_top = native_view.offset_top
    browser.anchor_left = 1.0
    browser.anchor_right = 1.0
    browser.anchor_bottom = 1.0
    browser.offset_left = -active_width
    browser.offset_right = 0.0
    browser.offset_top = 46.0
    browser.offset_bottom = 0.0
    browser.set_dock_width(active_width)

func _native_view_world() -> Dictionary:
    # Original SystemBalance's view accepts a read-only detached projection.
    # Copy only the small mutable body rows whose display angles change.
    # The old world.duplicate(true) copied markets, routes, ships and more
    # ten times per second, even though this map only reads them.
    var result: Dictionary = world.duplicate(false)
    var visible: Array = []
    for item in world.get("bodies", []):
        if not (item is Dictionary):
            continue
        var id: String = str(item.get("id", ""))
        if not Model.VISIBLE.has(id):
            continue
        var body: Dictionary = item.duplicate(false)
        var period: float = float(body.get("orbit_period", 0))
        if str(body.get("parent_body_id", "")) != "":
            period = float(body.get("satellite_orbit_period_native", period))
        if period > 0.0:
            body["current_angle"] = fposmod(
                float(body.get("current_angle", 0.0)) +
                native_time * 360.0 / period, 360.0)
        visible.append(body)
    result["bodies"] = visible
    var facilities: Array = []
    for f in world.get("facilities", []):
        if not (f is Dictionary):
            continue
        if Model.VISIBLE.has(str(f.get("body", ""))):
            # View.update_world() deep-detaches changed facility arrays
            # itself, so an extra detached copy is unnecessary here.
            facilities.append(f)
    result["facilities"] = facilities
    return result

func _make_native_map() -> void:
    native_view = NativeStarSystemView.new()
    native_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    native_view.anchor_right = 1.0
    native_view.offset_top = 46.0
    native_view.offset_right = -SIDE_WIDTH
    native_view.mouse_filter = Control.MOUSE_FILTER_STOP
    native_view.body_selected.connect(_native_body_selected)
    native_view.body_open_requested.connect(_native_body_selected)
    native_view.facility_selected.connect(_native_facility_selected)
    native_view.placement_site_selected.connect(_placement_chosen)
    native_view.placement_cancel_requested.connect(_cancel_placement)
    add_child(native_view)
    # Under sidebar and header, but above the empty root background.
    move_child(native_view, 0)
    native_view.set_world(_native_view_world())
    native_view.select_body(selected)
    native_view.set_native_station_time(native_time)
    native_view.set_colonizer(construction.expedition.ship, true)
    native_view.set_freight(construction.freight_status(), true)
    native_view.set_second_freight(construction.freight_status(2), true)
    district = EarthDistrict.new()
    add_child(district)
    district.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    move_child(district, 1)
    district.hide()
    district.bind_runtime(construction)
    district.return_requested.connect(_close_district)
    district.surface_projection_changed.connect(native_view.align_district)
    district.zoom_out_requested.connect(func(pointer: Vector2, fraction: Vector2):
        native_view.return_to_surface_point(pointer, fraction, district.body_id)
        district.cancel_camera()
        district.hide()
        native_view.set_open_district("")
        native_view.mouse_filter = Control.MOUSE_FILTER_STOP
        native_view._zoom_at(pointer, 1.0 / native_view.WHEEL_ZOOM))
    district.facility_selected.connect(_native_facility_selected)
    district.site_selected.connect(_placement_chosen)
    district.selection_invalid.connect(func(reason: String):
        browser.reject_placement(reason))
    district.placement_cancelled.connect(_cancel_placement)
    native_view.district_requested.connect(_open_district)


func _open_district(pointer := Vector2(-1, -1), projection := Rect2(), body_id := "earth") -> void:
    if not Model.colony(world, body_id) or (district.visible and district.body_id == body_id):
        return
    if district.visible:
        _close_district()
    if selected != body_id:
        _native_body_selected({"id": body_id})
    native_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    district.set_body(body_id)
    district.update_colony(world.get("facilities", []))
    native_view.district_extent = district.camera_extent()
    native_view.set_open_district(body_id)
    district.show_district(pointer, projection)
    _dock_colony_stock()
    _refresh_district()


func _close_district() -> void:
    _cancel_placement()
    district.cancel_camera()
    district.hide()
    native_view.set_open_district("")
    native_view.mouse_filter = Control.MOUSE_FILTER_STOP
    _dock_colony_stock()
    native_view.show()
    native_view.focus_body(district.body_id)


func _refresh_district() -> void:
    if district.visible:
        district.update_colony(world.get("facilities", []))
        native_view.district_extent = district.camera_extent()


func _dock_colony_stock() -> void:
    if district == null or browser == null:
        return
    var parent: Control = browser.dock_layout if browser.visible else colony_panel.dock_layout
    if colony_stock_panel.get_parent() == parent:
        return
    colony_stock_panel.reparent(parent, false)
    parent.move_child(colony_stock_panel, 1)
    if district.visible and not browser.visible:
        colony_panel.select_overview()


func _update_native_map(snap_freight: bool = false) -> void:
    if native_view == null:
        return
    var begun: int = Time.get_ticks_usec()
    native_view.update_world(_native_view_world())
    native_view.set_native_station_time(native_time)
    native_view.set_colonizer(construction.expedition.ship, snap_freight)
    native_view.set_freight(construction.freight_status(), snap_freight)
    native_view.set_second_freight(construction.freight_status(2), snap_freight)
    _refresh_district()
    _map_view_last_usec = maxi(0, Time.get_ticks_usec() - begun)
    _map_view_peak_usec = maxi(_map_view_peak_usec, _map_view_last_usec)

func _native_body_selected(body: Dictionary) -> void:
    var id: String = str(body.get("id", ""))
    if not Model.VISIBLE.has(id):
        return
    if id != selected:
        _cancel_placement()
        if district.visible:
            _close_district()
    selected = id
    native_view.select_body(id)
    if browser.visible:
        browser.select_planet(id)
    _show_selected()
    colony_panel.clear_facility_selection()
    _refresh_yard()
    district.select_facility("")

func _native_facility_selected(facility_id: String) -> void:
    _activate_facility(facility_id)


func _colony_facility_selected(facility_id: String) -> void:
    _activate_facility(facility_id)


## One selection path for the globe and the "Построено" list: never
## select by recipe type, since two miners are two different facilities.
func _activate_facility(facility_id: String) -> void:
    for item in world.get("facilities", []):
        if str(item.get("id", "")) != facility_id:
            continue
        var body: String = str(item.get("body", ""))
        if not Model.VISIBLE.has(body):
            return
        selected = body
        if browser != null and browser.visible:
            _close_browser()
        _show_selected()
        colony_panel.select_facility(facility_id)
        _refresh_yard()
        native_view.select_facility(facility_id)
        district.select_facility(facility_id)
        var kind: String = str(item.get("type", ""))
        if kind == "station" and str(item.get(
                "location", "")) == body + "-colony":
            _open_build()
        elif kind == "spaceport":
            colony_panel.show_logistics(construction.freight_line(),
                construction.freight_status(),
                construction.freight_line_wait(), construction.freight_status(2), construction.colony_destination())
            colony_panel.open_logistics()
        return


func _refresh_yard() -> void:
    var yard: String = colony_panel.selected_facility
    yard_controls.visible = selected == "earth" and construction._earth_yard(world.facilities, yard)
    if not yard_controls.visible:
        return
    var available: float = construction.colony_inventory("earth").supply.get("metals", 0)
    var order: Dictionary = construction.ship_order
    var active: bool = order.get("yard") == yard
    var built: bool = not construction.freight_status(2).is_empty()
    yard_status.text = "%d металла · %d дней\nНа складе %s металла" % [
        ConstructionRuntime.SHIP_METALS, ConstructionRuntime.SHIP_DAYS, Model.batch_amount(available)]
    if active:
        yard_status.text = ("Колонизатор · Земля" if order.get("kind") == "colonizer" else "Грузовик 2 · Земля")
        yard_status.text += "\nГотовность %d%% · осталось %d дн." % [
            int(construction.progress(order) * 100), Calendar.days_remaining(native_time, order.finish_native)]
    elif built:
        yard_status.text += "\nГрузовик 2 построен"
    yard_order.visible = not built and order.is_empty()
    yard_order.disabled = available < ConstructionRuntime.SHIP_METALS
    yard_colonizer.visible = construction.can_build_colonizer() and order.is_empty()
    yard_colonizer.disabled = available < ConstructionRuntime.SHIP_METALS
    yard_cancel.visible = active


func _order_second_ship() -> void:
    if construction.order_second_freighter(colony_panel.selected_facility):
        _show_selected()
        _notice("Грузовик 2 заложен")


func _order_colonizer() -> void:
    pending_yard = colony_panel.selected_facility
    colonizer_order_dialog.popup_centered(Vector2i(460, 165))


func _cancel_second_ship() -> void:
    if construction.cancel_second_freighter(colony_panel.selected_facility):
        _show_selected()
        _notice("Заказ отменён · металл возвращён")


func _set_speed(multiplier: int) -> void:
    if not SPEED_PRESETS.has(multiplier):
        return
    if not visual_clock.set_speed(float(multiplier)):
        return
    speed = multiplier
    for preset in speed_buttons:
        var button: Button = speed_buttons[preset]
        if is_instance_valid(button):
            button.button_pressed = int(preset) == speed
    _update_calendar_label()

func _advance_visual_clock(delta: float) -> void:
    if paused:
        return
    var completed: int = visual_clock.consume_frame(delta)
    if completed <= 0:
        return
    visual_tick_count += completed
    native_time += float(completed) * visual_clock.tick_scale()
    _advance_construction()
    # Match source presentation commits to REAL 8 TPS changes. The old
    # fixed 100ms polling against 125ms clock ticks made 100/200ms source
    # gaps on a 500ms beat; interpolation expired before each 200ms gap.
    # Rendering still interpolates on every frame; only the source
    # snapshot cadence is synchronized here.
    _update_native_map()

func _update_performance_label() -> void:
    if perf_label == null:
        return
    var perf: Dictionary = frame_profiler.summary()
    var draw: Dictionary = {}
    if native_view != null:
        draw = native_view.draw_profile()
    perf_label.text = (
        "FPS %d · кадр p95 %.1fмс · CPU p95 %.1fмс · " +
        "UI p95 %.1fмс · карта %.1fмс · SIM —") % [
        int(perf.get("fps", 0)),
        float(perf.get("frame_p95_ms", 0.0)),
        float(perf.get("process_p95_ms", 0.0)),
        float(perf.get("ui_p95_ms", 0.0)),
        float(draw.get("last_usec", 0)) / 1000.0]
    perf_label.tooltip_text = (
        "Профайлер SystemBalance: окно 120 кадров, обновление каждые 0.5 с\n" +
        "CPU _process: avg %.2f / p95 %.2f / max %.2f мс\n" +
        "UI: avg %.2f / p95 %.2f / max %.2f мс\n" +
        "Кадр: p95 %.2f мс, худший %.2f мс\n" +
        "Отрисовка карты: последняя %.2f / максимум %.2f мс, вызовов %d\n" +
        "Кадров медленнее 16.7 мс за окно: %d\n" +
        "SIM: не подключена. Тики N158 и физическая экономика = 0.\n" +
        "Ускорение ×1/×4/×8/×16 действует только на движение планет.\n" +
        "GPU и VSYNC не входят в CPU-замеры.") % [
        float(perf.get("process_avg_ms", 0.0)),
        float(perf.get("process_p95_ms", 0.0)),
        float(perf.get("worst_process_ms", 0.0)),
        float(perf.get("ui_avg_ms", 0.0)),
        float(perf.get("ui_p95_ms", 0.0)),
        float(perf.get("worst_ui_ms", 0.0)),
        float(perf.get("frame_p95_ms", 0.0)),
        float(perf.get("worst_frame_ms", 0.0)),
        float(draw.get("last_usec", 0)) / 1000.0,
        float(draw.get("max_usec", 0)) / 1000.0,
        int(draw.get("calls", 0)),
        int(perf.get("frame_over_16_7ms_window", 0))]
    perf_label.tooltip_text += (
        "
Sol Lab · обновление проекции карты: %.3f / пик %.3f мс" +
        "
Sol Lab · обновление очереди: %.3f / пик %.3f мс") % [
        float(_map_view_last_usec) / 1000.0,
        float(_map_view_peak_usec) / 1000.0,
        float(_dock_refresh_last_usec) / 1000.0,
        float(_dock_refresh_peak_usec) / 1000.0]
func _pending_on(body_id: String) -> int:
    var count: int = 0
    for site in construction.sites:
        if str(site.get("body", "")) == body_id:
            count += 1
    return count

func _update_calendar_label() -> void:
    if time_label == null:
        return
    var whole_days: int = int(floor(Calendar.native_to_days(native_time)))
    if whole_days == _calendar_display_day:
        return
    _calendar_display_day = whole_days
    time_label.text = "Г%d · Д%03d" % [
        whole_days / Calendar.DAYS_PER_YEAR + 1,
        whole_days % Calendar.DAYS_PER_YEAR + 1]
    time_label.tooltip_text = (
        Calendar.calendar_text(native_time) +
        "\nЗемля: 700 игровых единиц = 365 дней = 1 оборот.\n" +
        "×1/×4/×8/×16 ускоряют и строительство, и орбиты.")

func _advance_construction() -> void:
    var previous_revision: int = construction.batch_revision
    var finished: Array = construction.advance_to(native_time)
    if finished.is_empty():
        if previous_revision != construction.batch_revision:
            _show_selected()
            if browser.visible and browser.page == "build":
                browser.refresh_build_availability()
                _refresh_construction_ui()
        return
    _show_selected()
    if browser.visible and browser.page == "build":
        browser.refresh_build_availability()
    _refresh_construction_ui()
    var names := PackedStringArray()
    for item in finished:
        names.append(str(item))
    _notice("Завершено: " + ", ".join(names))

func _refresh_construction_ui() -> void:
    if browser == null:
        return
    var begun: int = Time.get_ticks_usec()
    browser.set_construction_state(world, construction.sites, native_time)
    _dock_refresh_last_usec = maxi(0, Time.get_ticks_usec() - begun)
    _dock_refresh_peak_usec = maxi(_dock_refresh_peak_usec,
        _dock_refresh_last_usec)

## Choosing the catalog item is free and enters placement mode.
func _begin_placement(body: String, building_id: String) -> void:
    if body != selected or browser == null or not browser.visible:
        return
    var candidates: Array = SurfaceSites.free_sites(body, building_id,
        world.get("facilities", []))
    if candidates.is_empty():
        _notice("Для здания нет свободных подходящих площадок")
        return
    var local: bool = building_id in EarthDistrict.Art.GROUND and body in native_view.DISTRICT_BODIES
    if local:
        native_view.stop_placement()
        _open_district(Vector2(-1, -1), Rect2(), body)
        district.start_placement(building_id)
        candidates = candidates.duplicate(true)
        for candidate in candidates:
            candidate["label"] = district.plot_name(str(candidate["id"]))
    else:
        if district.visible:
            _close_district()
        native_view.start_placement(body, building_id, candidates)
    browser.start_placement(building_id, candidates, local)


func _placement_chosen(site_id: String) -> void:
    if browser != null and browser.visible:
        browser.select_placement(site_id)


func _cancel_placement() -> void:
    if district != null:
        district.stop_placement()
    if native_view != null:
        native_view.stop_placement()
    if browser != null:
        browser.clear_placement()


## A valid plot click submits the construction order.
func _order_build(body: String, building_id: String,
        site_id: String = "") -> void:
    if not site_id.is_empty() and (
            browser == null or browser.placement_chosen_id != site_id or
            body != selected):
        _notice("Сначала выберите свободную площадку")
        return
    var result: Dictionary = construction.order(body, building_id, site_id)
    if bool(result.get("ok", false)):
        _cancel_placement()
    if bool(result.get("ok", false)):
        _update_native_map()
        _show_selected()
        _refresh_construction_ui()
    if browser != null:
        browser.show_order_result(result)
    if message_line != null:
        message_line.text = ("Строительство начато" if bool(
            result.get("ok", false)) else str(
            result.get("reason", "Заказ отклонён")))

func _cancel_build(site_id: String) -> void:
    var result: Dictionary = construction.cancel_order(site_id)
    if bool(result.get("ok", false)):
        _update_native_map()
        _show_selected()
        _refresh_construction_ui()
        if browser != null:
            browser.refresh_build_availability()
        var refunded: Dictionary = result.get("refunded", {})
        _notice("Стройка отменена · возвращено %s металла" % [
            Model.batch_amount(float(refunded.get("metals", 0)))])
    else:
        _notice(str(result.get("reason", "Отмена невозможна")))


func _notice(message: String) -> void:
    if message_line != null:
        message_line.text = message
    if browser != null and browser.visible:
        browser.feedback.text = message

func _new_game() -> void:
    # No implicit loading of old checkpoints on F5.
    get_tree().call_deferred("reload_current_scene")

func _save_game() -> void:
    var snapshot: Dictionary = construction.snapshot()
    snapshot["visual_tick_count"] = visual_tick_count
    snapshot["speed"] = speed
    snapshot["paused"] = paused
    snapshot["flight_display_time"] = native_view.flight_checkpoint_time()
    var target: String = ProjectSettings.globalize_path(USER_SAVE)
    var temp: String = target + ".tmp"
    var file := FileAccess.open(temp, FileAccess.WRITE)
    if file == null:
        _notice("Ошибка сохранения игры")
        return
    file.store_string(JSON.stringify(snapshot, "  ", true, true) + "\n")
    file.close()
    var result: Error = DirAccess.rename_absolute(temp, target)
    if result == OK:
        _notice("Игра сохранена")
    else:
        _notice("Ошибка замены сохранения; прежний файл не изменён")

func _load_game() -> void:
    if not FileAccess.file_exists(USER_SAVE):
        _notice("Сохранения пока нет")
        return
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        USER_SAVE))
    if not (value is Dictionary):
        _notice("Сохранение повреждено")
        return
    if not construction.restore(value):
        _notice("Сохранение несовместимо или повреждено")
        return
    _cancel_placement()
    native_time = construction.now_native
    visual_tick_count = int(value.get("visual_tick_count", 0))
    visual_clock.reset()
    paused = value.get("paused") == true
    visual_clock.set_paused(paused)
    pause_button.text = "Продолжить" if paused else "Пауза"
    var loaded_speed: int = int(value.get("speed", 1))
    _set_speed(loaded_speed if SPEED_PRESETS.has(loaded_speed) else 1)
    var displayed: Variant = value.get("flight_display_time", native_time)
    if not (displayed is float or displayed is int) or not is_finite(float(displayed)):
        displayed = native_time
    native_view.snap_flight_clock(native_time, paused, float(displayed))
    _update_native_map(true)
    if browser != null and browser.visible:
        browser.configure(world, config, selected,
            browser.page.begins_with("admin"))
    _refresh_construction_ui()
    _show_selected()
    _notice("Игра загружена: " + Calendar.calendar_text(native_time))




