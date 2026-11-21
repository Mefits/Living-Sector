extends SceneTree
## From sol_lab: XDG_DATA_HOME="$(mktemp -d)" godot --headless --path . --script tests/sol_freight_round_trip_check.gd
const Scene = preload("res://scenes/main.tscn")
const Lab = preload("res://scripts/main.gd")
const Calendar = preload("res://scripts/sol_calendar.gd")

var game: Control
var failed := false

func _initialize() -> void:
 run.call_deferred()

func check(condition: bool, message: String) -> void:
 if not condition:
  failed = true
  push_error(message)

func fresh_scene() -> void:
 change_scene_to_packed(Scene)
 await scene_changed
 game = current_scene

func press(label: String) -> void:
 if label in ["Сохранить", "Загрузить"]:
  for menu in game.top_bar.find_children("*", "MenuButton", true, false):
   menu.get_popup().id_pressed.emit(2 if label == "Сохранить" else 3)
   return
 for control in game.find_children("*", "Button", true, false):
  if control.text == label and control.is_visible_in_tree():
   check(not control.disabled, "Disabled button: " + label)
   control.pressed.emit()
   return
 check(false, "Missing button: " + label)

func select_body(id: String) -> void:
 for body in game.world.bodies:
  if body.id == id:
   game.native_view.body_selected.emit(body)
   return

func stock(body: String, resource: String) -> float:
 return float(game.construction.colony_inventory(body).supply.get(resource, 0))

func freight() -> Dictionary:
 return game.construction.freight_status()

func advance_to(deadline: float) -> void:
 for i in range(200):
  if game.native_time >= deadline:
   return
  game._step()
 check(false, "Game clock did not reach the deadline")

func build(id: String) -> void:
 var button: Button = game.browser.build_controls[id].button
 check(not button.disabled, "Cannot order: " + id)
 button.pressed.emit()

func load_checkpoint(data: Dictionary) -> void:
 data.paused = true
 data.speed = 16
 var file := FileAccess.open(Lab.USER_SAVE, FileAccess.WRITE)
 file.store_string(JSON.stringify(data, "", true, true))
 file.close()
 press("Загрузить")
 check(game.message_line.text.begins_with("Игра загружена"), "Checkpoint rejected")

func load_v2_freight(old_state: Dictionary) -> void:
 var data: Dictionary = game.construction.snapshot()
 data.version = 2
 data.freighter = old_state
 data.erase("freight_line")
 load_checkpoint(data)

func run() -> void:
 if FileAccess.file_exists(Lab.USER_SAVE) or FileAccess.file_exists(Lab.USER_SAVE + ".tmp") or (
     FileAccess.file_exists(Lab.USER_CONFIG)):
  push_error("Run the freight check with an isolated user-data directory")
  quit(1)
  return
 await fresh_scene()
 press("Пауза")
 press("×16")
 select_body("luna")
 press("Экспедиция · Луна")
 game.expedition_dialog.confirmed.emit()
 game.expedition_dialog.hide()
 advance_to(game.construction.expedition.ship.arrival)
 press("Строить")
 build("mining_rig")
 build("spaceport")
 game.browser.close_requested.emit()
 check(not game.construction.freight_block_reason(game.selected).is_empty(), "A port under construction must block shipping")
 if failed:
  quit(1)
  return
 advance_to(game.construction.sites[0].finish_native)

 # The legacy freight scenario covers two metal shipments from an accumulated stock.
 game.world.markets[0].supply.metals = 30
 var starting_line_checkpoint: Dictionary = game.construction.snapshot()
 var earth_metal := stock("earth", "metals")
 var moon_metal := stock("luna", "metals")
 game._send_freighter()
 game._send_freighter()
 var outbound := freight()
 check(outbound.get("order", {}).get("resource") == "metals", "Missing outbound cargo")
 check(stock("earth", "metals") == earth_metal - 10 and stock("luna", "metals") == moon_metal,
  "Outbound loading changed the warehouses incorrectly")
 if failed:
  quit(1)
  return
 game._step()
 var legacy_eta: float = outbound.departure + Calendar.days_to_native(12.0)
 load_v2_freight({"location": "transit", "metals": 10,
  "departure": outbound.departure, "arrival": legacy_eta})
 check(freight().order == outbound.order and absf(freight().arrival - legacy_eta) < 0.000001
  and freight().trajectory.legacy, "Migration changed outbound cargo or timing")
 advance_to(legacy_eta)
 check(freight() == {"location": "luna"} and stock("luna", "metals") == moon_metal + 10,
  "Outbound unloading must credit ten metals once")
 load_v2_freight({"location": "luna-colony", "metals": 0})
 check(freight() == {"location": "luna"} and stock("luna", "metals") == moon_metal + 10,
  "Migration repeated a completed delivery")

 select_body("earth")
 game._open_manual_freight()
 check(stock("luna", "ore") == 0 and not game.construction.freight_block_reason(game.selected).is_empty() and
  game.manual_preview.text.contains("0 руды · требуется 10"), "Shortage must show available and required ore")
 game.manual_freight_dialog.hide()
 for i in range(200):
  if stock("luna", "ore") >= 10:
   break
  game._step()
 var moon_ore := stock("luna", "ore")
 var earth_ore := stock("earth", "ore")
 check(moon_ore >= 10 and game.construction.freight_block_reason(game.selected).is_empty(), "Lunar mine must supply the return flight")
 if failed:
  DirAccess.remove_absolute(Lab.USER_SAVE)
  quit(1)
  return
 game._send_freighter()
 game._send_freighter()
 var inbound := freight()
 check(inbound.get("order", {}) ==
  {"source": "luna", "destination": "earth", "resource": "ore", "amount": 10}, "Wrong return cargo")
 check(game.native_view._freight == inbound and game.details.text.contains("Грузовик → Земля · 10 руды"),
  "Map and panel must show the return cargo and destination")
 check(stock("luna", "ore") == moon_ore - 10 and stock("earth", "ore") == earth_ore,
  "Return loading changed the warehouses incorrectly")
 game._step()
 var saved_time: float = game.native_time
 press("Сохранить")
 await fresh_scene()
 press("Загрузить")
 press("Загрузить")
 check(game.paused and game.native_time == saved_time and freight().get("arrival") == inbound.get("arrival")
  and freight().get("order", {}).get("amount") == 10, "Loading must preserve the flight and ETA")
 check(stock("luna", "ore") == moon_ore - 10 and stock("earth", "ore") == earth_ore,
  "Reloading duplicated or lost ore")
 check(not game.construction.freight_block_reason(game.selected).is_empty() and game.native_view._freight == freight(),
  "Loaded return flight must remain in flight on the map and block dispatch")
 advance_to(inbound.arrival)
 game._step()
 check(freight() == {"location": "earth"} and stock("earth", "ore") == earth_ore + 10 and
  stock("luna", "ore") == moon_ore - 10, "Return landing must empty the hold and unload once")
 press("Сохранить")
 press("Загрузить")
 game._step()
 check(stock("earth", "ore") == earth_ore + 10, "Reload after landing credited ore twice")

 select_body("luna")
 game._send_freighter()
 check(freight().get("order", {}).get("resource") == "metals" and
  stock("earth", "metals") == earth_metal - 20 and stock("luna", "metals") == moon_metal + 10,
  "The same freighter must be ready for another outbound order")
 if not failed:
  var legacy: Dictionary = game.construction.snapshot()
  legacy.version = 3
  legacy.erase("freight_line")
  press("Включить линию")
  load_checkpoint(legacy)
  check(not game.construction.freight_line().enabled and absf(freight().arrival - legacy.freighter.arrival) < 0.000001,
   "Version 3 must keep the active trip and disable the line")
  load_checkpoint(starting_line_checkpoint)
  await check_line()
 DirAccess.remove_absolute(Lab.USER_SAVE)
 if not failed:
  print("SOL_FREIGHT_ROUND_TRIP_PASS")
 quit(1 if failed else 0)

func configure_line(food_reserve: float) -> void:
 press("Настройка линии")
 check(game.freight_line_dialog.visible, "Line settings must open from the freight panel")
 var outbound: Dictionary = game.freight_line_fields.luna
 var inbound: Dictionary = game.freight_line_fields.earth
 var resource: OptionButton = outbound.resource
 for i in resource.item_count:
  if resource.get_item_metadata(i) == "food":
   resource.select(i)
 outbound.amount.get_line_edit().text = "6"
 outbound.reserve.get_line_edit().text = str(food_reserve)
 inbound.amount.get_line_edit().text = "10"
 inbound.reserve.get_line_edit().text = "5"
 game.freight_line_dialog.get_ok_button().pressed.emit()
 check(game.construction.freight_line().legs.luna ==
  {"resource": "food", "amount": 6, "reserve": food_reserve}, "Line settings must apply")

func meals_since(body: String, previous_deadline: float) -> int:
 var deadline: float = game.construction.meal_cycles[body].facility.next_meal_native
 return roundi(Calendar.native_to_days(deadline - previous_deadline) / 30.0)

func check_line() -> void:
 var initial_food := stock("earth", "food")
 var initial_moon_food := stock("luna", "food")
 var earth_deadline: float = game.construction.meal_cycles.earth.facility.next_meal_native
 var moon_deadline: float = game.construction.meal_cycles.luna.facility.next_meal_native
 var initial_earth_ore := stock("earth", "ore")
 var defaults: Dictionary = game.construction.freight_line()
 check(not defaults.enabled and defaults.legs.luna ==
  {"resource": "metals", "amount": 10, "reserve": 0.0} and defaults.legs.earth ==
  {"resource": "ore", "amount": 10, "reserve": 0.0}, "Default line must match the manual round trip")
 configure_line(initial_food - 5)
 press("Включить линию")
 game._send_freighter()
 game._step()
 check(stock("earth", "food") == initial_food + meals_since("earth", earth_deadline) * 6 and
  freight() == {"location": "earth"},
  "Line must respect the reserve and a manual order must not bypass it")
 configure_line(initial_food - 18)
 game._step()
 var outbound := freight()
 check(outbound.get("order", {}).get("resource") == "food" and outbound.order.amount == 6 and
  stock("earth", "food") == initial_food - 6 + meals_since("earth", earth_deadline) * 6,
  "Configured food cargo must depart without a manual order")
 if failed:
  return
 advance_to(outbound.arrival)
 check(freight() == {"location": "luna"} and stock("luna", "food") == initial_moon_food + 6 - meals_since("luna", moon_deadline) * 2 and
  game.details.text.contains("Луна") and game.details.text.contains("требуется 15"),
  "The freighter must unload and show the ore requirement while waiting")
 for round_number in [1, 2]:
  var mined_ore: float = 0
  for i in range(200):
   mined_ore = stock("luna", "ore")
   game._step()
   if freight().get("location") == "transit":
    break
  var inbound := freight()
  check(inbound.get("order", {}).get("resource") == "ore" and inbound.order.amount == 10 and
   mined_ore < 15 and stock("luna", "ore") >= 5 and
   stock("earth", "ore") == initial_earth_ore + (round_number - 1) * 10,
   "Real mining must release a full ore shipment without touching the five-unit reserve")
  if failed:
   return
  var ore_after_loading := stock("luna", "ore")
  if round_number == 1:
   var line: Dictionary = game.construction.freight_line()
   press("Сохранить")
   await fresh_scene()
   press("Загрузить")
   check(game.construction.freight_line() == line and freight().order == inbound.order and
    absf(freight().arrival - inbound.arrival) < 0.000001 and
    stock("luna", "ore") == ore_after_loading, "Reload must preserve the line and cargo without reloading")
  else:
   press("Отключить линию")
   check(freight() == inbound, "Disabling the line must leave the active order intact")
  advance_to(inbound.arrival)
  check(stock("earth", "ore") == initial_earth_ore + round_number * 10 and
   stock("luna", "ore") == ore_after_loading, "Each circle must deliver exactly ten ore")
  if round_number == 1:
   outbound = freight()
   check(outbound.get("order", {}).get("resource") == "food" and stock("earth", "food") == initial_food - 12 + meals_since("earth", earth_deadline) * 6,
    "Unloading at Earth must start the next outbound trip automatically")
   if failed:
    return
   advance_to(outbound.arrival)
   check(freight() == {"location": "luna"} and stock("luna", "food") == initial_moon_food + 12 - meals_since("luna", moon_deadline) * 2,
    "The second outbound trip must deliver another six food")
 game._step()
 check(freight() == {"location": "earth"} and not game.construction.freight_line().enabled and
  stock("earth", "food") == initial_food - 12 + meals_since("earth", earth_deadline) * 6, "Disabling in flight must leave the emptied ship at Earth")
 select_body("luna")
 game._send_freighter()
 check(freight().get("order", {}).get("resource") == "metals", "Manual dispatch must work again")
