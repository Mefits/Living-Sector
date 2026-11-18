extends Control
## Sol-only read-only visual slice. This does NOT advance authoritative N158/N39.
const SolProfile = preload("res://scripts/sol_profile.gd")
const DEFAULTS = "res://data/balance_defaults.json"
const USER_CONFIG = "user://sol_lab_balance.json"
const SIDE_WIDTH = 340.0
var world: Dictionary = {}
var config: Dictionary = {}
var native_time: float = 0.0
var paused: bool = false
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
var dragging: bool = false
var selected: String = "earth"
var positions: Dictionary = {}
var details: Label
var admin_area: ScrollContainer
var info_area: VBoxContainer
var mode_button: Button
var pause_button: Button
var time_label: Label
var admin_open: bool = false

func _ready() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sol.json"))
    if not (parsed is Dictionary):
        push_error("Отсутствует исходный Sol")
        return
    world = parsed
    if not SolProfile.apply_world(world):
        push_error("Отклонены исходные параметры спутников")
        return
    config = _load_config()
    _build_ui()
    _show_selected()
    queue_redraw()

func _build_ui() -> void:
    var bar := HBoxContainer.new()
    add_child(bar)
    bar.anchor_right = 1.0
    bar.offset_right = -SIDE_WIDTH
    bar.offset_bottom = 43
    var title := Label.new()
    title.text = "  LIVING SECTOR  /  SOL LAB  "
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(title)
    time_label = Label.new()
    bar.add_child(time_label)
    pause_button = _button(bar, "Пауза", _pause)
    _button(bar, "+1", _step)
    _button(bar, "Камера", _reset_camera)
    var sidebar := PanelContainer.new()
    add_child(sidebar)
    sidebar.anchor_left = 1.0
    sidebar.anchor_right = 1.0
    sidebar.anchor_bottom = 1.0
    sidebar.offset_left = -SIDE_WIDTH
    sidebar.offset_right = 0.0
    var contents := VBoxContainer.new()
    sidebar.add_child(contents)
    mode_button = _button(contents, "Админ-панель · F9", _toggle_admin)
    info_area = VBoxContainer.new()
    contents.add_child(info_area)
    var heading := Label.new()
    heading.text = "ВЫБРАННЫЙ ОБЪЕКТ"
    info_area.add_child(heading)
    details = Label.new()
    details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(details)
    var hint := Label.new()
    hint.text = "Клик — выбрать тело; колесо — масштаб; перетаскивание — карта.\nВремя пока только визуальное."
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(hint)
    admin_area = ScrollContainer.new()
    admin_area.visible = false
    admin_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
    contents.add_child(admin_area)
    var items := VBoxContainer.new()
    items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    admin_area.add_child(items)
    var warning := Label.new()
    warning.text = "НАСТРОЙКИ БАЛАНСА\nСохраняются между запусками.\nПока НЕ подключены к экономике N39."
    warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    items.add_child(warning)
    _add_numeric(items, "construction", "materials", "Стройка: материалы")
    _add_numeric(items, "construction", "labor", "Стройка: труд")
    _add_numeric(items, "recipes", "farm_water_in", "Ферма: вода (вход)")
    _add_numeric(items, "recipes", "farm_food_out", "Ферма: еда (выход)")
    _add_numeric(items, "recipes", "smelt_ore_in", "Плавка: руда (вход)")
    _add_numeric(items, "recipes", "smelt_fuel_in", "Плавка: топливо (вход)")
    _add_numeric(items, "recipes", "smelt_metals_out", "Плавка: металлы (выход)")
    _add_numeric(items, "needs", "earth_food", "Жители Земли: еда")
    _add_numeric(items, "needs", "earth_water", "Жители Земли: вода")
    _button(items, "Сохранить и перезапустить", _apply)
    _button(items, "Восстановить исходные", _restore)

func _button(parent: Node, label: String, action: Callable) -> Button:
    var b := Button.new()
    b.text = label
    parent.add_child(b)
    b.pressed.connect(action)
    return b

func _add_numeric(parent: Node, group: String, key: String, label: String) -> void:
    var l := Label.new()
    l.text = label
    parent.add_child(l)
    var spin := SpinBox.new()
    spin.min_value = 0
    spin.max_value = 100000
    spin.step = 1
    spin.value = float(config.get(group, {}).get(key, 0))
    parent.add_child(spin)
    spin.value_changed.connect(_changed.bind(group, key))

func _changed(value: float, group: String, key: String) -> void:
    var category: Dictionary = config.get(group, {})
    category[key] = int(value)
    config[group] = category

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
    file.store_string(JSON.stringify(config, "  ") + "\n")
    file.close()
    return true

func _apply() -> void:
    if _save_config():
        get_tree().reload_current_scene()
    else:
        push_error("Не удалось сохранить баланс")

func _restore() -> void:
    var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS))
    if defaults is Dictionary:
        config = defaults
        _apply()

func _toggle_admin() -> void:
    admin_open = not admin_open
    info_area.visible = not admin_open
    admin_area.visible = admin_open
    mode_button.text = "Вернуться к объекту · F9" if admin_open else "Админ-панель · F9"

func _pause() -> void:
    paused = not paused
    pause_button.text = "Продолжить" if paused else "Пауза"

func _step() -> void:
    native_time += 1.0
    queue_redraw()

func _reset_camera() -> void:
    zoom = 1.0
    pan = Vector2.ZERO
    queue_redraw()

func _process(delta: float) -> void:
    if not paused:
        native_time += delta * 20.0
        queue_redraw()
    if time_label != null:
        time_label.text = "Виз. тик %d  " % int(native_time)

func _center() -> Vector2:
    return Vector2((size.x - SIDE_WIDTH) * 0.5, size.y * 0.53) + pan

func _radius(body: Dictionary) -> float:
    var r: float = float(body.get("orbit_radius", 0.0))
    return (30.0 + pow(clampf(r / 24.0, 0.0, 1.0), 0.62) * minf(size.y, size.x - SIDE_WIDTH) * 0.38) * zoom

func _position(center: Vector2, radius: float, body: Dictionary, period_key: String) -> Vector2:
    var period: float = maxf(float(body.get(period_key, 1.0)), 1.0)
    var a: float = deg_to_rad(float(body.get("current_angle", 0.0)) + 360.0 * native_time / period)
    return center + Vector2(cos(a), sin(a)) * radius

func _rebuild_positions() -> void:
    positions.clear()
    for item in world.get("bodies", []):
        var b: Dictionary = item
        if str(b.get("parent_body_id", "")).is_empty():
            positions[str(b.get("id", ""))] = _position(_center(), _radius(b), b, "orbit_period")
    for item in world.get("bodies", []):
        var b: Dictionary = item
        var parent: String = str(b.get("parent_body_id", ""))
        if not parent.is_empty() and positions.has(parent):
            var moon_r: float = clampf(float(b.get("satellite_orbit_radius_native", 0.0)) * 1600.0, 18.0, 38.0) * zoom
            positions[str(b.get("id", ""))] = _position(positions[parent], moon_r, b, "satellite_orbit_period_native")

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, Vector2(size.x - SIDE_WIDTH, size.y)), Color("#0b1421"), true)
    if world.is_empty():
        return
    _rebuild_positions()
    for item in world.get("bodies", []):
        var b: Dictionary = item
        var parent: String = str(b.get("parent_body_id", ""))
        var radius: float = _radius(b)
        var c: Vector2 = _center()
        if not parent.is_empty() and positions.has(parent):
            c = positions[parent]
            radius = clampf(float(b.get("satellite_orbit_radius_native", 0.0)) * 1600.0, 18.0, 38.0) * zoom
        draw_arc(c, radius, 0.0, TAU, 96, Color(0.35, 0.51, 0.6, 0.28), 1.0)
    draw_circle(_center(), 12.0, Color("#e4bc75"))
    var font: Font = get_theme_default_font()
    draw_string(font, _center() + Vector2(16, 0), "Sol", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
    for item in world.get("bodies", []):
        var b: Dictionary = item
        var id: String = str(b.get("id", ""))
        if not positions.has(id):
            continue
        var pos: Vector2 = positions[id]
        var color: Color = Color("#8fa5ba")
        match str(b.get("biome", "")):
            "terrestrial": color = Color("#69aaa3")
            "gas_giant": color = Color("#bc9c7a")
            "desert": color = Color("#ae8068")
            "molten": color = Color("#a77a6d")
            "ice": color = Color("#99c1cf")
        var dot_radius: float = 9.0 if str(b.get("biome", "")) == "gas_giant" else 6.0
        draw_circle(pos, dot_radius, color)
        if selected == id:
            draw_arc(pos, dot_radius + 5.0, 0.0, TAU, 32, Color("#ecd391"), 2.0)
        if selected == id or id in ["earth", "venus", "mars", "jupiter", "saturn"]:
            draw_string(font, pos + Vector2(11, -6), str(b.get("name", id)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#d4dfe5"))

func _show_selected() -> void:
    if details == null:
        return
    for item in world.get("bodies", []):
        if str(item.get("id", "")) != selected:
            continue
        var resources: Dictionary = item.get("resources", {})
        var parts: Array[String] = []
        for resource in resources.keys():
            parts.append("%s — %s" % [str(resource), str(resources[resource])])
        var facilities: int = 0
        for f in world.get("facilities", []):
            if str(f.get("body", "")) == selected:
                facilities += 1
        details.text = "%s\nТип: %s\nБиом: %s\nРадиус орбиты: %s\nПредприятий в Sol: %d\nРесурсы:\n%s" % [str(item.get("name", selected)), str(item.get("type", "")), str(item.get("biome", "")), str(item.get("orbit_radius", "")), facilities, "\n".join(parts)]
        return

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.position.x < size.x - SIDE_WIDTH and event.position.y > 45.0:
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            zoom = clampf(zoom * 1.22, 0.5, 3.0)
            queue_redraw()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            zoom = clampf(zoom / 1.22, 0.5, 3.0)
            queue_redraw()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _rebuild_positions()
                var nearest: String = ""
                var dist: float = 19.0
                for id in positions.keys():
                    var d: float = event.position.distance_to(positions[id])
                    if d < dist:
                        dist = d
                        nearest = str(id)
                if nearest.is_empty():
                    dragging = true
                else:
                    selected = nearest
                    _show_selected()
                    queue_redraw()
            else:
                dragging = false
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        dragging = false
    elif event is InputEventMouseMotion and dragging:
        pan += event.relative
        queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
        _toggle_admin()
        get_viewport().set_input_as_handled()
