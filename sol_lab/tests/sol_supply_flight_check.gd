extends SceneTree
## Run with a disposable user data directory: exercises real save/load buttons.
func _initialize() -> void:
 call_deferred("_check")

func _check() -> void:
 if FileAccess.file_exists("user://sol_lab_construction_save_v1.json"):
  push_error("Use an empty test user data directory to preserve your save.")
  quit(1)
  return
 var game = load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 var sim = game.construction
 var earth_start: float = sim.colony_inventory("earth").supply.metals
 game._native_body_selected({"id":"luna"})
 game.colony_button.pressed.emit()
 game.native_time = sim.expedition.ship.arrival
 game._advance_construction()
 game._order_build("luna", "mining_rig")
 game._order_build("luna", "spaceport")
 assert(game.freight_button.disabled and not sim.dispatch_freight())
 assert(sim.colony_inventory("luna").supply.metals == 0)
 game.native_time = sim.sites.back().finish_native
 game._advance_construction()
 assert(game.freight_button.visible and not game.freight_button.disabled)
 game.freight_button.pressed.emit()
 assert(sim.colony_inventory("earth").supply.metals == earth_start - 10)
 assert(sim.freight.cargo == 10 and sim.colony_inventory("luna").supply.metals == 0)
 assert(not sim.dispatch_freight())
 game.native_time = (game.native_time + sim.freight.arrival) / 2
 game._advance_construction()
 game._pause()
 game._process(10)
 assert(game.native_time < sim.freight.arrival and sim.freight.cargo == 10)
 game._save_game()
 game.native_time = sim.freight.arrival
 game._advance_construction()
 game._load_game()
 assert(sim.freight.location == "transit" and sim.freight.cargo == 10)
 assert(sim.colony_inventory("luna").supply.metals == 0)
 game.native_time = sim.freight.arrival
 game._advance_construction()
 game._advance_construction()
 assert(sim.colony_inventory("luna").supply.metals == 10 and sim.freight.cargo == 0)
 assert(sim.freight.location == "luna" and not sim.dispatch_freight())
 game._order_build("luna", "refinery")
 assert(sim.colony_inventory("luna").supply.metals == 9)
 var legacy: Dictionary = sim.snapshot()
 legacy.erase("freight")
 assert(sim.restore(legacy))
 assert(_earth_ports(sim) == 1)
 legacy.facilities = legacy.facilities.filter(func(f): return f.id != "earth-starter-spaceport")
 assert(sim.restore(legacy))
 assert(_earth_ports(sim) == 1)
 sim.world.facilities = sim.world.facilities.filter(func(f): return f.id != "earth-starter-spaceport")
 assert(sim.order("earth", "spaceport").ok)
 legacy = sim.snapshot()
 legacy.erase("freight")
 assert(sim.restore(legacy) and _earth_ports(sim) == 0)
 sim.advance_to(sim.sites.back().finish_native)
 assert(_earth_ports(sim) == 1)
 print("SOL_SUPPLY_FLIGHT_PASS")
 quit()

func _earth_ports(sim) -> int:
 return sim.world.facilities.filter(func(f): return f.body == "earth" and f.type == "spaceport").size()
