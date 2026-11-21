extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Runtime = preload("res://scripts/sector_runtime.gd")
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
 var sim = view.sim
 sim.advance(0)
 var vessel: Dictionary = sim.ships["freighter-01"]
 var order: Dictionary = vessel.flight
 assert(sim.planets[order.source].colony.stock.ore == 14 and order.amount == 10)
 assert(sim.input_status(order.target, "ore").begins_with("груз в пути"))
 sim.advance(18)
 assert(sim.planets[order.target].colony.stock.ore == 0)
 view._select_ship(vessel.id)
 var position: Vector2 = view._ship_position(vessel)
 view._save()
 sim.advance(70)
 view._load()
 vessel = sim.ships[vessel.id]
 assert(view._ship_position(vessel).is_equal_approx(position))
 assert(vessel.flight.amount == 10)
 sim.advance(order.arrival)
 assert(sim.planets[order.target].colony.stock.ore == 10)
 assert(not vessel.has("flight"))
 sim.advance(60)
 assert(sim.planets[order.target].colony.stock.metals == 8)
 assert(sim.planets[order.target].colony.last.day == 60)
 assert(vessel.flight.amount == 0 and vessel.reserved.amount == 10)
 var pickup: float = vessel.flight.arrival
 assert(sim.available(order.source, "ore") == 24)
 sim.advance(pickup)
 assert(vessel.flight.amount == 10 and not vessel.has("reserved"))
 sim.advance(vessel.flight.arrival)
 assert(sim.planets[order.target].colony.stock.ore == 10)
 print("SECTOR first arrival ", order.arrival, "; output 8 at 60; empty return from 60; next pickup 10 at ", pickup, "; second arrival ", sim.day)
 check_alternate()
 quit()

func check_alternate() -> void:
 var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Data))
 data.systems[0].planets[0].erase("colony")
 data.systems[1].planets[0].erase("colony")
 data.systems[7].planets[1].colony = {"owner":"Test","industry":"refinery",
  "stock":{"metals":3,"ore":10,"fuel":1}}
 data.systems[4].planets[1].colony = {"owner":"Test","industry":"factory",
  "stock":{"metals":0,"polymers":1}}
 data.systems[8].planets[0].colony = {"owner":"Test","industry":"mining_rig","stock":{}}
 data.ships[0].merge({"port":"s8/a","owner":"Test"}, true)
 var second: Dictionary = data.ships[0].duplicate()
 second.id = "second"
 data.ships.append(second)
 var sim = Runtime.new()
 sim.setup(data)
 sim.advance(0)
 var first: Dictionary = sim.ships["freighter-01"]
 assert(first.reserved.resource == "metals" and first.reserved.amount == 3)
 assert(not sim.ships.second.has("flight"))
 assert(sim.available("s7/b", "metals") == 0 and sim.planets["s7/b"].colony.stock.metals == 3)
 var checkpoint = JSON.parse_string(JSON.stringify(sim.snapshot()))
 sim.restore(checkpoint)
 first = sim.ships["freighter-01"]
 sim.advance(first.flight.arrival)
 assert(first.flight.target == "s4/b" and first.flight.amount == 3)
 assert(is_equal_approx(first.flight.arrival - first.flight.start, 28.6155286516462))
 assert(sim.planets["s4/b"].colony.stock.metals == 0)
 sim.advance(first.flight.arrival)
 assert(sim.planets["s4/b"].colony.stock.metals == 3)
 sim.advance(90)
 assert(sim.planets["s4/b"].colony.stock.components == 5)
 print("SECTOR alternative factory supplied; both ships saw one requirement, only one reserved it")
