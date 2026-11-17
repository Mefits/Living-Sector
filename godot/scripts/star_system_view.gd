extends Control
## Read-only 2D view of one original Galaxy 0.6.7 system.
## Orbit radii are compressed for readability; native orbital angles are live.
## Station markers use native facility anchors. Fleet markers show ACTUAL
## ship locations from the same World; in-flight positions are not painted
## onto the visually compressed orbit map as if they were exact.

signal body_selected(body: Dictionary)
signal body_open_requested(body: Dictionary)
signal colony_facility_selected(facility_id: String)

const MIN_ZOOM: float = 0.45
const MAX_ZOOM: float = 32.0
const WHEEL_ZOOM: float = 1.32
const BACKGROUND: Color = Color("#0b1421")
const VisualMotion = preload("res://scripts/ui_source_motion_interpolator.gd")
const ColonyProjection = preload("res://scripts/view/colony_globe_projection.gd")
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
var _colony_data: Dictionary = {"nodes": [], "orbit": [], "links": []}
var _colony_pins: Array[Dictionary] = []
var _colony_time: float = 0.0
var _colony_redraw_accum: float = 0.0
var _colony_has_traffic: bool = false
var _focus_press: Vector2 = Vector2.ZERO
var _focus_drag_distance: float = 0.0
## U4: detached UI-only indices. The authoritative World is never mutated.
var _body_index: Dictionary = {}
var _facilities_by_body: Dictionary = {}
var _body_ids_by_location: Dictionary = {}
var _ships_by_body: Dictionary = {}
var _max_orbit_radius: float = 1.0
## Per-draw screen projection, invalidated on EVERY draw. Includes zoom,
## pan, viewport size and source angles; never reused across real ticks.
var _draw_body_positions: Dictionary = {}
var _last_draw_usec: int = 0
var _max_draw_usec: int = 0
var _draw_calls: int = 0
## Presentation-only Rust/Bevy InterpPos equivalent. These NEVER modify
## WorldModel, native orbit physics, N39 transit, N9 or checkpoints.
var _body_motion_from: Dictionary = {}
var _body_motion_started_usec: int = -1
var _body_motion_duration_usec: int = 0
var _last_body_commit_usec: int = -1
var _ship_motion_from: Dictionary = {}
var _ship_motion_started_usec: int = -1
var _ship_motion_duration_usec: int = 0
var _last_ship_commit_usec: int = -1
var _draw_now_usec: int = 0

func draw_profile() -> Dictionary:
    return {"calls": _draw_calls, "last_usec": _last_draw_usec,
        "max_usec": _max_draw_usec}

func _rebuild_body_index() -> void:
    _body_index.clear()
    _max_orbit_radius = 1.0
    for value in _world.get("bodies", []):
        if not (value is Dictionary):
            continue
        var body: Dictionary = value
        _body_index[str(body.get("id", ""))] = body
        _max_orbit_radius = maxf(_max_orbit_radius,
            float(body.get("orbit_radius", 0.0)))

func _rebuild_facility_index() -> void:
    _facilities_by_body.clear()
    _body_ids_by_location.clear()
    for value in _world.get("facilities", []):
        if not (value is Dictionary):
            continue
        var facility: Dictionary = value
        var bid: String = str(facility.get("body", ""))
        var location: String = str(facility.get("location", ""))
        _facilities_by_body[bid] = int(_facilities_by_body.get(bid, 0)) + 1
        if not _body_ids_by_location.has(location):
            _body_ids_by_location[location] = []
        var attached: Array = _body_ids_by_location[location]
        if not attached.has(bid):
            attached.append(bid)
    _rebuild_ship_index()

func _rebuild_ship_index() -> void:
    _ships_by_body.clear()
    for raw in _live_fleet.values():
        if not (raw is Dictionary):
            continue
        var ship: Dictionary = raw
        var transit: Variant = ship.get("transit", {})
        if not (transit is Dictionary) or not transit.is_empty():
            continue
        var location: String = str(ship.get("location", ""))
        for bid in _body_ids_by_location.get(location, []):
            _ships_by_body[bid] = int(_ships_by_body.get(bid, 0)) + 1


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true


func _process(delta: float) -> void:
    # Globe particles are decorative; no N158/N39 updates on draw frames.
    if not visible:
        return
    if is_body_focused():
        if _colony_has_traffic:
            _colony_time += minf(maxf(delta, 0.0), 0.05)
            _colony_redraw_accum += maxf(delta, 0.0)
            if _colony_redraw_accum >= 1.0 / 30.0:
                _colony_redraw_accum = 0.0
                queue_redraw()
        return
    var now_usec: int = Time.get_ticks_usec()
    if (not _body_motion_from.is_empty() and
            VisualMotion.alpha(_body_motion_started_usec,
                _body_motion_duration_usec, now_usec) < 1.0) or (
            not _ship_motion_from.is_empty() and
            VisualMotion.alpha(_ship_motion_started_usec,
                _ship_motion_duration_usec, now_usec) < 1.0):
        queue_redraw()


func set_world(world: Dictionary) -> void:
    _world = world.duplicate(true)
    _rebuild_body_index()
    _rebuild_facility_index()
    _selected_body_id = ""
    _focused_body_id = ""
    _colony_data = {"nodes": [], "orbit": [], "links": []}
    _colony_pins.clear()
    _colony_has_traffic = false
    _zoom = 1.0
    _pan = Vector2.ZERO
    _globe_zoom = 1.0
    _globe_pan = Vector2.ZERO
    # A newly opened system has no previous visual position. Snap to
    # the first real source snapshot; never glide between systems.
    _body_motion_from.clear()
    _body_motion_started_usec = -1
    _last_body_commit_usec = -1
    _ship_motion_from.clear()
    _ship_motion_started_usec = -1
    _last_ship_commit_usec = -1
    queue_redraw()


func set_live_fleet(fleet: Dictionary) -> void:
    # The caller's N158 fleet_snapshot is already detached. Retain ONLY
    # visual fields; no second clone of cargo, BT, wallets or provenance.
    var projected: Dictionary = {}
    for sid in fleet:
        var raw: Variant = fleet[sid]
        if not (raw is Dictionary):
            continue
        var ship: Dictionary = raw
        var transit: Variant = ship.get("transit", {})
        var visual_transit: Dictionary = {}
        if transit is Dictionary:
            visual_transit = (transit as Dictionary).duplicate(true)
        projected[sid] = {"location": str(ship.get("location", "")),
            "system_id": str(ship.get("system_id", "")),
            "class": str(ship.get("class", "")),
            "transit": visual_transit}
    if projected == _live_fleet:
        return
    var now_usec: int = Time.get_ticks_usec()
    var moving_origins: Dictionary = {}
    for sid in projected:
        if not _live_fleet.has(sid):
            continue
        var newer: Dictionary = projected[sid]
        var older: Dictionary = _live_fleet[sid]
        if str(newer.get("system_id", "")) != str(older.get("system_id", "")):
            continue # Different system: genuine transit discontinuity.
        var new_transit: Variant = newer.get("transit", {})
        var old_transit: Variant = older.get("transit", {})
        if not (new_transit is Dictionary) or not (old_transit is Dictionary):
            continue
        if new_transit.is_empty() or old_transit.is_empty():
            continue # Departure/arrival must NOT be animated as a fake flight.
        var old_position: Variant = _visual_ship_position(sid, older, now_usec)
        var new_position: Variant = new_transit.get("position", null)
        if VisualMotion.valid_xy(old_position) and (
                VisualMotion.valid_xy(new_position)) and (
                old_position != new_position):
            moving_origins[sid] = old_position
    _ship_motion_duration_usec = VisualMotion.sample_duration(
        _last_ship_commit_usec, now_usec, 160000)
    _ship_motion_started_usec = now_usec
    _last_ship_commit_usec = now_usec
    _ship_motion_from = moving_origins
    _live_fleet = projected
    _rebuild_ship_index()
    queue_redraw()

func update_world(world: Dictionary) -> void:
    if str(world.get("system", {}).get("id", "")) != str(_world.get("system", {}).get("id", "")):
        set_world(world)
        return
    # Native orbit angles can change each tick; static geometry usually
    # does not. Deep detach only changed visual domains, not whole World.
    var changed: bool = false
    if world.get("bodies", []) != _world.get("bodies", []):
        var now_usec: int = Time.get_ticks_usec()
        var visible_origins: Dictionary = {}
        for old_value in _world.get("bodies", []):
            if not (old_value is Dictionary):
                continue
            var old_body: Dictionary = old_value
            var body_id: String = str(old_body.get("id", ""))
            if not body_id.is_empty():
                visible_origins[body_id] = _visual_body_angle(
                    old_body, now_usec)
        _body_motion_duration_usec = VisualMotion.sample_duration(
            _last_body_commit_usec, now_usec, 160000)
        _body_motion_started_usec = now_usec
        _last_body_commit_usec = now_usec
        _body_motion_from = visible_origins
        _world["bodies"] = (world.get("bodies", []) as Array).duplicate(true)
        _rebuild_body_index()
        changed = true
    if world.get("facilities", []) != _world.get("facilities", []):
        _world["facilities"] = (world.get("facilities", []) as Array).duplicate(true)
        _rebuild_facility_index()
        changed = true
    if world.get("system", {}) != _world.get("system", {}):
        _world["system"] = (world.get("system", {}) as Dictionary).duplicate(true)
        changed = true
    if changed:
        queue_redraw()

func set_colony_projection(data: Dictionary) -> void:
    # Caller supplies ONLY the tiny detached per-body presentation model.
    if data == _colony_data:
        return
    _colony_data = data
    _colony_has_traffic = false
    for link in _colony_data.get("links", []):
        if int(link.get("activity", 0)) > 0:
            _colony_has_traffic = true
            break
    queue_redraw()


func select_body(body_id: String) -> void:
    if _selected_body_id == body_id:
        return
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
    _colony_data = {"nodes": [], "orbit": [], "links": []}
    _colony_pins.clear()
    _colony_has_traffic = false
    _colony_time = 0.0
    _globe_zoom = 1.0
    _globe_pan = Vector2.ZERO
    _dragging = false
    queue_redraw()
    return true


func unfocus_body() -> void:
    _focused_body_id = ""
    _colony_has_traffic = false
    _colony_pins.clear()
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
    return _body_index.get(body_id, {})

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
    var available: float = maxf(90.0, minf(size.x, size.y) * 0.40)
    return available / maxf(1.0, _radius_transform(_max_orbit_radius))

func _center() -> Vector2:
    return size * 0.5 + _pan


func _visual_body_angle(body: Dictionary, now_usec: int) -> float:
    var current: float = float(body.get("current_angle", 0.0))
    var bid: String = str(body.get("id", ""))
    if not _body_motion_from.has(bid):
        return current
    return VisualMotion.orbit_angle(float(_body_motion_from[bid]),
        current, VisualMotion.alpha(_body_motion_started_usec,
            _body_motion_duration_usec, now_usec))


func _visual_ship_position(sid: Variant, ship: Dictionary,
        now_usec: int) -> Variant:
    var transit: Variant = ship.get("transit", null)
    if not (transit is Dictionary):
        return null
    var current: Variant = transit.get("position", null)
    if not _ship_motion_from.has(sid):
        return current
    return VisualMotion.transit_position(_ship_motion_from[sid],
        current, VisualMotion.alpha(_ship_motion_started_usec,
            _ship_motion_duration_usec, now_usec))


func _body_position(body: Dictionary, scale: float) -> Vector2:
    var bid: String = str(body.get("id", ""))
    if not bid.is_empty() and _draw_body_positions.has(bid):
        return _draw_body_positions[bid]
    var radians: float = deg_to_rad(_visual_body_angle(
        body, _draw_now_usec))
    var parent: Dictionary = _known_moon_parent(body)
    var position: Vector2 = Vector2.ZERO
    if not parent.is_empty():
        position = _body_position(parent, scale) + Vector2(
            cos(radians), -sin(radians)) * _moon_visual_orbit(body, parent)
    else:
        var orbit: float = _radius_transform(float(
            body.get("orbit_radius", 0.0))) * scale * _zoom
        position = _center() + Vector2(cos(radians), -sin(radians)) * orbit
    if not bid.is_empty():
        _draw_body_positions[bid] = position
    return position


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
    return int(_facilities_by_body.get(body_id, 0))

func _live_ship_count(body_id: String) -> int:
    return int(_ships_by_body.get(body_id, 0))

func _draw() -> void:
    var started: int = Time.get_ticks_usec()
    _draw_now_usec = started
    _draw_body_positions.clear()
    if is_body_focused():
        _draw_body_focus()
    else:
        _draw_system()
    _last_draw_usec = maxi(0, Time.get_ticks_usec() - started)
    _max_draw_usec = maxi(_max_draw_usec, _last_draw_usec)
    _draw_calls += 1


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
    # Draw ONLY ships with a real committed N14 transit.position. The
    # radial display is compressed by the same source orbit transform as
    # the planets; there is no fabricated travel or per-frame motion.
    _draw_real_native_transits(system, scale)
    draw_string(font, Vector2(14.0, 26.0),
        "%s  /  %d тел  /  масштаб ×%.1f" % [str(system.get("name", "?")), bodies.size(), _zoom],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#dce8ee"))
    draw_string(font, Vector2(14.0, size.y - 14.0),
        "ЛКМ: выбрать · двойной клик / крупное колесо: глобус · колесо: орбиты · схематичный масштаб",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7d9cad"))


## Visual-only projection of N14's physical absolute world position.
## NativePositionResolver uses system.universe_offset + polar body orbit;
## the system diagram uses the same orbit with a nonlinear radial scale
## and flipped vertical screen axis. This function never advances travel,
## invents a route or changes the ship's canonical N39 location.
func _draw_real_native_transits(system: Dictionary,
        scale: float) -> void:
    var system_offset: Variant = system.get("universe_offset", null)
    if not (system_offset is Array) or system_offset.size() != 2:
        return
    if not (system_offset[0] is float or system_offset[0] is int) or (
            not (system_offset[1] is float or system_offset[1] is int)):
        return
    var offset: Vector2 = Vector2(float(system_offset[0]),
        float(system_offset[1]))
    var bounds: Rect2 = Rect2(Vector2.ZERO, size).grow(7.0)
    for sid in _live_fleet:
        var raw: Variant = _live_fleet[sid]
        if not (raw is Dictionary):
            continue
        var ship: Dictionary = raw
        if str(ship.get("system_id", "")) != str(system.get("id", "")):
            continue
        var transit: Variant = ship.get("transit", null)
        if not (transit is Dictionary) or transit.is_empty():
            continue
        var native_xy: Variant = _visual_ship_position(sid, ship,
            _draw_now_usec)
        if not (native_xy is Array) or native_xy.size() != 2:
            continue
        if not (native_xy[0] is int or native_xy[0] is float) or (
                not (native_xy[1] is int or native_xy[1] is float)):
            continue
        var physical: Vector2 = Vector2(float(native_xy[0]),
            float(native_xy[1])) - offset
        if not is_finite(physical.x) or not is_finite(physical.y):
            continue
        var distance: float = physical.length()
        var display: Vector2 = Vector2.ZERO
        if distance > 0.0:
            display = Vector2(physical.x, -physical.y) / distance * (
                _radius_transform(distance) * scale * _zoom)
        var screen: Vector2 = _center() + display
        if not bounds.has_point(screen):
            continue # Cross-system transfers are not painted in this map.
        var tone: Color = Color("#8ec9da")
        if str(ship.get("class", "")) == "miner":
            tone = Color("#9ecb95")
        elif str(ship.get("class", "")) == "freighter":
            tone = Color("#ddc287")
        draw_circle(screen, 3.4, tone)
        draw_arc(screen, 5.0, 0.0, TAU, 12, tone, 1.0, true)


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
    _draw_colony_on_focus(center, radius)
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
        "Колесо: размер · ЛКМ: выбрать/сдвиг · сеть и точки — визуальная активность",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#819cae"))


func _draw_colony_on_focus(center: Vector2, radius: float) -> void:
    _colony_pins.clear()
    var surface: Array = _colony_data.get("nodes", [])
    var orbital: Array = _colony_data.get("orbit", [])
    if surface.is_empty() and orbital.is_empty():
        return
    var hub: Vector2 = center + Vector2(-0.22, -0.24) * radius
    var positions: Dictionary = {"hub": hub}
    for entry in surface:
        positions[str(entry["id"])] = center + (entry["pos"] as Vector2) * radius
    for link in _colony_data.get("links", []):
        var a_id: String = str(link.get("a", ""))
        var b_id: String = str(link.get("b", ""))
        if not positions.has(a_id) or not positions.has(b_id):
            continue
        var a: Vector2 = positions[a_id]
        var b: Vector2 = positions[b_id]
        var is_chain: bool = str(link.get("kind", "")) == "production"
        draw_line(a, b, Color(0.57, 0.64, 0.60, 0.54 if is_chain else 0.72),
            maxf(1.0, radius * (0.009 if is_chain else 0.014)), true)
        var count: int = mini(6, int(link.get("activity", 0)))
        for index in range(count):
            var phase: float = fposmod(_colony_time * 0.16 +
                float(index) / float(count), 1.0)
            # Access road traffic commutes; production relation is one-way.
            if not is_chain:
                phase = 1.0 - absf(2.0 * phase - 1.0)
            draw_circle(a.lerp(b, phase), clampf(radius * 0.015, 1.5, 3.0),
                Color("#e1bd7e"))
    var font: Font = get_theme_default_font()
    if not surface.is_empty():
        draw_rect(Rect2(hub - Vector2(6, 6), Vector2(12, 12)), Color("#d1c39e"), true)
        draw_string(font, hub + Vector2(8, -8), "Узел",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e7e0ca"))
    for entry in surface:
        var point: Vector2 = positions[str(entry["id"])]
        var tint: Color = Color("#bdc9bd") if int(entry["activity"]) > 0 else Color("#718480")
        if bool(entry["abandoned"]):
            tint = Color("#725e62")
        draw_rect(Rect2(point - Vector2(5, 5), Vector2(10, 10)), tint, true)
        draw_rect(Rect2(point - Vector2(6, 6), Vector2(12, 12)),
            Color("#1b323b"), false, 1.0)
        _colony_pins.append({"id": str(entry["id"]), "position": point})
    # A real station remains an orbital object; its surface hub is only
    # a schematic road junction, not a second facility or invented AC.
    for i in range(orbital.size()):
        var entry: Dictionary = orbital[i]
        var point: Vector2 = center + Vector2(0.85, -0.76) * radius +
            Vector2(0.0, 23.0 * i)
        if i == 0:
            draw_line(center + Vector2(0.63, -0.62) * radius, point,
                Color(0.45, 0.57, 0.63, 0.5), 1.0, true)
        draw_rect(Rect2(point - Vector2(7, 5), Vector2(14, 10)),
            Color("#a9b8c4"), true)
        draw_string(font, point + Vector2(11, 4),
            str(entry["type"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color("#c3d1d8"))
        _colony_pins.append({"id": str(entry["id"]), "position": point})


func _pick_colony_facility(pointer: Vector2) -> void:
    var nearest: float = 14.0
    var chosen: String = ""
    for pin in _colony_pins:
        var distance: float = pointer.distance_to(pin["position"])
        if distance < nearest:
            nearest = distance
            chosen = str(pin["id"])
    colony_facility_selected.emit(chosen)


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
            if event.pressed:
                _dragging = true
                _focus_press = event.position
                _focus_drag_distance = 0.0
            else:
                if _dragging and _focus_drag_distance < 7.0:
                    _pick_colony_facility(event.position)
                _dragging = false
            accept_event()
    elif event is InputEventMouseMotion and _dragging:
        _focus_drag_distance += event.relative.length()
        _globe_pan += event.relative
        queue_redraw()
        accept_event()

