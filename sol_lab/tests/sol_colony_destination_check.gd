extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
const Calendar = preload("res://scripts/sol_calendar.gd")
const Flight = preload("res://scripts/sol_local_flight.gd")

func _initialize() -> void:
 call_deferred("run")

func advance(game: Control, time: float) -> void:
 game.native_time = time
 game._advance_construction()
 game._update_native_map()
 game._show_selected()

func play(target: String) -> Dictionary:
 var game = MAIN.instantiate()
 root.add_child(game)
 await process_frame
 game._pause()
 var sim = game.construction
 var earth_before: float = sim.colony_inventory("earth").supply.food
 var other := "mars" if target == "luna" else "luna"
 var plan: Dictionary = sim.expedition_preview(target)
 assert(plan.ore > 0 and plan.resupply_days > plan.port_days)
 game._native_body_selected({"id": target})
 game.colony_button.pressed.emit()
 assert(game.expedition_dialog.visible and game.expedition_summary.text.contains("местная шахта"))
 assert(int(game.expedition_food.value) == plan.recommended)
 if target == "mars":
  game.expedition_food.value = 2
 var extra: int = int(game.expedition_food.value)
 assert(sim.colony_inventory("earth").supply.food == earth_before)
 game.expedition_dialog.confirmed.emit()
 game.expedition_dialog.hide()
 assert(sim.expedition.ship.target == target)
 assert(not sim.depart_colonizer(other, 1))
 assert(sim.colony_inventory("earth").supply.food == earth_before - extra)
 var ship: Dictionary = sim.expedition.ship
 var arrival: float = ship.arrival
 var midpoint: float = lerpf(ship.departure, arrival, 0.5)
 advance(game, midpoint)
 var position: Vector2 = Flight.position(ship.trajectory, midpoint)
 if target == "mars":
  assert(ship.trajectory.orbit.has("solar"))
  assert(position.distance_to(Flight.gate(ship.trajectory.orbit, target, midpoint)) > 1)
  var pose: Dictionary = game.native_view._flight_pose("colonizer", ship, Time.get_ticks_usec())
  assert(pose.moving and pose.position.is_finite())
  var earth_at_save: float = sim.colony_inventory("earth").supply.food
  game._save_game()
  game._load_game()
  assert(sim.colony_inventory("earth").supply.food == earth_at_save)
  assert(sim.expedition.ship.target == target and sim.expedition.ship.food == 10 + extra)
  assert(sim.expedition.ship.arrival == arrival)
  assert(Flight.position(sim.expedition.ship.trajectory, midpoint).is_equal_approx(position))
 advance(game, arrival)
 assert(sim.colony_population(target) == 100 and sim.colony_population(other) == 0)
 assert(not sim.colony_inventory(other).present)
 assert(sim.colony_inventory(target).supply.food == 10 + extra)
 assert(sim.colony_inventory(target).supply.metals == 2 and sim.expedition.ship.is_empty())
 game._open_build()
 for kind in ["mining_rig", "spaceport"]:
  game.browser.build_controls[kind].button.pressed.emit()
  var site: String = game.browser.placement_options[0].id
  assert(site.begins_with(target + "-"))
  game.native_view.choose_placement(site)
  game.browser.select_placement(site)
  game.browser.placement_confirm.pressed.emit()
 assert(sim.sites.size() == 2)
 var ready: float = sim.sites.back().finish_native
 advance(game, ready)
 game._close_browser()
 game._open_manual_freight()
 assert(game.manual_destination.get_selected_metadata() == target)
 for index in game.manual_resource.item_count:
  if game.manual_resource.get_item_metadata(index) == "food":
   game.manual_resource.select(index)
 game.manual_amount.value = 10
 game._preview_manual_freight()
 assert(not game.manual_freight_dialog.get_ok_button().disabled)
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 var freight: Dictionary = sim.freight_status()
 assert(freight.order.source == "earth" and freight.order.destination == target)
 var freight_arrival: float = freight.arrival
 advance(game, freight_arrival - 0.001)
 var before: float = sim.colony_inventory(target).supply.food
 advance(game, freight_arrival)
 assert(is_equal_approx(sim.colony_inventory(target).supply.food, before + 10))
 assert(sim.freight_status().location == target and sim.meal_cycles[target].facility.fed)
 if target == "mars":
  game._save_game()
  game._load_game()
  assert(sim.freight_status().location == "mars")
  assert(sim.colony_inventory("mars").supply.food == before + 10)
  sim.set_freight_line_enabled(true)
  assert(sim._next_line_order().source == "mars")
  assert(sim._next_line_order().destination == "earth")
 assert(not sim.colony_inventory(other).present)
 if target == "mars":
  assert(sim.colony_inventory("mars").supply.ore >= plan.ore)
 var result: Dictionary = sim.snapshot()
 print("COLONY ", target, " flight=", plan.flight_days, " ore=", plan.ore, " port=", plan.port_days,
  " first_delivery=", Calendar.native_to_days(freight_arrival - arrival), " extra_food=", extra)
 await second_colony(game, target, other)
 game.queue_free()
 await process_frame
 return result

func run() -> void:
 var old_save: Dictionary = await play("luna")
 await play("mars")
 # Strip the v9 marker from an otherwise genuine lunar checkpoint.
 old_save.version = 8
 var game = MAIN.instantiate()
 root.add_child(game)
 await process_frame
 assert(game.construction.restore(JSON.parse_string(JSON.stringify(old_save))))
 assert(game.construction.colony_population("luna") == 100)
 assert(not game.construction.colony_inventory("mars").present)
 print("SOL_COLONY_DESTINATION_PASS")
 quit()

func order_building(game: Control, kind: String) -> void:
 game.browser.build_controls[kind].button.pressed.emit()
 var site: String = game.browser.placement_options[0].id
 game.browser.select_placement(site)
 game.browser.placement_confirm.pressed.emit()

func second_colony(game: Control, first: String, target: String) -> void:
 var sim = game.construction
 if first == "luna":
  assert(sim.configure_freight_line({
   "luna": {"resource": "food", "amount": 1, "reserve": 10, "policy": "full"},
   "earth": {"resource": "ore", "amount": 1, "reserve": 0, "policy": "empty"}}))
  sim.set_freight_line_enabled(true)
  advance(game, game.native_time)
  assert(sim.freight_status().order.destination == "earth")
 game._native_body_selected({"id": "earth"})
 game._open_build()
 for kind in ["shipyard", "refinery", "mining_rig", "mining_rig", "mining_rig"]:
  order_building(game, kind)
 advance(game, sim.sites.back().finish_native)
 game._close_browser()
 # Earn the cost through the ordinary Earth economy.
 for cycle in range(35):
  if sim.colony_inventory("earth").supply.metals >= 160:
   break
  advance(game, game.native_time + Calendar.days_to_native(30))
 assert(sim.colony_inventory("earth").supply.metals >= 160)
 var yard: String
 for facility in game.world.facilities:
  if facility.type == "shipyard":
   yard = facility.id
 game.colony_panel.built_buttons[yard].pressed.emit()
 game.yard_order.pressed.emit()
 advance(game, sim.ship_order.finish_native)
 assert(sim.freight_status(2).location == "earth")
 game._native_body_selected({"id": target})
 game.colony_button.pressed.emit()
 assert(game.colony_panel.selected_facility == yard)
 var earth_metal: float = sim.colony_inventory("earth").supply.metals
 game.yard_colonizer.pressed.emit()
 assert(sim.ship_order.is_empty())
 game.colonizer_order_dialog.confirmed.emit()
 game.colonizer_order_dialog.hide()
 assert(sim.ship_order.kind == "colonizer")
 assert(sim.colony_inventory("earth").supply.metals == earth_metal - 80)
 game.yard_cancel.pressed.emit()
 assert(sim.colony_inventory("earth").supply.metals == earth_metal)
 game.yard_colonizer.pressed.emit()
 game.colonizer_order_dialog.confirmed.emit()
 game.colonizer_order_dialog.hide()
 var ready: float = sim.ship_order.finish_native
 game._save_game()
 game._load_game()
 assert(sim.ship_order.kind == "colonizer" and sim.ship_order.finish_native == ready)
 assert(sim.colony_inventory("earth").supply.metals == earth_metal - 80)
 advance(game, ready)
 assert(sim.expedition.ship.id == "sol-colonizer-2")
 game._native_body_selected({"id": target})
 game.colony_button.pressed.emit()
 game.expedition_dialog.confirmed.emit()
 game.expedition_dialog.hide()
 var eta: float = sim.expedition.ship.arrival
 assert(not sim.depart_colonizer(first, 0) and not sim.depart_colonizer(target, 0))
 advance(game, (game.native_time + eta) * 0.5)
 game._save_game()
 game._load_game()
 assert(sim.expedition.ship.target == target and sim.colony_population(first) == 100)
 advance(game, eta)
 assert(sim.colony_population(first) == 100 and sim.colony_population(target) == 100)
 assert(sim.expedition.ship.is_empty() and sim.colony_destination() == first)
 if target != "mars":
  return
 game._open_build()
 order_building(game, "spaceport")
 advance(game, sim.sites.back().finish_native)
 game._close_browser()
 assert(sim.freight_line().enabled)
 if sim.freight_status().location != "transit":
  advance(game, game.native_time)
 assert(sim.freight_status().location == "transit")
 game._open_manual_freight()
 assert(game._manual_ship_slot() == 2 and game.manual_destination.get_selected_metadata() == "mars")
 for i in game.manual_resource.item_count:
  if game.manual_resource.get_item_metadata(i) == "food":
   game.manual_resource.select(i)
 game.manual_amount.value = 10
 var earth_food: float = sim.colony_inventory("earth").supply.food
 game._preview_manual_freight()
 assert(not game.manual_freight_dialog.get_ok_button().disabled)
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 assert(sim.colony_inventory("earth").supply.food == earth_food - 10)
 assert(sim.freight_status(2).order.destination == "mars")
 var moon_food: float = sim.colony_inventory("luna").supply.food
 var moon_ore: float = sim.colony_inventory("luna").supply.ore
 var mars_eta: float = sim.freight_status(2).arrival
 game._save_game()
 game._load_game()
 assert(sim.freight_status(2).arrival == mars_eta)
 if sim.freight_status().order.destination == "earth":
  advance(game, sim.freight_status().arrival)
 var lunar_eta: float = sim.freight_status().arrival
 assert(sim.freight_status().order.destination == "luna" and lunar_eta < mars_eta)
 advance(game, lunar_eta - 0.001)
 moon_food = sim.colony_inventory("luna").supply.food
 advance(game, lunar_eta)
 assert(sim.colony_inventory("luna").supply.food == moon_food + 1)
 assert(sim.colony_inventory("luna").supply.ore >= moon_ore)
 advance(game, mars_eta - 0.001)
 var mars_food: float = sim.colony_inventory("mars").supply.food
 var earth_ore: float = sim.colony_inventory("earth").supply.ore
 var lunar_food: float = sim.colony_inventory("luna").supply.food
 advance(game, mars_eta)
 assert(sim.colony_inventory("mars").supply.food == mars_food + 10)
 assert(sim.colony_inventory("luna").supply.food == lunar_food)
 assert(sim.colony_inventory("earth").supply.ore == earth_ore)
 advance(game, mars_eta)
 assert(sim.colony_inventory("mars").supply.food == mars_food + 10)
 print("SOL_DUAL_COLONY_SUPPLY_PASS")
