extends Control
## Sol-only read-only visual slice. This does NOT advance authoritative N158/N39.
const SolProfile = preload("res://scripts/sol_profile.gd")
const SolStarter = preload("res://scripts/sol_start_scenario.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const NativeStarSystemView = preload("res://scripts/star_system_view.gd")
const BuildingBrowser = preload("res://scripts/building_browser.gd")
const UIFrameProfiler = preload("res://scripts/ui_frame_profiler.gd")
const NativeClock = preload("res://scripts/sim/clock.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const ConstructionRuntime = preload("res://scripts/sol_construction_runtime.gd")
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
var construction = ConstructionRuntime.new()
var construction_ui_elapsed: float = 0.0
var message_line: Label
var paused: bool = false
var speed: int = 1
var speed_buttons: Dictionary = {}
var frame_profiler = UIFrameProfiler.new()
var perf_label: Label
var previous_process_started_usec: int = -1
var selected: String = "earth"
var details: Label
var info_area: VBoxContainer
var mode_button: Button
var pause_button: Button
var time_label: Label
var browser
var native_view
var sidebar: PanelContainer
var top_bar: HBoxContainer
var performance_bar: HBoxContainer
var view_elapsed: float = 0.0

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
    construction.setup(world, config["buildings"])
    _build_ui()
    _make_native_map()
    _make_browser()
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
    _button(bar, "Камера", _reset_camera)
    var perf_bar := HBoxContainer.new()
    performance_bar = perf_bar
    add_child(perf_bar)
    perf_bar.anchor_right = 1.0
    perf_bar.offset_top = 46
    perf_bar.offset_bottom = 78
    perf_bar.offset_right = -SIDE_WIDTH
    perf_label = Label.new()
    perf_label.text = "FPS — · кадр p95 — · CPU p95 — · UI p95 — · карта — · SIM —"
    perf_label.add_theme_font_size_override("font_size", 14)
    perf_label.add_theme_color_override("font_color", Color("#8fc6d9"))
    perf_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    perf_label.clip_text = true
    perf_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    perf_label.tooltip_text = "Оригинальный UIFrameProfiler из SystemBalance. " + (
        "Симуляция N158 пока не подключена.")
    perf_bar.add_child(perf_label)
    sidebar = PanelContainer.new()
    add_child(sidebar)
    sidebar.anchor_left = 1.0
    sidebar.anchor_right = 1.0
    sidebar.anchor_bottom = 1.0
    sidebar.offset_left = -SIDE_WIDTH
    sidebar.offset_right = 0.0
    var contents := VBoxContainer.new()
    sidebar.add_child(contents)
    info_area = VBoxContainer.new()
    contents.add_child(info_area)
    var heading := Label.new()
    heading.text = "ВЫБРАННЫЙ ОБЪЕКТ"
    info_area.add_child(heading)
    details = Label.new()
    details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(details)
    var hint := Label.new()
    hint.text = "Тест строительства: 1 металл · 45 дней.\n" + (
        "Никакого труда. Производство N39 пока не подключено.")
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(hint)
    message_line = Label.new()
    message_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    message_line.add_theme_color_override("font_color", Color("#e0c18b"))
    info_area.add_child(message_line)
    var filler := Control.new()
    filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
    contents.add_child(filler)
    _button(contents, "СТРОИТЕЛЬСТВО", _open_build)
    mode_button = _button(contents, "АДМИН-ПАНЕЛЬ · F9", _toggle_admin)
    var saves := HBoxContainer.new()
    contents.add_child(saves)
    _button(saves, "Новая", _new_game)
    _button(saves, "Сохр.", _save_game)
    _button(saves, "Загруз.", _load_game)


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
        view_elapsed += delta
        if view_elapsed >= 0.10:
            view_elapsed = fmod(view_elapsed, 0.10)
            _update_native_map()
    _update_calendar_label()
    construction_ui_elapsed += delta
    if construction_ui_elapsed >= 0.5:
        construction_ui_elapsed = fmod(construction_ui_elapsed, 0.5)
        _refresh_construction_ui()
    var ui_usec: int = maxi(0, Time.get_ticks_usec() - ui_started_usec)
    var process_usec: int = maxi(0, Time.get_ticks_usec() - started_usec)
    # Zero N158 and zero real sim ticks: this project renders a visual clock
    # only. Never present visual time as production/simulation performance.
    frame_profiler.capture(frame_delta, process_usec, 0, ui_usec, 0)
    if frame_profiler.display_due():
        _update_performance_label()

func _show_selected() -> void:
    if details == null:
        return
    for body in world.get("bodies", []):
        if str(body.get("id", "")) != selected:
            continue
        var items: Array[String] = [
            str(body.get("name", selected)),
            "Тип: "+str(body.get("type", "—")),
            "Биом: "+str(body.get("biome", "—")),
            "Металл на складе: %d" % Model.stock(world,selected),
            "Строек в очереди: %d" % _pending_on(selected),
            "Ресурсные коэффициенты:"
        ]
        var coeff: Dictionary = config.get("planets",{}).get(selected,{})
        for key in body.get("resources",{}).keys():
            items.append("%s: %.2f" % [Model.resource_label(str(key)),
                float(coeff.get(key,0.0))])
        details.text = "\n".join(items)
        return

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
        _toggle_admin()
        get_viewport().set_input_as_handled()

func _init_extra_settings() -> void:
    config["buildings"] = Model.building_defaults()
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
    browser.build_requested.connect(_order_build)
    browser.save_game_requested.connect(_save_game)
    browser.load_game_requested.connect(_load_game)
    browser.new_game_requested.connect(_new_game)
    browser.set_construction_state(world, construction.sites, native_time)
    browser.hide()

func _open_build() -> void:
    _open_browser(false)

func _open_browser(admin: bool) -> void:
    browser.configure(world, config, selected, admin)
    browser.set_construction_state(world, construction.sites, native_time)
    sidebar.hide()
    _layout_right_side()

func _close_browser() -> void:
    browser.hide()
    sidebar.show()
    _layout_right_side()

func _layout_right_side() -> void:
    if sidebar == null or native_view == null or browser == null:
        return
    var active_width: float = SIDE_WIDTH
    if browser.visible:
        # Reserve actual viewport space for the original map.
        # The catalog never overlays the planet/camera canvas.
        active_width = minf(clampf(size.x * 0.57, 620.0, 870.0),
            maxf(300.0, size.x - 430.0))
    for bar in [top_bar, performance_bar]:
        if bar != null:
            bar.offset_right = -active_width
    sidebar.offset_left = -SIDE_WIDTH
    sidebar.offset_right = 0.0
    native_view.offset_right = -active_width
    browser.anchor_left = 1.0
    browser.anchor_right = 1.0
    browser.anchor_bottom = 1.0
    browser.offset_left = -active_width
    browser.offset_right = 0.0
    browser.offset_top = 78.0
    browser.offset_bottom = 0.0
    browser.set_dock_width(active_width)

func _native_view_world() -> Dictionary:
    # Filter PRESENTATION only. Frozen source Sol and colony data stay intact.
    var result: Dictionary = world.duplicate(true)
    var visible: Array = []
    for item in world.get("bodies", []):
        if not (item is Dictionary):
            continue
        var id: String = str(item.get("id", ""))
        if not Model.VISIBLE.has(id):
            continue
        var body: Dictionary = item.duplicate(true)
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
        if Model.VISIBLE.has(str(f.get("body", ""))):
            facilities.append(f.duplicate(true))
    result["facilities"] = facilities
    return result

func _make_native_map() -> void:
    native_view = NativeStarSystemView.new()
    native_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    native_view.anchor_right = 1.0
    native_view.offset_top = 78.0
    native_view.offset_right = -SIDE_WIDTH
    native_view.mouse_filter = Control.MOUSE_FILTER_STOP
    native_view.body_selected.connect(_native_body_selected)
    native_view.body_open_requested.connect(_native_body_selected)
    add_child(native_view)
    # Under sidebar and header, but above the empty root background.
    move_child(native_view, 0)
    native_view.set_world(_native_view_world())
    native_view.select_body(selected)
    native_view.set_native_station_time(native_time)

func _update_native_map() -> void:
    if native_view == null:
        return
    native_view.update_world(_native_view_world())
    native_view.set_native_station_time(native_time)

func _native_body_selected(body: Dictionary) -> void:
    var id: String = str(body.get("id", ""))
    if not Model.VISIBLE.has(id):
        return
    selected = id
    native_view.select_body(id)
    if browser.visible:
        browser.select_planet(id)
    _show_selected()

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
    time_label.text = "Г%d · Д%03d" % [
        whole_days / Calendar.DAYS_PER_YEAR + 1,
        whole_days % Calendar.DAYS_PER_YEAR + 1]
    time_label.tooltip_text = (
        Calendar.calendar_text(native_time) +
        "\nЗемля: 700 игровых единиц = 365 дней = 1 оборот.\n" +
        "×1/×4/×8/×16 ускоряют и строительство, и орбиты.")

func _advance_construction() -> void:
    var finished: Array = construction.advance_to(native_time)
    if finished.is_empty():
        return
    _update_native_map()
    _show_selected()
    if browser.visible and browser.page == "build":
        browser.configure(world, config, selected, false)
    _refresh_construction_ui()
    _notice("Завершено: " + ", ".join(finished))

func _refresh_construction_ui() -> void:
    if browser == null:
        return
    browser.set_construction_state(world, construction.sites, native_time)

func _order_build(body: String, building_id: String) -> void:
    var result: Dictionary = construction.order(body, building_id)
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
    var target: String = ProjectSettings.globalize_path(USER_SAVE)
    var temp: String = target + ".tmp"
    var file := FileAccess.open(temp, FileAccess.WRITE)
    if file == null:
        _notice("Ошибка сохранения игры")
        return
    file.store_string(JSON.stringify(snapshot, "  ") + "\n")
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
    native_time = construction.now_native
    visual_tick_count = int(value.get("visual_tick_count", 0))
    visual_clock.reset()
    paused = false
    pause_button.text = "Пауза"
    var loaded_speed: int = int(value.get("speed", 1))
    _set_speed(loaded_speed if SPEED_PRESETS.has(loaded_speed) else 1)
    _update_native_map()
    if browser != null and browser.visible:
        browser.configure(world, config, selected,
            browser.page.begins_with("admin"))
    _refresh_construction_ui()
    _show_selected()
    _notice("Игра загружена: " + Calendar.calendar_text(native_time))
