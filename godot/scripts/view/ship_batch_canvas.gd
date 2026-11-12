extends Control
## N22 CODE_UNVERIFIED. One CanvasItem for all visible ship markers.
## Rendering only: model owns positions and IDs; no per-ship Node or _process.
signal ship_selected(ship_id: String)

const ShipBatchModel = preload("res://scripts/view/ship_batch_model.gd")
const MARKER_RADIUS: float = 4.0
const MIN_ZOOM: float = 0.05
const MAX_ZOOM: float = 64.0

var _model = ShipBatchModel.new()
var _center: Vector2 = Vector2.ZERO
var _zoom: float = 1.0
var _selected: String = ""
var _last_visible_count: int = 0

func _ready() -> void:
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP

func set_ships(records: Array) -> bool:
    if not _model.set_records(records):
        return false
    queue_redraw()
    return true

func set_camera(world_center: Vector2, zoom: float) -> bool:
    if not is_finite(world_center.x) or not is_finite(world_center.y):
        return false
    if not is_finite(zoom) or zoom <= 0.0:
        return false
    _center = world_center
    _zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
    queue_redraw()
    return true

func set_selected(ship_id: String) -> void:
    _selected = ship_id
    queue_redraw()

func visible_count() -> int:
    return _last_visible_count

func world_to_screen(point: Vector2) -> Vector2:
    return (point - _center) * _zoom + size * 0.5

func screen_to_world(point: Vector2) -> Vector2:
    return (point - size * 0.5) / _zoom + _center

func _viewport_rect() -> Rect2:
    return Rect2(screen_to_world(Vector2.ZERO), size / _zoom)

func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()

func _draw() -> void:
    var visible: Array[Dictionary] = _model.visible_records(_viewport_rect(), MARKER_RADIUS / _zoom)
    _last_visible_count = visible.size()
    for record in visible:
        var pos: Vector2 = world_to_screen(record["position"])
        var id: String = str(record["id"])
        var color: Color = Color("#8dc5da")
        match str(record["class"]).to_lower():
            "freighter", "cargo", "trader":
                color = Color("#d6bc7a")
            "miner", "mining":
                color = Color("#9fc18b")
            "patrol", "military":
                color = Color("#ce8d90")
        var radius: float = MARKER_RADIUS + (2.0 if id == _selected else 0.0)
        draw_circle(pos, radius, color)
        if id == _selected:
            draw_arc(pos, radius + 3.0, 0.0, TAU, 24, Color.WHITE, 1.0)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var id: String = _model.pick(screen_to_world(event.position), 9.0 / _zoom)
        if not id.is_empty():
            set_selected(id)
            ship_selected.emit(id)
            accept_event()
