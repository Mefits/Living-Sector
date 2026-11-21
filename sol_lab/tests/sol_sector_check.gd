extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Data := "res://data/sector_start.json"

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 var game = Main.instantiate()
 root.add_child(game)
 await process_frame
 game._on_game_menu(6)
 var view = game.sector_view
 view.halted = true
 await process_frame
 assert(not view.send.disabled)
 view.send.pressed.emit()
 var sim = view.sim
 var order: Dictionary = sim.ships["freighter-01"].flight
 assert(sim.planets[order.source].colony.stock.ore == 14 and order.amount == 10)
 sim.advance(18)
 assert(sim.planets[order.target].colony.stock.ore == 0)
 var position: Vector2 = view._ship_position(sim.ships["freighter-01"])
 view._save()
 sim.advance(70)
 view._load()
 assert(view._ship_position(sim.ships["freighter-01"]).is_equal_approx(position))
 assert(sim.ships["freighter-01"].flight.amount == 10)
 sim.advance(order.arrival)
 assert(sim.planets[order.target].colony.stock.ore == 10)
 sim.advance(60)
 assert(sim.planets[order.target].colony.stock.metals == 8)
 assert(sim.planets[order.target].colony.last.day == 60)
 sim.advance(120)
 assert(sim.planets[order.target].colony.stock.metals == 8)
 print("SECTOR ore 24 -> 14; cargo 10; received 10 at ", order.arrival, "; metal 8 at day 60")
 var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Data))
 data.systems[7].planets[1].colony = data.systems[0].planets[0].colony
 data.systems[4].planets[1].colony = data.systems[1].planets[0].colony
 data.ships[0].port = "s7/b"
 sim.setup(data)
 assert(sim.dispatch("freighter-01", "s7/b", "s4/b", "ore", 10))
 var new_order: Dictionary = sim.ships["freighter-01"].flight
 assert(not is_equal_approx(new_order.arrival, order.arrival))
 sim.advance(new_order.arrival)
 assert(sim.planets["s4/b"].colony.stock.ore == 10 and sim.planets["s1/a"].colony.stock.ore == 0)
 print("SECTOR alternate arrival ", new_order.arrival)
 quit()
