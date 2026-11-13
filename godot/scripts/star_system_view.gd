extends Control
## Read-only 2D view of one original Galaxy 0.6.7 system.
## Orbit radii are compressed for readability; native orbital angles are live.
## Station markers use native facility anchors. Fleet markers show ACTUAL
## ship locations from the same World; in-flight positions are not painted
## onto the visually compressed orbit map as if they were exact.

signal body_selected(body: Dictionary)
signal body_open_requested(body: Dictionary)

const MIN_ZOOM: float = 0.45
const MAX_ZOOM: float = 32.0
const WHEEL_ZOOM: float = 1.32
const BACKGROUND: Color = Color("#0b1421")
## A visual-only relationship for two real, unambiguous astronomical moons.
## Native Galaxy 0.6.7 stores heliocentric radius/period/angle for ALL
## bodies and has NO parent identifier. Do not rewrite Rust orbit physics.
## Unknown fictional moons (e.g. Wreckhold) are never attached by guess.
const KNOWN_VISUAL_MOON_PARENTS: Dictionary = {
    "luna": "earth",
    "callisto": "jupiter"
}
const SEMANTIC_FOCUS_ZOOM: float = 5.0
const GLOBE_MIN_ZOOM: float = 0.85
const GLOBE_MAX_ZOOM: float = 1.8

var _world: Dictionary = {}
var _live_fleet: Dictionary = {}
var _selected_body_id: String = ""
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_distance: float = 0.0
var _body_pins: Array = []
var _focused_body_id: String = ""
var _globe_zoom: float = 1.0
var _globe_pan: Vector2 = Vector2.ZERO


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true


func set_world(world: Dictionary) -> void:
    _world = world.duplicate(true)
    _selected_body_id = ""
    _focused_body_id = ""
    _zoom = 1.0
    _pan = Vector2.ZERO
    _globe_zoom = 1.0
    _globe_pan = Vector2.ZERO
    queue_redraw()


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


func is_body_focused() -> bool:
    return not _focused_body_id.is_empty()


func focus_body(body_id: String) -> bool:
    var body: Dictionary = _body_by_id(body_id)
    if body.is_empty():
        return false
    # A single real world object is shown at globe scale. No extra World.
    _selected_body_id = body_id
    _focused_body_id = body_id
    _globe_zoom = 1.0
    _globe_pan = Vector2.ZERO
    _dragging = false
    queue_redraw()
    return true


func unfocus_body() -> void:
    _focused_body_id = ""
    _globe_pan = Vector2.ZERO
    _globe_zoom = 1.0
    _dragging = false
    queue_redraw()


func reset_view() -> void:
    if is_body_focused():
        _globe_zoom = 1.0
        _globe_pan = Vector2.ZERO
    else:
        _zoom = 1.0
        _pan = Vector2.ZERO
    queue_redraw()


func _body_by_id(body_id: String) -> Dictionary:
    for body in _world.get("bodies", []):
        if str(body.get("id", "")) == body_id:
            return body
    return {}


func _known_moon_parent(body: Dictionary) -> Dictionary:
    if str(body.get("type", "")) != "moon":
        return {}
    # Prefer future explicit imported metadata; known real moons use a
    # rendering-only parent mapping until the simulation schema supports it.
    var parent_id: String = str(body.get("parent_body_id",
        KNOWN_VISUAL_MOON_PARENTS.get(str(body.get("id", "")), "")))
    var parent: Dictionary = _body_by_id(parent_id)
    if parent.is_empty() or str(parent.get("type", "")) != "planet":
        return {}
    return parent


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
    var parent: Dictionary = _known_moon_parent(body)
    if not parent.is_empty():
        var origin: Vector2 = _body_position(parent, scale)
        return origin + Vector2(cos(radians), -sin(radians)) * _moon_visual_orbit(body, parent)
    var orbit: float = _radius_transform(float(body.get("orbit_radius", 0.0))) * scale * _zoom
    return _center() + Vector2(cos(radians), -sin(radians)) * orbit


func _moon_visual_orbit(body: Dictionary, parent: Dictionary) -> float:
    # Deliberately schematic screen separation. Parent is now the moving
    # center; the LIVE native current_angle still advances from TickRunner.
    # Frozen orbit_period is NOT a true month, so never label it as one.
    var delta: float = absf(float(body.get("orbit_radius", 0.0)) -
        float(parent.get("orbit_radius", 0.0)))
    var base: float = 26.0 + minf(delta, 1.0) * 18.0
    return maxf(_body_size(parent) + 16.0,
        base * clampf(sqrt(_zoom), 1.0, 5.0))


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
    if is_body_focused():
        _draw_body_focus()
    else:
        _draw_system()


func _draw_system() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
    _body_pins.clear()
    if _world.is_empty():
        return
    var system: Dictionary = _world.get("system", {})
    var star: Vector2 = _center()
    var scale: float = _orbit_scale()
    var font: Font = get_theme_default_font()
    var bodies: Array = _world.get("bodies", [])
    # Source planets circle the star. Known real moon visual paths circle
    # their ACTUAL moving parent instead. An unnamed fictional moon with
    # no parent in frozen data stays on its legacy schematic source orbit.
    for body in bodies:
        var parent: Dictionary = _known_moon_parent(body)
        if not parent.is_empty():
            draw_arc(_body_position(parent, scale),
                _moon_visual_orbit(body, parent), 0.0, TAU,
                72, Color("#35495a"), 1.0, true)
            continue
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
        "ЛКМ: выбрать · двойной клик / крупное колесо: глобус · колесо: орбиты · схематичный масштаб",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7d9cad"))


func _zoom_at(pointer: Vector2, multiplier: float) -> void:
    var previous: float = _zoom
    _zoom = clampf(_zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
    var ratio: float = _zoom / previous
    _pan += (pointer - _center()) * (1.0 - ratio)
    queue_redraw()


func _pick(pointer: Vector2, open_body: bool = false) -> void:
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
    if open_body:
        body_open_requested.emit(chosen.duplicate(true))


func _nearest_pin(pointer: Vector2) -> Dictionary:
    var nearest: float = INF
    var chosen: Dictionary = {}
    for pin in _body_pins:
        var d: float = pointer.distance_to(pin["position"])
        if d <= float(pin.get("hit_radius", 22.0)) and d < nearest:
            nearest = d
            chosen = pin["body"]
    return chosen


func _gui_input(event: InputEvent) -> void:
    if is_body_focused():
        _focus_input(event)
        return
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            if _zoom >= SEMANTIC_FOCUS_ZOOM and not _nearest_pin(event.position).is_empty():
                _pick(event.position, true)
            else:
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

## Semantic level 3: decorative 2D globe, NOT a fabricated terrain/colony
## simulation. No nine slots, no fake building coordinates. Native physical
## body and real facility/resource data remain in the existing inspector.
func _draw_body_focus() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
    var body: Dictionary = _body_by_id(_focused_body_id)
    if body.is_empty():
        return
    var font: Font = get_theme_default_font()
    var biome: String = str(body.get("biome", ""))
    var radius: float = maxf(105.0, minf(205.0, minf(size.x, size.y) * 0.29)) * _globe_zoom
    var center: Vector2 = size * 0.5 + _globe_pan
    var base: Color = _body_color(body)
    draw_circle(center, radius + 2.0, Color("#283b4b"))
    draw_circle(center, radius, base)
    if biome == "terrestrial":
        # Minimal, source-independent surface illustration: NOT a map of
        # actual native land or claimed building locations.
        var land: Color = Color("#789c7d")
        var shape_a: PackedVector2Array = PackedVector2Array([
            center + Vector2(-0.70, -0.35) * radius,
            center + Vector2(-0.34, -0.72) * radius,
            center + Vector2(0.09, -0.73) * radius,
            center + Vector2(0.26, -0.44) * radius,
            center + Vector2(0.08, -0.12) * radius,
            center + Vector2(-0.26, -0.03) * radius,
            center + Vector2(-0.43, 0.30) * radius,
            center + Vector2(-0.67, 0.20) * radius
        ])
        var shape_b: PackedVector2Array = PackedVector2Array([
            center + Vector2(0.37, -0.05) * radius,
            center + Vector2(0.66, 0.00) * radius,
            center + Vector2(0.86, 0.35) * radius,
            center + Vector2(0.56, 0.65) * radius,
            center + Vector2(0.20, 0.75) * radius,
            center + Vector2(0.10, 0.30) * radius
        ])
        draw_colored_polygon(shape_a, land)
        draw_colored_polygon(shape_b, Color("#9bb38a"))
        draw_circle(center + Vector2(-0.17, 0.41) * radius,
            0.15 * radius, Color("#5689a3"))
    elif biome == "gas_giant":
        for band in [-0.70, -0.39, -0.06, 0.22, 0.57]:
            var y: float = float(band) * radius
            var half: float = sqrt(maxf(0.0, radius * radius - y * y)) * 0.92
            draw_line(center + Vector2(-half, y),
                center + Vector2(half, y), Color("#917d70"), maxf(2.0, radius * 0.065))
    elif biome in ["lifeless", "ice"]:
        draw_circle(center + Vector2(-0.32, -0.20) * radius,
            0.16 * radius, Color("#809aad"))
        draw_circle(center + Vector2(0.36, 0.31) * radius,
            0.10 * radius, Color("#90a9bd"))
    elif biome in ["molten", "desert"]:
        draw_arc(center + Vector2(0.10, -0.15) * radius,
            radius * 0.51, 0.50, 2.75, 44, Color("#e4b08c"), maxf(2.0, radius * 0.02))
    # A muted visible terminator, without gradients or glossy highlights.
    draw_arc(center, radius, 0.18 * PI, 1.15 * PI, 70,
        Color("#192a39"), maxf(2.0, radius * 0.025))
    var name: String = str(body.get("name", _focused_body_id))
    draw_string(font, Vector2(18.0, 31.0),
        name + "  /  " + str(body.get("type", "?")), HORIZONTAL_ALIGNMENT_LEFT,
        -1, 19, Color("#ebf2f4"))
    var parent: Dictionary = _known_moon_parent(body)
    if not parent.is_empty():
        draw_string(font, Vector2(18.0, 54.0),
            "Спутник " + str(parent.get("name", "планеты")) +
            " · орбита вокруг планеты показана условно",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#a9c5d4"))
    elif str(body.get("type", "")) == "moon":
        draw_string(font, Vector2(18.0, 54.0),
            "Родитель неизвестен в источнике — орбита не моделируется",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#d7b88c"))
    draw_string(font, Vector2(18.0, size.y - 40.0),
        "Биом: " + biome + "  ·  объектов: " + str(_facility_count(_focused_body_id)),
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#cbdce6"))
    draw_string(font, Vector2(18.0, size.y - 17.0),
        "Колесо: размер глобуса · ЛКМ: сдвиг · назад: к орбитам · поверхность схематична",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#819cae"))


func _focus_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
            _globe_zoom = clampf(_globe_zoom * 1.16, GLOBE_MIN_ZOOM, GLOBE_MAX_ZOOM)
            queue_redraw()
            accept_event()
        elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _globe_zoom = clampf(_globe_zoom / 1.16, GLOBE_MIN_ZOOM, GLOBE_MAX_ZOOM)
            queue_redraw()
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            _dragging = event.pressed
            accept_event()
    elif event is InputEventMouseMotion and _dragging:
        _globe_pan += event.relative
        queue_redraw()
        accept_event()

