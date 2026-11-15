extends Control
## Minimal 2D star map based strictly on native universe_offset coordinates.
## Coordinates are NOT light-years and drawn distances are NOT ship routes.

signal system_selected(world: Dictionary)
signal system_open_requested(world: Dictionary)

const MIN_ZOOM: float = 0.40
const MAX_ZOOM: float = 32.0
const WHEEL_ZOOM: float = 1.32

var worlds: Array = []
var _pins: Array = []
var _selected_id: String = ""
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _bounds_center: Vector2 = Vector2.ZERO
var _fit_scale: float = 1.0
var _dragging: bool = false
var _drag_distance: float = 0.0
## Sector geometry is immutable between explicit set_worlds / N38 reloads.
## Cache source coordinates but never change physical positions/routes.
var _source_positions: Array[Vector2] = []
var _bounds_extent: Vector2 = Vector2.ZERO
var _fit_dirty: bool = true
var _last_draw_usec: int = 0
var _max_draw_usec: int = 0
var _draw_calls: int = 0

func draw_profile() -> Dictionary:
    return {"calls": _draw_calls, "last_usec": _last_draw_usec,
        "max_usec": _max_draw_usec}

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true

func set_worlds(new_worlds: Array) -> void:
    worlds = new_worlds.duplicate(true)
    _zoom = 1.0
    _pan = Vector2.ZERO
    _recompute_bounds()
    _fit_dirty = true
    queue_redraw()

func select_system(system_id: String) -> void:
    if _selected_id == system_id:
        return
    _selected_id = system_id
    queue_redraw()

func reset_view() -> void:
    if is_equal_approx(_zoom, 1.0) and _pan == Vector2.ZERO:
        return
    _zoom = 1.0
    _pan = Vector2.ZERO
    queue_redraw()

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _fit_dirty = true
        queue_redraw()

func _native_position(item: Dictionary) -> Vector2:
    var system: Dictionary = item.get("system", {})
    var coordinates: Array = system.get("universe_offset", [0, 0])
    if coordinates.size() != 2:
        return Vector2.ZERO
    # Invert vertical axis only for screen-space display; keep source unchanged.
    return Vector2(float(coordinates[0]), -float(coordinates[1]))

func _recompute_bounds() -> void:
    _source_positions.clear()
    for item in worlds:
        _source_positions.append(_native_position(item))
    if _source_positions.is_empty():
        _bounds_center = Vector2.ZERO
        _bounds_extent = Vector2.ZERO
        return
    var min_pos: Vector2 = _source_positions[0]
    var max_pos: Vector2 = min_pos
    for point in _source_positions:
        min_pos = min_pos.min(point)
        max_pos = max_pos.max(point)
    _bounds_center = (min_pos + max_pos) * 0.5
    _bounds_extent = (max_pos - min_pos) * 0.5

func _update_fit() -> void:
    if not _fit_dirty:
        return
    _fit_dirty = false
    var avail: Vector2 = Vector2(maxf(size.x - 150.0, 80.0),
        maxf(size.y - 105.0, 80.0))
    _fit_scale = minf(avail.x / maxf(_bounds_extent.x * 2.0, 1.0),
        avail.y / maxf(_bounds_extent.y * 2.0, 1.0))

func _screen_point(source_position: Vector2) -> Vector2:
    return size * 0.5 + (source_position - _bounds_center) * (
        _fit_scale * _zoom) + _pan

func _draw() -> void:
    var started: int = Time.get_ticks_usec()
    _draw_map()
    _last_draw_usec = maxi(0, Time.get_ticks_usec() - started)
    _max_draw_usec = maxi(_max_draw_usec, _last_draw_usec)
    _draw_calls += 1

func _draw_map() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1421"), true)
    _pins.clear()
    if worlds.is_empty():
        return
    _update_fit()
    var font: Font = get_theme_default_font()
    for index in range(worlds.size()):
        var item: Dictionary = worlds[index]
        var system: Dictionary = item.get("system", {})
        var pos: Vector2 = _screen_point(_source_positions[index])
        var selected: bool = str(system.get("id", "")) == _selected_id
        var orbit_color: Color = Color("#81c8d8") if selected else Color("#344c63")
        # Symbols grow mildly with map zoom; they remain pickable even
        # when native universe_offset distances become very spread out.
        var marker_scale: float = clampf(sqrt(_zoom), 0.8, 2.6)
        draw_arc(pos, 16.0 * marker_scale, 0.0, TAU, 32, orbit_color, 1.5)
        draw_circle(pos, (6.0 if selected else 4.5) * marker_scale,
            Color("#b5edfc") if selected else Color("#6c9eac"))
        draw_string(font, pos + Vector2(13.0 * marker_scale, -10),
            str(system.get("name", "—")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
            Color("#e5f1f7"))
        _pins.append({"world": item, "pos": pos, "hit_radius": maxf(25.0, 16.0 * marker_scale + 8.0)})
    draw_string(font, Vector2(14, size.y - 16),
        "ЛКМ: выбрать / двигать · двойной клик: открыть · колесо: масштаб ×%.1f" % _zoom,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7d9cad"))

func _zoom_at(pointer: Vector2, multiplier: float) -> void:
    var old_zoom: float = _zoom
    _zoom = clampf(_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
    var ratio: float = _zoom / old_zoom
    var offset: Vector2 = pointer - size * 0.5 - _pan
    _pan += offset * (1.0 - ratio)
    queue_redraw()

func _pick(point: Vector2, open_system: bool = false) -> void:
    var best_distance: float = INF
    var best: Dictionary = {}
    for pin in _pins:
        var distance: float = point.distance_to(pin["pos"])
        if distance <= float(pin.get("hit_radius", 25.0)) and distance < best_distance:
            best_distance = distance
            best = pin["world"]
    if best.is_empty():
        return
    var system: Dictionary = best.get("system", {})
    select_system(str(system.get("id", "")))
    system_selected.emit(best.duplicate(true))
    if open_system:
        system_open_requested.emit(best.duplicate(true))

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom_at(event.position, WHEEL_ZOOM)
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom_at(event.position, 1.0 / WHEEL_ZOOM)
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                if event.double_click:
                    _dragging = false
                    _pick(event.position, true)
                else:
                    _dragging = true
                    _drag_distance = 0.0
            else:
                if _dragging and _drag_distance < 7.0:
                    _pick(event.position)
                _dragging = false
            accept_event()
    elif event is InputEventMouseMotion and _dragging:
        _drag_distance += event.relative.length()
        _pan += event.relative
        queue_redraw()
        accept_event()
