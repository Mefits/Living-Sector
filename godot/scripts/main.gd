extends Control
## P2 N158: original Galaxy orbital clock + real N39 physical paid production.
## Fleet, contract, population consumption and Head AI still await later P2 integration.

const NativeData = preload("res://scripts/native_data.gd")
const TickRunner = preload("res://scripts/sim/phase2/n158_production_runtime.gd")
const SaveState = preload("res://scripts/sim/save_state.gd")
const P2_SAVE_PATH: String = "user://saves/galaxy-067-p2-integration.json"
## Keep opt-in worker testing from overwriting the known-good default save.
const P2_WORKER_SAVE_PATH: String = "user://saves/galaxy-067-p2-worker-experimental.json"
const SPEEDS = [0.25, 1.0, 2.0, 4.0, 8.0, 16.0]
## User decision 13.11.2026: observer-first autonomous sector. Keep the
## N14/N21/N15 manual tools as an explicit later-game debug feature.
## Do NOT remove N39/N14 engine APIs: future autonomous agents reuse them.
const ENABLE_DEBUG_MANUAL_FLEET_UI: bool = false
const SystemMap = preload("res://scripts/system_map.gd")
const StarSystemView = preload("res://scripts/star_system_view.gd")
const ObserverPanel = preload("res://scripts/observer_panel.gd")
const StrategyUI = preload("res://scripts/view/strategy_ui.gd")
const FacilityLabels = preload("res://scripts/view/facility_labels_ru.gd")
const UI_SCALES = [1.0, 1.15, 1.25, 1.4]
const DEFAULT_UI_SCALE_INDEX: int = 2
const UIFrameProfiler = preload("res://scripts/ui_frame_profiler.gd")
const WorkerN158 = preload("res://scripts/sim/phase2/n158_real_owner_thread_probe.gd")
const ReadOnlyWorldModel = preload("res://scripts/sim/world_model.gd")

var _model
var _runner
var _seed: Dictionary = {}
var _cached_seed_stats: Dictionary = {}
var _selected_system: String = "system-sol"
var _selected_body_id: String = ""
var _selected_ship_id: String = ""
var _selected_facility_id: String = ""
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
var _strategy_ui
var _ship_choice: OptionButton
var _ship_destination: LineEdit
var _cargo_commodity: LineEdit
var _cargo_quantity: SpinBox
## U1/U2: real FPS and UI-only timing, no extra World snapshots.
var _frame_profiler = UIFrameProfiler.new()
var _perf_label: Label
var _ui_profile_log: bool = false
var _ui_profile_log_elapsed: float = 0.0
var _previous_process_start_usec: int = -1
## U6: all tick_completed signals are coalesced into the latest finished
## authoritative tick. SceneTree UI never runs inside advance_frame().
var _pending_ui_tick: int = -1
var _last_orbit_presentation_tick: int = -1
var _last_fleet_presentation_tick: int = -1
var _presentation_elapsed: float = 0.0
var _last_full_presentation_tick: int = -1
const UI_DETAIL_INTERVAL: float = 0.45
const UI_FLEET_MIN_TICKS: int = 4

## Experimental E-only real Thread backend. False by default; never shares
## the worker's live N158/N39/N9 with the SceneTree or view callbacks.
var _worker_mode: bool = false
var _worker_owner
var _worker_booted: bool = false
var _worker_failed: String = ""
var _worker_loading: bool = false
var _worker_frame_ticket: int = -1
var _worker_tick: int = 0
var _worker_speed: float = 0.25
var _worker_paused: bool = false
var _worker_elapsed: float = 0.0
var _worker_last_view_usec: int = -1
var _worker_calendar_text: String = ""
var _worker_native_time_units: float = 0.0
var _worker_economy: Dictionary = {}
var _worker_native: Dictionary = {}
var _worker_summary: Dictionary = {}
var _worker_fleet: Dictionary = {}
var _worker_last_sim_ms: float = 0.0
var _worker_view_dirty: bool = false
var _worker_pending_actions: Dictionary = {}
const WORKER_VIEW_INTERVAL_USEC: int = 450000
const WORKER_MAX_DELTA: float = 0.125
## Headless GUI acceptance is opt-in and NEVER runs in normal gameplay.
var _worker_smoke: bool = false
var _worker_smoke_stage: int = 0
var _worker_smoke_begin_msec: int = 0
var _worker_smoke_step_done: bool = false
var _worker_smoke_view_done: bool = false
var _worker_smoke_save_done: bool = false
var _worker_smoke_load_done: bool = false
var _worker_smoke_path: String = ""
## Bounded real-time SceneTree check: validates async frames while native
## paid economy advances by ordinary clock, not hand-issued fake steps.
var _worker_live_check: bool = false
var _worker_live_started_msec: int = 0
var _worker_live_frames: int = 0
var _worker_live_cpu_us: Array[int] = []

func _ready() -> void:
    get_window().content_scale_factor = float(UI_SCALES[DEFAULT_UI_SCALE_INDEX])
    _ui_profile_log = OS.get_cmdline_user_args().has("--p2-ui-profile") or (
        OS.get_environment("LS_PROFILE_UI_FRAMES") == "1")
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
    # Always-on counter. Engine FPS includes compositor stalls; the three
    # CPU timers below only measure code, not GPU presentation.
    _perf_label = Label.new()
    _perf_label.text = "FPS — · process — · sim — · UI —"
    _perf_label.add_theme_font_size_override("font_size", 11)
    _perf_label.add_theme_color_override("font_color", Color("#8fc6d9"))
    _perf_label.custom_minimum_size = Vector2.ZERO
    _perf_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _perf_label.clip_text = true
    _perf_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    _perf_label.tooltip_text = "FPS из Engine; p95 _process, advance_frame и UI за последние 120 кадров. Худший кадр — от запуска."
    heading.add_child(_perf_label)
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
    autonomy_hint.text = "НАБЛЮДЕНИЕ: N153/N84 корабельный ИИ работает; проверяйте реальные рейсы N14, контракты и причины ожидания"
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
    _system_view.set_ui_viewport_scale(float(UI_SCALES[DEFAULT_UI_SCALE_INDEX]))
    _system_view.visible = false
    map_stage.add_child(_system_view)
    _system_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _system_view.connect("body_selected", _on_body_selected)
    _system_view.connect("body_open_requested", _on_body_open_requested)
    _system_view.connect("ship_selected", _on_ship_selected)
    _system_view.connect("facility_selected", _on_facility_selected)

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
    _observer_panel.connect("section_changed", Callable(self, "_refresh_observer"))
    _observer_panel.visible = false
    _observer_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(_observer_panel)

    var footer := Label.new()
    footer.text = "P2 · карта сектора → система → планета · экономика и автономный флот N84/N153 в интеграции; состояние в Наблюдении"
    footer.add_theme_color_override("font_color", Color("#8da6b5"))
    root.add_child(footer)
    # The live world and map stay exactly as before. Only the old full-screen
    # debug chrome is replaced; '--p2-legacy-ui' restores it for diagnostics.
    if not OS.get_cmdline_user_args().has("--p2-legacy-ui"):
        heading.visible = false
        _status.visible = false
        toolbar.visible = false
        autonomy_hint.visible = false
        footer.visible = false
        details_panel.visible = false
        for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
            margins.add_theme_constant_override(side, 0)
        root.add_theme_constant_override("separation", 0)
        _strategy_ui = StrategyUI.new()
        _strategy_ui.attach(self)
        add_child(_strategy_ui)
        _strategy_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var data: Dictionary = NativeData.load_current_world()
    if data.has("error"):
        _status.text = "Ошибка импорта Galaxy"
        _details.text = str(data["error"])
        _startup_error = str(data["error"])
        push_error(_startup_error)
        return

    _seed = data
    # The PERF PR explicitly opts the regular F5 game into the isolated
    # worker. Godot editor run arguments and unregistered project keys did not
    # reach the game process. Explicit legacy override always wins.
    # Only one N158/N39/N9 owner exists in either branch.
    var run_args: PackedStringArray = OS.get_cmdline_user_args()
    # PERF BRANCH ONLY. Godot Editor F5 does not forward project.godot
    # editor/main_run_args; likewise the unregistered custom project key
    # was absent from headless runtime. Enable this isolated integration
    # by construction in this DRAFT PR, never silently merge as default.
    # The explicit legacy override below remains authoritative.
    const PERF_BRANCH_WORKER_F5: bool = true
    var request_worker: bool = OS.get_environment("LS_N158_WORKER_GUI") == "1" or (
        run_args.has("--p2-worker-gui"))
    var request_legacy: bool = OS.get_environment("LS_N158_WORKER_GUI") == "0" or (
        run_args.has("--p2-default-gui") or run_args.has("--p2-boot-check"))
    _worker_mode = (PERF_BRANCH_WORKER_F5 or request_worker) and not request_legacy
    if _worker_mode:
        title.text = "LIVING SECTOR / GODOT P2 · WORKER (ЭКСПЕРИМЕНТ)"
        _worker_smoke = OS.get_cmdline_user_args().has(
            "--p2-worker-gui-check")
        _worker_smoke_begin_msec = Time.get_ticks_msec()
        _worker_live_check = OS.get_cmdline_user_args().has(
            "--p2-worker-gui-run-check")
        _worker_live_started_msec = Time.get_ticks_msec()
        # This is a detached presentation WorldModel loaded from the frozen
        # seed. It is NEVER a second N158 simulation or writable N39 World.
        _model = ReadOnlyWorldModel.new()
        if not _model.load_seed(_seed):
            _startup_error = "Не удалось создать read-only UI карту"
            _details.text = _startup_error
            push_error(_startup_error)
            return
        _worker_owner = WorkerN158.new()
        if not _worker_owner.launch(_seed):
            _startup_error = "Не удалось запустить единственный N158 worker"
            _details.text = _startup_error
            push_error(_startup_error)
            return
        _sync_speed_control()
    else:
        _runner = TickRunner.new()
        if not _runner.start_from_seed(_seed):
            _status.text = "Ошибка индексации исходного мира"
            _details.text = "Не удалось собрать физический мир P2: " + str(_runner.boot_error())
            _startup_error = _details.text + " / " + str(_runner.boot_error())
            push_error(_startup_error)
            return

        # Restore ONLY the original owner here. Worker restores via its FIFO.
        _restore_startup_checkpoint()
        _sync_speed_control()
        _model = _runner.world
        _populate_ship_choices()
        _runner.tick_completed.connect(_on_tick_completed)
    var stats: Dictionary = _model.seed_stats()
    _cached_seed_stats = stats.duplicate()
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
    if _worker_mode:
        print("GODOT_P2_WORKER_GUI_OPT_IN owner=thread seed_ships=",
            int(_cached_seed_stats.get("ships", 0)))
    else:
        print("GODOT_P2_PAID_PRODUCTION_BOOT ", JSON.stringify(_runner.production_stats()))
    _update_status()
    _sync_strategy_ui()
    # The old P2 boot smoke always runs against the default owner.
    if not _worker_mode and OS.get_cmdline_user_args().has("--p2-boot-check"):
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
    if _worker_mode:
        return # debug manual N14 commands are disabled for this backend
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
    if _worker_mode:
        return # no unowned N14 direct command; fail closed
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
    if _worker_mode:
        return # no unowned N21 direct command; fail closed
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

func _refresh_observer() -> Dictionary:
    if _worker_mode:
        if _observer_panel == null or not _observer_panel.visible or (
                _worker_economy.is_empty() or _worker_native.is_empty()):
            return {}
        _observer_panel.call("show_live_economy", _worker_tick,
            _worker_economy, _worker_summary, _worker_fleet, _worker_native)
        return _worker_economy
    if not _observer_panel or not _observer_panel.visible or not _runner:
        return {}
    # A read-only checkpoint projection lets the Observer distinguish a
    # planned route from durable N15/N97 cargo and N9/N104 receipts. It
    # never owns, mutates, or reconstructs a second World/Ledger/Board.
    var checkpoint: Dictionary = _runner.checkpoint()
    var native_production: Dictionary = checkpoint.get("native_production", {})
    # All three Observer inputs refer to this one DETACHED completed N38
    # frame. Never clone growing markets/receipts a second time here.
    var economy: Dictionary = native_production.get("world", {})
    if economy.is_empty():
        return {}
    _observer_panel.call("show_live_economy", _runner.tick_count,
        economy, _runner.economy_summary(economy),
        economy.get("ships", {}), native_production)
    return economy

func _process(delta: float) -> void:
    if _worker_mode:
        _worker_gui_process(delta)
        return
    var began: int = Time.get_ticks_usec()
    # True monotonic time between GUI callbacks (including compositor and
    # previous blocking tick), rather than a possibly smoothed Engine delta.
    # N158 still receives ORIGINAL delta, preserving its time semantics.
    var wall_frame_delta: float = delta
    if _previous_process_start_usec >= 0:
        wall_frame_delta = float(maxi(0,
            began - _previous_process_start_usec)) / 1000000.0
    _previous_process_start_usec = began
    var ticks_before: int = _runner.tick_count if _runner != null else 0
    var advance_usec: int = 0
    if _runner and _fatal_restore_error.is_empty():
        var advance_start: int = Time.get_ticks_usec()
        _runner.advance_frame(delta)
        advance_usec = maxi(0, Time.get_ticks_usec() - advance_start)
    var ui_start: int = Time.get_ticks_usec()
    _flush_finished_tick_views(wall_frame_delta)
    var ui_usec: int = maxi(0, Time.get_ticks_usec() - ui_start)
    var process_usec: int = maxi(0, Time.get_ticks_usec() - began)
    var new_ticks: int = 0
    if _runner != null:
        new_ticks = maxi(0, _runner.tick_count - ticks_before)
    _frame_profiler.capture(wall_frame_delta, process_usec, advance_usec, ui_usec, new_ticks)
    if _frame_profiler.display_due() and _perf_label != null:
        var report: Dictionary = _frame_profiler.summary()
        var drawing: Dictionary = _active_draw_profile()
        _perf_label.text = _frame_profiler.compact_text()
        _perf_label.tooltip_text = (
            "CPU _process: avg %.2f / p95 %.2f / max %.2f мс\n" +
            "advance_frame (симуляция + callbacks): avg %.2f / p95 %.2f / max %.2f мс\n" +
            "UI после расчёта: avg %.2f / p95 %.2f / max %.2f мс\n" +
            "Кадр delta p95: %.2f мс; худший окно/с запуска: %.2f/%.2f мс; тиков всего: %d\n" +
            "draw CPU (последний / max): %.2f / %.2f мс, вызовов: %d\n" +
            "CPU доля _process: sim %.1f%% · UI %.1f%%\n" +
            "Кадры >16.7мс (окно): total %d · advance %d · UI %d\n" +
            "GPU-компоновка и VSYNC вне CPU-таймеров; проверяйте FPS."
        ) % [
            float(report["process_avg_ms"]), float(report["process_p95_ms"]),
            float(report["worst_process_ms"]),
            float(report["advance_avg_ms"]), float(report["advance_p95_ms"]),
            float(report["worst_advance_ms"]),
            float(report["ui_avg_ms"]), float(report["ui_p95_ms"]),
            float(report["worst_ui_ms"]),
            float(report["frame_p95_ms"]),
            float(report["frame_window_max_ms"]),
            float(report["worst_frame_ms"]), int(report["ticks"]),
            float(drawing.get("last_usec", 0)) / 1000.0,
            float(drawing.get("max_usec", 0)) / 1000.0,
            int(drawing.get("calls", 0)),
            float(report["advance_share_of_process_pct"]),
            float(report["ui_share_of_process_pct"]),
            int(report["frame_over_16_7ms_window"]),
            int(report["advance_over_16_7ms_window"]),
            int(report["ui_over_16_7ms_window"])]
        if _strategy_ui != null:
            _strategy_ui.update_performance(Engine.get_frames_per_second(),
                float(report["advance_p95_ms"]),
                float(report["ui_p95_ms"]), false,
                _perf_label.tooltip_text)
    if _ui_profile_log:
        _ui_profile_log_elapsed += maxf(wall_frame_delta, 0.0)
        if _ui_profile_log_elapsed >= 5.0:
            _ui_profile_log_elapsed = 0.0
            var output: Dictionary = _frame_profiler.summary()
            output["tick"] = _runner.tick_count if _runner != null else -1
            output["paused"] = _runner.clock.paused if _runner != null else true
            output["speed"] = _runner.clock.world_speed if _runner != null else 0.0
            output["view"] = "system" if _in_system else "sector"
            output["observer"] = _observer_panel.visible if _observer_panel != null else false
            output["draw_cpu"] = _active_draw_profile()
            print("P2_UI_FRAME " + JSON.stringify(output))


## Experimental F5 backend: every simulation mutation happens on the worker.
## _model is a separate, SEED-ONLY display map. Only the worker's detached,
## completed orbit/economy/N38 snapshots are projected into SceneTree UI.
func _worker_send(kind: String, payload: Dictionary = {}) -> int:
    if _worker_owner == null or not _worker_failed.is_empty():
        return -1
    var ticket: int = _worker_owner.submit(kind, payload)
    if ticket <= 0:
        _notice = "Worker отклонил команду " + kind
        _worker_update_status()
    return ticket

func _worker_gui_process(delta: float) -> void:
    var start_usec: int = Time.get_ticks_usec()
    var old_tick: int = _worker_tick
    if _worker_owner == null:
        return
    for _i in range(16):
        var outcome: Dictionary = _worker_owner.poll_answer()
        if outcome.is_empty():
            break
        _worker_receive(outcome)
    if _worker_view_dirty:
        _worker_view_dirty = false
        _worker_present()
    if _worker_smoke:
        _worker_gui_smoke_pump()
        return
    # One in-flight frame, no unbounded FIFO. Delayed GUI frames are bounded
    # like SourceClock.consume_frame; elapsed that cannot be simulated is
    # dropped, never converted into fake catch-up ticks.
    _worker_elapsed = minf(0.25, _worker_elapsed + maxf(delta, 0.0))
    if _worker_booted and not _worker_loading and (
            _worker_failed.is_empty() and _worker_frame_ticket < 0):
        var now_usec: int = Time.get_ticks_usec()
        var view_due: bool = _worker_economy.is_empty() or (
            _worker_last_view_usec < 0 or
            now_usec - _worker_last_view_usec >= WORKER_VIEW_INTERVAL_USEC)
        var admitted_delta: float = minf(_worker_elapsed, WORKER_MAX_DELTA)
        var frame_request: Dictionary = {
            "delta": admitted_delta, "view": view_due,
            "observer": view_due and _observer_panel != null and
                _observer_panel.visible}
        var ticket: int = _worker_send("frame", frame_request)
        if ticket > 0:
            _worker_frame_ticket = ticket
            _worker_elapsed = 0.0
            if view_due:
                _worker_last_view_usec = now_usec
    var cpu_usec: int = maxi(0, Time.get_ticks_usec() - start_usec)
    _frame_profiler.capture(maxf(delta, 0.0), cpu_usec, 0, cpu_usec,
        maxi(0, _worker_tick - old_tick))
    if _frame_profiler.display_due() and _perf_label != null:
        _perf_label.text = "WORKER · FPS %d · тик %d · sim %.1f мс (фон)" % [
            Engine.get_frames_per_second(), _worker_tick, _worker_last_sim_ms]
        _perf_label.tooltip_text = (
            "Экспериментальный N158 worker: 1 authoritative World/N9/Clock; " +
            "кадры SceneTree не вызывают advance_frame. Последний sim_ms " +
            "из worker; это НЕ измерение GPU и не подтверждение TPS.")
        if _strategy_ui != null:
            var worker_ui: Dictionary = _frame_profiler.summary()
            _strategy_ui.update_performance(Engine.get_frames_per_second(),
                _worker_last_sim_ms, float(worker_ui.get("process_p95_ms", 0)),
                true, _perf_label.tooltip_text)
    if _worker_live_check and _worker_booted:
        _worker_live_frames += 1
        _worker_live_cpu_us.append(cpu_usec)
        if _worker_tick >= 32:
            if _worker_economy.is_empty() or _worker_fleet.size() != 24 or (
                    not _worker_failed.is_empty()):
                push_error("P2_WORKER_GUI_LIVE_FAIL: no detached 32-tick frame")
                _worker_live_check = false
                get_tree().quit(1)
                return
            var samples: Array[int] = _worker_live_cpu_us.duplicate()
            samples.sort()
            var at: int = clampi(ceili(float(samples.size()) * 0.95) - 1,
                0, samples.size() - 1)
            print("P2_WORKER_GUI_32_TICK_LIVE_PASS ", JSON.stringify({
                "tick": _worker_tick, "frames": _worker_live_frames,
                "ui_process_p95_ms": snappedf(float(samples[at]) / 1000.0, 0.01),
                "elapsed_s": snappedf(float(Time.get_ticks_msec() -
                    _worker_live_started_msec) / 1000.0, 0.01),
                "ships": _worker_fleet.size(), "worker_thread": true}))
            _worker_live_check = false
            get_tree().quit(0)
        elif Time.get_ticks_msec() - _worker_live_started_msec > 30000:
            push_error("P2_WORKER_GUI_LIVE_FAIL: 32 source ticks timeout, last="
                + str(_worker_tick))
            _worker_live_check = false
            get_tree().quit(1)

func _worker_receive(result: Dictionary) -> void:
    var kind: String = str(result.get("kind", ""))
    var ticket: int = int(result.get("ticket", -1))
    if ticket == _worker_frame_ticket:
        _worker_frame_ticket = -1
    if kind == "boot":
        if not bool(result.get("ok", false)):
            _worker_failed = "Ошибка запуска N158 worker: " + str(
                result.get("error", "unknown"))
            push_error(_worker_failed)
            _worker_update_status()
            return
        _worker_booted = true
        _worker_tick = int(result.get("tick", 0))
        # Use SaveState on the SAME owner thread; no GUI-owned second N158.
        if (FileAccess.file_exists(P2_WORKER_SAVE_PATH) or
                FileAccess.file_exists(P2_WORKER_SAVE_PATH + ".bak") or
                FileAccess.file_exists(P2_WORKER_SAVE_PATH + ".pending")):
            _worker_loading = true
            if _worker_send("load", {"path": P2_WORKER_SAVE_PATH}) <= 0:
                _worker_loading = false
        _worker_update_status()
        return
    if kind == "load":
        _worker_loading = false
    if not bool(result.get("ok", false)):
        if kind == "save":
            _notice = "N38 сохранение отклонено: " + str(
                result.get("error", "unknown"))
        else:
            # Fail closed: the owner may be mid-recovery or have rejected a
            # native transaction. Never send more ticks or pretend success.
            _worker_failed = "N158 worker: " + kind + " — " + str(
                result.get("error", "rejected"))
            push_error(_worker_failed)
        _worker_update_status()
        return
    if result.has("tick"):
        _worker_tick = int(result["tick"])
    if result.has("paused"):
        _worker_paused = bool(result["paused"])
    if result.has("speed"):
        _worker_speed = float(result["speed"])
    if result.has("sim_usec") and (kind != "frame" or
            bool(result.get("advanced", false))):
        _worker_last_sim_ms = float(result["sim_usec"]) / 1000.0
    if result.get("angles") is Dictionary:
        if not _model.restore_orbital_snapshot(result["angles"]):
            _worker_failed = "Повреждён detached orbital FrameView"
            push_error(_worker_failed)
            _worker_update_status()
            return
        _worker_view_dirty = true
    if result.has("calendar_text"):
        _worker_calendar_text = str(result["calendar_text"])
    if result.has("native_time_units"):
        _worker_native_time_units = float(result["native_time_units"])
        if _in_system and _system_view != null:
            _system_view.set_native_station_time(_worker_native_time_units)
    if result.get("economy") is Dictionary:
        _worker_economy = result["economy"]
        _worker_fleet = _worker_economy.get("ships", {})
        _worker_summary = result.get("summary", {})
        # Never show N38 history from a DIFFERENT completed economic frame.
        _worker_native = result.get("native", {})
        _worker_view_dirty = true
    if kind == "save":
        _notice = "N38 сохранено на единственном N158 worker (тик %d)" % _worker_tick
    elif kind == "load":
        _notice = "N38 восстановлено на worker (тик %d)" % _worker_tick
        _last_full_presentation_tick = -1
        _last_orbit_presentation_tick = -1
        _worker_last_view_usec = -1
        _worker_view_dirty = true
        _sync_speed_control()
    elif kind == "speed":
        _sync_speed_control()
    if _worker_smoke:
        match kind:
            "step":
                _worker_smoke_step_done = true
            "frame":
                _worker_smoke_view_done = not _worker_native.is_empty()
            "save":
                _worker_smoke_save_done = true
            "load":
                _worker_smoke_load_done = true
    if kind != "frame" or result.has("economy") or result.has("angles"):
        _worker_update_status()

func _worker_gui_smoke_pump() -> void:
    if not _worker_failed.is_empty():
        push_error("P2_WORKER_GUI_BOOT_CHECK_FAIL: " + _worker_failed)
        get_tree().quit(1)
        _worker_smoke = false
        return
    if Time.get_ticks_msec() - _worker_smoke_begin_msec > 25000:
        push_error("P2_WORKER_GUI_BOOT_CHECK_FAIL: command timeout " +
            str(_worker_smoke_stage))
        get_tree().quit(1)
        _worker_smoke = false
        return
    if not _worker_booted or _worker_loading:
        return
    match _worker_smoke_stage:
        0:
            if _worker_send("pause") <= 0 or _worker_send(
                    "step", {"count": 2}) <= 0:
                _worker_failed = "smoke step command rejected"
                return
            _worker_smoke_stage = 1
        1:
            if _worker_smoke_step_done:
                if _worker_tick != 2 or _worker_economy.is_empty():
                    _worker_failed = "real paid step did not commit two ticks"
                    return
                if _worker_send("frame", {"delta": 0.0, "view": true,
                        "observer": true}) <= 0:
                    _worker_failed = "full detached observer frame rejected"
                    return
                _worker_smoke_stage = 2
        2:
            if _worker_smoke_view_done:
                if _worker_tick != 2 or _worker_native.is_empty() or (
                        _worker_fleet.size() != 24):
                    _worker_failed = "torn/missing N39/N9/ship FrameView"
                    return
                var sol: Dictionary = _model.system_by_id("system-sol")
                if sol.is_empty():
                    _worker_failed = "read-only system model unavailable"
                    return
                _open_world(sol)
                if not _in_system or not _system_view.visible:
                    _worker_failed = "real GUI map navigation failed"
                    return
                # Exercise exact outliner -> selected ship -> physical marker
                # using one real detached worker N39 ship, not a test sprite.
                var local_id: String = ""
                for ship_id in _worker_fleet:
                    var ship: Variant = _worker_fleet[ship_id]
                    if ship is Dictionary and str(ship.get("system_id", "")) == "system-sol":
                        local_id = str(ship_id)
                        break
                if local_id.is_empty() or _strategy_ui == null:
                    _worker_failed = "missing real Sol ship in GUI smoke"
                    return
                _strategy_ui.call("_select_ship", local_id)
                if _selected_ship_id != local_id or str(
                        _system_view.get("_selected_ship_id")) != local_id:
                    _worker_failed = "outliner vessel did not highlight on physical map"
                    return
                if str(_strategy_ui.get("_ship")) != local_id:
                    _worker_failed = "outliner ship context was not synchronized"
                    return
                _return_to_sector()
                if _in_system or not _map.visible:
                    _worker_failed = "real GUI return navigation failed"
                    return
                _worker_smoke_path = ("user://tests/p2-worker-gui-" +
                    str(Time.get_ticks_usec()) + ".json")
                if _worker_send("save", {"path": _worker_smoke_path}) <= 0:
                    _worker_failed = "worker N38 save rejected"
                    return
                _worker_smoke_stage = 3
        3:
            if _worker_smoke_save_done:
                _worker_loading = true
                if _worker_send("load", {"path": _worker_smoke_path}) <= 0:
                    _worker_failed = "worker N38 load rejected"
                    return
                _worker_smoke_stage = 4
        4:
            if _worker_smoke_load_done:
                var health: Dictionary = startup_health()
                if _worker_tick != 2 or not health.get("ok", false) or (
                        _worker_native.is_empty() or _worker_fleet.size() != 24):
                    _worker_failed = "worker GUI N38 restart or startup health drift"
                    return
                print("P2_WORKER_GUI_BOOT_CHECK_PASS tick=2 ships=24",
                    " worker_thread=true n38_restart=true gui_navigation=true")
                _worker_smoke = false
                get_tree().quit(0)

func _worker_present() -> void:
    if _model == null:
        return
    if _in_system and _system_view != null:
        var current: Dictionary = _model.system_by_id(_selected_system)
        if not current.is_empty():
            _system_view.update_world(current)
            _system_view.set_live_fleet(_worker_fleet)
    _refresh_observer()
    _refresh_selection(_worker_economy, false)
    _worker_update_status()

func _worker_update_status() -> void:
    if _status == null or _pause_button == null:
        return
    var totals: Dictionary = _cached_seed_stats
    var loading: String = " · загрузка..." if _worker_loading else ""
    var running: String = "Пауза" if _worker_paused else "Идёт время"
    _status.text = ("WORKER · %d систем · %d фракции · %d тел  |  " +
        "Тик %d  |  ×%s  |  %s%s") % [
        int(totals.get("systems", 0)), int(totals.get("factions", 0)),
        int(totals.get("bodies", 0)), _worker_tick,
        str(_worker_speed), running, loading]
    if not _worker_calendar_text.is_empty():
        _status.text += "  |  " + _worker_calendar_text
    if not _worker_summary.is_empty():
        _status.text += "  |  Native: %d рын. / %d предприятий" % [
            int(_worker_summary.get("markets", 0)),
            int(_worker_summary.get("facilities", 0))]
    if not _worker_failed.is_empty():
        _status.text += "  |  ОШИБКА: " + _worker_failed
    if not _notice.is_empty():
        _status.text += "  |  " + _notice
    _pause_button.text = ("Ошибка worker" if not _worker_failed.is_empty()
        else ("Продолжить" if _worker_paused else "Пауза"))
    _status.tooltip_text = _status.text

## Never call Thread.wait_to_finish from _process or a per-frame signal.
func _exit_tree() -> void:
    if _worker_owner != null:
        _worker_owner.close()
        _worker_owner = null

func _active_draw_profile() -> Dictionary:
    var view: Variant = _system_view if _in_system else _map
    if view != null and view.has_method("draw_profile"):
        return view.draw_profile()
    return {}

func _toggle_pause() -> void:
    if _worker_mode:
        if _worker_failed.is_empty():
            _worker_send("resume" if _worker_paused else "pause")
        return
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
    if _worker_mode:
        if _worker_failed.is_empty():
            _worker_send("pause")
            _worker_send("step", {"count": count})
        return
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
    if _worker_mode:
        if _worker_failed.is_empty() and index >= 0 and index < SPEEDS.size():
            _worker_send("speed", {"value": float(SPEEDS[index])})
        return
    if not _runner or not _fatal_restore_error.is_empty() or index < 0 or index >= SPEEDS.size():
        return
    _runner.queue_control("speed", float(SPEEDS[index]))
    _runner.advance_frame(0.0)
    _update_status()

func _save_game(save_path: String = "") -> void:
    if _worker_mode:
        if _worker_failed.is_empty():
            var path: String = P2_WORKER_SAVE_PATH if save_path.is_empty() else save_path
            _worker_send("save", {"path": path})
            _notice = "Сохранение N38 поставлено в очередь worker"
            _update_status()
        return
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
    if _worker_mode:
        if _worker_failed.is_empty():
            var path: String = P2_WORKER_SAVE_PATH if save_path.is_empty() else save_path
            _worker_loading = true
            if _worker_send("load", {"path": path}) <= 0:
                _worker_loading = false
        return
    if not _runner:
        return
    var target: String = P2_SAVE_PATH if save_path.is_empty() else save_path
    var result: Dictionary = SaveState.load_runner(_runner, _seed, target)
    if result.get("ok", false):
        _fatal_restore_error = ""
        _startup_error = ""
        _model = _runner.world
        _cached_seed_stats = _model.seed_stats()
        # A loaded checkpoint replaces the authoritative world and clock. Refresh
        # all read-only projections; never keep a stale seed-era map or speed UI.
        _pending_ui_tick = -1
        _last_orbit_presentation_tick = -1
        _last_fleet_presentation_tick = -1
        _last_full_presentation_tick = -1
        _presentation_elapsed = 0.0
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
    if _speed_menu == null or (_runner == null and not _worker_mode):
        return
    var restored_speed: float = (_worker_speed if _worker_mode
        else float(_runner.clock.world_speed))
    for index in range(SPEEDS.size()):
        if is_equal_approx(float(SPEEDS[index]), restored_speed):
            # Assigning selected does not dispatch item_selected or mutate time.
            _speed_menu.selected = index
            return
    # A compatible checkpoint may carry a valid custom speed. Do not lie
    # about the current multiplier by displaying a different preset.
    _speed_menu.select(-1)


func _on_tick_completed(tick: int) -> void:
    # N158 emits from WITHIN advance_frame(). It may advance several ticks
    # in one GUI frame: do not clone N39 World, rebuild inspector text or
    # redraw geometry inside the signal. This records only the last real
    # completed tick; it cannot influence tick order or AI.
    _pending_ui_tick = tick

func _flush_finished_tick_views(delta: float) -> void:
    _presentation_elapsed += maxf(delta, 0.0)
    if _pending_ui_tick < 0 or _runner == null:
        return
    var latest: int = _pending_ui_tick
    var need_fleet: bool = false
    # Orbit view always samples the newest completed real state, at most
    # once per visible GUI frame. No interpolation or fictitious movement.
    if _in_system and _system_view != null and _model != null and (
            latest != _last_orbit_presentation_tick):
        var current: Dictionary = _model.system_by_id(_selected_system)
        if not current.is_empty():
            _system_view.update_world(current)
            _system_view.set_native_station_time(
                _runner.calendar.native_time_units)
            _last_orbit_presentation_tick = latest
            need_fleet = _last_fleet_presentation_tick < 0 or (
                latest - _last_fleet_presentation_tick >= UI_FLEET_MIN_TICKS)
    # Native ships_snapshot already clones only owned ships, so the
    # interim frame can use it. When a full UI frame is ALSO due, reuse
    # that one detached N39 world instead: no second fleet copy.
    if _presentation_elapsed < UI_DETAIL_INTERVAL:
        if need_fleet:
            _system_view.set_live_fleet(_runner.fleet_snapshot())
            _last_fleet_presentation_tick = latest
        return
    _presentation_elapsed = 0.0
    if _last_full_presentation_tick == latest:
        if need_fleet:
            _system_view.set_live_fleet(_runner.fleet_snapshot())
            _last_fleet_presentation_tick = latest
        return
    _last_full_presentation_tick = latest
    if ENABLE_DEBUG_MANUAL_FLEET_UI:
        _populate_ship_choices()
    var shared_economy: Dictionary = _refresh_observer()
    if shared_economy.is_empty():
        shared_economy = _runner.economy_snapshot()
    if need_fleet:
        _system_view.set_live_fleet(shared_economy.get("ships", {}))
        _last_fleet_presentation_tick = latest
    _refresh_selection(shared_economy, false)
    _update_status(shared_economy)
    _pending_ui_tick = -1

func _runtime_failure() -> Dictionary:
    if _runner != null and _runner.has_method("last_phase_failure"):
        return _runner.last_phase_failure()
    return {}

func _update_status(shared_economy: Dictionary = {}) -> void:
    if _worker_mode:
        _worker_update_status()
        return
    if not _runner:
        return
    # Seed counts change only on explicit boot/N38 rebind, not on each
    # paid economic tick. They are UI metadata, never a second simulation.
    var totals: Dictionary = _cached_seed_stats
    _status.text = "%d систем · %d фракции · %d тел   |   Тик %d   |   ×%s   |   %s%s" % [
        totals.get("systems", 0), totals.get("factions", 0),
        totals.get("bodies", 0), _runner.tick_count,
        str(_runner.clock.world_speed),
        "Пауза" if _runner.clock.paused else "Идёт время",
        "   |   " + _notice if not _notice.is_empty() else ""
    ]
    _status.text += "   |   " + _runner.calendar.display_text(_runner.tick_count)
    if _runner.has_method("economy_summary"):
        var economic: Dictionary = _runner.economy_summary(shared_economy)
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

func _refresh_selection(shared_economy: Dictionary = {},
        refresh_live_view: bool = true) -> void:
    if _worker_mode:
        if _model == null:
            return
        var current: Dictionary = _model.system_by_id(_selected_system)
        if current.is_empty():
            return
        if _in_system:
            if refresh_live_view:
                _system_view.update_world(current)
                _system_view.set_live_fleet(_worker_fleet)
                _system_view.set_native_station_time(
                    _worker_native_time_units)
            if _worker_economy.has("facilities"):
                _system_view.set_live_facilities(
                    _worker_economy["facilities"], _worker_tick)
            _show_body_details(current, _worker_economy)
        else:
            _select_world(current, _worker_economy)
        _sync_strategy_ui(_worker_economy)
        return
    if not _runner:
        return
    var selected: Dictionary = _model.system_by_id(_selected_system)
    if not selected.is_empty():
        if _in_system:
            if refresh_live_view:
                _system_view.update_world(selected)
                _system_view.set_live_fleet(_runner.fleet_snapshot())
                _system_view.set_native_station_time(
                    _runner.calendar.native_time_units)
            if shared_economy.has("facilities"):
                _system_view.set_live_facilities(
                    shared_economy["facilities"], _runner.tick_count)
            _show_body_details(selected, shared_economy)
        else:
            _select_world(selected, shared_economy)
    _sync_strategy_ui(shared_economy)

func _change_ui_scale(index: int) -> void:
    if index < 0 or index >= UI_SCALES.size():
        return
    var value: float = float(UI_SCALES[index])
    get_window().content_scale_factor = value
    if _system_view != null:
        _system_view.set_ui_viewport_scale(value)

func _reset_map() -> void:
    if _in_system and _system_view:
        _system_view.reset_view()
    elif _map:
        _map.call("reset_view")

func _select_world(world: Dictionary, shared_economy: Dictionary = {}) -> void:
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
        _system_view.set_live_fleet(_worker_fleet if _worker_mode
            else _runner.fleet_snapshot())
        _show_body_details(world, shared_economy)
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
    # Selection and Observer may use the SAME completed, detached N39
    # snapshot. Never request another World copy within this one update.
    var economy: Dictionary = shared_economy
    if economy.is_empty() and _runner != null and _runner.has_method("economy_snapshot"):
        economy = _runner.economy_snapshot()
    if not economy.is_empty():
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
    if not economy.is_empty():
        var live_populations: Dictionary = economy.get("populations", {})
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
        if not _worker_mode and _runner != null and _runner.has_method("last_population_result"):
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
    _selected_ship_id = ""
    _selected_facility_id = ""
    _in_system = true
    _map.visible = false
    _system_view.visible = true
    _system_view.set_world(current)
    _system_view.set_native_station_time(
        _worker_native_time_units if _worker_mode
        else _runner.calendar.native_time_units)
    _system_view.call("set_live_fleet", _worker_fleet if _worker_mode
        else _runner.fleet_snapshot())
    _map.call("select_system", sid)
    _back_button.visible = true
    _back_button.text = "← К сектору"
    _open_button.visible = false
    _show_body_details(current)
    _sync_strategy_ui()


func _return_to_sector() -> void:
    # Three semantic map levels: globe -> orbital system -> sector.
    # Do not reset or duplicate the running world on a UI-only transition.
    if _in_system and _system_view != null and _system_view.is_body_focused():
        _system_view.unfocus_body()
        _back_button.text = "← К сектору"
        _sync_strategy_ui()
        return
    _in_system = false
    _system_view.visible = false
    _map.visible = true
    _back_button.visible = false
    _back_button.text = "← К сектору"
    _open_button.visible = true
    _selected_body_id = ""
    _selected_ship_id = ""
    _selected_facility_id = ""
    _refresh_selection()
    _sync_strategy_ui()


func _on_body_selected(body: Dictionary) -> void:
    if not _in_system or _model == null:
        return
    _selected_ship_id = ""
    _selected_facility_id = ""
    _selected_body_id = str(body.get("id", ""))
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        _show_body_details(current)
    _sync_strategy_ui()


func _on_body_open_requested(body: Dictionary) -> void:
    if not _in_system or _model == null or _system_view == null:
        return
    _selected_ship_id = ""
    _selected_facility_id = ""
    var id: String = str(body.get("id", ""))
    if id.is_empty() or not _system_view.focus_body(id):
        return
    _selected_body_id = id
    _back_button.text = "← К системе"
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        _show_body_details(current)
    _sync_strategy_ui()


## One real source facility ID, not a newly minted decorative module.
func _on_facility_selected(facility_id: String) -> void:
    if not _in_system or _model == null or _system_view == null:
        return
    _selected_facility_id = facility_id
    _selected_ship_id = ""
    _selected_body_id = ""
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        _show_body_details(current, _worker_economy if _worker_mode
            else _runner.economy_snapshot())
    _sync_strategy_ui()


## Both moving vessels and docked fleets use their authentic N39 ship
## snapshot. Never mint a UI ship, modify AI or call the worker thread.
func _on_ship_selected(ship_id: String) -> void:
    if not _in_system or _model == null or _system_view == null:
        return
    _selected_ship_id = ship_id
    _selected_facility_id = ""
    _selected_body_id = ""
    var current: Dictionary = _model.system_by_id(_selected_system)
    if not current.is_empty():
        var fleet: Dictionary = (_worker_fleet if _worker_mode else (
            _runner.fleet_snapshot() if _runner != null else {}))
        # Pick the SAME ship in the map as in the outliner. Select before
        # detaching projected fleet so its N14 waypoints can be retained.
        _system_view.select_ship(ship_id)
        # Refresh only the selected ship's bounded physical route.
        _system_view.set_live_fleet(fleet)
        _show_ship_details(fleet)
    _sync_strategy_ui()


## Outliner-only camera reveal: map mouse clicks do not jump the camera.
func _reveal_selected_ship_on_map() -> bool:
    if _system_view == null or _selected_ship_id.is_empty() or not _in_system:
        return false
    return _system_view.reveal_ship(_selected_ship_id)


func _show_ship_details(fleet: Dictionary) -> bool:
    if _selected_ship_id.is_empty():
        return false
    if not fleet.has(_selected_ship_id):
        # Selected vessel may be destroyed/retired between UI snapshots.
        _selected_ship_id = ""
        return false
    var ship: Dictionary = fleet[_selected_ship_id]
    var lines: Array[String] = [
        "КОРАБЛЬ",
        str(ship.get("name", _selected_ship_id)),
        "ID: " + _selected_ship_id,
        "Класс: " + str(ship.get("class", "—")),
        "Фракция: " + str(ship.get("faction_id", "—")),
        "Система: " + str(ship.get("system_id", "—")),
        ""
    ]
    var transit: Dictionary = ship.get("transit", {})
    if transit.is_empty():
        lines.append("Статус: в локации")
        lines.append("Локация: " + str(ship.get("location", "—")))
        var docked: String = str(ship.get("docked_at", ""))
        if not docked.is_empty():
            lines.append("Пристыкован: " + docked)
    else:
        lines.append("Статус: в полёте")
        lines.append("Откуда: " + str(transit.get("from", "—")))
        lines.append("Куда: " + str(transit.get("to", "—")))
        lines.append("Отправление: тик " + str(transit.get("departure_tick", "—")))
        lines.append("Последнее движение: тик " + str(transit.get("last_tick", "—")))
        lines.append("Ориентир прибытия: тик " + str(transit.get("arrival_tick", "—")))
        lines.append("Перелёт: физический N14, координаты не выдуманы")
        var detour: Variant = transit.get("navigation_waypoints", [])
        if detour is Array and not detour.is_empty():
            lines.append("Облёт: " + str(transit.get(
                "navigation_obstacle_id", "препятствия")) +
                " · осталось точек: " + str(detour.size()))
        var hold_reason: String = str(transit.get("navigation_hold", ""))
        if not hold_reason.is_empty():
            lines.append("Ожидание безопасного курса: " + hold_reason)
    lines.append("")
    lines.append("Топливо: %.1f / %.1f" % [
        float(ship.get("fuel", 0.0)), float(ship.get("fuel_capacity", 0.0))])
    var cargo: Dictionary = ship.get("cargo", {})
    var cargo_amount: int = 0
    for quantity in cargo.values():
        cargo_amount += int(quantity)
    lines.append("Груз: %d / %d" % [
        cargo_amount, int(ship.get("cargo_capacity", 0))])
    var materials: Array = cargo.keys()
    materials.sort()
    for material in materials:
        if float(cargo[material]) > 0.0:
            lines.append(" • %s: %s" % [str(material), str(cargo[material])])
    lines.append("Средства: %s CR" % str(ship.get("credits", "—")))
    var task: Variant = ship.get("task", null)
    if task != null and str(task) != "":
        lines.append("Задача: " + str(task))
    _details.text = "\n".join(lines)
    return true


## A selected station or surface enterprise has its own real N39
## state, owner, labor and money. The five frozen Sol entities currently
## share an economic location; this is shown honestly, not faked away.
func _show_facility_details(world: Dictionary,
        shared_economy: Dictionary = {}) -> bool:
    var source: Dictionary = {}
    for row in world.get("facilities", []):
        if str(row.get("id", "")) == _selected_facility_id:
            source = row
            break
    if source.is_empty():
        _selected_facility_id = ""
        return false
    var id: String = _selected_facility_id
    var kind: String = str(source.get("type", ""))
    var orbital: bool = kind in ["station", "shipyard"]
    var location: String = str(source.get("location", ""))
    var body_id: String = str(source.get("body", ""))
    var economy: Dictionary = shared_economy
    if economy.is_empty():
        if _worker_mode:
            economy = _worker_economy
        elif _runner != null:
            economy = _runner.economy_snapshot()
    var live_facilities: Dictionary = economy.get("facilities", {})
    var lines: Array[String] = [
        "ОРБИТАЛЬНАЯ СТАНЦИЯ" if orbital else "ПРЕДПРИЯТИЕ ПЛАНЕТЫ",
        str(source.get("name", id)),
        "ID: " + id, "Тип: " + kind,
        "Небесное тело: " + body_id,
        "Владелец: " + str(source.get("faction_id", "—")),
        ""
    ]
    if orbital:
        lines.append("Стыковочных мест: %d" % int(
            source.get("docking_capacity", 0)))
        var services: Array = source.get("services", [])
        lines.append("Службы: " + (", ".join(PackedStringArray(services))
            if not services.is_empty() else "нет"))
        lines.append("Орбитальный узел N43; корабли используют эту")
        lines.append("локацию для реального N14 сближения и стыковки.")
    else:
        lines.append("Положение предприятия на глобусе схематично.")
        lines.append("Это отдельный исходный объект N39, не станционный слот.")
    lines.append("")
    lines.append("ЖИВАЯ ЭКОНОМИКА N39")
    if live_facilities.has(id):
        var live: Dictionary = live_facilities[id]
        lines.append("Средства: %d CR" % int(live.get("credits", 0)))
        lines.append("Работники: %d" % int(live.get(
            "assigned_workers", 0)))
        var shift: Dictionary = live.get("work_shift", {})
        if shift.is_empty():
            lines.append("Оплаченная смена: нет данных")
        else:
            lines.append("Смена: тик %d · зарплата %d CR" % [
                int(shift.get("tick", 0)), int(shift.get("wages", 0))])
        var stock: Dictionary = live.get("module_stock", {}).get(
            "stock", {})
        if not stock.is_empty():
            lines.append("Ресурсы предприятия:")
            var goods: Array = stock.keys()
            goods.sort()
            for commodity in goods:
                if float(stock[commodity]) > 0.0:
                    lines.append(" • %s: %s" % [
                        str(commodity), str(stock[commodity])])
    else:
        lines.append("Нет подтверждённого состояния N39 для объекта")
    var ships: Dictionary = economy.get("ships", {})
    var docked_count: int = 0
    if orbital:
        for sid in ships:
            var ship: Dictionary = ships[sid]
            if str(ship.get("location", "")) == location and (
                    (ship.get("transit", {}) as Dictionary).is_empty()):
                docked_count += 1
        lines.append("Кораблей в общей локации: %d" % docked_count)
    lines.append("")
    lines.append("Логистический адрес: " + location)
    lines.append("Сейчас объекты Земли используют общий адрес")
    lines.append("в эталонной экономике. Отдельные перевозки")
    lines.append("поверхность ↔ орбита ещё не введены.")
    _details.text = "\n".join(lines)
    return true


func _show_body_details(world: Dictionary, shared_economy: Dictionary = {}) -> void:
    if not _selected_facility_id.is_empty():
        if _show_facility_details(world, shared_economy):
            return
    if not _selected_ship_id.is_empty():
        var fleet: Dictionary = shared_economy.get("ships", {})
        if fleet.is_empty():
            if _worker_mode:
                fleet = _worker_fleet
            elif _runner != null:
                fleet = _runner.fleet_snapshot()
        if _show_ship_details(fleet):
            return
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
        lines.append("Кораблей в исходной системе: %d · клик по кораблю открывает детали" %
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
    var economic: Dictionary = shared_economy
    if economic.is_empty():
        if _worker_mode:
            economic = _worker_economy
        elif _runner != null:
            economic = _runner.economy_snapshot()
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
    # Ships already belong to the same read-only N39 economy frame.
    # No second fleet_snapshot just to render a body inspector.
    var active_fleet: Dictionary = economic.get("ships", {})
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
    lines.append("Автономные N153/N84 решения выполняются; статус вылетов — в разделе Флот.")
    _details.text = "\n".join(lines)


## Read-only boot diagnostics for local Windows/Godot compatibility smoke.
## No gameplay mutation and no false claim that P2/P3 phases execute.
func startup_health() -> Dictionary:
    var booted: bool = (_worker_booted if _worker_mode
        else (_runner != null and _runner.is_started()))
    var has_map: bool = _map != null and is_instance_valid(_map)
    var has_ui: bool = _status != null and _details != null and _pause_button != null
    var seed_ok: bool = booted and _model != null and _model.seed_stats().get("systems", 0) == 8
    return {
        "ok": booted and has_map and has_ui and seed_ok and _startup_error.is_empty() and _fatal_restore_error.is_empty() and _worker_failed.is_empty(),
        "error": _startup_error,
        "godot_version": Engine.get_version_info().get("string", "unknown"),
        "booted": booted,
        "seed_ok": seed_ok,
        "map_ready": has_map,
        "ui_ready": has_ui,
        "tick": (_worker_tick if _worker_mode else _runner.tick_count) if booted else -1,
        "runtime_failure": _runtime_failure(),
        "fatal_restore_error": _fatal_restore_error,
        "worker_enabled": _worker_mode,
        "worker_failure": _worker_failed,
        "implemented_phases": (PackedStringArray(["N158_worker"]) if _worker_mode
            else (_runner.implemented_phases() if booted else PackedStringArray()))
    }

# Present one already-detached N39 frame, never request another snapshot here.
# UI aggregates explicit world market stocks, never creates faction resources.
func _sync_strategy_ui(shared_economy: Dictionary = {}) -> void:
    if _strategy_ui == null or _model == null:
        return
    var world: Dictionary = _model.system_by_id(_selected_system)
    if world.is_empty():
        return
    var tick: int = _worker_tick if _worker_mode else (
        _runner.tick_count if _runner != null else -1)
    var paused: bool = _worker_paused if _worker_mode else (
        _runner.clock.paused if _runner != null else false)
    var speed: float = _worker_speed if _worker_mode else (
        _runner.clock.world_speed if _runner != null else 1.0)
    _strategy_ui.present(world, shared_economy, _selected_body_id,
        _selected_facility_id, _selected_ship_id, tick, paused, speed,
        _status.text if _status != null else "",
        _details.text if _details != null else "",
        _worker_summary if _worker_mode else (
            _runner.native_autonomy_diagnostics()
            if _runner != null else {}))
