extends SceneTree
## From sol_lab: XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/sol_food_economy_check.gd
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")

var game: Control
var failed := false

func _initialize() -> void:
 run.call_deferred()

func check(ok: bool, message: String) -> void:
 if not ok:
  failed = true
  push_error(message)

func press(button: Button) -> void:
 check(button != null and button.is_visible_in_tree() and not button.disabled, "Expected enabled button")
 if button != null and not button.disabled:
  button.pressed.emit()

func select_body(id: String) -> void:
 for body in game.world.bodies:
  if body.id == id:
   game.native_view.body_selected.emit(body)
   return

func build(ids: Array[String]) -> void:
 game.colony_panel.build_requested.emit()
 for id in ids:
  press(game.browser.build_controls[id].button)
 game.browser.close_requested.emit()

func stock(body: String, resource: String) -> float:
 return float(game.construction.colony_inventory(body).supply.get(resource, 0))

func food(body: String) -> Dictionary:
 return game.construction.colony_food(body)

func freight() -> Dictionary:
 return game.construction.freight_status()

func wait_until(condition: Callable, message: String, ticks: int = 900) -> void:
 for i in range(ticks):
  if condition.call():
   return
  game._step()
 check(condition.call(), message)

func advance(deadline: float) -> void:
 wait_until(func(): return game.native_time >= deadline, "Calendar stalled")

func configure_line(ore_reserve: int) -> void:
 game.colony_panel.line_requested.emit()
 var outbound: Dictionary = game.freight_line_fields.luna
 var inbound: Dictionary = game.freight_line_fields.earth
 outbound.resource.select(1) # Food on the Moon-bound leg.
 outbound.amount.get_line_edit().text = "10"
 outbound.reserve.get_line_edit().text = "4"
 inbound.amount.get_line_edit().text = "10"
 inbound.reserve.get_line_edit().text = str(ore_reserve)
 game.freight_line_dialog.get_ok_button().pressed.emit()

func load_checkpoint(data: Dictionary) -> void:
 data.paused = true
 data.speed = 16
 var file := FileAccess.open(Lab.USER_SAVE, FileAccess.WRITE)
 file.store_string(JSON.stringify(data, "", true, true))
 file.close()
 game._load_game()
 check(game.message_line.text.begins_with("Игра загружена"), "Checkpoint rejected")

func check_migration() -> void:
 var actual: Dictionary = game.construction.snapshot()
 var legacy := actual.duplicate(true)
 legacy.version = 4
 for facility in legacy.facilities:
  facility.erase("next_meal_native")
  facility.erase("fed")
 for market in legacy.markets:
  if market.facility_id == "luna-colony":
   market.supply.food = 7
 load_checkpoint(legacy)
 check(stock("luna", "food") == 17, "Migration must add food to the existing stock once")
 load_checkpoint(legacy)
 game._save_game()
 game._load_game()
 check(stock("luna", "food") == 17 and stock("earth", "food") > 24, "Loading must not repeat the grant")
 load_checkpoint(actual)

func run() -> void:
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_CONFIG):
  push_error("Run with an isolated user-data directory")
  quit(1)
  return
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene
 press(game.pause_button)
 press(game.speed_buttons[16])
 build(["refinery"])
 advance(Calendar.days_to_native(120))
 check(stock("earth", "food") == 48 and stock("earth", "water") == 12 and food("earth").rate == 4,
  "The starter farm must cover the population and replenish stock with local water")
 check(stock("earth", "metals") == 31 and stock("earth", "ore") == 10 and stock("earth", "fuel") == 34,
  "The starting inputs must enable two refinery batches")

 select_body("luna")
 press(game.colony_button)
 var landing: float = game.construction.expedition.ship.arrival
 advance(landing)
 var ration: Dictionary = food("luna")
 check(ration.stock == 10 and ration.rate == 2 and ration.days == 150 and stock("luna", "metals") == 2,
  "The colonizer must land with food, settlers and exactly two metals")
 check_migration()
 build(["spaceport", "mining_rig"])
 wait_until(func(): return game.construction.sites.is_empty(), "Lunar mine and port not completed")
 configure_line(0)
 press(game.freight_line_toggle)
 game._step()
 var outbound := freight()
 check(outbound.get("order", {}).get("resource") == "food" and food("luna").incoming == 10 and
  food("luna").stock < 10 and game.colony_panel.food_status.text.contains("В пути: +10 еды"),
  "Projected delivery must be separate from the food in stock")
 var paused_time: float = game.native_time
 var next_meal: float = game.construction.meal_cycles.luna.facility.next_meal_native
 var lunar_food := food("luna")
 var earth_food := food("earth")
 await create_timer(0.25).timeout
 game._save_game()
 game._load_game()
 game._load_game()
 check(game.paused and game.native_time == paused_time and food("luna") == lunar_food and
  food("earth") == earth_food and freight() == outbound and
  game.construction.meal_cycles.luna.facility.next_meal_native == next_meal,
  "Pause and repeated loading must preserve food, meal deadlines and cargo")
 if failed:
  quit(1)
  return

 var working_line_checkpoint: Dictionary = game.construction.snapshot()
 advance(outbound.arrival)
 var before_empty_return := stock("earth", "ore")
 check(stock("luna", "ore") == 0 and game.return_freight_button.text.contains("пустым"),
  "The colony can recall an empty freighter before the first ore batch")
 press(game.return_freight_button)
 game._save_game()
 game._load_game()
 check(freight().get("order", {}).get("amount") == 0, "An empty return must survive loading")
 advance(freight().arrival)
 check(freight() == {"location": "earth"} and stock("earth", "ore") == before_empty_return,
  "An empty freighter must return without crediting ore")
 load_checkpoint(working_line_checkpoint)

 var arrivals: Array[float] = []
 var returned := 0
 for i in range(900):
  var prev := freight()
  game._step()
  if prev.get("location") == "transit" and game.native_time >= prev.arrival:
   if prev.order.destination == "luna":
    arrivals.append(game.native_time)
   elif prev.order.resource == "ore":
    returned += int(prev.order.amount)
  if not food("luna").covered:
   check(false, "The working line caused a lunar food shortage")
   break
  if returned == 30:
   break
 check(returned == 30 and arrivals.size() == 3 and stock("earth", "ore") > 0,
  "Three full automatic circles must deliver thirty ore")
 var intervals: Array[float] = []
 for i in range(1, arrivals.size()):
  intervals.append(snappedf(Calendar.native_to_days(arrivals[i] - arrivals[i - 1]), 0.1))

 configure_line(100) # Hold the freighter for a return batch that the colony cannot fill.
 wait_until(func(): return (not food("luna").covered and
  game.construction.production_summary("luna").contains("поселенцам не хватает еды")),
  "The shortage must stop the lunar mine")
 var stalled_ore := stock("luna", "ore")
 advance(game.native_time + Calendar.days_to_native(30))
 check(stock("luna", "ore") == stalled_ore and game.colony_panel.food_status.text.contains("Дефицит еды"),
  "The colony panel must explain the stoppage and the mine must stay idle")
 check(freight() == {"location": "luna"}, "The freighter should be waiting on Luna")
 press(game.return_freight_button)
 check(not game.construction.freight_line().enabled and freight().order.amount == 10,
  "The manual return must break the wait and carry available ore")
 advance(freight().arrival)
 press(game.food_freight_button)
 check(food("luna").stock == 0 and food("luna").incoming == 10, "Food must not be credited in flight")
 advance(freight().arrival)
 var ore_after_return := stock("luna", "ore")
 wait_until(func(): return stock("luna", "ore") > ore_after_return, "The mine did not recover", 150)
 check(food("luna").covered and stock("luna", "ore") - ore_after_return == 3,
  "The mine must produce three ore after food covers a cycle")
 print("SOL_FOOD_ECONOMY ", JSON.stringify({"moon_food_per_30_days": ration.rate,
  "starter_food": ration.stock, "ore_per_cycle": stock("luna", "ore") - ore_after_return,
  "delivery_intervals_days": intervals, "ore_returned": returned}))
 DirAccess.remove_absolute(Lab.USER_SAVE)
 if not failed:
  print("SOL_FOOD_ECONOMY_PASS")
 quit(1 if failed else 0)
