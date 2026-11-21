extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Calendar = preload("res://scripts/sol_calendar.gd")

func _initialize() -> void:
 run.call_deferred()

func play(intervene: bool) -> Dictionary:
 var script: GDScript = load("res://scripts/main.gd")
 script.start_mars_trade = true
 var game = Main.instantiate()
 root.add_child(game)
 await process_frame
 game._pause()
 var sim = game.construction
 assert(sim.freight_line().enabled and sim._colony_owner("mars") != sim._colony_owner("earth"))
 assert(sim.colony_inventory("luna").supply.food == 6)
 if intervene:
  game._open_colony_logistics()
  assert(game.trade_button.visible and not game.trade_button.disabled)
  game.trade_button.pressed.emit()
  assert(not sim.freight_line().enabled)
  assert(sim.colony_inventory("earth").supply.metals == 12)
  assert(sim.colony_inventory("mars").supply.ore == 4)
  assert(sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot()))))
 var minimum := 6.0
 var hungry := -1
 var first_output := -1
 var metal_trip := -1
 var fuel_arrived := -1
 for tick in range(1, 13001):
  var day := tick / 10.0
  game.native_time = Calendar.days_to_native(day)
  game._advance_construction()
  var moon: float = sim.colony_inventory("luna").supply.food
  minimum = minf(minimum, moon)
  if hungry < 0 and not sim.meal_cycles.luna.facility.fed:
   hungry = floori(day)
  for building in game.world.facilities:
   if building.body == "mars" and building.type == "refinery" and (
    building.has("last_batch_native") and first_output < 0):
    first_output = ceili(Calendar.native_to_days(building.last_batch_native))
  if metal_trip < 0 and sim.mars_trade.phase == "metal_out":
   metal_trip = ceili(day)
  if metal_trip > 0 and sim.colony_inventory("mars").movement.get("fuel", {}).get("in", 0) >= 4:
   fuel_arrived = ceili(day)
   break
 var refineries := 0
 for building in game.world.facilities:
  if building.body == "mars" and (building.type == "refinery" or (
   building.type == "construction_site" and building.get("construction_building_id") == "refinery")):
   refineries += 1
 assert(refineries == 1)
 var result := {"first_output": first_output, "moon_min": minimum, "hungry": hungry,
  "metal_trip": metal_trip, "fuel_arrived": fuel_arrived,
  "phase": sim.mars_trade.phase, "npc": sim.freight_status(2).get("arrival", -1), "moon_final": sim.colony_inventory("luna").supply.food}
 print("MARS_TRADE ", "charter" if intervene else "autonomous", " ", result)
 game.queue_free()
 await process_frame
 return result

func check_one_missed_run() -> void:
 var script: GDScript = load("res://scripts/main.gd")
 script.start_mars_trade = true
 var game = Main.instantiate()
 root.add_child(game)
 await process_frame
 game._pause()
 var sim = game.construction
 sim.set_freight_line_enabled(false)
 sim.advance_to(Calendar.days_to_native(60))
 assert(sim.meal_cycles.luna.facility.fed and sim.colony_inventory("luna").supply.food == 2)
 sim.set_freight_line_enabled(true)
 sim.advance_to(Calendar.days_to_native(60))
 assert(sim.freight_status().order.destination == "luna")
 sim.advance_to(sim.freight_status().arrival)
 assert(sim.colony_inventory("luna").supply.food == 4)
 game.queue_free()
 await process_frame

func run() -> void:
 await check_one_missed_run()
 var autonomous := await play(false)
 var assisted := await play(true)
 assert(autonomous.first_output > assisted.first_output and assisted.first_output > 0)
 assert(autonomous.hungry < 0 and assisted.hungry > 0)
 assert(autonomous.fuel_arrived > 0 and assisted.fuel_arrived > 0)
 print("SOL_MARS_TRADE_START_PASS")
 quit()
