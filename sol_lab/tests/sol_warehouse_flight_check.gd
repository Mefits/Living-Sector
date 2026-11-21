extends SceneTree

const Main = preload("res://scenes/main.tscn")

func _initialize() -> void:
 run.call_deferred()

func advance(game: Control, time: float) -> void:
 game.native_time = time
 game._advance_construction()
 game._update_native_map()
 game._show_selected()

func capture(name: String) -> void:
 var folder := OS.get_environment("SOL_STOCK_CAPTURE")
 if folder.is_empty() or DisplayServer.get_name() == "headless":
  return
 await process_frame
 await RenderingServer.frame_post_draw
 assert(root.get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK)

func run() -> void:
 root.size = Vector2i(1366, 768)
 var game = Main.instantiate()
 root.add_child(game)
 await process_frame
 game._pause()
 var sim = game.construction
 var stock = game.colony_stock_panel
 assert(stock.heading.text.ends_with("Земля"))
 game._native_body_selected({"id":"mars"})
 assert(not stock.visible)
 game._native_body_selected({"id":"luna"})
 game.colony_button.pressed.emit()
 game.expedition_dialog.confirmed.emit()
 game.expedition_dialog.hide()
 advance(game, sim.expedition.ship.arrival)
 game._open_build()
 for kind in ["spaceport", "mining_rig"]:
  game.browser.build_controls[kind].button.pressed.emit()
  game._placement_chosen(game.browser.placement_options[0].id)
 assert(stock.is_visible_in_tree())
 advance(game, sim.sites.back().finish_native)
 game._close_browser()
 game.native_view.focus_body("luna")
 await create_timer(0.6).timeout
 game._open_colony_logistics()
 game._open_manual_freight()
 await process_frame
 assert(stock.is_visible_in_tree() and game.manual_freight_dialog.position.x + game.manual_freight_dialog.size.x <= game.sidebar.position.x)
 for index in game.manual_resource.item_count:
  if game.manual_resource.get_item_metadata(index) == "food":
   game.manual_resource.select(index)
 game.manual_amount.value = 10
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 var eta: float = sim.freight_status().arrival
 advance(game, eta - 0.001)
 var before: Dictionary = sim.colony_inventory("luna")
 assert(before.incoming.size() == 1 and before.supply.food == 8)
 assert(before.movement.food.out == 2)
 assert(stock.arrivals.get_child(0).text.contains("В пути: +10 еды"))
 await capture("Luna-Food-In-Transit")
 advance(game, eta)
 var after: Dictionary = sim.colony_inventory("luna")
 assert(after.supply.food == before.supply.food + 10 and after.incoming.is_empty())
 assert(after.movement.food["in"] - after.movement.food.out == 8)
 await capture("Luna-Food-Delivered")
 var mine: Dictionary = {}
 for building in game.colony_panel.built_facilities:
  if building.type == "mining_rig":
   mine = building
 advance(game, mine.next_batch_native)
 var produced: Dictionary = sim.colony_inventory("luna")
 assert(produced.movement.ore["in"] == produced.supply.ore and produced.supply.ore > 0)
 game.colony_panel.built_buttons[mine.id].pressed.emit()
 assert(stock.is_visible_in_tree() and stock.heading.text.ends_with("Луна"))
 var lunar_text: String = stock.amount_labels.food.text
 game._native_body_selected({"id":"earth"})
 assert(stock.heading.text.ends_with("Земля"))
 game._native_body_selected({"id":"luna"})
 assert(stock.heading.text.ends_with("Луна") and stock.amount_labels.food.text == lunar_text)
 print("SOL_WAREHOUSE_FLIGHT_PASS")
 quit()
