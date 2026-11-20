extends SceneTree
## Actual Godot view acceptance: between-tick ship draws, both speeds,
## pause, changed speed, checkpoint reload, target at arrival and docking.
## No synthetic resource injection or alteration to simulation flight timing.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Flight = preload("res://scripts/sol_local_flight.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Profile = preload("res://scripts/sol_profile.gd")

var game: Control
var failures: Array[String] = []

func _initialize() -> void:
 call_deferred("_run")

func _check(condition: bool, label: String) -> void:
 if not condition:
  failures.append(label)
  push_error("SOL_SHIP_FLIGHT_FAIL: " + label)

func _body(id: String) -> void:
 for obj in game.world.get("bodies", []):
  if str(obj.get("id", "")) == id:
   game.native_view.body_selected.emit(obj)
   return
 _check(false, "missing body " + id)

func _pose(kind: String) -> Dictionary:
 return game.native_view._flight_draw_states.get(kind, {})

func _motion(kind: String, seconds: float) -> Dictionary:
 var start: int = Time.get_ticks_usec()
 var prior_tick: int = -1
 var prior_point: Vector2 = Vector2.ZERO
 var within_tick: int = 0
 var draws: int = 0
 var increasing: int = 0
 var previous_progress: float = -1.0
 while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
  await process_frame
  var row: Dictionary = _pose(kind)
  if row.is_empty() or not bool(row.get("moving", false)):
   continue
  var point: Vector2 = row["position"]
  var current_tick: int = game.visual_tick_count
  var progress: float = float(row["progress"])
  if prior_tick == current_tick and point.distance_to(prior_point) > 0.00001:
   within_tick += 1
  if previous_progress >= 0.0 and progress > previous_progress + 0.000001:
   increasing += 1
  previous_progress = progress
  prior_tick = current_tick
  prior_point = point
  draws += 1
 return {"draws":draws, "within_tick_moves":within_tick,
  "progress_increases":increasing}

func _step_until(when: float, label: String) -> void:
 for i in range(400):
  if game.native_time >= when:
   return
  game._step()
 _check(false, "could not reach " + label)

func _test_geometry() -> void:
 var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sol.json"))
 _check(Profile.apply_world(source), "lunar profile available")
 for phase in [0.0, 4.5, 11.0, 20.0]:
  for kind in ["colonizer", "freight"]:
   for origin in ["earth", "luna"]:
    var route := Flight.make(source, kind, origin, Calendar.days_to_native(phase))
    var t0: float = route.departure
    var t1: float = route.arrival
    var orbit: Dictionary = route.orbit
    var start := Flight.gate(orbit, origin, t0)
    var finish := Flight.gate(orbit, route.destination, t1)
    _check(Flight.position(route, t0) == start and Flight.position(route, t1) == finish,
     "terminal positions follow launch and arrival gates")
    _check(Flight.velocity(route, t0).distance_to(Flight.tangent(start, orbit.omega)) < 0.01 and
     Flight.velocity(route, t1).distance_to(Flight.tangent(finish, orbit.omega)) < 0.01,
     "zero relative velocity at both gates")
    var mid := (t0 + t1) * 0.5
    var native_day := Calendar.days_to_native(1.0)
    _check(Flight._peak_acceleration(route, t1 - t0) * native_day * native_day
     <= Flight.ACCELERATION[kind] * 1.00001, "flight respects the ship acceleration limit")
    var v_mid := Flight.velocity(route, mid) - Flight.tangent(Flight.position(route, mid), orbit.omega)
    for edge in [lerpf(t0, t1, 0.005), lerpf(t0, t1, 0.995)]:
     var relative := Flight.velocity(route, edge) - Flight.tangent(Flight.position(route, edge), orbit.omega)
     _check(relative.length() < v_mid.length() * 0.04, "smooth relative acceleration and braking")
    for index in range(161):
     var at := lerpf(t0, t1, index / 160.0)
     var point := Flight.position(route, at)
     _check(point.length() > Profile.SOL_BODY_RADII_KM.earth and
      point.distance_to(Flight.axis(orbit, at) * orbit.distance) > Profile.SOL_BODY_RADII_KM.luna,
      "trajectory stays clear of Earth and Moon")

func _check_screen(kind: String, ship: Dictionary) -> void:
 var view = game.native_view
 var route: Dictionary = ship.trajectory
 var frame: Dictionary = view._flight_frame(kind)
 _check(frame.opacity > 0.0, "flight visible at local map zoom")
 var axis: Vector2 = frame.axis
 var earth: Vector2 = frame.center
 var moon: Vector2 = earth + axis * frame.separation
 for index in range(61):
  var at := lerpf(route.departure, route.arrival, index / 60.0)
  var pixel: Vector2 = view._project_flight(Flight.position(route, at), route.orbit, at, frame, axis)
  _check(pixel.distance_to(earth) >= view._body_size(view._body_by_id("earth")) + frame.glyph * 8.0 - 0.01 and
   pixel.distance_to(moon) >= view._body_size(view._body_by_id("luna")) + frame.glyph * 8.0 - 0.01,
   "visible marker must clear both enlarged discs")
 var dock: Dictionary = view._flight_pose(kind, {"location": route.source}, Time.get_ticks_usec())
 var launch: Vector2 = view._project_flight(route.p, route.orbit, route.departure, frame, axis)
 _check(launch.distance_to(dock.position) < 0.001, "launch is the parked marker")
 var target: Vector2 = view._project_flight(Flight.position(route, route.arrival),
  route.orbit, route.arrival, frame, axis)
 if kind == "freight":
  var landed: Dictionary = view._flight_pose(kind, {"location": route.destination}, Time.get_ticks_usec())
  _check(target.distance_to(landed.position) < 0.001, "arrival is the parked marker")

func _launch_metrics(kind: String, ship: Dictionary) -> Dictionary:
 var eta: float = ship.arrival
 _check_screen(kind, ship)
 game._set_speed(1)
 game._pause()
 var x1: Dictionary = await _motion(kind, 0.8)
 _check(x1.within_tick_moves > 4 and x1.progress_increases > 3, "moves between x1 ticks")
 game._set_speed(16)
 var x16: Dictionary = await _motion(kind, 0.35)
 _check(x16.within_tick_moves > 3 and x16.progress_increases > 3, "moves between x16 ticks")
 game._pause()
 await process_frame
 var frozen: Vector2 = _pose(kind).get("position", Vector2.ZERO)
 var game_time: float = game.native_time
 await create_timer(0.20).timeout
 _check(_pose(kind).get("position") == frozen and game.native_time == game_time,
  "position and simulation time frozen on pause")
 game._save_game()
 game._load_game()
 await process_frame
 await process_frame
 _check(_pose(kind).get("position", Vector2.ZERO).distance_to(frozen) < 0.01,
  "reload preserves the paused rendered phase")
 var restored: Dictionary = game.construction.expedition.ship if kind == "colonizer" else game.construction.freight_status()
 var sample_time: float = (ship.departure + eta) * 0.5
 _check(absf(restored.arrival - eta) < 0.000001 and
  Flight.position(restored.trajectory, sample_time).distance_to(
   Flight.position(ship.trajectory, sample_time)) < 0.1,
  "reload preserves exact deadline and flight solution")
 return {"days": snappedf(Calendar.native_to_days(eta - ship.departure), 0.001),
  "x1_between_ticks": x1.within_tick_moves, "x16_between_ticks": x16.within_tick_moves}

func _finish_visible_freight(eta: float, speed: int) -> void:
 if speed == 1:
  game._set_speed(1)
  _step_until(eta - 0.6, "last part of approach at x1")
  await process_frame
  await process_frame
 game._pause()
 var largest_last_step := 0.0
 var previous: Vector2 = _pose("freight").position
 for i in range(120):
  await process_frame
  var pose := _pose("freight")
  if pose.get("progress", 1.0) >= 0.8:
   largest_last_step = maxf(largest_last_step, previous.distance_to(pose.position))
  previous = pose.position
  if not pose.moving:
   break
 game._pause()
 _check(not _pose("freight").moving and largest_last_step < 5.0,
  "rendered final approach joins parked marker without a jump at x%d" % speed)

func _run() -> void:
 _test_geometry()
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_SHIP_FLIGHT_FAIL: run with isolated XDG_DATA_HOME")
  quit(1)
  return
 Engine.max_fps = 60
 root.size = Vector2i(1366, 768)
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 game.native_view._zoom = 4.0
 game.native_view._focused_body_id = "earth"
 _body("luna")
 game._colonize_luna()
 var colonizer: Dictionary = game.construction.expedition.ship.duplicate(true)
 await process_frame
 var colony_metric: Dictionary = await _launch_metrics("colonizer", colonizer)
 _step_until(colonizer.arrival, "colonizer arrival")
 _check(game.construction.expedition.ship.is_empty(), "colonizer merges at the calculated ETA")
 for id in ["mining_rig", "spaceport"]:
  _check(game.construction.order("luna", id).ok, "pay for lunar " + id)
 _step_until(game.construction.sites[0].finish_native, "lunar port")
 game._send_freighter(true)
 var outbound: Dictionary = game.construction.freight_status()
 await process_frame
 var out_metric: Dictionary = await _launch_metrics("freight", outbound)
 var earth_food: float = game.construction.colony_food("earth").stock
 var initial_moon_food: float = game.construction.colony_food("luna").stock
 await _finish_visible_freight(outbound.arrival, 1)
 _check(game.construction.colony_food("luna").stock >= initial_moon_food + 8 and
  game.construction.colony_food("luna").covered and game.construction.freight_status().location == "luna",
  "first food arrives before colony starvation and unloads once")
 _check(game.construction.colony_food("earth").stock >= earth_food, "load does not debit twice")
 # The first workshop batches use the real colony stock and clock.
 game._set_speed(16)
 for i in range(400):
  if game.construction.colony_inventory("luna").supply.get("ore", 0) >= 10:
   break
  game._step()
 _body("earth")
 var before_ore: float = game.construction.colony_inventory("earth").supply.ore
 game._send_freighter()
 var inbound: Dictionary = game.construction.freight_status()
 _check(inbound.get("order", {}).get("source") == "luna", "freighter starts Moon to Earth")
 if inbound.has("trajectory"):
  await process_frame
  var in_metric: Dictionary = await _launch_metrics("freight", inbound)
  await _finish_visible_freight(inbound.arrival, 16)
  _check(game.construction.freight_status().location == "earth" and
   game.construction.colony_inventory("earth").supply.ore == before_ore + 10, "ore unloads exactly at ETA")
  print("SOL_SHIP_FLIGHT_TIMES ", JSON.stringify({"colonizer": colony_metric,
   "earth_to_moon": out_metric, "moon_to_earth": in_metric,
   "first_food_days_after_settlement": Calendar.native_to_days(outbound.arrival - colonizer.arrival)}))
 DirAccess.remove_absolute(Lab.USER_SAVE)
 if failures.is_empty():
  print("SOL_SHIP_FLIGHT_PASS")
 quit(0 if failures.is_empty() else 1)
