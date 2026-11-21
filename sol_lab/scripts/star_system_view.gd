extends Control
## Read-only continuous camera over a Galaxy 0.6.7 system.
## Display radii are schematic but all orbital screen separations use one
## camera zoom. Native N14/N39 positions and orbital angles are untouched.
## Facility markers remain attached to real source body identities.

signal earth_district_requested(pointer: Vector2, projection: Rect2)
const DistrictRoads = preload("res://scripts/view/sol_district_roads.gd")
var district_extent: Vector2 = DistrictRoads.AREA
signal body_selected(body: Dictionary)
signal body_open_requested(body: Dictionary)
signal ship_selected(ship_id: String)
signal facility_selected(facility_id: String)
signal placement_site_selected(site_id: String)
signal placement_cancel_requested

const MIN_ZOOM: float = 0.45
const DISTRICT_ENTRY_RADIUS: float = 220.0
const MAX_ZOOM: float = 512.0
const FOCUS_GLOBE_RADIUS: float = 165.0
## Sol Lab camera acquisition: begin following the zoomed planet at x3.1.
## Keep globe surface LOD independent of camera follow.
const FOLLOW_START_ZOOM: float = 3.1
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
const LocalFlight = preload("res://scripts/sol_local_flight.gd")
const StationShipProjection = preload("res://scripts/ui_station_ship_projection.gd")
const Model = preload("res://scripts/sol_building_model.gd")
const PhysicalAssets = preload("res://scripts/view/physical_assets_projection.gd")
const PlanetSurface = preload("res://scripts/view/planet_surface_projection.gd")
const PlanetSprites = preload("res://scripts/view/planet_sprite_catalog.gd")
const FacilityLabels = preload("res://scripts/view/facility_labels_ru.gd")
const ColonyRoads = preload("res://scripts/view/colony_roads_projection.gd")
const SurfaceBuildingLOD = preload("res://scripts/view/surface_building_lod.gd")
const BuildingGlyph = preload("res://scripts/view/colony_building_glyph.gd")
const SurfaceSites = preload("res://scripts/view/sol_surface_sites.gd")
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
var _earth_follow_offset := Vector2.ZERO
var _zoom: float = 1.0
## Compensates the logical viewport shrink introduced by the *global UI*
## content_scale_factor at close-up only. Native physical world untouched.
var _ui_viewport_scale: float = 1.0
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
var _physical_assets: Dictionary = {"orbital": [], "surface": [],
    "profiles": {}}
var _live_asset_definitions: Dictionary = {}
var _live_facility_status: Dictionary = {}
var _colony_roads: Dictionary = {"sites": {}, "links": []}
var _colony_tick: int = -1
var _colony_anim_time: float = 0.0
var _colony_anim_accum: float = 0.0
var _colony_has_activity: bool = false
var _facility_pins: Array = []
## Pure visual placement state; only Runtime.order() commits resources.
var _placement_body_id: String = ""
var _placement_building_id: String = ""
var _placement_sites: Array = []
var _placement_pins: Array = []
var _placement_hover_id: String = ""
var _placement_chosen_id: String = ""
## Bounded screen records of real Sol stations. Never N39 objects or nodes.
var _station_draw_records: Array = []
## At most one ephemeral UI interpolation per actual arrival receipt.
var _recent_arrivals: Dictionary = {}
var _native_station_time: float = 0.0
var _previous_native_time: float = 0.0
var _station_phase_from_deg: float = 0.0
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
## Sol-only flight presentation. Ship and market snapshots remain authoritative.
var _colonizer: Dictionary = {}
var _flight_draw_states: Dictionary = {}
## Keep the last receipt only until the interpolated calendar reaches its ETA.
var _ending_flights: Dictionary = {}
var _selected_flight_kind: String = ""
var _flight_pins: Array = []
var _flight_paused: bool = false
var _flight_pause_started_usec: int = -1
var _flight_frozen_native: float = 0.0

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
    _physical_assets = PhysicalAssets.build(_world)
    _live_asset_definitions.clear()
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
    # Navigation sites are genuine N43 locations bound to a source body.
    # A miner at a nav waypoint must be visible in the body's list.
    for site in _world.get("nav_sites", []):
        if not (site is Dictionary):
            continue
        var location: String = str(site.get("name", ""))
        var body_id: String = str(site.get("body", ""))
        if location.is_empty() or body_id.is_empty() or not _body_index.has(body_id):
            continue
        if not _body_ids_by_location.has(location):
            _body_ids_by_location[location] = []
        var registered: Array = _body_ids_by_location[location]
        if not registered.has(body_id):
            registered.append(body_id)
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
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


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
        elif _focused_body_id == "earth":
            var earth := _body_by_id("earth")
            var radius_ratio := _body_size_at_zoom(earth, next_zoom_wheel) / _body_size(earth)
            var relative := _wheel_anchor - size * 0.5
            _earth_follow_offset = relative + (_earth_follow_offset - relative) * radius_ratio
        _zoom = next_zoom_wheel
        camera_changed = true
        if absf(_zoom - _wheel_target_zoom) < 0.005:
            _zoom = _wheel_target_zoom
            _wheel_target_zoom = -1.0

    # Camera follows the actual body once zoom crosses x3.1, even before
    # surface detail is visible. This is independent of body pixel radius.
    if not _zoom_candidate_body_id.is_empty() and _focused_body_id.is_empty() and not _return_camera:
        var candidate: Dictionary = _body_by_id(_zoom_candidate_body_id)
        if not candidate.is_empty() and _follow_threshold_reached(_zoom):
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
            if _focused_body_id == "earth":
                desired_pan += _earth_follow_offset
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

    if _colony_has_activity and not _focused_body_id.is_empty():
        _colony_anim_accum += maxf(delta, 0.0)
        if _colony_anim_accum >= 1.0 / 30.0:
            _colony_anim_time += minf(_colony_anim_accum, 0.10)
            _colony_anim_accum = 0.0
            camera_changed = true
    var now_usec: int = Time.get_ticks_usec()
    for sid in _recent_arrivals.keys():
        var row: Dictionary = _recent_arrivals[sid]
        if VisualMotion.alpha(int(row["started_usec"]),
                int(row["duration_usec"]), now_usec) >= 1.0:
            _recent_arrivals.erase(sid)
    if camera_changed or (
            not _flight_paused and (not _ending_flights.is_empty() or
            _colonizer.get("location", "") == "transit" or
            _freight.get("location", "") == "transit" or
            _second_freight.get("location", "") == "transit")) or (
            not _recent_arrivals.is_empty()) or (
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
    _colony_tick = -1
    _colony_roads = ColonyRoads.build(_physical_assets.get("surface", []), {}, -1)
    _colony_has_activity = false
    _colony_anim_time = 0.0
    _colony_anim_accum = 0.0
    _native_station_time = 0.0
    _previous_native_time = 0.0
    _station_phase_from_deg = 0.0
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
        _rebuild_colony_roads()
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


func start_placement(body_id: String, building_id: String,
        candidates: Array) -> void:
 _placement_body_id = body_id
 _placement_building_id = building_id
 _placement_sites = candidates.duplicate(true)
 _placement_chosen_id = ""
 _placement_hover_id = ""
 focus_body(body_id)
 queue_redraw()


func stop_placement() -> void:
 _placement_body_id = ""
 _placement_building_id = ""
 _placement_sites.clear()
 _placement_pins.clear()
 _placement_hover_id = ""
 _placement_chosen_id = ""
 queue_redraw()


func choose_placement(site_id: String) -> void:
 _placement_chosen_id = site_id
 queue_redraw()


func _pick_placement(pointer: Vector2) -> void:
 var chosen: String = ""
 var closest: float = INF
 for pin in _placement_pins:
  var distance: float = pointer.distance_to(pin["position"])
  if distance <= float(pin["hit_radius"]) and distance < closest:
   closest = distance
   chosen = str(pin["id"])
 if not chosen.is_empty():
  choose_placement(chosen)
  placement_site_selected.emit(chosen)


func _draw_placement(scale: float) -> void:
 _placement_pins.clear()
 if _placement_body_id.is_empty():
  return
 var body: Dictionary = _body_by_id(_placement_body_id)
 if body.is_empty():
  return
 var center: Vector2 = _body_position(body, scale)
 var radius: float = _body_size(body)
 var font: Font = get_theme_default_font()
 for site in _placement_sites:
  var position: Vector2 = center + SurfaceSites.site_position(site) * radius
  var id: String = str(site.get("id", ""))
  var active: bool = id == _placement_chosen_id
  var hovered: bool = id == _placement_hover_id
  var color: Color = Color("#f3d89e") if active else (
   Color("#a5e6dd") if hovered else Color("#75d1a5"))
  var outline: float = maxf(7.0, radius * 0.055)
  draw_circle(position, outline * 0.80,
   Color(color.r, color.g, color.b, 0.13))
  draw_arc(position, outline, 0.0, TAU, 24, color, 2.0, true)
  _placement_pins.append({"id": id, "position": position,
   "hit_radius": maxf(13.0, outline * 1.5)})
  if active or hovered:
   BuildingGlyph.paint(self, _placement_building_id,
    position, maxf(5.5, radius * 0.075), color)
   draw_string(font, position + Vector2(13, -14),
    str(site.get("label", id)),
    HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
  else:
   draw_circle(position, 2.5, color)
 draw_string(font, Vector2(14, 52),
  "РАЗМЕЩЕНИЕ · %s · площадок %d · кликните маркер" % [
   str(Model.find_building(_placement_building_id).get(
    "name", _placement_building_id)), _placement_sites.size()],
  HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#e7d0a5"))


## One native scalar from the real N158 calendar, not another simulation.
## The station uses exactly the N43 initial phase and orbit period.
func set_flight_clock_paused(value: bool) -> void:
    if value == _flight_paused:
        return
    var now: int = Time.get_ticks_usec()
    if value:
        _flight_frozen_native = _display_native_time(now)
        _flight_pause_started_usec = now
        _flight_paused = true
    else:
        var elapsed: int = maxi(0, now - _flight_pause_started_usec)
        # Hold the same visual phase while paused; do not let wall clock
        # consume its interpolation or a docking animation.
        if _station_time_started_usec >= 0:
            _station_time_started_usec += elapsed
        if _last_station_sample_usec >= 0:
            _last_station_sample_usec += elapsed
        if _body_motion_started_usec >= 0:
            _body_motion_started_usec += elapsed
        if _last_body_commit_usec >= 0:
            _last_body_commit_usec += elapsed
        _flight_paused = false
        _flight_pause_started_usec = -1
    queue_redraw()


func flight_checkpoint_time() -> float:
    if not _ending_flights.is_empty():
        return _native_station_time
    return _display_native_time(Time.get_ticks_usec())


func snap_flight_clock(native_units: float, paused_now: bool,
        displayed: float = -1.0) -> void:
    # Save/load must not interpolate from the OLD game's calendar.
    _native_station_time = native_units
    _station_phase_from_deg = fposmod(native_units * 360.0 /
        SolOrbits.STATION_ORBIT_PERIOD_NATIVE, 360.0)
    var now := Time.get_ticks_usec()
    _previous_native_time = clampf(displayed, 0.0, native_units) if displayed >= 0.0 else native_units
    _station_time_started_usec = now
    _station_time_duration_usec = 125000
    _last_station_sample_usec = -1
    _flight_frozen_native = _previous_native_time
    _flight_paused = paused_now
    _flight_pause_started_usec = now if paused_now else -1
    _ending_flights.clear()
    _body_motion_from.clear()
    queue_redraw()


func set_native_station_time(native_units: float) -> void:
    if not is_finite(native_units) or native_units < 0.0:
        return
    if _native_station_time == native_units:
        return
    var now: int = Time.get_ticks_usec()
    _previous_native_time = _display_native_time(now)
    _station_phase_from_deg = _visual_station_time(now)
    _native_station_time = native_units
    if _flight_paused:
        # One explicit manual tick while paused updates the visible clock.
        _flight_frozen_native = native_units
    _station_time_duration_usec = VisualMotion.sample_duration(
        _last_station_sample_usec, now, 160000)
    _station_time_started_usec = now
    _last_station_sample_usec = now
    queue_redraw()


func _display_native_time(now: int) -> float:
    if _flight_paused:
        return _flight_frozen_native
    return lerpf(_previous_native_time, _native_station_time, VisualMotion.alpha(
        _station_time_started_usec, _station_time_duration_usec, now))


func _visual_station_time(now: int) -> float:
    # Returns *degrees*, not native calendar units. Prior code stored a
    # smoothed angle and converted it AGAIN as time on the next snapshot:
    # source of jitter/jumps on accelerated ticks.
    var current_phase_deg: float = fposmod(
        _native_station_time * 360.0 /
        SolOrbits.STATION_ORBIT_PERIOD_NATIVE, 360.0)
    if _station_time_started_usec < 0:
        return current_phase_deg
    var alpha: float = VisualMotion.alpha(_station_time_started_usec,
        _station_time_duration_usec, now)
    return VisualMotion.orbit_angle(
        _station_phase_from_deg, current_phase_deg, alpha)


func set_live_facilities(facilities: Dictionary, tick: int = -1) -> void:
    # N39 may construct a real station/dock/factory AFTER the frozen Rust
    # seed was loaded. Metadata changes cause one reprojection; paid status
    # updates never regenerate the planet surface or reorder old facilities.
    var definitions: Dictionary = {}
    for fid in facilities:
        var row: Variant = facilities[fid]
        if not (row is Dictionary):
            continue
        var bid: String = str(row.get("body_id", row.get("body", "")))
        if not _body_index.has(bid):
            continue
        var kind: String = str(row.get("type", ""))
        var location: String = str(row.get("location", ""))
        definitions[str(fid)] = [kind, bid, location]
    if definitions != _live_asset_definitions:
        _live_asset_definitions = definitions
        _physical_assets = PhysicalAssets.build(_world, facilities)
        _rebuild_colony_roads()
    var projected: Dictionary = {}
    for group in ["orbital", "surface"]:
        for facility in _physical_assets.get(group, []):
            projected[str(facility["id"])] = PhysicalAssets.live_status(
                facility, facilities)
    if projected != _live_facility_status or tick != _colony_tick:
        _live_facility_status = projected
        _colony_tick = tick
        _rebuild_colony_roads()
        queue_redraw()


func _rebuild_colony_roads() -> void:
    _colony_roads = ColonyRoads.build(_physical_assets.get("surface", []),
        _live_facility_status, _colony_tick)
    _colony_has_activity = false
    for road in _colony_roads.get("links", []):
        if int(road.get("particles", 0)) > 0:
            _colony_has_activity = true
            break

func select_ship(ship_id: String) -> void:
    if not _live_fleet.has(ship_id):
        return
    _selected_ship_id = ship_id
    _selected_facility_id = ""
    _selected_body_id = ""
    queue_redraw()

## Explicit outliner navigation. Highlight the SAME N39 ship the map
## can select, and bring it into view without modifying real N14 position.
func reveal_ship(ship_id: String) -> bool:
    if not _live_fleet.has(ship_id):
        return false
    select_ship(ship_id)
    var ship: Dictionary = _live_fleet[ship_id]
    var transit: Variant = ship.get("transit", {})
    if transit is Dictionary and not transit.is_empty():
        var point: Variant = transit.get("position", null)
        var offset: Variant = _world.get("system", {}).get("universe_offset", null)
        if point is Array and point.size() == 2 and offset is Array and (
                (offset as Array).size() == 2) and (
                (point[0] is float or point[0] is int) and
                (point[1] is float or point[1] is int)):
            var where: Vector2 = Vector2(float(point[0]), float(point[1]))
            var anchor: Vector2 = Vector2(float(offset[0]), float(offset[1]))
            if is_finite(where.x) and is_finite(where.y):
                _focused_body_id = ""
                _zoom_candidate_body_id = ""
                _follow_orbit_valid = false
                _focus_zoom_target = -1.0
                _wheel_target_zoom = -1.0
                _return_camera = false
                var marker: Vector2 = _native_screen_for_ship(
                    where, anchor, _orbit_scale())
                _pan += size * 0.5 - marker
                queue_redraw()
        return true
    var location: String = str(ship.get("location", ""))
    var bodies: Array = _body_ids_by_location.get(location, [])
    if not bodies.is_empty():
        var body: String = str(bodies[0])
        if _focused_body_id != body:
            focus_body(body)
    queue_redraw()
    return true


func is_body_focused() -> bool:
    return not _focused_body_id.is_empty()


func focus_body(body_id: String) -> bool:
    var body: Dictionary = _body_by_id(body_id)
    if body.is_empty():
        return false
    _earth_follow_offset = Vector2.ZERO
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
        if _body_size_at_zoom(body, mid) < FOCUS_GLOBE_RADIUS / _ui_viewport_scale:
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


func set_ui_viewport_scale(value: float) -> void:
    var normalized: float = clampf(value, 1.0, 2.0)
    if is_equal_approx(_ui_viewport_scale, normalized):
        return
    _ui_viewport_scale = normalized
    _follow_orbit_valid = false
    queue_redraw()


func _orbit_scale() -> float:
    # The Godot window already scales drawing coordinates by
    # content_scale_factor. The Control's logical size is smaller by the
    # same factor, so using it directly keeps physical orbit dimensions
    # stable at every UI scale. Compensating here again enlarged lunar
    # orbits relative to planets (and previously clamped at 150%).
    var available: float = maxf(
        90.0 / _ui_viewport_scale, minf(size.x, size.y) * 0.40)
    return available / maxf(1.0,
        _radius_transform(_max_orbit_radius))

func _center() -> Vector2:
    return size * 0.5 + _pan


func _visual_body_angle(body: Dictionary, now_usec: int) -> float:
    var current: float = float(body.get("current_angle", 0.0))
    var bid: String = str(body.get("id", ""))
    if bid in ["earth", "luna", "mars"]:
        var period: float = body.get("satellite_orbit_period_native", body.get("orbit_period", 0.0))
        if period > 0.0:
            return current + 360.0 * (_display_native_time(now_usec) - _native_station_time) / period
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
    # Fade thresholds remain fixed in physical pixels as UI scale changes.
    return clampf((separation - combined_radius + 3.0 /
        _ui_viewport_scale) / (14.0 / _ui_viewport_scale), 0.0, 1.0)


func _overview_body_radius(body: Dictionary) -> float:
    var kind: String = str(body.get("type", ""))
    if kind in ["asteroid", "belt"]:
        return 4.5
    var system: Dictionary = _world.get("system", {})
    var id: String = str(body.get("id", ""))
    var physical_size: Variant = body.get("physical_radius_km",
        body.get("radius_km", null))
    if (physical_size is int or physical_size is float) and (
            is_finite(float(physical_size)) and
            float(physical_size) > 0.0):
        var physical_symbol: float = 3.25 + 3.25 * pow(
            float(physical_size) / 6371.0, 0.33)
        return minf(4.0, physical_symbol) if kind == "moon" else (
            physical_symbol)
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
    # Body diameters belong to the world camera, NOT the UI font scale.
    # Keep the approved Sol 0.65 map's physical screen sizes at 125–200%.
    if str(body.get("type", "")) in ["asteroid", "belt"]:
        return base * minf(scale, 6.0) / _ui_viewport_scale
    return base * scale / _ui_viewport_scale


func _body_size(body: Dictionary) -> float:
    return _body_size_at_zoom(body, _zoom)


func _surface_detail_start_zoom(body: Dictionary) -> float:
    # Invert the SAME visual-size function used for the globe. No per-planet
    # threshold values: gas giants, rocky planets and moons all receive the
    # same two-wheel-step fade after they cross DETAIL_RADIUS.
    var size_at_one: float = _body_size_at_zoom(body, 1.0)
    var threshold_at_low_zoom: float = pow(
        (DETAIL_RADIUS / _ui_viewport_scale) / size_at_one, 2.0)
    if threshold_at_low_zoom <= 32.0:
        return threshold_at_low_zoom
    return 32.0 * pow(
        (DETAIL_RADIUS / _ui_viewport_scale) / (
            size_at_one * sqrt(32.0)), 1.0 / 1.12)


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

var colonizer_progress := -1.0 # legacy readout, no longer drives a ship draw
var _freight: Dictionary = {}
var _second_freight: Dictionary = {}


func _flight_frame(kind: String) -> Dictionary:
    var earth := _body_by_id("earth")
    var moon := _body_by_id("luna")
    var scale := _orbit_scale()
    var center := _body_position(earth, scale)
    var separation := _body_position(moon, scale) - center
    # Globe symbols are enlarged relative to the local orbit. Use their
    # actual draw bounds plus the ship glyph radius for the approach gates.
    var earth_radius := _body_size(earth) * 1.07
    var moon_radius := _body_size(moon) * 1.07
    var room := separation.length() - earth_radius - moon_radius
    var glyph := clampf(room / 24.0, 0.0, 1.0)
    var earth_clearance := earth_radius + glyph * 8.0
    var gap := room - glyph * 16.0
    return {"center": center, "axis": separation.normalized(),
        "separation": separation.length(), "earth_gate": earth_clearance,
        "gap": maxf(0.0, gap), "glyph": glyph, "opacity": clampf(gap / 8.0, 0.0, 1.0),
        "berth": (6.0 if kind == "colonizer" else (-17.0 if kind == "freight2" else -6.0)) * glyph}


func _project_flight(point: Vector2, orbit: Dictionary, time: float,
        frame: Dictionary, screen_axis: Vector2) -> Vector2:
    var axis := LocalFlight.axis(orbit, time)
    var along := clampf(inverse_lerp(orbit.earth, orbit.luna, point.dot(axis)), 0.0, 1.0)
    var across: float = axis.cross(point) * frame.separation / orbit.distance + frame.berth
    return frame.center + screen_axis * (frame.earth_gate + frame.gap * along) + (
        Vector2(-screen_axis.y, screen_axis.x) * across)


func _solar_screen_body(orbit: Dictionary, id: String, at: float) -> Vector2:
    var body := _body_by_id(id)
    var physical := LocalFlight.gate(orbit, id, at)
    var radius := _radius_transform(float(body.orbit_radius)) * _orbit_scale() * _zoom
    return _center() + physical.normalized() * radius

func _solar_flight_position(path: Dictionary, at: float) -> Vector2:
    var orbit: Dictionary = path.orbit
    var source: String = path.source
    var target: String = path.destination
    var from := _solar_screen_body(orbit, source, at)
    var toward := _solar_screen_body(orbit, target, at)
    var heading := (toward - from).normalized()
    var point := LocalFlight.position(path, at)
    var progress := LocalFlight.progress(path, at)
    var scale := from.distance_to(toward) / maxf(1.0,
        LocalFlight.gate(orbit, source, at).distance_to(LocalFlight.gate(orbit, target, at)))
    var from_offset := from + heading * (_body_size(_body_by_id(source)) * 1.07 + 5.0)
    var to_offset := toward - heading * (_body_size(_body_by_id(target)) * 1.07 + 5.0)
    from_offset -= LocalFlight.gate(orbit, source, at) * scale
    to_offset -= LocalFlight.gate(orbit, target, at) * scale
    return point * scale + from_offset.lerp(to_offset, progress)

func _flight_pose(kind: String, ship: Dictionary, when_usec: int) -> Dictionary:
    if ship.is_empty():
        return {}
    var path: Dictionary = ship.get("trajectory", {})
    if path.get("orbit", {}).has("solar"):
        var at := clampf(_display_native_time(when_usec), path.departure, path.arrival)
        var position := _solar_flight_position(path, at)
        var direction := (_solar_flight_position(path, minf(path.arrival, at + 0.1)) -
            _solar_flight_position(path, maxf(path.departure, at - 0.1))).normalized()
        return {"moving": true, "position": position, "direction": direction, "opacity": 1.0,
            "glyph": 1.0, "route": path, "time": at, "progress": LocalFlight.progress(path, at),
            "world_position": LocalFlight.position(path, at)}
    if ship.get("location") == "mars":
        var body := _body_by_id("mars")
        var center := _body_position(body, _orbit_scale())
        var earth := _body_position(_body_by_id("earth"), _orbit_scale())
        var axis := (earth - center).normalized()
        return {"moving": false, "position": center + axis * (_body_size(body) * 1.07 + 5.0),
            "direction": axis, "opacity": 1.0, "glyph": 1.0}
    var frame := _flight_frame(kind)
    var screen_axis: Vector2 = frame.axis
    var lateral := Vector2(-screen_axis.y, screen_axis.x)
    if ship.get("location") != "transit":
        var dock_id: String = ship.location if kind != "colonizer" else "earth"
        if dock_id == "loading":
            dock_id = "earth"
        var distance: float = frame.earth_gate + (frame.gap if dock_id == "luna" else 0.0)
        var offset: Vector2 = screen_axis * distance + lateral * frame.berth
        return {"moving": false, "position": frame.center + offset,
            "direction": Vector2(offset.y, -offset.x).normalized(), "opacity": frame.opacity,
            "glyph": frame.glyph}
    if path.is_empty():
        return {}
    var t := clampf(_display_native_time(when_usec), path.departure, path.arrival)
    var point := LocalFlight.position(path, t)
    var axis := LocalFlight.axis(path.orbit, t)
    var velocity := LocalFlight.velocity(path, t)
    var position := _project_flight(point, path.orbit, t, frame, screen_axis)
    var relative := velocity - LocalFlight.tangent(point, path.orbit.omega)
    var heading := LocalFlight.tangent(position - (frame.center as Vector2), path.orbit.omega)
    heading += screen_axis * (frame.gap * relative.dot(axis) / (path.orbit.luna - path.orbit.earth))
    heading += lateral * (frame.separation * axis.cross(relative) / path.orbit.distance)
    return {"moving": true, "world_position": point,
        "position": position, "direction": heading.normalized(),
        "progress": LocalFlight.progress(path, t), "route": path, "time": t,
        "frame": frame, "opacity": frame.opacity, "glyph": frame.glyph}


func _remember_arrival(kind: String, previous: Dictionary, next: Dictionary,
        snap: bool) -> void:
    if snap:
        _ending_flights.erase(kind)
    elif previous.has("trajectory") and previous.get("arrival") != next.get("arrival"):
        _ending_flights[kind] = previous


func set_colonizer(ship: Dictionary, snap: bool = false) -> void:
    if ship != _colonizer or snap:
        _remember_arrival("colonizer", _colonizer, ship, snap)
        _colonizer = ship.duplicate(true)
        queue_redraw()


func set_freight(freight: Dictionary, snap: bool = false) -> void:
    if freight != _freight or snap:
        _remember_arrival("freight", _freight, freight, snap)
        _freight = freight.duplicate(true)
        queue_redraw()


func set_second_freight(ship: Dictionary, snap: bool = false) -> void:
    if ship != _second_freight or snap:
        _remember_arrival("freight2", _second_freight, ship, snap)
        _second_freight = ship.duplicate(true)
        queue_redraw()


const ShipArt = preload("res://sol_lab/earth_port/ship_art.gd")

func _paint_flight_ship(kind: String, position: Vector2,
        direction: Vector2, fade: float, glyph: float, loaded: bool) -> void:
    var tint := Color(1.0, 1.0, 1.0, clampf(fade, 0.0, 1.0))
    ShipArt.paint(self, position, direction.angle(), glyph * 0.6, tint, kind == "colonizer", loaded)


func _draw_flight(kind: String, ship: Dictionary) -> void:
    var ending: Dictionary = _ending_flights.get(kind, {})
    if not ending.is_empty():
        if _display_native_time(_draw_now_usec) < float(ending.arrival):
            ship = ending
        else:
            _ending_flights.erase(kind)
    var pose: Dictionary = _flight_pose(kind, ship, _draw_now_usec)
    if pose.is_empty():
        return
    _flight_draw_states[kind] = pose
    if pose.opacity <= 0.0:
        return # At overview scale the enlarged body symbols can touch.
    var position: Vector2 = pose["position"]
    if bool(pose["moving"]) and kind == _selected_flight_kind:
        var path: Dictionary = pose.route
        var line := PackedVector2Array()
        for index in range(25):
            var at := lerpf(path.departure, path.arrival, index / 24.0)
            if path.orbit.has("solar"):
                line.append(_solar_flight_position(path, at))
            else:
                var frame: Dictionary = pose.frame
                var axis: Vector2 = frame.axis.rotated(path.orbit.omega * (at - pose.time))
                line.append(_project_flight(LocalFlight.position(path, at), path.orbit, at, frame, axis))
        draw_polyline(line, Color("#8cbbce", 0.65), 1.5, true)
    var loaded: bool = float(ship.get("order", {}).get("amount", 0)) > 0
    _paint_flight_ship(kind, position, pose["direction"], pose.opacity, pose.glyph, loaded)
    if bool(pose["moving"]):
        _flight_pins.append({"kind": kind, "position": position})
        if kind == _selected_flight_kind:
            draw_arc(position, 11.0, 0.0, TAU, 18,
                Color("#fff0b0", 0.9), 1.3, true)
    if bool(pose["moving"]) and kind != "colonizer":
        var cargo: Dictionary = ship.get("order", {})
        var label: String = "%s · %s · %s %s" % [
            "2" if kind == "freight2" else "1",
            Model.PLANET_NAMES.get(str(cargo.get("destination", "")), "?"),
            Model.batch_amount(float(cargo.get("amount", 0))),
            Model.batch_unit(str(cargo.get("resource", "")))]
        draw_string(get_theme_default_font(), position + Vector2(9.0, -7.0),
            label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#f6d38a"))

func _draw() -> void:
    var started: int = Time.get_ticks_usec()
    _draw_now_usec = started
    _draw_body_positions.clear()
    _draw_system()
    _flight_draw_states.clear()
    _flight_pins.clear()
    if not _body_by_id("earth").is_empty() and not _body_by_id("luna").is_empty():
        _draw_flight("colonizer", _colonizer)
        _draw_flight("freight", _freight)
        _draw_flight("freight2", _second_freight)
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
    var star_size: float = (
        13.5 * clampf(sqrt(_zoom), 0.8, 4.0) / _ui_viewport_scale)
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
        var sprite: Texture2D = null
        var sprite_extent: float = visual_radius
        if kind != "asteroid" and kind != "belt":
            # Use the actual sprite bounds, including Saturn's rings. Screen
            # pixels, not camera zoom alone, decide the rasterized SVG tier.
            var is_saturn: bool = str(system.get("id", "")) == (
                "system-sol") and bid == "saturn"
            sprite_extent = visual_radius * (1.65 if is_saturn else 1.07)
            var bounds := Rect2(
                position - Vector2.ONE * sprite_extent,
                Vector2.ONE * sprite_extent * 2.0)
            var visible_pixels: float = (
                sprite_extent * 2.0 * _ui_viewport_scale
                if bounds.intersects(Rect2(Vector2.ZERO, size)) else 0.0)
            sprite = PlanetSprites.texture_for(body,
                str(system.get("id", "")),
                visual_radius < 16.0 / _ui_viewport_scale,
                visible_pixels)
            if sprite == null:
                sprite_extent = visual_radius
        if kind == "asteroid" or kind == "belt":
            var vertices: PackedVector2Array = PackedVector2Array([
                position + Vector2(0.0, -visual_radius),
                position + Vector2(visual_radius, 0.0),
                position + Vector2(0.0, visual_radius),
                position + Vector2(-visual_radius, 0.0)
            ])
            draw_colored_polygon(vertices, color)
        elif sprite != null:
            draw_texture_rect(sprite,
                Rect2(position - Vector2.ONE * sprite_extent,
                    Vector2.ONE * sprite_extent * 2.0),
                false, Color(1.0, 1.0, 1.0, moon_fade))
        else:
            draw_circle(position, visual_radius, color)
            if visual_radius >= DETAIL_RADIUS / _ui_viewport_scale:
                var detail_opacity: float = _surface_detail_alpha(body) * moon_fade
                if detail_opacity > 0.001:
                    _draw_globe_detail(body, position, visual_radius,
                        detail_opacity)
        if bid == "earth" and _body_ids_by_location.has("earth-colony"):
            var settlement := position + Vector2(-0.17, -0.20) * sprite_extent
            draw_circle(settlement, 5.0, Color("#1e3433"), true, -1.0, true)
            draw_circle(settlement, 3.2, Color("#e9cf91"), true, -1.0, true)
            if visual_radius >= 105.0:
                var footprint := _district_footprint(position, visual_radius)
                draw_rect(footprint, Color("#646b4c"))
                draw_rect(footprint, Color("#c5c49f"), false, 1)
                var district_scale: float = footprint.size.x / district_extent.x
                for segment in DistrictRoads.streets(district_extent):
                    draw_line(footprint.position + segment[0] * district_scale,
                        footprint.position + segment[1] * district_scale, Color("#858672"),
                        maxf(1.0, 14.0 * district_scale), true)
                for facility in _world.get("facilities", []):
                    var site: String = str(facility.get("surface_site_id", ""))
                    if facility.get("body") == "earth" and DistrictRoads.PLOTS.has(site):
                        var plot: Rect2 = DistrictRoads.PLOTS[site]
                        draw_rect(Rect2(footprint.position + plot.position * district_scale,
                            plot.size * district_scale), Color("#92927b"))
                if visual_radius >= 162.0:
                    for pad in [DistrictRoads.PAD, DistrictRoads.PAD + Vector2(167, 0)]:
                        draw_circle(footprint.position + pad * district_scale,
                            29.0 * district_scale, Color("#444d48"), true, -1.0, true)
            if visual_radius >= 85.0:
                var callout := settlement + Vector2(27, -26)
                draw_line(settlement, callout, Color("#e9cf91"), 1.2, true)
                draw_string(font, callout + Vector2(4, 0), "Поселение · приблизить",
                    HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#f2e6c7"))
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
        var label_offset: Vector2 = Vector2(sprite_extent + 8.0, -8.0)
        var label_color: Color = (
            Color("#f2f7fa") if picked else Color("#a9bbc8"))
        label_color.a *= moon_fade
        draw_string(font, position + label_offset, str(body.get("name", bid)),
            HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_color)
        if moon_fade >= 0.5:
            _body_pins.append({"body": body, "position": position,
                "hit_radius": maxf(22.0, sprite_extent + 9.0)})
    # Real source-backed stations and surface enterprises are drawn
    # independently. No extra N39/N9 objects are generated in the UI.
    _draw_physical_assets(scale)
    _draw_placement(scale)
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
func _draw_physical_assets(scale: float) -> void:
    var is_sol: bool = str(
        _world.get("system", {}).get("id", "")) == "system-sol"
    var font: Font = get_theme_default_font()
    # Project both separate gameplay assets into ONE orbital hull per
    # colony. Do not merge facilities, services, locations or save IDs.
    var platform_by_body: Dictionary = {}
    var yard_by_body: Dictionary = {}
    for asset in _physical_assets.get("orbital", []):
        var bid: String = str(asset.get("body", ""))
        if str(asset.get("type", "")) == "orbital_platform":
            platform_by_body[bid] = asset
        elif str(asset.get("type", "")) == "shipyard":
            yard_by_body[bid] = asset
    for facility in _physical_assets.get("orbital", []):
        var orbital_body: String = str(facility.get("body", ""))
        if str(facility.get("type", "")) == "shipyard" and (
                platform_by_body.has(orbital_body)):
            continue
        var attached_yard: Dictionary = yard_by_body.get(orbital_body, {})
        var has_module: bool = not attached_yard.is_empty() and (
            str(facility.get("type", "")) in ["orbital_platform", "shipyard"])
        var parent: Dictionary = _body_by_id(str(facility["body"]))
        if parent.is_empty():
            continue
        var body_pos: Vector2 = _body_position(parent, scale)
        var body_radius: float = _body_size(parent)
        var source_angle: float = float(N43.initial_facility_angle(
            str(facility["location"])))
        # Sol has verified native docking geometry; other systems render a
        # stable schematic station marker until their own N43 orbital
        # ephemeris is available. Never animate a fictional physical orbit.
        var native_angle: float = fposmod(
            source_angle + (
                _visual_station_time(_draw_now_usec) if is_sol else 0.0),
            360.0)
        var direction: Vector2 = Vector2(
            cos(deg_to_rad(native_angle)), -sin(deg_to_rad(native_angle)))
        var local_native: float = (
            SolOrbits.compact_station_orbit_radius(
                str(facility["body"])) if is_sol else 0.0)
        var physical_compressed: float = (
            pow(local_native, SATELLITE_COMPRESSION) * scale * _zoom
            if local_native > 0.0 else 0.0)
        # Keep the station off the enlarged planet glyph without
        # confusing this presentation gap with physical N43 altitude.
        # At close zoom the old +20px gap is roughly doubled; distant
        # overview keeps a compact readable station near the planet.
        # At extreme zoom an extra fixed 40px is too close to the
        # enormous enlarged planet symbol. Increase clearance with
        # glyph size, capped for mouse reach and predictable framing.
        # Native N43 still orbits at the same 800km physical altitude.
        var near_surface_zoom: float = clampf(
            (_zoom - 10.0) / 38.0, 0.0, 1.0)
        var orbit_gap_px: float = (
            lerpf(18.0, 40.0,
                clampf((_zoom - 1.0) / 8.0, 0.0, 1.0)) /
                _ui_viewport_scale +
            minf(body_radius * 0.10,
                80.0 / _ui_viewport_scale) * near_surface_zoom)
        var display_radius: float = maxf(
            body_radius + orbit_gap_px, physical_compressed)
        var pos: Vector2 = body_pos + direction * display_radius
        var native_info: Dictionary = (
            _station_native_location(str(facility["location"]))
            if is_sol else {"ok": false})
        if native_info.get("ok", false):
            var source_offset: Variant = _world.get(
                "system", {}).get("universe_offset", [0.0, 0.0])
            if source_offset is Array and source_offset.size() == 2:
                var native_offset: Vector2 = Vector2(
                    float(source_offset[0]), float(source_offset[1]))
                var body_native: Dictionary = (
                    StationShipProjection.native_body_position(
                    _body_index, native_offset, str(facility["body"])))
                if body_native.get("ok", false):
                    _station_draw_records.append({
                        "location": str(facility["location"]),
                        "native": native_info["position"],
                        "native_radius": native_info["native_radius"],
                        "screen": pos,
                        "native_global_screen": _native_screen_global(
                            native_info["position"], native_offset, scale),
                        "body_native": body_native["position"],
                        "body_native_radius": SolOrbits.physical_radius_native(
                            str(facility["body"])),
                        "body_screen": body_pos,
                        "body_global_screen": _native_screen_global(
                            body_native["position"], native_offset, scale),
                        "screen_orbit_radius": display_radius
                    })
        if _zoom >= 2.0 and is_sol:
            draw_arc(body_pos, display_radius, 0, TAU, 60,
                Color(0.35, 0.51, 0.59, 0.24), 1.0, true)
        var tone: Color = Color("#e6c48d")
        # Small overview glyph, larger close-up station and clickable
        # target. Never scale per ship or create new SceneTree nodes.
        var station_lod: float = clampf((_zoom - 1.0) / 11.0,
            0.0, 1.0)
        var icon_scale: float = lerpf(0.78, 1.38, station_lod)
        if str(facility["id"]) == _selected_facility_id:
            draw_arc(pos, 12.0 * icon_scale, 0, TAU, 24,
                Color("#fff4c5"), 1.6, true)
        # Visual industrial hub, 1 actual source N39 station ID.
        draw_rect(Rect2(pos - Vector2(5, 4) * icon_scale,
            Vector2(10, 8) * icon_scale), tone, true)
        draw_line(pos + Vector2(-12, 0) * icon_scale,
            pos + Vector2(12, 0) * icon_scale, tone, 1.5)
        draw_rect(Rect2(pos + Vector2(-16, -3) * icon_scale,
            Vector2(6, 6) * icon_scale), Color("#6ca1ba"), true)
        draw_rect(Rect2(pos + Vector2(10, -3) * icon_scale,
            Vector2(6, 6) * icon_scale), Color("#6ca1ba"), true)
        _facility_pins.append({"id": str(facility["id"]),
            "position": pos,
            "hit_radius": lerpf(15.0, 24.0, station_lod)})
        if has_module:
            var module_pos: Vector2 = pos + Vector2(
                18.0, -9.0) * icon_scale
            BuildingGlyph.paint(self, "shipyard", module_pos,
                4.5 * icon_scale, Color("#c4dcea"))
            if str(attached_yard.get("id", "")) == _selected_facility_id:
                draw_arc(module_pos, 8.5 * icon_scale, 0, TAU, 20,
                    Color("#fff4c5"), 1.6, true)
            if str(attached_yard.get("id", "")) != str(facility["id"]):
                _facility_pins.append({
                    "id": str(attached_yard["id"]),
                    "position": module_pos,
                    "hit_radius": 10.0 * icon_scale})
        var docked_ids: Array = _ship_ids_by_location.get(
            str(facility["location"]), [])
        if not docked_ids.is_empty():
            var docked_marker: Vector2 = pos + (
                Vector2(-11, -11) * icon_scale)
            draw_circle(docked_marker, 3.0, Color("#85d1e0"))
            if docked_ids.has(_selected_ship_id):
                draw_arc(docked_marker, 7.0, 0, TAU, 16,
                    Color("#fff0b0"), 1.5, true)
            _ship_pins.append({"position": docked_marker,
                "ship_ids": docked_ids.duplicate(), "hit_radius": 9.0})
        if _zoom >= 7.0 or _focused_body_id == str(facility["body"]):
            draw_string(font, pos + Vector2(17, -9) * icon_scale,
                "Административный док" if str(facility.get(
                    "type", "")) == "construction_dock"
                else ("Орбитальная станция · верфь" if has_module
                    else "Орбитальная станция"), HORIZONTAL_ALIGNMENT_LEFT,
                -1, 12, Color("#dfc8a4"))
    # Roads go behind the existing clickable source-backed facilities.
    # Only draw on the enlarged focused globe; roads are NOT physical cargo.
    _draw_colony_roads(scale)
    # Ground facilities are *real* N39 enterprise IDs, not synthetic
    # site slots. Their surface coordinates are explicitly schematic
    # until a physical colony land-placement model is designed.
    for facility in _physical_assets.get("surface", []):
        var parent: Dictionary = _body_by_id(str(facility["body"]))
        if parent.is_empty():
            continue
        var body_radius: float = _body_size(parent)
        # Continuous reveal, independent of the terrain-detail cutoff.
        var alpha: float = SurfaceBuildingLOD.visibility(
            body_radius, _ui_viewport_scale)
        if alpha <= 0.001:
            continue
        var body_pos: Vector2 = _body_position(parent, scale)
        var site: Vector2 = facility["site"]
        var pos: Vector2 = body_pos + site * body_radius
        var kind: String = str(facility.get(
            "render_type", facility["type"]))
        var tone: Color = Color("#d6c9a1", alpha)
        if kind == "farm":
            tone = Color(0.65, 0.85, 0.60, alpha)
        elif kind == "mining_rig":
            tone = Color(0.88, 0.72, 0.53, alpha)
        elif kind == "refinery":
            tone = Color(0.70, 0.81, 0.88, alpha)
        elif kind == "administrative_center":
            tone = Color(0.89, 0.81, 0.57, alpha)
        elif kind == "colony_construction_dock":
            tone = Color(0.73, 0.69, 0.55, alpha)
        elif kind == "construction_site":
            tone = Color(0.99, 0.76, 0.35, alpha)
        elif kind == "spaceport":
            tone = Color(0.54, 0.82, 0.94, alpha)
        var icon_size: float = SurfaceBuildingLOD.icon_half_size(
            body_radius, _ui_viewport_scale)
        # Render the SAME vector symbol as the list and build catalog.
        # A building site advertises its eventual type, not a generic box.
        var symbol_kind: String = (
            str(facility.get("construction_building_id", ""))
            if kind == "construction_site" else kind)
        if symbol_kind.is_empty():
            symbol_kind = kind
        BuildingGlyph.paint(self, symbol_kind, pos,
            maxf(3.0, icon_size), tone)
        # Reserved free apron: two stable map-local coordinates for future
        # touchdown and cargo handling. Decorative only; no ship movement.
        if kind == "spaceport":
            var pads: Dictionary = facility.get("port_pads", {})
            for target_kind in ["landing", "loading"]:
                var pad: Dictionary = pads.get(target_kind, {})
                if pad.is_empty():
                    continue
                var pad_pos: Vector2 = body_pos + (
                    SurfaceSites.site_position(pad)) * body_radius
                var pad_color: Color = (
                    Color("#92d5d9", alpha) if target_kind == "landing"
                    else Color("#dfca8f", alpha))
                draw_line(pos, pad_pos, Color(
                    pad_color.r, pad_color.g, pad_color.b, 0.38), 1.0)
                draw_rect(Rect2(pad_pos - Vector2(6, 4),
                    Vector2(12, 8)), Color(
                    pad_color.r, pad_color.g, pad_color.b, alpha * 0.16), true)
                draw_rect(Rect2(pad_pos - Vector2(6, 4),
                    Vector2(12, 8)), pad_color, false, 1.25)
                draw_string(font, pad_pos + Vector2(-3, 3),
                    "П" if target_kind == "landing" else "Г",
                    HORIZONTAL_ALIGNMENT_LEFT, -1, 10, pad_color)
        if kind == "construction_site":
            # Existing unique site progress, backed by calendar timestamps.
            var begin: float = float(facility.get("construction_start_native", 0.0))
            var finish: float = float(facility.get("construction_finished_native", begin))
            var done: float = 0.0
            if finish > begin:
                done = clampf((_native_station_time - begin) / (finish - begin), 0.0, 1.0)
            var width: float = icon_size * 2.4
            var bottom: float = pos.y + icon_size * 1.8
            draw_rect(Rect2(pos.x - width * 0.5, bottom,
                width, maxf(2.0, icon_size * 0.26)),
                Color(0.12, 0.19, 0.24, alpha), true)
            if done > 0.0:
                draw_rect(Rect2(pos.x - width * 0.5, bottom,
                    width * done, maxf(2.0, icon_size * 0.26)),
                    Color(0.43, 0.87, 0.58, alpha), true)
        if str(facility["id"]) == _selected_facility_id:
            draw_arc(pos, icon_size + 5.0, 0, TAU, 22,
                Color("#fff4c5"), 1.5, true)
        _facility_pins.append({"id": str(facility["id"]),
            "position": pos, "hit_radius": maxf(10.0, icon_size + 5.0)})
        # Gradually bring in the name; never switch it on at radius 112.
        var label_alpha: float = alpha * SurfaceBuildingLOD.label_visibility(
            body_radius, _ui_viewport_scale)
        if label_alpha > 0.001:
            draw_string(font, pos + Vector2(icon_size + 5, -6),
                FacilityLabels.display_name(facility),
                HORIZONTAL_ALIGNMENT_LEFT,
                -1, 11, Color(0.88, 0.90, 0.85, label_alpha))


## Lightweight roads from real source-backed ground sites, attached to the
## SAME animated orbital position as their parent. No separate terrain mode.
func _draw_colony_roads(scale: float) -> void:
    if _focused_body_id.is_empty():
        return
    var body: Dictionary = _body_by_id(_focused_body_id)
    if body.is_empty():
        return
    var radius: float = _body_size(body)
    var road_fade: float = SurfaceBuildingLOD.road_visibility(
        radius, _ui_viewport_scale)
    if road_fade <= 0.001:
        return
    var alpha: float = SurfaceBuildingLOD.visibility(
        radius, _ui_viewport_scale) * road_fade
    var center: Vector2 = _body_position(body, scale)
    var sites: Dictionary = _colony_roads.get("sites", {})
    var has_roads: bool = false
    for edge in _colony_roads.get("links", []):
        if str(edge.get("body", "")) != _focused_body_id:
            continue
        var src: String = str(edge.get("a", ""))
        var dst: String = str(edge.get("b", ""))
        if not sites.has(src) or not sites.has(dst):
            continue
        has_roads = true
        var from_pos: Vector2 = center + (sites[src] as Vector2) * radius
        var to_pos: Vector2 = center + (sites[dst] as Vector2) * radius
        var production: bool = str(edge.get("kind", "")) == "production"
        draw_line(from_pos, to_pos,
            Color(0.62, 0.75, 0.70, alpha * (0.56 if production else 0.74)),
            clampf(radius * (0.008 if production else 0.013), 1.0, 3.0), true)
        var count: int = clampi(int(edge.get("particles", 0)), 0,
            ColonyRoads.MAX_PARTICLES_PER_LINK)
        for i in range(count):
            var phase: float = fposmod(_colony_anim_time * 0.20
                + float(i) / float(count), 1.0)
            if not production:
                phase = 1.0 - absf(2.0 * phase - 1.0)
            draw_circle(from_pos.lerp(to_pos, phase),
                clampf(radius * 0.014, 1.5, 3.0),
                Color(0.93, 0.76, 0.48, alpha))
    if not has_roads:
        return
    # Visual-only origin of the road network, not a minted N39 AC.
    # N151 AC is already a REAL surface pin; do not draw a phantom hub.
    if not (_colony_roads.get("has_ac", {}) as Dictionary).has(
            _focused_body_id):
        var hub_site: Vector2 = (_colony_roads.get(
            "hubs", {}) as Dictionary).get(
            _focused_body_id, ColonyRoads.HUB_SITE)
        var hub: Vector2 = center + hub_site * radius
        draw_rect(Rect2(hub - Vector2(4.0, 4.0), Vector2(8.0, 8.0)),
            Color(0.91, 0.86, 0.69, alpha), true)


## Surface placeholders grow in place on the very same orbital map.
## No imaginary T1 industries or second terrain simulation are shown.
func _draw_globe_detail(body: Dictionary, center: Vector2, radius: float,
        opacity: float) -> void:
    var bid: String = str(body.get("id", ""))
    var profile: Dictionary = _physical_assets.get(
        "profiles", {}).get(bid, {})
    if profile.is_empty():
        profile = PlanetSurface.build(body, str(
            _world.get("system", {}).get("id", "")))
    var subtle: float = clampf((opacity - 0.15) / 0.85, 0.0, 1.0)
    for region in profile.get("regions", []):
        var points: PackedVector2Array = PackedVector2Array()
        for local in region["points"]:
            points.append(center + (local as Vector2) * radius)
        if points.size() >= 3:
            draw_colored_polygon(points, _surface_tint(
                str(region["color"]), opacity))
    var biome: String = str(profile.get("biome", ""))
    for detail in profile.get("details", []):
        var kind: String = str(detail.get("kind", ""))
        if kind == "lake":
            draw_circle(center + (detail["pos"] as Vector2) * radius,
                radius * float(detail["radius"]),
                _surface_tint("#5689a3", subtle))
        elif kind == "crater":
            draw_arc(center + (detail["pos"] as Vector2) * radius,
                radius * float(detail["radius"]), 0.0, TAU, 32,
                _surface_tint("#677e92", subtle),
                maxf(1.0, radius * 0.012))
        elif kind == "band" and biome == "gas_giant":
            var y: float = float(detail["y"]) * radius
            var half: float = sqrt(maxf(
                0.0, radius * radius - y * y)) * 0.92
            draw_line(center + Vector2(-half, y),
                center + Vector2(half, y),
                _surface_tint("#917d70", opacity),
                maxf(2.0, radius * 0.065))
    draw_arc(center, radius, 0.18 * PI, 1.15 * PI, 70,
        _surface_tint("#192a39", opacity),
        maxf(1.0, radius * 0.025))

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
        SolOrbits.STATION_ORBIT_PERIOD_NATIVE / 360.0)
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


func _follow_threshold_reached(current_zoom: float) -> bool:
    return current_zoom >= FOLLOW_START_ZOOM


func _district_footprint(center: Vector2, radius: float) -> Rect2:
    var extent := district_extent * (0.44 * radius / district_extent.x)
    return Rect2(center + Vector2(-0.18, -0.21) * radius - extent * 0.5, extent)

func earth_district_projection() -> Rect2:
    var earth := _body_by_id("earth")
    return _district_footprint(_body_position(earth, _orbit_scale()), _body_size(earth))

func return_to_earth_point(pointer: Vector2, fraction: Vector2) -> void:
    _focused_body_id = "earth"
    _focus_zoom_target = -1.0
    _wheel_target_zoom = -1.0
    var earth := _body_by_id("earth")
    var radius := _body_size(earth)
    _draw_now_usec = Time.get_ticks_usec()
    _draw_body_positions.clear()
    var center := _body_position(earth, _orbit_scale())
    var footprint := _district_footprint(center, radius)
    _pan += pointer - (footprint.position + footprint.size * fraction)
    _earth_follow_offset = center + pointer - (footprint.position + footprint.size * fraction) - size * 0.5
    _follow_orbit_offset = center - (_center() - (pointer - (footprint.position + footprint.size * fraction)))
    _follow_orbit_valid = true
    _draw_body_positions.clear()
    queue_redraw()

func _zoom_at(pointer: Vector2, multiplier: float) -> void:
    _return_camera = false
    _focus_zoom_target = -1.0
    var prior_target: float = _wheel_target_zoom if _wheel_target_zoom > 0.0 else _zoom
    _wheel_target_zoom = clampf(prior_target * multiplier, MIN_ZOOM, MAX_ZOOM)
    _wheel_anchor = pointer
    if multiplier > 1.0 and _focused_body_id == "earth" and (
            _body_ids_by_location.has("earth-colony") and
            _body_size_at_zoom(_body_by_id("earth"), prior_target) >=
            DISTRICT_ENTRY_RADIUS / _ui_viewport_scale):
        var earth := _body_by_id("earth")
        var footprint := _district_footprint(_body_position(earth, _orbit_scale()), _body_size(earth))
        if footprint.has_point(pointer):
            _wheel_target_zoom = -1.0
            earth_district_requested.emit(pointer, footprint)
        else:
            _wheel_target_zoom = minf(_wheel_target_zoom, prior_target)
        return
    if multiplier > 1.0:
        # Identify by existing screen hit-test. Acquire focus at x3.1,
        # independent of globe surface detail and camera UI scale.
        var under_cursor: Dictionary = _nearest_pin(pointer)
        if not under_cursor.is_empty():
            _zoom_candidate_body_id = str(under_cursor.get("id", ""))
    elif not _focused_body_id.is_empty():
        var focused: Dictionary = _body_by_id(_focused_body_id)
        if focused.is_empty() or not _follow_threshold_reached(_wheel_target_zoom):
            # Unlock as the zoom target crosses below x3.1; pointer-anchored
            # free panning resumes without switching to a different map.
            _focused_body_id = ""
            _zoom_candidate_body_id = ""
            _follow_orbit_valid = false
    elif not _zoom_candidate_body_id.is_empty():
        var candidate: Dictionary = _body_by_id(_zoom_candidate_body_id)
        if candidate.is_empty() or not _follow_threshold_reached(_wheel_target_zoom):
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


## Flying Sol craft can be selected without bringing back permanent
## decorative route lines. An unselected craft is just a small marker.
func _pick_sol_flight(pointer: Vector2) -> bool:
    for pin in _flight_pins:
        if pointer.distance_to(pin["position"]) <= 10.0:
            _selected_flight_kind = str(pin["kind"])
            queue_redraw()
            return true
    return false


func _pick(pointer: Vector2, open_body: bool = false) -> void:
    if not _placement_body_id.is_empty():
        _pick_placement(pointer)
        return
    if _pick_sol_flight(pointer):
        return
    if _pick_ship(pointer):
        return
    # Pick closest marker, not the first wide hull hit box. This keeps
    # the small shipyard module selectable beside its parent station.
    var closest_facility: Dictionary = {}
    var closest_distance: float = INF
    for pin in _facility_pins:
        var distance: float = pointer.distance_to(pin["position"])
        if distance <= float(pin.get("hit_radius", 12.0)) and (
                distance < closest_distance):
            closest_distance = distance
            closest_facility = pin
    if not closest_facility.is_empty():
        select_facility(str(closest_facility["id"]))
        facility_selected.emit(str(closest_facility["id"]))
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
    var id: String = str(chosen.get("id", ""))
    select_body(id)
    if open_body:
        # Immediate follow acquisition, independent of wheel x3.1.
        # Use the existing focus/tracking path for moving moons.
        focus_body(id)
        body_open_requested.emit(chosen.duplicate(true))
    else:
        body_selected.emit(chosen.duplicate(true))


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
    if event is InputEventMouseMotion and (
            not _placement_body_id.is_empty()):
        var newest: String = ""
        var nearest: float = INF
        for marker in _placement_pins:
            var gap: float = event.position.distance_to(
                marker["position"])
            if gap <= float(marker["hit_radius"]) and gap < nearest:
                newest = str(marker["id"])
                nearest = gap
        if newest != _placement_hover_id:
            _placement_hover_id = newest
            queue_redraw()
        return
    if event is InputEventMouseButton and (
            not _placement_body_id.is_empty()):
        if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
            placement_cancel_requested.emit()
        elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            _pick_placement(event.position)
        accept_event()
        return
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


