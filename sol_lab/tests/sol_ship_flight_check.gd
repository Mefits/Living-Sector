extends SceneTree
## Actual Godot view acceptance: between-tick ship draws, both speeds,
## pause, changed speed, checkpoint reload, target at arrival and docking.
## No synthetic resource injection or alteration to simulation flight timing.
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Flight = preload("res://scripts/view/sol_flight_visual.gd")

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
 for ends in [[Vector2(0, 0), Vector2(85, -24)],
              [Vector2(85, -24), Vector2(0, 0)]]:
  var a: Vector2 = ends[0]
  var b: Vector2 = ends[1]
  var curve: PackedVector2Array = Flight.curve(a, b)
  _check(Flight.point(curve, 0.0).distance_to(a) < 0.0001,
   "flight must start at departure point")
  _check(Flight.point(curve, 1.0).distance_to(b) < 0.0001,
   "flight must reach predicted arrival point")
  for p in [0.05, 0.3, 0.7, 0.97]:
   var tangent: Vector2 = Flight.tangent(curve, p)
   var derivative: Vector2 = Flight.point(curve, p+0.0001)-Flight.point(curve, p-0.0001)
   _check(tangent.dot(derivative.normalized()) > 0.999,
    "heading follows tangent")
 _check(Flight.fraction(2.0, 12.0, 7.0) == 0.5,
  "display fraction derives from fixed ship timestamps")

func _run() -> void:
 _test_geometry()
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("SOL_SHIP_FLIGHT_FAIL: run with isolated XDG_DATA_HOME")
  quit(1)
  return
 var old_fps: int = Engine.max_fps
 Engine.max_fps = 60
 root.size = Vector2i(1366, 768)
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 game._pause()
 _body("luna")
 game._colonize_luna()
 _check(game.construction.expedition.ship.get("location") == "transit",
  "colonizer launched by game")
 var original_arrival: float = float(game.construction.expedition.ship["arrival"])
 var original_departure: float = float(game.construction.expedition.ship["departure"])
 _check(original_arrival > original_departure, "colonizer real ETA")
 game._pause() # x1 running
 var colony_x1: Dictionary = await _motion("colonizer", 1.1)
 _check(int(colony_x1["within_tick_moves"]) > 5,
  "colonizer moves BETWEEN x1 simulation ticks")
 _check(int(colony_x1["progress_increases"]) > 5,
  "colonizer progresses smoothly at x1")
 game._pause()
 await process_frame
 var frozen: float = float(game.native_view._display_native_time(
  Time.get_ticks_usec()))
 await create_timer(0.25).timeout
 _check(absf(float(game.native_view._display_native_time(
  Time.get_ticks_usec())) - frozen) < 0.000001,
  "visual flight time must stop on pause")
 game._set_speed(16)
 await create_timer(0.15).timeout
 _check(absf(float(game.native_view._display_native_time(
  Time.get_ticks_usec())) - frozen) < 0.000001,
  "changing speed while paused cannot move the ship")
 game._pause()
 var colony_x16: Dictionary = await _motion("colonizer", 0.35)
 _check(int(colony_x16["within_tick_moves"]) > 3,
  "colonizer moves BETWEEN x16 simulation ticks")
 var visual_before: Dictionary = game.native_view._flight_pose(
  "colonizer", game.construction.expedition.ship, Time.get_ticks_usec())
 var clock_before: float = game.native_time
 game._save_game()
 game._load_game()
 _check(game.construction.expedition.ship.get("location") == "transit",
  "colonizer still in flight after save/load")
 _check(game.native_time == clock_before and
  absf(float(game.construction.expedition.ship["arrival"]) - original_arrival) < 0.000001,
  "loading does not change colonizer flight duration")
 var visual_after: Dictionary = game.native_view._flight_pose(
  "colonizer", game.construction.expedition.ship, Time.get_ticks_usec())
 _check(not visual_after.is_empty() and not visual_before.is_empty(),
  "colonizer visual route available after loading")
 if not visual_after.is_empty() and not visual_before.is_empty():
  var flight_length: float = (visual_before["control"][3] as Vector2).distance_to(
   visual_before["control"][0])
  _check((visual_before["position"] as Vector2).distance_to(
   visual_after["position"]) < maxf(3.0,flight_length*0.12),
   "loading in-flight ship must not teleport across its route")
 # Arrival itself is simulation-owned; the preview MUST predict Moon at ETA.
 var visual: Dictionary = game.native_view._flight_pose(
  "colonizer", game.construction.expedition.ship, Time.get_ticks_usec())
 var target: Vector2 = game.native_view._native_body_screen(
  game.native_view._body_by_id("luna"), original_arrival,
  game.native_view._orbit_scale()) + game.native_view._flight_offset("colonizer")
 _check((visual["control"][3] as Vector2).distance_to(target) < 0.01,
  "arrival trajectory predicts Moon at actual ETA")
 game._pause()
 _step_until(original_arrival, "colonizer arrival")
 _check(game.construction.expedition.ship.is_empty() and
  float(game.construction.colony_inventory("luna").get("supply", {}).get("metals", 0.0)) == 2.0,
  "colony receipt is authoritative and exact")
 _check(game.native_view._docking_visuals.has("colonizer"),
  "colonizer has a visual final dock transition")
 game._pause()
 await create_timer(0.28).timeout
 _check(not game.native_view._docking_visuals.has("colonizer"),
  "colonizer docks and visual transition retires")

 # Build BOTH sites from the real two-unit lunar market, no free cargo.
 game._pause()
 _check(bool(game.construction.order("luna","mining_rig").get("ok",false)),
  "lunar mine paid")
 _check(bool(game.construction.order("luna","spaceport").get("ok",false)),
  "lunar port paid")
 _check(float(game.construction.colony_inventory("luna").get(
  "supply", {}).get("metals",-1.0)) == 0.0, "lunar metal spent once")
 _step_until(float(game.construction.sites[0].get("finish_native",0.0)),
  "lunar port construction")
 _check(game.construction.sites.is_empty(), "port and mine built")
 _body("luna")
 game._send_freighter() # from Earth to Moon
 _check(game.construction.freight_status().get("location") == "transit",
  "freighter departed from Earth")
 var outbound: Dictionary = game.construction.freight_status()
 var outbound_arrival: float = float(outbound["arrival"])
 var moon_before: float = float(game.construction.colony_inventory(
  "luna").get("supply",{}).get("metals",0))
 # The freighter was launched while paused. Set x1, then unpause
 # ONCE and keep running across the x1 -> x16 comparison.
 game._set_speed(1)
 game._pause()
 var freight_x1: Dictionary = await _motion("freight", 1.0)
 _check(int(freight_x1["within_tick_moves"]) > 5,
  "freighter moves between x1 ticks")
 game._set_speed(16)
 var freight_x16: Dictionary = await _motion("freight", 0.35)
 _check(int(freight_x16["within_tick_moves"]) > 3,
  "freighter moves between x16 ticks")
 game._pause()
 _step_until(outbound_arrival, "freight to Moon")
 _check(game.construction.freight_status().get("location") == "luna",
  "freighter docked at Moon on simulation deadline")
 _check(float(game.construction.colony_inventory("luna").get(
  "supply", {}).get("metals",0)) == moon_before + 10,
  "cargo delivered exactly on simulation docking")
 _check(game.native_view._docking_visuals.has("freight"),
  "freighter has continuous visual docking")
 game._pause() # resume interpolation so the final approach can complete
 await create_timer(0.28).timeout
 _check(not game.native_view._docking_visuals.has("freight"),
  "freighter dock transitions to parked icon")
 # Native mine eventually supplies enough ore for the opposite trip.
 game._pause()
 var ready: bool = false
 for i in range(400):
  if float(game.construction.colony_inventory("luna").get(
       "supply",{}).get("ore",0)) >= 10.0:
   ready = true
   break
  game._step()
 _check(ready, "lunar mining funds real return cargo")
 if ready:
  _body("earth")
  game._send_freighter()
  var inbound: Dictionary = game.construction.freight_status()
  _check(inbound.get("location") == "transit" and str(
   inbound.get("order",{}).get("source","")) == "luna",
   "real return trip from Moon to Earth")
  var incoming: Dictionary = game.native_view._flight_pose(
   "freight", inbound, Time.get_ticks_usec())
  var arrival_target: Vector2 = game.native_view._native_body_screen(
   game.native_view._body_by_id("earth"), float(inbound["arrival"]),
   game.native_view._orbit_scale()) + game.native_view._flight_offset("freight")
  _check((incoming["control"][3] as Vector2).distance_to(arrival_target) < 0.01,
   "return trajectory predicts moving Earth at delivery ETA")
  var ore_before: float = float(game.construction.colony_inventory(
   "earth").get("supply",{}).get("ore",0.0))
  _step_until(float(inbound["arrival"]), "return flight")
  _check(game.construction.freight_status().get("location") == "earth",
   "freighter docked back at Earth on deadline")
  _check(float(game.construction.colony_inventory("earth").get(
   "supply",{}).get("ore",0.0)) == ore_before + 10,
   "return cargo delivered only by simulation")
 print("SOL_SHIP_FLIGHT_RESULT ", JSON.stringify({
  "colonizer_x1":colony_x1, "colonizer_x16":colony_x16,
  "freight_x1":freight_x1, "freight_x16":freight_x16,
  "colonizer_eta_native":original_arrival-original_departure,
  "outbound_eta_native":outbound_arrival-float(outbound["departure"]),
  "assertions_failed":failures.size()
 }))
 Engine.max_fps = old_fps
 if failures.is_empty():
  print("SOL_SHIP_FLIGHT_PASS")
  quit(0)
 else:
  print("SOL_SHIP_FLIGHT_FAILURES ",JSON.stringify(failures))
  quit(1)
