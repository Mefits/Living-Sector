extends Control
## Read-only continuous camera over a Galaxy 0.6.7 system.
## Display radii are schematic but all orbital screen separations use one
## camera zoom. Native N14/N39 positions and orbital angles are untouched.
## Facility markers remain attached to real source body identities.

signal body_selected(body: Dictionary)
signal body_open_requested(body: Dictionary)
signal ship_selected(ship_id: String)
signal facility_selected(facility_id: String)

const MIN_ZOOM: float = 0.45
const MAX_ZOOM: float = 512.0
const FOCUS_GLOBE_RADIUS: float = 165.0
const CAMERA_EASING: float = 12.0
const DETAIL_RADIUS: float = 24.0
const SURFACE_REVEAL_WHEEL_STEPS: float = 2.0
const WHEEL_ZOOM: float = 1.32
## Agreed Sol Lab 01 baseline: compress EMPTY map space, not world physics.
const ORBIT_COMPRESSION: float = 0.65
## Recursive local-space visual projection for parented satellites.
## Smaller than the stellar exponent so moons emerge during planet zoom;
## the parent/satellite relation comes from physical distance metadata.
const SATELLITE_COMPRESSION: float = 0.50
const KM_PER_AU: float = 149597870.7
## The frozen Sol seed encodes Earth orbit_radius=2 for 1 AU.
const SOL_NATIVE_UNITS_PER_AU: float = 2.0
## Data-only Sol presentation metadata absent from frozen native seed.
## No simulation change: later replace with body.parent_body_id and local orbit.
const SOL_SATELLITE_ORBIT_KM: Dictionary = {
    "luna": 384400.0,
    "callisto": 1882700.0
}
const SOL_BODY_RADII_KM: Dictionary = {
    "mercury": 2439.7, "venus": 6051.8, "earth": 6371.0,
    "luna": 1737.4, "mars": 3389.5, "jupiter": 69911.0,
    "saturn": 58232.0, "callisto": 2410.3
}
const BACKGROUND: Color = Color("#0b1421")
## Orbit paths are orientation guides, not the main visual subject.
## Suppress them near planet detail scale without changing any geometry.
const ORBIT_LINE_OPACITY: float = 0.30
const SATELLITE_ORBIT_LINE_OPACITY: float = 0.25
const ORBIT_FADE_BEGIN_ZOOM: float = 8.0
const VisualMotion = preload("res://scripts/ui_source_motion_interpolator.gd")
const StationShipProjection = preload("res://scripts/ui_station_ship_projection.gd")
const SolAssets = preload("res://scripts/sim/phase2/sol_physical_assets_projection.gd")
const N43 = preload("res://scripts/sim/ships/native_location_resolver.gd")
const SolOrbits = preload("res://scripts/sim/orbits/native_satellite_orbit_profiles.gd")
## A visual-only relationship for two real, unambiguous astronomical moons.
## Native Galaxy 0.6.7 stores heliocentric radius/period/angle for ALL
## bodies and has NO parent identifier. Do not rewrite Rust orbit physics.
## Unknown fictional moons (e.g. Wreckhold) are never attached by guess.
const KNOWN_VISUAL_MOON_PARENTS: Dictionary = {
    "luna": "earth",
    "callisto": "jupiter"
}

var _world: Dictionary = {}
var _live_fleet: Dictionary = {}
var _selected_body_id: String = ""
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _drag_distance: float = 0.0
var _body_pins: Array = []
var _focused_body_id: String = ""
## Camera-only animation; never writes into physical World/N39.
var _wheel_target_zoom: float = -1.0
var _wheel_anchor: Vector2 = Vector2.ZERO
var _focus_zoom_target: float = -1.0
var _return_camera: bool = false
## Wheel proximity chooses a real body; no artificial zoom-level scene swap.
var _zoom_candidate_body_id: String = ""
## The previously projected orbit offset lets the camera compensate *every*
## body movement, even during fast N158 ticks and wheel interpolation.
var _follow_orbit_offset: Vector2 = Vector2.ZERO
var _follow_orbit_valid: bool = false
## U4: detached UI-only indices. The authoritative World is never mutated.
var _body_index: Dictionary = {}
var _facilities_by_body: Dictionary = {}
var _body_ids_by_location: Dictionary = {}
var _ships_by_body: Dictionary = {}
var _ship_ids_by_body: Dictionary = {}
var _ship_ids_by_location: Dictionary = {}
var _ship_pins: Array = []
var _selected_ship_id: String = ""
var _selected_facility_id: String = ""
var _physical_assets: Dictionary = {"orbital": [], "surface": []}
var _live_facility_status: Dictionary = {}
var _facility_pins: Array = []
## Bounded screen records of real Sol stations. Never N39 objects or nodes.
var _station_draw_records: Array = []
## At most one ephemeral UI interpolation per actual arrival receipt.
var _recent_arrivals: Dictionary = {}
var _native_station_time: float = 0.0
var _native_station_time_from: float = 0.0
var _station_time_started_usec: int = -1
var _station_time_duration_usec: int = 0
var _last_station_sample_usec: int = -1
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
    _physical_assets = SolAssets.build(_world)
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
    _ship_ids_by_body.clear()
    _ship_ids_by_location.clear()
    var ids: Array = _live_fleet.keys()
    ids.sort()
    for sid in ids:
        var raw: Variant = _live_fleet[sid]
        if not (raw is Dictionary):
            continue
        var ship: Dictionary = raw
        var transit: Variant = ship.get("transit", {})
        if not (transit is Dictionary) or not transit.is_empty():
            continue
        var location: String = str(ship.get("location", ""))
        if not location.is_empty():
            if not _ship_ids_by_location.has(location):
                _ship_ids_by_location[location] = []
            (_ship_ids_by_location[location] as Array).append(str(sid))
        for bid in _body_ids_by_location.get(location, []):
            _ships_by_body[bid] = int(_ships_by_body.get(bid, 0)) + 1
            if not _ship_ids_by_body.has(bid):
                _ship_ids_by_body[bid] = []
            (_ship_ids_by_body[bid] as Array).append(str(sid))


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true


func _process(delta: float) -> void:
    if not visible:
        return
    var camera_changed: bool = false
    var ease: float = 1.0 - exp(-clampf(delta, 0.0, 0.1) * CAMERA_EASING)
    if _return_camera:
        _zoom = lerpf(_zoom, 1.0, ease)
        _pan = _pan.lerp(Vector2.ZERO, ease)
        camera_changed = true
        if absf(_zoom - 1.0) < 0.005 and _pan.length() < 0.5:
            _zoom = 1.0
            _pan = Vector2.ZERO
            _return_camera = false
    elif _focus_zoom_target > 0.0 and not _focused_body_id.is_empty():
        # Double-click animation changes zoom, but the tracking block below
        # owns the camera position for both double-click and wheel focus.
        _zoom = lerpf(_zoom, _focus_zoom_target, ease)
        camera_changed = true
        if absf(_zoom - _focus_zoom_target) < 0.01:
            _zoom = _focus_zoom_target
            _focus_zoom_target = -1.0
    elif _wheel_target_zoom > 0.0:
        var next_zoom_wheel: float = lerpf(_zoom, _wheel_target_zoom, ease)
        var ratio: float = next_zoom_wheel / maxf(_zoom, 0.001)
        # Follow mode anchors the real body; free zoom anchors the pointer.
        if _focused_body_id.is_empty():
            _pan += (_wheel_anchor - _center()) * (1.0 - ratio)
        _zoom = next_zoom_wheel
        camera_changed = true
        if absf(_zoom - _wheel_target_zoom) < 0.005:
            _zoom = _wheel_target_zoom
            _wheel_target_zoom = -1.0

    # Enter follow automatically when the body under the zoom cursor reaches
    # the SAME radius that begins drawing surface details. Never a new map.
    if not _zoom_candidate_body_id.is_empty() and _focused_body_id.is_empty() and not _return_camera:
        var candidate: Dictionary = _body_by_id(_zoom_candidate_body_id)
        if not candidate.is_empty() and _body_size(candidate) >= DETAIL_RADIUS:
            _focused_body_id = _zoom_candidate_body_id
            _follow_orbit_valid = false

    if not _focused_body_id.is_empty() and not _return_camera:
        var focused: Dictionary = _body_by_id(_focused_body_id)
        if focused.is_empty():
            _focused_body_id = ""
            _follow_orbit_valid = false
        else:
            # _body_position returns viewport_center + pan + orbit_offset.
            # Project fresh each frame because native angles interpolate.
            _draw_now_usec = Time.get_ticks_usec()
            _draw_body_positions.clear()
            var pan_before_follow: Vector2 = _pan
            var screen_position: Vector2 = _body_position(focused, _orbit_scale())
            var orbit_offset: Vector2 = screen_position - _center()
            if _follow_orbit_valid:
                # Cancel orbital motion exactly before centering; otherwise
                # the body drifts out during accelerated simulated time.
                _pan -= orbit_offset - _follow_orbit_offset
            _follow_orbit_offset = orbit_offset
            _follow_orbit_valid = true
            var desired_pan: Vector2 = -orbit_offset
            var remaining: Vector2 = desired_pan - _pan
            if remaining.length() < 1.5:
                _pan = desired_pan
            else:
                # Smooth *initial* acquisition, not orbital movement itself.
                _pan += remaining * ease
            # Following a stationary body while paused must not force a
            # continuous redraw or unnecessary FPS/CPU load.
            if _pan.distance_to(pan_before_follow) > 0.005:
                camera_changed = true

    var now_usec: int = Time.get_ticks_usec()
    for sid in _recent_arrivals.keys():
        var row: Dictionary = _recent_arrivals[sid]
        if VisualMotion.alpha(int(row["started_usec"]),
                int(row["duration_usec"]), now_usec) >= 1.0:
            _recent_arrivals.erase(sid)
    if camera_changed or not _recent_arrivals.is_empty() or (
            _station_time_started_usec >= 0 and (
            VisualMotion.alpha(_station_time_started_usec,
                _station_time_duration_usec, now_usec) < 1.0)) or (
            not _body_motion_from.is_empty() and
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
    _selected_ship_id = ""
    _selected_facility_id = ""
    _ship_pins.clear()
    _facility_pins.clear()
    _station_draw_records.clear()
    _recent_arrivals.clear()
    _live_facility_status.clear()
    _native_station_time = 0.0
    _native_station_time_from = 0.0
    _station_time_started_usec = -1
    _focused_body_id = ""
    _zoom = 1.0
    _pan = Vector2.ZERO
    _wheel_target_zoom = -1.0
    _focus_zoom_target = -1.0
    _return_camera = false
    _zoom_candidate_body_id = ""
    _follow_orbit_valid = false
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
        if transit is Dictionary and not transit.is_empty():
            # Only the two coordinates are needed for drawing. Duplicating
            # each N14 receipt (route, fuel, token, trajectory, etc.) on
            # every UI update scales unnecessarily with a large fleet.
            # Keep nonempty transit status even if its point is malformed:
            # an in-flight vessel must never appear as docked instead.
            var point: Variant = transit.get("position", null)
            if point is Array and (point as Array).size() == 2:
                visual_transit = {"position": [point[0], point[1]]}
                # Selected ship only. Never copy hundreds of unrelated
                # route receipts into the hot UI frame.
                if str(sid) == _selected_ship_id:
                    var points: Variant = transit.get(
                        "navigation_waypoints", [])
                    if points is Array and (points as Array).size() <= 24:
                        visual_transit["navigation_waypoints"] = (
                            points as Array).duplicate(true)
            else:
                visual_transit = {"invalid_position": true}
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
        if old_transit.is_empty() and not new_transit.is_empty():
            # A genuine N14 receipt carries its actual physical launch
            # coordinate. Interpolate only between two committed points,
            # never generate a synthetic undock path or free movement.
            var live_row: Variant = fleet.get(sid, {})
            if live_row is Dictionary:
                var source_receipt: Variant = live_row.get("transit", {})
                if source_receipt is Dictionary:
                    var real_start: Variant = source_receipt.get(
                        "departure_position", null)
                    if VisualMotion.valid_xy(real_start):
                        moving_origins[sid] = real_start
            continue
        if new_transit.is_empty() and not old_transit.is_empty():
            # Preserve the last REAL N14 position for a single transition
            # into its N43 station marker after the canonical arrival.
            # The native movement has already been paid and committed.
            var arrival_location: String = str(
                newer.get("location", ""))
            var source_last: Variant = _visual_ship_position(
                sid, older, now_usec)
            if VisualMotion.valid_xy(source_last) and (
                    _is_sol_station_location(arrival_location)):
                var dock_native: Dictionary = _station_native_location(
                    arrival_location)
                if dock_native.get("ok", false):
                    var from_xy: Vector2 = Vector2(
                        float(source_last[0]), float(source_last[1]))
                    if from_xy.distance_to(dock_native["position"]) <= 0.15:
                        _recent_arrivals[sid] = {
                            "from": [from_xy.x, from_xy.y],
                            "location": arrival_location,
                            "started_usec": now_usec,
                            "duration_usec": VisualMotion.sample_duration(
                                _last_ship_commit_usec, now_usec, 160000)
                        }
            continue
        if new_transit.is_empty() or old_transit.is_empty():
            continue
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
    if not _selected_ship_id.is_empty() and not _live_fleet.has(
            _selected_ship_id):
        _selected_ship_id = ""
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

func select_body(body_id: String) -> void:
    if _selected_body_id == body_id and _selected_ship_id.is_empty() and (
            _selected_facility_id.is_empty()):
        return
    _selected_body_id = body_id
    _selected_ship_id = ""
    _selected_facility_id = ""
    queue_redraw()

func select_facility(facility_id: String) -> void:
    var found: bool = false
    for group in ["orbital", "surface"]:
        for facility in _physical_assets.get(group, []):
            if str(facility.get("id", "")) == facility_id:
                found = true
                break
    if not found:
        return
    _selected_facility_id = facility_id
    _selected_ship_id = ""
    _selected_body_id = ""
    queue_redraw()


## One native scalar from the real N158 calendar, not another simulation.
## The station uses exactly the N43 initial phase and orbit period.
func set_native_station_time(native_units: float) -> void:
    if not is_finite(native_units) or native_units < 0.0:
        return
    if is_equal_approx(_native_station_time, native_units):
        return
    var now: int = Time.get_ticks_usec()
    _native_station_time_from = _visual_station_time(now)
    _native_station_time = native_units
    _station_time_duration_usec = VisualMotion.sample_duration(
        _last_station_sample_usec, now, 160000)
    _station_time_started_usec = now
    _last_station_sample_usec = now
    queue_redraw()


func _visual_station_time(now: int) -> float:
    if _station_time_started_usec < 0:
        return fposmod(_native_station_time * 360.0 /
            N43.FACILITY_ORBIT_PERIOD, 360.0)
    var alpha: float = VisualMotion.alpha(_station_time_started_usec,
        _station_time_duration_usec, now)
    # Interpolate orbital PHASE rather than huge absolute time when
    # accelerated ticks skip multiple station revolutions.
    var from_angle: float = fposmod(
        _native_station_time_from * 360.0 / N43.FACILITY_ORBIT_PERIOD, 360.0)
    var current_angle: float = fposmod(
        _native_station_time * 360.0 / N43.FACILITY_ORBIT_PERIOD, 360.0)
    return VisualMotion.orbit_angle(from_angle, current_angle, alpha)


func set_live_facilities(facilities: Dictionary) -> void:
    var projected: Dictionary = {}
    for group in ["orbital", "surface"]:
        for facility in _physical_assets.get(group, []):
            projected[str(facility["id"])] = SolAssets.live_status(
                facility, facilities)
    if projected != _live_facility_status:
        _live_facility_status = projected
        queue_redraw()

func select_ship(ship_id: String) -> void:
    if not _live_fleet.has(ship_id):
        return
    _selected_ship_id = ship_id
    _selected_facility_id = ""
    _selected_body_id = ""
    queue_redraw()


func is_body_focused() -> bool:
    return not _focused_body_id.is_empty()


func focus_body(body_id: String) -> bool:
    var body: Dictionary = _body_by_id(body_id)
    if body.is_empty():
        return false
    _selected_body_id = body_id
    _focused_body_id = body_id
    _return_camera = false
    _wheel_target_zoom = -1.0
    _zoom_candidate_body_id = ""
    _follow_orbit_valid = false
    # One continuous camera, animated until the real body is large enough.
    var low: float = MIN_ZOOM
    var high: float = MAX_ZOOM
    for i in range(20):
        var mid: float = (low + high) * 0.5
        if _body_size_at_zoom(body, mid) < FOCUS_GLOBE_RADIUS:
            low = mid
        else:
            high = mid
    _focus_zoom_target = high
    _dragging = false
    queue_redraw()
    return true


func unfocus_body() -> void:
    _focused_body_id = ""
    _zoom_candidate_body_id = ""
    _follow_orbit_valid = false
    _focus_zoom_target = -1.0
    _wheel_target_zoom = -1.0
    _return_camera = true
    _dragging = false
    queue_redraw()


func reset_view() -> void:
    _focused_body_id = ""
    _zoom_candidate_body_id = ""
    _follow_orbit_valid = false
    _focus_zoom_target = -1.0
    _wheel_target_zoom = -1.0
    _return_camera = true
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
    # Do not guess a local orbit from the child and parent's
    # heliocentric radii in the frozen Rust seed.
    if _satellite_orbit_native_radius(body) <= 0.0:
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
    return pow(maxf(radius, 0.0), ORBIT_COMPRESSION)


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
        # The satellite has its OWN local orbital coordinate frame.
        # Native seed heliocentric orbit_radius never means moon distance.
        position = _body_position(parent, scale) + Vector2(
            cos(radians), -sin(radians)) * (
                _satellite_orbit_radius(body, parent, scale))
    else:
        var orbit: float = _radius_transform(float(
            body.get("orbit_radius", 0.0))) * scale * _zoom
        position = _center() + Vector2(cos(radians), -sin(radians)) * orbit
    if not bid.is_empty():
        _draw_body_positions[bid] = position
    return position


func _satellite_orbit_native_radius(body: Dictionary) -> float:
    # A future body may specify this directly; no need for any known ID.
    var native_radius: float = float(body.get("satellite_orbit_radius_native", 0.0))
    if is_finite(native_radius) and native_radius > 0.0:
        return native_radius
    # The original Sol seed has no planetocentric moon radii. Supply
    # real astronomical LOCAL orbit distances to the visual layer only.
    var system: Dictionary = _world.get("system", {})
    var bid: String = str(body.get("id", ""))
    if str(system.get("id", "")) == "system-sol" and (
            SOL_SATELLITE_ORBIT_KM.has(bid)):
        return float(SOL_SATELLITE_ORBIT_KM[bid]) / KM_PER_AU * (
            SOL_NATIVE_UNITS_PER_AU)
    return 0.0


func _satellite_orbit_radius(body: Dictionary, _parent: Dictionary,
        scale: float) -> float:
    var local_native_radius: float = _satellite_orbit_native_radius(body)
    if local_native_radius <= 0.0:
        return 0.0
    # Hierarchical map LOD: project a LOCAL radius under its parent,
    # not a fake delta of heliocentric radii (old Luna-as-Mars bug).
    # Display-only compression is intentional and identical for all moons.
    return pow(local_native_radius, SATELLITE_COMPRESSION) * scale * _zoom


func _satellite_visibility(body: Dictionary, parent: Dictionary,
        scale: float) -> float:
    # On overview scale, an actual moon separation is subpixel. Hide
    # overlapping map glyphs until the viewer zooms into the parent.
    var separation: float = _satellite_orbit_radius(body, parent, scale)
    var combined_radius: float = _body_size(body) + _body_size(parent)
    return clampf((separation - combined_radius + 3.0) / 14.0, 0.0, 1.0)


func _overview_body_radius(body: Dictionary) -> float:
    var kind: String = str(body.get("type", ""))
    if kind in ["asteroid", "belt"]:
        return 4.5
    var system: Dictionary = _world.get("system", {})
    var id: String = str(body.get("id", ""))
    if str(system.get("id", "")) == "system-sol" and (
            SOL_BODY_RADII_KM.has(id)):
        # Readable, gently compressed physical size hierarchy.
        # The star remains larger than Jupiter at orbital overview.
        var known_km: float = float(SOL_BODY_RADII_KM[id])
        var symbolic: float = 3.25 + 3.25 * pow(known_km / 6371.0, 0.33)
        return minf(4.0, symbolic) if kind == "moon" else symbolic
    if kind == "moon":
        return 4.0
    if str(body.get("biome", "")) == "gas_giant":
        return 10.0
    return 6.5


func _body_size_at_zoom(body: Dictionary, at_zoom: float) -> float:
    # Symbol at sector scale; continuous larger globe at near scale.
    var scale: float = sqrt(maxf(at_zoom, 0.64))
    if at_zoom > 32.0:
        scale = sqrt(32.0) * pow(at_zoom / 32.0, 1.12)
    var base: float = _overview_body_radius(body)
    if str(body.get("type", "")) in ["asteroid", "belt"]:
        return base * minf(scale, 6.0)
    return base * scale


func _body_size(body: Dictionary) -> float:
    return _body_size_at_zoom(body, _zoom)


func _surface_detail_start_zoom(body: Dictionary) -> float:
    # Invert the SAME visual-size function used for the globe. No per-planet
    # threshold values: gas giants, rocky planets and moons all receive the
    # same two-wheel-step fade after they cross DETAIL_RADIUS.
    var size_at_one: float = _body_size_at_zoom(body, 1.0)
    var threshold_at_low_zoom: float = pow(DETAIL_RADIUS / size_at_one, 2.0)
    if threshold_at_low_zoom <= 32.0:
        return threshold_at_low_zoom
    return 32.0 * pow(
        DETAIL_RADIUS / (size_at_one * sqrt(32.0)), 1.0 / 1.12)


func _surface_detail_alpha(body: Dictionary) -> float:
    var first_zoom: float = _surface_detail_start_zoom(body)
    if _zoom <= first_zoom:
        return 0.0
    # Logarithmic camera steps make a wheel notch visually consistent
    # regardless of the body's size or current orbital zoom level.
    var steps: float = log(_zoom / first_zoom) / log(WHEEL_ZOOM)
    var t: float = clampf(steps / SURFACE_REVEAL_WHEEL_STEPS, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t) # smoothstep: no abrupt alpha edges


func _surface_tint(hex: String, opacity: float) -> Color:
    var tint: Color = Color(hex)
    tint.a = opacity
    return tint


func _facility_count(body_id: String) -> int:
    return int(_facilities_by_body.get(body_id, 0))

func _live_ship_count(body_id: String) -> int:
    return int(_ships_by_body.get(body_id, 0))

func _draw() -> void:
    var started: int = Time.get_ticks_usec()
    _draw_now_usec = started
    _draw_body_positions.clear()
    _draw_system()
    _last_draw_usec = maxi(0, Time.get_ticks_usec() - started)
    _max_draw_usec = maxi(_max_draw_usec, _last_draw_usec)
    _draw_calls += 1


func _orbit_line_alpha(is_satellite: bool) -> float:
    var base: float = (
        SATELLITE_ORBIT_LINE_OPACITY if is_satellite else ORBIT_LINE_OPACITY)
    # At close zoom, orbit circles become visual clutter, especially while
    # following a moving planet. Fade them rather than cutting them off.
    var near_fade: float = minf(
        1.0, ORBIT_FADE_BEGIN_ZOOM / maxf(_zoom, ORBIT_FADE_BEGIN_ZOOM))
    return base * near_fade


func _draw_system() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND, true)
    _body_pins.clear()
    _ship_pins.clear()
    _facility_pins.clear()
    _station_draw_records.clear()
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
            var moon_fade: float = _satellite_visibility(body, parent, scale)
            if moon_fade > 0.01:
                draw_arc(_body_position(parent, scale),
                    _satellite_orbit_radius(body, parent, scale), 0.0, TAU,
                    72, Color(0.23, 0.32, 0.42,
                        _orbit_line_alpha(true) * moon_fade), 1.0, true)
            continue
        var radius: float = _radius_transform(float(body.get("orbit_radius", 0.0))) * scale * _zoom
        if radius > 1.0:
            draw_arc(star, radius, 0.0, TAU, 96,
                Color(0.18, 0.26, 0.35, _orbit_line_alpha(false)), 1.0, true)
    # A small, legible symbol: no giant Sun covering Mercury's orbit.
    var star_size: float = 13.5 * clampf(sqrt(_zoom), 0.8, 4.0)
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
        var moon_parent: Dictionary = _known_moon_parent(body)
        var moon_fade: float = 1.0
        if not moon_parent.is_empty():
            moon_fade = _satellite_visibility(body, moon_parent, scale)
            if moon_fade < 0.001:
                # The moon still exists, but cannot be distinguished
                # from its parent at this overview magnification.
                continue
        var color: Color = _body_color(body)
        color.a *= moon_fade
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
            if visual_radius >= DETAIL_RADIUS:
                var detail_opacity: float = _surface_detail_alpha(body) * moon_fade
                if detail_opacity > 0.001:
                    _draw_globe_detail(body, position, visual_radius,
                        detail_opacity)
        if picked:
            draw_arc(position, visual_radius + 7.0, 0.0, TAU, 40,
                Color(0.65, 0.92, 0.98, moon_fade), 1.8, true)
        # Facilities have their OWN real IDs and orbital/surface map
        # objects, not a decorative facility-count square on the planet.
        var local_ships: int = _live_ship_count(bid)
        var station_carries_ships: bool = false
        for asset in _physical_assets.get("orbital", []):
            if str(asset["body"]) == bid and (
                    (_ship_ids_by_location.get(
                    str(asset["location"]), []) as Array).size() > 0):
                station_carries_ships = true
                break
        # Physically docked ships belong at the real station icon, not
        # a false aggregate marker at the center of the planet.
        if local_ships > 0 and not station_carries_ships:
            # The marker represents real ships AT this location; active
            # transits are in the live observer, not fake diagram pixels.
            var fleet_marker: Vector2 = position + Vector2(
                -visual_radius - 10.0, 0.0)
            _ship_pins.append({"position": fleet_marker,
                "ship_ids": (_ship_ids_by_body.get(bid, []) as Array).duplicate(),
                "hit_radius": 12.0})
            var ship_marker: PackedVector2Array = PackedVector2Array([
                position + Vector2(-visual_radius - 13.0, -3.0),
                position + Vector2(-visual_radius - 7.0, 0.0),
                position + Vector2(-visual_radius - 13.0, 3.0)
            ])
            draw_colored_polygon(ship_marker, Color("#7abacb"))
            if (_ship_ids_by_body.get(bid, []) as Array).has(
                    _selected_ship_id):
                draw_arc(fleet_marker, 9.0, 0.0, TAU, 18,
                    Color("#fff0b0"), 1.5, true)
            draw_string(font, position + Vector2(-visual_radius - 25.0, 16.0),
                str(local_ships), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7abacb"))
        var label_offset: Vector2 = Vector2(visual_radius + 8.0, -8.0)
        var label_color: Color = (
            Color("#f2f7fa") if picked else Color("#a9bbc8"))
        label_color.a *= moon_fade
        draw_string(font, position + label_offset, str(body.get("name", bid)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_color)
        if moon_fade >= 0.5:
            _body_pins.append({"body": body, "position": position,
                "hit_radius": maxf(22.0, visual_radius + 9.0)})
    # Real source-backed stations and surface enterprises are drawn
    # independently. No extra N39/N9 objects are generated in the UI.
    _draw_physical_sol_assets(scale)
    # Draw ONLY ships with a real committed N14 transit.position. The
    # radial display is compressed by the same source orbit transform as
    # the planets; there is no fabricated travel or per-frame motion.
    _draw_real_native_transits(system, scale)
    _draw_true_arrival_transitions(system, scale)
    draw_string(font, Vector2(14.0, 26.0),
        "%s  /  %d тел  /  масштаб ×%.1f" % [str(system.get("name", "?")), bodies.size(), _zoom],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#dce8ee"))
    draw_string(font, Vector2(14.0, size.y - 14.0),
        "Колесо: бесшовный масштаб до поверхности · двойной клик: приблизить планету · условные расстояния",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#7d9cad"))


## The orbital station is the actual source N39 station facility at the
## same native location N43 uses for N14 arrivals. Only the radius glyph is
## expanded outside the schematic globe icon to keep it clickable.
func _draw_physical_sol_assets(scale: float) -> void:
    if str(_world.get("system", {}).get("id", "")) != "system-sol":
        return
    var font: Font = get_theme_default_font()
    for facility in _physical_assets.get("orbital", []):
        var parent: Dictionary = _body_by_id(str(facility["body"]))
        if parent.is_empty():
            continue
        var body_pos: Vector2 = _body_position(parent, scale)
        var body_radius: float = _body_size(parent)
        var source_angle: float = float(N43.initial_facility_angle(
            str(facility["location"])))
        var native_angle: float = fposmod(
            source_angle + _visual_station_time(_draw_now_usec), 360.0)
        var direction: Vector2 = Vector2(
            cos(deg_to_rad(native_angle)), -sin(deg_to_rad(native_angle)))
        var local_native: float = SolOrbits.compact_station_orbit_radius(
            str(facility["body"]))
        if local_native <= 0.0:
            continue
        var physical_compressed: float = pow(
            local_native, SATELLITE_COMPRESSION) * scale * _zoom
        var display_radius: float = maxf(
            body_radius + 20.0, physical_compressed)
        var pos: Vector2 = body_pos + direction * display_radius
        var native_info: Dictionary = _station_native_location(
            str(facility["location"]))
        if native_info.get("ok", false):
            var source_offset: Variant = _world.get(
                "system", {}).get("universe_offset", [0.0, 0.0])
            if source_offset is Array and source_offset.size() == 2:
                var native_offset: Vector2 = Vector2(
                    float(source_offset[0]), float(source_offset[1]))
                _station_draw_records.append({
                    "location": str(facility["location"]),
                    "native": native_info["position"],
                    "native_radius": native_info["native_radius"],
                    "screen": pos,
                    "native_global_screen": _native_screen_global(
                        native_info["position"], native_offset, scale)
                })
        if _zoom >= 2.0:
            draw_arc(body_pos, display_radius, 0, TAU, 60,
                Color(0.35, 0.51, 0.59, 0.24), 1.0, true)
        var tone: Color = Color("#e6c48d")
        if str(facility["id"]) == _selected_facility_id:
            draw_arc(pos, 12.0, 0, TAU, 24,
                Color("#fff4c5"), 1.6, true)
        # Compact industrial hub: central hull, two radial docking arms,
        # solar collectors. The icon is visual, not a fake N39 module.
        draw_rect(Rect2(pos - Vector2(5, 4), Vector2(10, 8)),
            tone, true)
        draw_line(pos + Vector2(-12, 0), pos + Vector2(12, 0),
            tone, 1.5)
        draw_rect(Rect2(pos + Vector2(-16, -3), Vector2(6, 6)),
            Color("#6ca1ba"), true)
        draw_rect(Rect2(pos + Vector2(10, -3), Vector2(6, 6)),
            Color("#6ca1ba"), true)
        _facility_pins.append({"id": str(facility["id"]),
            "position": pos, "hit_radius": 15.0})
        var docked_ids: Array = _ship_ids_by_location.get(
            str(facility["location"]), [])
        if not docked_ids.is_empty():
            var docked_marker: Vector2 = pos + Vector2(-11, -11)
            draw_circle(docked_marker, 3.0, Color("#85d1e0"))
            if docked_ids.has(_selected_ship_id):
                draw_arc(docked_marker, 7.0, 0, TAU, 16,
                    Color("#fff0b0"), 1.5, true)
            _ship_pins.append({"position": docked_marker,
                "ship_ids": docked_ids.duplicate(), "hit_radius": 9.0})
        if _zoom >= 7.0 or _focused_body_id == str(facility["body"]):
            draw_string(font, pos + Vector2(17, -9),
                "Орбитальная станция", HORIZONTAL_ALIGNMENT_LEFT,
                -1, 12, Color("#dfc8a4"))
    # Ground facilities are *real* N39 enterprise IDs, not synthetic
    # site slots. Their surface coordinates are explicitly schematic
    # until a physical colony land-placement model is designed.
    for facility in _physical_assets.get("surface", []):
        var parent: Dictionary = _body_by_id(str(facility["body"]))
        if parent.is_empty():
            continue
        var body_radius: float = _body_size(parent)
        if body_radius < DETAIL_RADIUS:
            continue
        var alpha: float = _surface_detail_alpha(parent)
        if alpha < 0.10:
            continue
        var body_pos: Vector2 = _body_position(parent, scale)
        var site: Vector2 = facility["site"]
        var pos: Vector2 = body_pos + site * body_radius
        var kind: String = str(facility["type"])
        var tone: Color = Color("#d6c9a1", alpha)
        if kind == "farm":
            tone = Color(0.65, 0.85, 0.60, alpha)
        elif kind == "mining_rig":
            tone = Color(0.88, 0.72, 0.53, alpha)
        elif kind == "refinery":
            tone = Color(0.70, 0.81, 0.88, alpha)
        var icon_size: float = clampf(body_radius * 0.070, 4.5, 9.0)
        draw_rect(Rect2(pos - Vector2(icon_size, icon_size * 0.65),
            Vector2(icon_size * 2.0, icon_size * 1.3)),
            tone, true)
        draw_line(pos + Vector2(icon_size * 0.5, -icon_size * 0.65),
            pos + Vector2(icon_size * 0.5, -icon_size * 1.5),
            tone, 2.0)
        if str(facility["id"]) == _selected_facility_id:
            draw_arc(pos, icon_size + 5.0, 0, TAU, 22,
                Color("#fff4c5"), 1.5, true)
        _facility_pins.append({"id": str(facility["id"]),
            "position": pos, "hit_radius": maxf(10.0, icon_size + 5.0)})
        if body_radius > 112.0:
            draw_string(font, pos + Vector2(icon_size + 5, -6),
                str(facility["name"]), HORIZONTAL_ALIGNMENT_LEFT,
                -1, 11, Color(0.88, 0.90, 0.85, alpha))


## Surface placeholders grow in place on the very same orbital map.
## No imaginary T1 industries or second terrain simulation are shown.
func _draw_globe_detail(body: Dictionary, center: Vector2, radius: float,
        opacity: float) -> void:
    # Major terrain fades in first; small lakes, bands and craters follow.
    # Both layers reach the original full-strength colors after two notches.
    var subtle_opacity: float = clampf((opacity - 0.15) / 0.85, 0.0, 1.0)
    var biome: String = str(body.get("biome", ""))
    if biome == "terrestrial":
        var land_a: PackedVector2Array = PackedVector2Array([
            center + Vector2(-0.70, -0.35) * radius,
            center + Vector2(-0.34, -0.72) * radius,
            center + Vector2(0.09, -0.73) * radius,
            center + Vector2(0.26, -0.44) * radius,
            center + Vector2(0.08, -0.12) * radius,
            center + Vector2(-0.26, -0.03) * radius,
            center + Vector2(-0.43, 0.30) * radius,
            center + Vector2(-0.67, 0.20) * radius
        ])
        var land_b: PackedVector2Array = PackedVector2Array([
            center + Vector2(0.37, -0.05) * radius,
            center + Vector2(0.66, 0.00) * radius,
            center + Vector2(0.86, 0.35) * radius,
            center + Vector2(0.56, 0.65) * radius,
            center + Vector2(0.20, 0.75) * radius,
            center + Vector2(0.10, 0.30) * radius
        ])
        draw_colored_polygon(land_a, _surface_tint("#789c7d", opacity))
        draw_colored_polygon(land_b, _surface_tint("#9bb38a", opacity))
        draw_circle(center + Vector2(-0.17, 0.41) * radius,
            radius * 0.15, _surface_tint("#5689a3", subtle_opacity))
    elif biome == "gas_giant":
        for band in [-0.70, -0.39, -0.06, 0.22, 0.57]:
            var y: float = float(band) * radius
            var half: float = sqrt(maxf(0.0, radius * radius - y * y)) * 0.92
            draw_line(center + Vector2(-half, y),
                center + Vector2(half, y), _surface_tint("#917d70", opacity),
                maxf(2.0, radius * 0.065))
    elif biome in ["lifeless", "ice"]:
        draw_circle(center + Vector2(-0.32, -0.20) * radius,
            radius * 0.16, _surface_tint("#809aad", subtle_opacity))
        draw_circle(center + Vector2(0.36, 0.31) * radius,
            radius * 0.10, _surface_tint("#90a9bd", subtle_opacity))
    elif biome in ["molten", "desert"]:
        draw_arc(center + Vector2(0.10, -0.15) * radius,
            radius * 0.51, 0.50, 2.75, 44, _surface_tint("#e4b08c", opacity),
            maxf(2.0, radius * 0.02))
    draw_arc(center, radius, 0.18 * PI, 1.15 * PI, 70,
        _surface_tint("#192a39", opacity), maxf(1.0, radius * 0.025))


## Visual-only projection of N14's physical absolute world position.
## NativePositionResolver uses system.universe_offset + polar body orbit;
## the system diagram uses the same orbit with a nonlinear radial scale
## and flipped vertical screen axis. This function never advances travel,
## invents a route or changes the ship's canonical N39 location.
## N43 phase is authoritative. Body and station positions are derived
## from committed read-only WorldModel angles and the real native calendar.
func _is_sol_station_location(location: String) -> bool:
    if location.is_empty() or str(
            _world.get("system", {}).get("id", "")) != "system-sol":
        return false
    for station in _physical_assets.get("orbital", []):
        if str(station["location"]) == location:
            return true
    return false


func _station_native_location(location: String) -> Dictionary:
    var source: Dictionary = {}
    for station in _physical_assets.get("orbital", []):
        if str(station["location"]) == location:
            source = station
            break
    if source.is_empty():
        return {"ok": false}
    var raw: Variant = _world.get(
        "system", {}).get("universe_offset", null)
    if not (raw is Array) or raw.size() != 2:
        return {"ok": false}
    var offset: Vector2 = Vector2(float(raw[0]), float(raw[1]))
    # Substituting the equivalent orbital phase for the displayed
    # calendar time makes the same station position as the UI easing;
    # N43 itself remains untouched.
    var displayed_angle: float = _visual_station_time(
        Time.get_ticks_usec())
    var display_native_units: float = displayed_angle * (
        N43.FACILITY_ORBIT_PERIOD / 360.0)
    return StationShipProjection.station_native_position(
        _body_index, offset, str(source["body"]), location,
        display_native_units)


func _native_screen_global(native: Vector2,
        offset: Vector2, scale: float) -> Vector2:
    var local: Vector2 = native - offset
    var distance: float = local.length()
    if distance <= 0.0:
        return _center()
    return _center() + Vector2(
        local.x, -local.y) / distance * (
        _radius_transform(distance) * scale * _zoom)


func _native_screen_for_ship(native: Vector2,
        offset: Vector2, scale: float) -> Vector2:
    var original: Vector2 = _native_screen_global(
        native, offset, scale)
    if str(_world.get("system", {}).get("id", "")) != "system-sol":
        return original
    return StationShipProjection.corrected_screen(
        native, original, _station_draw_records)


## Interpolate only between two ACTUAL completed physical states:
## last observed native in-flight N14 position and an N43 station
## already reached by the paid arrival. Never changes transit/credits.
func _draw_true_arrival_transitions(system: Dictionary,
        scale: float) -> void:
    if _recent_arrivals.is_empty() or str(
            system.get("id", "")) != "system-sol":
        return
    var raw: Variant = system.get("universe_offset", null)
    if not (raw is Array) or raw.size() != 2:
        return
    var offset: Vector2 = Vector2(float(raw[0]), float(raw[1]))
    for sid in _recent_arrivals:
        var state: Dictionary = _recent_arrivals[sid]
        var destination: String = str(state["location"])
        var docked: Dictionary = _station_native_location(destination)
        if not docked.get("ok", false):
            continue
        var from: Variant = state["from"]
        var target: Vector2 = docked["position"]
        var alpha: float = VisualMotion.alpha(
            int(state["started_usec"]), int(state["duration_usec"]),
            _draw_now_usec)
        if alpha >= 1.0:
            continue
        var current: Vector2 = Vector2(
            float(from[0]), float(from[1])).lerp(target, alpha)
        var marker: Vector2 = _native_screen_for_ship(
            current, offset, scale)
        var color: Color = Color("#8ec9da", 1.0 - alpha)
        draw_circle(marker, 3.4, color)
        if str(sid) == _selected_ship_id:
            draw_arc(marker, 7.0, 0.0, TAU, 16,
                Color("#fff0b0", 1.0 - alpha), 1.3, true)


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
        var native_position: Vector2 = Vector2(
            float(native_xy[0]), float(native_xy[1]))
        if not is_finite(native_position.x) or not is_finite(
                native_position.y):
            continue
        # A ship at the actual N43 dock has the SAME screen position
        # as the station icon, even with intentionally expanded glyph
        # radii. Correction vanishes farther from stations.
        var screen: Vector2 = _native_screen_for_ship(
            native_position, offset, scale)
        if not bounds.has_point(screen):
            continue # Cross-system transfers are not painted in this map.
        var tone: Color = Color("#8ec9da")
        if str(ship.get("class", "")) == "miner":
            tone = Color("#9ecb95")
        elif str(ship.get("class", "")) == "freighter":
            tone = Color("#ddc287")
        # At sector overview one simple marker per vessel; hundreds of
        # decorative arc strokes have no gameplay value. Keep a halo on
        # actual selected vessels and when zoomed to a local flight.
        if str(sid) == _selected_ship_id:
            var native_route: Variant = transit.get(
                "navigation_waypoints", [])
            if native_route is Array and not native_route.is_empty():
                var line: PackedVector2Array = PackedVector2Array([screen])
                for raw_point in native_route:
                    if not (raw_point is Array) or raw_point.size() != 2:
                        break
                    var wp: Vector2 = Vector2(
                        float(raw_point[0]), float(raw_point[1]))
                    line.append(_native_screen_for_ship(
                        wp, offset, scale))
                if line.size() > 1:
                    draw_polyline(line, Color(0.51, 0.81, 0.90, 0.7),
                        1.7, true)
        draw_circle(screen, 3.4, tone)
        if _zoom >= 4.0:
            draw_arc(screen, 5.0, 0.0, TAU, 12, tone, 1.0, true)
        if str(sid) == _selected_ship_id:
            draw_arc(screen, 9.0, 0.0, TAU, 20,
                Color("#fff0b0"), 1.6, true)
        _ship_pins.append({"position": screen,
            "ship_ids": [str(sid)], "hit_radius": 12.0})


func _zoom_at(pointer: Vector2, multiplier: float) -> void:
    _return_camera = false
    _focus_zoom_target = -1.0
    var prior_target: float = _wheel_target_zoom if _wheel_target_zoom > 0.0 else _zoom
    _wheel_target_zoom = clampf(prior_target * multiplier, MIN_ZOOM, MAX_ZOOM)
    _wheel_anchor = pointer
    if multiplier > 1.0:
        # Identify by existing screen hit-test. Lock is activated only once
        # the planet visually reaches detail scale, not before it.
        var under_cursor: Dictionary = _nearest_pin(pointer)
        if not under_cursor.is_empty():
            _zoom_candidate_body_id = str(under_cursor.get("id", ""))
    elif not _focused_body_id.is_empty():
        var focused: Dictionary = _body_by_id(_focused_body_id)
        if focused.is_empty() or _body_size_at_zoom(focused, _wheel_target_zoom) < DETAIL_RADIUS:
            # Reverse zoom restores free panning naturally, without a jump
            # to orbit/default view.
            _focused_body_id = ""
            _zoom_candidate_body_id = ""
            _follow_orbit_valid = false
    elif not _zoom_candidate_body_id.is_empty():
        var candidate: Dictionary = _body_by_id(_zoom_candidate_body_id)
        if candidate.is_empty() or _body_size_at_zoom(candidate, _wheel_target_zoom) < DETAIL_RADIUS:
            _zoom_candidate_body_id = ""
    queue_redraw()


## Ship markers take priority over overlapping planet glyphs.
## Repeated clicks on an aggregate docked marker cycle real vessel IDs.
func _pick_ship(pointer: Vector2) -> bool:
    var chosen: Dictionary = {}
    var nearest: float = INF
    for pin in _ship_pins:
        var distance: float = pointer.distance_to(pin["position"])
        if distance <= float(pin.get("hit_radius", 12.0)) and (
                distance < nearest):
            nearest = distance
            chosen = pin
    if chosen.is_empty():
        return false
    var ids: Array = chosen.get("ship_ids", [])
    if ids.is_empty():
        return false
    var index: int = ids.find(_selected_ship_id)
    var next_id: String = str(ids[(index + 1) % ids.size()])
    if not _live_fleet.has(next_id):
        return false
    select_ship(next_id)
    ship_selected.emit(next_id)
    return true


func _pick(pointer: Vector2, open_body: bool = false) -> void:
    if _pick_ship(pointer):
        return
    for pin in _facility_pins:
        if pointer.distance_to(pin["position"]) <= float(
                pin.get("hit_radius", 12.0)):
            select_facility(str(pin["id"]))
            facility_selected.emit(str(pin["id"]))
            return
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
        if _drag_distance >= 7.0:
            # Manual navigation takes precedence over both acquired focus
            # and a pending wheel-to-detail focus.
            _focused_body_id = ""
            _zoom_candidate_body_id = ""
            _focus_zoom_target = -1.0
            _follow_orbit_valid = false
        _pan += event.relative
        queue_redraw()
        accept_event()

