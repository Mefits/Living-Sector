extends Control
## Sol-only read-only visual slice. This does NOT advance authoritative N158/N39.
const SolProfile = preload("res://scripts/sol_profile.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const NativeStarSystemView = preload("res://scripts/star_system_view.gd")
const BuildingBrowser = preload("res://scripts/building_browser.gd")
const DEFAULTS = "res://data/balance_defaults.json"
const USER_CONFIG = "user://sol_lab_balance.json"
const SIDE_WIDTH = 340.0
var world: Dictionary = {}
var config: Dictionary = {}
var native_time: float = 0.0
var paused: bool = false
var selected: String = "earth"
var details: Label
var info_area: VBoxContainer
var mode_button: Button
var pause_button: Button
var time_label: Label
var browser
var native_view
var view_elapsed: float = 0.0

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
    _init_extra_settings()
    _build_ui()
    _make_native_map()
    _make_browser()
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
    _button(contents, "СТРОИТЕЛЬСТВО", _open_build)
    mode_button = _button(contents, "АДМИН-ПАНЕЛЬ · F9", _toggle_admin)
    info_area = VBoxContainer.new()
    contents.add_child(info_area)
    var heading := Label.new()
    heading.text = "ВЫБРАННЫЙ ОБЪЕКТ"
    info_area.add_child(heading)
    details = Label.new()
    details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(details)
    var hint := Label.new()
    hint.text = "Оригинальная карта SystemBalance: двойной клик — приблизить.\nСимуляция пока не подключена."
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_area.add_child(hint)


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
    file.store_string(JSON.stringify(config, "  ") + "\n")
    file.close()
    return true

func _apply() -> void:
    if _save_config():
        get_tree().reload_current_scene()
    else:
        push_error("Не удалось сохранить баланс")

func _restore() -> void:
    if FileAccess.file_exists(USER_CONFIG):
        if DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_CONFIG)) != OK:
            push_error("Не удалось сбросить баланс")
            return
    get_tree().call_deferred("reload_current_scene")

func _toggle_admin() -> void:
    if browser.visible:
        browser.hide()
    else:
        browser.configure(world, config, selected, true)

func _pause() -> void:
    paused = not paused
    pause_button.text = "Продолжить" if paused else "Пауза"

func _step() -> void:
    native_time += 1.0
    _update_native_map()

func _reset_camera() -> void:
    if native_view != null:
        native_view.reset_view()

func _process(delta: float) -> void:
    if not paused:
        # Visual clock only; no N158 tick and no economic side effects.
        native_time += delta * 20.0
        view_elapsed += delta
        if view_elapsed >= 0.10:
            view_elapsed = 0.0
            _update_native_map()
    if time_label != null:
        time_label.text = "Виз. тик %d  " % int(native_time)

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
    browser.hide()

func _open_build() -> void:
    browser.configure(world,config,selected,false)

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
    native_view.offset_top = 43.0
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
    _show_selected()
