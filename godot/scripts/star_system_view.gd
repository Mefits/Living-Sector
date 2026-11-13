extends Control
## Read-only 2D view of one original Galaxy 0.6.7 system.
## Orbit radii are compressed for readability; native orbital angles are live.
## Station markers use native facility anchors. Fleet markers show ACTUAL
## ship locations from the same World; in-flight positions are not painted
## onto the visually compressed orbit map as if they were exact.

signal body_selected(body: Dictionary)

const MIN_ZOOM: float = 0.45
const MAX_ZOOM: float = 32.0
const WHEEL_ZOOM: float = 1.32
const BACKGROUND: Color = Color("#0b1421")

var _world: Dictionary = {}
var _live_fleet: Dictionary = {}
var _selected_body_id: String = ""
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_distance: float = 0.0
var _body_pins: Array = []


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true


func set_world(world: Dictionary) -> void:
    _world = world.duplicate(true)
    _selected_body_id = ""
    reset_view()


func set_live_fleet(fleet: Dictionary) -> void:
    _live_fleet = fleet.duplicate(true)
    queue_redraw()


func update_world(world: Dictionary) -> void:
    if str(world.get("system", {}).get("id", "")) != str(_world.get("system", {}).get("id", "")):
        set_world(world)
        return
    _world = world.duplicate(true)
    queue_redraw()


func select_body(body_id: String) -> void:
    _selected_body_id = body_id
    queue_redraw()


func reset_view() -> void:
    _zoom = 1.0
    _pan = Vector2.ZERO
    queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        queue_redraw()


func _star_color(star_type: String) -> Color:
    match star_type:
        "O", "B", "A":
            return Color("#a7d6ed")
        "F":
            return Color("#d7eaf1")
        "G":
            return Color("#f0d594")
        "K":
            return Color("#edb37c")
        "M":
            return Color("#df867a")
    return Color("#b4d1d9")


func _body_color(body: Dictionary) -> Color:
    match str(body.get("biome", "")):
        "terrestrial":
            return Color("#77bf99")
        "ice", "lifeless":
            return Color("#b0c7dc")
        "gas_giant":
            return Color("#c5a780")
        "molten":
            return Color("#d68b70")
        "desert":
            return Color("#c5ae83")
        "asteroid":
            return Color("#8796ad")
    return Color("#80b4c4")


func _radius_transform(radius: float) -> float:
    # Deliberate nonlinear display compression, NOT physical distance.
    return pow(maxf(radius, 0.0), 0.62)


func _orbit_scale() -> float:
    var max_radius: float = 1.0
    for body in _world.get("bodies", []):
        max_radius = maxf(max_radius, float(body.get("orbit_radius", 0.0)))
    var available: float = maxf(90.0, minf(size.x, size.y) * 0.40)
    return available / maxf(1.0, _radius_transform(max_radius))


func _center() -> Vector2:
    return size * 0.5 + _pan


func _body_position(body: Dictionary, scale: float) -> Vector2:
    var radians: float = deg_to_rad(float(body.get("current_angle", 0.0)))
    var orbit: float = _radius_transform(float(body.get("orbit_radius", 0.0))) * scale * _zoom
    return _center() + Vector2(cos(radians), -sin(radians)) * orbit


func _body_size(body: Dictionary) -> float:
    # The old diagram zoomed the orbit position but kept every planet at
    # 4–10 pixels, so close-up still looked distant. Symbol radius is
    # deliberately schematic and grows sublinearly, never by physical size.
    var symbol_scale: float = clampf(sqrt(_zoom), 0.8, 5.0)
    var kind: String = str(body.get("type", ""))
    if kind == "moon":
        return 4.0 * symbol_scale
    if kind == "asteroid" or kind == "belt":
        return 4.5 * symbol_scale
    if str(body.get("biome", "")) == "gas_giant":
        return 10.0 * symbol_scale
    return 6.5 * symbol_scale


func _facility_count(body_id: String) -> int:
    var result: int = 0
    for facility in _world.get("facilities", []):
        if str(facility.get("body", "")) == body_id:
            result += 1
    return result


func _live_ship_count(body_id: String) -> int:
    var locations: Dictionary = {}
    for facility in _world.get("facilities", []):
        if str(facility.get("body", "")) == body_id:
            locations[str(facility.get("location", ""))] = true
    var total: int = 0
    for ship_id in _live_fleet:
        var ship: Dictionary = _live_fleet[ship_id]
        if locations.has(str(ship.get("location", ""))) and ship.get("transit", {}).is_empty():
            total += 1
    return total


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
    _body_pins.clear()
    if _world.is_empty():
        return
    var system: Dictionary = _world.get("system", {})
    var star: Vector2 = _center()
    var scale: float = _orbit_scale()
    var font: Font = get_theme_default_font()
    var bodies: Array = _world.get("bodies", [])
    # The frozen source orbit_radius is relative to the system's origin; moons
    # have no native parent anchor, so no fictitious planet-moon orbit is drawn.
    for body in bodies:
        var radius: float = _radius_transform(float(body.get("orbit_radius", 0.0))) * scale * _zoom
        if radius > 1.0:
            draw_arc(star, radius, 0.0, TAU, 96, Color("#26394a"), 1.0, true)
    var star_size: float = 13.0 * clampf(sqrt(_zoom), 0.8, 4.0)
    draw_circle(star, star_size, _star_color(str(system.get("star_type", ""))))
    draw_circle(star, star_size + 5.0, Color("#526575"), false, 1.0, true)
    draw_string(font, star + Vector2(star_size + 8.0, -15.0), str(system.get("name", "")),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#f3e2bc"))
    for body in bodies:
        var position: Vector2 = _body_position(body, scale)
        var bid: String = str(body.get("id", ""))
        var picked: bool = bid == _selected_body_id
        var visual_radius: float = _body_size(body)
        var kind: String = str(body.get("type", ""))
        var color: Color = _body_color(body)
        if kind == "asteroid" or kind == "belt":
            var vertices: PackedVector2Array = PackedVector2Array([
                position + Vector2(0.0, -visual_radius),
                position + Vector2(visual_radius, 0.0),
                position + Vector2(0.0, visual_radius),
                position + Vector2(-visual_radius, 0.0)
            ])
            draw_colored_polygon(vertices, color)
        else:
            draw_circle(position, visual_radius, color)
        if picked:
            draw_arc(position, visual_radius + 7.0, 0.0, TAU, 40,
                Color("#a7eafa"), 1.8, true)
        var attached: int = _facility_count(bid)
        if attached > 0:
            # A small outlined square denotes a real seed facility/station
            # anchor; it does NOT imply that ship traffic is already active.
            draw_rect(Rect2(position + Vector2(visual_radius + 3.0, 4.0),
                Vector2(5.0, 5.0)), Color("#e5c98b"), true)
        var local_ships: int = _live_ship_count(bid)
        if local_ships > 0:
            # The marker represents real ships AT this location; active
            # transits are in the live observer, not fake diagram pixels.
            var ship_marker: PackedVector2Array = PackedVector2Array([
                position + Vector2(-visual_radius - 13.0, -3.0),
                position + Vector2(-visual_radius - 7.0, 0.0),
                position + Vector2(-visual_radius - 13.0, 3.0)
            ])
            draw_colored_polygon(ship_marker, Color("#7abacb"))
            draw_string(font, position + Vector2(-visual_radius - 25.0, 16.0),
                str(local_ships), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7abacb"))
        var label_offset: Vector2 = Vector2(visual_radius + 8.0, -8.0)
        draw_string(font, position + label_offset, str(body.get("name", bid)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
            Color("#f2f7fa") if picked else Color("#a9bbc8"))
        _body_pins.append({"body": body, "position": position, "hit_radius": maxf(22.0, visual_radius + 9.0)})
    draw_string(font, Vector2(14.0, 26.0),
        "%s  /  %d тел  /  масштаб ×%.1f" % [str(system.get("name", "?")), bodies.size(), _zoom],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#dce8ee"))
    draw_string(font, Vector2(14.0, size.y - 14.0),
        "ЛКМ: выбрать тело · перетаскивание: карта · колесо: масштаб · орбиты схематичны",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7d9cad"))


func _zoom_at(pointer: Vector2, multiplier: float) -> void:
    var previous: float = _zoom
    _zoom = clampf(_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
    var ratio: float = _zoom / previous
    _pan += (pointer - _center()) * (1.0 - ratio)
    queue_redraw()


func _pick(pointer: Vector2) -> void:
    var chosen: Dictionary = {}
    var nearest: float = INF
    for pin in _body_pins:
        var d: float = pointer.distance_to(pin["position"])
        if d <= float(pin.get("hit_radius", 22.0)) and d < nearest:
            nearest = d
            chosen = pin["body"]
    if chosen.is_empty():
        return
    select_body(str(chosen.get("id", "")))
    body_selected.emit(chosen.duplicate(true))


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
