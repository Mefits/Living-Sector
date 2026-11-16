extends SceneTree
## Read-only scale benchmark. 500/1000 synthetic visual vessel snapshots
## DO NOT impersonate autonomous N39 ships or a full 500-ship simulation.
## Measures actual Godot CanvasItem draw and fleet UI projection time,
## then independently times 500 N14 predictive guidance solves.
##
## Run: godot --headless --path godot --script res://tests/p2_ship_scale_500_benchmark.gd
const NativeData = preload("res://scripts/native_data.gd")
const WorldModel = preload("res://scripts/sim/world_model.gd")
const SystemView = preload("res://scripts/star_system_view.gd")
const NativeIntercept = preload("res://scripts/sim/ships/native_orbital_intercept.gd")
const SNAPSHOTS: int = 24
const DRAW_RATIO_LIMIT: float = 35.0
const SNAPSHOT_RATIO_LIMIT: float = 35.0

func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var seed: Dictionary = NativeData.load_current_world()
    if seed.has("error"):
        _fail("missing original Galaxy seed")
        return
    var model: RefCounted = WorldModel.new()
    if not model.load_seed(seed):
        _fail("cannot build original Sol")
        return
    var view: Control = SystemView.new()
    root.add_child(view)
    view.size = Vector2(1100, 800)
    view.set_world(model.system_by_id("system-sol"))
    await process_frame
    await process_frame
    var results: Dictionary = {}
    for count in [50, 500, 1000]:
        var fleet: Dictionary = _build_fleet(count)
        var draw_us: Array[int] = []
        var projection_us: Array[int] = []
        var previous_calls: int = int(view.draw_profile().get("calls", 0))
        for frame_index in range(SNAPSHOTS):
            # A changed source snapshot is projected, never advanced by UI.
            # Independent positions simulate genuine N14 time progression
            # while keeping source authority completely outside the map.
            for sid in fleet:
                var ship: Dictionary = fleet[sid]
                var transit: Dictionary = ship["transit"]
                var pos: Array = transit["position"]
                pos[0] = float(pos[0]) + 0.0005
            var t0: int = Time.get_ticks_usec()
            view.set_live_fleet(fleet)
            projection_us.append(Time.get_ticks_usec() - t0)
            view.queue_redraw()
            await process_frame
            await process_frame
            var profile: Dictionary = view.draw_profile()
            if int(profile.get("calls", 0)) <= previous_calls:
                _fail("real CanvasItem draw did not execute")
                return
            previous_calls = int(profile["calls"])
            draw_us.append(int(profile.get("last_usec", -1)))
        var average_draw: float = _average(draw_us)
        var average_snapshot: float = _average(projection_us)
        results[count] = {
            "draw_mean_us": average_draw,
            "draw_p95_us": _p95(draw_us),
            "snapshot_mean_us": average_snapshot,
            "snapshot_p95_us": _p95(projection_us)
        }
        print("P2 SHIP SCALE ", count, ": DRAW mean=", snappedf(
            average_draw, 0.01), "us p95=", results[count]["draw_p95_us"],
            "us; snapshot mean=", snappedf(average_snapshot, 0.01),
            "us p95=", results[count]["snapshot_p95_us"], "us")
    var draw_ratio: float = (float(results[500]["draw_mean_us"]) /
        maxf(1.0, float(results[50]["draw_mean_us"])))
    var snapshot_ratio: float = (float(
        results[500]["snapshot_mean_us"]) / maxf(
        1.0, float(results[50]["snapshot_mean_us"])))
    if draw_ratio > DRAW_RATIO_LIMIT or (
            snapshot_ratio > SNAPSHOT_RATIO_LIMIT):
        _fail("500 ships exhibit possible superlinear UI scaling: draw=" +
            str(draw_ratio) + " snapshot=" + str(snapshot_ratio))
        return
    var target: Dictionary = {"center": Vector2.ZERO,
        "components": [
            {"radius": 2.0, "angle": 15.0, "period": 700.0},
            {"radius": 0.005, "angle": 50.0, "period": 52.0}
        ]}
    if not NativeIntercept.valid_trajectory(target):
        _fail("authentic N14 solver cannot process a parented ephemeris")
        return
    var actual: Vector2 = NativeIntercept.position_after(target, 0.0)
    var solves_started: int = Time.get_ticks_usec()
    var usable: int = 0
    for i in range(500):
        var ship_position: Vector2 = Vector2(
            1.0 + float(i % 30) * 0.024, -0.3 + float(i / 30) * 0.013)
        var lead: Dictionary = NativeIntercept.aim_point(
            ship_position, 0.08, target, actual)
        if bool(lead.get("prediction_used", false)):
            usable += 1
    var solve_us: int = Time.get_ticks_usec() - solves_started
    if usable < 1:
        _fail("N14 guidance baseline could not compute intercept")
        return
    print("P2 SHIP SCALE N14: 500 separate authentic guidance calls ",
        solve_us, "us total, ", snappedf(float(solve_us) / 500.0,
        0.01), "us/call; successful=", usable)
    print("P2 SHIP SCALE PASS: 50/500/1000 CanvasItem moving snapshots, ",
        "500 genuine N14 guidance solves; drawing and simulation ",
        "are DIFFERENT benchmarks")
    view.queue_free()
    quit(0)


static func _build_fleet(count: int) -> Dictionary:
    var fleet: Dictionary = {}
    for i in range(count):
        var id: String = "bench-ship-%04d" % i
        var theta: float = TAU * float(i) / float(count)
        var orbit: float = 1.4 + float(i % 14) * 0.25
        fleet[id] = {
            "id": id, "name": "Benchmark " + id,
            "system_id": "system-sol", "location": "",
            "class": "freighter" if i % 3 == 0 else "miner",
            "transit": {
                "position": [cos(theta) * orbit, sin(theta) * orbit],
                "from": "bench-a", "to": "bench-b",
                "departure_tick": 0, "last_tick": 1,
                "token": i + 1
            }
        }
    return fleet


static func _average(samples: Array[int]) -> float:
    if samples.is_empty():
        return -1.0
    var total: int = 0
    for val in samples:
        total += val
    return float(total) / float(samples.size())


static func _p95(samples: Array[int]) -> int:
    if samples.is_empty():
        return -1
    var ordered: Array[int] = samples.duplicate()
    ordered.sort()
    return int(ordered[mini(ordered.size() - 1,
        ceili(float(ordered.size()) * 0.95) - 1)])


func _fail(reason: String) -> void:
    push_error("P2 SHIP SCALE FAIL: " + reason)
    quit(1)
