extends SceneTree
## E visual-only interpolation: frozen source coordinates remain immutable.
const Motion = preload("res://scripts/ui_source_motion_interpolator.gd")
const SystemView = preload("res://scripts/star_system_view.gd")

func _initialize() -> void:
    if not is_equal_approx(Motion.orbit_angle(359.0, 1.0, 0.5), 0.0):
        _fail("orbit seam 359->1 did not take 2-degree short path")
        return
    if not is_equal_approx(Motion.orbit_angle(1.0, 359.0, 0.5), 0.0):
        _fail("orbit seam 1->359 did not take short negative path")
        return
    if not is_equal_approx(Motion.orbit_angle(45.0, 135.0, 0.25), 67.5):
        _fail("quarter-turn visual angle math")
        return
    if not is_equal_approx(Motion.orbit_angle(45.0, 135.0, -2.0), 45.0):
        _fail("negative fractional time must clamp")
        return
    if not is_equal_approx(Motion.orbit_angle(45.0, 135.0, 2.0), 135.0):
        _fail("fraction must not extrapolate beyond next source snapshot")
        return
    if not is_equal_approx(Motion.alpha(1000, 100, 1050), 0.5):
        _fail("monotonic UI timeline alpha")
        return
    if not is_equal_approx(Motion.alpha(1000, 100, 1300), 1.0):
        _fail("stalled sim must halt visual movement instead of extrapolate")
        return
    # Regression: at late N158 tick a source frame can take ~1.4 s.
    # 650ms interpolation used to complete and then visibly freeze until the
    # next real snapshot. Its duration now follows the observed cadence.
    var slow_duration: int = Motion.sample_duration(1000000, 2400000)
    if slow_duration < 1400000 or slow_duration > 2000000 or (
            Motion.alpha(2400000, slow_duration, 3200000) >= 1.0):
        _fail("slow 1.4s source commits still freeze at former 650ms cap")
        return
    if Motion.sample_duration(1000000, 1100000) < 100000 or (
            Motion.sample_duration(1000000, 9000000) != 3500000):
        _fail("adaptive smoothing did not respect bounded source interval")
        return
    if Motion.sample_duration(-1, 3000000) != 160000 or (
            Motion.sample_duration(4000000, 3000000) != 160000):
        _fail("first or reversed source timestamps must use safe initial tween")
        return
    if not Motion.valid_xy([0.0, 8]) or Motion.valid_xy([1.0]) or (
            Motion.valid_xy([INF, 1.0])):
        _fail("transit XY validation admits invalid/malformed data")
        return
    var from: Array = [0.0, 0.0]
    var to: Array = [8.0, 4.0]
    var halfway: Variant = Motion.transit_position(from, to, 0.5)
    if not Motion.valid_xy(halfway) or not is_equal_approx(
            float(halfway[0]), 4.0) or not is_equal_approx(
            float(halfway[1]), 2.0):
        _fail("ship transit midpoint was not a projection of real endpoints")
        return
    if from != [0.0, 0.0] or to != [8.0, 4.0]:
        _fail("motion sampler modified its authoritative input")
        return

    # The actual view is driven by source snapshots, not artificial ticks.
    var view = SystemView.new()
    view.size = Vector2(750.0, 540.0)
    get_root().add_child(view)
    var original: Dictionary = _world(359.0)
    var newer: Dictionary = _world(1.0)
    view.set_world(original)
    view.update_world(newer)
    if float(original["bodies"][0]["current_angle"]) != 359.0 or (
            float(newer["bodies"][0]["current_angle"]) != 1.0):
        _fail("visual update mutated caller's real snapshots")
        return
    var current: Dictionary = view._body_by_id("earth")
    if not is_equal_approx(float(current.get("current_angle", -1.0)), 1.0):
        _fail("read-only view canonical body angle overwritten by smoothing")
        return
    view._body_motion_started_usec = int(
        Time.get_ticks_usec() - view._body_motion_duration_usec / 2)
    var halfway_angle: float = view._visual_body_angle(
        current, Time.get_ticks_usec())
    if minf(absf(halfway_angle), absf(360.0 - halfway_angle)) > 1.0:
        _fail("real system view did not smooth orbit wrap")
        return
    if not is_equal_approx(float(current["current_angle"]), 1.0):
        _fail("visual angle touched committed snapshot")
        return

    var old_ships: Dictionary = {"ship-1": _ship("sol", [0.0, 0.0])}
    var new_ships: Dictionary = {"ship-1": _ship("sol", [8.0, 4.0])}
    view.set_live_fleet(old_ships)
    view.set_live_fleet(new_ships)
    if not view._ship_motion_from.has("ship-1"):
        _fail("real ship transit did not retain visual previous position")
        return
    view._ship_motion_started_usec = int(
        Time.get_ticks_usec() - view._ship_motion_duration_usec / 2)
    var visual_xy: Variant = view._visual_ship_position(
        "ship-1", view._live_fleet["ship-1"], Time.get_ticks_usec())
    if not Motion.valid_xy(visual_xy) or absf(float(visual_xy[0]) - 4.0) > 0.2:
        _fail("UI transit not interpolated halfway between actual source points")
        return
    if new_ships["ship-1"]["transit"]["position"] != [8.0, 4.0] or (
            view._live_fleet["ship-1"]["transit"]["position"] != [8.0, 4.0]):
        _fail("smoothed ship position leaked into source data")
        return
    var changed_system: Dictionary = {"ship-1": _ship("different", [50.0, 40.0])}
    view.set_live_fleet(changed_system)
    if not view._ship_motion_from.is_empty():
        _fail("cross-system jump must snap; never fake in-system transit")
        return
    var docked: Dictionary = {"ship-1": _ship("different", null)}
    view.set_live_fleet(docked)
    if not view._ship_motion_from.is_empty():
        _fail("arrival must snap; never fake post-arrival movement")
        return
    view.set_world(original)
    if not view._body_motion_from.is_empty() or (
            not view._ship_motion_from.is_empty()):
        _fail("map reset/new system retained stale interpolated positions")
        return
    print("P2_PERF_E_VISUAL_INTERPOLATION_PASS orbit_wrap=true",
        " native_transit=true source_immutable=true snap_on_jump=true",
        " no_source_ticks=true")
    quit(0)

func _world(angle: float) -> Dictionary:
    return {"system": {"id": "sol", "name": "Sol", "star_type": "G",
            "universe_offset": [0.0, 0.0]},
        "bodies": [{"id": "earth", "name": "Earth",
            "type": "planet", "current_angle": angle,
            "orbit_radius": 1.0, "orbit_period": 365.0}],
        "facilities": []}

func _ship(system_id: String, xy: Variant) -> Dictionary:
    var transit: Dictionary = {}
    if xy is Array:
        transit["position"] = xy.duplicate()
    return {"system_id": system_id, "location": system_id,
        "class": "miner", "transit": transit}

func _fail(reason: String) -> void:
    push_error("P2_PERF_E_VISUAL_INTERPOLATION_FAIL: " + reason)
    quit(1)
