extends SceneTree
## A single ordinary campaign. Only the calendar is advanced between actions.
const MAIN = preload("res://scenes/main.tscn")

func _initialize() -> void:
 call_deferred("run")

func advance(game: Control, time: float) -> void:
 game.native_time = time
 game._advance_construction()
 game._update_native_map()
 game._show_selected()

func capture(id: String) -> void:
 var folder := OS.get_environment("SOL_SUPPLY_SCREENSHOTS")
 if folder.is_empty() or DisplayServer.get_name() == "headless":
  return
 await process_frame
 await RenderingServer.frame_post_draw
 assert(root.get_texture().get_image().save_png(folder.path_join(id + ".png")) == OK)

func fit(game: Control) -> void:
 await process_frame
 var panel: Rect2 = game.sidebar.get_global_rect()
 assert(panel.end.x <= 1366.5 and panel.end.y <= 768.5)
 assert(game.colony_stock_panel.is_visible_in_tree())
 assert(game.colony_panel.scroll.size.y >= 150)

func run() -> void:
 root.size = Vector2i(1366, 768)
 var game = MAIN.instantiate()
 root.add_child(game)
 await process_frame
 game._pause()
 var sim = game.construction
 await fit(game)
 await capture("01-earth")
 game._native_body_selected({"id": "luna"})
 game.colony_button.pressed.emit()
 advance(game, sim.expedition.ship.arrival)
 game._open_build()
 for kind in ["spaceport", "refinery"]:
  game.browser.build_controls[kind].button.pressed.emit()
  var plot: String = game.browser.placement_options[0].id
  game.native_view.choose_placement(plot)
  game.browser.select_placement(plot)
  game.browser.placement_confirm.pressed.emit()
  assert(game.colony_stock_panel.is_visible_in_tree())
 advance(game, sim.sites.back().finish_native)
 game._close_browser()

 game.colony_stock_panel.resource_buttons.ore.pressed.emit()
 assert(game.stock_links.get_child_count() == 1)
 assert(game.stock_links.get_child(0).text.contains("Перерабатывающий"))
 game.stock_flight.pressed.emit()
 assert(game.manual_destination.get_selected_metadata() == "luna")
 assert(game.manual_resource.get_selected_metadata() == "ore")
 game.manual_amount.value = 10
 assert(not game.manual_freight_dialog.get_ok_button().disabled)
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 advance(game, sim.freight_status().load_due)
 advance(game, sim.freight_status().arrival)
 game._open_manual_freight()
 game.manual_empty.button_pressed = true
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 assert(sim.freight_status().order.amount == 0)
 advance(game, sim.freight_status().arrival)

 var plant: String
 for item in game.colony_panel.built_facilities:
  if item.type == "refinery":
   plant = item.id
 advance(game, sim.production_details(plant).next_native)
 game.colony_panel.built_buttons[plant].pressed.emit()
 assert(game.colony_panel.detail_description.text.contains("не хватает 1 топлива"))
 await fit(game)
 game.native_view.focus_body("luna")
 await create_timer(0.5).timeout
 await capture("02-luna-shortage")
 game.colony_stock_panel.resource_buttons.fuel.pressed.emit()
 assert(game.stock_totals.text.contains("Доступно: 0"))
 assert(game.stock_links.get_child_count() == 1)
 await capture("03-luna-fuel")
 game.stock_flight.pressed.emit()
 assert(game.manual_destination.get_selected_metadata() == "luna")
 assert(game.manual_resource.get_selected_metadata() == "fuel")
 assert(game.manual_amount.value == 1)
 assert(not game.manual_freight_dialog.get_ok_button().disabled)
 await process_frame
 assert(game.manual_freight_dialog.size.y <= 650)
 await capture("04-freight")
 game.manual_freight_dialog.confirmed.emit()
 game.manual_freight_dialog.hide()
 assert(sim.freight_status().order.resource == "fuel")
 assert(sim.colony_inventory("luna").supply.get("fuel", 0) == 0)
 assert(game.colony_panel.detail_description.text.contains("Грузовик 1 · в пути"))
 advance(game, sim.freight_status().arrival)
 assert(sim.colony_inventory("luna").supply.fuel == 1)
 assert(game.colony_panel.detail_description.text.contains("ждёт следующего цикла"))
 advance(game, sim.production_details(plant).next_native)
 assert(sim.production_details(plant).last_present)
 assert(sim.colony_inventory("luna").supply.fuel == 0)
 assert(is_equal_approx(sim.colony_inventory("luna").movement.fuel.consumed, 1.0))
 assert(game.colony_panel.detail_description.text.contains("Фактическая последняя партия"))
 await capture("05-luna-resumed")
 assert(sim.configure_freight_line({
  "luna": {"resource": "medical", "amount": 9, "reserve": 99, "policy": "partial"},
  "earth": {"resource": "electronics", "amount": 10, "reserve": 99, "policy": "partial"}}))
 sim.set_freight_line_enabled(true)
 game._show_selected()
 game._open_colony_logistics()
 await fit(game)
 await capture("06-luna-line")
 print("SOL_LUNAR_SUPPLY_UI_PASS")
 quit()
